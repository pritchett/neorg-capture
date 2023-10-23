local neorg = require('neorg.core')

local module = neorg.modules.create('external.capture')

module.setup = function()
  return {
    success = true,
    requires = {
      'core.neorgcmd',
      'core.dirman',
      'core.dirman.utils',
      'external.templates',

    }
  }
end

module.config.public = {
  templates = {}
}

module.config.private = {
  gid = nil
}


module.load = function()
  module.required['core.neorgcmd'].add_commands_from_table({
    ['capture'] = {
      args = 0,
      name = 'external.capture.execute'
    }
  })

  local gid = vim.api.nvim_create_augroup("neorg-capture", { clear = true })
  module.config.private.gid = gid

  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "neorg-capture://*.norg",
    callback = function(args)
      local bufnr = args.buf
      vim.api.nvim_buf_set_option(bufnr, "filetype", "norg")
      vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
      vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
      vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("Neorg templates add " .. args.data.template)
      end)

      vim.api.nvim_create_autocmd("QuitPre", {
        buffer = bufnr,
        callback = function(_)
          return args.data.on_save(bufnr)
        end
      })

    end,
    group = gid
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = "neorg-capture://*.norg",
    callback = function(args)
      vim.api.nvim_buf_set_option(args.buf, 'modified', false)
    end,
    group = gid
  })

end

module.events.subscribed = {
    ['core.neorgcmd'] = {
        ['external.capture.execute'] = true
    }
}

module.private = {
  build_items = function(bufnr)
    local conf = module.config.public
    local items = {}
    local data = {}

    for _, item in ipairs(conf.templates) do
      if item.enabled == nil or type(item.enabled) == 'function' and item.enabled(bufnr) or item.enabled then
        if item.name and item.name ~= "" then
          table.insert(items, item.description)
          table.insert(data, { template = item.name, file = item.file })
        end
      end
    end

    return items, data
  end
}

module.on_event = function(event)

  if event.split_type[2] == 'external.capture.execute' then
    local items, data = module.private.build_items(event.buffer)
    if(#items == 0) then
      vim.notify("No active templates")
      return
    end

    local original_bufnr = vim.api.nvim_get_current_buf()

    vim.ui.select(items, { prompt = "Choose Template" }, function(_, idx)
      local current_name = vim.api.nvim_buf_get_name(0)
      local file = "neorg-capture://" .. data[idx].template .. "//" .. current_name .. ".norg"
      vim.cmd("noautocmd split " .. file)
      vim.api.nvim_exec_autocmds("BufReadCmd", {
        group = module.config.private.gid,
        pattern = file,
        data = {
          template = data[idx].template,
          calling_file = current_name,
          calling_bufnr = vim.api.nvim_get_current_buf(),
          on_save = function(bufnr)

            local save_file = data[idx].file:gsub(".norg$", "")
            if not save_file then
              vim.notify("No file set", vim.log.levels.ERROR)
              return false
            end

            vim.api.nvim_buf_call(original_bufnr, function()
              local path = module.required['core.dirman.utils'].expand_path(save_file)
              if not path then
                vim.notify("Some error", vim.log.levels.ERROR)
                return
              end

              local save_bufnr = vim.api.nvim_create_buf(false, false)
              vim.api.nvim_buf_call(save_bufnr, function()
                pcall(vim.cmd.read, path)
                local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                vim.api.nvim_buf_set_lines(0, -1, -1, false, lines)
                vim.cmd.write({ args = { path }, bang = true })
              end)
            end)
          end
        }
      } )
    end)
  end
end

return module
