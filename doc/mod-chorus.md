# Configuration

The main `chorus` module lets you run a collection of self-contained
configuration files, each independently specifying which packages it requires.
Required packages from all files are batched into efficient calls to
`vim.pack.add` so that installation and building occur in parallel.

[`chorus.setup`](chorus.setup), usually invoked from `init.lua`, specifies
a set of configuration files to run.

Within a configuration file, `chorus` invoked as a function (or `chorus.use`)
specifies one or more packages to use with a subset of Lazy.nvim syntax.
Execution is suspended so the packages can be installed, built, and set up (and
so other configuration files can specify their packages), then resumed when
ready.  If multiple files need the same package, the settings from each
(dependencies, options, etc.) are merged together. This allows one file to
specify the package in detail (with complicated dependencies and build rules)
while other simply reference it by name.

If package installation, building, or setup fails, all configuration files
requiring the package bail out with an error (which can be caught with `pcall`
if desired) while others proceed, so as much of your configuration is
remains functional as possible.

```{warning}
`vim.pack` doesn't currently support detecting individual package
installation failures, so any package failing to install will cause all
configuration files that require packages to bail out
```

## Example

`init.lua`:
```lua
-- Leader key must be configured set early
vim.keymap.set('n', '<Space>', '<Nop>', { noremap = true })
vim.g.mapleader = ' '

vim.pack.add({ 'https://github.com/bkoropoff/chorus' }, { confirm = false })

require 'chorus'.setup {
  -- Drop configuration files in `config/` in your Neovim config directory
  sources = 'config/*.lua',
  -- Override variables that will be added to config file environment without
  -- being explicitly `require`d. Defaults to `chorus` and `chorus.*`
  prelude = {
     chorus = require 'chorus'
  }
}
```

`config/neo-tree.lua`:
```lua
-- A somewhat involved neo-tree configuration:
chorus {
  ["nvim-neo-tree/neo-tree.nvim"] = {
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons"
    },
    opts = {
      sources = { "filesystem", "buffers", "diagnostics", "document_symbols" },
      window = {
        mappings = {
          ["<space>"] = "nop",
          ["<tab>"] = "toggle_node"
        }
      },
      document_symbols = {
        kinds = {
          Variable = {
            icon = ''
          }
        }
      }
    }
  },
  ["mrbjarksen/neo-tree-diagnostics.nvim"] = {
    dependencies = {
      "nvim-neo-tree/neo-tree.nvim"
    }
  },
}

local cmd = require 'neo-tree.command'

local function execute(args)
  return function()
    cmd.execute(args)
  end
end

keymap {
  ["n <leader>s"] = {
    b = execute { source = "buffers" },
    f = execute { source = "filesystem" },
    d = execute { source = "diagnostics" },
    s = execute { source = "document_symbols" },
    c = execute { action = "close" }
  }
}
```

`config/blink.lua`:
```lua
-- A blink.cmp configuration using a build command:
chorus {
  'saghen/blink.cmp',
  build = "cargo build --release",
  opts = {
    completion = {
      menu = {
        auto_show = false
      }
    },
    cmdline = {
      enabled = false
    },
    keymap = {
      preset = "none",
      ["<Tab>"] = {"select_next", "fallback"},
      ["<S-Tab>"] = {"show", "select_prev", "fallback"},
      ["<CR>"] = {"accept", "fallback"},
      ["<Esc>"] = {"cancel", "fallback"}
    }
  }
}
```

## Reference

```{lua:autoobject} chorus
```
