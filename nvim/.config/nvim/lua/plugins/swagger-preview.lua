return {
  "vinnymeller/swagger-preview.nvim",
  -- Global installation is required because swagger-preview.nvim expects 'swagger-ui-watcher' to be available as a CLI tool in the PATH.
  -- Check if 'swagger-ui-watcher' is already installed globally before installing.
  build = vim.fn.executable("npm") == 1 and "sh -c 'npm list -g swagger-ui-watcher >/dev/null 2>&1 || npm install -g swagger-ui-watcher'" or nil,
  -- Only enable if npm is available
  cond = function()
    return vim.fn.executable("npm") == 1
  end,
  config = true,
}
