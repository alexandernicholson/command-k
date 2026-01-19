-- Command K - AI Command Assistant for Neovim
-- Like Cursor's CMD+K, but for Neovim

local M = {}

-- Default configuration
M.config = {
  -- Path to cmdk-rs binary (auto-detected if nil)
  binary_path = nil,
  -- Keybinding to open Command K
  keymap = "<C-k>",
  -- Floating window settings
  width = 0.8,
  height = 0.7,
  border = "rounded",
  -- Whether to gather Neovim-specific context
  send_buffer_content = true,
  send_filetype = true,
  send_cursor_position = true,
  send_visual_selection = true,
  send_lsp_diagnostics = true,
}

-- State
local state = {
  buf = nil,
  win = nil,
  result_file = nil,
  original_buf = nil,
  original_win = nil,
  visual_selection = nil,
}

-- Find the cmdk-rs binary
local function find_binary()
  if M.config.binary_path then
    return M.config.binary_path
  end

  -- Try common locations
  local paths = {
    -- In plugin directory
    vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h") .. "/cmdk-rs/target/release/cmdk-rs",
    -- In PATH
    vim.fn.exepath("cmdk-rs"),
    -- Home directory
    vim.fn.expand("~/.local/bin/cmdk-rs"),
    vim.fn.expand("~/.cargo/bin/cmdk-rs"),
  }

  for _, path in ipairs(paths) do
    if path ~= "" and vim.fn.executable(path) == 1 then
      return path
    end
  end

  return nil
end

-- Get current buffer content (limited to avoid huge payloads)
local function get_buffer_content()
  if not M.config.send_buffer_content then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Limit to ~10KB
  if #content > 10000 then
    content = content:sub(1, 10000) .. "\n... (truncated)"
  end

  return content
end

-- Get visual selection if any
local function get_visual_selection()
  if not M.config.send_visual_selection then
    return nil
  end

  -- Check if we have a saved visual selection
  if state.visual_selection then
    return state.visual_selection
  end

  return nil
end

