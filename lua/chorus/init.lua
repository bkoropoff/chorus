--- Chorus configuration
local M = {}

local util = require 'chorus._util'
local async = require 'chorus._async'
local Pack = require 'chorus._pack'.Pack

--- Has at least one invocation of [`chorus.setup`](./chorus.setup) completed?
--- @type boolean
M.did_setup = false
--- Is [`chorus.setup`](./chorus.setup) in progress?
--- @type boolean
M.in_setup = false

--- @class chorus.Provide
--- @field [1] boolean | chorus.async.Task
--- @field [2] any?
--- @field [3] string?

--- @class state
--- @package
--- @field scheduled chorus.pack.Pack[]
--- @field reactor chorus.async.Reactor
--- @field provide { [any]: chorus.Provide? }
--- @field need { [any]: boolean? }
--- @field lazy { [chorus.async.Task]: boolean? }
local state

--- Package spec
--- @class chorus.Spec
--- @field [1] string URL or Github `org/repo`
--- @field name? string Name (derived from `[1]` otherwise)
--- @field build? (string | async fun()) A command or ex command (prefix with
--- `:`), or a function to run to build the package before it is usable.  The
--- function may continually call `coroutine.yield` with an optional status
--- message to avoid blocking Neovim while waiting for completion
--- @field setup? function A function to set up the package after it's
--- available.  As above, the function may yield to avoid blocking Neovim.
--- @field opts? any Options to pass to package setup function
--- @field main? string Name of main Lua module, guessed from package name by default
--- @field dependencies? (chorus.SpecOrUrl[] | chorus.SpecOrUrl) Specs of dependencies
--- @field version? string Which version (tag or branch) to install.  Overrides `branch`
--- @field branch? string Which branch to install.  Excludes `version`
--- @field add? boolean Add package.  `false` allows specifying details without actually
--- causing the package to be installed until later.  Default: `true`

--- Package specification, plain URL, or Github `org/repo`
--- @alias chorus.SpecOrUrl chorus.Spec | string

--- @param pack chorus.pack.Pack
local function schedule_pack(pack)
  for _, dep in pairs(pack.depends) do
    schedule_pack(dep)
  end

  if not pack.scheduled then
    table.insert(state.scheduled, pack)
    pack.scheduled = true
  end
end

--- @return chorus.async.Task
local function package_task()
  return state.reactor:task(function()
    -- Always start by idling, to give sources a chance to run first
    async.pend(function() return async.State.IDLE end)

    while true do
      local sched = state.scheduled
      state.scheduled = {}
      local add = vim.tbl_map(Pack.to_add, sched)

      local ok, err, tb = util.tbcall(
        function() vim.pack.add(add, { confirm = false, load = M.did_setup }) end)

      if not ok then
        util.notify_error("vim.pack.add: " .. err, tb)
      end

      local setups = {}

      for _, pack in ipairs(sched) do
        if not ok then
          pack.error = "package add failed"
        else
          pack.added = true
          if pack:needs_setup() then
            table.insert(setups, pack)
          end
        end
      end

      for _, pack in ipairs(setups) do
        if not pack.error then
          state.reactor:schedule(pack:setup(state.reactor))
        end
      end

      async.pend(function()
        if #state.scheduled > 0 then
          return async.State.IDLE
        else
          return async.State.DETACH
        end
      end)
    end
  end, { name = "package" })
end

--- Use packages
---
--- Also available by invoking [`chorus`](chorus) as a function.
---
--- If the same package is specified multiple times, details will be merged
--- from all specifications. Certain details may only be specified once or an
--- error will be raised:
--- - `package` or `version`
--- - `build`
--- - `setup`
--- @async
--- @param specs chorus.SpecOrUrl[] | chorus.Spec
function M.use(specs)
  if vim.iter(pairs(specs)):any(function(k, _) return type(k) == 'string' and not k:match('/') end) then
    specs = {
      --- @as chorus.Spec
      specs
    }
  end

  local packs = {}
  for key, spec in pairs(specs) do
    if type(key) == 'string' then
      -- ['url'] = { ... }
      spec = util.copy(spec)
      table.insert(spec, 1, key)
      --- @cast spec chorus.Spec
    end
    local pack = Pack:resolve(spec)
    if pack.add then
      schedule_pack(pack)
      table.insert(packs, pack)
    end
  end

  async.pend(function()
    if vim.iter(packs):all(function(pack) return pack:ready() end) then
      return async.State.RUN
    else
      return async.State.DEPEND
    end
  end)

  for _, pack in ipairs(packs) do
    if pack.error then
      error(pack.error, 0)
    end
  end
end

local function default_prelude()
  return {
    chorus = M,
    autocmd = M.autocmd,
    defer = M.defer,
    filetype = M.filetype,
    fork = M.fork,
    keymap = M.keymap,
    lazy = M.lazy,
    lsp = M.lsp,
    need = M.need,
    opt = M.opt,
    provide = M.provide,
    treesitter = M.treesitter,
    usercmd = M.usercmd,
  }
