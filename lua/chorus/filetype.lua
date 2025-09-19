--- Filetype Helper
M = {}

local cspec = require 'chorus._spec'

--- Filetype options
--- @class chorus.filetype.Opts
--- @field treesitter? boolean | string | chorus.treesitter.Parsers Configure treesitter
--- 1. `false`: No (default)
--- 2. `true`: Install and enable the default parser for the filetype
--- 2. `"<parser>"`: Install and enable the named parser
--- 3. `{ ... }`: Install parsers and options as by [`chorus.treesitter.enable`](./chorus.treesitter.enable)
--- @field lsp? chorus.lsp.Config

local opts_spec = cspec.compile {
  treesitter = {'boolean', 'string', 'table'},
  lsp = 'table',
}

--- Filetype spec
--- @class chorus.filetype.Spec
--- @field treesitter? boolean | chorus.treesitter.Opts Default to enabling treesitter for filetypes
--- (or specify precise options).  Default: `false`
--- @field [string] chorus.filetype.Opts Filetype and options
--- @field [integer] string Filetype (default options)

local ft_spec = cspec.compile {
  treesitter = { 'boolean', 'table' },
  [cspec.ARGS] = 'string',
  [cspec.CONFIG] = {
    allow_unknown_options = true
  }
}

--- Configure filetypes
---
--- Also available by invoking [`chorus.filetype`](./chorus.filetype) (or
--- `filetype` if using the default prelude).
---
--- The current configuration source is suspended.
---
--- On the first `FileType` event for each specified filetype:
--- - Treesitter parsers will be installed if needed and configured in `spec`
--- - LSP will be set up if configured in `spec`
--- - The current configuration source will be resumed (if still suspended),
---   and its completion awaited.
---
--- @async
--- @param spec chorus.filetype.Spec | string Filetype specification
function M.setup(spec)
  local async = require 'chorus._async'
  local task = async.current()

  if not task then
    error("filetype.setup: must be called from a configuration source")
  end

  if type(spec) == 'string' then
    spec = { spec } --[[@as chorus.filetype.Spec]]
  end

  local opts, args, rest = ft_spec:parse(spec)

  local fts = {}
  for k, v in pairs(rest) do
    fts[k] = opts_spec:parse(v, opts)
  end
  for _, ft in ipairs(args) do
    fts[ft] = opts
  end

  local cap = task.name .. '.filetype'

  local chorus = require 'chorus'

  for ft, subopts in pairs(fts) do
    chorus.fork(function()
      chorus.defer {
        event = 'FileType',
        pattern = ft
      }

      if subopts.treesitter then
        local ts = subopts.treesitter
        if type(ts) == 'string' then
          ts = { ts }
        elseif type(ts) == 'boolean' then
          ts = {}
        end
        if type(opts.treesitter) == 'table' then
          ts = vim.tbl_extend('force', opts.treesitter, ts)
        end
        chorus.treesitter { [ft] = ts }
      end

      if subopts.lsp then
        chorus.lsp(subopts.lsp)
      end

      chorus.need(cap)
    end)
  end

  chorus.provide { cap, lazy = true }
end

local mt = {}

--- @async
function mt:__call(patterns)
  return M.setup(patterns)
end

setmetatable(M, mt)
return M
