local M = {}

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

--- @param tbl table
--- @return table
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
    function() return { func() } end,
    function(err)
      return { err or "unknown", debug.traceback() }
    end
  )
  return ok, unpack(res)
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

return M
