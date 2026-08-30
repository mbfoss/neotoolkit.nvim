---@diagnostic disable: undefined-global, undefined-field

--- The module keeps its state in upvalues and refuses a second `init()`, so each
--- spec gets a fresh copy rather than trying to unpick the previous one's marks.
--- Namespaces and augroups are process-global and keyed by name, but they are
--- reused rather than accumulated, and every spec works in its own buffers.
local function fresh_group()
    package.loaded["neotoolkit.fileextmarks"] = nil
    local fem = require("neotoolkit.fileextmarks")
    fem.init("ntkspec")
    return fem.define_group("marks")
end

--- A real directory: `tempname()` hands back a path under /var on macOS, which
--- is itself a symlink to /private/var -- exactly the mismatch these specs are
--- about, so resolve it away unless a spec is asking for it.
---@return string
local function tmpdir()
    local dir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(dir, "p")
    return dir
end

---@param lines string[]
---@return string
local function tmpfile(lines)
    local file = tmpdir() .. "/file.txt"
    vim.fn.writefile(lines, file)
    return file
end

--- Opens `file` and returns its buffer.
---@param file string
---@return integer
local function open(file)
    vim.cmd.edit(vim.fn.fnameescape(file))
    return vim.api.nvim_get_current_buf()
end

--- Extmarks sitting past the last line of `bufnr` -- the state the repair exists
--- to prevent. Read straight from Neovim, so it cannot be masked by the module
--- clamping what it reports.
---@param bufnr integer
---@return integer
local function stranded_count(bufnr)
    local ns = vim.api.nvim_get_namespaces()["ntkspec.marks"]
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    return #vim.api.nvim_buf_get_extmarks(bufnr, ns, { line_count, 0 }, { -1, -1 }, {})
end

--- Every extmark this group holds in `bufnr`, read straight from Neovim rather
--- than through the module, which reports marks by file and so cannot see one
--- left behind in a buffer that no longer answers to that file.
---@param bufnr integer
---@return integer
local function buf_mark_count(bufnr)
    local ns = vim.api.nvim_get_namespaces()["ntkspec.marks"]
    return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
end

local group

before_each(function()
    group = fresh_group()
end)

after_each(function()
    vim.cmd("silent! %bwipeout!")
end)

describe("fileextmarks stranded marks", function()
    it("re-anchors a mark left past the end by a deletion", function()
        local file = tmpfile({ "a", "b", "c", "d" })
        local buf = open(file)
        group.set_file_extmark(1, file, 4, 0, {}, nil)

        vim.api.nvim_buf_set_lines(buf, 2, 4, true, {})

        assert.equals(0, stranded_count(buf))
        assert.equals(2, group.get_file_extmarks(file, true)[1].lnum)
    end)

    it("re-anchors a mark stranded by a replacement that grows the buffer", function()
        local file = tmpfile({ "a", "b" })
        local buf = open(file)
        group.set_file_extmark(1, file, 2, 0, {}, nil)

        vim.api.nvim_buf_set_lines(buf, 1, 2, true, { "x", "y", "z" })

        assert.equals(0, stranded_count(buf))
    end)

    it("re-anchors marks on a file tracked through a symlinked path", function()
        -- Every spelling of a path normalizes to the one resolved key, so this
        -- file is tracked under the buffer's own name however it was reached.
        local real = tmpdir()
        vim.fn.writefile({ "a", "b" }, real .. "/file.txt")

        local link = vim.fn.resolve(vim.fn.tempname())
        vim.fn.mkdir(vim.fn.fnamemodify(link, ":h"), "p")
        vim.fn.system({ "ln", "-s", real, link })
        local via_link = link .. "/file.txt"

        local buf = open(via_link)
        group.set_file_extmark(1, via_link, 2, 0, {}, nil)
        assert.not_equals(vim.api.nvim_buf_get_name(buf), via_link)

        vim.api.nvim_buf_set_lines(buf, 1, 2, true, {})

        assert.equals(0, stranded_count(buf))
    end)

    it("keeps the buffer editable when a stranded mark carries a stale range", function()
        -- A multi-line highlight whose end row no longer exists: re-placing it
        -- unclamped throws, and an error raised inside on_lines fails the edit
        -- that triggered it and every edit after it.
        local file = tmpfile({ "aaa", "bbb", "ccc", "ddd" })
        local buf = open(file)
        group.set_file_extmark(1, file, 3, 0, { end_row = 3, end_col = 3 }, nil)

        assert.has_no.errors(function()
            vim.api.nvim_buf_set_lines(buf, 1, 4, true, {})
        end)
        assert.has_no.errors(function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, { "z" })
        end)
        assert.equals(0, stranded_count(buf))
    end)

    it("clamps a stale range without rewriting the stored opts", function()
        local file = tmpfile({ "aaa", "bbb", "ccc" })
        local buf = open(file)
        group.set_file_extmark(1, file, 3, 0, { end_row = 2, end_col = 3 }, nil)

        vim.api.nvim_buf_set_lines(buf, 1, 3, true, {})

        -- The caller's range survives, so undoing the deletion restores it whole.
        assert.equals(2, group.get_extmark_by_id(1).opts.end_row)
    end)

    it("does not throw from refresh() when a stored range no longer fits", function()
        local file = tmpfile({ "aaa", "bbb", "ccc" })
        local buf = open(file)
        group.set_file_extmark(1, file, 1, 0, { end_row = 2, end_col = 3 }, nil)

        vim.api.nvim_buf_set_lines(buf, 1, 3, true, {})

        assert.has_no.errors(group.refresh)
    end)
