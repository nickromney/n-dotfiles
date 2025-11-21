return {
  "vinnymeller/swagger-preview.nvim",
  -- Only build if npm is available
  build = vim.fn.executable("npm") == 1 and "npm install -g swagger-ui-watcher" or nil,
  -- Only enable if npm is available
  cond = function()
    return vim.fn.executable("npm") == 1
  end,
  config = true,
}
