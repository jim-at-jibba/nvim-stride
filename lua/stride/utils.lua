---@class Stride.Context
---@field prefix string Text before cursor
---@field suffix string Text after cursor
---@field row number 0-indexed row
---@field col number 0-indexed column
---@field buf number Buffer handle
---@field filetype string Buffer filetype

local M = {}

local Log = require("stride.log")

---@type uv_timer_t|nil
M.timer = nil

---@type uv_timer_t|nil
M.timer_normal = nil

---Helper to check if node type is a structural block
---@param node_type string
---@return boolean
local function _is_block_type(node_type)
  return node_type:match("function") or node_type:match("method") or node_type:match("class") or node_type:match("impl")
end

---Expand context boundaries to include full function/class definitions
---@param buf number Buffer handle
---@param start_line number Start line (0-indexed)
---@param end_line number End line (0-indexed)
---@return number, number Expanded start_line, end_line
local function _expand_context_via_treesitter(buf, start_line, end_line)
  local orig_start, orig_end = start_line, end_line
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    Log.debug("treesitter: no parser available")
    return start_line, end_line
  end

  local trees = parser:parse()
  if not trees or not trees[1] then
    Log.debug("treesitter: parse failed")
    return start_line, end_line
  end
  local root = trees[1]:root()

  -- Check top boundary - expand upward if we cut a block
  local top_node = root:named_descendant_for_range(start_line, 0, start_line, 0)
  while top_node do
    local node_type = top_node:type()
    if _is_block_type(node_type) then
      local s_row, _, _, _ = top_node:range()
      if s_row < start_line then
        -- Limit expansion to 50 lines to avoid massive payloads
        if (start_line - s_row) <= 50 then
          start_line = s_row
        end
      end
      break
    end
    top_node = top_node:parent()
  end

  -- Check bottom boundary - expand downward if we cut a block
  local bottom_node = root:named_descendant_for_range(end_line, 0, end_line, 0)
  while bottom_node do
    local node_type = bottom_node:type()
    if _is_block_type(node_type) then
      local _, _, e_row, _ = bottom_node:range()
      if e_row > end_line then
        -- Limit expansion to 50 lines
        if (e_row - end_line) <= 50 then
          end_line = e_row
        end
      end
      break
    end
    bottom_node = bottom_node:parent()
  end

  if start_line ~= orig_start or end_line ~= orig_end then
    Log.debug("treesitter: expanded context %d-%d -> %d-%d", orig_start, orig_end, start_line, end_line)
  end

  return start_line, end_line
end

---Get context around cursor for LLM completion
---@param base_context_lines number|nil Lines before/after cursor (default from config)
---@return Stride.Context
function M.get_context(base_context_lines)
  local Config = require("stride.config")
  base_context_lines = base_context_lines or Config.options.context_lines or 60

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2] -- 0-indexed
  local total_lines = vim.api.nvim_buf_line_count(buf)

  -- Calculate naive boundaries
  local start_line = math.max(0, row - base_context_lines)
  local end_line = math.min(total_lines, row + base_context_lines)

  -- Smart expansion via Treesitter if enabled
  if Config.options.use_treesitter then
    start_line, end_line = _expand_context_via_treesitter(buf, start_line, end_line)
  end

  -- Extract text
  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)

  -- Split prefix/suffix at cursor
  local cursor_line_idx = row - start_line + 1
  local current_line = lines[cursor_line_idx] or ""

  local prefix_lines = {}
  local suffix_lines = {}

  for i, line in ipairs(lines) do
    if i < cursor_line_idx then
      table.insert(prefix_lines, line)
    elseif i > cursor_line_idx then
      table.insert(suffix_lines, line)
    end
  end

  local prefix_part = string.sub(current_line, 1, col)
  local suffix_part = string.sub(current_line, col + 1)

  table.insert(prefix_lines, prefix_part)
  table.insert(suffix_lines, 1, suffix_part)

  Log.debug(
    "get_context: row=%d col=%d prefix=%d chars suffix=%d chars ft=%s",
    row,
    col,
    #table.concat(prefix_lines, "\n"),
    #table.concat(suffix_lines, "\n"),
    vim.bo[buf].filetype
  )

  return {
    prefix = table.concat(prefix_lines, "\n"),
    suffix = table.concat(suffix_lines, "\n"),
    row = row,
    col = col,
    buf = buf,
    filetype = vim.bo[buf].filetype,
  }
end

---Debounce a callback
---@param ms number Delay in milliseconds
---@param callback function Function to call after delay
function M.debounce(ms, callback)
  if M.timer then
    Log.debug("debounce: cancelling previous timer")
    M.timer:stop()
    M.timer:close()
  end
  Log.debug("debounce: scheduling callback in %dms", ms)
  M.timer = vim.loop.new_timer()
  M.timer:start(ms, 0, vim.schedule_wrap(callback))
end

---Debounce for normal mode edits (separate timer)
---@param ms number Delay in milliseconds
---@param callback function Function to call after delay
function M.debounce_normal(ms, callback)
  if M.timer_normal then
    Log.debug("debounce_normal: cancelling previous timer")
    M.timer_normal:stop()
    M.timer_normal:close()
  end
  Log.debug("debounce_normal: scheduling callback in %dms", ms)
  M.timer_normal = vim.loop.new_timer()
  M.timer_normal:start(ms, 0, vim.schedule_wrap(callback))
end

return M
