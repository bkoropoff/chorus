-- Option Support
local M = {}
local util = require 'chorus._util'

--- @class chorus.opt.Method Option method
--- @field set? any Just set the option
--- @field prepend? any Prepend to the option
--- @field append? any Append to the option
--- @field remove? any Remove from the option

--- @class chorus.opt.Spec Option spec
--- @field scope? "default" | "local" | "global" | "buffer" | "window" Scope in which option should be set
--- `"buffer"` and `"window"` scopes don't support methods below other than `set`.
--- @field [string] any | chorus.opt.Method Options
--- 1. `<key> = <value>`: Performs `vim.<scope>.<key> = <value>`
--- 2. `<key> = { <method> = { <value> ...}, ... }`: Performs
--- `vim.<scope>.<key>:<method>{ <value> ... }...`
--- 3. `<key> = { set = <value>, ...}`: Performs `vim.<scope>.<key> = <value>`
--- (alternate syntax)

local keywords = {
  scope = true
}

local special_map = {
  set = function(k, s, v) s[k] = v end,
  prepend = function(k, s, v) s[k]:prepend(v) end,
  append = function(k, s, v) s[k]:append(v) end,
  remove = function(k, s, v) s[k]:remove(v) end
}

local scope_map = {
  ["default"] = vim.opt,
  ["local"] = vim.opt_local,
  ["global"] = vim.opt_global,
  ["buffer"] = vim.bo,
  ["window"] = vim.wo
}

--- Set options
---
--- Also available by invoking [`chorus.opt`](./chorus.opt) as a function
--- (or just `opt` when using the default prelude)
---
--- @param opts chorus.opt.Spec Options to set
function M.set(opts)
  local scope = scope_map[opts.scope or "default"]

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
          method(k, scope, sv)
          is_special = true
        end
      end
    end
    if not is_special then
      scope[k] = v
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
