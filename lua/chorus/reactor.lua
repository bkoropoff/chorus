local M = {}
local util = require 'chorus.util'
local State = require 'chorus.job'.State

---@class chorus.reactor.Reactor: chorus.util.Object
---@field _runq chorus.job.Job[]
---@field _pendq chorus.job.Job[]
---@field _interval integer
---@field _spinning integer
---@field _pending { [chorus.job.State]: integer }
M.Reactor = util.class()

--- @return self
function M.Reactor:new()
  return setmetatable({
    _runq = {},
    _pendq = {},
    _interval = 50,
    _spinning = 0,
    _pending = {
      [State.DEPEND] = 0,
      [State.WAIT] = 0
    }
  }, self)
end

---@private
---@param job chorus.job.Job
---@param delta integer
function M.Reactor:_update_pending(job, delta)
  local state = job:state()
  self._pending[state] = self._pending[state] + delta
end

---@param job chorus.job.Job
function M.Reactor:schedule(job)
  if job:ready() then
    if job:state() == State.SPIN then
      self._spinning = self._spinning + 1
    end
    table.insert(self._runq, job)
  else
    self:_update_pending(job, 1)
    table.insert(self._pendq, job)
  end
end

---@private
function M.Reactor:_runnable()
  local pendq = self._pendq
  self._pendq = {}

  for _, job in ipairs(pendq) do
    self:_update_pending(job, -1)
    self:schedule(job)
  end

  return #self._runq + self._pending[State.WAIT] > 0
end

---@private
function M.Reactor:_run()
  local runq = self._runq
  self._runq = {}

  for _, job in ipairs(runq) do
    if job:state() == State.SPIN then
      self._spinning = self._spinning - 1
    end
    local ok, res, tb = job()
    if not ok then
      util.notify_error(job.name .. ": " .. res, tb)
    end
    if not job.done then
      self:schedule(job)
    end
  end
end

function M.Reactor:drain()
  while self:_runnable() do
    self:_run()
    if self._spinning > 0 then
      vim.wait(self._interval, function() return false end, self._interval)
    end
  end

  for _, job in ipairs(self._pendq) do
    local ok, res, tb = job:error("can't make progress")
    if not ok then
      util.notify_error(job.name .. ": " .. res, tb)
    end
  end
  self._pendq = {}
end

return M
