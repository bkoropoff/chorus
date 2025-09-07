# LSP Settings

The `lsp` module declaratively configures and enables the built-in Neovim LSP
client. One difference from using `vim.lsp.config` directly is that callbacks
from lspconfig-provided, global, common, and per-server configurations are
combined rather than replacing each other.

## Example

`config/lsp.lua`:
```lua
-- Get server configurations provided by nvim-lspconfig
chorus {
  "neovim/nvim-lspconfig"
}

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
`config/python.lua`:
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
## Reference

```{lua:autoobject} chorus.lsp
