local M = {}

local Config = require("stride.config")
local Utils = require("stride.utils")
local Client = require("stride.client")
local Ui = require("stride.ui")
local Log = require("stride.log")
local History = require("stride.history")
local Predictor = require("stride.predictor")

---Check if current filetype is disabled
---@return boolean
local function _is_disabled()
  local ft = vim.bo.filetype
  for _, disabled_ft in ipairs(Config.options.disabled_filetypes or {}) do
    if ft == disabled_ft then
      return true
    end
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

---Trigger V2 refactor prediction based on recent edits
---@param buf number Buffer handle
local function _trigger_refactor_prediction(buf)
  if not _mode_has_refactor() then
    return
  end

  local edits = History.compute_diff(buf)
  if #edits == 0 then
    Log.debug("refactor: no edits detected, skipping prediction")
    return
  end

  Log.debug("refactor: %d edits detected, fetching next-edit prediction", #edits)

  Predictor.fetch_next_edit(edits, buf, function(suggestion)
    if not suggestion then
      Log.debug("refactor: no suggestion returned")
      return
    end

    if Config.options.show_remote then
      Ui.render_remote(suggestion, buf)
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
  Log.debug("disabled_filetypes=%s", vim.inspect(Config.options.disabled_filetypes))
  Log.debug("mode=%s", Config.options.mode)
  Log.debug("show_remote=%s", tostring(Config.options.show_remote))

  local augroup = vim.api.nvim_create_augroup("StrideGroup", { clear = true })

  -- V2: Take snapshot on InsertEnter for history tracking
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = augroup,
    callback = function()
      if _is_disabled() then
        return
      end
      if _mode_has_refactor() then
        local buf = vim.api.nvim_get_current_buf()
        History.take_snapshot(buf)
        Log.debug("InsertEnter: snapshot taken for buf %d", buf)
      end
    end,
  })

  -- Trigger prediction on text change (debounced)
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function()
      if _is_disabled() then
        Log.debug("TextChangedI: filetype disabled, skipping")
        return
      end
      Log.debug("TextChangedI: triggered, scheduling prediction")
      Ui.clear()
      Client.cancel()
      Predictor.cancel()

      local buf = vim.api.nvim_get_current_buf()

      Utils.debounce(Config.options.debounce_ms, function()
        if _is_disabled() then
          return
        end

        -- V1: Completion mode
        if _mode_has_completion() then
          Log.debug("debounce complete, fetching V1 completion")
          local ctx = Utils.get_context(Config.options.context_lines)
          Client.fetch_prediction(ctx, Ui.render)
        end

        -- V2: Refactor mode
        if _mode_has_refactor() then
          Log.debug("debounce complete, fetching V2 refactor prediction")
          _trigger_refactor_prediction(buf)
        end
      end)
    end,
  })

  -- Clear on cursor move or mode change
  vim.api.nvim_create_autocmd({ "CursorMovedI", "ModeChanged" }, {
    group = augroup,
    callback = function()
      Ui.clear()
      Client.cancel()
      Predictor.cancel()
    end,
  })

  -- V2: Clear history on InsertLeave
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function()
      Ui.clear()
      Client.cancel()
      Predictor.cancel()
      History.clear()
      Log.debug("InsertLeave: history cleared")
    end,
  })

  -- Tab keymap: accept suggestion or fallback to normal Tab
  vim.keymap.set("i", Config.options.accept_keymap, function()
    return M.accept()
  end, { expr = true, silent = true })

  Log.debug("setup complete, keymap=%s, debounce=%dms, mode=%s", Config.options.accept_keymap, Config.options.debounce_ms, Config.options.mode)
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
    Log.debug("accept: remote suggestion at line %d", s.target_line)

    local target_line = s.target_line
    local col_start = s.col_start
    local col_end = s.col_end
    local new_text = s.new

    Ui.clear()

    vim.schedule(function()
      -- Apply the replacement
      vim.api.nvim_buf_set_text(buf, target_line - 1, col_start, target_line - 1, col_end, { new_text })

      -- Jump cursor to the target line
      vim.api.nvim_win_set_cursor(0, { target_line, col_start })

      Log.debug("accept: applied remote edit and jumped to line %d", target_line)

      -- Auto-trigger next prediction after accepting (chain edits)
      if _mode_has_refactor() then
        vim.defer_fn(function()
          _trigger_refactor_prediction(buf)
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
