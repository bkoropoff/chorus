-- Option Support
local M = {}
local util = require 'chorus._util'

--- @class chorus.opt.Method Option method
--- @field set? any Just set the option
--- @field prepend? any Prepend to the option
--- @field append? any Append to the option
--- @field remove? any Remove from the option

--- @class chorus.opt.Spec Option spec
--- @field buffer? boolean | integer Set options locally in the given buffer;
--- `0` or `true` means the current buffer.  This mode uses `vim.bo` and doesn't
--- support methods as detailed below.  Mutually exclusive with other modes.
--- @field window? boolean | integer Set options locally in the given window;
--- `0` or `true` means the current window.  This mode uses `vim.wo` and doesn't
--- support methods as detailed below.  Mutually exclusive with other modes.
--- @field scope? "local" | "global" Set global-local options locally or globally
--- instead of both.  This mode uses `vim.opt_{local,global}` and does support
--- methods as detailed below.  Mutually exclusive with other modes.
--- @field [string] any | chorus.opt.Method Options
--- 1. `<key> = <value>`: Performs `vim.opt{,_local,_global}.<key> = <value>`
--- 2. `<key> = { <method> = { <value> ...}, ... }`: Performs
--- `vim.opt{,_local,_global}.<key>:<method>{ <value> ... }...`
--- 3. `<key> = { set = <value>, ...}`: Performs `vim.opt{,_local,_global}.<key> = <value>`
--- (alternate syntax)

local keywords = {
  buffer = true,
  window = true,
  scope = true
}

local special_map = {
  set = function(k, s, v) s[k] = v end,
  prepend = function(k, s, v) s[k]:prepend(v) end,
  append = function(k, s, v) s[k]:append(v) end,
  remove = function(k, s, v) s[k]:remove(v) end
}

local scope_map = {
  ["local"] = vim.opt_local,
  ["global"] = vim.opt_global,
  ["default"] = vim.opt
}

--- Set options
---
--- Also available by invoking [`chorus.opt`](./chorus.opt) as a function
--- (or just `opt` when using the default prelude)
---
--- @param opts chorus.opt.Spec Options to set
function M.set(opts)
  local window = opts.window
  local scope = opts.scope
  local buffer = opts.buffer
  if (window and scope) or (window and buffer) or (scope and buffer) then
    error("opt.set: multiple modes specified")
  end

  if buffer == true or buffer == 0 then
    buffer = vim.api.nvim_get_current_buf()
  end

  if buffer then
    for k, v in pairs(opts) do
      vim.bo[k] = v
    end
    return
  end

  if window == true or window == 0 then
    window = vim.api.nvim_get_current_buf()
  end

  if window then
    for k, v in pairs(opts) do
      vim.wo[k] = v
    end
    return
  end

  local so = scope_map[scope or "default"]

  for k, v in pairs(opts) do
    if keywords[k] then
      goto next
    end
    local is_special = false
    if type(v) == 'table' then
      --- @cast v table
      local m = util.copy(v)
      for sk, method in pairs(special_map) do
        local sv = m[sk]
        if sv ~= nil then
          method(k, so, sv)
          is_special = true
        end
      end
    end
    if not is_special then
      so[k] = v
    end
    ::next::
  end
end

local mt = {}

function mt:__call(spec)
  return M.set(spec)
end

setmetatable(M, mt)
return M
