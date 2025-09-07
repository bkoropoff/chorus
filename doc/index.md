# Chorus

Chorus is a declarative, modular configuration system for Neovim. Structure
your configuration as self-contained files that declare what packages they
require; Chorus executes them "simultaneously" as coroutines and installs
packages as efficient batches with `vim.pack`.

## Getting Started

To set up Chorus, add it to your `init.lua`:

```lua
vim.pack.add({ 'https://github.com/bkoropoff/chorus' }, { confirm = false })

require 'chorus'.setup {
  -- Drop configuration files in `config/` in your Neovim config directory
  sources = 'config/*.lua',
}
```
See [Configuration](mod-chorus) for details.

## Updating

To update packages, run `:Chorus update`.  Accept the update with `:write` or
dismiss it with `:quit`. This uses `vim.pack.update`, but defers the actual
checkout of git repositories until Neovim exits to avoid disrupting running
packages.

```{toctree}
:maxdepth: 2
:caption: Contents

mod-chorus
mod-chorus.opt
mod-chorus.keymap
mod-chorus.autocmd
mod-chorus.usercmd
mod-chorus.lsp
