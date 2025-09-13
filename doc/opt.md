# Options

The `chorus.opt` module defines options declaratively.  It is a very direct
wrapper around `vim.opt` and `vim.bo`.

## Example

Basic option tweaking:
```lua
opt {
  expandtab = true,
  softtabstop = 4,
  shiftwidth = { set = 4 }, -- Alternate set syntax
  wildmode = { "longest", "list" },
  wildignore = { remove = { "node_modules" } },
  whichwrap = { append = "h,l,<,>,[,]" },
  shortmess = { prepend = "I" }
}
```

Set buffer-local options:
```lua
opt {
  buffer = true,
  buflisted = true,
  bufhidden = 'delete'
}
```
