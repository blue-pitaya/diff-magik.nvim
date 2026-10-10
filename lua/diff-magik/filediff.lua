local config = require("diff-magik.config")
local util = require("diff-magik.util")

local ns = vim.api.nvim_create_namespace("diff-magik.filediff")

local COPIED_HL = {
	DiffMagikFileAdded = "DiffAdd",
	DiffMagikFileDeleted = "DiffDelete",
}

local function define_hl()
	for name, source in pairs(COPIED_HL) do
		vim.api.nvim_set_hl(0, name, vim.api.nvim_get_hl(0, { name = source, link = false }))
	end
end

local FOLD_OPTS = {
	foldmethod = "expr",
	foldexpr = "v:lua.require'diff-magik.filediff'.foldexpr(v:lnum)",
	foldenable = true,
	foldlevel = 0,
}

---@type table<integer, table<integer, boolean>>
local unfolded = {}

---@class FileDiffState
---@field base string
---@field base_lines string[]
---@field label string

---@class FileDiffModuleState
---@field active table<integer, FileDiffState>
---@field win_opts table<integer, table<string, any>>
local state = {
	active = {},
	win_opts = {},
}

local M = {}

---@param lnum integer
---@return string
function M.foldexpr(lnum)
	local keep = unfolded[vim.api.nvim_get_current_buf()]
	if not keep or keep[lnum] then
		return "0"
	end
	return "1"
end

---@param lines string[]
local function as_text(lines)
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

---@param line string
---@param tabstop integer
local function expand_tabs(line, tabstop)
	local col = line:find("\t", 1, true)
	while col do
		local pad = tabstop - vim.fn.strdisplaywidth(line:sub(1, col - 1)) % tabstop
		line = line:sub(1, col - 1) .. (" "):rep(pad) .. line:sub(col + 1)
		col = line:find("\t", 1, true)
	end
	return line
end

---@param bufnr integer
---@param hunks integer[][]
local function mark_unfolded(bufnr, hunks)
	if #hunks == 0 then
		unfolded[bufnr] = nil
		return
	end

	local total = vim.api.nvim_buf_line_count(bufnr)
	local context = config.options.fold_context
	local keep = {}

	for _, hunk in ipairs(hunks) do
		local start_b, count_b = hunk[3], hunk[4]
		local first = math.max(start_b, 1)
		local last = count_b > 0 and start_b + count_b - 1 or first

		for lnum = math.max(first - context, 1), math.min(last + context, total) do
			keep[lnum] = true
		end
	end

	unfolded[bufnr] = keep
end

---@param bufnr integer
---@return integer
local function text_width(bufnr)
	local width = 0
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		local info = vim.fn.getwininfo(winid)[1]
		if info then
			width = math.max(width, info.width - info.textoff)
		end
	end
	return width
end

---@param bufnr integer
---@param force boolean
local function fold_windows(bufnr, force)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		if not state.win_opts[winid] then
			local saved = {}
			for name in pairs(FOLD_OPTS) do
				saved[name] = vim.wo[winid][name]
			end
			state.win_opts[winid] = saved

			for name, value in pairs(FOLD_OPTS) do
				vim.wo[winid][name] = value
			end
		elseif force then
			vim.api.nvim_win_call(winid, function()
				vim.cmd("normal! zX")
			end)
		end
	end
end

---@param bufnr integer
local function refold_windows(bufnr)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		if state.win_opts[winid] and vim.api.nvim_win_is_valid(winid) then
			if vim.wo[winid].foldmethod ~= FOLD_OPTS.foldmethod or vim.wo[winid].foldexpr ~= FOLD_OPTS.foldexpr then
				vim.wo[winid][0].foldmethod = FOLD_OPTS.foldmethod
				vim.wo[winid][0].foldexpr = FOLD_OPTS.foldexpr
			end
		end
	end
end

---@param bufnr integer
local function unfold_windows(bufnr)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		local saved = state.win_opts[winid]
		if saved then
			for name, value in pairs(saved) do
				vim.wo[winid][name] = value
			end
			state.win_opts[winid] = nil
		end
	end
end

---@param bufnr integer
local function render(bufnr)
	local diff = state.active[bufnr]
	if not diff or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local current = as_text(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
	---@type integer[][]?
	local hunks = vim.diff(diff.base, current, { result_type = "indices" })
	if not hunks then
		return
	end

	local hl = config.options.highlights
	local width = text_width(bufnr)
	local tabstop = vim.bo[bufnr].tabstop

	for _, hunk in ipairs(hunks) do
		local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]

		for i = 0, count_b - 1 do
			vim.api.nvim_buf_set_extmark(bufnr, ns, start_b - 1 + i, 0, {
				line_hl_group = hl.file_added,
			})
		end

		if count_a > 0 then
			local virt_lines = {}
			for i = 0, count_a - 1 do
				local text = expand_tabs(diff.base_lines[start_a + i] or "", tabstop)
				text = text .. (" "):rep(math.max(width - vim.fn.strdisplaywidth(text), 0))
				table.insert(virt_lines, { { text, hl.file_deleted } })
			end

			local above = count_b > 0 or start_b == 0
			vim.api.nvim_buf_set_extmark(bufnr, ns, math.max(start_b - 1, 0), 0, {
				virt_lines = virt_lines,
				virt_lines_above = above,
			})
		end
	end

	mark_unfolded(bufnr, hunks)
	fold_windows(bufnr, false)
end

---@param bufnr integer
function M.detach(bufnr)
	state.active[bufnr] = nil
	unfolded[bufnr] = nil

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	unfold_windows(bufnr)
end

function M.clear()
	for bufnr in pairs(state.active) do
		M.detach(bufnr)
	end
	state.win_opts = {}
end

function M.setup()
	local augroup = vim.api.nvim_create_augroup("diff-magik.filediff", { clear = true })

	define_hl()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = define_hl,
		desc = "DiffMagik: re-copy the diff colors the in-file diff draws with",
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufReadPost" }, {
		group = augroup,
		callback = function(args)
			render(args.buf)
		end,
		desc = "DiffMagik: keep the in-file diff in sync with the buffer",
	})

	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = augroup,
		callback = function()
			for bufnr in pairs(state.active) do
				render(bufnr)
			end
		end,
		desc = "DiffMagik: refit the in-file diff to the window",
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function(args)
			M.detach(args.buf)
		end,
		desc = "DiffMagik: drop the in-file diff of a closed buffer",
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function(args)
			local bufnr = args.buf
			vim.schedule(function()
				if state.active[bufnr] then
					refold_windows(bufnr)
				end
			end)
		end,
		desc = "DiffMagik: keep the hunk folds an attaching LSP would take over",
	})
end

---@param repo Git
---@param rel string
---@param bufnr integer
---@return string?
function M.attach(repo, rel, bufnr)
	local base_lines, label, err = repo:base_lines(rel)
	if not base_lines then
		vim.notify("DiffMagik: " .. err, vim.log.levels.ERROR)
		return nil
	end

	state.active[bufnr] = {
		base = as_text(base_lines),
		base_lines = base_lines,
		label = label,
	}

	util.tag_buffer(bufnr, repo.root, rel)

	render(bufnr)
	fold_windows(bufnr, true)

	return label
end

return M
