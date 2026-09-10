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

---@param rel string path to the file, relative to `self.root`
function Git:exists_in_head(rel)
	return run({ "-C", self.root, "cat-file", "-e", ("HEAD:%s"):format(rel) }) ~= nil
end

---@param rel string
function Git:diff_name_only(rel)
	return run({ "-C", self.root, "diff", "--name-only", "HEAD", "--", rel })
end

---@param rel string
function Git:head_lines(rel)
	return run({ "-C", self.root, "show", ("HEAD:%s"):format(rel) })
end

---@param line string
---@return { status: string, path: string }
local function parse_name_status(line)
	local status, path = line:match("^(%S+)\t(.*)$")
	return { status = status and status:sub(1, 1) or "M", path = path or line }
end

---@return { status: string, path: string }[]|nil
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

	local entries = {}
	local seen = {}

	local function add(entry)
		if not seen[entry.path] then
			seen[entry.path] = true
			table.insert(entries, entry)
		end
	end

	for _, line in ipairs(tracked) do
		add(parse_name_status(line))
	end
	for _, path in ipairs(untracked) do
		add({ status = "A", path = path })
	end
	return entries
end

return Git
