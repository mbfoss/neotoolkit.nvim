local plenary_dir = os.getenv("NVIM_PLENARY_DIR") or "/tmp/plenary.nvim"

local plugin_file = plenary_dir .. "/plugin/plenary.vim"
if vim.fn.filereadable(plugin_file) == 0 then
  if vim.fn.isdirectory(plenary_dir) == 1 then
    print("removing incomplete plenary clone at " .. plenary_dir)
    vim.fn.delete(plenary_dir, "rf")
  end
  print("cloning plenary into " .. plenary_dir)
  local out = vim.fn.system({
    "git", "clone", "--depth", "1",
    "https://github.com/nvim-lua/plenary.nvim", plenary_dir,
  })
  if vim.v.shell_error ~= 0 or vim.fn.filereadable(plugin_file) == 0 then
    error("failed to clone plenary into " .. plenary_dir .. "\n" .. out)
  end
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
