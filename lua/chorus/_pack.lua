local M = {}
local util = require 'chorus._util'
local shada = require 'chorus._shada'
local async = require 'chorus._async'

--- @class chorus.pack.Pack: chorus.util.Object
--- @field name string
--- @field url string
--- @field path string
--- @field add boolean
--- @field added boolean
--- @field scheduled boolean
--- @field version? string
--- @field error? any
--- @field depends { [string]: chorus.pack.Pack }
--- @field private _build? async fun(chorus.pack.Pack)
--- @field private _setup? async fun()
--- @field private _build_run boolean
--- @field private _setup_run boolean
--- @field private _setup_start boolean
M.Pack = util.class()

--- @type { [string]: chorus.pack.Pack? }
local pack_by_url = {}

--- @type { [string]: chorus.pack.Pack? }
local pack_by_name = {}

--- @param url string
--- @return string
--- @return string
local function resolve_source(url)
  if not url:match('^[%l%u][%w%a.+-]*:') then
    url = "https://github.com/" .. url
  end
  while url:match("/$") do
    url = url:sub(1, #url - 1)
  end
  local name = url:match("/([^/]*)$")
  if not name then
    error("couldn't derive name from url: " .. url)
  end
  return url, name
end

--- @return chorus.pack.Pack?
function M.Pack:for_url(url)
  return pack_by_url[url]
end

--- @return chorus.pack.Pack?
function M.Pack:for_name(name)
  return pack_by_name[name]
end

--- @return table
function M.Pack:_shada()
  local pack = shada.pack
  if not pack then
    pack = vim.empty_dict()
    shada.pack = pack
  end
  local pdata = pack[self.name]
  if not pdata then
    pdata = vim.empty_dict()
    pack[self.name] = pdata
  end
  return pdata
end

--- @type { [string]: any }
local shada_keys = {
  _build_run = true,
  path = ''
}

--- @param key string
--- @return any
function M.Pack:__index(key)
  local default = shada_keys[key]
  if default then
    local v = self:_shada()[key]
    if v == nil then
      v = default
    end
    return v
  end
  return M.Pack[key]
end

--- @param key string
--- @param value any
function M.Pack:__newindex(key, value)
  if shada_keys[key] then
    self:_shada()[key] = value
    return
  end
  rawset(self, key, value)
end

--- @param spec_or_url chorus.SpecOrUrl
--- @return self
function M.Pack:resolve(spec_or_url)
  local spec
  if type(spec_or_url) == 'string' then
      --- @type chorus.Spec
      spec = { spec_or_url }
  else
      spec = spec_or_url
  end
  local url, guess = resolve_source(spec[1])
  local inst = pack_by_url[url]
  if not inst then
    inst = setmetatable({}, self) --[[@as chorus.pack.Pack]]
    pack_by_url[url] = inst
    inst.url = url
    inst.name = spec.name or guess
    pack_by_name[inst.name] = inst
    inst.added = false
    inst.add = false
    inst.depends = {}
    inst._setup_run = false
    inst._setup_start = false
  end

  if spec.add ~= false then
    inst.add = true
  end

  if spec.version or spec.branch then
    if inst.version then
      error(inst.name .. ": version/branch conflict")
    end
    inst.version = inst.version or spec.version or spec.branch
  end

  local deps_or_url = spec.dependencies or {}
  local deps
  if type(deps_or_url) ~= 'table' or not vim.isarray(deps_or_url) then
    --- @cast deps_or_url -chorus.SpecOrUrl[]
    deps = { deps_or_url }
  else
    --- @cast deps_or_url -chorus.Spec
    deps = deps_or_url
  end
  for _, dspec in ipairs(deps) do
    local dpack = self:resolve(dspec)
    inst.depends[dpack.name] = dpack
  end

  local setup
  if spec.setup then
    --- @async
    setup = function() spec.setup(spec.opts) end
  end
  if spec.opts then
    --- @async
    setup = setup or function()
      local main = spec.main or inst.name:match("^(.*)%.nvim$") or inst.name
      local mod = require(main)
      if mod.setup then
        mod.setup(spec.opts)
      end
    end
  end
  if setup then
    if inst._setup then
      error(inst.name .. ": setup conflict")
    end
    inst._setup = setup
  end

  --- @type async fun()?
  local build = nil
  if type(spec.build) == 'string' then
    if spec.build:match('^:') then
      local cmd = spec.build:sub(2)
      build = function ()
        vim.cmd(cmd)
      end
    else
      local cmd = spec.build
      --- @async
      build = function ()
        util.notify("Building " .. inst.name)
        local shell = vim.fn.has('win32') == 1 and { "cmd.exe", "/c", cmd } or
          { "sh", "-c", cmd }
        local done = false
        local proc = vim.system(shell, { cwd = inst.path }, function() done = true end)
        while not done do
          coroutine.yield()
        end
        local res = proc:wait()
        if res.code ~= 0 then
          error("build failed")
        end
      end
    end
  elseif spec.build and vim.is_callable(spec.build) then
    build = spec.build
  end
  if build then
    if inst._build then
      error(inst.name .. ": build conflict")
    end
    inst._build = build
  end

  return inst
end

--- @return vim.pack.Spec
function M.Pack:to_add()
  return {
    src = self.url,
    name = self.name,
    version = self.version
  }
end

--- @param event 'install'|'update'|'delete'
--- @param arg string|nil
function M.Pack:changed(event, arg)
  if event == 'install' or event == 'update' then
    self.path = arg
    self._build_run = false
  else
    shada.data.pack[self.name] = nil
    pack_by_url[self.url] = nil
  end

  if require 'chorus'.did_setup then
    -- The first setup will flush shada in one go
    vim.schedule(function() shada.flush(true) end)
  end
end

--- @return boolean
function M.Pack:needs_setup()
  return (self._build ~= nil and not self._build_run) or
    (self._setup ~= nil and not self._setup_run)
end

--- @param reactor chorus.async.Reactor
--- @return chorus.async.Task
function M.Pack:setup(reactor)
  if self._setup_start then
    error("duplicate setup")
  end
  self._setup_start = true
  --- @async
  return reactor:task(function()
    async.pend(function() return self:depends_ready() and async.State.RUN or async.State.DEPEND end)
    if self._build and not self._build_run then
      --- @async
      async.spin(function() return self._build(self) end)
      self._build_run = true
    end
    if self._setup and not self._setup_run then
      async.spin(self._setup)
      self._setup()
      self._setup_run = true
    end
  end, {
    name = self.name,
    on_done = function(task)
      self._setup_start = false
      if not task.ok then
        self.error = "build or setup failed"
      end
    end
  })
end

--- @return boolean
function M.Pack:depends_ready()
  return vim.iter(self.depends):all(function (_, d) return d:ready() end)
end

--- @return boolean
function M.Pack:ready()
  if self.error then
    return true
  end

  if not self:depends_ready() then
    return false
  end

  if not self.added or self:needs_setup() then
    return false
  end

  return true
end

return M
