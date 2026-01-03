local M = {}

---@type boolean Global enabled state
M.enabled = true

local Config = require("stride.config")
local Utils = require("stride.utils")
local Client = require("stride.client")
local Ui = require("stride.ui")
local Log = require("stride.log")
local History = require("stride.history")
local Predictor = require("stride.predictor")

---Check if filetype matches any disabled pattern
---@param ft string Filetype to check
---@param disabled table<string, boolean> Map of patterns to check against
---@return boolean
local function _matches_disabled(ft, disabled)
  if not disabled or ft == "" then
    return false
  end
  for pattern, enabled in pairs(disabled) do
    if enabled and ft:match("^" .. pattern .. "$") then
      return true
    end
  end
  return false
end

---Check if current filetype/buftype is disabled
---@return boolean
local function _is_disabled()
  if not M.enabled then
    return true
  end
  local ft = vim.bo.filetype
  local bt = vim.bo.buftype

  if _matches_disabled(ft, Config.options.disabled_filetypes) then
    return true
  end
  if _matches_disabled(bt, Config.options.disabled_buftypes) then
    return true
  end
  return false
end

---Check if mode includes completion (V1)
---@return boolean
local function _mode_has_completion()
  local mode = Config.options.mode or "completion"
  return mode == "completion" or mode == "both"
end

---Check if mode includes refactor (V2)
---@return boolean
local function _mode_has_refactor()
  local mode = Config.options.mode or "completion"
  return mode == "refactor" or mode == "both"
end

---Get current cursor position
---@return Stride.CursorPos
local function _get_cursor_pos()
  local pos = vim.api.nvim_win_get_cursor(0)
  return {
    line = pos[1], -- 1-indexed
    col = pos[2], -- 0-indexed
  }
end

---Check if current state is from undo/redo (not at tip of undo tree)
---@return boolean
local function _is_undo_redo()
  local tree = vim.fn.undotree()
  return tree.seq_cur ~= tree.seq_last
end

---Trigger V2 refactor prediction based on recent edits
---@param buf number Buffer handle
---@param cursor_pos Stride.CursorPos
local function _trigger_refactor_prediction(buf, cursor_pos)
  if not _mode_has_refactor() then
    return
  end

  local change_count = History.get_change_count()
  if change_count == 0 then
    Log.debug("refactor: no changes tracked, skipping prediction")
    return
  end

  Log.debug("refactor: %d changes tracked, fetching next-edit prediction", change_count)

  Predictor.fetch_next_edit(buf, cursor_pos, function(suggestion)
    if not suggestion then
      Log.debug("refactor: no suggestion returned")
      return
    end

    if Config.options.show_remote then
      Ui.render_remote(suggestion, buf, 1, 1)
    end
  end)
end

