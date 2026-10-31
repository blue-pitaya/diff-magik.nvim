local root = vim.uv.cwd()
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

vim.o.columns = 200
vim.o.lines = 50

local helpers = require("helpers")

local spec, case = arg[1], arg[2]

local loaded, load_err = xpcall(function()
	dofile(spec)
end, debug.traceback)
if not loaded then
	io.stdout:write(load_err, "\n")
	os.exit(1)
end

if not case then
	for _, c in ipairs(helpers.cases) do
		io.stdout:write(c.name, "\n")
	end
	os.exit(0)
end

for _, c in ipairs(helpers.cases) do
	if c.name == case then
		local ok, err = xpcall(c.fn, debug.traceback)
		if not ok then
			io.stdout:write(err, "\n")
			os.exit(1)
		end
		os.exit(0)
	end
end

io.stdout:write(("no test named '%s'\n"):format(case))
os.exit(1)
