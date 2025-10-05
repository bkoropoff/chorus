# Chorus

Chorus is a declarative, modular configuration system for Neovim. Structure
your configuration as self-contained files that declare what packages they
require; Chorus executes them concurrently as coroutines and installs
packages as efficient batches with `vim.pack`.

```{note}
`vim.pack` will only become officially available in Neovim 0.12, so a nightly
build is currently necessary.
```

Chorus also includes several handy modules to configure Neovim features such as
options, keymaps, and LSP servers in a more declarative style.  These can be
used *a la carte* even if Chorus isn't used for package management.

## Getting Started

To set up Chorus, add it to your `init.lua`:

```lua
vim.pack.add({ 'https://github.com/bkoropoff/chorus' }, { confirm = false })

-- Drop configuration files in `config/` in your Neovim config directory
require 'chorus'.setup "config/*.lua"
```

A configuration file is ordinary Lua, but should declare which packages it
uses up front with [`chorus`](chorus.use), e.g. `config/lualine.lua`:

```lua
chorus {
  'nvim-lualine/lualine.nvim',
  'nvim-tree/nvim-web-devicons',
}

require 'lualine'.setup {
  ...
}

```

See [Configuration Structure](config) for details.

## Updating

To update packages, run:

```
:Chorus update
```

Accept the update with `:write` or dismiss it with `:quit`. This uses
`vim.pack.update`, but defers the actual checkout of git repositories until
Neovim exits to avoid disrupting running packages.

## Removing Unused Packages

To remove packages that aren't used, run:

```
:Chorus prune
```

This will implictly finish any configuration sources that have deferred
completion so that all packages that might be used by your configuration are
known.


## Syncing

To prune and update packages in one go:

```
:Chorus sync
```

```{toctree}
:maxdepth: 2
:caption: Contents

config
opt
keymap
autocmd
usercmd
filetype
api/index
