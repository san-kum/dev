-- doc_generator.lua - Generate documentation for functions and classes

local M = {}

-- Configuration with default values
local config = {
	python = {
		doc_style = "google", -- Options: "google", "numpy", "sphinx"
		include_types = true,
		include_returns = true,
		include_raises = true,
	},
	c = {
		include_params = true,
		include_return = true,
		align_params = true,
	},
	cpp = {
		doc_style = "doxygen", -- Options: "doxygen", "javadoc"
		include_params = true,
		include_return = true,
		include_brief = true,
	},
	go = {
		include_params = true,
		include_returns = true,
		capitalize_first_letter = true,
	},
}

-- Parse Python function definition
local function parse_python_function(line, next_lines)
	local func_pattern = "^%s*def%s+([%w_]+)%s*%((.-)%)%s*%-%>?%s*(.-)%s*:"
	local name, params, return_type = line:match(func_pattern)

	if not name then
		return nil
	end

	local param_list = {}
	for param in params:gmatch("([^,]+)") do
		local param_name, param_type
		param = param:gsub("^%s*", ""):gsub("%s*$", "") -- Trim whitespace

		-- Check for type annotation
		if param:match(":") then
			param_name, param_type = param:match("([%w_]+)%s*:%s*(.+)")
		else
			param_name = param:match("([%w_]+)")
		end

		-- Handle default values
		if param_name and param_name:match("=") then
			param_name = param_name:match("([%w_]+)%s*=")
		end

		if param_name and param_name ~= "self" and param_name ~= "cls" then
			table.insert(param_list, { name = param_name, type = param_type or "" })
		end
	end

	-- Look for raises/exceptions in function body
	local exceptions = {}
	for i, next_line in ipairs(next_lines) do
		if next_line:match("raise%s+[%w_]+") then
			local exception = next_line:match("raise%s+([%w_]+)")
			if exception then
				table.insert(exceptions, exception)
			end
		end

		-- Only look at the first 10 lines or until indentation changes
		if i > 10 or (next_line:match("^%s*[^%s]") and not next_line:match("^%s+")) then
			break
		end
	end

	return {
		name = name,
		params = param_list,
		return_type = return_type ~= "" and return_type or nil,
		exceptions = exceptions,
	}
end

-- Parse Python class definition
local function parse_python_class(line)
	local class_pattern = "^%s*class%s+([%w_]+)%s*%(?(.-)%)?%s*:"
	local name, inherits = line:match(class_pattern)

	if not name then
		return nil
	end

	local inherit_list = {}
	if inherits and inherits ~= "" then
		for parent in inherits:gmatch("([^,]+)") do
			parent = parent:gsub("^%s*", ""):gsub("%s*$", "") -- Trim whitespace
			table.insert(inherit_list, parent)
		end
	end

	return {
		name = name,
		inherits = inherit_list,
	}
end

-- Parse C/C++ function definition
local function parse_c_function(line, next_lines)
	-- Handle function prototypes and definitions
	local return_type, name, params

	-- Try to match function with params and return type on one line
	return_type, name, params = line:match("^%s*([%w_%*&<>:%s]+)%s+([%w_]+)%s*%((.-)%)%s*{?%s*$")

	if not return_type or not name then
		-- Try multiline function definitions
		-- First line usually has return type and name
		return_type, name = line:match("^%s*([%w_%*&<>:%s]+)%s+([%w_]+)%s*%(?")

		if return_type and name then
			-- Find the closing parenthesis in next lines
			local param_lines = {}
			for i, next_line in ipairs(next_lines) do
				table.insert(param_lines, next_line)
				if next_line:match("%)%s*{%s*$") then
					-- Found the end of the function declaration
					break
				end
				if i > 10 then
					break
				end -- Don't go too far
			end

			-- Combine lines and extract parameters
			local combined = table.concat(param_lines, " ")
			params = combined:match("%((.-)%)%s*{")
		end
	end

	if not return_type or not name or not params then
		return nil
	end

	-- Clean up return type
	return_type = return_type:gsub("^%s*", ""):gsub("%s*$", "")

	-- Parse parameters
	local param_list = {}
	for param in params:gmatch("([^,]+)") do
		param = param:gsub("^%s*", ""):gsub("%s*$", "") -- Trim whitespace

		if param ~= "void" and param ~= "" then
			local param_type, param_name

			-- Handle function pointers and complex declarations
			if param:match("%(") then
				-- Function pointer or complex parameter
				param_name = param:match(".*%(%*([%w_]+)%)")
					or param:match(".*%*([%w_]+)")
					or param:match(".*([%w_]+)$")
				param_type = param:gsub(param_name, ""):gsub("%s*$", "")
			else
				-- Simple parameter
				param_type, param_name = param:match("(.+)%s+([%w_]+)$")

				-- Handle pointer/reference types
				if not param_name then
					param_name = param:match(".*%*([%w_]+)$")
					if param_name then
						param_type = param:gsub("%*" .. param_name .. "$", "*"):gsub("%s*$", "")
					end
				end
			end

			if param_name then
				table.insert(param_list, { name = param_name, type = param_type or "" })
			end
		end
	end

	return {
		name = name,
		return_type = return_type,
		params = param_list,
	}
