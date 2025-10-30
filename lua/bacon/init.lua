-- A companion to bacon - https://dystroy.org/bacon
local config = require("bacon.config")
-- local options = config.options

local Bacon = {}

local api = vim.api
local buf, win
local ns_id = api.nvim_create_namespace("bacon")

local locations
local location_idx = 0 -- 1-indexed, 0 is "none"
local cached_locations_file = nil -- Cache the last found .bacon-locations file path
local cached_socket_dir = nil -- Cache the last found .bacon.socket directory

function Bacon.setup(opts)
	config.setup(opts)
end

local function center(str, width)
	local shift = math.floor(width / 2) - math.floor(string.len(str) / 2)
	local remain = width - shift - string.len(str)
	return string.rep(" ", shift) .. str .. string.rep(" ", remain)
end

local function open_window()
	Bacon.close_window() -- close the window if it's already open

	buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "bacon"

	local width = vim.o.columns
	local height = vim.o.lines

	local win_height = math.ceil(height * 0.8 - 4)
	local win_width = math.ceil(width * 0.8)
	local row = math.ceil((height - win_height) / 2 - 1)
	local col = math.ceil((width - win_width) / 2)

	local opts = {
		style = "minimal",
		relative = "editor",
		width = win_width,
		height = win_height,
		row = row,
		col = col,
	}

	win = api.nvim_open_win(buf, true, opts)
	vim.wo[win].cursorline = true
	local win_width_actual = api.nvim_win_get_width(0)
	local header_text = center("Bacon Locations (hit q to close)", win_width_actual)
	api.nvim_buf_set_lines(buf, 0, -1, false, { header_text, "", "" })
	api.nvim_buf_set_extmark(buf, ns_id, 0, 0, { end_col = #header_text, hl_group = "BaconHeader" })
end

-- Close the bacon list. Do nothing if it's not open
function Bacon.close_window()
	if win ~= nil then
		if win == api.nvim_get_current_win() then
			api.nvim_win_close(win, true)
		end
		win = nil
	end
end

-- Tell whether a file exists
local function file_exists(file)
	local f = io.open(file, "rb")
	if f then
		f:close()
	end
	return f ~= nil
end

-- get all lines from a file
local function lines_from(file)
	local lines = {}
	for line in io.lines(file) do
		lines[#lines + 1] = line
	end
	return lines
end

-- Find the project root by looking for .git directory or falling back to current directory
local function find_project_root()
	local dir = vim.fn.getcwd()
	-- Try to find .git directory by walking up
	local current = dir
	while current ~= "/" do
		if file_exists(current .. "/.git") or file_exists(current .. "/.git/config") then
			return current
		end
		current = vim.fn.fnamemodify(current, ":h")
	end
	-- Fall back to current working directory
	return dir
end

-- Check if a path is ignored by git using git check-ignore
local function is_git_ignored(path)
	-- Always ignore .git directory itself
	if path:match("/%.git$") or path:match("/%.git/") then
		return true
	end

	-- Use git check-ignore to check if path is ignored
	-- -q flag makes it quiet (no output), we only check exit code
	-- Exit code 0 = ignored, 1 = not ignored, >1 = error (not in repo, git not available, etc.)
	local result = vim.fn.system({'git', 'check-ignore', '-q', path})
	local exit_code = vim.v.shell_error

	-- If git command failed (exit code > 1), fall back to false (don't ignore)
	-- This handles cases where we're not in a git repo or git is not available
	if exit_code > 1 then
		return false
	end

	return exit_code == 0
end

-- Recursively find all instances of a file in a directory tree
local function find_files_recursive(dir, filename)
	local results = {}

	-- Check if we're in a git repository once at the start
	local in_git_repo = vim.fn.system({'git', 'rev-parse', '--git-dir'}):match("%S+") ~= nil

	local function search_dir(current_dir)
		-- Check if the target file exists in current directory
		local target_path = current_dir .. "/" .. filename
		if file_exists(target_path) then
			table.insert(results, target_path)
		end

		-- Get all entries in the directory
		local handle = vim.uv.fs_scandir(current_dir)
		if handle then
			while true do
				local name, type = vim.uv.fs_scandir_next(handle)
				if not name then break end

				-- Recursively search subdirectories, skip hidden and git-ignored directories
				if type == "directory" and name ~= "." and name ~= ".." then
					local subdir_path = current_dir .. "/" .. name
					-- Skip hidden directories
					if not name:match("^%.") then
						-- Only use git check-ignore if we're in a git repo
						if not in_git_repo or not is_git_ignored(subdir_path) then
							search_dir(subdir_path)
						end
					end
				end
			end
		end
	end

	search_dir(dir)
	return results
end

-- Check if a .bacon.socket file exists in the given directory
local function has_socket_file(dir)
	return file_exists(dir .. "/.bacon.socket")
end

-- Find the directory containing .bacon.socket
-- Returns: directory path if exactly one socket found, nil + error message otherwise
local function find_socket_directory()
	-- Check cache first - if we have a cached directory and the socket still exists, use it
	if cached_socket_dir and has_socket_file(cached_socket_dir) then
		return cached_socket_dir, nil
	end

	-- Cache miss or stale cache - search for socket
	local project_root = find_project_root()
	local found_files = find_files_recursive(project_root, ".bacon.socket")

	if #found_files == 0 then
		cached_socket_dir = nil
		return nil, "No .bacon.socket file found in project"
	elseif #found_files == 1 then
		local dir = vim.fn.fnamemodify(found_files[1], ":h")
		cached_socket_dir = dir
		return dir, nil
	else
		cached_socket_dir = nil
		local error_msg = "Multiple .bacon.socket files found:\n"
		for _, file_path in ipairs(found_files) do
			local dir = vim.fn.fnamemodify(file_path, ":h")
			error_msg = error_msg .. "  - " .. dir .. "\n"
		end
		return nil, error_msg
	end
end

function Bacon.move_cursor()
	local new_pos = math.max(3, api.nvim_win_get_cursor(win)[1] - 1)
	api.nvim_win_set_cursor(win, { new_pos, 0 })
end

local function set_mappings()
	local mappings = {
		["<cr>"] = "open_selected_location()",
		q = "close_window()",
		k = "move_cursor()",
	}
	for digit = 1, 9 do
		mappings["" .. digit] = 'close_window() require"bacon".open_location(' .. digit .. ")"
	end

	for k, v in pairs(mappings) do
		api.nvim_buf_set_keymap(buf, "n", k, ':lua require"bacon".' .. v .. "<cr>", {
			nowait = true,
			noremap = true,
			silent = true,
		})
	end
	local other_chars = {
		"a",
		"b",
		"c",
		"d",
		"e",
		"f",
		"g",
		"i",
		"n",
		"o",
		"p",
		"r",
		"s",
		"t",
		"u",
		"v",
		"w",
		"x",
		"y",
		"z",
	}
	for _, v in ipairs(other_chars) do
		api.nvim_buf_set_keymap(buf, "n", v, "", { nowait = true, noremap = true, silent = true })
		api.nvim_buf_set_keymap(buf, "n", v:upper(), "", { nowait = true, noremap = true, silent = true })
		api.nvim_buf_set_keymap(buf, "n", "<c-" .. v .. ">", "", { nowait = true, noremap = true, silent = true })
	end
end

-- Open a specific location and remember it as "last
function Bacon.open_location(idx)
	local location = locations[idx]
	api.nvim_command("edit " .. location.filename)

	-- Validate cursor position to avoid out-of-range errors
	local buf_line_count = api.nvim_buf_line_count(0)
	local target_line = math.min(location.lnum, buf_line_count)
	local line_content = api.nvim_buf_get_lines(0, target_line - 1, target_line, false)[1] or ""
	local target_col = math.min(location.col - 1, #line_content)

	api.nvim_win_set_cursor(0, { target_line, target_col })
	location_idx = idx
end

-- Open the location under the cursor in the location window
function Bacon.open_selected_location()
	local i = api.nvim_win_get_cursor(win)[1] - 2
	Bacon.close_window()
	if i > 0 and i <= #locations then
		Bacon.open_location(i)
	end
end

local function same_location(a, b)
	return a and b and a.filename == b.filename and a.lnum == b.lnum and a.col == b.col
end

-- Load the locations found in the .bacon-locations file.
-- Doesn't modify the display, only the location table.
-- We first search recursively downward from the project root, then fall back to searching upward.
function Bacon.bacon_load()
	local old_location = nil
	if location_idx > 0 then
		old_location = locations[location_idx]
	end
	locations = {}

	local selected_file = nil
	local file_dir = ""

	-- Check cache first - if we have a cached file and it still exists, use it
	if cached_locations_file and file_exists(cached_locations_file) then
		selected_file = cached_locations_file
		file_dir = vim.fn.fnamemodify(selected_file, ":h") .. "/"
	end

	-- Step 1: Try recursive downward search from project root (only if cache miss)
	if not selected_file then
		local project_root = find_project_root()
		local found_files = find_files_recursive(project_root, ".bacon-locations")

		if #found_files > 0 then
			-- Check which files have corresponding .bacon.socket files
			local files_with_socket = {}
			for _, file_path in ipairs(found_files) do
				local dir = vim.fn.fnamemodify(file_path, ":h")
				if has_socket_file(dir) then
					table.insert(files_with_socket, file_path)
				end
			end

			-- Select the appropriate file based on socket presence
			if #files_with_socket == 1 then
				-- Exactly one file has a socket, use it
				selected_file = files_with_socket[1]
			elseif #files_with_socket > 1 then
				-- Multiple files have sockets, warn and use first one
				print("Warning: Multiple .bacon-locations files with .bacon.socket found. Using the first one. Found:")
				for _, file_path in ipairs(files_with_socket) do
					print("  - " .. file_path)
				end
				selected_file = files_with_socket[1]
			elseif #found_files == 1 then
				-- Exactly one file without socket
				selected_file = found_files[1]
			else
				-- Multiple files without sockets, warn and use first one
				print("Warning: Multiple .bacon-locations files found but none have a .bacon.socket. Using the first one. Found:")
				for _, file_path in ipairs(found_files) do
					print("  - " .. file_path)
				end
				selected_file = found_files[1]
			end

			-- Extract the directory from the selected file for relative path resolution
			file_dir = vim.fn.fnamemodify(selected_file, ":h") .. "/"
		end

		-- Step 2: If no file found in downward search, fall back to upward search
		if not selected_file then
			local dir = ""
			repeat
				local file = dir .. ".bacon-locations"
				if file_exists(file) then
					selected_file = file
					file_dir = dir
					break
				end

				if vim.uv.fs_realpath(dir) == "/" then
					break
				end
				dir = "../" .. dir
			until not file_exists(dir)
		end
	end

	-- Step 3: Parse and load the selected file
	if selected_file then
		local raw_lines = lines_from(selected_file)
		for _, raw_line in ipairs(raw_lines) do
			-- each line is like "error lua/bacon.lua:61:15 the faucet is leaking"
			local cat
			local path
			local line
			local col
			local text

			if vim.fn.has("win32") > 0 then
				raw_line = raw_line:gsub("\\", "/")
				cat, path, line, col, text = string.match(raw_line, "(%S+) (%a:[^:]+):(%d+):(%d+)%s*(.*)")
			else
				cat, path, line, col, text = string.match(raw_line, "(%S+) ([^:]+):(%d+):(%d+)%s*(.*)")
			end

			if cat ~= nil and #cat > 0 then
				local loc_path = path
				if string.sub(loc_path, 1, 1) ~= "/" then
					loc_path = file_dir .. loc_path
				end
				local location = {
					cat = cat,
					filename = loc_path,
					lnum = tonumber(line),
					col = tonumber(col),
				}
				if text ~= "" then
					location.text = text
				else
					location.text = ""
				end
				table.insert(locations, location)
			end
		end

		-- Update quickfix list if enabled
		if config.options.quickfix.enabled then
			vim.fn.setqflist(locations, " ")
			vim.fn.setqflist({}, "a", { title = "Bacon" })
			if config.options.quickfix.event_trigger then
				-- triggers the Neovim event for populating the quickfix list
				vim.cmd("doautocmd QuickFixCmdPost")
			end
		end

		-- Restore previously selected location if it still exists
		location_idx = 0
		if old_location then
			for idx, location in ipairs(locations) do
				if same_location(location, old_location) then
					location_idx = idx
					break
				end
			end
		end

		-- Cache the selected file for future loads
		cached_locations_file = selected_file
	end
end

-- Fill our buf with the locations, one per line
local function update_view()
	vim.bo[buf].modifiable = true
	local cwd = vim.fn.getcwd() .. "/"
	local lines = {}
	for i, location in ipairs(locations) do
		local cat = string.upper(location.cat):sub(1, 1)
		local path = location.filename
		if string.find(path, cwd) == 1 then
			path = string.gsub(location.filename, cwd, "")
		end
		local shield = center("" .. i, 5)
		table.insert(
			lines,
			" " .. cat .. shield .. path .. ":" .. location.lnum .. ":" .. location.col .. " | " .. location.text
		)
	end
	api.nvim_buf_set_lines(buf, 2, -1, false, lines)
	vim.bo[buf].modifiable = false
end

-- Show the window with the locations, assuming they have been previously loaded
function Bacon.bacon_show()
	if #locations > 0 then
		location_idx = 0
		open_window()
		update_view()
		set_mappings()
		vim.wo[win].wrap = false
		api.nvim_win_set_cursor(win, { 3, 1 })
	else
		print("Error: no bacon locations loaded")
	end
end

-- Load the locations, then show them
function Bacon.bacon_list()
	Bacon.bacon_load()
	Bacon.bacon_show()
end

function Bacon.bacon_previous()
	if #locations > 0 then
		location_idx = location_idx - 1
		if location_idx < 1 then
			location_idx = #locations
		end
		Bacon.open_location(location_idx)
	else
		print("Error: no bacon locations loaded")
	end
end

function Bacon.bacon_next()
	if #locations > 0 then
		location_idx = location_idx + 1
		if location_idx > #locations then
			location_idx = 1
		end
		Bacon.open_location(location_idx)
	else
		print("Error: no bacon locations loaded")
	end
end

-- Send a command to bacon via its socket
-- action: the bacon action to send (e.g., "job:test", "job:clippy", "scroll-lines(-2)")
function Bacon.bacon_send(action)
	if not action or action == "" then
		print("Error: No action specified for BaconSend")
		return
	end

	-- Find the directory containing .bacon.socket
	local socket_dir, error_msg = find_socket_directory()
	if not socket_dir then
		print("Error: " .. error_msg)
		return
	end

	-- Execute bacon --send command with the socket directory as cwd
	local cmd = string.format("cd '%s' && bacon --send '%s'", socket_dir, action:gsub("'", "'\\''"))
	local result = vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	if exit_code == 0 then
		print("Bacon: Sent '" .. action .. "' to " .. socket_dir)
	else
		-- Display error message
		local error_output = result:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
		if error_output == "" then
			error_output = "Command failed with exit code " .. exit_code
		end
		print("Error sending to bacon: " .. error_output)
	end
end

-- Return the public API
return Bacon
