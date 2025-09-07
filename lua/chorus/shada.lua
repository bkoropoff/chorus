local mt = {}

local M = {}

local TABLE_NAME = 'CHORUS_SHADA'

local cache = nil

local function init()
  vim.cmd.rshada()
  return vim.g[TABLE_NAME] or vim.empty_dict()
end

function mt:__index(key)
  if cache == nil then
    cache = init()
  end
  return cache[key]
end

function mt:__newindex(key, value)
  if cache == nil then
    cache = init()
  end
  cache[key] = value
end

function M.flush(write)
  vim.g[TABLE_NAME] = cache
  if write then
    vim.cmd.wshada()
  end
  cache = nil
end

setmetatable(M, mt)
return M
