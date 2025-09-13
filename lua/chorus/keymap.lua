--- Keymap Support
local M = {}
local cspec = require 'chorus._spec'
local util = require 'chorus._util'

--- Indicates that a mapping should be deleted in a keymap spec
--- @class chorus.keymap.DELETE
M.DELETE = {}

--- Left-hand side in a keymap spec
---
--- Several formats are possible:
---
--- 1. `["<mode> <keys>"]`: Mode (or modes) and key sequence together
--- 2. `["<mode>"]`: Only a mode (or modes); nested tables specifies key sequences only
--- 3. `["<keys>"]`: Only a key sequence; mode must be specified in a parent table
--- 4. `[{ "<lhs>", ... }]`: Multiple left-hand sides with a common right-hand side
---
--- Modes have the following formats:
--- 1. `<m1>...`: One or more modes, e.g. `vn`, but not abbreviations
--- 2. `ca`: Command mode abbreviation
--- 3. `ia`: Insert mode abbreviation
--- 3. `!a`: Both abbreviation modes
---
--- @alias chorus.keymap.Lhs string | string[]

--- Action in a keymap spec
---
--- 1. `"<k1><k2>..."`: A key sequence
--- 2. `function() ... end`: A callback function (which returns a string if `expr = true`)
---
--- @alias chorus.keymap.Action
--- | string
--- | fun()
--- | fun():string

--- Right-hand side in a keymap spec
---
--- 1. [An action](./chorus.keymap.Action)
--- 3. [`DELETE`](./chorus.keymap.DELETE): Indicates mapping should be deleted if it exists
--- 4. `{ <action>, <option> = <value> ... }`: An action plus options
--- 5. [A nested spec](./chorus.keymap.Spec) which inherits modes and options and
--- any key sequence as a prefix
--- @alias chorus.keymap.Rhs
--- | chorus.keymap.Action
--- | { [1]: chorus.keymap.Action, [string]: any }
--- | chorus.keymap.DELETE
--- | chorus.keymap.Spec

--- Keymap spec
---
--- Describes a set of keymaps
---
--- @class chorus.keymap.Spec
--- @field buffer? boolean | integer Set mapping only in provided buffer; `0` or `true` mean
--- current buffer.  Default: `false`
--- @field expr? boolean Expression mapping (function returns a character
--- sequence to further interpret).  Default: `false`
--- @field noremap? boolean Non-recursive mapping.  Default: `true`
--- @field nowait? boolean Don't wait for additional keystrokes.  Default: `false`
--- @field script? boolean Script-local mapping.  Of limited value in Lua.  Default: `false`
--- @field silent? boolean Mapping won't be echoed on command line.  Default: `false`
--- @field unique? boolean Fail if the mapping already exists.  Default: `false`
--- @field replace_keycodes? boolean Replace keycode escapes in return value of `expr`
--- mappings.  Default: `true`
--- @field [chorus.keymap.Lhs] chorus.keymap.Rhs Key mapping

--- Mapping identifier
---
--- A token that can be used to delete a prior mapping
--- @class chorus.keymap.ID

--- Keymap arguments
---
--- This table contains additional information about the currently executing
--- mapping that may be useful.  It is not passed directly to the callback to
--- avoid diverging from the function signature used by `vim.keymap.set` or any
--- future extensions it may introduce.
---
--- @class chorus.keymap.args
--- @field expr? boolean Expression mapping
--- @field noremap? boolean Non-recursive mapping
--- @field nowait? boolean No-wait mapping
--- @field script? boolean Script-local mapping
--- @field silent? boolean Silent mapping
--- @field unique? boolean Unique mapping
--- @field replace_keycodes? boolean Replace keycodes in return value
--- @field lhs string Left-hand side of mapping
M.args = {
  lhs = '',
}

local option_spec = cspec.compile {
  buffer = cspec.buffer,
  expr = 'boolean',
  noremap = 'boolean',
  remap = 'boolean',
  nowait = 'boolean',
  wait = 'boolean',
  script = 'boolean',
  silent = 'boolean',
  unique = 'boolean',
  replace_keycodes = 'boolean',
  [cspec.CONFIG] = {
    allow_unknown_options = true
  }
}

local rhs_spec = cspec.compile {
  {'string', 'callable'},
  [cspec.CONFIG] = {
    inherit = option_spec,
    allow_unknown_options = false
  }
}