end

-- Parse C++ class definition
local function parse_cpp_class(line, next_lines)
	-- Match class, struct, or template class
	local class_type, name, inherits

	-- Check for template class first
	local template_pattern = "^%s*template%s*<.->%s*class%s+([%w_]+)"
	name = line:match(template_pattern)

	if not name then
		-- Regular class or struct
		class_type, name = line:match("^%s*(class|struct)%s+([%w_]+)")
	end

	if not name then
		return nil
	end

	-- Check for inheritance in the same line or next lines
	inherits = line:match(":%s*(.+)%s*{")

	if not inherits then
		-- Look in next few lines
		for i, next_line in ipairs(next_lines) do
			if next_line:match(":%s*(.+)%s*{") then
				inherits = next_line:match(":%s*(.+)%s*{")
				break
			end
			if next_line:match("{") or i > 5 then
				break
			end
		end
	end

	local inherit_list = {}
	if inherits then
		for inheritance in inherits:gmatch("([^,]+)") do
			inheritance = inheritance:gsub("^%s*", ""):gsub("%s*$", "") -- Trim whitespace

			-- Extract access specifier and class name
			local access, parent = inheritance:match("(public|protected|private)%s+(.+)")

			if not access then
				parent = inheritance
				access = "private" -- Default access specifier in C++
			end

			table.insert(inherit_list, { access = access, name = parent })
		end
	end

	return {
		name = name,
		class_type = class_type or "class", -- Could be nil for template classes
		inherits = inherit_list,
	}
end

-- doc_generator.lua - Generate documentation for functions and classes (continued)

-- Parse Go function definition (continued)
local function parse_go_function(line)
	local func_pattern = "^%s*func%s+([%(]?[%w_%.%*]+[%)]?%s+)?([%w_]+)%s*%((.-)%)%s*([%w%s%*%[%]%.{}]+)?"
	local receiver, name, params, returns = line:match(func_pattern)

	if not name then
		return nil
	end

	-- Parse parameters
	local param_list = {}
	if params and params ~= "" then
		local param_groups = {}
		for param_group in params:gmatch("([^,]+)") do
			table.insert(param_groups, param_group:gsub("^%s*", ""):gsub("%s*$", ""))
		end

		-- Handle Go's grouped parameter syntax (param1, param2 Type)
		for _, group in ipairs(param_groups) do
			local names, param_type = group:match("(.+)%s+([^%s]+)$")

			if names and param_type then
				-- Multiple params with same type
				for param_name in names:gmatch("([^%s,]+)") do
					table.insert(param_list, { name = param_name, type = param_type })
				end
			else
				-- Single param (maybe unnamed)
				local single_type = group:match("^([^%s]+)$")
				if single_type then
					table.insert(param_list, { name = "_", type = single_type })
				end
			end
		end
	end

	-- Parse return values
	local return_list = {}
	if returns and returns ~= "" then
		-- Clean up returns string
		returns = returns:gsub("^%s*", ""):gsub("%s*$", "")

		-- Handle multiple return values in parentheses
		if returns:match("^%((.-)%)$") then
			local return_groups = {}
			for return_group in returns:match("^%((.-)%)$"):gmatch("([^,]+)") do
				table.insert(return_groups, return_group:gsub("^%s*", ""):gsub("%s*$", ""))
			end

			for _, group in ipairs(return_groups) do
				local ret_name, ret_type = group:match("([%w_]+)%s+([^%s]+)$")

				if ret_name and ret_type then
					-- Named return
					table.insert(return_list, { name = ret_name, type = ret_type })
				else
					-- Unnamed return
					local single_type = group:match("^([^%s]+)$")
					if single_type then
						table.insert(return_list, { name = "", type = single_type })
					end
				end
			end
		else
			-- Single return value without parentheses
			table.insert(return_list, { name = "", type = returns })
		end
	end

	-- Parse receiver (if method)
	local receiver_type
	if receiver then
		receiver = receiver:gsub("^%(", ""):gsub("%)%s*$", "")
		receiver_type = receiver:match("[%w_%.%*]+$")
	end

	return {
		name = name,
		receiver = receiver_type,
		params = param_list,
		returns = return_list,
	}
