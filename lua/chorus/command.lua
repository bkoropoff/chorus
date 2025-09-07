function update(fargs)
  local autocmd = require 'chorus.autocmd'

  local ac = autocmd {
    once = true,
    'FileType',
    'nvim-pack',
    function(args)
      local write_ac = vim.api.nvim_get_autocmds {
        event = 'BufWriteCmd',
        buffer = args.buf
      }[1]
      if not write_ac then
        error("Could not find BufWriteCmd autocmd to override")
      end
      local cb = write_ac.callback
      local id = write_ac.id
      if not cb or not id then
        error("Could not find expected BufWriteCmd autocmd attributes")
      end
      autocmd.delete(id)
      autocmd {
        {
          buffer = args.buf,
          'BufWriteCmd',
          function()
            vim.cmd.quit()
            vim.notify("Restart Neovim to apply updates", vim.log.levels.INFO)
          end
        },
        {
          group = 'chorus.finish',
          clear = true,
          'VimLeavePre',
          cb
        }
      }
    end
  }

  local ok, err = pcall(function() vim.pack.update(#fargs ~= 0 and fargs or nil) end)
  if not ok then
    vim.api.nvim_del_autocmd(ac)
    error(err, 0)
  end
end

local ops = {
  update = update
}

function command(args)
  fargs = args.fargs
  op = table.remove(fargs, 1)
  func = ops[op]
  if not func then
    vim.notify("No such operation: " .. op, vim.log.levels.ERROR)
    return
  end
  func(fargs)
end

return command
