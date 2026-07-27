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

    describe("escaped whitespace", function()
        it("joins an argument across an escaped space", function()
            assert.same({ "a b" }, split([[a\ b]]))
            assert.same({ "a b c" }, split([[a\ b\ c]]))
        end)

        it("joins an argument across an escaped tab", function()
            assert.same({ "a\tb" }, split("a\\\tb"))
        end)

        it("keeps escaped whitespace at the edges of an argument", function()
            assert.same({ " a" }, split([[\ a]]))
            assert.same({ "a " }, split([[a\ ]]))
            assert.same({ " " }, split([[\ ]]))
        end)

        it("mixes escaped and unescaped whitespace", function()
            assert.same({ "one two", "three" }, split([[one\ two three]]))
            assert.same({ "cmd", "my file.txt", "-v" }, split([[cmd my\ file.txt -v]]))
        end)

        it("escapes a space inside a flag value", function()
            assert.same({ "--p=x y" }, split([[--p=x\ y]]))
        end)
    end)

    describe("escaped backslashes", function()
        it("collapses a doubled backslash to one", function()
            assert.same({ "a\\b" }, split([[a\\b]]))
            assert.same({ "\\" }, split([[\\]]))
            assert.same({ "a\\\\b" }, split([[a\\\\b]]))
        end)

        it("does not let an escaped backslash escape the next space", function()
            assert.same({ "a\\", "b" }, split([[a\\ b]]))
            assert.same({ "a\\ b" }, split([[a\\\ b]]))
        end)

        it("keeps a trailing backslash literally", function()
            assert.same({ "a\\" }, split([[a\]]))
            assert.same({ "\\" }, split([[\]]))
        end)
    end)

    describe("backslash before an ordinary character", function()
        it("keeps both the backslash and the character", function()
            assert.same({ "a\\nb" }, split([[a\nb]]))
            assert.same({ "\\d+" }, split([[\d+]]))
            assert.same({ "a\\b" }, split([[a\b]]))
        end)
    end)

    describe("quotes are not special", function()
        it("treats a double quote as an ordinary character", function()
            assert.same({ '"a', 'b"' }, split('"a b"'))
            assert.same({ '"a"' }, split('"a"'))
            assert.same({ '""' }, split('""'))
            assert.same({ 'a"b"c' }, split('a"b"c'))
        end)

        it("treats a single quote as an ordinary character", function()
            assert.same({ "'a", "b'" }, split("'a b'"))
            assert.same({ "it's" }, split("it's"))
        end)

        it("does not strip a quote escaped with a backslash", function()
            assert.same({ '\\"a' }, split([[\"a]]))
        end)

        it("needs a backslash, not quotes, to keep a phrase together", function()
            assert.same({ "say", "hello world" }, split([[say hello\ world]]))
        end)
    end)
end)
