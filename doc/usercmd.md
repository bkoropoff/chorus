# User Commands

The `chorus.usercmd` module defines user commands declaratively.

## Example

```lua
usercmd {
  Hello = {
    desc = "Print Hello",
    nargs = 0,
    "echo 'Hello, world!'"
  },
  Format = {
    desc = "Run LSP formatting",
    nargs = 0,
    range = "%",
    function()
      vim.lsp.buf.format()
      print("Formatting complete.")
    end
  }
}
```

You can use positional syntax for the name, if you prefer:

```lua
usercmd {
   desc = "Print Goodbye",
   nargs = 0
   "Goodbye",
   function()
     print("Goodbye, world!")
   end
}
```
