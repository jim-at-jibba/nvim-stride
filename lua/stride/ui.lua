---@class Stride.Suggestion
---@field text string Full suggestion text
---@field row number 0-indexed row where suggestion starts
---@field col number 0-indexed column where suggestion starts
---@field lines string[] Split lines of suggestion
---@field buf number Buffer handle
---@field is_remote? boolean True if this is a remote (V2) suggestion
---@field target_line? number 1-indexed target line for remote suggestions
---@field original? string Original text to replace (remote only)
---@field new? string Replacement text (remote only)
---@field col_start? number 0-indexed column start (remote only)
---@field col_end? number 0-indexed column end (remote only)

local M = {}

local Log = require("stride.log")

local ns_id = vim.api.nvim_create_namespace("StrideGhost")
local ns_id_remote = vim.api.nvim_create_namespace("StrideRemote")

---Notify via fidget.nvim if available (optional integration)
---@param current number Current edit index
---@param total number Total pending edits
local function _notify_fidget(current, total)
  local ok, fidget = pcall(require, "fidget")
  if not ok then
    return
  end

  if total > 1 then
    fidget.notify(
      string.format("Edit %d/%d", current, total),
      vim.log.levels.INFO,
      { annote = "Tab to apply", key = "stride-edits", ttl = 1.5 }
    )
  elseif total == 1 then
    fidget.notify("1 edit suggested", vim.log.levels.INFO, { annote = "Tab to apply", key = "stride-edits", ttl = 1.5 })
  end
end

---@type Stride.Suggestion|nil
M.current_suggestion = nil

---@type number|nil
M.current_buf = nil

---@type number|nil
M.extmark_id = nil

---@type number|nil Highlight extmark for remote suggestions
M.remote_hl_id = nil

---@type number|nil Virtual text extmark for remote suggestions
M.remote_virt_id = nil

---@type boolean Whether Esc keymap is currently set
M._esc_mapped = false

---@type number|nil Buffer where Esc mapping was set
M._esc_buf = nil

---Setup Esc keymap to dismiss suggestion
---@param buf number Buffer handle
local function _setup_esc_mapping(buf)
  if M._esc_mapped then
    return
  end

  -- Set buffer-local Esc mapping in normal mode
  vim.keymap.set("n", "<Esc>", function()
    M.clear()
    -- Re-feed Esc so it still works for other things (like clearing search highlight)
    return "<Esc>"
  end, { buffer = buf, expr = true, silent = true, desc = "Dismiss Stride suggestion" })

  M._esc_mapped = true
  M._esc_buf = buf
  Log.debug("ui: Esc mapping set for buf %d", buf)
end

---Remove Esc keymap
local function _clear_esc_mapping()
  if not M._esc_mapped or not M._esc_buf then
    return
  end

  -- Remove the buffer-local mapping
  pcall(vim.keymap.del, "n", "<Esc>", { buffer = M._esc_buf })
  M._esc_mapped = false
  M._esc_buf = nil
  Log.debug("ui: Esc mapping cleared")
end

---Clear current ghost text
function M.clear()
  -- Clear local suggestion extmark
  if M.extmark_id and M.current_buf then
    Log.debug("ui.clear: removing extmark %d", M.extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id, M.extmark_id)
  end

  -- Clear remote suggestion extmarks
  if M.remote_hl_id and M.current_buf then
    Log.debug("ui.clear: removing remote highlight %d", M.remote_hl_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id_remote, M.remote_hl_id)
  end
  if M.remote_virt_id and M.current_buf then
    Log.debug("ui.clear: removing remote virt_text %d", M.remote_virt_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id_remote, M.remote_virt_id)
  end

  M.extmark_id = nil
  M.remote_hl_id = nil
  M.remote_virt_id = nil
  M.current_suggestion = nil
  M.current_buf = nil

  _clear_esc_mapping()
end

