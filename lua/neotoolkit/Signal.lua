--- An observable event with a typed payload: the producer owns the `Signal`
--- and emits, consumers subscribe and hold the returned unsubscribe function.
--- Use it where a single `on_*` callback option would otherwise have to be
--- multiplexed by hand.
---@class neotoolkit.Signal<T>
---@field _listeners T[]
local Signal = {}
Signal.__index = Signal

--- Create a signal with no listeners.
---@generic T: fun(...)
---@return neotoolkit.Signal<T>
function Signal.new()
    return setmetatable({ _listeners = {} }, Signal)
end

--- Add `fn` as a listener.
---@param fn T
---@return fun() unsubscribe
function Signal:subscribe(fn)
    table.insert(self._listeners, fn)
    return function() self:unsubscribe(fn) end
end

--- Remove a previously subscribed `fn`.
---@param fn T
function Signal:unsubscribe(fn)
    for i, l in ipairs(self._listeners) do
        if l == fn then
            table.remove(self._listeners, i)
            return
        end
    end
end

--- Call every listener with `...`. Listeners run over a snapshot, so one may
--- subscribe or unsubscribe during the call; a listener that raises is reported
--- with `ErrorMsg` and the rest still run.
---@param ... T
function Signal:emit(...)
    local snapshot = vim.list_slice(self._listeners)
    for _, fn in ipairs(snapshot) do
        local ok, err = xpcall(fn, debug.traceback, ...)
        if not ok then
            vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } },
                true, { err = true })
        end
    end
end

return Signal
