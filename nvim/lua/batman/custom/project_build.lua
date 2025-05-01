local M = {}

local config = {
	python = {
		run_cmd = "python3 %",
		test_cmd = "pytest",
		lint_cmd = "flake8 %",
		format_cmd = "black %",
		venv_activate = "./venv/bin/activate",
	},
	c = {
		build_cmd = "gcc -Wall -Wextra -o %:r %",
		run_cmd = "./%:r",
		debug_cmd = "gdb %:r",
		lint_cmd = "cppcheck %",
	},
	cpp = {
		build_cmd = "g++ -std=c++17 -Wall -Wextra -o %:r %",
		run_cmd = "./%:r",
		debug_cmd = "gdb %:r",
		lint_cmd = "cppcheck --language=c++ %",
	},

	go = {
		run_cmd = "go run %",
		build_cmd = "go build",
		test_cmd = "go test ./...",
		lint_cmd = "golint %",
		fmt_cmd = "gofmt -w %",
	},

	term_position = "botright",
	term_size = 12,
}

-- Project detection
local function detect_project_type()
	local cwd = vim.fn.getcwd()

	-- Check for Go project
	if vim.fn.filereadable(cwd .. "/go.mod") == 1 then
		return "go"
	end

	-- Check for Python project
	if
		vim.fn.filereadable(cwd .. "/requirements.txt") == 1
		or vim.fn.filereadable(cwd .. "/setup.py") == 1
		or vim.fn.filereadable(cwd .. "/pyproject.toml") == 1
	then
		return "python"
	end

	-- Check for C/C++ project with CMake
	if vim.fn.filereadable(cwd .. "/CMakeLists.txt") == 1 then
		-- Try to determine if it's more C or C++
		local cmake_content = vim.fn.readfile(cwd .. "/CMakeLists.txt")
		local cpp_score, c_score = 0, 0

		for _, line in ipairs(cmake_content) do
			if line:match("%.cpp") or line:match("C%+%+") then
				cpp_score = cpp_score + 1
			end
			if line:match("%.c[^p]") then -- match .c but not .cpp
				c_score = c_score + 1
			end
		end

		if cpp_score > c_score then
			return "cpp"
		else
			return "c"
		end
	end

	-- Check for Makefile (could be C or C++)
	if vim.fn.filereadable(cwd .. "/Makefile") == 1 then
		-- Count .c and .cpp files to determine project type
		local c_files = vim.fn.system("find " .. cwd .. " -name '*.c' | wc -l")
		local cpp_files = vim.fn.system("find " .. cwd .. " -name '*.cpp' | wc -l")

		if tonumber(cpp_files) > tonumber(c_files) then
			return "cpp"
		else
			return "c"
		end
	end

	-- Fallback to current file's filetype
	local filetype = vim.bo.filetype
	if filetype == "python" or filetype == "c" or filetype == "cpp" or filetype == "go" then
		return filetype
	end

	return nil
end

-- Run a command in a terminal
local function run_in_terminal(cmd)
	-- Close existing terminal if open
	pcall(function()
		vim.cmd("bdelete! term")
	end)

	-- Open a new terminal with the command
	vim.cmd(config.term_position .. " " .. config.term_size .. "split")
	vim.cmd("terminal " .. cmd)
	vim.cmd("setlocal nonumber")
	vim.cmd("setlocal norelativenumber")
	vim.cmd("setlocal signcolumn=no")
	vim.cmd("startinsert")
end

-- Function to run the current file
function M.run_current_file()
	local project_type = detect_project_type()

	if not project_type then
		vim.notify("Project type not detected", vim.log.levels.WARN)
		return
	end

	-- Save the current file
	vim.cmd("write")

	local cmd
	if project_type == "python" then
		-- Check for virtual environment
		local venv_path = vim.fn.getcwd() .. "/venv"
		local has_venv = vim.fn.isdirectory(venv_path) == 1

		if has_venv then
			cmd = "source " .. config.python.venv_activate .. " && " .. config.python.run_cmd
		else
			cmd = config.python.run_cmd
		end
	elseif project_type == "c" or project_type == "cpp" then
		-- Build then run
		cmd = config[project_type].build_cmd .. " && " .. config[project_type].run_cmd
	elseif project_type == "go" then
		cmd = config.go.run_cmd
	end

	-- Replace % with current file
	cmd = cmd:gsub("%%", vim.fn.expand("%"))
	cmd = cmd:gsub("%%:r", vim.fn.expand("%:r"))

	run_in_terminal(cmd)
end

-- Function to build the project
function M.build_project()
	local project_type = detect_project_type()

	if not project_type or project_type == "python" then
		vim.notify("No build step needed for this project type", vim.log.levels.INFO)
		return
	end

	-- Save all files
	vim.cmd("wall")

	local cmd
	if project_type == "c" or project_type == "cpp" then
		-- Check for CMake
		if vim.fn.filereadable("CMakeLists.txt") == 1 then
			cmd = "mkdir -p build && cd build && cmake .. && make"
		-- Check for Makefile
		elseif vim.fn.filereadable("Makefile") == 1 then
			cmd = "make"
		else
			cmd = config[project_type].build_cmd
			cmd = cmd:gsub("%%", vim.fn.expand("%"))
			cmd = cmd:gsub("%%:r", vim.fn.expand("%:r"))
		end
	elseif project_type == "go" then
		cmd = config.go.build_cmd
	end

	run_in_terminal(cmd)