---Render ghost text at position
---@param text string|nil Suggestion text
---@param row number 0-indexed row
---@param col number 0-indexed column
---@param buf number Buffer handle
function M.render(text, row, col, buf)
  Log.debug("===== UI RENDER CALLED =====")
  Log.debug("row=%d col=%d buf=%d", row, col, buf)
  
  M.clear()
  if not text or text == "" then
    Log.debug("SKIP: empty/nil text received")
    return
  end

  Log.debug("text (%d chars): %s", #text, text)

  -- Verify buffer is still valid and current
  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("SKIP: buffer %d is invalid", buf)
    return
  end
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= buf then
    Log.debug("SKIP: buffer changed (request=%d current=%d)", buf, current_buf)
    return
  end

  -- Log current mode (but don't block - mode check happens earlier in flow)
  local mode = vim.api.nvim_get_mode().mode
  Log.debug("current mode=%s", mode)

  -- Log cursor position (but don't block - stale check happens in client)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cur_row, cur_col = cursor[1] - 1, cursor[2]
  Log.debug("cursor position: row=%d col=%d (expected row=%d col=%d)", cur_row, cur_col, row, col)

  local lines = vim.split(text, "\n")
  Log.debug("rendering %d lines as ghost text", #lines)

  -- Line 1: Inline after cursor
  local virt_text = { { lines[1], "Comment" } }

  -- Line 2+: Virtual lines below
  local virt_lines = {}
  if #lines > 1 then
    for i = 2, #lines do
      table.insert(virt_lines, { { lines[i], "Comment" } })
    end
  end

  local opts = {
    virt_text = virt_text,
    virt_text_pos = "inline",
    hl_mode = "combine",
  }
  if #virt_lines > 0 then
    opts.virt_lines = virt_lines
  end

  local ok, extmark = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, col, opts)
  if not ok then
    Log.debug("ERROR: failed to set extmark: %s", tostring(extmark))
    return
  end

  M.extmark_id = extmark
  M.current_buf = buf
  M.current_suggestion = {
    text = text,
    row = row,
    col = col,
    lines = lines,
    buf = buf,
  }
  Log.debug("SUCCESS: extmark_id=%d created", M.extmark_id)
end

---Get namespace ID (for testing)
---@return number
function M.get_ns_id()
  return ns_id
end

---Define highlight groups (called on setup and colorscheme change)
local function _define_highlights()
  -- StrideReplace: red foreground for text to be replaced
  vim.api.nvim_set_hl(0, "StrideReplace", { fg = "#ff6b6b", strikethrough = true })
  -- StrideRemoteSuggestion: green for replacement text
  vim.api.nvim_set_hl(0, "StrideRemoteSuggestion", { fg = "#50fa7b", italic = true })
  Log.debug("ui: highlight groups defined")
end

---Setup highlight groups for remote suggestions
function M.setup_highlights()
  _define_highlights()

  -- Reapply highlights when colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("StrideHighlights", { clear = true }),
    callback = _define_highlights,
  })
end

---Render a remote suggestion (V2)
---@param suggestion Stride.RemoteSuggestion
---@param buf number Buffer handle
---@param current? number Current edit index (1-based), for count display
---@param total? number Total pending edits, for count display
function M.render_remote(suggestion, buf, current, total)
  Log.debug("===== UI RENDER REMOTE =====")
  Log.debug("line=%d original='%s' new='%s'", suggestion.line, suggestion.original, suggestion.new)

  M.clear()

  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("SKIP: buffer %d is invalid", buf)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= buf then
    Log.debug("SKIP: buffer changed (request=%d current=%d)", buf, current_buf)
    return
  end

  local row = suggestion.line - 1 -- Convert to 0-indexed

  -- 1. Highlight the original text with StrideReplace
  local ok_hl, hl_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, suggestion.col_start, {
    end_col = suggestion.col_end,
    hl_group = "StrideReplace",
  })
  if ok_hl then
    M.remote_hl_id = hl_id
    Log.debug("remote highlight extmark=%d", hl_id)
  else
    Log.debug("ERROR: failed to set remote highlight: %s", tostring(hl_id))
  end

  -- 2. Add inline virtual text showing the replacement (right after original)
  -- Include count indicator if multiple edits pending
  local suffix = ""
  if total and total > 1 and current then
    suffix = string.format(" [%d/%d]", current, total)
  end

  local ok_virt, virt_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, suggestion.col_end, {
    virt_text = { { " → " .. suggestion.new .. suffix, "StrideRemoteSuggestion" } },
    virt_text_pos = "inline",
  })
  if ok_virt then
    M.remote_virt_id = virt_id
    Log.debug("remote virt_text extmark=%d", virt_id)
  else
    Log.debug("ERROR: failed to set remote virt_text: %s", tostring(virt_id))
  end

  M.current_buf = buf
  M.current_suggestion = {
    text = suggestion.new,
    row = row,
    col = suggestion.col_start,
    lines = { suggestion.new },
    buf = buf,
    is_remote = true,
    target_line = suggestion.line,
    original = suggestion.original,
    new = suggestion.new,
    col_start = suggestion.col_start,
    col_end = suggestion.col_end,
  }

  _setup_esc_mapping(buf)

  -- Notify via fidget if available
  if current and total then
    _notify_fidget(current, total)
  end

  Log.debug("SUCCESS: remote suggestion rendered for line %d", suggestion.line)
end

---Get remote namespace ID (for testing)
---@return number
function M.get_ns_id_remote()
  return ns_id_remote
end

return M