end

--- @param source string
--- @return string[]
local function expand_source(source)
  if vim.fn.isabsolutepath(source) == 1 then
    return vim.fn.glob(source, true, true)
  end
  local result = {}
  for _, prefix in ipairs(vim.opt.rtp:get()) do
    table.insert(result, vim.fn.glob(vim.fs.joinpath(prefix, source), true, true))
  end
  return vim.iter(result):flatten():totable()
end

--- Chorus configuration
--- @class chorus.Config
--- @field prelude? { [string] : any } Variables to inject into environment of
--- configuration files or functions.  Default:
--- ```lua
--- {
---    chorus = require 'chorus',
---    autocmd = require 'chorus'.autocmd,
---    defer = require 'chorus'.defer,
---    filetype = require 'chorus'.filetype,
---    fork = require 'chorus'.fork,
---    keymap = require 'chorus'.keymap,
---    lazy = require 'chorus'.lazy,
---    lsp = require 'chorus'.lsp,
---    need = require 'chorus'.lsp,
---    opt = require 'chorus'.opt,
---    provide = require 'chorus'.provide
---    treesitter = require 'chorus'.treesitter,
---    usercmd = require 'chorus'.usercmd,
--- }
--- ```
--- @field [integer] string|async fun() Files or functions to run to provide configuration.
--- Strings may be globs.  Relative paths will be expanded in `vim.opt.runtimepath`.

--- Deferral spec
---
--- Defines what autocmd event to wait for before continuing with configuration
---
--- @class chorus.DeferSpec
--- @field event string | string[] Autocommand event(s)
--- @field pattern? (string | string[]) Autocommand pattern(s)
--- @field predicate? fun(vim.api.keyset.create_autocmd.callback_args):boolean Additional predicate to
--- determine match

--- Defer until autocommand event
---
--- The current configuration source is suspended and resumed when the first
--- autocommand event matching the given specification occurs.
---
--- @async
--- @param spec chorus.DeferSpec Specifies when to resume
function M.defer(spec)
  local cur = async.current()

  if not cur then
    error("chorus.defer must be called from configuration source")
  end

  local autocmd = require 'chorus.autocmd'
  --- @type integer
  local id

  local fired = false

  id = autocmd {
    event = spec.event,
    pattern = spec.pattern,
    nested = true,
    callback = function(args)
      if not spec.predicate or spec.predicate(args) then
        autocmd.delete(id)
        fired = true
        state.reactor:schedule(cur)
        state.reactor:drain { cur }
      end
    end
  }

  state.lazy[cur] = true
  async.pend(function() return (fired or state.need[cur]) and async.State.RUN or async.State.DETACH end)
  state.lazy[cur] = nil
  autocmd.delete(id)
end

--- Advertise capabilities
---
--- The given capabilities are treated as available once the current
--- configuration source completes.
---
--- If `lazy` is `true` in `caps`, the current configuration source is
--- suspended and resumed when one of the given capabilities is requested by
--- [`chorus.need`](./chorus.need).
---
--- @async
--- @param caps string | { lazy: boolean?, [integer]: string} Capabilities
function M.provide(caps)
  if type(caps) ~= 'table' then
    caps = { caps }
  end
  local cur = async.current()
  if not cur then
    error("chorus.provide must be called from a configuration sourcec")
  end
  for _, thing in ipairs(caps) do
    if state.provide[thing] then
      error("chorus.provide: duplicate capability: " .. thing)
    end
    state.provide[thing] = { cur } --[[@as chorus.Provide]]
  end

  if caps.lazy then
    async.pend(function()
      if vim.iter(ipairs(caps)):any(function(_, t) return state.need[t] end) then
        return async.State.RUN
      else
        return async.State.DETACH
      end
    end)
  end
end

--- Defer until capabilities available
---
--- The current configuration source is suspended and resumed once the
--- specified abstract capabilities are available, usually by a configuration
--- source that called [`chorus.provide`](./chorus.provide) resuming and
--- completing.
---
--- @async
--- @param caps string | string[] Capabilities
function M.need(caps)
  if type(caps) ~= 'table' then
    caps = { caps }
  end
  for _, thing in ipairs(caps) do
    state.need[thing] = true
    local provide = state.provide[thing]
    if provide and type(provide[1]) == 'table' then
      state.reactor:schedule(provide[1])
    end
  end

  async.pend(function()
    if vim.iter(caps):all(function(t)
      local provide = state.provide[t]
      return provide and type(provide[1]) == 'boolean'
    end) then
      return async.State.RUN
    else
      return async.State.DEPEND
    end
  end)

  for _, thing in ipairs(caps) do
    local provide = state.provide[thing]
    assert(provide)
    if not provide[1] then
      error("chorus.need: " .. thing .. " provider failed with error")
    end
  end
end

