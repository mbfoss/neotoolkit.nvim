local M = {}

---@class neotoolkit.fileextmarks.MarkInfo
---@field id number
---@field file string
---@field lnum number        -- 1-based
---@field col number        -- 0-based
---@field opts vim.api.keyset.set_extmark
---@field user_data any
---@field source "live"|"stored"

---@class neotoolkit.fileextmarks.MarkData
---@field id number
---@field ns number
---@field lnum number        -- 1-based
---@field col number        -- 0-based
---@field opts vim.api.keyset.set_extmark
---@field user_data any

---@alias neotoolkit.fileextmarks.ById table<number, neotoolkit.fileextmarks.MarkData>
---@alias neotoolkit.fileextmarks.ByFile table<string, neotoolkit.fileextmarks.ById>

---@class neotoolkit.fileextmarks.GroupData
---@field ns number
---@field byfile neotoolkit.fileextmarks.ByFile
---@field id_to_file table<number, string>

---@type table<string, neotoolkit.fileextmarks.GroupData>
local _defined_groups = {}
local _autocmds_registered = false

-- Neovim keeps extmark namespaces and autocmd groups in a single, process-wide
-- registry keyed by name, while the state above is per module instance. If this
-- file is vendored into several plugins, two copies asking for the same group
-- name would silently share a namespace and clear each other's autocmds, so the
-- owning plugin must claim a prefix via M.init() before anything else.
---@type string?
local _prefix = nil

---@return string
local function _require_prefix()
    return assert(_prefix, "init(prefix) must be called first")
end

---@param name string
---@return string
local function _prefixed(name)
    return ("%s.%s"):format(_require_prefix(), name)
end

--- Marks are keyed by resolved absolute path, so every spelling of a file --
--- relative, or reached through a symlinked component -- lands on the one key.
---
--- Neovim does not name buffers this way. It resolves symlinked *directory*
--- components, but a final-component file symlink stays under the name it was
--- opened with, so `nvim_buf_get_name()` is normalized through here as well.
--- `vim.fn.bufnr()` still finds such a buffer from the resolved path because it
--- matches by inode rather than by name.
---
--- `resolve()` rather than `vim.uv.fs_realpath()`: a mark may be stored for a
--- file that does not exist yet, and realpath returns nil for those.
---@param file string
---@return string
local function _normalize_file(file)
    return vim.fn.resolve(vim.fn.fnamemodify(file, ":p"))
end

---@class neotoolkit.fileextmarks.BufCacheEntry
---@field bufnr integer
---@field name string        -- the buffer's name when it was resolved

--- Cache for `_get_loaded_bufnr`, keyed by normalized path.
---@type table<string, neotoolkit.fileextmarks.BufCacheEntry>
local _bufnr_cache = {}

--- `vim.fn.bufnr()` is the most expensive call on the read path: it walks the
--- whole buffer list matching names as patterns, and it runs once per file on
--- every lookup. Cache the answer and re-validate it with three cheap C calls
--- instead.
---
--- Validation compares the buffer's name to the name it had when it was cached, so
--- a wipe, an unload or a rename all fall through to a fresh lookup and the cache
--- heals itself with no invalidation autocmds.
---@param file string        -- must already be normalized
---@return integer
local function _get_loaded_bufnr(file)
    local entry = _bufnr_cache[file]
    if entry then
        if vim.api.nvim_buf_is_valid(entry.bufnr)
            and vim.api.nvim_buf_is_loaded(entry.bufnr)
            and vim.api.nvim_buf_get_name(entry.bufnr) == entry.name
        then
            return entry.bufnr
        end
        _bufnr_cache[file] = nil
    end

    local bufnr = vim.fn.bufnr(file, false)
    if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then return -1 end

    _bufnr_cache[file] = { bufnr = bufnr, name = vim.api.nvim_buf_get_name(bufnr) }
    return bufnr
end

--- Buffers holding marks, each mapped to the normalized file they hold them for.
--- `_on_lines` needs that file on every change and cannot afford to re-derive it
--- from the buffer's name, and the absence of an entry is what tells the callback
--- to detach.
---@type table<integer, string>
local _attached = {}

--- Buffers with a live `on_lines` subscription.
---
--- Deliberately not folded into `_attached`. A subscription outlives its entry
--- there: `_forget_bufnr` drops the entry to *schedule* a detach, but the
--- callback can only release itself, so it stays live until the next change. One
--- table doing both jobs makes that window look unsubscribed, and a mark re-added
--- inside it stacks a second subscription on the buffer -- every one of which
--- then runs the repair on every edit, for the life of the session.
---@type table<integer, true>
local _subscribed = {}

