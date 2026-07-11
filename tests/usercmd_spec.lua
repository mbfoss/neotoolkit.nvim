---@diagnostic disable: undefined-global, undefined-field
require("plenary.busted")

local usercmd = require("neotoolkit.usercmd")
local split = usercmd.split_args

describe("usercmd.split_args", function()
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
    end)

    describe("backslash escaping", function()
        it("drops an unquoted backslash and keeps the next char literally", function()
            assert.same({ "ab" }, split("a\\b"))
        end)

        it("escapes an unquoted space into a single arg", function()
            assert.same({ "a b" }, split("a\\ b"))
        end)

        it("escapes a quote so it is not treated as a delimiter", function()
            assert.same({ 'a"b' }, split('a\\"b'))
        end)

        it("keeps a trailing unquoted backslash literally", function()
            assert.same({ "a\\" }, split("a\\"))
        end)

        it("escapes a backslash into a single literal backslash", function()
            assert.same({ "a\\b" }, split("a\\\\b"))
        end)

        it("honors backslash for \" and \\ inside double quotes", function()
            assert.same({ 'a"b' }, split('"a\\"b"'))
            assert.same({ "a\\b" }, split('"a\\\\b"'))
        end)

        it("keeps a non-special backslash literally inside double quotes", function()
            assert.same({ "a\\nb" }, split('"a\\nb"'))
        end)

        it("treats backslash as literal inside single quotes", function()
            assert.same({ "a\\b" }, split("'a\\b'"))
        end)
    end)
end)
