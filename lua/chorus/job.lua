local M = {}
local util = require 'chorus.util'

local jobs = {}

--- @enum chorus.job.State
M.State = {
  RUN = "run",
  WAIT = "wait",
  DEPEND = "depend",
  SPIN = "spin",
}

---@enum chorus.job.PendKind
M.PendKind = {
  WAIT = M.State.WAIT,
  DEPEND = M.State.DEPEND,
  SPIN = M.State.SPIN
}

---@class chorus.job.Job: chorus.util.Object
---@field done boolean
---@field name string
---@field _cr thread
---@field _pred fun():boolean
---@field _pend chorus.job.PendKind
M.Job = util.class()

--- @class chorus.job.Opts
--- @field name string | nil
--- @field on_done fun(boolean, ...) | nil

--- @param func async fun(): any
--- @param opts? chorus.job.Opts
--- @return self
function M.Job:new(func, opts)
  opts = opts or {}
  local inst = setmetatable({}, self)
  inst._cr = coroutine.create(function()
    local ok, res, tb = util.tbcall(function() return { func() } end)
    inst.done = true
    jobs[inst._cr] = nil
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
  inst._pred = function() return true end
  ---@type chorus.job.State
  inst._pend = M.State.WAIT
  jobs[inst._cr] = inst
  return inst
end

function M.Job:ready()
  return self._pred()
end

--- @return chorus.job.State
function M.Job:state()
  return coroutine.running() == self._cr and M.State.RUN or
      --- @as chorus.job.State
      self._pend
end

--- @async
--- @param kind chorus.job.PendKind
--- @param pred fun():boolean
--- @return any ...
function M.pend(kind, pred, ...)
  local self = jobs[coroutine.running()]
  self._pred = pred
  self._pend = kind
  local ok, res = coroutine.yield(true, {...})
  if not ok then
    error(res, 0)
  end
  return unpack(res)
end

--- @return boolean ok
--- @return any res
--- @return string|nil tb
function M.Job:__call(...)
  local _, ok, res, tb = coroutine.resume(self._cr, true, {...})
  return ok, res, tb
end

--- @return boolean ok
--- @return any res
--- @return string|nil tb
function M.Job:error(err)
  local _, ok, res, tb = coroutine.resume(self._cr, false, err)
  return ok, res, tb
end

--- @class chorus.job.Spin: chorus.job.Job
---
--- A Job subclass that expects the main function to just spin calling
--- `coroutine.yield` with a status string, compatible with lazy.nvim's `build
--- = function() ... end` mechanism
M.Spin = util.class(M.Job)

--- @return self
function M.Spin:new(func, opts)
  return M.Job.new(self, func, opts)
end

function M.Spin:__call()
  local ok, res, tb = coroutine.resume(self._cr)
  if not self.done then
    if ok and type(res) == 'string' then
      util.notify(self.name .. ": " .. res)
    end
    self._pend = M.State.SPIN
  end
  return ok, res, tb
end

function M.Spin:error(err)
  return false, err, debug.traceback(self._cr)
end

return M