--- Forgets the cached buffer lookup for `file`, unless some group still tracks
--- it. Call after dropping a file from a group; the cache is shared across
--- groups, so the last one out turns the light off.
---@param file string
local function _forget_bufnr(file)
    for _, group_data in pairs(_defined_groups) do
        if group_data.byfile[file] then return end
    end

    _bufnr_cache[file] = nil

    -- Schedule the `on_lines` release too, or a buffer keeps paying a query per
    -- group on every edit that reaches its end long after its last mark went
    -- away. `_subscribed` is left alone: the subscription is still live until the
    -- callback next runs and drops it. `_attached` is scanned rather than read
    -- through `_bufnr_cache`, which may never have been populated for this file:
    -- a buffer opened with marks already stored attaches from the autocmd's
    -- bufnr, without a lookup.
    for bufnr, attached_file in pairs(_attached) do
        if attached_file == file then _attached[bufnr] = nil end
    end
end

--- Call after removing a single mark: drops `file` from the group if that was
--- its last one, then releases the cache.
---
--- Without this an emptied file lingers as a bare table that every later
--- `_get_extmarks` still walks -- and still pays a buffer lookup for -- and its
--- cache entries outlive the marks that justified them.
---@param group_data neotoolkit.fileextmarks.GroupData
---@param file string
local function _release_file(group_data, file)
    local file_table = group_data.byfile[file]
    if file_table and next(file_table) == nil then
        group_data.byfile[file] = nil
    end

    _forget_bufnr(file)
end

