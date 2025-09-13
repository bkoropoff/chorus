--- Treesitter Support
local M = {}

local cspec = require 'chorus._spec'
local util = require 'chorus._util'

--- @type { [string]: string[] }
local ftmap = {
  asm68k = { "m68k" },
  automake = { "make" },
  bib = { "bibtex" },
  bzl = { "starlark" },
  clientscript = { "runescript" },
  confini = { "ini" },
  cook = { "cooklang" },
  cs = { "c_sharp" },
  dosini = { "ini" },
  dsp = { "faust" },
  dts = { "devicetree" },
  ecma = { "javascript" },
  eelixir = { "eex" },
  eruby = { "embedded_template" },
  expect = { "tcl" },
  fsd = { "facility" },
  gdresource = { "godot_resource" },
  gdshaderinc = { "gdshader" },
  gitconfig = { "git_config" },
  gitdiff = { "diff" },
  gitrebase = { "git_rebase" },
  gyp = { "python" },
  handlebars = { "glimmer" },
  haskellpersistent = { "haskell_persistent" },
  help = { "vimdoc" },
  htmlangular = { "angular" },
  ["html.handlebars"] = { "glimmer" },
  html_tags = { "html" },
  idris2 = { "idris" },
  janet = { "janet_simple" },
  ["javascript.glimmer"] = { "glimmer_javascript" },
  javascriptreact = { "javascript" },
  jproperties = { "properties" },
  jsx = { "javascript" },
  ld = { "linkerscript" },
  lisp = { "commonlisp" },
  mysql = { "sql" },
  neomuttrc = { "muttrc" },
  ocamlinterface = { "ocaml_interface" },
  pbtxt = { "textproto" },
  poefilter = { "poe_filter" },
  ps1 = { "powershell" },
  qml = { "qmljs" },
  sbt = { "scala" },
  sface = { "surface" },
  shaderslang = { "slang" },
  sh = { "bash" },
  sshconfig = { "ssh_config" },
  svg = { "xml" },
  systemd = { "ini" },
  tal = { "uxntal" },
  tape = { "vhs" },
  ["terraform-vars"] = { "terraform" },
  tex = { "latex" },
  tla = { "tlaplus" },
  trace32 = { "t32" },
  ["typescript.glimmer"] = { "glimmer_typescript" },
  typescriptreact = { "tsx" },
  ["typescript.tsx"] = { "tsx" },
  udevrules = { "udev" },
  verilog = { "systemverilog" },
  vlang = { "v" },
  vto = { "vento" },
  xdefaults = { "xresources" },
  xsd = { "xml" },
  xslt = { "xml" },
}

--- Treesitter options
--- @class chorus.treesitter.Opts
--- @field fold? boolean Enable code folding.  Default: `true`
--- @field highlight? boolean Enable highlighting.  Default: `true`
--- @field indent? boolean Enable indenting.  Default: `true`

--- Treesitter parsers and options
--- @class chorus.treesitter.Parsers: chorus.treesitter.Opts
--- @field [integer] string Parsers

--- Treesitter specification
--- @class chorus.treesitter.Spec : chorus.treesitter.Opts
--- @field [string] chorus.treesitter.Parsers | string Parsers for filetypes
--- @field [integer] string Filetypes (default parsers)


--- @class chorus.treesitter.Parsed
--- @private
--- @field [string] chorus.treesitter.Parsers

local opt_spec = cspec.compile {
  fold = 'boolean',
  highlight = 'boolean',
  indent = 'boolean'
}

local parser_spec = cspec.compile {
  [cspec.ARGS] = 'string',
  [cspec.CONFIG] = {
    inherit = opt_spec
  }
}

local spec_spec = cspec.compile {
  [cspec.ARGS] = {'string', 'table'},
  [cspec.CONFIG] = {
    inherit = opt_spec,
    allow_unknown_options = true
  }
}

local defaults = {
  fold = true,
  highlight = true,
  indent = true
}

--- @return chorus.treesitter.Parsed
local function parse_spec(spec)
  --- @type chorus.treesitter.Parsed
  local out = {}
  local opts, args, rest = spec_spec:parse(spec, defaults)

  for _, v in ipairs(args) do
    out[v] = vim.tbl_extend('keep', ftmap[v] or { v }, opts)
  end

  for k, v in pairs(rest) do
    if type(v) ~= 'table' then
      v = { v }
    end
    local subopts, subargs = parser_spec:parse(v, opts)
    --- @type chorus.treesitter.Parsers
    local parsers = vim.tbl_extend('keep', subargs, subopts)
    out[k] = parsers
  end

  return out
end

local function ensure(parsers)
  local chorus = require 'chorus'

  if chorus.did_setup then
    chorus.setup(function()
      chorus { 'nvim-treesitter/nvim-treesitter' }
    end)
  end

  return require 'nvim-treesitter'.install(util.retract(parsers, 'highlight', 'fold', 'indent'))
end


local did_once = false

--- Enable treesitter
---
--- Also available by invoking [`chorus.treesitter`](./chorus.treesitter) as a
--- function (or just `treesitter` with the default prelude)
---
--- Registers `FileType` autocommands to install parsers and
--- enable treesitter features.
---
--- @param spec chorus.treesitter.Spec | string Specification
function M.enable(spec)
  local chorus = require 'chorus'
  if chorus.in_setup or chorus.did_setup then
    -- Define package, but don't add it yet
    if not did_once then
      chorus {
        'nvim-treesitter/nvim-treesitter',
        build = function()
          require 'nvim-treesitter.install'.update()
        end,
        branch = 'main',
        add = false,
      }
      -- Add package on flush, however
      chorus.fork(function()
        chorus.lazy()
        chorus { 'nvim-treesitter/nvim-treesitter' }
      end)
      did_once = true
    end
  end

  if type(spec) ~= 'table' then
    --- @cast spec -chorus.treesitter.Spec
    local wrap = { spec }
    --- @cast wrap chorus.treesitter.Spec
    spec = wrap
  end
  local parsed = parse_spec(spec)
  local autocmd = require 'chorus.autocmd'
  for ft, parsers in pairs(parsed) do
    local ftconcat = type(ft) == 'table' and table.concat(ft, ".") or ft
    local group = 'chorus.treesitter.' .. ftconcat

    autocmd {
      group = group,
      event = 'FileType',
      pattern = ft,
      apply = true,
      desc = "Chorus treesitter support: " .. vim.inspect(ft),
      function(args)
        local buf = args.buf
        local win = vim.api.nvim_get_current_win()

        ensure(parsers):await(function(err, res)
          if err or not res then
            return
          end

          if parsers.highlight then
            vim.treesitter.start(buf, parsers[1])
          end
          if parsers.fold and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_win_call(win, function()
              vim.api.nvim_buf_call(buf, function()
                vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
              end)
            end)
          end
          if parsers.indent then
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end)
      end
    }
  end
end

local mt = {}
--- @async
function mt:__call(spec)
  return M.enable(spec)
end

setmetatable(M, mt)
return M
