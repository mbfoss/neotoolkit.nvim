-- Busted helper: loaded once, inside Neovim, before any spec runs.

-- nlua starts Neovim with `-u NONE`, so the plugin is not on the runtimepath.
-- Specs `require` it through `lpath` (see .busted); put it on the rtp as well
-- so anything reaching for plugin/, ftplugin/ or friends finds it too.
vim.opt.runtimepath:prepend(vim.uv.cwd())