--- Writes `mark` into the buffer at the given position, clamped to a real line
--- and a real column. Does not touch the cached position in `mark`.
---@param bufnr integer
---@param mark neotoolkit.fileextmarks.MarkData
---@param lnum integer        -- 1-based
---@param col integer        -- 0-based
---@return integer lnum, integer col      -- the clamped position actually used
local function _place_extmark(bufnr, mark, lnum, col)
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    lnum = math.max(1, math.min(lnum, line_count))
    local row = lnum - 1

    -- Only a non-zero column needs the line, and marks overwhelmingly sit at 0.
    -- Kept around for the range end below, which usually wants the same line.
    local row_line
    if col > 0 then
        row_line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, true)[1] or ""
        col = math.min(col, #row_line)
    else
        col = 0
    end

    -- Clamp the range end inside the buffer. Neovim measures `end_col` against
    -- the length of the `end_row` line (and, when `end_row` is absent, against
    -- the start row's line), so a range whose text has since been deleted makes
    -- `nvim_buf_set_extmark` throw. `mark.opts` is deliberately left alone: the
    -- mark keeps the range its caller gave it, so an undo that puts the text back
    -- puts the whole range back with it. A range that already fits -- the
    -- overwhelmingly common case -- allocates nothing.
    local opts = mark.opts
    local end_row, end_col = opts.end_row, opts.end_col

    if end_row or end_col then
        local clamped_row = math.min(end_row or row, line_count - 1)
        local clamped_col = end_col

        if end_col then
            local line = clamped_row == row and row_line
            if not line then
                line = vim.api.nvim_buf_get_lines(bufnr, clamped_row, clamped_row + 1, true)[1] or ""
            end
            clamped_col = math.min(end_col, #line)
        end

        if (end_row and clamped_row ~= end_row) or clamped_col ~= end_col then
            opts = vim.tbl_extend("force", opts, { end_row = clamped_row, end_col = clamped_col })
        end
    end

    assert(type(mark.id) == "number")
    local id = vim.api.nvim_buf_set_extmark(bufnr, mark.ns, row, col, opts)
    assert(id == mark.id)

    return lnum, col
end

---@param bufnr integer
---@param mark neotoolkit.fileextmarks.MarkData
local function _set_extmark(bufnr, mark)
    if not vim.api.nvim_buf_is_loaded(bufnr) then return end
    if vim.api.nvim_buf_line_count(bufnr) == 0 then return end

    mark.lnum, mark.col = _place_extmark(bufnr, mark, mark.lnum, mark.col)
end

---@class neotoolkit.fileextmarks.LivePos
---@field id number
---@field lnum number        -- 1-based
---@field col number        -- 0-based

--- Reports where this group's marks currently sit in `bufnr`. Pure: `_on_lines`
--- keeps the buffer in a state where every row is real, so nothing needs fixing
--- here. The clamp is defence in depth for a buffer we failed to attach to -- we
--- would rather report the last line than a line that does not exist.
---@param bufnr integer
---@param file_table neotoolkit.fileextmarks.ById
---@param ns integer
---@return neotoolkit.fileextmarks.LivePos[]      -- in buffer order
local function _read_live_marks(bufnr, file_table, ns)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local result = {}

    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = false })) do
        local id, row, col = m[1], m[2], m[3]
        if file_table[id] then
            result[#result + 1] = { id = id, lnum = math.min(row + 1, line_count), col = col }
        end
    end

    return result
end

--- Re-anchors marks stranded past the end of `bufnr` onto its last line.
---
--- Deleting a range of lines that runs to the end of the buffer leaves the marks
--- it contained on row `line_count` -- one past the last real line. Neovim never
--- drops them: they keep drifting with later edits, one row past the end forever.
--- But nothing renders on a row that does not exist and a ranged query for the
--- last line never returns them, so from the outside the mark simply vanishes.
---
--- Only that tail can hold a stranded mark, so the query is bounded by it rather
--- than walking the namespace: the cost is proportional to the number of marks
--- actually stranded, which is normally none.
---
--- Marks are matched against `byfile[file]`, the marks this group holds for the
--- file this buffer is attached under, rather than by id through `id_to_file`.
--- An id resolves to exactly one file, but a buffer can hold an extmark for a
--- file it is no longer the buffer of: moving a mark to another file skips the
--- buffer-side delete while the old buffer is unloaded, and extmarks survive an
--- unload, so the orphan is still there when the buffer is read back. Matching
--- by id would look that orphan up, find the mark under its *new* file, and
--- re-anchor a foreign mark here on every edit. Going through `byfile` also
--- skips the query outright for a group holding nothing for this file.
---
--- `file` comes from `_attached` rather than from the buffer's name so that this
--- costs no `_normalize_file` -- a readlink per path component -- on an edit.
---@param bufnr integer
---@param file string        -- normalized; the file `bufnr` was attached under
---@param line_count integer      -- the buffer's line count after the change
local function _repair_stranded_marks(bufnr, file, line_count)
    for _, group_data in pairs(_defined_groups) do
        local file_table = group_data.byfile[file]
        if file_table then
            local stranded = vim.api.nvim_buf_get_extmarks(
                bufnr,
                group_data.ns,
                { line_count, 0 },
                { -1, -1 },
                { details = false }
            )
            for _, m in ipairs(stranded) do
                local mark = file_table[m[1]]
                if mark then
                    -- Clamps onto the last line. The cached position is left alone
                    -- so an unsaved buffer's cache keeps describing the file on disk.
                    _place_extmark(bufnr, mark, m[2] + 1, m[3])
                end
            end
        end
    end
end

--- Fires for every change to an attached buffer, including changes made through
--- the API, which is why this replaced a TextChanged autocmd: `nvim_buf_set_lines`
--- fires no TextChanged, so a plugin editing the buffer stranded marks silently.
---
--- Only a change that runs to the end of the buffer can strand a mark, and that
--- is decided from the change range alone: every edit that stops short of the
--- last line is rejected in O(1) without the extmark tree being touched at all.
---
--- Note this is not just about deletions. A replacement that grows the buffer
--- strands marks too, because a right-gravity mark at the end of the replaced
--- range lands on `last_new` -- which is exactly `line_count` when the range ran
--- to the end. Testing "did anything get removed" first therefore misses real
--- strandings, so the reach test stands alone.
---
--- Errors are swallowed on purpose. One raised here propagates out of the change
--- that triggered it: `nvim_buf_set_lines` returns the error to its caller and
--- the buffer then rejects every later edit, so a throwing repair costs far more
--- than the mark it failed to move.
---
--- A missing `_attached` entry means the last mark for this buffer's file is
--- gone. Returning true is the whole detach path: a Lua `on_lines` callback can
--- only be released from inside itself, so `_forget_bufnr` drops the entry and
--- the next change tears the subscription down.
local function _on_lines(_, bufnr, _, _, _, last_new)
    local file = _attached[bufnr]
    if not file then
        _subscribed[bufnr] = nil
        return true -- detach
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if last_new < line_count then return end -- change stopped short of the end

    pcall(_repair_stranded_marks, bufnr, file, line_count)
end

---@param bufnr integer
---@param file string        -- normalized; the file `bufnr` holds marks for
local function _attach_buffer(bufnr, file)
    _attached[bufnr] = file        -- may be a re-attach under a new name

    -- A subscription scheduled for release but not yet torn down is reused: the
    -- entry above revives it, and attaching again would leave two running.
    if _subscribed[bufnr] then return end

    _subscribed[bufnr] = true
    local ok = vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = _on_lines,
        on_detach = function(_, b)
            _attached[b] = nil
            _subscribed[b] = nil
        end,
    })
    if not ok then
        _attached[bufnr] = nil
        _subscribed[bufnr] = nil
    end
