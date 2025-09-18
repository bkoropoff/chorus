local M = {}

function M.pack(...)
  return { n = select('#', ...), ... }
end

function M.unpack(tbl)
  local n = tbl.n or #tbl
  return unpack(tbl, 1, n)
end

--- @class chorus.util.Object
M.Object = {}
M.Object.__index = M.Object

--- @param super chorus.util.Object?
function M.class(super)
  local mt = { __index = super or M.Object }
  local class = setmetatable({}, mt)
  class.__index = class
  return class
end

--- @param tbl table
--- @param array table
--- @return table
function M.insert_all(tbl, array)
  for _, v in ipairs(array) do
    table.insert(tbl, v)
  end
  return tbl
end

--- @generic T: table
--- @param tbl T
--- @return T
function M.copy(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    copy[k] = v
  end
  return copy
end

--- @param tbl table
--- @param ... any
--- @return table
function M.retract(tbl, ...)
  local copy = M.copy(tbl)
  for _, k in ipairs { ... } do
    copy[k] = nil
  end
  return copy
end

--- @sync
--- @param func sync fun():any
--- @return boolean ok
--- @return any ...
function M.tbcall(func)
  local ok, res = xpcall(
    function() return M.pack(func()) end,
    function(err)
      return { err or "unknown", debug.traceback() }
    end
  )
  return ok, M.unpack(res)
end

--- @param msg any
--- @param tb string | nil
function M.notify_error(msg, tb)
  local tbl = {{tostring(msg), "ErrorMsg"}}
  if tb then
    table.insert(tbl, {"\n"})
    table.insert(tbl, {tb})
  end
  vim.api.nvim_echo(tbl, true, {})
end

--- @param msg string
--- @param level vim.log.levels | nil
function M.notify(msg, level)
  return vim.notify(msg, level)
end

--- @class chorus.util.GUARD
--- @package
local GUARD = {}

--- @class chorus.util.Thunk<T>
--- @field package func fun(): T
--- @field package value T | chorus.util.GUARD
local Thunk = M.class()

--- @generic T
--- @param func fun(): T
--- @return chorus.util.Thunk<T>
function M.delay(func)
  return setmetatable({
    func = func,
    value = GUARD
  }, Thunk)
end

--- @generic T
--- @param thunk chorus.util.Thunk<T>
--- @return T
function M.force(thunk)
  if thunk.value == GUARD then
    thunk.value = M.pack(thunk.func())
  end
  return M.unpack(thunk.value)
end

--- @param key any
--- @return any
function Thunk:__index(key)
  return M.force(self)[key]
end

--- @param key any
--- @param value any
function Thunk:__newindex(key, value)
  M.force(self)[key] = value
end

--- @param ... any
--- @return any...
function Thunk:__call(...)
  local args = M.pack(...)
  -- Support indexing for method calls
  if args[1] == self then
    args[1] = M.force(self)
  end
  return M.force(self)(M.unpack(args))
end

return M
