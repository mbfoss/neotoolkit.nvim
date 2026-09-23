# neotoolkit.nvim

A Lua library for Neovim plugin development. Not an end-user plugin: it
registers no commands, no keymaps and no autocmds until a module is required and
used. Every module is standalone and returns its own table, class or function.

Requires Neovim 0.11+: `jobstart({term = true})`, the `err` field of
`nvim_echo()`, the current `vim.validate()` signature, and `vim.lsp.Client`
methods called with `:`.

## Installation

Declare it as a dependency of your plugin; do not call `setup()` — there is none.

```lua
-- lazy.nvim
{ "your/plugin", dependencies = { "mbfoss/neotoolkit.nvim" } }
```

```lua
local strutil = require("neotoolkit.strutil")
```

## Modules

| Module | Returns | Purpose |
| -------------------------- | -------- | -------------------- |
| [`neotoolkit.Signal`](#neotoolkitsignal) | class | Typed listener list with unsubscribe handles |
| [`neotoolkit.LRU`](#neotoolkitlru) | class | LRU cache with eviction hooks |
| [`neotoolkit.Spinner`](#neotoolkitspinner) | class | Frame-based spinner driven by a timer |
| [`neotoolkit.Tree`](#neotoolkittree) | class | Ordered tree keyed by opaque ids |
| [`neotoolkit.TreeBuffer`](#neotoolkittreebuffer) | class | Renders a `Tree` into a scratch buffer |
| [`neotoolkit.timer`](#neotoolkittimer) | table | `vim.uv` timer wrappers that return a stop function |
| [`neotoolkit.throttle`](#neotoolkitthrottle) | table | Throttle and debounce wrappers |
| [`neotoolkit.strutil`](#neotoolkitstrutil) | table | Width-aware cropping, shell splitting, glob matching |
| [`neotoolkit.fsutil`](#neotoolkitfsutil) | table | Async directory walks, rename, copy, trash |
| [`neotoolkit.ui`](#neotoolkitui) | table | Window/buffer creation, file opening, colour blending |
| [`neotoolkit.color`](#neotoolkitcolor) | table | Colorscheme-reactive highlight groups |
| [`neotoolkit.floatwin`](#neotoolkitfloatwin) | table | Centred, dismissable text float |
| [`neotoolkit.inputwin`](#neotoolkitinputwin) | table | Single-line input float with validation |
| [`neotoolkit.hover`](#neotoolkithover) | table | LSP-style hover at the cursor |
| [`neotoolkit.fixedwin`](#neotoolkitfixedwin) | table | Split pinned to a ratio of the editor |
| [`neotoolkit.term`](#neotoolkitterm) | table | Command in a terminal buffer |
| [`neotoolkit.spawn`](#neotoolkitspawn) | function | `vim.uv.spawn` with pipe lifetime handled |
| [`neotoolkit.usercmd`](#neotoolkitusercmd) | table | Subcommand dispatch and completion |
| [`neotoolkit.fileextmarks`](#neotoolkitfileextmarks) | table | Extmarks that survive buffer unload |

---

## neotoolkit.Signal <!-- tag: signal -->

An observable event with a typed payload: the producer owns the `Signal` and
emits, consumers subscribe and hold the returned unsubscribe function. Use it
where a single `on_*` callback option would otherwise have to be multiplexed by
hand.

`Signal.new() -> Signal`

| Method | Signature |
| ----------- | ------------------------- |
| `subscribe` | `(fn) -> fun() unsubscribe` |
| `unsubscribe` | `(fn)` |
| `emit` | `(...)` |

Listeners are called over a snapshot of the list, so a listener may subscribe or
unsubscribe during `emit`. A listener that raises is reported via
`nvim_echo` with `ErrorMsg`; the remaining listeners still run.

```lua
local Signal = require("neotoolkit.Signal")
---@type neotoolkit.Signal<fun(path:string)>
local on_change = Signal.new()
local cancel = on_change:subscribe(function(path) vim.print(path) end)
on_change:emit("/tmp/x")
cancel()
```

## neotoolkit.LRU <!-- tag: lru -->

A bounded cache with least-recently-used eviction, for anything expensive to
recompute per item — file stats, rendered lines, parsed output. The eviction
hooks make it usable for values that own a resource, such as a buffer to wipe
or a handle to close.

`LRU:new(capacity, opts?) -> LRU`

| Option | Type | Called for |
| ---------- | --------------- | -------- |
| `on_evict` | `fun(key, value)` | capacity overflow only |
| `on_removed` | `fun(key, value)` | every removal (evict, delete, clear) |

| Method | Signature | Notes |
| ---------- | ----------------------- | ----------- |
| `get` | `(key) -> any?` | promotes to most-recent |
| `peek` | `(key) -> any?` | no promotion |
| `put` | `(key, value)` | evicts the tail at capacity |
| `promote` | `(key)` | |
| `delete` | `(key)` | |
| `has` | `(key) -> boolean` | |
| `clear` | `()` | |
| `size` | `() -> integer` | |
| `keys` | `() -> any[]` | most-recent first |
| `iter_items` | `() -> fun(): key, value` | most-recent first |

## neotoolkit.Spinner <!-- tag: spinner -->

An animation clock, not a widget: it advances a frame index on a timer and hands
the current frame to `on_update`. Where the frame is drawn — statusline, virtual
text, window title — is the caller's choice.

`Spinner:new(opts?) -> Spinner`

| Option | Type | Default |
| --------- | -------------------------------- | -------- |
| `frames` | `string[]` | spinning dots, 10 frames |
| `interval` | `integer` (ms) | `80` |
| `on_update` | `fun(frame:string, index:integer)` | none |

`start()` and `stop()` are idempotent. `on_update` runs on the main loop
(`vim.schedule_wrap`), so it may touch buffers and windows.

## neotoolkit.Tree <!-- tag: tree -->

Ordered tree of nodes keyed by caller-supplied ids, for hierarchical data that
is updated in place — a file tree, a symbol outline, a result set grouped by
file. Nodes hold `parent_id`, `data` and sibling/child links; there is no node
object to hold on to, and ids must be unique across the whole tree.

`Tree.new() -> Tree`

| Method | Signature |
| ------------------- | --------------------------------- |
| `add_item` | `(parent_id, id, data)` — `parent_id` nil appends a root |
| `add_sibling` | `(reference_id, id, data, before?)` |
| `set_children` | `(parent_id, items)` — replaces the subtree |
| `update_children` | `(parent_id, items)` — diffs; `keep_children` preserves a subtree |
| `set_item_data` | `(id, data)` |
| `remove_item` | `(id)` / `remove_children(id)` |
| `get_data` / `get_depth` / `get_parent_id` | `(id) -> any` |
| `get_roots` / `get_items` | `() -> Item[]` |
| `get_children` / `get_children_ids` | `(parent_id) -> …` |
| `get_first_child_id` / `get_last_child_id` | `(id) -> any?` |
| `get_prev_sibling_id` / `get_next_sibling_id` | `(id) -> any?` |
| `have_item` / `have_children` / `is_root` | `(id) -> boolean` |
| `iter_roots` / `iter_children` | `(…) -> iterator` |
| `walk_tree` | `(handler)` — handler returns false to skip a subtree |
| `walk_node` | `(id, handler)` |
| `validate` | `()` — asserts link consistency; for tests |

## neotoolkit.TreeBuffer <!-- tag: treebuffer -->

A rendered `Tree`: it owns the tree, a scratch buffer and a namespace, keeps the
buffer in step with every mutation, and re-renders only the range that changed.
The caller supplies the tree contents and a formatter; expansion state,
indentation, guides, highlights and cursor mapping are handled here.

`TreeBuffer.new(opts) -> TreeBuffer`

| Option | Type | Default |
| ------------------ | -------- | ------------------------- |
| `formatter` | `function` | required |
| `filetype` | `string` | `"neotoolkit-tree"` |
| `collapsible` | `boolean` | `true` |
| `expand_symbol` | `string` | `"›"` |
| `collapse_symbol` | `string` | `"⌄"` |
| `expand_symbol_hl` | `string` | none |
| `collapse_symbol_hl` | `string` | none |
| `indent_string` | `string` | `"  "` |
| `indent_guides` | `boolean` | `true` |
| `indent_guide_char` | `string` | `"│"` |
| `indent_guide_hl` | `string` | `NeotoolkitTreeIndentGuide` |

`formatter` is `fun(id, data, expanded, prefix_width)` returning `chunks`,
`virt_text` and `line_hl`. The first two are lists of `{text, hl_group}` pairs.
`prefix_width` is the display width already consumed by the indent and the
expand symbol — use it to budget the remaining columns.

| Method | Signature |
| ------------------- | ----------------------------------------- |
| `create_buffer` | `(on_deleted) -> bufnr, created` |
| `get_bufnr` / `get_winid` | `() -> integer` |
| `subscribe` | `({on_selection?, on_toggle?}) -> {cancel}` |
| `set_children` / `merge_children` | `(parent_id, children)` |
| `add_item` / `add_sibling` | `(parent_id\|reference_id, item, before?)` |
| `remove_item` / `remove_children` / `clear_items` | `(id?)` |
| `set_item_data` / `set_item_expandable` / `refresh_item` | `(id, …)` |
| `expand` / `collapse` / `toggle_expand` | `(id)` |
| `expand_all` / `collapse_all` | `(id?)` |
| `get_item` / `get_item_data` / `get_parent_item` | `(id) -> …` |
| `get_cursor_item` / `get_item_at_row` | `(row?) -> id, data` |
| `set_cursor_by_id` | `(id)` |
| `get_items` / `get_roots` / `get_visible_items` | `(winid?) -> Item[]` |
| `is_visible` / `have_item` / `have_children` | `(id) -> boolean` |
| `redraw` | `()` |

Default keymaps in the buffer: `<CR>` and `<2-LeftMouse>` toggle an expandable
node or emit `on_selection`; when `collapsible`, `zo`, `zc`, `za`, `zO`, `zC`.

```lua
local tb = require("neotoolkit.TreeBuffer").new({
    formatter = function(id, data, expanded, prefix_width)
        return { { data.name, "Directory" } }, {}, nil
    end,
})
local bufnr = tb:create_buffer(function() end)
tb:set_children(nil, {
    { id = "/", data = { name = "/" }, expandable = true },
})
```

## neotoolkit.timer <!-- tag: timer -->

`vim.uv` timers with the lifetime handled: each call returns a stop function, so
no handle has to be stored, checked for `is_closing` or closed by hand.

| Function | Signature |
| -------------------- | ------------------------------- |
| `defer` | `(interval_ms, fn) -> fun() stop` |
| `every` | `(interval_ms, fn) -> fun() stop` |
| `stop_and_close_timer` | `(timer?) -> nil` |

Callbacks are `vim.schedule_wrap`ped. `stop` closes the handle and is
idempotent.

## neotoolkit.throttle <!-- tag: throttle -->

Rate limiters for callbacks driven by events the plugin does not control —
autocmds, keystrokes, job output. The four variants differ only in when `fn`
runs relative to the window; pick by the table below.

| Function | Leading | Trailing | Resets |
| ----------------------------- | ------- | -------- | ------ |
| `throttle_wrap(ms, fn)` | yes | yes (one run) | no |
| `leading_throttle_wrap(ms, fn)` | yes | no | no |
| `trailing_fixed_wrap(ms, fn)` | no | yes | no |
| `debounce_wrap(ms, fn)` | no | yes | yes |

`debounce_wrap` returns `wrapped, cancel`. All wrappers skip `fn` when Neovim is
exiting (`v:exiting`). Only `leading_throttle_wrap` and `trailing_fixed_wrap`
forward arguments.

## neotoolkit.strutil <!-- tag: strutil -->

String handling for the two places Lua's own is not enough: text measured in
display cells rather than bytes, and text arriving as byte chunks rather than
lines.

| Function | Signature |
| ------------------------- | --------------------------------------------- |
| `pad_right` | `(str, cells) -> string` |
| `fit_to_width` | `(str, cells, right?) -> string` — cuts between graphemes, no ellipsis |
| `crop_for_ui` | `(str, max_cells, right?) -> string, changed` — adds `…` |
| `human_case` | `(str) -> string` |
| `prepare_buffer_lines` | `(lines) -> string[]` — splits embedded newlines |
| `clean_and_split_lines` | `(lines) -> string[]` — strips `\r`, drops empties |
| `create_line_buffered_feed` | `(cb) -> fun(chunk)` — emits complete lines only |
| `split_shell_args` | `(str) -> string[]` |
| `cmd_to_string_array` | `(string\|string[]) -> string[]` |
| `get_shell_command` | `(argv) -> string` — quotes for display/logging |
| `indent_errors` | `(errors?, parent_msg) -> string[]` |
| `compile_glob` | `(glob) -> vim.regex?, err?` — nil on invalid glob |
| `any_match` | `(str, regex[]) -> boolean` |
| `matches_any` | `(path, glob_patterns) -> boolean` |
| `check_path_pattern` | `(path, is_dir, include?, exclude?) -> boolean` |

`compile_glob` returns the error rather than raising, so globs may come from
live user input.

## neotoolkit.fsutil <!-- tag: fsutil -->

Filesystem access that keeps the UI responsive: the directory walks yield to the
event loop instead of blocking, and rename, copy and trash handle the editor and
platform details a plain `vim.uv` call leaves to the caller.

| Function | Signature |
| -------------------- | ------------------------------------------------- |
| `file_exists` / `dir_exists` | `(path) -> boolean` |
| `make_dir` / `create_file` | `(path) -> ok, err?` |
| `read_content` | `(path) -> ok, content\|err` |
| `write_content` | `(path, data) -> ok, err?` |
| `get_relative_path` | `(path, base?) -> string?` |
| `async_load_text_file` | `(path, {max_size?, timeout?}?, cb) -> fun() abort` |
| `async_scan_dir` | `(dir, include?, exclude?, on_file, on_done)` `-> fun() cancel` |
| `async_walk_dir` | `(dir, opts) -> fun() cancel` |
| `monitor_dir` | `(dir, cb) -> fun()? cancel, err?` |
| `rename_file` | `(from, to) -> ok, err?` — updates buffers, notifies LSP |
| `copy_path` | `(from, to) -> ok, err?` — recursive, preserves symlinks |
| `has_trash` / `trash_path` | `() -> boolean` / `(path) -> ok, err?` |

`async_walk_dir` opts: `include_regex_list`, `exclude_regex_list`,
`on_dir_enter`, `on_file(filepath, filename, relative_path)`, `on_done`,
`follow_symlinks`, `slice_ms` (default 10), `yield_ms` (default 1). The walk
parks on a timer between slices so libuv returns to the main loop; a
`vim.schedule` chain would not yield on a deep tree.

`trash_path` resolves a platform mechanism once and caches it; check
`has_trash()` before offering the action.

## neotoolkit.ui <!-- tag: ui -->

Window and buffer primitives for plugins that own a panel. `smart_open_file` and
`smart_open_buffer` are the important pair: they open a result in a window the
user would expect, rather than inside the plugin's own float or fixed window.

| Function | Signature |
| --------------------- | ------------------------------------------------ |
| `create_window` | `(buf, enter, config, on_close) -> winid, augroup` |
| `create_scratch_buffer` | `(listed, bo?, on_delete?) -> bufnr` |
| `win_setlocal` | `(win, opt, val)` — `scope = "local"`, unlike `vim.wo` |
| `smart_open_file` | `(path, line?, col?, activate?) -> winid, bufnr` |
| `smart_open_buffer` | `(bufnr, line?, col?, activate?) -> winid` |
| `confirm_action` | `(msg, default_yes, cb)` — `cb(nil)` on abort |
| `fill_viewport` | `(winid)` — scrolls content into trailing blank space |
| `unique_buf_name` | `(basename) -> string` |
| `normalize_color` | `(integer\|"#rrggbb") -> integer` |
| `blend_colors` | `(c1, c2, alpha) -> integer` |

`smart_open_file` skips floats and `winfixbuf` windows, reuses a window already
showing the buffer, and splits only when no regular window exists. It returns
`-1, -1` when the load aborts (swap-file prompt, unreadable file, `E37`).

`create_scratch_buffer` sets `filetype` last, after `on_delete` is hooked up, so
`FileType` handlers see the final options.

## neotoolkit.color <!-- tag: color -->

Highlight groups defined as a function of the current colorscheme, so a plugin
can derive its colours from existing groups instead of hardcoding them and still
follow a theme switch.

| Function | Signature |
| ---------------- | ------------------------------------------- |
| `mix` | `(fg, bg, pct) -> integer` |
| `faded_hl_info` | `(src, pct, bg?) -> vim.api.keyset.highlight` |
| `create_themed_hl` | `({name, spec})` |

`create_themed_hl` evaluates `spec` now and again on every `ColorScheme` event,
under a shared `NeotoolkitThemedHl` augroup. `faded_hl_info` takes only the text
colour of `src`, so no block is painted behind the text, and links to `src` when
it has none.

```lua
color.create_themed_hl({
    name = "MyPluginDim",
    spec = function() return color.faded_hl_info("Comment", 50) end,
})
```

## neotoolkit.floatwin <!-- tag: floatwin -->

A read-only float for a block of text — help, a diff, a summary. Fire and
forget: it owns its buffer and closes itself.

`open(text, opts?)`

| Option | Type | Notes |
| ------------ | ------- | ----------- |
| `title` | `string` | centred in the border |
| `is_markdown` | `boolean` | starts the markdown treesitter parser |
| `conceallevel` | `integer` | default 3; pass 0 to keep fixed-width content in column |

Sized to the content, capped at 80% of the editor. Closes on `q`, `<Esc>` or
`WinLeave`.

## neotoolkit.inputwin <!-- tag: inputwin -->

A `vim.ui.input` replacement for cases needing validation before the window
closes, so a rejected value can be corrected in place rather than re-prompted.

`open(opts, on_confirm)`

| Option | Type |
| ------------- | ----------------------------- |
| `prompt` | `string` |
| `default` | `string` |
| `default_width` | `number` |
| `row_offset` / `col_offset` | `number` |
| `validate` | `fun(content) -> boolean, err?` |

Opens at the cursor in insert mode and grows with the text. `<CR>` confirms
(subject to `validate`), `<C-c>`, `<Esc>` and `WinLeave` cancel. `on_confirm`
receives `nil` on cancel and runs after the window has closed and focus has
returned.

## neotoolkit.hover <!-- tag: hover -->

A transient float at the cursor, for text belonging to whatever the cursor is
on — a definition, a blame line, an error. It behaves like an LSP hover because
it is built on one.

`show(text, opts?) -> bufnr?, winid?`

| Option | Type |
| -------- | ----------- |
| `title` | `string` |
| `syntax` | `string` |
| `focus_id` | `string` (default: one id for all of neotoolkit) |

Built on `vim.lsp.util.open_floating_preview`: opens unfocused at the cursor and
closes on cursor move; calling it again from the same buffer focuses it, where
`q` or `<Esc>` closes it. The window is re-fitted against the whole screen
rather than the current window, and anchored up or left when it would not fit.
Returns `nil` when `text` is blank.

## neotoolkit.fixedwin <!-- tag: fixedwin -->

A panel split that keeps its proportion of the editor as the layout changes,
instead of the fixed line count a plain `:split` leaves behind once other
windows open, close or move.

`create_fixed_win(buf, opts) -> winid, augroup`

| Option | Type | Default |
| --------- | ---------- | -------- |
| `axis` | `"height"\|"width"` | required |
| `ratio` | `number` (0..1) | required |
| `min` | `integer` | `1` |
| `pos` | `"topleft"\|"botright"` | `"botright"` |
| `enter` | `boolean` | `false` |
| `on_delete` | `fun(ratio)` | none |

A split pinned to `ratio` of the editor lines/columns, re-applied on `WinNew`,
`VimResized`, `WinResized` and `WinClosed`. Manual resizes update the tracked
ratio, and `on_delete` reports the last-known one so it can be persisted. Moved
across the layout (`<C-w>L`), it re-pins along the cross axis; the fix option is
cleared when no sibling frame can absorb the freed space.

## neotoolkit.term <!-- tag: term -->

Runs a command in a terminal buffer the caller can display where it likes, with
ANSI rendering handled by Neovim. For a job whose output is parsed rather than
shown, use `neotoolkit.spawn`.

| Function | Signature |
| -------- | ---------------------------------------- |
| `spawn` | `(cmd, opts, bufnr?) -> TermHandle?, err?` |
| `rename` | `(bufnr, bufname?)` |

`TermHandle` is `{ bufnr, pid, stop }`. `opts`: `bufname`, `cwd`, `env`,
`clear_env`, `on_stdout`, `on_stderr`, `on_exit`, `line_buffered`.

`jobstart({term = true})` requires the buffer to be in a window, so the terminal
is opened in a hidden full-size float that is closed again before returning.
`line_buffered` wraps the callbacks so they never see the partial fragment
Neovim puts last in each chunk. On `TermClose`, editing keys are mapped to
`<Nop>`.

## neotoolkit.spawn <!-- tag: spawn -->

A `vim.uv.spawn` wrapper for jobs whose output is consumed as data: raw stdout
and stderr chunks, optional stdin, and an exit callback that cannot fire before
the output has been delivered.

`spawn(cmd, opts, on_exit) -> SpawnHandle?, err?`

`opts`: `cwd`, `env`, `stdin` (opt-in pipe), `stdout(data)`, `stderr(data)`.
`SpawnHandle` is `{ kill, write, get_write_queue_size }`.

`on_exit(code)` fires only once both pipes have reached EOF, so no output is
lost. `env` is merged over `vim.fn.environ()` — `vim.uv.spawn` replaces the
child environment wholesale, so a bare dict would drop `PATH`. `write(nil)`
shuts down stdin after queued writes flush. A failed exec returns
`nil, err` and still calls `on_exit(-1)`.

```lua
local spawn = require("neotoolkit.spawn")
local handle, err = spawn({ "rg", "--json", "foo" }, {
    cwd = vim.uv.cwd(),
    stdout = feed,
}, function(code) vim.print(code) end)
```

## neotoolkit.usercmd <!-- tag: usercmd -->

The two halves of a `:Command sub arg` interface — dispatch and completion —
splitting arguments exactly as Vim does and keeping the plugin off the startup
path.

| Function | Signature |
| -------- | -------------------------------------------- |
| `handle` | `(opts, run_fn)` |
| `complete` | `(arg_lead, cmd_line, subcommand) -> string[]` |

For commands registered with `nargs = "*"`. Both are meant to be called from
inside the command's callbacks, so the module — and whatever the callbacks close
over — is loaded on first use rather than at startup. No argument parsing of its
own: dispatch passes Neovim's `fargs` through and completion runs the command
line back through `nvim_parse_cmd`, so both split by Vim's native rules.
`handle` reports an error from `run_fn` as a notification, not a traceback.

```lua
vim.api.nvim_create_user_command("MyCmd", function(opts)
    require("neotoolkit.usercmd").handle(opts, require("myplugin").run)
end, {
    nargs = "*",
    complete = function(arg_lead, cmd_line)
        return require("neotoolkit.usercmd").complete(
            arg_lead, cmd_line, require("myplugin").subcommand)
    end,
})
```

## neotoolkit.fileextmarks <!-- tag: fileextmarks -->

Extmarks addressed by file path rather than by buffer: positions are stored,
applied when the file is opened, tracked through edits, and written back on
unload, so marks survive a buffer being wiped and land on files that are never
opened.

`M.init(prefix)` once per plugin, then `M.define_group(group) -> GroupFunctions`.

| Group function | Signature |
| ----------------------- | -------------------------------------- |
| `set_file_extmark` | `(id, file, lnum, col, opts, user_data)` — `lnum` 1-based, `col` 0-based |
| `remove_extmark` / `remove_file_extmarks` / `remove_extmarks` | `(id)` / `(file)` / `()` |
| `get_extmark_by_id` | `(id) -> MarkInfo?` |
| `get_extmark_by_location` | `(file, line, live) -> MarkInfo?` |
| `get_extmarks` / `get_file_extmarks` | `(live)` / `(file, live) -> MarkInfo[]` |
| `refresh` | `()` |

`live` selects the position in the open buffer over the stored one; `MarkInfo.source`
reports which was used. Paths are normalized through `resolve()`, so every
spelling of a file — relative, or through a symlinked component — lands on one
key. Tracking uses `nvim_buf_attach`/`on_lines`, not `TextChanged`, so API edits
such as `nvim_buf_set_lines` move marks too. Positions are written back to the
cache only from a buffer whose text matches the file on disk.

`init` asserts on a second, different prefix, and `define_group` asserts on a
namespace clash, which catches a second copy of the module claiming the same
prefix.

## Development <!-- tag: development -->

```sh
make test
make test BUSTED_ARGS="--filter=crop_for_ui -o gtest"
```

Specs run under busted with `nlua`, so they execute inside Neovim and can use
the `vim` API. busted and nlua install into a gitignored project-local luarocks
tree (`.luarocks`) on first run. `tests/init.lua` prepends the repo to
`runtimepath` and `package.path` and restores what `-u NONE` omits.

`doc/neotoolkit.txt` is generated from this file; edit the README, never the
help file.

```sh
scripts/gendoc.sh           # rewrite doc/neotoolkit.txt and doc/tags
scripts/gendoc.sh --check   # exit 1 when the help file is out of date
```

Needs pandoc; panvimdoc is fetched and cached at a pinned commit on first run.
Section help tags come from a hidden comment on the heading
(`## neotoolkit.ui <!-- tag: ui -->` yields `*neotoolkit-ui*`).

Table columns in the help file are sized from the dash counts in each
separator row, scaled to 72 columns, except that a column is never narrower
than its widest unbreakable atom — a `code span` is one atom, so a cell holding
a single long signature widens the whole table past 78 columns. Split such a
cell into two spans, or move the signature into the prose below the table.
