local M = {}
local util = require 'chorus.util'

--- @class chorus.opt.Method Option method
--- @field set? any Just sets the option
--- @field prepend? any Prepends to the option
--- @field append? any Append to the option
--- @field remove? any Removes from the option

--- @class chorus.opt.Spec Option spec
--- @field buffer? boolean | integer Set options locally in the given buffer;
--- `0` or `true` means the current buffer.  This mode uses `vim.bo` and doesn't
--- support methods as detailed below.
--- @field [string] any | chorus.opt.Method Options settings
--- 1. `<key> = <value>`: Performs `vim.opt.<key> = <value>`
--- 2. `<key> = { <method> = { <value> ...}, ... }`: Performs
--- `vim.opt.<key>:<method>{ <value> ... }...` (multiple methods possible at once)

local special_map = {
  set = function(k, _, v) vim.opt[k] = v end,
  prepend = function(_, o, v) o:prepend(v) end,
  append = function(_, o, v) o:append(v) end,
  remove = function(_, o, v) o:remove(v) end
}

--- Set options
---
--- Also available by invoking the [`opt`](chorus.opt) module as a function.
---
--- @param opts chorus.opt.Spec Options to set
function M.set(opts) 
  local buffer = opts.buffer
  if buffer == 'true' or 'buffer' == 0 then
    buffer = vim.api.nvim_get_current_buf()
  end

  if buffer then
    for k, v in pairs(opts) do
      vim.bo[k] = v
    end
    return
  end

  for k, v in pairs(opts) do
    local o = vim.opt[k]
    local is_special = false
    if type(v) == 'table' then
      --- @cast v table
      local m = util.copy(v)
      for sk, method in pairs(special_map) do
        local sv = m[sk]
        if sv ~= nil then
          method(k, o, sv)
          v[sk] = nil
          is_special = true
        end
      end
    end
    if not is_special then
      vim.opt[k] = v
    end
  end
end

local mt = {}

function mt:__call(spec)
  return M.set(spec)
end

setmetatable(M, mt)
return M
