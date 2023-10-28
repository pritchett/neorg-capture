



# Neorg Capture

\* **This README is generated from [./README.norg](./README.norg).**


## Usage

Set up a template with [neorg-templates](https://github.com/pysan3/neorg-templates)


## Installation

- [lazy.nvim](https://github.com/folke/lazy.nvim) installation
```lua
-- neorg.lua
local M = {
  "nvim-neorg/neorg",
  ft = "norg",
  dependencies = {
    { "pysan3/neorg-templates", dependencies = { "L3MON4D3/LuaSnip" } }, -- ADD THIS LINE
    { "pritchett/neorg-capture"},                                        -- ADD THIS LINE
  },
}
```


## Configuration

```lua
M.config = function ()
  require("neorg").setup({
    load = {
      ["external.templates"] = {
        ...
      },
      ["external.capture"] = {
        templates = {
          {
            description = "Example",   -- What will be shown when invoked
            name = "example",          -- Name of the neorg-templates template.
            file = "example",          -- Name of the target file for the caputure. With or without `.norg` suffix
                                       -- Can be a function. If a full filepath is given, thats where it will be save.
                                       -- If just a filename, it will be saved into your workspace.

            enabled = function()       -- Either a function or boolean value. Default is true.
              return true              -- If false, it will not be shown in the list when invoked.
            end,

            datetree = true,           -- Save the capture into a datetree. Default is false

            headline = "Example"       -- If set, will save the caputure under this headline
            path = { "Save", "Here" }  -- List of headlines to traverse, then save the capture under
            query =                    -- A query for where to place the capture. Must be named neorg-capture-target
              "(headline1) @neorg-capture-target"

          },
          ...
        }
      },
    }
  })
end
```

- Headlines take precedence over paths. If neither is set, the capture is set at the bottom of the target file.
- Datetrees can be combined with headlines or paths. 


## Contribution

- PRs are welcome
- Please follow code style defined in [./stylua.toml](./stylua.toml) using [StyLua](https://github.com/johnnymorganz/stylua).


## LICENSE

All files in this repository without annotation are licensed under the **GPL-3.0 license** as detailed in [LICENSE](LICENSE).

