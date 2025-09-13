local M = {}

local util = require 'chorus._util'

--- @class chorus.spec.CONFIG
M.CONFIG = {}
--- @class chorus.spec.ARGS
M.ARGS = {}

--- @alias chorus.spec.TypeErr { [1]: string, [2]: any }
--- @alias chorus.spec.Verify fun(any): (boolean, any | chorus.spec.TypeErr)
--- @alias chorus.spec.Type string | chorus.spec.Verify | chorus.spec.Type[]

--- @class chorus.spec.Config
--- @field allow_unknown_elements? boolean
--- @field inherit? chorus.spec.Compiled

--- @class chorus.spec.Spec
--- @field [string] chorus.spec.Type?
--- @field [chorus.spec.CONFIG] chorus.spec.Config?
--- @field [chorus.spec.ARGS] chorus.spec.Type?

--- @param ty string
--- @return chorus.spec.Verify
local function verify_type(ty)
  if ty == 'array' then
    return function(obj)
      if vim.isarray(obj) then
        return true, obj
      else
        return false, {'array', obj}
      end
    end
  end
  if ty == 'list' then
    return function(obj)
      if vim.islist(obj) then
        return true, obj
      else
        return false, {'list', obj}
      end
    end
  end
  if ty == 'callable' then
    return function(obj)
      if vim.is_callable(obj) then
        return true, obj
      else
        return false, {'callable', obj}
      end
    end
  end
  return function(obj)
    if type(obj) ~= ty then
      return false, {ty, obj}
    else
      return true, obj
    end
  end
end

--- @param tbl chorus.spec.Verify[]
--- @return chorus.spec.Verify
local function verify_alternates(tbl)
  return function(obj)
    local errs = {}
    local res, val
    local all_obj = true
    for _, alt in ipairs(tbl) do
      res, val = alt(obj)
      if res then
        return true, val
      end
      all_obj = all_obj and val[2] ~= obj
      table.insert(errs, val)
    end
    local fmt
    if all_obj then
      fmt = function(o) return o[1] end
    else
      fmt = function(o) return o[1] .. ":" .. vim.inspect(o[2]) end
    end
    local expected = table.concat(vim.tbl_map(fmt, errs), ", ")
    if not all_obj then
      expected = "[" .. expected .. "]"
    end
    return false, {expected, obj}
  end
end

--- @param obj chorus.spec.Type
--- @return chorus.spec.Verify
local function compile_verifier(obj)
  if type(obj) == 'string' then
    return verify_type(obj)
  end
  if vim.is_callable(obj) then
    --- @cast obj -chorus.spec.Type[]
    return obj
  end
  --- @cast obj -chorus.spec.Verify
  if vim.isarray(obj) then
    return verify_alternates(vim.tbl_map(compile_verifier, obj))
  end
  error("expected callable, array, or string: " .. vim.inspect(obj))
end

function M.array(inner)
  inner = compile_verifier(inner)
  return function(obj)
    if not vim.isarray(obj) then
      return false, {"array", obj}
    end
    for _, v in ipairs(obj) do
      local valid
      valid, v = inner(v)
      if not valid then
        return valid, v
      end
    end
    return true, obj
  end
end

--- @param tbl { key: any, value: chorus.spec.Type }
--- @return chorus.spec.Verify
function M.table(tbl)
  local key = compile_verifier(tbl.key)
  local value = compile_verifier(tbl.value)
  return function(obj)
    if type(obj) ~= 'table' then
      return false, {"table", obj}
    end
    for k, v in pairs(obj) do
      local valid
      valid, k = key(k)
      if not valid then
        return valid, k
      end
      valid, v = value(v)
      if not valid then
        return valid, v
      end
    end
    return true, obj
  end
end

--- @class chorus.spec.DATA
--- @package
local DATA = {}

--- @class chorus.spec.Compiled
--- @field private [chorus.spec.DATA] table
--- @field private [chorus.spec.CONFIG] table
--- @field private [chorus.spec.ARGS] table
local Compiled = util.class()

--- @param spec chorus.spec.Spec
--- @return chorus.spec.Compiled
function M.compile(spec)
  local data = {}
  --- @type table?
  local cfg = nil
  for k, v in pairs(spec) do
    if k == M.CONFIG then
      --- @cast v chorus.spec.Config
      cfg = v
    else
      --- @cast v -chorus.spec.Config
      data[k] = compile_verifier(v)
    end
  end
  if cfg then
    if cfg.inherit then
      data = vim.tbl_extend('keep', data, cfg.inherit[DATA])
      cfg = vim.tbl_extend('keep', cfg, cfg.inherit[M.CONFIG] or {})
    end
    data[M.CONFIG] = cfg
  end
  return setmetatable({ [DATA] = data }, Compiled)
end

--- @param tbl { [string]: any, [integer]: any }
--- @param defaults? { [string]: any }
--- @return { [string]: any }
--- @return any[]
--- @return { [string]: any }
function Compiled:parse(tbl, defaults)
  tbl = vim.tbl_extend("keep", tbl, defaults or {})
  local opts = {}
  local args = {}
  local rest = {}
  local data = self[DATA]
  local config = data[M.CONFIG] or {}

  for k, v in pairs(tbl) do
    local kty = type(k)
    local ver = data[k]
    if kty == 'number' and ver == nil then
      ver = data[M.ARGS]
    end
    if ver == nil then
      if kty == 'number' then
        if not config.allow_unknown_elements then
          error("unknown extra element [" .. k .. "]: " .. vim.inspect(v))
        end
      else
        if not config.allow_unknown_options then
          error("unknown key: " .. k)
        end
      end
      rest[k] = v
      goto next
    end
    local valid, val = ver(v)
    if not valid then
      local expected, obj = unpack(val)
      error("invalid option " .. k .. ": expected " .. expected .. ": " .. vim.inspect(obj))
    end
    if kty == 'number' then
      args[k] = val
    else
      opts[k] = val
    end
    ::next::
  end

  return opts, args, rest
end

--- @param buffer any
--- @return bool
--- @return any | chorus.spec.TypeErr
function M.buffer(buffer)
  if type(buffer) == 'number' then
    return true, buffer
  elseif buffer == true then
    return true, 0
  elseif buffer == false then
    return true, nil
  else
    return false, {'number, boolean', buffer}
  end
end

return M
