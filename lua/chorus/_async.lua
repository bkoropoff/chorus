local M = {}
local util = require 'chorus._util'

--- @type { [thread]: chorus.async.Task? }
local task_by_cr = {}

--- @return chorus.async.Task?
function M.current()
  return task_by_cr[coroutine.running()]
end

--- @enum chorus.async.State
M.State = {
  -- Runnable
  RUN = "run",
  -- Runnable and spinning
  SPIN = "spin",
  -- Runnable when idle
  IDLE = "idle",
  -- Waiting for operation (e.g. I/O)
  WAIT = "wait",
  -- Waiting for another task
  DEPEND = "depend",
  -- Detached (reactor should not wait for task)
  DETACH = "detach"
}

---@class chorus.async.Task: chorus.util.Object
---@field done boolean
---@field name string
---@field reactor chorus.async.Reactor
---@field _cr thread
---@field _pred fun():chorus.async.State
M.Task = util.class()

--- @class chorus.async.Opts
--- @field name string | nil
--- @field on_done fun(boolean, ...) | nil

--- @param func async fun(): any
--- @param opts? chorus.async.Opts
--- @return self
function M.Task:new(func, opts)
  opts = opts or {}
  local inst = setmetatable({}, self)
  inst._cr = coroutine.create(function()
    local ok, res, tb = util.tbcall(function() return { func() } end)
    inst.done = true
    task_by_cr[inst._cr] = nil
    if not ok then
      if opts.on_done then
        opts.on_done(ok, res, tb)
      end
      return ok, res, tb
    end
    if opts.on_done then
      opts.on_done(ok, unpack(res))
    end
    return ok, unpack(res)
  end)
  inst.name = opts.name or vim.inspect(func)
  inst._pred = function() return M.State.RUN end
  ---@type chorus.async.State
  task_by_cr[inst._cr] = inst
  return inst
end

--- @return chorus.async.State
function M.Task:state()
  return self._pred()
end

--- @async
--- @param pred fun():chorus.async.State
--- @return any ...
function M.pend(pred, ...)
  if pred() == M.State.RUN then
    return
  end
  local self = task_by_cr[coroutine.running()]
  if not self then
    error("chorus.async.pend: must be called from task")
  end
  self._pred = pred
  local ok, res = coroutine.yield(true, {...})
  if not ok then
    error(res, 0)
  end
  return unpack(res)
end

--- @return boolean ok
--- @return any res
--- @return string? tb
function M.Task:__call(...)
  local _, ok, res, tb = coroutine.resume(self._cr, true, {...})
  return ok, res, tb
end

--- @return boolean ok
--- @return any res
--- @return string? tb
function M.Task:error(err)
  local _, ok, res, tb = coroutine.resume(self._cr, false, err)
  return ok, res, tb
end

--- Run a function that spins with `coroutine.yield(message)`
--- @async
--- @param func function
--- @param name? string
--- @return any
function M.spin(func, name)
  local DONE = {}
  local task = task_by_cr[coroutine.running()] or error("chorus.async.spin: must be called by task")
  name = name or task.name
  local cr = coroutine.wrap(function() return DONE, func() end)
  while true do
    local status, res = cr()
    if status == DONE then
      return res
    elseif type(status) == 'string' then
      util.notify((name and (name .. ": ") or ""))
    end
    M.pend(function() return M.State.SPIN end)
  end
  return nil
end

---@class chorus.async.Reactor
---@field _runq { [chorus.async.Task]: chorus.async.State? }
---@field _pendq { [chorus.async.Task]: chorus.async.State? }
---@field _interval integer
---@field _spinning integer
---@field _ready integer
---@field _waiting integer
---@field _detached integer
---@field _pending { [chorus.async.State]: integer }
---@field _running boolean
M.Reactor = util.class()

--- @return self
function M.Reactor:new()
  return setmetatable({
    _runq = {},
    _pendq = {},
    _interval = 50,
    _spinning = 0,
    _ready = 0,
    _waiting = 0,
    _detached = 0,
    _running = false
  }, self)
end

--- @param task chorus.async.Task
--- @return chorus.async.State?
function M.Reactor:deschedule(task)
  local pstate = self._runq[task]
  self._runq[task] = nil
  if pstate then
    if pstate == M.State.SPIN then
      self._spinning = self._spinning - 1
    end
    self._ready = self._ready - 1
    return pstate
  end
  pstate = self._pendq[task]
  self._pendq[task] = nil
  if pstate == M.State.WAIT then
    self._waiting = self._waiting - 1
  elseif pstate == M.State.DETACH then
    self._detached = self._detached - 1
  end
  return pstate
end

--- @param task chorus.async.Task
--- @param state chorus.async.State
function M.Reactor:_schedule(task, state)
  self:deschedule(task)

  if state == M.State.SPIN or state == M.State.RUN then
    if state == M.State.SPIN then
      self._spinning = self._spinning + 1
    end
    self._ready = self._ready + 1
    self._runq[task] = state
  else
    if state == M.State.WAIT then
      self._waiting = self._waiting + 1
    elseif state == M.State.DETACH then
      self._detached = self._detached + 1
    end
    self._pendq[task] = state
  end
end

---@param task chorus.async.Task
function M.Reactor:schedule(task)
  return self:_schedule(task, task:state())
end

--- @param idle boolean
function M.Reactor:_reschedule(idle)
  local q = self._pendq
  self._pendq = {}
  for task, state in pairs(q) do
    --- @cast task chorus.async.Task
    --- @cast state chorus.async.State
    if state == M.State.WAIT then
      self._waiting = self._waiting - 1
    end

    if state == M.State.IDLE then
      state = idle and M.State.SPIN or M.State.IDLE
    else
      state = task:state()
    end
    self:_schedule(task, state)
  end
end

---@private
function M.Reactor:_runnable()
  self:_reschedule(false)
  if self._ready - self._spinning == 0 then
    -- Everything that is running is just spinning, so run idle tasks too
    self:_reschedule(true)
  end

  return self._ready + self._waiting > 0
end

---@private
function M.Reactor:_run()
  local runq = self._runq
  self._runq = {}

  for j, state in pairs(runq) do
    self._ready = self._ready - 1
    if state == M.State.SPIN then
      self._spinning = self._spinning - 1
    end
    local ok, res, tb = j()
    if not ok then
      util.notify_error(j.name .. ": " .. res, tb)
    end
    if not j.done then
      self:schedule(j)
    end
  end
end

--- @param tasks chorus.async.Task[]
function M.Reactor:drain(tasks)
  if M.current() then
    error("Attempt to drain reactor from within task")
  end

  local function done()
    return vim.iter(tasks):all(function(t) return t.done end)
  end

  if self._running then
    vim.wait(self._interval, function() return not self._running or done() end, self._interval)
  end

  self._running = true
  while not done() and self:_runnable() do
    self:_run()
    if self._spinning > 0 then
      vim.wait(self._interval, function() return false end, self._interval)
    end
  end

  for _, task in ipairs(tasks) do
    if not task.done and self:deschedule(task) ~= M.State.DETACH then
      local ok, res, tb = task:error("can't make progress")
      if not ok then
        util.notify_error(task.name .. ": " .. res, tb)
      end
    end
  end
  self._running = false
end

--- @param func async fun(): any
--- @param opts? chorus.async.Opts
--- @return chorus.async.Task
function M.Reactor:task(func, opts)
  return M.Task:new(func, opts)
end

return M
