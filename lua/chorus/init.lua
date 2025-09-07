local M = {}

local shada = require 'chorus.shada'
local util = require 'chorus.util'
local PendKind = require 'chorus.job'.PendKind
local Job = require 'chorus.job'.Job
local pend = require 'chorus.job'.pend
local Reactor = require 'chorus.reactor'.Reactor
local Pack = require 'chorus.pack'.Pack

--- Package spec
--- @class chorus.Spec
--- @field [1] string URL or Github `org/repo`
--- @field name? string Name (derived from `[1]` otherwise)
--- @field build? (string | async fun()) A command or ex command (prefix with
--- `:`), or a function to run to build the package before it is usable.  The
--- function may continually call `coroutine.yield` with an optional status
--- message to avoid blocking Neovim while waiting for completion
--- @field setup? async fun(any) A function to set up the package after it's
--- available.  As above, the function may yield to avoid blocking Neovim.
--- @field opts? any Options to pass to package setup function
--- @field main? string Name of main Lua module, guessed from package name by default
--- @field dependencies? (chorus.SpecOrUrl[] | chorus.SpecOrUrl) Specs of dependencies
--- @field version? string Which version (tag or branch) to install.  Overrides `branch`
--- @field branch? string Which branch to install.  Excludes `version`

--- Package specification, plain URL, or Github `org/repo`
--- @alias chorus.SpecOrUrl chorus.Spec | string

--- @type chorus.pack.Pack[]
local scheduled = {}


--- @param pack chorus.pack.Pack
local function schedule_pack(pack)
  for _, dep in pairs(pack.depends) do
    schedule_pack(dep)
  end

  if not pack.scheduled then
    table.insert(scheduled, pack)
    pack.scheduled = true
  end
end

--- @param reactor chorus.reactor.Reactor
--- @param source_jobs chorus.job.Job[]
--- @return chorus.job.Job
local function package_job(reactor, source_jobs)
  local function done()
    return vim.iter(source_jobs):all(function (job) return job.done end)
  end

  return Job:new(function()
    while not done() do
      local add = vim.tbl_map(Pack.to_add, scheduled)

      local ok, err, tb = util.tbcall(
        function() vim.pack.add(add, { confirm = false }) end)

      if not ok then
        util.notify_error("vim.pack.add: " .. err, tb)
      end

      local setups = {}

      for _, pack in ipairs(scheduled) do
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
          reactor:schedule(pack:setup())
        end
      end

      scheduled = {}

      pend(PendKind.DEPEND, function() return #scheduled > 0 or done() end)
    end
  end, { name = "package" })
end

--- Use packages
---
--- Also available by invoking the [`chorus`](chorus) module as a function
---
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
    schedule_pack(pack)
    table.insert(packs, pack)
  end

  pend(PendKind.DEPEND, function()
    return vim.iter(packs):all(function(pack) return pack:ready() end)
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
    opt = require 'chorus.opt',
    keymap = require 'chorus.keymap',
    autocmd = require 'chorus.autocmd',
    usercmd = require 'chorus.usercmd',
    lsp = require 'chorus.lsp'
  }
end

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
--- @field sources (string|async fun())[]|string|async fun() Files or functions to run to provide configuration.
--- Strings may be globs.  Relative paths will be expanded in `vim.opt.runtimepath`.
--- @field prelude? { [string] : any } Variables to inject into environment of
--- configuration files or functions.  Default:
--- ```
--- {
---    chorus = require 'chorus',
---    opt = require 'chorus.opt',
---    keymap = require 'chorus.keymap',
---    autocmd = require 'chorus.autocmd',
---    usercmd = require 'chorus.usercmd',
---    lsp = require 'chorus.lsp'
--- }
--- ```

--- Set up chorus
--- @param cfg chorus.Config Configuration
function M.setup(cfg)
  local stdconf = vim.fn.stdpath('config')
  assert(type(stdconf) == 'string')
  local config = vim.fn.fnamemodify(stdconf, ':~') .. '/'

  local jobs = {}
  local prelude = cfg.prelude or default_prelude()
  local sources = cfg.sources
  if type(sources) ~= 'table' then
    sources = { sources }
  end

  for _, source in ipairs(sources) do
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
        table.insert(jobs, Job:new(chunk, { name = name }))
      end
    else
      setfenv(source, vim.tbl_extend('force', getfenv(source), prelude))
      table.insert(jobs, Job:new(source))
    end
    ::next::
  end

  require 'chorus.autocmd' {
    group = 'ChorusPack',
    clear = true,
    'PackChanged',
    function(args)
      local data = args.data
      local pack = Pack:for_name(data.spec.name)
      pack:changed(data.kind, data.path)
    end
  }

  local reactor = Reactor:new()

  for _, source in ipairs(jobs) do
    reactor:schedule(source)
  end

  reactor:schedule(package_job(reactor, jobs))

  reactor:drain()

  shada.flush(true)

  require 'chorus.usercmd' {
    Chorus = {
      nargs = '+',
      desc = "Chorus management",
      function(...) return require 'chorus.command'(...) end
    }
  }
end

local mt = {}

--- @async
function mt:__call(specs)
  M.use(specs)
end

setmetatable(M, mt)
return M
