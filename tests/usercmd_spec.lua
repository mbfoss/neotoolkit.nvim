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

    describe("single quotes", function()
        it("treats a single quote as an ordinary character", function()
            assert.same({ "'a", "b'" }, split("'a b'"))
        end)

        it("keeps single quotes inside a double-quoted span", function()
            assert.same({ "it's" }, split([["it's"]]))
        end)

        it("keeps an apostrophe in a bare arg", function()
            assert.same({ "it's" }, split("it's"))
        end)
    end)

    describe("empty and edge cases", function()
        it("preserves an empty quoted argument", function()
            assert.same({ "" }, split('""'))
        end)

        it("preserves an empty quoted argument between others", function()
            assert.same({ "a", "", "b" }, split('a "" b'))
        end)

        it("keeps an unterminated quote literally and runs to end of input", function()
            assert.same({ '"a b' }, split('"a b'))
        end)

        it("keeps the opening quote of an unterminated span mid-arg", function()
            assert.same({ 'a"bc' }, split('a"bc'))
        end)
    end)

    describe("backslash escaping", function()
        it("keeps an unquoted backslash before an ordinary char literally", function()
            assert.same({ "a\\b" }, split("a\\b"))
        end)

        it("does not let a backslash escape a space", function()
            assert.same({ "a\\", "b" }, split("a\\ b"))
        end)

        it("escapes a quote so it does not open a span", function()
            assert.same({ 'a"b' }, split('a\\"b'))
        end)

        it("escapes a quote so it does not swallow the rest of the input", function()
            assert.same({ 'a"', "b" }, split('a\\" b'))
        end)

        it("keeps a trailing unquoted backslash literally", function()
            assert.same({ "a\\" }, split("a\\"))
        end)

        it("keeps a doubled backslash literally", function()
            assert.same({ "a\\\\b" }, split("a\\\\b"))
        end)

        it("escapes a quote inside a double-quoted span", function()
            assert.same({ 'a"b' }, split('"a\\"b"'))
            assert.same({ 'say "hi" there' }, split('"say \\"hi\\" there"'))
        end)

        it("keeps a non-quote backslash literally inside a double-quoted span", function()
            assert.same({ "a\\nb" }, split('"a\\nb"'))
            assert.same({ "a\\\\b" }, split('"a\\\\b"'))
        end)
    end)
end)
