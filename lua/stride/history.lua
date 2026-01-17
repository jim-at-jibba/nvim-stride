---@class Stride.TrackedChange
---@field file string Relative file path
---@field old_text string Text before change
---@field new_text string Text after change
---@field range {start_line: number, start_col: number, end_line: number, end_col: number}
---@field timestamp number os.time() when change occurred
---@field hrtime number High-resolution timestamp for grouping rapid changes

---@class Stride.History
---Incremental change tracking across buffers for V2 next-edit prediction
local M = {}

local Config = require("stride.config")
local Log = require("stride.log")
local Treesitter = require("stride.treesitter")

---@type Stride.TrackedChange[] Recent changes across all buffers
M._changes = {}

---@type table<number, boolean> Buffers we've attached to
M._attached_buffers = {}

---@type table<number, string[]> Previous buffer state for computing diffs
M._buffer_states = {}

---@type table<string, string[]> Snapshot of line(s) before rapid editing started (key: "file:line")
M._edit_snapshots = {}

---@type table<string, number> Last edit hrtime per line (key: "file:line")
M._last_edit_time = {}

---Threshold in nanoseconds to consider edits as part of same "session" (500ms)
local AGGREGATION_THRESHOLD_NS = 500 * 1000000

---Get relative path for a buffer
---@param buf number Buffer handle
---@return string
local function _get_relative_path(buf)
  local full_path = vim.api.nvim_buf_get_name(buf)
  if full_path == "" then
    return "[scratch:" .. buf .. "]"
  end
  local cwd = vim.fn.getcwd()
  if full_path:sub(1, #cwd) == cwd then
    return full_path:sub(#cwd + 2) -- +2 to skip trailing slash
  end
  return full_path
end

---Record a change with aggregation of rapid consecutive edits
---@param change Stride.TrackedChange
function M.record_change(change)
  local max_changes = Config.options.max_tracked_changes or 10
  local now = vim.loop.hrtime()
  change.hrtime = now

  local key = change.file .. ":" .. change.range.start_line

  -- Check if this is a continuation of rapid editing on the same line
  local last_time = M._last_edit_time[key]
  local is_continuation = last_time and (now - last_time) < AGGREGATION_THRESHOLD_NS

  if is_continuation then
    -- Find and update the existing change for this line instead of adding new
    for i = #M._changes, 1, -1 do
      local existing = M._changes[i]
      if existing.file == change.file and existing.range.start_line == change.range.start_line then
        -- Update the existing change with new text (keep original old_text from snapshot)
        existing.new_text = change.new_text
        existing.hrtime = now
        existing.range.end_col = math.max(existing.range.end_col, change.range.end_col)
        M._last_edit_time[key] = now

        Log.debug(
          "history.record_change: aggregated edit on %s line %d, old='%s' new='%s'",
          change.file,
          change.range.start_line,
          existing.old_text,
          existing.new_text
        )
        return
      end
    end
  end

  -- New edit session on this line - take snapshot and record
  M._edit_snapshots[key] = change.old_text
  M._last_edit_time[key] = now

  table.insert(M._changes, change)

  -- Trim to max
  while #M._changes > max_changes do
    table.remove(M._changes, 1)
  end

  Log.debug(
    "history.record_change: %s lines %d-%d, old='%s' new='%s', now tracking %d changes",
    change.file,
    change.range.start_line,
    change.range.end_line,
    change.old_text,
    change.new_text,
    #M._changes
  )
end

---Attach change tracking to a buffer
---@param buf number Buffer handle
function M.attach_buffer(buf)
  if M._attached_buffers[buf] then
    return -- Already attached
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Skip special buffers
  local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
  if buftype ~= "" then
    return
  end

  -- Skip unnamed/scratch buffers
  local bufname = vim.api.nvim_buf_get_name(buf)
  if bufname == "" then
    return
  end

  -- Store initial state
  M._buffer_states[buf] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local ok = vim.api.nvim_buf_attach(buf, false, {
    on_bytes = function(_, b, _, start_row, start_col, _, old_end_row, old_end_col, _, new_end_row, new_end_col)
      -- Skip if buffer state not tracked (shouldn't happen but be safe)
      if not M._buffer_states[b] then
        return
      end

      local old_lines = M._buffer_states[b]
      local new_lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)

      -- For single-line edits, track full line content for better context
      local is_single_line = old_end_row == 0 and new_end_row == 0
      local old_text, new_text

      if is_single_line then
        -- Track full line content (trimmed) for single-line changes
        local old_line = old_lines[start_row + 1] or ""
        local new_line = new_lines[start_row + 1] or ""
        old_text = old_line
        new_text = new_line
      else
        -- Multi-line changes: extract the specific changed region
        old_text =
          M._extract_text(old_lines, start_row, start_col, start_row + old_end_row, start_col + old_end_col)
        new_text =
          M._extract_text(new_lines, start_row, start_col, start_row + new_end_row, start_col + new_end_col)
      end

      -- Only record if there's actual text change
      if old_text ~= new_text then
        -- Skip changes inside comments or strings
        if Treesitter.is_inside_comment_or_string(b, start_row, start_col) then
          Log.debug("history: skipping change in comment/string at line %d", start_row + 1)
          M._buffer_states[b] = new_lines
          return
        end

        M.record_change({
          file = _get_relative_path(b),
          old_text = old_text,
          new_text = new_text,
          range = {
            start_line = start_row + 1, -- Convert to 1-indexed
            start_col = start_col,
            end_line = start_row + math.max(old_end_row, new_end_row) + 1,
            end_col = math.max(old_end_col, new_end_col),
          },
          timestamp = os.time(),
        })
      end

      -- Update stored state
      M._buffer_states[b] = new_lines
    end,

    on_detach = function(_, b)
      M._attached_buffers[b] = nil
      M._buffer_states[b] = nil
      Log.debug("history: detached from buffer %d", b)
    end,
  })

  if ok then
    M._attached_buffers[buf] = true
    Log.debug("history.attach_buffer: attached to buffer %d (%s)", buf, _get_relative_path(buf))
  end
end

---Extract text from lines given byte positions
---@param lines string[] Buffer lines
---@param start_row number 0-indexed start row
---@param start_col number 0-indexed start column (bytes)
---@param end_row number 0-indexed end row
---@param end_col number 0-indexed end column (bytes)
---@return string
function M._extract_text(lines, start_row, start_col, end_row, end_col)
  if #lines == 0 then
    return ""
  end

  -- Clamp to valid range
  start_row = math.max(0, math.min(start_row, #lines - 1))
  end_row = math.max(0, math.min(end_row, #lines - 1))

  if start_row == end_row then
    local line = lines[start_row + 1] or ""
    return line:sub(start_col + 1, end_col)
  end

  local result = {}
  for row = start_row, end_row do
    local line = lines[row + 1] or ""
    if row == start_row then
      table.insert(result, line:sub(start_col + 1))
    elseif row == end_row then
      table.insert(result, line:sub(1, end_col))
    else
      table.insert(result, line)
    end
  end

  return table.concat(result, "\n")
end

---Detach from a buffer
---@param buf number Buffer handle
function M.detach_buffer(buf)
  if M._attached_buffers[buf] then
    -- nvim_buf_attach returns a detach function, but we don't store it
    -- The on_detach callback will clean up
    M._attached_buffers[buf] = nil
    M._buffer_states[buf] = nil
  end
end

---Get all tracked changes
---@return Stride.TrackedChange[]
function M.get_changes()
  return M._changes
end

---Get changes formatted for prompt, respecting token budget
---@param token_budget? number Max tokens (default from config)
---@param file_filter? string Only include changes from this file
---@return string Formatted diff text
function M.get_changes_for_prompt(token_budget, file_filter)
  token_budget = token_budget or Config.options.token_budget or 1000

  local selected = {}
  local char_budget = token_budget * 3 -- ~3 chars per token
  local char_count = 0

  -- Start from most recent and work backwards
  for i = #M._changes, 1, -1 do
    local change = M._changes[i]

    -- Skip changes from other files if filter specified
    if not file_filter or change.file == file_filter then
      -- Format as unified diff style
      local diff_text = M._format_change_as_diff(change)
      local diff_chars = #diff_text

      if char_count + diff_chars > char_budget then
        break
      end

      table.insert(selected, 1, diff_text) -- Prepend to maintain order
      char_count = char_count + diff_chars
    end
  end

  if #selected == 0 then
    return "(no recent changes)"
  end

  return table.concat(selected, "\n")
end

---Format a single change as unified diff
---@param change Stride.TrackedChange
---@return string
function M._format_change_as_diff(change)
  local lines = {}

  table.insert(lines, string.format("%s:%d:%d", change.file, change.range.start_line, change.range.end_line))

  -- Format old text lines with -
  if change.old_text and change.old_text ~= "" then
    for _, line in ipairs(vim.split(change.old_text, "\n")) do
      table.insert(lines, "- " .. line)
    end
  end

  -- Format new text lines with +
  if change.new_text and change.new_text ~= "" then
    for _, line in ipairs(vim.split(change.new_text, "\n")) do
      table.insert(lines, "+ " .. line)
    end
  end

  return table.concat(lines, "\n")
end

---Clear all tracked changes
function M.clear()
  M._changes = {}
  M._edit_snapshots = {}
  M._last_edit_time = {}
  Log.debug("history.clear: cleared all tracked changes")
end

---Get count of tracked changes
---@return number
function M.get_change_count()
  return #M._changes
end

---Get changes for a specific file
---@param file string File path (relative)
---@return Stride.TrackedChange[]
function M.get_changes_for_file(file)
  local result = {}
  for _, change in ipairs(M._changes) do
    if change.file == file then
      table.insert(result, change)
    end
  end
  return result
end

return M
