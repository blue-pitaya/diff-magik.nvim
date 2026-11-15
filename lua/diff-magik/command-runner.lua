local util = require("diff-magik.util")

---@class CommandRunner
---@field base string[] program and leading arguments every run starts with
---@field config Config
local CommandRunner = {}
CommandRunner.__index = CommandRunner

---@param base string[]
---@param config Config
---@return CommandRunner
function CommandRunner.new(base, config)
	return setmetatable({ base = base, config = config }, CommandRunner)
end

---@param args string[]
---@param timeout integer milliseconds before the command is killed
---@param opts? { stdin?: string, sep?: string }
---@return string[] lines
---@return string? err
function CommandRunner:execute(args, timeout, opts)
	opts = opts or {}

	local cmd = vim.list_extend(vim.list_extend({}, self.base), args)
	local completed = vim.system(cmd, { text = true, stdin = opts.stdin }):wait(timeout)
	if completed.code ~= 0 then
		local err = ("%s exited with code %d"):format(cmd[1], completed.code)
		local stderr = vim.trim(completed.stderr or "")
		return util.fail(stderr ~= "" and ("%s: %s"):format(err, stderr) or err)
	end

	local lines = vim.split(completed.stdout or "", opts.sep or "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines, nil
end

---@param args string[]
---@param opts? { stdin?: string, sep?: string }
---@return string[] lines stdout split on `sep` ("\n" by default), without the trailing empty entry
---@return string? err exit code followed by stderr
function CommandRunner:run(args, opts)
	return self:execute(args, self.config.command_timeout, opts)
end

---@param args string[]
---@param timeout integer
---@param opts? { stdin?: string, sep?: string }
---@return string[] lines stdout split on `sep` ("\n" by default), without the trailing empty entry
---@return string? err exit code followed by stderr
function CommandRunner:run_with_timeout(args, timeout, opts)
	return self:execute(args, timeout, opts)
end

return CommandRunner
