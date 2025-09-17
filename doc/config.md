# Configuration Structure

## Overview

The main `chorus` module lets you run a collection of self-contained
configuration files, each independently specifying which packages it requires.
Required packages from all files are batched into efficient calls to
`vim.pack.add` so that installation and building occur in parallel.

[`chorus.setup`](chorus.setup), usually invoked from `init.lua`, specifies
a set of configuration files to run.

To make your configuration compact, Chorus injects its modules and functions
into the environment so you don't need to explicitly `require` them.  This
can be overridden with the `prelude` option.

### Example: `init.lua`
```lua
-- Leader key must be set early
vim.keymap.set('n', '<Space>', '<Nop>', { noremap = true })
vim.g.mapleader = ' '

vim.pack.add({ 'https://github.com/bkoropoff/chorus' }, { confirm = false })

require 'chorus'.setup {
  -- Drop configuration files in `config/` in your Neovim config directory
  "config/*.lua",
  -- Override variables that will be added to config file environment without
  -- being explicitly `require`d. Defaults to everything: `chorus` and `chorus.*`
  prelude = {
     chorus = require 'chorus',
     filetype = require 'chorus'.filetype,
     keymap = require 'chorus'.keymap,
     lazy = require 'chorus'.lazy,
     lsp = require 'chorus'.lsp,
     need = require 'chorus'.need,
     provide = require 'chorus'.provide,
     treesitter = require 'chorus'.treesitter,
  }
}
```

## Using Packages

Within a configuration file, `chorus` invoked as a function (or `chorus.use`)
specifies one or more packages to use with a subset of Lazy.nvim syntax.
Execution is suspended so the packages can be installed, built, and set up (and
so other configuration files can specify their packages), then resumed when
ready.  If multiple files need the same package, the settings from each
(dependencies, options, etc.) are merged together. This allows one file to
specify the package in detail (with complicated dependencies and build rules)
while others simply reference it by name.

### Example: `config/blink.lua`
```lua
-- A blink.cmp configuration using a build command, eagerly loaded:
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
  }
}
```

## Dependencies

Although configuration files are intended to be independent, sometimes one will
end up needing setup performed by another.  One file can use
[`chorus.provide`](chorus.provide) to indicate that it provides some abstract
capability in your configuration, and another can wait for it to finish running
with [`chorus.need`](chorus.need).

### Example: `config/colorscheme.lua`
```lua
-- Suspend until needed (by file below)
provide "colorscheme"

-- Install and configure color scheme
chorus {
  "catppuccin/nvim",
  name = "catppuccin"
}
vim.cmd.colorscheme "catppucin"
```

### Example: `config/lualine.lua`
```lua
-- Install packages for lualine
chorus {
  'nvim-lualine/lualine.nvim',
  'nvim-tree/nvim-web-devicons'
}

-- Color scheme needs to be set before configuring lualine
need "colorscheme"

require 'lualine'.setup {
 ...
}
```

## Lazy Loading

Although packages should ideally lazy load themselves internally, some don't.
You may also want to avoid setting up packages entirely until you need them.
Finally, there might be filetype-specific setup that you want to perform only
once rather than on every buffer load, and you want a convenient way to do it.
Chorus provides various mechanisms to accomplish all of these, if you care to
leverage them.

### Lazy Imports and Configuration

[`chorus.lazy`](chorus.lazy) allows lazily importing Lua modules or computing
values, as well as designating a portion of a configuration file as lazily
executed. The configuration file is suspended at that point until a lazy import
or value is accessed (e.g. from a keymap), at which point execution resumes,
the lazy import or value is resolved, and whatever triggered it continues on.
This can go as far as installing packages on the fly.

#### Example: `config/neo-tree.lua`
```lua
-- A somewhat involved, lazy-loaded neo-tree configuration:

-- Lazily require module
local cmd = lazy 'neo-tree.command'

-- Helper function for keymap
local function execute(args)
  return function()
    cmd.execute(args)
  end
end

-- Configure keymaps.  By using the lazy import, they will
-- automatically trigger lazy loading
keymap {
  ["n <leader>s"] = {
    b = execute { source = "buffers" },
    f = execute { source = "filesystem" },
    d = execute { source = "diagnostics" },
    s = execute { source = "document_symbols" },
    c = execute { action = "close" }
  }
}

-- Defer remainder of file until triggered by keymap
lazy()

-- Install and configure neo-tree packages
chorus {
  ["nvim-neo-tree/neo-tree.nvim"] = {
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons"
    },
    opts = {
      ...
  },
  ["mrbjarksen/neo-tree-diagnostics.nvim"] = {
    dependencies = "nvim-neo-tree/neo-tree.nvim"
  },
}
```

### Filetypes

Using [`chorus.filetype`](filetype), you can suspend a configuration file until
the one of the specified file types is first loaded, at which point execution
resumes to perform one-time configuration.  Consult the documentation for
additional features and modules related to configuring filetypes (particularly
Treesitter and LSP).

```{note}
For per-buffer configuration on every file load, use `ftplugin/` files or
`FileType` autocommands as usual.
```

#### Example: `config/help.lua`
```lua
-- Lazy one-time VIM help file configuration
filetype "help"

-- Set up autocommands for VIM help
autocmd {
  group = "me.help",
  -- Since we set up autocommand lazily, apply it to current buffer
  apply = true,
  "FileType", "help",
  function()
    keymap {
      buffer = true,
      ["n q"] = vim.cmd.quit
    }
  end
}
```

## Errors

If package installation, building, or setup fails, all configuration files
requiring the package bail out with an error (which can be caught with `pcall`
if desired) while others proceed, so as much of your configuration is
remains functional as possible.

```{warning}
`vim.pack` doesn't currently support detecting individual package
installation failures, so any package failing to install will cause all
configuration files that require packages to bail out
```