end

-- Parse Go type/struct definition
local function parse_go_type(line, next_lines)
	local type_pattern = "^%s*type%s+([%w_]+)%s+(.+)$"
	local name, typedef = line:match(type_pattern)

	if not name then
		return nil
	end

	-- Check if it's a struct
	local is_struct = typedef:match("^struct%s*{") ~= nil

	-- If not defined inline, check next lines
	if not is_struct and typedef:match("struct%s*$") then
		is_struct = true
	end

	-- Parse struct fields (for detailed documentation)
	local fields = {}
	if is_struct then
		local in_struct = false
		if typedef:match("^struct%s*{") then
			in_struct = true
		end

		for i, next_line in ipairs(next_lines) do
			if not in_struct and next_line:match("{") then
				in_struct = true
				goto continue
			end

			if in_struct then
				if next_line:match("}") then
					break
				end

				-- Parse field
				local field_pattern = "^%s*([%w_]+)%s+([^%s]+)%s*`?(.-)$"
				local field_name, field_type, tags = next_line:match(field_pattern)

				if field_name then
					table.insert(fields, {
						name = field_name,
						type = field_type,
						tags = tags:match("`(.+)`") or "",
					})
				end
			end

			::continue::
		end
	end

	return {
		name = name,
		is_struct = is_struct,
		typedef = typedef,
		fields = fields,
	}
end

-- Generate Python function documentation
local function generate_python_function_doc(func_info)
	local style = config.python.doc_style
	local docs = {}

	if style == "google" then
		table.insert(docs, '"""' .. func_info.name .. " function.")
		table.insert(docs, "")

		if #func_info.params > 0 and config.python.include_types then
			table.insert(docs, "Args:")
			for _, param in ipairs(func_info.params) do
				local param_doc = "    " .. param.name
				if param.type and param.type ~= "" then
					param_doc = param_doc .. " (" .. param.type .. "): "
				else
					param_doc = param_doc .. ": "
				end
				table.insert(docs, param_doc)
			end
			table.insert(docs, "")
		end

		if func_info.return_type and config.python.include_returns then
			table.insert(docs, "Returns:")
			table.insert(docs, "    " .. func_info.return_type .. ": ")
			table.insert(docs, "")
		end

		if #func_info.exceptions > 0 and config.python.include_raises then
			table.insert(docs, "Raises:")
			for _, exception in ipairs(func_info.exceptions) do
				table.insert(docs, "    " .. exception .. ": ")
			end
			table.insert(docs, "")
		end
	elseif style == "numpy" then
		table.insert(docs, '"""')
		table.insert(docs, func_info.name .. " function.")
		table.insert(docs, "")

		if #func_info.params > 0 and config.python.include_types then
			table.insert(docs, "Parameters")
			table.insert(docs, "----------")
			for _, param in ipairs(func_info.params) do
				local param_doc = param.name
				if param.type and param.type ~= "" then
					param_doc = param_doc .. " : " .. param.type
				end
				table.insert(docs, param_doc)
				table.insert(docs, "    ")
			end
			table.insert(docs, "")
		end

		if func_info.return_type and config.python.include_returns then
			table.insert(docs, "Returns")
			table.insert(docs, "-------")
			table.insert(docs, func_info.return_type)
			table.insert(docs, "    ")
			table.insert(docs, "")
		end

		if #func_info.exceptions > 0 and config.python.include_raises then
			table.insert(docs, "Raises")
			table.insert(docs, "------")
			for _, exception in ipairs(func_info.exceptions) do
				table.insert(docs, exception)
				table.insert(docs, "    ")
			end
			table.insert(docs, "")
		end
	elseif style == "sphinx" then
		table.insert(docs, '"""' .. func_info.name .. " function.")
		table.insert(docs, "")

		if #func_info.params > 0 and config.python.include_types then
			for _, param in ipairs(func_info.params) do
				local param_doc = ":param " .. param.name .. ": "
				if param.type and param.type ~= "" then
					param_doc = param_doc .. "\n:type " .. param.name .. ": " .. param.type
				end
				table.insert(docs, param_doc)
			end
			table.insert(docs, "")
		end

		if func_info.return_type and config.python.include_returns then
			table.insert(docs, ":return: ")
			table.insert(docs, ":rtype: " .. func_info.return_type)
			table.insert(docs, "")
		end

		if #func_info.exceptions > 0 and config.python.include_raises then
			for _, exception in ipairs(func_info.exceptions) do
				table.insert(docs, ":raises " .. exception .. ": ")
			end
			table.insert(docs, "")
		end
	end

	table.insert(docs, '"""')
	return docs
