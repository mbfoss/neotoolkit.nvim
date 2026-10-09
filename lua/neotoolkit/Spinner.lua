local timer = require('neotoolkit.timer')

local _default_frames = {
    "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"
}

---@class neotoolkit.SpinnerOpts
---@field frames string[]?   (default: ten spinning dots)
---@field interval integer?  milliseconds between frames (default: 80)
---@field on_update fun(frame:string, index:integer)?  called once per frame

--- An animation clock, not a widget: it advances a frame index on a timer and
--- hands the current frame to `on_update`. Where the frame is drawn —
--- statusline, virtual text, window title — is the caller's choice.
---@class neotoolkit.Spinner
---@field frames string[]
---@field interval integer
---@diagnostic disable-next-line: undefined-doc-name
---@field cancel_timer fun()?
---@field frame integer
---@field running boolean
---@field on_update fun(frame:string, index:integer)?
local Spinner = {}
Spinner.__index = Spinner

--- Create a spinner; call `start` to run it.
---@param opts neotoolkit.SpinnerOpts?
---@return neotoolkit.Spinner
function Spinner:new(opts)
    local obj = setmetatable({}, self)
    if obj.init then obj:init(opts) end
    return obj
end

---@private
---@param opts neotoolkit.SpinnerOpts?
function Spinner:init(opts)
    opts = opts or {}
    self.frames = opts.frames or _default_frames
    self.interval = opts.interval or 80
    self.cancel_timer = nil
    self.frame = 1
    self.running = false
    self.on_update = opts.on_update
end

--- Start advancing frames. Idempotent: a spinner already running is left alone.
function Spinner:start()
    if self.running then
        return
    end
    self.running = true
    self.cancel_timer = timer.every(self.interval, function()
        if not self.running then return end
        local frame = self.frames[self.frame]
        if self.on_update then self.on_update(frame, self.frame) end
        self.frame = (self.frame % #self.frames) + 1
    end)
end

--- Stop advancing frames. Idempotent: a stopped spinner is left alone.
function Spinner:stop()
    if not self.running then
        return
    end
    self.running = false
    if self.cancel_timer then self.cancel_timer() end
end

return Spinner
