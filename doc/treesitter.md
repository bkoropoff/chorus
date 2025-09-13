# Treesitter

The `chorus.treesitter` module enables treesitter parsers and features declaratively.

## Example

```lua
-- Defer until opening a c/cpp file for the first time
filetype { "c", "cpp" }

-- Enable c/cpp with default features (everything)
treesitter { "c", "cpp" }
```
