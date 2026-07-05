---@diagnostic disable: undefined-global, undefined-field
require("plenary.busted")

local usercmd = require("neotoolkit.usercmd")
local split = usercmd._split_args

describe("usercmd._split_args", function()
    describe("plain splitting", function()
        it("returns an empty table for an empty string", function()
            assert.same({}, split(""))
        end)

        it("returns an empty table for whitespace only", function()
            assert.same({}, split("   "))
        end)

        it("splits on single spaces", function()
            assert.same({ "a", "b", "c" }, split("a b c"))
        end)

        it("collapses runs of whitespace", function()
            assert.same({ "a", "b" }, split("a    b"))
        end)

        it("splits on tabs and mixed whitespace", function()
            assert.same({ "a", "b", "c" }, split("a\tb \t c"))
        end)

        it("ignores leading and trailing whitespace", function()
            assert.same({ "a", "b" }, split("  a b  "))
        end)
    end)

    describe("double quoting", function()
        it("keeps spaces inside double quotes together", function()
            assert.same({ "a b" }, split('"a b"'))
        end)

        it("joins a quoted segment to an adjacent bare segment", function()
            assert.same({ "abc def" }, split('a"bc de"f'))
        end)

        it("handles a quoted arg among bare args", function()
            assert.same({ "cmd", "one two", "three" }, split('cmd "one two" three'))
        end)
    end)

    describe("single quoting", function()
        it("keeps spaces inside single quotes together", function()
            assert.same({ "a b" }, split("'a b'"))
        end)

        it("treats double quotes literally inside single quotes", function()
            assert.same({ 'say "hi"' }, split([['say "hi"']]))
        end)

        it("treats single quotes literally inside double quotes", function()
            assert.same({ "it's" }, split([["it's"]]))
        end)
    end)

    describe("empty and edge cases", function()
        it("preserves an empty quoted argument", function()
            assert.same({ "" }, split('""'))
        end)

        it("preserves an empty quoted argument between others", function()
            assert.same({ "a", "", "b" }, split('a "" b'))
        end)

        it("treats an unterminated quote as running to end of input", function()
            assert.same({ "a b" }, split('"a b'))
        end)

        it("does not treat backslash as an escape", function()
            assert.same({ "a\\b" }, split("a\\b"))
        end)

        it("keeps a backslash-space as two separate args", function()
            assert.same({ "a\\", "b" }, split("a\\ b"))
        end)
    end)
end)