end)

describe("fileextmarks live queries", function()
    it("reports the live position for a mark found live", function()
        local file = tmpfile({ "a", "b", "c", "d" })
        local buf = open(file)
        group.set_file_extmark(1, file, 4, 0, {}, nil)

        vim.api.nvim_buf_set_lines(buf, 0, 2, true, {})   -- mark slides up to line 2

        local found = group.get_extmark_by_location(file, 2, true)
        assert.equals(1, found.id)
        assert.equals(2, found.lnum)
        assert.equals("live", found.source)
    end)

    it("reports the stored position when not asked for a live one", function()
        local file = tmpfile({ "a", "b", "c", "d" })
        local buf = open(file)
        group.set_file_extmark(1, file, 4, 0, {}, nil)
        vim.api.nvim_buf_set_lines(buf, 0, 2, true, {})

        local found = group.get_extmark_by_location(file, 4, false)
        assert.equals(4, found.lnum)
        assert.equals("stored", found.source)
    end)

    it("finds nothing on a line no mark sits on", function()
        local file = tmpfile({ "a", "b", "c" })
        open(file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)

        assert.is_nil(group.get_extmark_by_location(file, 2, true))
        assert.is_nil(group.get_extmark_by_location(file, 99, true))
    end)

    it("finds a mark on the last line", function()
        local file = tmpfile({ "a", "b", "c" })
        open(file)
        group.set_file_extmark(1, file, 3, 0, {}, nil)

        assert.equals(1, group.get_extmark_by_location(file, 3, true).id)
    end)
end)

