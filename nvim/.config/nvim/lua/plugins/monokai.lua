return {
  {
    "tanvirtin/monokai.nvim",
    lazy = false,
    name = "monokai",
    priority = 1000,

    config = function()
      -- Custom palette based on VSCode Monokai Dimmed colors
      local dimmed_palette = {
        name = "monokai_dimmed",
        base1 = "#1e1e1e",  -- VSCode background
        base2 = "#272727",  -- Sidebar background
        base3 = "#303030",  -- Line highlight
        base4 = "#525252",  -- Comments
        base5 = "#676b71",  -- Selection
        base6 = "#c5c8c6",  -- Foreground
        base7 = "#f8f8f2",  -- Bright foreground
        white = "#e3e3dd",
        grey = "#666666",
        black = "#1e1e1e",
        pink = "#f92672",      -- VSCode Bright Red
        green = "#A6E22E",     -- VSCode Bright Green
        aqua = "#66D9EF",      -- VSCode Bright Cyan
        yellow = "#e2e22e",    -- VSCode Bright Yellow
        orange = "#c07020",    -- VSCode Cursor color
        purple = "#AE81FF",    -- VSCode Bright Magenta
        red = "#C4265E",       -- VSCode Red
      }

      require("monokai").setup({
        palette = dimmed_palette,
        custom_hlgroups = {
          -- Match VSCode Monokai Dimmed background
          Normal = { bg = dimmed_palette.base1, fg = dimmed_palette.base6 },
          NormalFloat = { bg = dimmed_palette.base2 },
        }
      })
    end
  }
}
