local BufferOrigin = require("diff-magik.buffer-origin")

---@class Git
---@field root string
---@field has_head? boolean
---@field empty_tree? string
local Git = {}
Git.__index = Git

local EMPTY_TREE_SHA1 = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

---@param args string[]
---@param opts? { stdin?: string, sep?: string }
local function run(args, opts)
	opts = opts or {}

	local cmd = { "git" }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd, { text = true, stdin = opts.stdin }):wait(opts.stdin and 5000 or nil)
	if result.code ~= 0 then
		return nil
	end
	local lines = vim.split(result.stdout, opts.sep or "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

---@param dir string
---@return string?
local function existing_dir(dir)
	while not vim.uv.fs_stat(dir) do
		local parent = vim.fs.dirname(dir)
		if not parent or parent == dir then
			return nil
		end
		dir = parent
	end
	return dir
end

---@param path string
---@return Git?
function Git.new(path)
	local dir = existing_dir(path)
	local out = dir and run({ "-C", dir, "rev-parse", "--show-toplevel" })
	local root = out and out[1]
	return root and Git.from_root(root) or nil
end

---@param root string
function Git.from_root(root)
	return setmetatable({ root = root }, Git)
end

---@param bufnr integer
---@return Git?
---@return string?
---@return string?
function Git.for_buffer(bufnr)
	local origin = BufferOrigin.of(bufnr)
	if origin then
		return Git.from_root(origin.root), origin.rel
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return nil, nil, "current buffer has no file"
	end

	local repo = Git.new(vim.fs.dirname(path))
	if not repo then
		return nil, nil, "not inside a git repository"
	end

	rel = vim.fs.relpath(repo.root, path)
	if not rel then
		return nil, nil, "failed to resolve path relative to repo root"
	end

	return repo, rel
end

---@return string
function Git:base()
	if self.has_head == nil then
		self.has_head = run({ "-C", self.root, "rev-parse", "--verify", "--quiet", "HEAD" }) ~= nil
	end
	if self.has_head then
		return "HEAD"
	end

	if not self.empty_tree then
		local out = run({ "-C", self.root, "hash-object", "-t", "tree", "--stdin" }, { stdin = "" })
		self.empty_tree = out and out[1] or EMPTY_TREE_SHA1
	end
	return self.empty_tree
end

---@param rel string
---@return GitEntry?
function Git:entry(rel)
	local entries = self:get_changed_files({ rel })
	return entries and entries[1]
end

---@param rel string
---@return boolean
function Git:matches_base(rel)
	return run({ "-C", self.root, "diff", "--quiet", self:base(), "--", rel }) ~= nil
end

---@param rel string
---@return boolean
function Git:stage(rel)
	return run({ "-C", self.root, "add", "--", rel }) ~= nil
end

---@param rel string
---@return boolean
function Git:unstage(rel)
	if self:base() ~= "HEAD" then
		return run({ "-C", self.root, "rm", "--cached", "--quiet", "--force", "--", rel }) ~= nil
	end
	return run({ "-C", self.root, "restore", "--staged", "--", rel }) ~= nil
end

---@param rel string
---@return boolean
function Git:toggle_stage(rel)
	local entry = self:entry(rel)
	if entry and entry.staged and not entry.unstaged then
		return self:unstage(rel)
	end
	return self:stage(rel)
end

---@param rel string
---@return boolean
function Git:reset(rel)
	local entry = self:entry(rel)
	if not entry then
		return false
	end

	if entry.status ~= "A" then
		return run({ "-C", self.root, "checkout", self:base(), "--", rel }) ~= nil
	end

	if entry.staged and not self:unstage(rel) then
		return false
	end

	local path = vim.fs.joinpath(self.root, rel)
	if not vim.uv.fs_stat(path) then
		return true
	end
	return vim.uv.fs_unlink(path) ~= nil
end

---@param rel string
function Git:head_lines(rel)
	return run({ "-C", self.root, "show", ("%s:%s"):format(self:base(), rel) })
end

---@param rel string
function Git:index_lines(rel)
	return run({ "-C", self.root, "show", (":%s"):format(rel) })
end

---@param rel string
---@return string[]?
---@return string?
---@return string?
function Git:base_lines(rel)
	local entries = self:get_changed_files({ rel })
	if not entries then
		return nil, nil, "failed to run git status"
	end

	local entry = entries[1]
	if not entry then
		return nil, nil, ("no changes in '%s'"):format(rel)
	end

	if entry.staged and entry.unstaged and self:matches_base(rel) then
		local lines = self:index_lines(rel)
		if not lines then
			return nil, nil, "failed to read indexed version of file"
		end
		return lines, "INDEX"
	end

	if entry.status == "A" then
		return {}, "HEAD"
	end

	local lines = self:head_lines(rel)
	if not lines then
		return nil, nil, "failed to read HEAD version of file"
	end
	return lines, "HEAD"
end

---@class GitEntry
---@field status string
---@field path string
---@field staged boolean
---@field unstaged boolean

---@param x string
---@param y string
local function entry_status(x, y)
	if x == "?" then
		return "A"
	end
	if x ~= " " then
		return x
	end
	return y
end

---@param pathspec? string[]
---@return GitEntry[]?
function Git:get_changed_files(pathspec)
	local args = {
		"-C",
		self.root,
		"status",
		"--porcelain",
		"-z",
		"--untracked-files=all",
		"--no-renames",
		"--ignore-submodules",
	}
	if pathspec then
		table.insert(args, "--")
		vim.list_extend(args, pathspec)
	end

	local records = run(args, { sep = "\0" })
	if not records then
		return nil
	end

	local entries = {}
	for _, record in ipairs(records) do
		local x, y, path = record:sub(1, 1), record:sub(2, 2), record:sub(4)
		if path ~= "" then
			table.insert(entries, {
				status = entry_status(x, y),
				path = path,
				staged = x ~= " " and x ~= "?",
				unstaged = y ~= " ",
			})
		end
	end
	return entries
end

return Git