end

-- Generate Python class documentation
local function generate_python_class_doc(class_info)
	local style = config.python.doc_style
	local docs = {}

	if style == "google" then
		table.insert(docs, '"""' .. class_info.name .. " class.")
		table.insert(docs, "")

		if #class_info.inherits > 0 then
			table.insert(docs, "Inherits from:")
			for _, parent in ipairs(class_info.inherits) do
				table.insert(docs, "    " .. parent)
			end
			table.insert(docs, "")
		end

		table.insert(docs, "Attributes:")
		table.insert(docs, "    None")
		table.insert(docs, "")
	elseif style == "numpy" then
		table.insert(docs, '"""')
		table.insert(docs, class_info.name .. " class.")
		table.insert(docs, "")

		if #class_info.inherits > 0 then
			table.insert(docs, "Inheritance")
			table.insert(docs, "----------")
			for _, parent in ipairs(class_info.inherits) do
				table.insert(docs, parent)
			end
			table.insert(docs, "")
		end

		table.insert(docs, "Attributes")
		table.insert(docs, "----------")
		table.insert(docs, "None")
		table.insert(docs, "")
	elseif style == "sphinx" then
		table.insert(docs, '"""' .. class_info.name .. " class.")
		table.insert(docs, "")

		if #class_info.inherits > 0 then
			table.insert(docs, "Inherits from: " .. table.concat(class_info.inherits, ", "))
			table.insert(docs, "")
		end
	end

	table.insert(docs, '"""')
	return docs
end

