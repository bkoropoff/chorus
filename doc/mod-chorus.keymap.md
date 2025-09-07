# Keymaps

The `keymap` module declaratively defines key mappings. Nested tables with
option and prefix inheritance let you create concise configurations, but flat
syntax (or a combination) is also available if readability is more important.

## Example

Maximal use of nesting:
```lua
keymap {
  -- Options can be set at any level and are inherited by nested tables
  unique = true,
  -- First level specifies the mode or modes
  n = {
    -- Subsequent levels specify prefixes and mappings
    ["<leader>"] = {
      f = {
        silent = true,
        f = { "<cmd>Telescope find_files<CR>", desc = "Find Files" },
        g = { "<cmd>Telescope live_grep<CR>", desc = "Live Grep" },
      },
      b = {
        l = { "<cmd>ls<CR>", desc = "List Buffers" },
        d = { "<cmd>bd<CR>", desc = "Delete Buffer" },
      }
    }
  }
} 
```

Flat syntax:
```lua
keymap {
   -- Modes and entire key sequence in one go
   ["vn <leader>gb"] = "<cmd>Git blame<CR>"
}
```

## Reference

```{lua:autoobject} chorus.keymap
