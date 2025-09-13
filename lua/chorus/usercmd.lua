-- User Command Support
local M = {}

local cspec = require 'chorus._spec'
local util = require 'chorus._util'

--- User command function
---
--- Type of function invoked when a user command is run
--- @alias chorus.usercmd.Func fun(vim.api.keyset.create_user_command.command_args)

--- User command spec
---
--- Specifies how to create one or more user commands
--- @class chorus.usercmd.Spec: vim.api.keyset.user_command
--- @field buffer? boolean | integer Create command only for given buffer; `0` or `true`
--- mean the current buffer.  Default: `false`
--- @field addr? string Address range handling
--- @field bang? boolean Command accepts `!`.  Default: `false`
--- @field bar? boolean Command can be followed by a `|` and another command.  Default: `false`
--- @field complete? string | function Completion rule.  Default: none
--- @field count? integer | boolean Count accepted.
--- 1. `false`: Count not accepted (default)
--- 2. `n`: A count (default `n`) is specified in the line number position or first argument
--- 3. `true`: Acts like `0`
--- @field desc? string A description of the command.  Default: none
--- @field force? boolean Override previous definition.  Default: `true`
--- @field keepscript? boolean Use location of command invocation for verbose messages.  Default: `false`
--- @field nargs? 0 | 1 | '*' | '?' | '+' Argument count.
--- 1. `0`: No arguments allowed (default)
--- 2. `1`: One argument required
--- 3. `'*'`: Any number of whitespace-separated arguments are allowed
--- 4. `'?'`: 0 or 1 arguments allowed
--- 5. `'+'`: One or more arguments required
--- @field preview? function Preview callback
--- @field range? boolean | '%' | integer Range allowed
--- 1. `false`: Range not accepted (default)
--- 1. `true`: Range accepted, default is current line
--- 2. `'%'`: Range accepted, default is whole file
--- 3. `n`: A count (default `n`) is specified in the line number position
--- @field register? boolean The first argument to the command can be an
--- optional register name.  Default: `false`
--- @field [string] string | chorus.usercmd.Spec | chorus.usercmd.Spec Nested specification
--- 1. `"<name>" = "<cmd>"`: Command name and ex command to run
--- 2. `"<name>" = function(args) .. end` Command name and function to run
--- 3. `"<name>" = { .... }` Nested specification (should not provide name)
--- which inherits options from parent table
--- @field [integer] string | chorus.usercmd.Func | chorus.usercmd.Spec Positional arguments
--- 1. `"<name>", "<cmd>"`: Command name and ex command to run
--- 2. `"<name>", function(args) ... end`: Command name and function to run
--- 3. `{ ... }, ...`: Nested user command specs which inherit options from the parent table

--- User command ID
---
--- Token with information to delete a created user command
--- @class chorus.usercmd.ID

local option_spec = cspec.compile {
  buffer = cspec.buffer,
  bang = 'boolean',
  nargs = {'string', 'number'},
  range = {'string', 'number', 'boolean'},
  count = 'number',
  addr = 'string',
  bar = 'boolean',
  complete = {'string', 'callable'},
  desc = 'string',
  force = 'boolean',
  preview = 'callable',
  [cspec.ARGS] = {'string', 'callable', 'table'},
  [cspec.CONFIG] = {
    allow_unknown_options = true
  }
}

--- @param spec chorus.usercmd.Spec
--- @param defaults? { [string]: any }
--- @return chorus.usercmd.ID[]
local function apply(spec, defaults)
  local opts, args, rest = option_spec:parse(spec, defaults)

  if not vim.tbl_isempty(rest) then
    local result = {}
    for k, v in pairs(rest) do
      --- @cast k string
      --- @cast v chorus.usercmd.Spec
      v = util.copy(v)
      table.insert(v, 1, k)
      for _, id in ipairs(apply(v, opts)) do
        table.insert(result, id)
      end
    end
    return result
  end

  if type(args[1]) == 'string' then
    local name = args[1]
    local command = args[2]
    local buffer = opts.buffer
    opts.buffer = nil
    if buffer == nil then
      if vim.is_callable(command) and type(command) ~= 'function' then
        local inner = command
        command = function(...) return inner(...) end
      end
      vim.api.nvim_create_user_command(name, command, opts)
    else
      vim.api.nvim_buf_create_user_command(buffer, name, command, opts)
    end
    return {{name, buffer == 0 and vim.api.nvim_get_current_buf() or buffer}}
  end

  local result = {}
  for _, subtbl in ipairs(args) do
    for _, id in ipairs(apply(subtbl, opts)) do
      table.insert(result, id)
    end
  end
  return result
end

--- Create user commands
---
--- Also available by invoking [`chorus.usercmd`](./chorus.usercmd) as a
--- function (or just `usercmd` when using the default prelude)
---
--- @param spec chorus.usercmd.Spec The specification
--- @return chorus.usercmd.ID? ... ids IDs of created commands
function M.create(spec)
  return unpack(apply(spec))
end

--- Delete user commands
--- @param ... chorus.usercmd.ID The IDs to delete
function M.delete(...)
  for _, id in ipairs { ... } do
    local name, buffer = unpack(id)
    if buffer then
      vim.api.nvim_buf_del_user_command(buffer, name)
    else
      vim.api.nvim_del_user_command(name)
    end
  end
end

local mt = {}

function mt:__call(spec)
  return M.create(spec)
end

setmetatable(M, mt)
return M
