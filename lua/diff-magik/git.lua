---@class Git
---@field root string absolute path to the git repo's top level
local Git = {}
Git.__index = Git

---@param args string[]
local function run(args)
	local cmd = { "git" }
	vim.list_extend(cmd, args)
	local result = vim.system(cmd, { text = true }):wait()
	if result.code ~= 0 then
		return nil
	end
	local lines = vim.split(result.stdout, "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

---@param dir string
function Git.new(dir)
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

---@param rel string path to the file, relative to `self.root`
function Git:exists_in_head(rel)
	return run({ "-C", self.root, "cat-file", "-e", ("HEAD:%s"):format(rel) }) ~= nil
end

---@param rel string
function Git:diff_name_only(rel)
	return run({ "-C", self.root, "diff", "--name-only", "HEAD", "--", rel })
end

---@param rel string
function Git:stage(rel)
	return run({ "-C", self.root, "add", "--", rel }) ~= nil
end

---@param rel string
function Git:unstage(rel)
	return run({ "-C", self.root, "restore", "--staged", "--", rel }) ~= nil
end

---@param rel string
function Git:is_staged(rel)
	local out = run({ "-C", self.root, "diff", "--cached", "--name-only", "HEAD", "--", rel })
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
function Git:head_lines(rel)
	return run({ "-C", self.root, "show", ("HEAD:%s"):format(rel) })
end

---@class GitEntry
---@field status string status against HEAD
---@field path string
---@field staged boolean the index differs from HEAD
---@field unstaged boolean the working tree differs from the index

---@param lines string[]|nil
---@return table<string, boolean>
local function path_set(lines)
	local set = {}
	for _, path in ipairs(lines or {}) do
		set[path] = true
	end
	return set
end

---@param line string
---@param staged table<string, boolean>
---@param unstaged table<string, boolean>
---@return GitEntry
local function parse_name_status(line, staged, unstaged)
	local status, path = line:match("^(%S+)\t(.*)$")
	path = path or line

	return {
		status = status and status:sub(1, 1) or "M",
		path = path,
		staged = staged[path] or false,
		unstaged = unstaged[path] or false,
	}
end

---@return GitEntry[]|nil
function Git:get_changed_files()
	local tracked = run({
		"-C",
		self.root,
		"diff",
		"--ignore-submodules",
		"--no-renames",
		"--name-status",
		"HEAD",
	})
	if not tracked then
		return nil
	end

	local untracked = run({ "-C", self.root, "ls-files", "--others", "--exclude-standard" }) or {}

	local staged = path_set(run({
		"-C",
		self.root,
		"diff",
		"--ignore-submodules",
		"--no-renames",
		"--cached",
		"--name-only",
		"HEAD",
	}))
	local unstaged = path_set(run({
		"-C",
		self.root,
		"diff",
		"--ignore-submodules",
		"--no-renames",
		"--name-only",
	}))

	local entries = {}
	local seen = {}

	local function add(entry)
		if not seen[entry.path] then
			seen[entry.path] = true
			table.insert(entries, entry)
		end
	end

	for _, line in ipairs(tracked) do
		add(parse_name_status(line, staged, unstaged))
	end
	for _, path in ipairs(untracked) do
		add({ status = "A", path = path, staged = false, unstaged = true })
	end
	return entries
end

return Git