end

-- Function to run tests
function M.run_tests()
	local project_type = detect_project_type()

	if not project_type then
		vim.notify("Project type not detected", vim.log.levels.WARN)
		return
	end

	-- Save all files
	vim.cmd("wall")

	local cmd
	if project_type == "python" then
		-- Check for virtual environment
		local venv_path = vim.fn.getcwd() .. "/venv"
		local has_venv = vim.fn.isdirectory(venv_path) == 1

		if has_venv then
			cmd = "source " .. config.python.venv_activate .. " && " .. config.python.test_cmd
		else
			cmd = config.python.test_cmd
		end
	elseif project_type == "go" then
		cmd = config.go.test_cmd
	else
		vim.notify("Test command not configured for this project type", vim.log.levels.WARN)
		return
	end

	run_in_terminal(cmd)
end

-- Function to format code
function M.format_code()
	local project_type = detect_project_type()

	if not project_type then
		vim.notify("Project type not detected", vim.log.levels.WARN)
		return
	end

	local cmd
	if project_type == "python" then
		cmd = config.python.format_cmd
	elseif project_type == "go" then
		cmd = config.go.fmt_cmd
	else
		vim.notify("Format command not configured for this project type", vim.log.levels.WARN)
		return
	end

	cmd = cmd:gsub("%%", vim.fn.expand("%"))

	-- Run formatter and check exit code
	local output = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		vim.notify("Formatting failed: " .. output, vim.log.levels.ERROR)
	else
		vim.notify("Code formatted successfully", vim.log.levels.INFO)
		-- Reload the file if it was changed externally
		vim.cmd("edit")
	end
end

-- Function to lint code
function M.lint_code()
	local project_type = detect_project_type()

	if not project_type then
		vim.notify("Project type not detected", vim.log.levels.WARN)
		return
	end

	local cmd
	if project_type == "python" then
		cmd = config.python.lint_cmd
	elseif project_type == "c" or project_type == "cpp" then
		cmd = config[project_type].lint_cmd
	elseif project_type == "go" then
		cmd = config.go.lint_cmd
	else
		vim.notify("Lint command not configured for this project type", vim.log.levels.WARN)
		return
	end

	cmd = cmd:gsub("%%", vim.fn.expand("%"))

	-- Run linter and capture output
	local output = vim.fn.system(cmd)

	-- Create a new scratch buffer for the output
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n"))

	-- Open the buffer in a new window
	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.cmd("setlocal buftype=nofile bufhidden=wipe noswapfile nowrap")
	vim.cmd("setlocal filetype=text")
	vim.cmd("resize 10")
end

-- Function to debug the current file
function M.debug_current_file()
	local project_type = detect_project_type()

	if not project_type or project_type == "python" then
		vim.notify("Debug command not configured for this project type", vim.log.levels.WARN)
		return
	end

	-- Save the current file
	vim.cmd("write")

	local cmd
	if project_type == "c" or project_type == "cpp" then
		-- Build first
		local build_cmd = config[project_type].build_cmd
		build_cmd = build_cmd:gsub("%%", vim.fn.expand("%"))
		build_cmd = build_cmd:gsub("%%:r", vim.fn.expand("%:r"))
		os.execute(build_cmd)

		-- Then debug
		cmd = config[project_type].debug_cmd
		cmd = cmd:gsub("%%", vim.fn.expand("%"))
		cmd = cmd:gsub("%%:r", vim.fn.expand("%:r"))
	end

	run_in_terminal(cmd)
end

-- Setup function for customization
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Create commands
function M.create_commands()
	vim.api.nvim_create_user_command("Run", function()
		M.run_current_file()
	end, {})

	vim.api.nvim_create_user_command("Build", function()
		M.build_project()
	end, {})

	vim.api.nvim_create_user_command("Test", function()
		M.run_tests()
	end, {})

	vim.api.nvim_create_user_command("Format", function()
		M.format_code()
	end, {})

	vim.api.nvim_create_user_command("Lint", function()
		M.lint_code()
	end, {})

	vim.api.nvim_create_user_command("Debug", function()
		M.debug_current_file()
	end, {})
end

-- Setup keymaps
function M.setup_keymaps()
	-- Normal mode keymaps
	vim.keymap.set("n", "<leader>r", M.run_current_file, { noremap = true, desc = "Run current file" })
	vim.keymap.set("n", "<leader>b", M.build_project, { noremap = true, desc = "Build project" })
	vim.keymap.set("n", "<leader>t", M.run_tests, { noremap = true, desc = "Run tests" })
	vim.keymap.set("n", "<leader>f", M.format_code, { noremap = true, desc = "Format code" })
	vim.keymap.set("n", "<leader>l", M.lint_code, { noremap = true, desc = "Lint code" })
	vim.keymap.set("n", "<leader>d", M.debug_current_file, { noremap = true, desc = "Debug current file" })
end

-- Auto-setup
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		M.create_commands()
		M.setup_keymaps()
	end,
})

return M
