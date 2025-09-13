--- LSP Support
local M = {}

--- LSP settings for a particular language server
---
--- See Neovim documentation for available settings
--- @class chorus.lsp.Subconfig: vim.lsp.Config
--- @field keymap? chorus.keymap.Spec Keymap to apply when this language server attaches to a buffer
--- @field inherit? boolean Inherit from global and base (nvim-lspconfig) settings (default `true`)

--- LSP settings for one or more languages
--- @class chorus.lsp.Config
--- @field global? chorus.lsp.Subconfig Common settings for all language servers configured by `chorus.lsp`
--- @field common? chorus.lsp.Subconfig Common settings for all language servers in this table
--- @field [string] chorus.lsp.Subconfig Settings for particular language servers

--- @param common? function | function[]
--- @param specific? function | function[]
--- @return function[]
local function chain(common, specific)
  return vim.iter { common, specific }:flatten():totable()
end

--- @param funcs? function[]
--- @return function?
local function combine(funcs)
  if not funcs or #funcs == 0 then
    return nil
  end
  return function(...)
    for _, func in ipairs(funcs) do
      func(...)
    end
  end
end

--- @param map chorus.keymap.Spec
--- @return fun(any, integer)
local function apply_keymap(map)
  return function(_, bufnr)
    require 'chorus.keymap'.set(
      vim.tbl_extend('keep', map, { buffer = bufnr }) --[[@as chorus.keymap.Spec]]
    )
  end
end

--- @type chorus.lsp.Subconfig
local global = {}
--- @type { [string]: chorus.lsp.Subconfig }
local specific = {}

--- @type string[]
local cb_names = {'before_init', 'on_attach', 'on_init', 'on_exit', 'on_error'}

--- @param final boolean
--- @param ... chorus.lsp.Subconfig
local function merge(final, ...)
  local cfgs = { ... }
  if final then
    local last = cfgs[#cfgs]
    if last and last.inherit == false then
      cfgs = {last}
      --- @cast cfgs chorus.lsp.Subconfig[]
    end
  end

  local merged = vim.tbl_deep_extend(
    'force', unpack(cfgs) --[[@as chorus.lsp.Subconfig]]
  )
  --- @cast merged chorus.lsp.Subconfig
  for _, name in ipairs(cb_names) do
    --- @type function[]?
    local cbs
    for _, src in ipairs(cfgs) do
      if name == 'on_attach' and src.keymap then
        cbs = chain(cbs, apply_keymap(src.keymap))
      end
      cbs = chain(cbs, src[name])
    end
    if final then
      merged[name] = combine(cbs)
    else
      merged[name] = cbs
    end
  end
  merged.keymap = nil
  if final then
    merged.inherit = nil
  end
  return merged
end

--- @param args vim.api.keyset.create_autocmd.callback_args
local function on_filetype(args)
  if not args.match or #args.match == 0 then
      return
  end

  local chorus = require 'chorus'
  if chorus.did_setup then
    -- Only do this if this module isn't being used a la carte
    chorus.setup( function()
        chorus { 'neovim/nvim-lspconfig' }
    end)
  end

  local cfgs = {}

  for k, v in pairs(specific) do
    local base = vim.lsp.config[k]
    local ftypes = base.filetypes or v.filetypes
    if vim.tbl_contains(ftypes, args.match) then
      local cfg = merge(true, base, global, v)
      if not cfg.root_dir and cfg.root_markers then
        cfg.root_dir = vim.fs.root(args.buf, cfg.root_markers)
      end
      cfgs[k] = cfg
    end
  end

  for k, v in pairs(cfgs) do
    vim.lsp.config[k] = v
    vim.lsp.start(v, { bufnr = args.buf })
  end
end

local did_fork = false

--- Configure LSP settings
---
--- Also available by invoking [`chorus.lsp`](./chorus.lsp) as a function (or
--- just `lsp` when using the default prelude).
---
--- May be called multiple times to configure different servers.  Providing the
--- same server or the `global` key more than once replaces the prior settings
--- for that key.
---
--- Base (nvim-lspconfig), global, common, and specific settings are merged (as
--- by `vim.tbl_deep_extend`) when applied. In addition, the following
--- callbacks are merged so that all versions from the mentioned sources are
--- run in order:
--- - `before_init`
--- - `on_attach` (including any `keymap`)
--- - `on_init`
--- - `on_exit`
--- - `on_error`
---
--- Merging can be disabled by setting `inherit = false` for a particular
--- language server.
---
--- @param config chorus.lsp.Config Configuration
function M.setup(config)
  require 'chorus.autocmd' {
    group = 'chorus.lsp.enable',
    event = 'FileType',
    desc = "Chorus LSP support",
    on_filetype
  }

  local common = config.common or {}
  global = merge(false, global, config.global or {})

  for k, v in pairs(config) do
    --- @cast k +string
    if k ~= 'common' and k ~= 'global' and k ~= 'keymap' then
      specific[k] = merge(false, common, v)
    end
  end

  vim.api.nvim_exec_autocmds("FileType", { group = "chorus.lsp.enable" })

  -- Ensure lspconfig is installed by a lazy task on flush
  if not did_fork then
    local chorus = require 'chorus'
    if chorus.in_setup then
      chorus.fork(function()
        chorus.lazy()
        chorus { 'neovim/nvim-lspconfig' }
      end)
      did_fork = true
    end
  end
end

local mt = {
  __call = function(_, tbl) M.setup(tbl) end
}

setmetatable(M, mt)
return M
