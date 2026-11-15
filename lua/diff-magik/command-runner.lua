local util = require("diff-magik.util")

---Runs external commands to completion and returns their stdout as lines.
---@class CommandRunner
local CommandRunner = {}

local DEFAULT_TIMEOUT_MS = 5000

---Runs a command to completion; a command that outlives the timeout is killed and fails.
---@param cmd string[]
---@param opts? { stdin?: string, sep?: string, timeout?: integer }
---@return string[] lines stdout
---@return string? err
function CommandRunner.run(cmd, opts)
	opts = opts or {}

	local completed = vim.system(cmd, { text = true, stdin = opts.stdin }):wait(opts.timeout or DEFAULT_TIMEOUT_MS)
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

return CommandRunner
