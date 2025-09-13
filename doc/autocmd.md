# Autocommands

The `chorus.autocmd` module defines autocommands and groups declaratively, with
nested syntax allowing common options to apply to multiple autocommands.

## Examples

Basic autocommand, using key-value syntax:

```lua
autocmd {
  event = "BufWritePre",
  pattern = "*.lua",
  callback = function(args)
    vim.notify("Saving: " .. args.file)
  end
}
```

You can also use positional arguments for greater brevity:

```lua
autocmd {
  -- event, pattern
  "BufWritePre", "*.lua",
  -- callback
  function(args)
    vim.notify("Saving: " .. args.file)
  end
}
```

Creating an autocommand group and clearing it first:

```lua
autocmd {
  group = "MyGroup",
  clear = true,
  -- event
  "BufReadPost"
  -- callback (not treated as pattern since it's not a string)
  function(args) print("Read: " .. args.file) end,
}
```

Defining multiple autocommands with shared options:

```lua
autocmd {
  {
    event = "BufEnter",
    -- Event is inherited, so [1] is treated as pattern
    { "*.txt", function(args) print("Entering txt: " .. args.file) end },
    { "*.md", function(args) print("Entering md: " .. args.file) end }
  }
}
```

Buffer-local autocommand:

```lua
autocmd {
  -- Current buffer
  buffer = true,
  event = "InsertLeave",
  -- Ex command instead of function
  command = "echo 'Left insert mode'"
}
```

Deleting an autocommand by ID (as returned by `autocmd`):

```lua
-- Multiple return values if multiple autocommands are defined
local id = autocmd {
  "BufWritePre",
  "*.tmp",
  function() print("About to save a .tmp file") end
}
autocmd.delete(id)
```
