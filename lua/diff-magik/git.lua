---@class Git
---@field root string absolute path to the git repo's top level
---@field has_head boolean|nil
---@field empty_tree string|nil
local Git = {}
Git.__index = Git

local EMPTY_TREE_SHA1 = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

---@param args string[]
---@param opts { stdin?: string, sep?: string }|nil
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

--- `git -C` fails outright on a missing directory, which a deleted file's parent may well be.
---@param dir string
---@return string|nil dir the closest ancestor that still exists on disk
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

---@param dir string
function Git.new(dir)
	dir = existing_dir(dir)
	if not dir then
		return nil
	end

	local out = run({ "-C", dir, "rev-parse", "--show-toplevel" })
	local root = out and out[1] or nil
	if not root then
		return nil
	end
	return setmetatable({ root = root }, Git)
end

---@param root string absolute path to the repo's top level
function Git.from_root(root)
	return setmetatable({ root = root }, Git)
end

---@return string rev `HEAD`, or the empty tree while the repo has no commits
function Git:base()
	if not self.has_head then
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

---@param rel string path to the file, relative to `self.root`
function Git:exists_in_head(rel)
	return run({ "-C", self.root, "cat-file", "-e", ("%s:%s"):format(self:base(), rel) }) ~= nil
end

---@param rel string
function Git:diff_name_only(rel)
	return run({ "-C", self.root, "diff", "--name-only", self:base(), "--", rel })
end

---@param rel string
function Git:stage(rel)
	return run({ "-C", self.root, "add", "--", rel }) ~= nil
end

---@param rel string
function Git:unstage(rel)
	if self:base() ~= "HEAD" then
		return run({ "-C", self.root, "rm", "--cached", "--quiet", "--force", "--", rel }) ~= nil
	end
	return run({ "-C", self.root, "restore", "--staged", "--", rel }) ~= nil
end

---@param rel string
function Git:is_staged(rel)
	local out = run({ "-C", self.root, "diff", "--cached", "--name-only", self:base(), "--", rel })
	return out ~= nil and #out > 0
end

---@param rel string
function Git:is_unstaged(rel)
	local out = run({ "-C", self.root, "diff", "--name-only", "--", rel })
	return out ~= nil and #out > 0
end

---@param rel string
---@return boolean ok
function Git:toggle_stage(rel)
	if self:is_staged(rel) and not self:is_unstaged(rel) then
		return self:unstage(rel)
	end
	return self:stage(rel)
end

---@param rel string
---@return boolean ok
function Git:reset(rel)
	if self:exists_in_head(rel) then
		return run({ "-C", self.root, "checkout", self:base(), "--", rel }) ~= nil
	end

	if self:is_staged(rel) and not self:unstage(rel) then
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

---@class GitEntry
---@field status string status against HEAD
---@field path string
---@field staged boolean the index differs from HEAD
---@field unstaged boolean the working tree differs from the index

---@param x string index status letter
---@param y string working-tree status letter
local function entry_status(x, y)
	if x == "?" then
		return "A"
	end
	if x ~= " " then
		return x
	end
	return y
end

---@param pathspec string[]|nil limits the scan to these paths
---@return GitEntry[]|nil
function Git:get_changed_files(pathspec)
	-- `git diff HEAD` misses paths the index changed but the working tree did not, such as a staged
	-- new file deleted from disk again; `git status` reports both sides of every path in one pass.
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