end

---@param bufnr integer
---@param ns integer
local function _clear_buf_namespace(bufnr, ns)
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@param bufnr integer
---@param group string
local function _apply_buffer_extmarks(bufnr, group)
    local group_data = _defined_groups[group]
    assert(group_data)

    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then return end
    file = _normalize_file(file)

    local file_data = group_data.byfile[file]
    if not file_data then return end

    for _, mark in pairs(file_data) do
        _set_extmark(bufnr, mark)
    end

    _attach_buffer(bufnr, file)
end

---@param bufnr number
local function _sync_file_extmarks(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if file == "" then return end
    file = _normalize_file(file)

    for _, group_data in pairs(_defined_groups) do
        local file_table = group_data.byfile[file]
        if file_table then
            for _, live in ipairs(_read_live_marks(bufnr, file_table, group_data.ns)) do
                local mark = file_table[live.id]
                mark.lnum, mark.col = live.lnum, live.col
            end
        end
    end
end

local function _register_autocmds()
    if _autocmds_registered then return end
    _autocmds_registered = true

    local augroup = vim.api.nvim_create_augroup(_prefixed("fileextmarks"), { clear = true })
    vim.api.nvim_create_autocmd("BufReadPost", {
        group = augroup,
        callback = function(ev)
            for group in pairs(_defined_groups) do
                _apply_buffer_extmarks(ev.buf, group)
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        callback = function(ev) _sync_file_extmarks(ev.buf) end,
    })
    vim.api.nvim_create_autocmd("BufUnload", {
        group = augroup,
        callback = function(ev) _sync_file_extmarks(ev.buf) end,
    })
end

---@param id number
---@param file string
---@param lnum number        -- 1-based
---@param col number        -- 0-based
---@param group_data neotoolkit.fileextmarks.GroupData
---@param opts vim.api.keyset.set_extmark       -- extmark opts (include `priority` here)
---@param user_data any
---@see vim.api.nvim_buf_set_extmark
local function _set_file_extmark(id, file, lnum, col, group_data, opts, user_data)
    assert(lnum >= 1, "lnum must be 1-based")

    file = _normalize_file(file)
    local bufnr = _get_loaded_bufnr(file)

    local old_file = group_data.id_to_file[id]
    if old_file and old_file ~= file then
        local old_bufnr = _get_loaded_bufnr(old_file)
        if old_bufnr >= 0 then
            vim.api.nvim_buf_del_extmark(old_bufnr, group_data.ns, id)
        end

        -- Vacate the old file, or the mark stays visible there: it would be
        -- reported twice by `_get_extmarks` and put back into the old buffer by
        -- `refresh()`, since both read from `byfile` rather than from the buffer.
        local old_table = group_data.byfile[old_file]
        if old_table then
            old_table[id] = nil
            _release_file(group_data, old_file)
        end
    end

    group_data.id_to_file[id] = file
    group_data.byfile[file] = group_data.byfile[file] or {}

    ---@type neotoolkit.fileextmarks.MarkData
    local mark = {
        id = id,
        ns = group_data.ns,
        lnum = lnum,
        col = col,
        opts = vim.tbl_extend("force", { id = id }, opts or {}),
        user_data = user_data,
    }

    group_data.byfile[file][id] = mark

    if bufnr >= 0 then
        _set_extmark(bufnr, mark)
        _attach_buffer(bufnr, file)
    end
end

---@param id number
---@param group_data neotoolkit.fileextmarks.GroupData
local function _remove_extmark(id, group_data)
    local file = group_data.id_to_file[id]
    if not file then return end

    group_data.id_to_file[id] = nil

    local file_table = group_data.byfile[file]
    if not file_table then return end

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        vim.api.nvim_buf_del_extmark(bufnr, group_data.ns, id)
    end

    file_table[id] = nil
    _release_file(group_data, file)
end

---@param file string
---@param group_data neotoolkit.fileextmarks.GroupData
local function _remove_file_extmarks(file, group_data)
    file = _normalize_file(file)

    local file_table = group_data.byfile[file]
    if not file_table then return end

    for id in pairs(file_table) do
        group_data.id_to_file[id] = nil
    end

    group_data.byfile[file] = nil

    local bufnr = _get_loaded_bufnr(file)
    if bufnr >= 0 then
        _clear_buf_namespace(bufnr, group_data.ns)
    end

    _forget_bufnr(file)
end

---@param group_data neotoolkit.fileextmarks.GroupData
local function _remove_extmarks(group_data)
    local files = {}
    for file in pairs(group_data.byfile) do
        files[#files + 1] = file
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            _clear_buf_namespace(bufnr, group_data.ns)
        end
    end

    group_data.byfile = {}
    group_data.id_to_file = {}

    for _, file in ipairs(files) do
        _forget_bufnr(file)
    end
end

---@param id number
---@param group_data neotoolkit.fileextmarks.GroupData
---@return neotoolkit.fileextmarks.MarkInfo?
local function _get_extmark_by_id(id, group_data)
    local file = group_data.id_to_file[id]
    if not file then return nil end

    local mark = (group_data.byfile[file] or {})[id]
    if not mark then return nil end

    return {
        id = mark.id,
        file = file,
        lnum = mark.lnum,
        col = mark.col,
        opts = mark.opts,
        user_data = mark.user_data,
        source = "stored",
    }
end

---@param file string
---@param line number
---@param group_data neotoolkit.fileextmarks.GroupData
---@param live boolean
---@return neotoolkit.fileextmarks.MarkInfo?
local function _get_extmark_by_location(file, line, group_data, live)
    assert(type(live) == "boolean")
    assert(line >= 1, "line must be 1-based")

    file = _normalize_file(file)

    local file_table = group_data.byfile[file]
    if not file_table then return nil end

    local bufnr = live and _get_loaded_bufnr(file) or -1
    if bufnr >= 0 then
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if line > line_count then return nil end

        -- Bounded to the line asked for rather than walking the namespace. The
        -- last line has to reach past the end too: a mark stranded there reads
        -- as sitting on it (see `_read_live_marks`), which `_on_lines` normally
        -- repairs but a buffer we failed to attach to can still be holding.
        local last = line == line_count and { -1, -1 } or { line - 1, -1 }
        local found = vim.api.nvim_buf_get_extmarks(
            bufnr,
            group_data.ns,
            { line - 1, 0 },
            last,
            { details = false }
        )

        for _, m in ipairs(found) do
            local mark = file_table[m[1]]
            if mark then
                return {
                    id = m[1],
                    file = file,
                    lnum = line,        -- every hit in this range reads as `line`
                    col = m[3],
                    opts = mark.opts,
                    user_data = mark.user_data,
                    source = "live",
                }
            end
        end

        return nil
    end

    for id, mark in pairs(file_table) do
        if mark.lnum == line then
            return {
                id = id,
                file = file,
                lnum = mark.lnum,
                col = mark.col,
                opts = mark.opts,
                user_data = mark.user_data,
                source = "stored",
            }
        end
    end

    return nil
end

---@param group_data neotoolkit.fileextmarks.GroupData
---@param live boolean
---@return neotoolkit.fileextmarks.MarkInfo[]
local function _get_extmarks(group_data, live)
    assert(type(live) == "boolean")

    local result = {}

    for file, file_table in pairs(group_data.byfile) do
        local bufnr = live and _get_loaded_bufnr(file) or -1
        if bufnr >= 0 then
            for _, m in ipairs(_read_live_marks(bufnr, file_table, group_data.ns)) do
                local mark = file_table[m.id]
                result[#result + 1] = {
                    id = m.id,
                    file = file,
                    lnum = m.lnum,
                    col = m.col,
                    opts = mark.opts,
                    user_data = mark.user_data,
                    source = "live",
                }
            end
        else
            for id, mark in pairs(file_table) do
                result[#result + 1] = {
                    id = id,
                    file = file,
                    lnum = mark.lnum,
                    col = mark.col,
                    opts = mark.opts,
                    user_data = mark.user_data,
                    source = "stored",
                }
            end
        end
    end

    return result
end

---@param file string
---@param group_data neotoolkit.fileextmarks.GroupData
---@param live boolean
---@return neotoolkit.fileextmarks.MarkInfo[]
local function _get_file_extmarks(file, group_data, live)
    assert(type(live) == "boolean")

    file = _normalize_file(file)
    local result = {}

    local file_table = group_data.byfile[file]
    if not file_table then return result end

    local bufnr = live and _get_loaded_bufnr(file) or -1
    if bufnr >= 0 then
        for _, m in ipairs(_read_live_marks(bufnr, file_table, group_data.ns)) do
            local mark = file_table[m.id]
            result[#result + 1] = {
                id = mark.id,
                file = file,
                lnum = m.lnum,
                col = m.col,
                opts = mark.opts,
                user_data = mark.user_data,
                source = "live",
            }
        end
    else
        for _, mark in pairs(file_table) do
            result[#result + 1] = {
                id = mark.id,
                file = file,
                lnum = mark.lnum,
                col = mark.col,
                opts = mark.opts,
                user_data = mark.user_data,
                source = "stored",
            }
        end
    end

    return result
end

---@param group_data neotoolkit.fileextmarks.GroupData
---@param group string
local function _refresh_group(group_data, group)
    for file in pairs(group_data.byfile) do
        local bufnr = _get_loaded_bufnr(file)
        if bufnr >= 0 then
            _clear_buf_namespace(bufnr, group_data.ns)
            _apply_buffer_extmarks(bufnr, group)
        end
    end
end

---@class neotoolkit.fileextmarks.GroupFunctions
---@field set_file_extmark fun(id:number, file:string, lnum:number, col:number, opts:vim.api.keyset.set_extmark, user_data:any)
---@field remove_extmarks fun()
---@field remove_extmark fun(id:number)
---@field remove_file_extmarks fun(file:string)
---@field get_extmark_by_id fun(id:number): neotoolkit.fileextmarks.MarkInfo?
---@field get_extmark_by_location fun(file:string, line:number, live:boolean): neotoolkit.fileextmarks.MarkInfo?
---@field get_extmarks fun(live:boolean): neotoolkit.fileextmarks.MarkInfo[]
---@field get_file_extmarks fun(file:string, live:boolean): neotoolkit.fileextmarks.MarkInfo[]
---@field refresh fun()

--- Claims the prefix used for every namespace and augroup this module creates.
--- Must be called (once) before M.define_group().
---@param prefix string  unique to the calling plugin, e.g. "myplugin"
function M.init(prefix)
    assert(type(prefix) == "string" and prefix ~= "", "prefix (non-empty string) required")
    assert(not _prefix or _prefix == prefix, ("already initialized with prefix %q"):format(_prefix))

    _prefix = prefix
end

---@param group string  name, unique within this module instance; used to derive the extmark namespace
---@return neotoolkit.fileextmarks.GroupFunctions
function M.define_group(group)
    _require_prefix()
    assert(type(group) == "string", "group (string) required")
    assert(not _defined_groups[group], "group already defined")

    ---@type neotoolkit.fileextmarks.GroupData
    local group_data = {
        ns = vim.api.nvim_create_namespace(_prefixed(group)),
        byfile = {},
        id_to_file = {},
    }
    _defined_groups[group] = group_data

    _register_autocmds()

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            _apply_buffer_extmarks(bufnr, group)
        end
    end

    ---@type neotoolkit.fileextmarks.GroupFunctions
    return {
        set_file_extmark = function(id, file, lnum, col, opts, user_data)
            _set_file_extmark(id, file, lnum, col, group_data, opts, user_data)
        end,
        remove_extmark = function(id)
            _remove_extmark(id, group_data)
        end,
        remove_file_extmarks = function(file)
            _remove_file_extmarks(file, group_data)
        end,
        remove_extmarks = function()
            _remove_extmarks(group_data)
        end,
        get_extmark_by_id = function(id)
            return _get_extmark_by_id(id, group_data)
        end,
        get_extmark_by_location = function(file, line, live)
            return _get_extmark_by_location(file, line, group_data, live)
        end,
        get_extmarks = function(live)
            return _get_extmarks(group_data, live)
        end,
        get_file_extmarks = function(file, live)
            return _get_file_extmarks(file, group_data, live)
        end,
        refresh = function()
            _refresh_group(group_data, group)
        end,
    }
end

return M