local function parse_options(compiled, tbl, defaults)
  local opts, args, rest = compiled:parse(tbl, defaults)
  if opts.expr and opts.replace_keycodes == nil then
    opts.replace_keycodes = true
  end
  if opts.remap then
    opts.noremap = false
  end
  if opts.wait then
    opts.nowait = false
  end
  return opts, args, rest
end

local function parse_mode(mode)
  if type(mode) == 'table' then
    return mode
  elseif mode == "ca" or mode == "ia" or mode == "!a" then
    return {mode}
  end
  return vim.iter(mode:gmatch(".")):totable()
end

local function parse_lhs(obj, mode, prefix)
  if type(obj) == 'table' then
    return mode, vim.tbl_map(function(lhs) return prefix .. lhs end, obj)
  end
  if type(obj) ~= 'string' then
    error("LHS is not a string: " .. vim.inspect(obj))
  end
  local lhs = nil
  local split = vim.split(obj, ' ')
  if #split == 1 then
    if mode == nil then
      mode = parse_mode(split[1])
    else
      lhs = split[1]
    end
  else
    if mode ~= nil then
      error("duplicate mode")
    end
    mode = parse_mode(split[1])
    lhs = split[2]
  end

  return mode, lhs and {prefix .. lhs}
end

local function apply(cfg, modes, prefix, defaults)
  local ids = {}
  local opts, _, rest = parse_options(option_spec, cfg, defaults)
  for k, rhs in pairs(rest) do
    local submodes, lhs = parse_lhs(k, modes, prefix)

    if lhs == nil then
      util.insert_all(ids, apply(rhs, submodes, prefix, opts))
      goto next
    end

    if rhs == M.DELETE then
      for _, sublhs in ipairs(lhs) do
        for _, mode in ipairs(modes) do
          local res, err = pcall(function()
            if opts.buffer ~= nil then
              vim.api.nvim_buf_del_keymap(opts.buffer, mode, sublhs)
            else
              vim.api.nvim_del_keymap(mode, sublhs)
            end
          end)
          if not res and type(err) == 'string' and not string.match(err, "E31: ") then
            error(err, 0)
          end
        end
      end
      goto next
    end

    if vim.is_callable(rhs) or type(rhs) ~= 'table' then
      rhs = { rhs }
    end
    if not rhs[1] then
      for _, sublhs in ipairs(lhs) do
        util.insert_all(ids, apply(rhs, submodes, sublhs, opts))
      end
      goto next
    end
    local subopts, args = parse_options(rhs_spec, rhs, opts)
    rhs = args[1]
    if rhs == nil then
      error("No RHS specified for mapping: " .. lhs)
    end

    local buffer = subopts.buffer
    local fopts = vim.tbl_extend('keep', subopts, {})
    subopts.buffer = nil
    subopts.remap = nil
    subopts.wait = nil

    for _, sublhs in ipairs(lhs) do
      local subrhs = rhs
      if vim.is_callable(subrhs) then
        local func = subrhs
        local fargs = vim.tbl_extend('force', fopts, { lhs = sublhs })
        subopts.callback = function()
          local old = M.args
          M.args = fargs
          local res = func()
          M.args = old
          return res
        end
        subrhs = ''
      end

      for _, mode in ipairs(submodes) do
        if buffer ~= nil then
          vim.api.nvim_buf_set_keymap(buffer, mode, sublhs, subrhs, subopts)
        else
          vim.api.nvim_set_keymap(mode, sublhs, subrhs, subopts)
        end
        table.insert(ids, {mode, sublhs, buffer == 0 and vim.api.nvim_get_current_buf() or buffer})
      end
    end
    ::next::
  end

  return ids
end

--- Set keymap
---
--- Also available by invoking [`chorus.keymap`](./chorus.keymap) as a function
--- (or just `keymap` when using the default prelude)
---
--- @param spec chorus.keymap.Spec Keymap spec
--- @return chorus.keymap.ID ... ids All created mappings
function M.set(spec)
  local defaults = { noremap = true }
  return unpack(apply(spec, nil, '', defaults))
end

--- Delete mappings
---
--- Deletes one or more mapping previously created with [`chorus.keymap[.set]`](./chorus.keymap.set)
--- @param ... chorus.keymap.ID Identifier mappings
function M.delete(...)
  for _, id in ipairs { ... } do
    local mode, lhs, buffer = unpack(id)
    if buffer then
      vim.api.nvim_buf_del_keymap(buffer, mode, lhs)
    else
      vim.api.nvim_del_keymap(mode, lhs)
    end
  end
end

local mt = {
  __call = function(_, spec) return M.set(spec) end
}

setmetatable(M, mt)

return M
