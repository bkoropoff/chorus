local M = {}
local cspec = require 'chorus.spec'
local util = require 'chorus.util'

--- @alias chorus.autocmd.Callback fun(vim.api.keyset.create_autocmd.callback_args)

--- Autocommand specification
--- @class chorus.autocmd.Spec
--- @field event? string | string[] Event or events; can also be passed positionally
--- @field pattern? string | string[] Event pattern or patterns; can also be passed positionally
--- @field command? string Ex command to execute; can also be passed positionally
--- @field callback? chorus.autocmd.Callback Callback to execute; can also be passed positionally
--- @field group? string Group for the created autocommands.  Default: no group.
--- @field create? boolean Create autocommand group if it doesn't exist.  Default: `true`
--- @field buffer? boolean | integer Create autocommand for given buffer only
--- (`0` or `true` for current buffer).  Default: `false`
--- @field nested? boolean Allow nested autocommand triggering
--- @field once? boolean Unregister autocommand after triggering
--- @field clear? boolean Clear autocommand group if specified.  Default: `false`
--- @field [integer] string | chorus.autocmd.Callback | chorus.autocmd.Spec Positional arguments
--- - A string is interpreted as the event or pattern (whichever hasn't been specified yet)
--- - A callable is interpreted as the callback
--- - A table is a nested autocommand specification which inherits from its parents

local option_spec = cspec.compile {
  group = 'string',
  event = { 'string', cspec.array('string') },
  pattern = { 'string', cspec.array('string') },
  buffer = cspec.buffer,
  clear = 'boolean',
  create = 'boolean',
  callback = 'callable',
  command = 'string',
  nested = 'boolean',
  once = 'boolean',
  [cspec.ARGS] = {'callable', 'string', 'table'}
}

local function apply(spec, defaults, created)
  created = created or {}

  local ids = {}
  local opts, args = option_spec:parse(spec, defaults)

  local create = opts.create
  if create == nil then
    create = true
  end

  if opts.group and create and not created[opts.group] then
    vim.api.nvim_create_augroup(opts.group, {
      clear = opts.clear
    })
    created[opts.group] = true
  end
  if not opts.event and #args >= 2 and type(args[1]) == 'string' then
    opts.event = table.remove(args, 1)
  end
  if not opts.pattern and #args >= 2 and type(args[1]) == 'string' then
    opts.pattern = table.remove(args, 1)
  end
  if not opts.command and not opts.callback and #args == 1 then
    if type(args[1]) == 'string' then
      opts.command = table.remove(args, 1)
    elseif vim.is_callable(args[1]) then
      opts.callback = table.remove(args, 1)
    end
  end

  for _, obj in ipairs(args) do
    if type(obj) ~= 'table' then
      error("Expected table for trailing argument: " .. vim.inspect(obj))
    end
    util.insert_all(ids, apply(obj, opts, created))
  end

  if opts.command and opts.callback then
    error("Both command and callback specified")
  end

  if opts.pattern and opts.buffer then
    error("Both pattern and buffer specified")
  end

  if opts.command or opts.callback then
    table.insert(ids, vim.api.nvim_create_autocmd(
      opts.event,
      util.retract(opts, 'create', 'event', 'clear')))
  end

  return ids
end

--- Create autocommands
---
--- Also available by invoking [`chorus.autocmd`](chorus.autocmd) as a function.
--- @param spec chorus.autocmd.Spec The specification
--- @return integer ... ids All created autocommands
function M.create(spec)
  return unpack(apply(spec))
end

--- Delete autocommands
---
--- @param ... integer One or more IDs previously returned by
--- [`chorus.autocmd[.set]`](chorus.autocmd.set)
function M.delete(...)
  for _, id in ipairs { ... } do
    return vim.api.nvim_del_autocmd(id)
  end
end

local mt = {}
function mt:__call(spec)
  return M.create(spec)
end

setmetatable(M, mt)
return M
