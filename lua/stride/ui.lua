---@class Stride.Suggestion
---@field text string Full suggestion text
---@field row number 0-indexed row where suggestion starts
---@field col number 0-indexed column where suggestion starts
---@field lines string[] Split lines of suggestion
---@field buf number Buffer handle

local M = {}

local Log = require("stride.log")

local ns_id = vim.api.nvim_create_namespace("StrideGhost")

---@type Stride.Suggestion|nil
M.current_suggestion = nil

---@type number|nil
M.current_buf = nil

---@type number|nil
M.extmark_id = nil

---Clear current ghost text
function M.clear()
  if M.extmark_id and M.current_buf then
    Log.debug("ui.clear: removing extmark %d", M.extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id, M.extmark_id)
  end
  M.extmark_id = nil
  M.current_suggestion = nil
  M.current_buf = nil
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

return M
