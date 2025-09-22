# Filetype Handling

## Treesitter

The [`chorus.treesitter`](chorus.treesitter) module enables Treesitter parsers
and features declaratively.

### Example: `config/c.lua`

```lua
-- Enable c/cpp with default features (everything)
treesitter { "c", "cpp" }
```

### Example: `config/markdown.lua`

```lua
-- Fine-grained control
treesitter {
  markdown = {
    -- Options
    highlight = true, -- Enable highlighting (default)
    indent = false -- Disable indenting
    fold = false -- Disable folding
    -- Specific parsers.  The first is used for the filetype,
    -- additional ones are installed so they are available for injections
    -- (e.g. within code blocks)
    "markdown",
    "javascript"
  }
}
```

## LSP Settings

The [`chorus.lsp`](chorus.lsp) module declaratively configures and enables the
built-in Neovim LSP client for a set of servers. Syntax for individual server
configuration is nearly the same as `vim.lsp.config`, with these differences:

- The `keymap` key specifies a [`chorus.keymap`](keymap) spec to apply
upon attaching to a buffer as a shortcut.
- Global configuration uses the `global` key instead of `*`.
- Servers configured together can share configuration from a `common` key (in
addition to inheriting global settings)
- Callbacks from lspconfig-provided, global, common, and per-server
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
      print("LSP server attached:" .. client.name)
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
  -- Default to enabling treesitter without folding
  -- for all filetypes mentioned here
  treesitter = { fold = false },
  "json",
  "toml",
  "yaml",
  cmake = {
    -- Turn folding on for this particular filetype
    treesitter = { fold = true },
    lsp = {
      cmake = {}
    }
  },
  sh = {
    lsp = {
      bashls = {}
    }
  }
}
```

### Example: `config/c.lua`
```lua
-- Keys can be multiple filetypes that share the same settings
filetype {
  [{"c", "cpp"}] = {
    treesitter = true,
    lsp = {
      ccls = {}
    },
  }
}
```
