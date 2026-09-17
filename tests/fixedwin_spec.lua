---@diagnostic disable: undefined-global, undefined-field
local fixedwin = require("neotoolkit.fixedwin")

-- Let the scheduled re-pin passes (and the settling tick) run.
local function settle()
    vim.wait(50, function() return false end)
end

-- headless Neovim never redraws, so fire WinResized as a UI would
local function redraw()
    vim.cmd("doautocmd <nomodeline> WinResized")
    settle()
end

local function close_others()
    vim.cmd("silent! only!")
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        vim.wo[win].winfixwidth = false
        vim.wo[win].winfixheight = false
    end
end

describe("neotoolkit.fixedwin", function()
    local groups = {}

    before_each(function()
        vim.o.columns = 200
        vim.o.lines = 60
        close_others()
    end)

    after_each(function()
        for _, g in ipairs(groups) do pcall(vim.api.nvim_del_augroup_by_id, g) end
        groups = {}
        close_others()
    end)

    local function create(axis, ratio, opts)
        opts = vim.tbl_extend("force", { axis = axis, ratio = ratio }, opts or {})
        local win, group = fixedwin.create_fixed_win(0, opts)
        groups[#groups + 1] = group
        settle()
        return win
    end

    it("keeps a side panel and a bottom panel pinned across new splits", function()
        local side = create("width", 0.25)
        local bottom = create("height", 0.3)
        local width, height = vim.api.nvim_win_get_width(side), vim.api.nvim_win_get_height(bottom)
        assert.equal(50, width)
        assert.equal(18, height)

        vim.cmd("vsplit")
        settle()
        vim.cmd("split")
        settle()
        assert.equal(width, vim.api.nvim_win_get_width(side))
        assert.equal(height, vim.api.nvim_win_get_height(bottom))
        assert.is_true(vim.wo[side].winfixwidth)
        assert.is_true(vim.wo[bottom].winfixheight)
    end)

    it("shows the given buffer and only enters it when asked", function()
        local editor = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_create_buf(false, true)
        local side = create("width", 0.25, { pos = "topleft" })
        assert.equal(editor, vim.api.nvim_get_current_win())

        local bottom, group = fixedwin.create_fixed_win(buf, { axis = "height", ratio = 0.3, enter = true })
        groups[#groups + 1] = group
        settle()
        assert.equal(bottom, vim.api.nvim_get_current_win())
        assert.equal(buf, vim.api.nvim_win_get_buf(bottom))
        assert.equal(0, vim.api.nvim_win_get_position(side)[2])
    end)

    it("keeps a bottom panel created before a side panel pinned", function()
        local bottom = create("height", 0.3)
        local side = create("width", 0.25)
        local width, height = vim.api.nvim_win_get_width(side), vim.api.nvim_win_get_height(bottom)

        vim.cmd("vsplit")
        settle()
        assert.equal(width, vim.api.nvim_win_get_width(side))
        assert.equal(height, vim.api.nvim_win_get_height(bottom))
    end)

    it("re-pins a side panel nested in a column with another window", function()
        local editor = vim.api.nvim_get_current_win()
        local side = create("width", 0.25)
        local width = vim.api.nvim_win_get_width(side)

        -- nest: split the side panel's column, pinning the new window's height
        vim.api.nvim_set_current_win(side)
        vim.cmd("belowright split")
        vim.wo.winfixheight = true
        settle()
        assert.is_true(vim.wo[side].winfixwidth)

        vim.api.nvim_set_current_win(editor)
        vim.cmd("vsplit")
        settle()
        assert.equal(width, vim.api.nvim_win_get_width(side))
    end)

    it("keeps the ratio when a bottom panel is moved to the side and back", function()
        local bottom = create("height", 0.3)

        vim.api.nvim_set_current_win(bottom)
        vim.cmd("wincmd L")
        redraw()
        assert.equal(60, vim.api.nvim_win_get_width(bottom))
        assert.is_true(vim.wo[bottom].winfixwidth)
        assert.is_false(vim.wo[bottom].winfixheight)

        vim.cmd("wincmd J")
        redraw()
        assert.equal(18, vim.api.nvim_win_get_height(bottom))
        assert.is_true(vim.wo[bottom].winfixheight)
        assert.is_false(vim.wo[bottom].winfixwidth)
    end)

    it("carries a manual resize on the side back to the bottom", function()
        local bottom = create("height", 0.3)

        vim.api.nvim_set_current_win(bottom)
        vim.cmd("wincmd L")
        redraw()
        vim.api.nvim_win_set_width(bottom, 80)
        redraw()

        vim.cmd("wincmd J")
        redraw()
        assert.equal(24, vim.api.nvim_win_get_height(bottom))
    end)

    it("keeps a cross fix option set by the caller", function()
        local side = create("width", 0.25)
        vim.wo[side].winfixheight = true
        vim.cmd("split")
        settle()
        assert.is_true(vim.wo[side].winfixheight)
        assert.is_true(vim.wo[side].winfixwidth)
    end)

    it("ignores layout changes in another tabpage", function()
        local bottom = create("height", 0.3)
        vim.cmd("tabnew")
        vim.cmd("vsplit | split")
        redraw()
        vim.cmd("tabprevious")
        assert.equal(18, vim.api.nvim_win_get_height(bottom))
        assert.is_true(vim.wo[bottom].winfixheight)
        vim.cmd("silent! tabonly!")
    end)

    it("clears the fix option while unmanageable and restores it after", function()
        local editor = vim.api.nvim_get_current_win()
        local side = create("width", 0.25)

        vim.api.nvim_win_close(editor, true)
        settle()
        assert.is_false(vim.wo[side].winfixwidth)

        vim.api.nvim_set_current_win(side)
        vim.cmd("topleft vsplit")
        settle()
        assert.is_true(vim.wo[side].winfixwidth)
        assert.equal(50, vim.api.nvim_win_get_width(side))
    end)
end)
