local M = {}

M.CONFIG = {}
M.ARGS = {}

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

local function compile_verifier(obj)
  if vim.is_callable(obj) then
    return obj
  elseif vim.isarray(obj) then
    return verify_alternates(vim.tbl_map(compile_verifier, obj))
  elseif type(obj) == 'string' then
    return verify_type(obj)
  else
    error("expected callable, array, or string: " .. vim.inspect(obj))
  end
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

local DATA = {}

local Spec = {}
Spec.__index = Spec

function M.compile(spec_tbl)
  local data = {}
  --- @type table?
  local cfg = nil
  for k, v in pairs(spec_tbl) do
    if k == M.CONFIG then
      cfg = v
    else
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
  return setmetatable({ [DATA] = data }, Spec)
end

function Spec:parse(tbl, defaults)
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