describe("fileextmarks bookkeeping", function()
    it("vacates the old file when a mark moves to another one", function()
        local one = tmpfile({ "a", "b" })
        local two = tmpfile({ "x", "y" })
        group.set_file_extmark(1, one, 1, 0, {}, nil)

        group.set_file_extmark(1, two, 1, 0, {}, nil)

        assert.equals(0, #group.get_file_extmarks(one, false))
        assert.equals(1, #group.get_extmarks(false))
        assert.equals(vim.fn.fnamemodify(two, ":p"), group.get_extmark_by_id(1).file)
    end)

    it("keeps the mark when it is re-set on the same file", function()
        local file = tmpfile({ "a", "b" })
        open(file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)

        group.set_file_extmark(1, file, 2, 0, {}, nil)

        assert.equals(1, #group.get_extmarks(true))
        assert.equals(2, group.get_extmarks(true)[1].lnum)
    end)

    it("drops a file once its last mark is removed", function()
        local file = tmpfile({ "a", "b" })
        group.set_file_extmark(1, file, 1, 0, {}, nil)
        group.set_file_extmark(2, file, 2, 0, {}, nil)

        group.remove_extmark(1)
        assert.equals(1, #group.get_file_extmarks(file, false))

        group.remove_extmark(2)
        assert.equals(0, #group.get_file_extmarks(file, false))
        assert.is_nil(group.get_extmark_by_id(2))
    end)

    it("applies stored marks when the file is opened later", function()
        local file = tmpfile({ "a", "b", "c" })
        group.set_file_extmark(1, file, 2, 0, {}, nil)

        open(file)

        assert.equals(1, #group.get_file_extmarks(file, true))
        assert.equals(2, group.get_file_extmarks(file, true)[1].lnum)
    end)

    it("resolves the same buffer after it is renamed away and back", function()
        local file = tmpfile({ "a", "b" })
        local buf = open(file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)
        assert.equals("live", group.get_file_extmarks(file, true)[1].source)

        -- The cached bufnr must not survive the buffer being renamed off `file`.
        vim.api.nvim_buf_set_name(buf, vim.fn.fnamemodify(file, ":h") .. "/other.txt")
        assert.equals("stored", group.get_file_extmarks(file, true)[1].source)

        vim.api.nvim_buf_set_name(buf, file)
        assert.equals("live", group.get_file_extmarks(file, true)[1].source)
    end)

    it("ignores a buffer whose name merely contains the file", function()
        local dir = tmpdir()
        -- `bufnr()` settles for a partial match when nothing matches exactly, which
        -- would hand this buffer back for a file that has none of its own.
        vim.fn.writefile({ "x", "y" }, dir .. "/file.txt.bak")
        local bak = open(dir .. "/file.txt.bak")

        local file = dir .. "/file.txt"
        vim.fn.writefile({ "a", "b" }, file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)

        assert.equals(0, buf_mark_count(bak))
        assert.equals("stored", group.get_file_extmarks(file, true)[1].source)
    end)

    it("does not clear an unrelated buffer that partially matches", function()
        local dir = tmpdir()
        vim.fn.writefile({ "x", "y" }, dir .. "/file.txt.bak")
        vim.fn.writefile({ "a", "b" }, dir .. "/file.txt")
        local bak = open(dir .. "/file.txt.bak")
        group.set_file_extmark(1, dir .. "/file.txt.bak", 1, 0, {}, nil)
        group.set_file_extmark(2, dir .. "/file.txt", 1, 0, {}, nil)
        assert.equals(1, buf_mark_count(bak))

        -- Removing a file that no buffer holds must not take the namespace of the
        -- buffer that merely spells like it down with it.
        group.remove_file_extmarks(dir .. "/file.txt")

        assert.equals(1, buf_mark_count(bak))
    end)

    it("clears marks a buffer is renamed away from", function()
        local file = tmpfile({ "a", "b" })
        local buf = open(file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)
        assert.equals(1, buf_mark_count(buf))

        -- No BufReadPost fires for a rename, and every later lookup for `file`
        -- misses this buffer, so nothing else could ever collect these.
        vim.api.nvim_buf_set_name(buf, vim.fn.fnamemodify(file, ":h") .. "/renamed.txt")

        assert.equals(0, buf_mark_count(buf))
        assert.equals("stored", group.get_file_extmarks(file, true)[1].source)
    end)

    it("applies the new name's marks on rename", function()
        local dir = tmpdir()
        local from, to = dir .. "/from.txt", dir .. "/to.txt"
        vim.fn.writefile({ "a", "b" }, from)
        vim.fn.writefile({ "a", "b" }, to)

        local buf = open(from)
        group.set_file_extmark(1, to, 2, 0, {}, nil)
        assert.equals(0, buf_mark_count(buf))

        vim.api.nvim_buf_set_name(buf, to)

        assert.equals(1, buf_mark_count(buf))
        assert.equals("live", group.get_file_extmarks(to, true)[1].source)
    end)

    it("tracks one file however its path is spelled", function()
        local real = tmpdir()
        vim.fn.writefile({ "a", "b" }, real .. "/file.txt")
        local link = vim.fn.resolve(vim.fn.tempname())
        vim.fn.system({ "ln", "-s", real, link })
        local direct, via_link = real .. "/file.txt", link .. "/file.txt"

        open(direct)
        group.set_file_extmark(1, direct, 1, 0, {}, nil)
        group.set_file_extmark(2, via_link, 2, 0, {}, nil)

        -- One key, so either spelling sees both marks and refresh() keeps them.
        assert.equals(2, #group.get_extmarks(false))
        assert.equals(2, #group.get_file_extmarks(via_link, true))
        group.refresh()
        assert.equals(2, #group.get_file_extmarks(direct, true))
    end)
end)

describe("fileextmarks buffer subscriptions", function()
    --- Counts the namespace queries the module makes while `buf` is appended to.
    --- Appending at the end is what reaches `_on_lines`' repair path, so this is
    --- the per-edit cost an attached buffer imposes.
    ---@param buf integer
    ---@return integer
    local function queries_while_appending(buf)
        local hits = 0
        local orig = vim.api.nvim_buf_get_extmarks
        vim.api.nvim_buf_get_extmarks = function(...)
            hits = hits + 1
            return orig(...)
        end

        local ok, err = pcall(function()
            for i = 1, 10 do
                vim.api.nvim_buf_set_lines(buf, -1, -1, true, { "x" .. i })
            end
        end)

        vim.api.nvim_buf_get_extmarks = orig
        assert(ok, err)
        return hits
    end

    it("stops watching a buffer once its last mark is removed", function()
        local file = tmpfile({ "a", "b" })
        local buf = open(file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)

        assert.is_true(queries_while_appending(buf) > 0)

        group.remove_extmark(1)

        -- A Lua `on_lines` callback can only detach from inside itself, so the
        -- first edit after the mark goes away tears the subscription down
        -- without querying, and every edit after that never runs at all.
        assert.equals(0, queries_while_appending(buf))
    end)

    it("stops watching after the file's marks are removed wholesale", function()
        local file = tmpfile({ "a", "b" })
        local buf = open(file)
        group.set_file_extmark(1, file, 1, 0, {}, nil)
        group.set_file_extmark(2, file, 2, 0, {}, nil)

        group.remove_file_extmarks(file)

        assert.equals(0, queries_while_appending(buf))
    end)

    it("collects an extmark orphaned in an unloaded buffer", function()
        -- Extmarks survive an unload, and moving a mark away skips the
        -- buffer-side delete while the old buffer is unloaded. Reading the
        -- buffer back has to collect the orphan left behind: nothing records
        -- it, so it would otherwise render for the rest of the session.
        local one, two = tmpfile({ "a1", "a2", "a3" }), tmpfile({ "b1", "b2" })
        local buf = open(one)
        group.set_file_extmark(1, one, 3, 0, { hl_group = "Error" }, nil)
        group.set_file_extmark(2, one, 1, 0, {}, nil)

        vim.cmd("enew")
        vim.cmd("bunload! " .. buf)
        group.set_file_extmark(1, two, 1, 0, {}, nil)
        vim.cmd("silent! buffer " .. buf)

        vim.api.nvim_buf_set_lines(buf, 1, 3, true, {})   -- reaches the end

        local ns = vim.api.nvim_get_namespaces()["ntkspec.marks"]
        local orphan
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
            if m[1] == 1 then orphan = m[4] end
        end

        -- Gone from the buffer, and never re-anchored on the way out.
        assert.is_nil(orphan)
        assert.equals(vim.fn.fnamemodify(two, ":p"), group.get_extmark_by_id(1).file)
    end)
end)

describe("fileextmarks path normalization", function()
    it("tracks a file reached through a symlinked name", function()
        -- Neovim resolves symlinked directory components but keeps a final
        -- component symlink as the name it was opened with, so the buffer's own
        -- name still has to be normalized before it can be matched.
        local dir = tmpdir()
        local real, link = dir .. "/real.txt", dir .. "/link.txt"
        vim.fn.writefile({ "a", "b" }, real)
        vim.fn.system({ "ln", "-s", real, link })

        local buf = open(link)
        assert.equals(link, vim.api.nvim_buf_get_name(buf))

        group.set_file_extmark(1, real, 2, 0, {}, nil)

        -- Either spelling is the one key, and the open buffer is found from it.
        local found = group.get_file_extmarks(link, true)
        assert.equals(1, #found)
        assert.equals("live", found[1].source)
        assert.equals(real, found[1].file)
    end)

    it("normalizes a relative path against the current directory", function()
        -- The resolve memo is keyed on the absolute path, not on the caller's
        -- spelling, or the same relative name would stick to the first `cd`.
        local one, two = tmpdir(), tmpdir()
        vim.fn.writefile({ "a" }, one .. "/file.txt")
        vim.fn.writefile({ "a" }, two .. "/file.txt")

        local cwd = vim.uv.cwd()
        local ok, err = pcall(function()
            vim.cmd.cd(vim.fn.fnameescape(one))
            group.set_file_extmark(1, "file.txt", 1, 0, {}, nil)
            vim.cmd.cd(vim.fn.fnameescape(two))
            group.set_file_extmark(2, "file.txt", 1, 0, {}, nil)
        end)
        vim.cmd.cd(vim.fn.fnameescape(cwd))
        assert(ok, err)

        assert.equals(one .. "/file.txt", group.get_extmark_by_id(1).file)
        assert.equals(two .. "/file.txt", group.get_extmark_by_id(2).file)
    end)
end)
