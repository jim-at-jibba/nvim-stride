---@class Stride.Suggestion
---@field text string Full suggestion text
---@field row number 0-indexed row where suggestion starts
---@field col number 0-indexed column where suggestion starts
---@field lines string[] Split lines of suggestion
---@field buf number Buffer handle

local M = {}

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
  M.clear()
  if not text or text == "" then
    return
  end

  -- Verify buffer is still valid and current
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.api.nvim_get_current_buf() ~= buf then
    return
  end

  local lines = vim.split(text, "\n")

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

  M.extmark_id = vim.api.nvim_buf_set_extmark(buf, ns_id, row, col, opts)
  M.current_buf = buf
  M.current_suggestion = {
    text = text,
    row = row,
    col = col,
    lines = lines,
    buf = buf,
  }
end

---Get namespace ID (for testing)
---@return number
function M.get_ns_id()
  return ns_id
end

return M