-- Get LSP diagnostics for current buffer
local function get_lsp_diagnostics()
  if not M.config.send_lsp_diagnostics then
    return nil
  end

  local diagnostics = vim.diagnostic.get(0)
  if #diagnostics == 0 then
    return nil
  end

  local result = {}
  for i, d in ipairs(diagnostics) do
    if i > 10 then
      table.insert(result, "... and " .. (#diagnostics - 10) .. " more")
      break
    end
    local severity = vim.diagnostic.severity[d.severity] or "Unknown"
    table.insert(result, string.format("[%s] Line %d: %s", severity, d.lnum + 1, d.message))
  end

  return table.concat(result, "\n")
end

-- Gather Neovim-specific context
local function gather_nvim_context()
  local ctx = {}

  -- File info
  ctx.filepath = vim.fn.expand("%:p")
  ctx.filename = vim.fn.expand("%:t")
  ctx.filetype = vim.bo.filetype
  ctx.buftype = vim.bo.buftype

  -- Cursor position
  if M.config.send_cursor_position then
    local cursor = vim.api.nvim_win_get_cursor(0)
    ctx.cursor_line = cursor[1]
    ctx.cursor_col = cursor[2]
  end

  -- Buffer content
  ctx.buffer_content = get_buffer_content()

  -- Visual selection
  ctx.visual_selection = get_visual_selection()

  -- LSP diagnostics
  ctx.lsp_diagnostics = get_lsp_diagnostics()

  -- Current line
  ctx.current_line = vim.api.nvim_get_current_line()

  return ctx
end

-- Create the floating window
local function create_float_win()
  -- Calculate dimensions
  local width = math.floor(vim.o.columns * M.config.width)
  local height = math.floor(vim.o.lines * M.config.height)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Window options
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = M.config.border,
    title = " ⌘K Command K ",
    title_pos = "center",
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, opts)

  -- Set window options
  vim.api.nvim_set_option_value("winblend", 0, { win = win })

  return buf, win
end

-- Write context to a temp file for the binary to read
local function write_context_file(ctx)
  local tmpfile = vim.fn.tempname() .. ".cmdk-nvim-context"

  local lines = {
    "CMDK_NVIM_FILEPATH=" .. (ctx.filepath or ""),
    "CMDK_NVIM_FILENAME=" .. (ctx.filename or ""),
    "CMDK_NVIM_FILETYPE=" .. (ctx.filetype or ""),
    "CMDK_NVIM_CURSOR_LINE=" .. (ctx.cursor_line or ""),
    "CMDK_NVIM_CURSOR_COL=" .. (ctx.cursor_col or ""),
    "CMDK_NVIM_CURRENT_LINE=" .. (ctx.current_line or ""):gsub("\n", "\\n"),
  }

  if ctx.visual_selection then
    table.insert(lines, "CMDK_NVIM_VISUAL_SELECTION=" .. ctx.visual_selection:gsub("\n", "\\n"))
  end

  if ctx.lsp_diagnostics then
    table.insert(lines, "CMDK_NVIM_LSP_DIAGNOSTICS=" .. ctx.lsp_diagnostics:gsub("\n", "\\n"))
  end

  -- Write buffer content to a separate file
  if ctx.buffer_content then
    local content_file = tmpfile .. ".content"
    local f = io.open(content_file, "w")
    if f then
      f:write(ctx.buffer_content)
      f:close()
      table.insert(lines, "CMDK_NVIM_BUFFER_FILE=" .. content_file)
    end
  end

  local f = io.open(tmpfile, "w")
  if f then
    f:write(table.concat(lines, "\n"))
    f:close()
  end

  return tmpfile
end

-- Check if a string contains special key notation
local function contains_special_keys(str)
  return str:match("<[A-Za-z%-]+>") ~= nil
end

-- Convert special key notation to Neovim's internal format
local function convert_special_keys(str)
  local key_map = {
    ["<Esc>"] = "<Esc>",
    ["<Enter>"] = "<CR>",
    ["<CR>"] = "<CR>",
    ["<Tab>"] = "<Tab>",
    ["<BS>"] = "<BS>",
    ["<Del>"] = "<Del>",
    ["<Up>"] = "<Up>",
    ["<Down>"] = "<Down>",
    ["<Left>"] = "<Left>",
    ["<Right>"] = "<Right>",
    ["<Space>"] = "<Space>",
  }

  local result = str

  -- Convert known keys
  for from, to in pairs(key_map) do
    result = result:gsub(vim.pesc(from), to)
  end

  -- Convert Ctrl combinations: <C-x> stays as <C-x>
  -- Convert Alt combinations: <M-x> or <A-x> -> <M-x>
  result = result:gsub("<A%-([a-zA-Z])>", "<M-%1>")

  return result
end

-- Execute special keys using feedkeys
local function execute_special_keys(str)
  local converted = convert_special_keys(str)
  local keys = vim.api.nvim_replace_termcodes(converted, true, false, true)
  vim.api.nvim_feedkeys(keys, "n", false)
end

-- Handle the result from cmdk-rs
local function handle_result(action, result)
  if not result or result == "" then
    return
  end

  -- First, return to original window if valid
  if state.original_win and vim.api.nvim_win_is_valid(state.original_win) then
    vim.api.nvim_set_current_win(state.original_win)
  end

  -- Check if original buffer is valid and modifiable
  local buf_valid = state.original_buf and vim.api.nvim_buf_is_valid(state.original_buf)
  local buf_modifiable = buf_valid and vim.api.nvim_get_option_value("modifiable", { buf = state.original_buf })
  local buf_type = buf_valid and vim.api.nvim_get_option_value("buftype", { buf = state.original_buf }) or ""

  -- Terminal buffers and other special buffers can't be modified
  if buf_type == "terminal" or buf_type == "nofile" or buf_type == "prompt" then
    buf_modifiable = false
  end

  -- Check if result contains special keys
  local has_special_keys = contains_special_keys(result)

  if action == "insert" then
    if buf_modifiable then
      vim.api.nvim_set_current_buf(state.original_buf)
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line = cursor[1] - 1
      vim.api.nvim_buf_set_lines(state.original_buf, line, line, false, vim.split(result, "\n"))
      vim.notify("Inserted " .. #vim.split(result, "\n") .. " line(s)", vim.log.levels.INFO)
    else
      -- Fall back to clipboard if buffer not modifiable
      vim.fn.setreg("+", result)
      vim.fn.setreg('"', result)
      vim.notify("Buffer not modifiable - copied to clipboard instead", vim.log.levels.WARN)
    end
  elseif action == "replace" then
    if buf_modifiable then
      vim.api.nvim_set_current_buf(state.original_buf)
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line = cursor[1] - 1
      vim.api.nvim_buf_set_lines(state.original_buf, line, line + 1, false, vim.split(result, "\n"))
      vim.notify("Replaced line with " .. #vim.split(result, "\n") .. " line(s)", vim.log.levels.INFO)
    else
      -- Fall back to clipboard if buffer not modifiable
      vim.fn.setreg("+", result)
      vim.fn.setreg('"', result)
      vim.notify("Buffer not modifiable - copied to clipboard instead", vim.log.levels.WARN)
    end
  elseif action == "copy" then
    vim.fn.setreg("+", result)
    vim.fn.setreg('"', result)
    vim.notify("Copied to clipboard", vim.log.levels.INFO)
  elseif action == "run" then
    -- Check if result contains special keys
    if has_special_keys then
      -- Execute as keystrokes
      execute_special_keys(result)
      vim.notify("Executed key sequence", vim.log.levels.INFO)
    else
      -- Run as vim command
      local ok, err = pcall(vim.cmd, result)
      if not ok then
        vim.notify("Failed to run command: " .. err, vim.log.levels.ERROR)
      end
    end
  end
end

-- Close the floating window
local function close_float()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end

  -- Clean up temp files
  if state.result_file then
    vim.fn.delete(state.result_file)
    vim.fn.delete(state.result_file .. ".content")
  end

  state.buf = nil
  state.win = nil
  state.result_file = nil
end

-- Read result from temp file
local function read_result_file()
  if not state.result_file then
    return nil, nil
  end

  local result_path = state.result_file .. ".result"
  local action_path = state.result_file .. ".action"

  local result = nil
  local action = nil

  local f = io.open(result_path, "r")
  if f then
    result = f:read("*a")
    f:close()
    vim.fn.delete(result_path)
  end

  f = io.open(action_path, "r")
  if f then
    action = f:read("*a"):gsub("%s+", "")
    f:close()
    vim.fn.delete(action_path)
  end

  return action, result
end

-- Main function to open Command K
function M.open(opts)
  opts = opts or {}

  -- Find binary
  local binary = find_binary()
  if not binary then
    vim.notify("cmdk-rs binary not found. Please build it or set binary_path in config.", vim.log.levels.ERROR)
    return
  end

  -- Save original buffer/window
  state.original_buf = vim.api.nvim_get_current_buf()
  state.original_win = vim.api.nvim_get_current_win()

  -- Capture visual selection if in visual mode
  if opts.visual then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
    if #lines > 0 then
      -- Adjust for partial line selection
      if #lines == 1 then
        lines[1] = lines[1]:sub(start_pos[3], end_pos[3])
      else
        lines[1] = lines[1]:sub(start_pos[3])
        lines[#lines] = lines[#lines]:sub(1, end_pos[3])
      end
      state.visual_selection = table.concat(lines, "\n")
    end
  else
    state.visual_selection = nil
  end

  -- Gather context
  local ctx = gather_nvim_context()

  -- Write context to temp file
  state.result_file = write_context_file(ctx)

  -- Create floating window
  state.buf, state.win = create_float_win()

  -- Build command
  local cmd = string.format("%s --nvim %s", binary, state.result_file)

  -- Open terminal in the floating window
  vim.fn.termopen(cmd, {
    on_exit = function(_, exit_code, _)
      -- Read result
      local action, result = read_result_file()

      -- Close float and handle result
      vim.schedule(function()
        close_float()

        -- Handle result (this also returns to original window)
        if action and result then
          handle_result(action, result)
        else
          -- If no action, just return to original window
          if state.original_win and vim.api.nvim_win_is_valid(state.original_win) then
            vim.api.nvim_set_current_win(state.original_win)
          end
        end
      end)
    end,
  })

  -- Enter insert mode for the terminal
  vim.cmd("startinsert")
end

-- Quick query without TUI
function M.query(prompt)
  local binary = find_binary()
  if not binary then
    vim.notify("cmdk-rs binary not found", vim.log.levels.ERROR)
    return
  end

  -- Gather context
  local ctx = gather_nvim_context()
  local ctx_file = write_context_file(ctx)

  -- Run query
  local cmd = string.format("%s --nvim %s -q %s", binary, ctx_file, vim.fn.shellescape(prompt))
  local result = vim.fn.system(cmd)

  -- Clean up
  vim.fn.delete(ctx_file)
  vim.fn.delete(ctx_file .. ".content")

  return result:gsub("%s+$", "")
end

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Create user commands
  vim.api.nvim_create_user_command("CmdK", function()
    M.open()
  end, { desc = "Open Command K" })

  vim.api.nvim_create_user_command("CmdKQuery", function(cmd_opts)
    local result = M.query(cmd_opts.args)
    if result then
      print(result)
    end
  end, { nargs = "+", desc = "Quick Command K query" })

  -- Set up keymaps
  if M.config.keymap then
    vim.keymap.set("n", M.config.keymap, function()
      M.open()
    end, { desc = "Open Command K" })

    vim.keymap.set("v", M.config.keymap, function()
      -- Exit visual mode first
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      -- Open with visual selection
      vim.schedule(function()
        M.open({ visual = true })
      end)
    end, { desc = "Open Command K with selection" })
  end
end

return M
