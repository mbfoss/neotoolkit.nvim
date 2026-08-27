---@diagnostic disable: undefined-global, undefined-field
local strutil = require("neotoolkit.strutil")

--- Display cells the string occupies on screen.
---@param str string
---@return integer
local function cells(str)
    return vim.api.nvim_strwidth(str)
end

--- Graphemes in `str`, counting a combining sequence as the one it renders as.
---@param str string
---@return integer
local function graphemes(str)
    return vim.fn.strchars(str, 1)
end

--- The first (or, when `right`, last) `n` graphemes of `str`.
---@param str string
---@param n integer
---@param right? boolean
---@return string
local function take(str, n, right)
    if right then return vim.fn.strcharpart(str, graphemes(str) - n, n, 1) end
    return vim.fn.strcharpart(str, 0, n, 1)
end

--- `crop_for_ui` without its second return value, so it can be asserted inline.
---@param str string
---@param max_len integer
---@param right? boolean
---@return string
local function crop(str, max_len, right)
    return (strutil.crop_for_ui(str, max_len, right))
end

describe("strutil.pad_right", function()
    it("pads to the requested display width", function()
        assert.equals(8, cells(strutil.pad_right("abc", 8)))
        assert.equals(8, cells(strutil.pad_right("日本", 8)))
        assert.equals(8, cells(strutil.pad_right("cafe\u{0301}", 8)))
    end)

    it("leaves a string that is already wide enough alone", function()
        assert.equals("abcdef", strutil.pad_right("abcdef", 3))
        assert.equals("日本語", strutil.pad_right("日本語", 6))
    end)
end)

describe("strutil.fit_to_width", function()
    it("keeps the start of the string", function()
        assert.equals("hello", strutil.fit_to_width("hello world", 5))
        assert.equals("héllo", strutil.fit_to_width("héllo wörld", 5))
    end)

    it("keeps the end of the string when asked to cut from the left", function()
        assert.equals("world", strutil.fit_to_width("hello world", 5, true))
        assert.equals("wörld", strutil.fit_to_width("héllo wörld", 5, true))
    end)

    it("returns the string untouched when it already fits", function()
        assert.equals("hi", strutil.fit_to_width("hi", 99))
        assert.equals("日本", strutil.fit_to_width("日本", 4))
    end)

    it("returns nothing for a non-positive budget", function()
        assert.equals("", strutil.fit_to_width("hello", 0))
        assert.equals("", strutil.fit_to_width("hello", -3))
    end)

    it("counts double-width characters as two cells", function()
        assert.equals("日本", strutil.fit_to_width("日本語テスト", 4))
        assert.equals("スト", strutil.fit_to_width("日本語テスト", 4, true))
        assert.equals("a日", strutil.fit_to_width("a日b", 3))
    end)

    it("drops a character it cannot fit whole rather than overflowing", function()
        -- a 5-cell budget holds two double-width characters and no half of a third
        assert.equals("日本", strutil.fit_to_width("日本語テスト", 5))
        assert.equals("テスト", strutil.fit_to_width("日本語テスト", 7, true))
    end)

    it("keeps a combining mark with the character it decorates", function()
        -- "café" and "école" spelled with a combining acute rather than a
        -- precomposed é, so a naive per-codepoint cut would strand the mark
        assert.equals("cafe\u{0301}", strutil.fit_to_width("cafe\u{0301}", 4))
        assert.equals("e\u{0301}co", strutil.fit_to_width("e\u{0301}cole", 3))
        assert.equals("fe\u{0301}", strutil.fit_to_width("cafe\u{0301}", 2, true))
        -- never a bare mark at the front, which would compose onto the ellipsis
        assert.equals("…fe\u{0301}", crop("cafe\u{0301}", 3, true))
    end)

    it("keeps a zero-width-joiner sequence whole", function()
        local family = "\u{1F468}\u{200D}\u{1F469}" -- renders as one 2-cell glyph
        assert.equals(family, strutil.fit_to_width(family .. "x", 2))
        assert.equals(family .. "x", strutil.fit_to_width(family .. "x", 3))
        assert.equals("x", strutil.fit_to_width(family .. "x", 1, true))
    end)

    local INPUTS = {
        "héllo wörld", "日本語テスト", "a日b🎉x", "→ ok", "plain ascii",
        "cafe\u{0301}", "e\u{0301}cole", "\u{1F468}\u{200D}\u{1F469}x",
    }

    it("never exceeds the budget or splits a grapheme", function()
        for _, str in ipairs(INPUTS) do
            for width = 0, 14 do
                for _, right in ipairs({ false, true }) do
                    local got = strutil.fit_to_width(str, width, right)
                    assert.is_true(cells(got) <= width)
                    -- a run of whole graphemes taken from the requested end
                    assert.equals(take(str, graphemes(got), right), got)
                end
            end
        end
    end)

    it("fits as much as the budget allows", function()
        for _, str in ipairs(INPUTS) do
            for width = 0, 14 do
                for _, right in ipairs({ false, true }) do
                    local got = strutil.fit_to_width(str, width, right)
                    local kept = graphemes(got)
                    if kept < graphemes(str) then
                        -- it stopped because one more grapheme would not fit
                        assert.is_true(cells(take(str, kept + 1, right)) > width)
                    end
                end
            end
        end
    end)
end)

describe("strutil.crop_for_ui", function()
    it("returns the string unchanged when it fits", function()
        assert.same({ "abc", false }, { strutil.crop_for_ui("abc", 5) })
        assert.same({ "日本", false }, { strutil.crop_for_ui("日本", 4) })
    end)

    it("marks a cropped string with an ellipsis at the cut end", function()
        assert.same({ "abcd…", true }, { strutil.crop_for_ui("abcdefgh", 5) })
        assert.same({ "…efgh", true }, { strutil.crop_for_ui("abcdefgh", 5, true) })
    end)

    it("crops on character boundaries, not bytes", function()
        assert.equals("héllo…", crop("héllo wörld", 6))
        assert.equals("…wörld", crop("héllo wörld", 6, true))
        assert.equals("日本…", crop("日本語テスト", 5))
    end)

    it("keeps the result within the requested width", function()
        local inputs = {
            "héllo wörld", "日本語テスト", "a日b🎉x", "abcdefghij",
            "cafe\u{0301}", "\u{1F468}\u{200D}\u{1F469}x",
        }
        for _, str in ipairs(inputs) do
            for max_len = 3, 12 do
                assert.is_true(cells(crop(str, max_len)) <= max_len)
                assert.is_true(cells(crop(str, max_len, true)) <= max_len)
            end
        end
    end)

    it("clamps a max_len below the ellipsis budget", function()
        assert.equals(2, cells(crop("abcdefgh", 0)))
        assert.equals(2, cells(crop("abcdefgh", 1)))
    end)
end)