---Setup stride.nvim
---@param opts Stride.Config|nil
function M.setup(opts)
  -- Check dependencies
  if not pcall(require, "plenary") then
    error("stride.nvim requires plenary.nvim")
  end

  -- Optional warning for Treesitter
  if opts and opts.use_treesitter and not pcall(require, "nvim-treesitter") then
    vim.notify("stride.nvim: Treesitter enabled but nvim-treesitter not found. Using built-in.", vim.log.levels.WARN)
  end

  Config.setup(opts)

  -- Setup highlight groups for remote suggestions
  Ui.setup_highlights()

  Log.debug("===== STRIDE SETUP =====")
  Log.debug("debug=%s", tostring(Config.options.debug))
  Log.debug("endpoint=%s", Config.options.endpoint)
  Log.debug("model=%s", Config.options.model)
  Log.debug("debounce_ms=%d", Config.options.debounce_ms)
  Log.debug("context_lines=%d", Config.options.context_lines)
  Log.debug("use_treesitter=%s", tostring(Config.options.use_treesitter))
  Log.debug("accept_keymap=%s", Config.options.accept_keymap)
  Log.debug("api_key=%s", Config.options.api_key and "(set)" or "(NOT SET)")
  Log.debug("disabled_filetypes=%d patterns", vim.tbl_count(Config.options.disabled_filetypes or {}))
  Log.debug("disabled_buftypes=%d patterns", vim.tbl_count(Config.options.disabled_buftypes or {}))
  Log.debug("mode=%s", Config.options.mode)
  Log.debug("show_remote=%s", tostring(Config.options.show_remote))
  Log.debug("max_tracked_changes=%d", Config.options.max_tracked_changes or 10)
  Log.debug("token_budget=%d", Config.options.token_budget or 1000)
  Log.debug("small_file_threshold=%d", Config.options.small_file_threshold or 200)

  local augroup = vim.api.nvim_create_augroup("StrideGroup", { clear = true })

  -- V2: Attach change tracker to buffers
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      if _mode_has_refactor() then
        History.attach_buffer(args.buf)
      end
    end,
  })

  -- Also attach to current buffer on setup
  if _mode_has_refactor() then
    local current_buf = vim.api.nvim_get_current_buf()
    History.attach_buffer(current_buf)
  end

  -- Trigger prediction on text change (debounced) - V1 only during insert
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function()
      if _is_disabled() then
        Log.debug("TextChangedI: filetype disabled, skipping")
        return
      end

      -- Only V1 completion triggers during insert
      if not _mode_has_completion() then
        return
      end

      Log.debug("TextChangedI: triggered, scheduling V1 prediction")
      Ui.clear()
      Client.cancel()

      Utils.debounce(Config.options.debounce_ms, function()
        if _is_disabled() then
          return
        end

        Log.debug("debounce complete, fetching V1 completion")
        local ctx = Utils.get_context(Config.options.context_lines)
        Client.fetch_prediction(ctx, Ui.render)
      end)
    end,
  })

  -- Clear on cursor move (in insert mode)
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    callback = function()
      Ui.clear()
      Client.cancel()
    end,
  })

  -- V2: Trigger refactor prediction on InsertLeave (after debounce)
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
      -- Clear any V1 suggestions
      Ui.clear()
      Client.cancel()
      Predictor.cancel()

      if _is_disabled() then
        return
      end

      -- V2: Trigger prediction based on tracked changes
      if _mode_has_refactor() then
        local buf = vim.api.nvim_get_current_buf()
        local cursor_pos = _get_cursor_pos()

        Utils.debounce(Config.options.debounce_ms, function()
          _trigger_refactor_prediction(buf, cursor_pos)
        end)
      end
    end,
  })

  -- V2: Trigger refactor prediction on normal mode text changes (x, dd, etc.)
  vim.api.nvim_create_autocmd("TextChanged", {
    group = augroup,
    callback = function()
      if _is_disabled() then
        return
      end

      if not _mode_has_refactor() then
        return
      end

      -- Skip undo/redo operations
      if _is_undo_redo() then
        return
      end

      -- Clear stale prediction immediately
      Ui.clear()
      Predictor.cancel()

      local buf = vim.api.nvim_get_current_buf()
      local cursor_pos = _get_cursor_pos()

      Utils.debounce_normal(Config.options.debounce_normal_ms, function()
        _trigger_refactor_prediction(buf, cursor_pos)
      end)
    end,
  })

  -- Clear on mode change (e.g., leaving normal mode)
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    pattern = "*:n", -- Entering normal mode
    callback = function()
      -- Don't clear on InsertLeave->Normal, let the prediction show
      -- This is handled by the Esc keymap in UI
    end,
  })

  -- Tab keymap: accept suggestion or fallback to normal Tab
  vim.keymap.set("i", Config.options.accept_keymap, function()
    return M.accept()
  end, { expr = true, silent = true })

  -- Normal mode Tab: accept remote suggestion
  vim.keymap.set("n", Config.options.accept_keymap, function()
    return M.accept()
  end, { expr = true, silent = true })

  -- Create :StrideClear command
  vim.api.nvim_create_user_command("StrideClear", function()
    History.clear()
    Ui.clear()
    Predictor.cancel()
    Client.cancel()
    Log.debug(":StrideClear executed")
    vim.notify("Stride: cleared change history and suggestions", vim.log.levels.INFO)
  end, { desc = "Clear Stride change history and suggestions" })

  -- Create :StrideEnable command
  vim.api.nvim_create_user_command("StrideEnable", function()
    M.enabled = true
    Log.debug(":StrideEnable executed")
    vim.notify("Stride: enabled", vim.log.levels.INFO)
  end, { desc = "Enable Stride predictions" })

  -- Create :StrideDisable command
  vim.api.nvim_create_user_command("StrideDisable", function()
    M.enabled = false
    Ui.clear()
    Predictor.cancel()
    Client.cancel()
    Log.debug(":StrideDisable executed")
    vim.notify("Stride: disabled", vim.log.levels.INFO)
  end, { desc = "Disable Stride predictions" })

  -- Create :StrideStatus command for debugging
  vim.api.nvim_create_user_command("StrideStatus", function()
    local ft = vim.bo.filetype
    local bt = vim.bo.buftype
    local ft_disabled = _matches_disabled(ft, Config.options.disabled_filetypes)
    local bt_disabled = _matches_disabled(bt, Config.options.disabled_buftypes)
    local is_disabled = _is_disabled()

    local lines = {
      "Stride Status:",
      "  enabled: " .. tostring(M.enabled),
      "  filetype: '" .. ft .. "' (disabled: " .. tostring(ft_disabled) .. ")",
      "  buftype: '" .. bt .. "' (disabled: " .. tostring(bt_disabled) .. ")",
      "  overall disabled: " .. tostring(is_disabled),
      "  mode: " .. (Config.options.mode or "completion"),
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Show Stride status for current buffer" })

  Log.debug(
    "setup complete, keymap=%s, debounce=%dms, mode=%s",
    Config.options.accept_keymap,
    Config.options.debounce_ms,
    Config.options.mode
  )
end

---Accept current suggestion (V1 local or V2 remote)
---@return string Empty string if accepted, Tab key otherwise
function M.accept()
  local s = Ui.current_suggestion
  if not s or not s.text or s.text == "" then
    Log.debug("accept: no suggestion, fallback to Tab")
    return vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
  end

  -- Capture values before clearing
  local buf = s.buf or vim.api.nvim_get_current_buf()
  local is_remote = s.is_remote

  if is_remote then
    -- V2: Remote suggestion - jump and apply
    local action = s.action or "replace"
    Log.debug("accept: remote %s suggestion at line %d", action, s.target_line)

    local target_line = s.target_line
    local col_start = s.col_start
    local col_end = s.col_end

    Ui.clear()

    vim.schedule(function()
      if action == "insert" then
        -- INSERT action: insert text at the insertion point
        local insert_text = s.insert or s.new
        local insert_lines = vim.split(insert_text, "\n")

        -- For single-line insert, just insert at position
        if #insert_lines == 1 then
          vim.api.nvim_buf_set_text(buf, target_line - 1, col_start, target_line - 1, col_start, { insert_text })
        else
          -- Multi-line insert: first line at position, rest as new lines
          vim.api.nvim_buf_set_text(buf, target_line - 1, col_start, target_line - 1, col_start, { insert_lines[1] })
          if #insert_lines > 1 then
            local extra = { unpack(insert_lines, 2) }
            vim.api.nvim_buf_set_lines(buf, target_line, target_line, false, extra)
          end
        end

        -- Jump cursor to end of inserted text
        local final_line = target_line + #insert_lines - 1
        local final_col = (#insert_lines == 1) and (col_start + #insert_text) or #insert_lines[#insert_lines]
        vim.api.nvim_win_set_cursor(0, { final_line, final_col })

        Log.debug("accept: inserted text at line %d", target_line)
      else
        -- REPLACE action: replace existing text
        local new_text = s.new
        vim.api.nvim_buf_set_text(buf, target_line - 1, col_start, target_line - 1, col_end, { new_text })

        -- Jump cursor to the target line
        vim.api.nvim_win_set_cursor(0, { target_line, col_start })

        Log.debug("accept: applied replacement at line %d", target_line)
      end

      -- Auto-trigger next prediction after accepting (chain edits)
      if _mode_has_refactor() then
        local cursor_pos = _get_cursor_pos()
        vim.defer_fn(function()
          _trigger_refactor_prediction(buf, cursor_pos)
        end, 50) -- Small delay to let buffer update
      end
    end)
  else
    -- V1: Local suggestion - insert at cursor
    Log.debug("accept: inserting %d lines at row=%d col=%d", #s.lines, s.row, s.col)

    local r, c = s.row, s.col
    local lines = s.lines

    Ui.clear()

    vim.schedule(function()
      -- Insert first line at cursor position
      vim.api.nvim_buf_set_text(buf, r, c, r, c, { lines[1] })

      -- Insert remaining lines below
      if #lines > 1 then
        local extra = { unpack(lines, 2) }
        vim.api.nvim_buf_set_lines(buf, r + 1, r + 1, false, extra)
      end

      -- Move cursor to end of inserted text
      local last_len = #lines[#lines]
      local tr = r + #lines - 1
      local tc = (tr == r) and (c + last_len) or last_len
      vim.api.nvim_win_set_cursor(0, { tr + 1, tc })
    end)
  end

  return ""
end

return M