-- Generate C function documentation
local function generate_c_function_doc(func_info)
	local docs = {}

	table.insert(docs, "/**")
	table.insert(docs, " * @brief ")
	table.insert(docs, " *")

	-- Parameters
	if #func_info.params > 0 and config.c.include_params then
		-- Find max param name length for alignment
		local max_name_len = 0
		if config.c.align_params then
			for _, param in ipairs(func_info.params) do
				max_name_len = math.max(max_name_len, #param.name)
			end
		end

		for _, param in ipairs(func_info.params) do
			local padding = ""
			if config.c.align_params then
				padding = string.rep(" ", max_name_len - #param.name)
			end

			table.insert(docs, " * @param " .. param.name .. padding .. "  ")
		end
		table.insert(docs, " *")
	end

	-- Return value
	if func_info.return_type and func_info.return_type ~= "void" and config.c.include_return then
		table.insert(docs, " * @return ")
		table.insert(docs, " *")
	end

	table.insert(docs, " */")
	return docs
end

-- Generate C++ function documentation
local function generate_cpp_function_doc(func_info)
	local style = config.cpp.doc_style
	local docs = {}

	if style == "doxygen" then
		table.insert(docs, "/**")

		if config.cpp.include_brief then
			table.insert(docs, " * @brief ")
		end

		table.insert(docs, " *")

		-- Parameters
		if #func_info.params > 0 and config.cpp.include_params then
			for _, param in ipairs(func_info.params) do
				table.insert(docs, " * @param " .. param.name .. " ")
			end
			table.insert(docs, " *")
		end

		-- Return value
		if func_info.return_type and func_info.return_type ~= "void" and config.cpp.include_return then
			table.insert(docs, " * @return ")
			table.insert(docs, " *")
		end

		table.insert(docs, " */")
	elseif style == "javadoc" then
		table.insert(docs, "/**")
		table.insert(docs, " * ")
		table.insert(docs, " *")

		-- Parameters
		if #func_info.params > 0 and config.cpp.include_params then
			for _, param in ipairs(func_info.params) do
				table.insert(docs, " * @param " .. param.name .. " ")
			end
			table.insert(docs, " *")
		end

		-- Return value
		if func_info.return_type and func_info.return_type ~= "void" and config.cpp.include_return then
			table.insert(docs, " * @return ")
			table.insert(docs, " *")
		end

		table.insert(docs, " */")
	end

	return docs
end

-- Generate C++ class documentation
local function generate_cpp_class_doc(class_info)
	local style = config.cpp.doc_style
	local docs = {}

	if style == "doxygen" then
		table.insert(docs, "/**")

		if config.cpp.include_brief then
			table.insert(docs, " * @brief " .. class_info.name .. " " .. class_info.class_type)
		end

		table.insert(docs, " *")

		-- Base classes
		if #class_info.inherits > 0 then
			for _, inherit in ipairs(class_info.inherits) do
				table.insert(docs, " * @inherit " .. inherit.access .. " " .. inherit.name)
			end
			table.insert(docs, " *")
		end

		table.insert(docs, " */")
	elseif style == "javadoc" then
		table.insert(docs, "/**")
		table.insert(docs, " * The " .. class_info.name .. " " .. class_info.class_type)
		table.insert(docs, " *")

		-- Base classes
		if #class_info.inherits > 0 then
			table.insert(docs, " * Extends/implements:")
			for _, inherit in ipairs(class_info.inherits) do
				table.insert(docs, " *   - " .. inherit.name .. " (" .. inherit.access .. ")")
			end
			table.insert(docs, " *")
		end

		table.insert(docs, " */")
	end

	return docs
end

-- Generate Go function documentation
local function generate_go_function_doc(func_info)
	local docs = {}

	-- Go doc comments use // prefix

	-- Start with function name and brief description
	local first_letter = config.go.capitalize_first_letter and "F" or "f"
	table.insert(docs, "// " .. func_info.name .. " " .. first_letter .. "unction ")

	-- If it's a method, mention the receiver
	if func_info.receiver then
		table.insert(docs, "// Method of " .. func_info.receiver)
	end

	-- Parameters
	if #func_info.params > 0 and config.go.include_params then
		table.insert(docs, "//")
		for _, param in ipairs(func_info.params) do
			if param.name ~= "_" then -- Skip unnamed parameters
				table.insert(docs, "// " .. param.name .. ": ")
			end
		end
	end

	-- Return values
	if #func_info.returns > 0 and config.go.include_returns then
		table.insert(docs, "//")
		if #func_info.returns == 1 and func_info.returns[1].name == "" then
			-- Single unnamed return
			table.insert(docs, "// Returns: ")
		else
			table.insert(docs, "// Returns:")
			for _, ret in ipairs(func_info.returns) do
				if ret.name ~= "" then
					table.insert(docs, "//   " .. ret.name .. ": ")
				else
					table.insert(docs, "//   " .. ret.type .. ": ")
				end
			end
		end
	end

	return docs
end

-- Generate Go type documentation
local function generate_go_type_doc(type_info)
	local docs = {}

	-- Go doc comments use // prefix

	-- Start with type name
	local first_letter = config.go.capitalize_first_letter and "T" or "t"
	table.insert(docs, "// " .. type_info.name .. " " .. first_letter .. "ype ")

	-- For structs, document the fields
	if type_info.is_struct and #type_info.fields > 0 then
		table.insert(docs, "//")
		table.insert(docs, "// Fields:")

		for _, field in ipairs(type_info.fields) do
			table.insert(docs, "//   " .. field.name .. ": ")
		end
	end

	return docs
end

-- Generate documentation for the current function or class
function M.generate_doc()
	local filetype = vim.bo.filetype

	-- Get current line and some context
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local current_line = vim.api.nvim_get_current_line()
	local current_line_nr = cursor_pos[1]

	-- Get some lines following the current line for context
	local next_lines = {}
	for i = current_line_nr + 1, current_line_nr + 10 do
		local line = vim.api.nvim_buf_get_line(0, i - 1, false)
		table.insert(next_lines, line)
	end

	-- Get some lines before the current line to check for existing docs
	local prev_lines = {}
	for i = math.max(1, current_line_nr - 5), current_line_nr - 1 do
		local line = vim.api.nvim_buf_get_line(0, i - 1, false)
		table.insert(prev_lines, line)
	end

	-- Check if documentation already exists
	local has_doc = false
	if filetype == "python" then
		for _, line in ipairs(prev_lines) do
			if line:match('"""') then
				has_doc = true
				break
			end
		end
	elseif filetype == "c" or filetype == "cpp" then
		for _, line in ipairs(prev_lines) do
			if line:match("/%*%*") then
				has_doc = true
				break
			end
		end
	elseif filetype == "go" then
		for _, line in ipairs(prev_lines) do
			if line:match("^%s*//") then
				has_doc = true
				break
			end
		end
	end

	if has_doc then
		vim.notify("Documentation already exists", vim.log.levels.WARN)
		return
	end

	-- Parse the code and generate documentation
	local docs

	if filetype == "python" then
		-- Try to parse as function first
		local func_info = parse_python_function(current_line, next_lines)

		if func_info then
			docs = generate_python_function_doc(func_info)
		else
			-- Try to parse as class
			local class_info = parse_python_class(current_line)

			if class_info then
				docs = generate_python_class_doc(class_info)
			end
		end
	elseif filetype == "c" then
		-- Parse as C function
		local func_info = parse_c_function(current_line, next_lines)

		if func_info then
			docs = generate_c_function_doc(func_info)
		end
	elseif filetype == "cpp" then
		-- Try to parse as function first
		local func_info = parse_c_function(current_line, next_lines)

		if func_info then
			docs = generate_cpp_function_doc(func_info)
		else
			-- Try to parse as class
			local class_info = parse_cpp_class(current_line, next_lines)

			if class_info then
				docs = generate_cpp_class_doc(class_info)
			end
		end
	elseif filetype == "go" then
		-- Try to parse as function first
		local func_info = parse_go_function(current_line)

		if func_info then
			docs = generate_go_function_doc(func_info)
		else
			-- Try to parse as type
			local type_info = parse_go_type(current_line, next_lines)

			if type_info then
				docs = generate_go_type_doc(type_info)
			end
		end
	end

	if not docs then
		vim.notify("Could not parse code under cursor", vim.log.levels.ERROR)
		return
	end

	-- Calculate the indentation of the current line
	local indent = current_line:match("^%s*")

	-- Add indentation to each line of docs
	for i, line in ipairs(docs) do
		if line ~= "" then
			docs[i] = indent .. line
		end
	end

	-- Insert docs above the current line
	vim.api.nvim_buf_set_lines(0, current_line_nr - 1, current_line_nr - 1, false, docs)

	-- Position cursor after the docs
	vim.api.nvim_win_set_cursor(0, { current_line_nr, #indent })
end

-- Setup function for customization
function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Create commands
function M.create_commands()
	vim.api.nvim_create_user_command("GenDoc", function()
		M.generate_doc()
	end, {})
end

-- Setup keymaps
function M.setup_keymaps()
	vim.keymap.set("n", "<leader>gd", M.generate_doc, { noremap = true, desc = "Generate documentation" })
end

-- Auto-setup
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		M.create_commands()
		M.setup_keymaps()
	end,
})

return M
