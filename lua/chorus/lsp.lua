local M = {}
local keymap = require 'chorus.keymap'
local util = require 'chorus.util'

--- LSP settings for a particular language server
---
--- See Neovim documentation for available settings
--- @class chorus.lsp.Subconfig: vim.lsp.Config
--- @field keymap? chorus.keymap.Spec Keymap to apply when this language server attaches to a buffer
--- @field inherit? boolean Inherit from global and base (nvim-lspconfig) settings (default `true`)

--- LSP settings for one or more languages
--- @class chorus.lsp.Config
--- @field global? chorus.lsp.Subconfig Common settings for all language servers configured by `chorus.lsp`
--- @field common? chorus.lsp.Subconfig Common settings for all language servers in this table
--- @field [string] chorus.lsp.Subconfig Settings for particular language servers

local function chain(common, specific)
  return function(...)
    common(...)
    specific(...)
  end
end

local function apply_keymap(map)
  return function(_, bufnr)
    keymap.set(map, bufnr)
  end
end

--- @type chorus.lsp.Subconfig
local global = vim.lsp.config['*'] or {}
--- @type { [string]: chorus.lsp.Subconfig }
local specific = {}

local cb_names = {'before_init', 'on_attach', 'on_init', 'on_exit', 'on_error'}

--- Configure LSP settings
---
--- Also available by invoking the [`lsp`](chorus.lsp) module as a function.
---
--- May be called multiple times to configure different servers.  Providing the
--- same server or the `global` key more than once replaces the prior settings
--- for that key.
---
--- Base (nvim-lspconfig), global, common, and specific settings are merged (as
--- by `vim.tbl_deep_extend`) when applied. In addition, the following
--- callbacks are merged so that all versions from the mentioned sources are
--- run in order:
--- - `before_init`
--- - `on_attach` (including any `keymap`)
--- - `on_init`
--- - `on_exit`
--- - `on_error`
---
--- Merging can be disabled by setting `inherit = false` for a particular
--- language server.
---
--- @param config chorus.lsp.Config Configuration
function M.setup(config)
  --- @type chorus.lsp.Subconfig
  local common = util.copy(config.common or {})
  --- @type chorus.lsp.Subconfig
  local globl = util.copy(config.global or {})

  for _, special in ipairs { common, globl } do
    if special.keymap then
      if special.on_attach then
        special.on_attach = chain(special.on_attach, apply_keymap(special.keymap))
      else
        special.on_attach = apply_keymap(special.keymap)
      end
      special.keymap = nil
    end
  end

  global = globl

  for k, v in pairs(config) do
    --- @cast k +string
    if k ~= 'common' and k ~= 'global' and k ~= 'keymap' then
      --- @cast v -chorus.keymap.Spec
      local merge = vim.tbl_deep_extend('force', common, v)
      for _, name in ipairs(cb_names) do
        local composed = nil
        for _, src in ipairs { common, v } do
          local func = src[name]
          --- @cast func function?
          if func then
            if composed then
              composed = chain(composed, func)
            else
              composed = func
            end
          end
        end
        if composed then
          merge[name] = composed
        end
      end
      specific[k] = merge
    end
  end
end

function M.apply()
  for k, v in pairs(specific) do
    if v.inherit == nil or v.inherit then
      local base = vim.lsp.config[k] or {}
      --- @type chorus.lsp.Subconfig
      local merge = vim.tbl_deep_extend('force', base, global, v)
      merge.keymap = nil
      merge.inherit = nil
      for _, name in ipairs(cb_names) do
        --- @type function?
        local composed = nil
        for _, src in ipairs { base, global, v } do
          local func = src[name]
          if func then
            if composed then
              composed = chain(composed, func)
            else
              composed = func
            end
          end
        end
        if composed then
          merge[name] = composed
        end
      end
      v = merge
    else
      v = util.copy(v)
      v.keymap = nil
      v.inherit = nil
    end
    --- @cast v vim.lsp.Config
    vim.lsp.config[k] = v
    vim.lsp.enable(k)
  end
end

local mt = {
  __call = function(_, tbl) M.setup(tbl) end
}

setmetatable(M, mt)
return M
