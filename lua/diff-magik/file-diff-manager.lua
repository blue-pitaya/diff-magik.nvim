local util = require("diff-magik.util")
local BufferOrigin = require("diff-magik.buffer-origin")
local FileDiff = require("diff-magik.file-diff")

local COPIED_HL = {
	DiffMagikFileAdded = "DiffAdd",
	DiffMagikFileDeleted = "DiffDelete",
}

local FOLD_OPTS = {
	foldmethod = "manual",
	foldenable = true,
	foldlevel = 0,
}

local FOLD_OPT_NAMES = vim.tbl_keys(FOLD_OPTS)

---@class FileDiffManager
---@field config Config
---@field active table<integer, FileDiff> diffs by view buffer
---@field win_opts table<integer, table<string, any>> window options saved before the fold options replaced them, by window
local FileDiffManager = {}
FileDiffManager.__index = FileDiffManager

local function define_hl()
	for name, source in pairs(COPIED_HL) do
		local hl = vim.api.nvim_get_hl(0, { name = source, link = false }) --[[@as vim.api.keyset.highlight]]
		vim.api.nvim_set_hl(0, name, hl)
	end
end

---@param config Config
---@return FileDiffManager
function FileDiffManager.new(config)
	local self = setmetatable({ config = config, active = {}, win_opts = {} }, FileDiffManager)

	local augroup = vim.api.nvim_create_augroup("diff-magik.file-diff", { clear = true })

	define_hl()

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = define_hl,
		desc = "DiffMagik: re-copy the diff colors the in-file diff draws with",
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufReadPost" }, {
		group = augroup,
		callback = function(args)
			for _, diff in ipairs(self:diffs_of(args.buf)) do
				self:render(diff)
			end
		end,
		desc = "DiffMagik: keep the in-file diff in sync with the file",
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function(args)
			self:detach(args.buf)
		end,
		desc = "DiffMagik: drop the in-file diff of a closed buffer",
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(args)
			self.win_opts[tonumber(args.match)] = nil
		end,
		desc = "DiffMagik: forget the fold options of a closed window",
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		callback = function(args)
			local bufnr = args.buf
			vim.schedule(function()
				local diff = self.active[bufnr]
				if diff then
					self:refold_windows(diff)
				end
			end)
		end,
		desc = "DiffMagik: keep the hunk folds an attaching LSP would take over",
	})

	return self
end

---@param source integer
---@return FileDiff[]
function FileDiffManager:diffs_of(source)
	local diffs = {}
	for _, diff in pairs(self.active) do
		if diff.source == source then
			table.insert(diffs, diff)
		end
	end
	return diffs
end

---Gives every window showing the diff's view the fold options and the diff's folds.
---@param diff FileDiff
function FileDiffManager:fold_windows(diff)
	for _, winid in ipairs(vim.fn.win_findbuf(diff.view)) do
		if not self.win_opts[winid] then
			self.win_opts[winid] = util.save_wo(winid, FOLD_OPT_NAMES)
			util.set_wo(winid, FOLD_OPTS)
		end
		diff:apply_folds(winid)
	end
end

---Puts the diff's folds back in windows where something (e.g. an LSP) changed the fold method.
---@param diff FileDiff
function FileDiffManager:refold_windows(diff)
	for _, winid in ipairs(vim.fn.win_findbuf(diff.view)) do
		if self.win_opts[winid] and vim.wo[winid].foldmethod ~= FOLD_OPTS.foldmethod then
			vim.wo[winid].foldmethod = FOLD_OPTS.foldmethod
			diff:apply_folds(winid)
		end
	end
end

---@param winid integer
function FileDiffManager:restore_window(winid)
	local saved = self.win_opts[winid]
	if saved and vim.api.nvim_win_is_valid(winid) then
		util.set_wo(winid, saved)
	end
	self.win_opts[winid] = nil
end

---@param diff FileDiff
function FileDiffManager:render(diff)
	if diff:render() then
		self:fold_windows(diff)
	end
end

---@param bufnr integer
---@return integer? source the buffer `bufnr` shows a diff of, when it is a view
function FileDiffManager:source_of(bufnr)
	local diff = self.active[bufnr]
	return diff and diff.source
end

---@param bufnr integer
function FileDiffManager:detach(bufnr)
	local diff = self.active[bufnr]
	self.active[bufnr] = nil

	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if diff then
		diff:clear_highlights()
	end
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		self:restore_window(winid)
	end
end

function FileDiffManager:clear()
	for bufnr in pairs(self.active) do
		self:detach(bufnr)
	end
	for winid in pairs(self.win_opts) do
		self:restore_window(winid)
	end
end

---@param repo Git
---@param rel string
---@param bufnr integer
---@return integer view
---@return string? err
function FileDiffManager:attach(repo, rel, bufnr)
	local base, err = repo:base_lines(rel)
	if err ~= nil then
		return util.fail(err)
	end

	local existing = self:diffs_of(bufnr)[1]
	local view = existing and existing.view
	if not view then
		view = util.scratch_buf(("diffmagik://%s@%s:inline"):format(rel, base.label))
		vim.bo[view].filetype = vim.bo[bufnr].filetype
		BufferOrigin.new(repo.root, rel):tag(view)
	end

	local diff = FileDiff.new(view, bufnr, base.lines, self.config)
	self.active[view] = diff

	vim.api.nvim_win_set_buf(0, view)

	self:render(diff)

	return view, nil
end

return FileDiffManager
