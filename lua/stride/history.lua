---@class Stride.EditDiff
---@field change_type "insert"|"delete"|"modification"
---@field line number 1-indexed line number
---@field original string|nil Original text (nil for insert)
---@field new string|nil New text (nil for delete)

---@class Stride.History
---Buffer snapshot and diff computation for V2 next-edit prediction
local M = {}

local Log = require("stride.log")

---@type string[]|nil Buffer lines snapshot taken on InsertEnter
M._snapshot = nil

---@type number|nil Buffer handle for current snapshot
M._snapshot_buf = nil

---@type Stride.EditDiff[] Sliding window of recent edits
M._edit_history = {}

---@type number Maximum edits to track in sliding window
M._max_history = 5

---Take a snapshot of buffer contents
---@param buf number Buffer handle
function M.take_snapshot(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("history.take_snapshot: invalid buffer %d", buf)
    return
  end

  M._snapshot = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  M._snapshot_buf = buf
  Log.debug("history.take_snapshot: captured %d lines from buf %d", #M._snapshot, buf)
end

---Clear snapshot and history (called on InsertLeave)
function M.clear()
  Log.debug("history.clear: clearing snapshot and history")
  M._snapshot = nil
  M._snapshot_buf = nil
  M._edit_history = {}
end

---Parse unified diff output into structured EditDiff objects
---@param diff_output string Output from vim.diff()
---@return Stride.EditDiff[]
local function _parse_diff(diff_output)
  local edits = {}

  if not diff_output or diff_output == "" then
    return edits
  end

  -- Parse unified diff format
  -- @@ -start,count +start,count @@
  -- Lines starting with - are deletions
  -- Lines starting with + are additions
  -- Lines starting with space are context

  local lines = vim.split(diff_output, "\n")
  local i = 1

  while i <= #lines do
    local line = lines[i]

    -- Match hunk header: @@ -old_start,old_count +new_start,new_count @@
    local old_start, old_count, new_start, new_count =
      line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

    if old_start then
      old_start = tonumber(old_start)
      old_count = tonumber(old_count) or 1
      new_start = tonumber(new_start)
      new_count = tonumber(new_count) or 1

      i = i + 1
      local old_lines = {}
      local new_lines = {}

      -- Collect lines in this hunk
      while i <= #lines and not lines[i]:match("^@@") do
        local hunk_line = lines[i]
        if hunk_line:sub(1, 1) == "-" then
          table.insert(old_lines, hunk_line:sub(2))
        elseif hunk_line:sub(1, 1) == "+" then
          table.insert(new_lines, hunk_line:sub(2))
        end
        -- Skip context lines (starting with space)
        i = i + 1
      end

      -- Determine change type and create EditDiff
      if #old_lines == 0 and #new_lines > 0 then
        -- Pure insertion
        for j, new_text in ipairs(new_lines) do
          table.insert(edits, {
            change_type = "insert",
            line = new_start + j - 1,
            original = nil,
            new = new_text,
          })
        end
      elseif #old_lines > 0 and #new_lines == 0 then
        -- Pure deletion
        for j, old_text in ipairs(old_lines) do
          table.insert(edits, {
            change_type = "delete",
            line = old_start + j - 1,
            original = old_text,
            new = nil,
          })
        end
      else
        -- Modification (paired old/new lines)
        local max_lines = math.max(#old_lines, #new_lines)
        for j = 1, max_lines do
          local old_text = old_lines[j]
          local new_text = new_lines[j]
          if old_text and new_text then
            table.insert(edits, {
              change_type = "modification",
              line = old_start + j - 1,
              original = old_text,
              new = new_text,
            })
          elseif old_text then
            table.insert(edits, {
              change_type = "delete",
              line = old_start + j - 1,
              original = old_text,
              new = nil,
            })
          elseif new_text then
            table.insert(edits, {
              change_type = "insert",
              line = new_start + j - 1,
              original = nil,
              new = new_text,
            })
          end
        end
      end
    else
      i = i + 1
    end
  end

  return edits
end

---Compute diff between snapshot and current buffer state
---@param buf number Buffer handle
---@return Stride.EditDiff[] Array of edit diffs
function M.compute_diff(buf)
  if not M._snapshot then
    Log.debug("history.compute_diff: no snapshot available")
    return {}
  end

  if M._snapshot_buf ~= buf then
    Log.debug("history.compute_diff: buffer mismatch (snapshot=%d, current=%d)", M._snapshot_buf or -1, buf)
    return {}
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("history.compute_diff: invalid buffer %d", buf)
    return {}
  end

  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local snapshot_text = table.concat(M._snapshot, "\n")
  local current_text = table.concat(current_lines, "\n")

  if snapshot_text == current_text then
    Log.debug("history.compute_diff: no changes detected")
    return {}
  end

  -- Use vim.diff for unified diff output
  local diff_output = vim.diff(snapshot_text, current_text, {
    result_type = "unified",
    ctxlen = 0, -- No context lines needed
  })

  Log.debug("history.compute_diff: raw diff output:\n%s", diff_output or "(nil)")

  local edits = _parse_diff(diff_output)
  Log.debug("history.compute_diff: parsed %d edits", #edits)

  -- Add to sliding window history
  for _, edit in ipairs(edits) do
    table.insert(M._edit_history, edit)
    -- Trim to max history size
    while #M._edit_history > M._max_history do
      table.remove(M._edit_history, 1)
    end
  end

  -- Update snapshot to current state for next diff
  M._snapshot = current_lines

  return edits
end

---Get recent edit history (sliding window)
---@return Stride.EditDiff[]
function M.get_history()
  return M._edit_history
end

---Get the most recent edit
---@return Stride.EditDiff|nil
function M.get_last_edit()
  if #M._edit_history == 0 then
    return nil
  end
  return M._edit_history[#M._edit_history]
end

return M
