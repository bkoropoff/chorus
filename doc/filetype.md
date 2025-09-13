# Filetype Handling

## Treesitter

The [`chorus.treesitter`](chorus.treesitter) module enables Treesitter parsers
and features declaratively.

### Example: `config/c.lua`

```lua
-- Enable c/cpp with default features (everything)
treesitter { "c", "cpp" }
```

## LSP Settings

The [`chorus.lsp`](chorus.lsp) module declaratively configures and enables the
built-in Neovim LSP client. One difference from using `vim.lsp.config` directly
is that callbacks from lspconfig-provided, global, common, and per-server
configurations are combined rather than replacing each other.

### Example: `config/lsp.lua`
```lua
-- Configure global LSP settings
lsp {
  global = {
    -- Only applies in LSP-attached buffers
    keymap = {
      ["n <leader>l"] = {
        a = { vim.lsp.buf.code_action, desc = "Code Action" },
        i = {
          function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
          end,
          desc = "Toggle Inlay Hints"
        }
      }
    }
  }
}
```

### Example: `config/python.lua`:
```lua
-- Configure python-related LSP settings
lsp {
  -- Applies to both servers listed here, but not globally
  common = {
    on_attach = function(client)
      print("LSP server attached:" .. client)
    end
  },
  basepyright = {}
  ruff = {}
}
```

## Combined Configuration

The [`chorus.filetype`](chorus.filetype) module suspends a configuration file
until the first time one of the specified file types is loaded, at which point
the remainder is executed to perform one-time configuration.  It can
additionally apply per-filetype Treesitter and LSP settings as a shortcut to
using those modules directly.

### Example: `config/rust.lua`
```lua
filetype {
  rust = {
    treesitter = true,
    lsp = {
      rust_analyzer = {
        settings = {
          ["rust-analyzer"] = {
            check = {
              command = "clippy"
            }
           }
        }
      }
    }
  }
}
```

### Example: `config/filetypes.lua`
```lua
-- Misc. filetypes combined into one configuration file
filetype {
  -- Default to enabling treesitter for all filetypes mentioned here
  treesitter = true,
  "json",
  "toml",
  "yaml",
  cmake = {
    lsp = {
      cmake = {}
    }
  },
  just = {
    lsp = { 
      just = {}
    }
  },
  dockerfile = {
    lsp = {
      dockerls = {}
    }
  },
  sh = {
    lsp = {
      bashls = {}
    }
  }
}
```
