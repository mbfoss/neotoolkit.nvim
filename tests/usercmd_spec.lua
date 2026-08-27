---@diagnostic disable: undefined-global, undefined-field
local usercmd = require("neotoolkit.usercmd")

--- Register a command, run `line`, and return the args its run_fn received.
---@param line string
---@return string[]
local function run(line)
    local got
    vim.api.nvim_create_user_command("NtkSpec", function(opts)
        usercmd.handle(opts, function(_, args) got = args end)
    end, { nargs = "*" })
    vim.cmd(line)
    pcall(vim.api.nvim_del_user_command, "NtkSpec")
    return got
end

--- Register a command with a subcommand handler and return what completion
--- passed it: the cmd name, the preceding args, and the arg being completed.
---@param cmd_line string
---@return table
local function complete(cmd_line)
    local seen
    vim.api.nvim_create_user_command("NtkSpec", function() end, {
        nargs = "*",
        complete = function(arg_lead, line, _)
            return usercmd.complete(arg_lead, line, function(cmd, rest, lead)
                seen = { cmd = cmd, rest = rest, lead = lead }
                return {}
            end)
        end,
    })
    vim.fn.getcompletion(cmd_line, "cmdline")
    pcall(vim.api.nvim_del_user_command, "NtkSpec")
    return seen or {}
end

describe("usercmd argument splitting", function()
    it("splits on unescaped whitespace", function()
        assert.same({ "a", "b", "c" }, run("NtkSpec a b c"))
        assert.same({ "a", "b" }, run("NtkSpec   a    b  "))
        assert.same({}, run("NtkSpec"))
    end)

    it("joins an argument across escaped whitespace", function()
        assert.same({ "a b" }, run([[NtkSpec a\ b]]))
        assert.same({ "my file.txt", "-v" }, run([[NtkSpec my\ file.txt -v]]))
        assert.same({ "--p=x y" }, run([[NtkSpec --p=x\ y]]))
        assert.same({ "a\tb" }, run("NtkSpec a\\\tb"))
    end)

    it("collapses a doubled backslash to one", function()
        assert.same({ "a\\b" }, run([[NtkSpec a\\b]]))
        assert.same({ "a\\", "b" }, run([[NtkSpec a\\ b]]))
        assert.same({ "a\\ b" }, run([[NtkSpec a\\\ b]]))
    end)

    it("keeps a backslash before an ordinary character", function()
        assert.same({ "a\\nb" }, run([[NtkSpec a\nb]]))
        assert.same({ "\\d+" }, run([[NtkSpec \d+]]))
        assert.same({ "a\\" }, run([[NtkSpec a\]]))
    end)

    it("treats quotes as ordinary characters", function()
        assert.same({ '"a', 'b"' }, run('NtkSpec "a b"'))
        assert.same({ 'a"b"c' }, run('NtkSpec a"b"c'))
        assert.same({ "it's" }, run("NtkSpec it's"))
    end)
end)

describe("usercmd completion", function()
    it("passes the command name and no context for the first argument", function()
        assert.same({ cmd = "NtkSpec", rest = {}, lead = "" }, complete("NtkSpec "))
        assert.same({ cmd = "NtkSpec", rest = {}, lead = "su" }, complete("NtkSpec su"))
    end)

    it("passes completed arguments as context, excluding the one in progress", function()
        assert.same({ "a" }, complete("NtkSpec a ").rest)
        assert.same({ "a" }, complete("NtkSpec a b").rest)
        assert.same({ "a", "b" }, complete("NtkSpec a b ").rest)
    end)

    it("applies escaping rules to the context arguments", function()
        assert.same({ "a b" }, complete([[NtkSpec a\ b ]]).rest)
    end)

    it("strips a range and command modifiers", function()
        assert.same({ cmd = "NtkSpec", rest = { "a" }, lead = "" }, complete("vert NtkSpec a "))
        assert.same({ cmd = "NtkSpec", rest = { "a" }, lead = "" }, complete("silent! NtkSpec a "))
    end)
end)
