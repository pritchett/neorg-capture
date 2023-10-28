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
      return { template = item.name, file = item.file, headline = item.headline, path = item.path, query = item.query, datetree = item.datetree }
    end

    local item_is_enabled = function(item)
      return item.enabled == nil or type(item.enabled) == 'function' and item.enabled(bufnr) or item.enabled
    end

    for _, item in ipairs(conf.templates) do
      if item_is_enabled(item) then
        if item.name and item.name ~= "" then
          table.insert(items, item.description)
          table.insert(data, build_data_entry(item))
        end
      end
    end

    return items, data
  end,

  on_save = function(bufnr, data)

    local save_file
    if type(data.file) == "function" then
      save_file = data.file()
    elseif type(data.file) == "string" then
      save_file = data.file
    else
      save_file = nil
    end

    if not save_file then
      vim.notify("No file set", vim.log.levels.ERROR)
      return false
    end

    save_file = save_file:gsub(".norg$", "")

    local path = nil
    vim.api.nvim_buf_call(data.calling_bufnr, function()
      path = module.required['core.dirman.utils'].expand_path(save_file)
    end)

    if not path then
      vim.notify("Could not determine target file path", vim.log.levels.ERROR)
      return
    end

    local already_open = vim.fn.bufexists(path) > 0
    local target_bufnr = vim.fn.bufnr(path, true)

    if not target_bufnr then
      vim.notify("Could not open or locate buffer for " .. path, vim.log.levels.ERROR)
      return
    end

    if not already_open then
      vim.api.nvim_buf_set_option(target_bufnr, "filetype", "norg")
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local ts = module.required['core.integrations.treesitter']

    local end_line = function(node)
      local child_count = node:child_count()
      if child_count > 0 then
        local child = node:child(child_count - 1)
        return child:end_()
      else
        return node:end_()
      end
    end

    local set_lines_and_write = function(end_linenr, insert_lines)
      vim.api.nvim_buf_set_lines(target_bufnr, end_linenr, end_linenr, false, insert_lines)
      vim.api.nvim_buf_call(target_bufnr, function()
        vim.cmd.write({ args = { path }, bang = true })
      end)
    end

    local cb_non_datetree = function(insert_lines)
      return function(query, id, node, _)
        if(query.captures[id] ~= "org-capture-target") then
          return false
        end
        local end_linenr = end_line(node)
        set_lines_and_write(end_linenr, insert_lines)
        return true -- Returning true makes `ts.execute_query` stop iterating over captures
      end
    end

    local get_headingnr = function(i)
      if i > 6 then
        return 6
      else
        return i
      end
    end

    local build_query = function(headline_path)
      local query = "("
      local end_parens = ""
      for i, headline in ipairs(headline_path) do
        local headingnr = get_headingnr(i)
        query = query .. "(heading" .. headingnr .. " title: (paragraph_segment) @t" .. i .. " (#eq? @t" .. i .. " \"" .. headline .. "\"" .. ") "
        end_parens = end_parens .. ")"
      end
      query = query ..  " ) @org-capture-target" .. end_parens
      return query
    end

    local exec_query = function(query_string, cb)
        local query = vim.treesitter.query.parse("norg", query_string)
        local root = ts.get_document_root(target_bufnr)

        if not root then
            return false
        end

        for id, node, metadata in query:iter_captures(root, target_bufnr) do
            if cb(query, id, node, metadata) == true then
                return true
            end
        end

        return false
    end

    local build_and_execute_query = function(path_or_headline, cb)
      if not path_or_headline or #path_or_headline == 0 then
        return true
      end
      local query = build_query(path_or_headline)
      return exec_query(query, cb)
    end

    local do_datetree = function(datetree_path)

      local cb_find_datetree_path = function(query, id, _, _)
        if(query.captures[id] ~= "org-capture-target") then
          return false
        end
        return true -- Returning true makes `ts.execute_query` stop iterating over captures
      end

      local dates = { os.date("%Y"), os.date("%Y-%m %B"), os.date("%Y-%m-%d %A") }

      for _, value in ipairs(dates) do
        table.insert(datetree_path, value)
      end

      local not_found = {}

      while not build_and_execute_query(datetree_path, cb_find_datetree_path) do
        local element = table.remove(datetree_path, #datetree_path)
        table.insert(not_found, 1, element)
      end

      local remaining_path = {}
      for i, remaining in ipairs(not_found) do
        table.insert(remaining_path, string.rep("*", #datetree_path + i) .. " " .. remaining)
      end

      if not #datetree_path == 0 then
        build_and_execute_query(datetree_path, cb_non_datetree(remaining_path))
      else
        set_lines_and_write(-1, remaining_path)
      end

      for _, value in ipairs(not_found) do
        table.insert(datetree_path, value)
      end

      build_and_execute_query(datetree_path, cb_non_datetree(lines))
    end

    if data.datetree then
      if (data.headline) then
        do_datetree({ data.headline })
      elseif data.path then
        do_datetree(data.path)
      else
        do_datetree({})
      end
    elseif data.headline then
      build_and_execute_query({ data.headline }, cb_non_datetree(lines))
    elseif data.path then
      build_and_execute_query(data.path, cb_non_datetree(lines))
    elseif data.query then
      exec_query(data.query, cb_non_datetree(lines))
    else
      set_lines_and_write(-1, lines) -- Negative one means the end of the file
    end
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
          headline = data[idx].headline,
          path = data[idx].path,
          query = data[idx].query,
          datetree = data[idx].datetree,
          calling_file = current_name,
          calling_bufnr = calling_bufnr,
          on_save = function(bufnr, passed_data) module.private.on_save(bufnr, passed_data) end
        }
      } )
    end)
  end
end

return module
