local config = require("diff-magik.config")

local ns = vim.api.nvim_create_namespace("diff-magik.filediff")
local group_id = 0

local COPIED_HL = {
	DiffMagikFileAdded = "DiffAdd",
	DiffMagikFileDeleted = "DiffDelete",
}

--- 'winhighlight' remaps `DiffDelete` to the dim filler colors in every pane this plugin opens, and a
--- virtual line drawn in such a window picks the remap up. Copying the colors out into groups of our
--- own — the same trick diffview.nvim uses for `DiffviewDiffAddAsDelete` — keeps deleted lines red
--- wherever they end up being drawn.
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

--- Lines worth showing, keyed by buffer then line number, read back by `foldexpr` — which Vim calls
--- for every line of the buffer and so cannot afford to diff anything itself.
---@type table<integer, table<integer, boolean>|nil>
local unfolded = {}

---@class FileDiffState
---@field base string the base revision's text, as `vim.diff` wants it
---@field base_lines string[]
---@field label string the revision the base came from

---@class FileDiff
---@field augroup integer
---@field active table<integer, FileDiffState>
---@field win_opts table<integer, table<string, any>> `FOLD_OPTS` as they were before we folded a window
local FileDiff = {}
FileDiff.__index = FileDiff

--- Folds everything that is not a hunk or one of its context lines.
---@param lnum integer
---@return string
function FileDiff.foldexpr(lnum)
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

--- Virtual lines are drawn as-is, so a tab would land on the wrong column.
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
		-- A deleted-only hunk hangs its virtual lines off a real line, and a closed fold hides those.
		local first = math.max(start_b, 1)
		local last = count_b > 0 and start_b + count_b - 1 or first

		for lnum = math.max(first - context, 1), math.min(last + context, total) do
			keep[lnum] = true
		end
	end

	unfolded[bufnr] = keep
end

---@param bufnr integer
---@return integer width the widest text area the buffer is displayed in
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

function FileDiff.new()
	group_id = group_id + 1

	local self = setmetatable({
		augroup = vim.api.nvim_create_augroup(("diff-magik.filediff.%d"):format(group_id), { clear = true }),
		active = {},
		win_opts = {},
	}, FileDiff)

	define_hl()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = self.augroup,
		callback = define_hl,
		desc = "DiffMagik: re-copy the diff colors the in-file diff draws with",
	})

	-- `TextChangedI` is left out on purpose: rediffing the whole file on every keystroke is not worth
	-- what it buys, and `InsertLeave` catches up as soon as the edit is over.
	vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufReadPost" }, {
		group = self.augroup,
		callback = function(args)
			self:render(args.buf)
		end,
		desc = "DiffMagik: keep the in-file diff in sync with the buffer",
	})

	-- Deleted lines are padded to the text area, so a resize leaves them the wrong length.
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = self.augroup,
		callback = function()
			for bufnr in pairs(self.active) do
				self:render(bufnr)
			end
		end,
		desc = "DiffMagik: refit the in-file diff to the window",
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = self.augroup,
		callback = function(args)
			self:detach(args.buf)
		end,
		desc = "DiffMagik: drop the in-file diff of a closed buffer",
	})

	return self
end

---@param bufnr integer
function FileDiff:render(bufnr)
	local state = self.active[bufnr]
	if not state or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local current = as_text(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
	---@type integer[][]|nil
	local hunks = vim.diff(state.base, current, { result_type = "indices" })
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
				local text = expand_tabs(state.base_lines[start_a + i] or "", tabstop)
				text = text .. (" "):rep(math.max(width - vim.fn.strdisplaywidth(text), 0))
				table.insert(virt_lines, { { text, hl.file_deleted } })
			end

			-- A hunk with no lines on the working-copy side anchors *after* line `start_b`, which is
			-- line 0 when the deletion sits at the very top of the file.
			local above = count_b > 0 or start_b == 0
			vim.api.nvim_buf_set_extmark(bufnr, ns, math.max(start_b - 1, 0), 0, {
				virt_lines = virt_lines,
				virt_lines_above = above,
			})
		end
	end

	mark_unfolded(bufnr, hunks)
	self:fold_windows(bufnr, false)
end

---@param bufnr integer
---@param force boolean recompute the folds of a window that is already set up
function FileDiff:fold_windows(bufnr, force)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		-- Setting the options up is a once-per-window job: doing it on every redraw would slam shut
		-- every fold the reader had opened since.
		if not self.win_opts[winid] then
			local saved = {}
			for name in pairs(FOLD_OPTS) do
				saved[name] = vim.wo[winid][name]
			end
			self.win_opts[winid] = saved

			for name, value in pairs(FOLD_OPTS) do
				vim.wo[winid][name] = value
			end
		elseif force then
			-- `foldexpr` reads a table Vim knows nothing about, so a new file in an already folded
			-- window has to be told that its folds are stale.
			vim.api.nvim_win_call(winid, function()
				vim.cmd("normal! zX")
			end)
		end
	end
end

---@param bufnr integer
function FileDiff:unfold_windows(bufnr)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		local saved = self.win_opts[winid]
		if saved then
			for name, value in pairs(saved) do
				vim.wo[winid][name] = value
			end
			self.win_opts[winid] = nil
		end
	end
end

---@param bufnr integer
function FileDiff:detach(bufnr)
	self.active[bufnr] = nil
	unfolded[bufnr] = nil

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	self:unfold_windows(bufnr)
end

function FileDiff:clear()
	for bufnr in pairs(self.active) do
		self:detach(bufnr)
	end
	self.win_opts = {}
end

---@param repo Git
---@param rel string path to the file, relative to `repo.root`
---@param bufnr integer
---@return string|nil label the revision the buffer is now diffed against
function FileDiff:attach(repo, rel, bufnr)
	local base_lines, label, err = repo:base_lines(rel)
	if not base_lines then
		vim.notify("DiffMagik: " .. err, vim.log.levels.ERROR)
		return nil
	end

	self.active[bufnr] = {
		base = as_text(base_lines),
		base_lines = base_lines,
		label = label,
	}

	vim.b[bufnr].diffmagik_root = repo.root
	vim.b[bufnr].diffmagik_path = rel

	self:render(bufnr)
	self:fold_windows(bufnr, true)

	return label
end

return FileDiff
