local M = {}

local config = {
	author = "Sanjith Kumar V",
	email = "sanjith959@gmail.com",
	license = "MIT",
	include_timestamp = true,
}

local headers = {
	python = function(filename)
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		return {
			"#!/usr/bin/env python3",
			"# -*- coding: utf-8 -*-",
			"# " .. string.rep("-", 60),
			"# File Name: " .. filename,
			"# Author: " .. config.author,
			"# Email: " .. config.email,
			"# License: " .. config.license,
			config.include_timestamp and "# Created on: " .. timestamp or nil,
			"# " .. string.rep("-", 60),
			'"""',
			"Description: ",
			"",
			"Usage:",
			"   ",
			'"""',
			"",
			"",
		}
	end,
	c = function(filename)
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		return {
			"/**",
			" * " .. string.rep("-", 60),
			" * @file " .. filename,
			" * @author " .. config.author .. " <" .. config.email .. ">",
			config.include_timestamp and " * @date " .. timestamp or nil,
			" * @license " .. config.license,
			" * " .. string.rep("-", 60),
			" * @brief ",
			" * ",
			" * @details ",
			" * ",
			" */",
			"",
			"#include <stdio.h>",
			"",
			"int main(int argc, char *argv[]) {",
			'    printf("Hello World!\\n");',
			"    return 0;",
			"}",
			"",
		}
	end,
	cpp = function(filename)
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		return {
			"/**",
			" * " .. string.rep("-", 60),
			" * @file " .. filename,
			" * @author " .. config.author .. " <" .. config.email .. ">",
			config.include_timestamp and " * @date " .. timestamp or nil,
			" * @license " .. config.license,
			" * " .. string.rep("-", 60),
			" * @brief ",
			" * ",
			" * @details ",
			" * ",
			" */",
			"",
			"#include <iostream>",
			"",
			"int main(int argc, char *argv[]) {",
			'    std::cout << "Hello World!\\n";',
			"    return 0;",
			"}",
			"",
		}
	end,

	go = function(filename)
		local timestamp = os.date("%Y-%m-%d %H:%M:%S")
		return {
			"// " .. string.rep("-", 78),
			"// Filename: " .. filename,
			"// Author: " .. config.author,
			"// Email: " .. config.email,
			config.include_timestamp and ("// Created: " .. timestamp) or nil,
			"// License: " .. config.license,
			"// " .. string.rep("-", 78),
			"// Description: ",
			"//",
			"",
			"package main",
			"",
			"import (",
			'    "fmt"',
			")",
			"",
			"func main() {",
			"    // Your code here",
			'    fmt.Println("Hello, World!")',
			"}",
			"",
		}
	end,
}

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.insert_header()
	local filename = vim.fn.expand("%:t")
	local filetype = vim.bo.filetype

	local header_func = headers[filetype]
	if not header_func then
		print("Unsupported filetype: " .. filetype)
		return
	end

	local header = header_func(filename)

	local filtered_lines = header_func(filename)

	local filtered_lines = {}
	for _, line in ipairs(header) do
		if line ~= "" then
			table.insert(filtered_lines, line)
		end
	end

	vim.api.nvim_buf_set_lines(0, 0, 0, false, filtered_lines)
end

function M.new_file_with_header(filetype, filename)
	-- Create a new buffer
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buf)

	-- Set the buffer's filetype
	vim.bo.filetype = filetype

	-- Save the buffer with the given filename
	vim.cmd("write " .. filename)

	-- Insert header
	M.insert_header()
	vim.cmd("write")
end

-- Set up commands
function M.create_commands()
	vim.api.nvim_create_user_command("InsertHeader", function()
		M.insert_header()
	end, {})

	vim.api.nvim_create_user_command("NewPythonFile", function(opts)
		M.new_file_with_header("python", opts.args)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("NewCFile", function(opts)
		M.new_file_with_header("c", opts.args)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("NewCppFile", function(opts)
		M.new_file_with_header("cpp", opts.args)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("NewGoFile", function(opts)
		M.new_file_with_header("go", opts.args)
	end, { nargs = 1 })
end

-- Auto-setup
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		M.create_commands()
	end,
})

return M