--- Lazily import module or evaluate function
---
--- If no argument is provided, the current configuration source is
--- suspended. This allows delineating a portion of the configuration source
--- that should be run only lazily.
---
--- If an argument is provided, returns a proxy object.  When this object is
--- indexed or called:
--- - The configuration source is resumed and run to completion if needed
--- - The argument is run (if a function) or `require`d (if a string)
---   and the result cached, if not already
--- - The index or call operation is performed and returned
---
--- Modules or functions that return an object other than a table or function
--- are not supported.
---
--- @async
--- @param delayed string | fun():(table|function) Module name or function
--- @return any
--- @overload fun()
function M.lazy(delayed)
  --- @cast delayed +nil
  local cur = async.current()
  if not cur then
    error("chorus.lazy: must be called from a configuration source")
  end
  if delayed then
    return util.delay(function()
      if not cur.done and not async.current() then
        state.need[cur] = true
        state.reactor:schedule(cur)
        state.reactor:drain { cur }
        state.need[cur] = false
      end
      if type(delayed) == 'string' then
        return require(delayed)
      end
      return delayed()
    end)
  end
  state.lazy[cur] = true
  async.pend(function() return state.need[cur] and async.State.RUN or async.State.DETACH end)
  state.lazy[cur] = nil
end

--- Wrap value as proxy object
---
--- Calling or indexing the result will resume the current configuration source
--- if it is suspended by [`lazy`](./chorus.lazy).
--- @generic T table | function
--- @async
--- @param value T
--- @return T
function M.lazy_wrap(value)
  return M.lazy(function() return value end)
end

--- Start new concurrent configuration source
---
--- Functions like [`lazy`](./chorus.lazy) and [`provide`](./chorus.provide) are
--- scoped to the new source, not the current source.
---
--- @param func async fun() Function to run concurrently
--- @param name? string Optional name for the source
function M.fork(func, name)
  state.reactor:schedule(state.reactor:task(func, { name = name }))
end

local function source_done(task)
  for _, v in pairs(state.provide) do
    if v[1] == task then
      v[1] = task.ok
      v[2] = task.error
      v[3] = task.traceback
    end
  end
  state.need[task] = nil
  state.lazy[task] = nil
end

--- Set up chorus
--- @param cfg chorus.Config | string | async fun() Configuration
function M.setup(cfg)
  local was_in_setup = M.in_setup
  M.in_setup = true

  local stdconf = vim.fn.stdpath('config')
  assert(type(stdconf) == 'string')
  local config = vim.fn.fnamemodify(stdconf, ':~') .. '/'

  if type(cfg) ~= 'table' then
    cfg = { cfg } --[[@as chorus.Config]]
  end

  local tasks = {}
  local prelude = cfg.prelude or default_prelude()

  if not state then
    state = {
      scheduled = {},
      provide = {},
      need = {},
      lazy = {},
      reactor = async.Reactor:new()
    }
  end

  for _, source in ipairs(cfg) do
    if type(source) == 'string' then
      for _, path in ipairs(expand_source(source)) do
        local name = vim.fn.fnamemodify(path, ':~')
        if name:sub(1, #config) == config then
          name = name:sub(#config + 1)
        end
        local chunk, err = loadfile(path)
        if not chunk then
          util.notify_error(name .. ': ' .. (err or "unknown"))
          goto next
        end
        setfenv(chunk, vim.tbl_extend('force', getfenv(chunk), prelude))
        table.insert(tasks, state.reactor:task(chunk, { name = name, on_done = source_done }))
      end
    else
      setfenv(source, vim.tbl_extend('force', getfenv(source), prelude))
      table.insert(tasks, state.reactor:task(source, {
        name = debug.getinfo(source).name,
        on_done = source_done
      }))
    end
    ::next::
  end

  for _, j in ipairs(tasks) do
    state.reactor:schedule(j)
  end

  require 'chorus.autocmd' {
    group = 'chorus.packchanged',
    desc = "Chorus vim.pack integration",
    'PackChanged',
    function(args)
      local data = args.data
      local pack = Pack:for_name(data.spec.name)
      if pack then
        pack:changed(data.kind, data.path)
      end
    end
  }

  state.reactor:schedule(package_task())
  state.reactor:drain(tasks)

  if not M.did_setup then
    require 'chorus._shada'.flush(true)

    require 'chorus.usercmd' {
      Chorus = {
        nargs = '+',
        desc = "Chorus management",
        function(...) return require 'chorus._command'(...) end
      }
    }
  end

  M.did_setup = true
  M.in_setup = was_in_setup
end

function M._flush()
  while not vim.tbl_isempty(state.lazy) do
    local tasks = {}
    local lazy = state.lazy
    state.lazy = {}
    for task, _ in pairs(lazy) do
      state.need[task] = true
      state.reactor:schedule(task)
      table.insert(tasks, task)
    end
    state.reactor:drain(tasks)
  end
end

local mt = {}

--- @async
function mt:__call(specs)
  return M.use(specs)
end

function mt:__index(key)
  if type(key) ~= 'string' or key:match('^_') then
    return nil
  end
  return require('chorus.' .. key)
end

function mt:__newindex(_, _)
  error("assignment disallowed")
end

setmetatable(M, mt)
return M
