local Browser = require("diff-magik.browser")
local util = require("diff-magik.util")

local M = {}

local MARKER = "diffmagik-editor:"
local EDITOR = ([[sh -c 'echo "%s$1"; read _' sh]]):format(MARKER)

---@param root string
---@param path string
---@param job vim.SystemObj
local function open_message(root, path, job)
	if path:sub(1, 1) ~= "/" then
		path = vim.fs.joinpath(root, path)
	end

	vim.cmd.tabedit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					if vim.bo[buf].modified then
						vim.api.nvim_buf_call(buf, function()
							vim.cmd("silent write")
						end)
					end
					vim.api.nvim_buf_delete(buf, { force = true })
				end
				job:write("\n")
			end)
		end,
	})
end

---@param repo Git
function M.open(repo)
	local output = {}
	local job

	job = vim.system({ "git", "-C", repo.root, "commit" }, {
		env = { GIT_EDITOR = EDITOR },
		stdin = true,
		text = true,
		stdout = function(_, data)
			if not data then
				return
			end
			if not vim.startswith(data, MARKER) then
				table.insert(output, data)
				return
			end
			local path = vim.split(data:sub(#MARKER + 1), "\n")[1]
			vim.schedule(function()
				open_message(repo.root, path, job)
			end)
		end,
	}, function(result)
		vim.schedule(function()
			local stdout = vim.trim(table.concat(output))
			if result.code == 0 then
				util.info(vim.split(stdout, "\n")[1])
				Browser.refresh()
				return
			end
			local stderr = vim.trim(result.stderr or "")
			util.error(stderr ~= "" and stderr or stdout ~= "" and stdout or "git commit failed")
		end)
	end)
end

return M
