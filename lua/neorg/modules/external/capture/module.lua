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
      'core.integrations.treesitter'
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
          return args.data.on_save(bufnr, args.data)
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

    local build_data_entry = function(item)
      return { template = item.name, file = item.file, type = item.type, headline = item.headline }
    end

    local item_is_enabled = function(item)
      return item.enabled == nil or type(item.enabled) == 'function' and item.enabled(bufnr) or item.enabled
    end

    for _, item in ipairs(conf.templates) do
      if item.type then
        if item_is_enabled(item) then
          if item.name and item.name ~= "" then
            table.insert(items, item.description)
            table.insert(data, build_data_entry(item))
          end
        end
      end
    end

    return items, data
  end,

  on_save = function(bufnr, data)

    local save_file = data.file and data.file:gsub(".norg$", "")
    if not save_file then
      vim.notify("No file set", vim.log.levels.ERROR)
      return false
    end

    vim.api.nvim_buf_call(data.calling_bufnr, function()
      local path = module.required['core.dirman.utils'].expand_path(save_file)
      if not path then
        vim.notify("Some error", vim.log.levels.ERROR)
        return
      end

      local save_bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_call(save_bufnr, function()
        pcall(vim.cmd.read, path)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        if data.type == "entry" then

          if data.headline then
            local ts = module.required['core.integrations.treesitter']
            local query = "( (heading1 title: (paragraph_segment) @title_text) (#eq? @title_text " .. data.headline .. ") ) @next-segment"

            local end_line = function(node, child_count)
              if child_count > 0 then
                local child = node:child(child_count - 1)
                return child:end_()
              else
                return node:end_()
              end
            end

            local cb = function(_, _, node, _)
              local child_count = node:child_count()
              local end_linenr = end_line(node, child_count)
              vim.api.nvim_buf_set_lines(0, end_linenr, end_linenr, false, lines)
              vim.cmd.write({ args = { path }, bang = true })
              return true
            end

            ts.execute_query(query, cb, save_bufnr)
          else
            vim.api.nvim_buf_set_lines(0, -1, -1, false, lines)
            vim.cmd.write({ args = { path }, bang = true })
          end

        end
      end)
    end)

  end
}

module.on_event = function(event)

  if event.split_type[2] == 'external.capture.execute' then
    local items, data = module.private.build_items(event.buffer)
    if(#items == 0) then
      vim.notify("No active templates")
      return
    end

    local calling_bufnr = vim.api.nvim_get_current_buf()
    vim.ui.select(items, { prompt = "Choose Template" }, function(_, idx)
      local current_name = vim.api.nvim_buf_get_name(0)
      local file = "neorg-capture://" .. data[idx].template .. "//" .. current_name .. ".norg"
      vim.cmd("noautocmd split " .. file)
      vim.api.nvim_exec_autocmds("BufReadCmd", {
        group = module.config.private.gid,
        pattern = file,
        data = {
          template = data[idx].template,
          file = data[idx].file,
          type = data[idx].type,
          headline = data[idx].headline,
          calling_file = current_name,
          calling_bufnr = calling_bufnr,
          on_save = function(bufnr, passed_data) module.private.on_save(bufnr, passed_data) end
        }
      } )
    end)
  end
end

return module
