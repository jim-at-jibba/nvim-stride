---@class Stride.RemoteSuggestion
---@field line number 1-indexed target line
---@field original string Text to replace (the "find" text) - for replace action
---@field new string Replacement text - for replace action
---@field col_start number 0-indexed column start
---@field col_end number 0-indexed column end
---@field is_remote boolean Always true for remote suggestions
---@field action "replace"|"insert" Action type (default: "replace")
---@field anchor? string Anchor text for insertion (insert action only)
---@field position? "after"|"before" Insert position relative to anchor (insert action only)
---@field insert? string Text to insert (insert action only)

---@class Stride.CursorPos
---@field line number 1-indexed line
---@field col number 0-indexed column

---@class Stride.Predictor
local M = {}

local Config = require("stride.config")
local History = require("stride.history")
local Log = require("stride.log")
local curl = require("plenary.curl")

---@type table|nil Current active job handle
M._active_job = nil

---@type number Request ID to detect stale callbacks
M._request_id = 0

---Cancel any in-flight prediction request
function M.cancel()
  if M._active_job then
    Log.debug("predictor.cancel: invalidating request id=%d", M._request_id)
    M._request_id = M._request_id + 1
    M._active_job = nil
  end
end

---Get buffer context centered around cursor position
---@param buf number Buffer handle
---@param cursor_pos Stride.CursorPos Cursor position {line, col}
---@return string context_text, number start_line, number end_line
local function _get_buffer_context(buf, cursor_pos)
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local context_lines = Config.options.context_lines or 30
  local small_threshold = Config.options.small_file_threshold or 200

  local start_line, end_line

  -- Small file: send everything
  if total_lines <= small_threshold then
    start_line = 1
    end_line = total_lines
  else
    -- Center around cursor: 30% before, 70% after
    local before = math.floor(context_lines * 0.3)
    local after = context_lines - before

    start_line = math.max(1, cursor_pos.line - before)
    end_line = math.min(total_lines, cursor_pos.line + after)
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

  -- Add line numbers and cursor marker
  local numbered = {}
  for i, line in ipairs(lines) do
    local line_num = start_line + i - 1
    local display_line = line

    -- Mark cursor position with │
    if line_num == cursor_pos.line then
      local col = math.min(cursor_pos.col, #line)
      display_line = line:sub(1, col) .. "│" .. line:sub(col + 1)
    end

    table.insert(numbered, string.format("%d: %s", line_num, display_line))
  end

  return table.concat(numbered, "\n"), start_line, end_line
end

---Get relative path for current buffer
---@param buf number Buffer handle
---@return string
local function _get_relative_path(buf)
  local full_path = vim.api.nvim_buf_get_name(buf)
  if full_path == "" then
    return "[buffer]"
  end
  local cwd = vim.fn.getcwd()
  if full_path:sub(1, #cwd) == cwd then
    return full_path:sub(#cwd + 2)
  end
  return full_path
end

---Find all occurrences of text in buffer
---@param buf number Buffer handle
---@param find_text string Text to find
---@return {line: number, col_start: number, col_end: number, line_text: string}[]
local function _find_all_occurrences(buf, find_text)
  local occurrences = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for line_num, line in ipairs(lines) do
    local start_pos = 1
    while true do
      local col_start, col_end = line:find(find_text, start_pos, true)
      if not col_start then
        break
      end
      table.insert(occurrences, {
        line = line_num,
        col_start = col_start - 1, -- 0-indexed
        col_end = col_end, -- exclusive
        line_text = line, -- store full line for insert detection
      })
      start_pos = col_start + 1
    end
  end

  return occurrences
end

---Check if insert text already exists adjacent to anchor
---@param occ {line: number, col_start: number, col_end: number, line_text: string}
---@param insert_text string Text that would be inserted
---@param position "after"|"before" Insert position
---@return boolean true if already inserted
local function _already_inserted(occ, insert_text, position)
  local line = occ.line_text
  if not line then
    return false
  end

  -- Normalize insert text (strip leading/trailing whitespace for comparison)
  local normalized_insert = insert_text:match("^%s*(.-)%s*$")
  if not normalized_insert or normalized_insert == "" then
    return false
  end

  if position == "after" then
    -- Check if text after anchor contains the insert text
    local after_anchor = line:sub(occ.col_end + 1)
    -- Check immediate vicinity (within reasonable range)
    local check_range = after_anchor:sub(1, #insert_text + 10)
    if check_range:find(normalized_insert, 1, true) then
      return true
    end
  else
    -- Check if text before anchor contains the insert text
    local before_anchor = line:sub(1, occ.col_start)
    -- Check immediate vicinity
    local start_pos = math.max(1, #before_anchor - #insert_text - 10)
    local check_range = before_anchor:sub(start_pos)
    if check_range:find(normalized_insert, 1, true) then
      return true
    end
  end

  return false
end

---Select best match near cursor, excluding the cursor line (where user just edited)
---@param occurrences {line: number, col_start: number, col_end: number}[]
---@param cursor_pos Stride.CursorPos
---@return {line: number, col_start: number, col_end: number}|nil
local function _select_best_match(occurrences, cursor_pos)
  if #occurrences == 0 then
    return nil
  end

  -- Filter out occurrences on cursor line (user just edited there)
  local remote_occurrences = {}
  for _, occ in ipairs(occurrences) do
    if occ.line ~= cursor_pos.line then
      table.insert(remote_occurrences, occ)
    end
  end

  -- If all occurrences are on cursor line, no remote suggestion
  if #remote_occurrences == 0 then
    Log.debug("predictor: all %d occurrences on cursor line, skipping", #occurrences)
    return nil
  end

  if #remote_occurrences == 1 then
    return remote_occurrences[1]
  end

  -- Priority: after cursor > before cursor
  -- Within same priority: closest to cursor wins
  local best = nil
  local best_distance = math.huge

  for _, occ in ipairs(remote_occurrences) do
    local distance = math.abs(occ.line - cursor_pos.line)

    -- Prefer matches after cursor over before
    if occ.line > cursor_pos.line then
      distance = distance * 0.9 -- Slight preference for after
    end

    if distance < best_distance then
      best = occ
      best_distance = distance
    end
  end

  return best
end

---Validate LLM response (supports both replace and insert actions)
---@param response table Parsed JSON response
---@param buf number Buffer handle
---@param cursor_pos Stride.CursorPos
---@return Stride.RemoteSuggestion|nil
local function _validate_response(response, buf, cursor_pos)
  -- Determine action type with backward compatibility
  local action = response.action
  if action == vim.NIL then
    action = nil
  end

  -- Backward compat: if no action field but find/replace present, treat as replace
  if not action and response.find and response.find ~= vim.NIL then
    action = "replace"
  end

  -- Check for null/no suggestion
  if not action then
    Log.debug("predictor: LLM returned no suggestion (action=null)")
    return nil
  end

  if action == "replace" then
    -- REPLACE action: find text and replace it
    if not response.find or response.find == vim.NIL then
      Log.debug("predictor: replace action missing 'find' field")
      return nil
    end
    if not response.replace then
      Log.debug("predictor: replace action missing 'replace' field")
      return nil
    end

    -- Remove cursor marker if present
    local find_text = response.find:gsub("│", "")
    local replace_text = response.replace:gsub("│", "")

    -- Find all occurrences
    local occurrences = _find_all_occurrences(buf, find_text)

    if #occurrences == 0 then
      Log.debug("predictor: find text '%s' not found in buffer", find_text)
      return nil
    end

    -- Select best match near cursor
    local best = _select_best_match(occurrences, cursor_pos)
    if not best then
      return nil
    end

    Log.debug("predictor: replace action - found %d occurrences, selected line %d", #occurrences, best.line)

    return {
      line = best.line,
      original = find_text,
      new = replace_text,
      col_start = best.col_start,
      col_end = best.col_end,
      is_remote = true,
      action = "replace",
    }
  elseif action == "insert" then
    -- INSERT action: find anchor and insert text relative to it
    if not response.anchor or response.anchor == vim.NIL then
      Log.debug("predictor: insert action missing 'anchor' field")
      return nil
    end
    if not response.insert or response.insert == vim.NIL then
      Log.debug("predictor: insert action missing 'insert' field")
      return nil
    end

    local position = response.position
    if position ~= "after" and position ~= "before" then
      position = "after" -- Default to after
    end

    -- Remove cursor marker if present
    local anchor_text = response.anchor:gsub("│", "")
    local insert_text = response.insert:gsub("│", "")

    -- Find all occurrences of anchor
    local occurrences = _find_all_occurrences(buf, anchor_text)

    if #occurrences == 0 then
      Log.debug("predictor: anchor text '%s' not found in buffer", anchor_text)
      return nil
    end

    -- Filter out occurrences where insert text already exists
    local pending_occurrences = {}
    for _, occ in ipairs(occurrences) do
      if not _already_inserted(occ, insert_text, position) then
        table.insert(pending_occurrences, occ)
      else
        Log.debug("predictor: skipping line %d - insert text already present", occ.line)
      end
    end

    if #pending_occurrences == 0 then
      Log.debug("predictor: all %d occurrences already have insert text", #occurrences)
      return nil
    end

    -- Select best match near cursor from remaining occurrences
    local best = _select_best_match(pending_occurrences, cursor_pos)
    if not best then
      return nil
    end

    Log.debug(
      "predictor: insert action - anchor found at line %d, position=%s (%d/%d pending)",
      best.line,
      position,
      #pending_occurrences,
      #occurrences
    )

    -- For insert action, col_start/col_end mark the insertion point
    local insert_col
    if position == "after" then
      insert_col = best.col_end -- Insert after anchor
    else
      insert_col = best.col_start -- Insert before anchor
    end

    return {
      line = best.line,
      original = anchor_text, -- Store anchor for reference
      new = insert_text, -- The text to insert
      col_start = insert_col, -- Insertion point
      col_end = insert_col, -- Same as col_start (no text to replace)
      is_remote = true,
      action = "insert",
      anchor = anchor_text,
      position = position,
      insert = insert_text,
    }
  else
    Log.debug("predictor: unknown action type '%s'", tostring(action))
    return nil
  end
end

---System prompt for general next-edit prediction
local SYSTEM_PROMPT = [[Predict the user's next edit based on their recent changes and cursor position (marked by │).

Rules:
- Return ONLY valid JSON, no markdown
- Two action types supported:
  1. Replace: {"action": "replace", "find": "text_to_find", "replace": "replacement_text"}
  2. Insert: {"action": "insert", "anchor": "text_to_find", "position": "after"|"before", "insert": "text_to_insert"}
- Remove │ from all text fields
- The "find" or "anchor" text MUST be a complete identifier, word, or expression - never a partial match
- The "find" or "anchor" text must exist EXACTLY in the current context (not on the cursor line)
- If no prediction is possible: {"action": null}
- Predict the NEXT edit the user will make, not the edit they just made

IMPORTANT - When to use each action:
- Use "replace" when existing text needs to change (e.g., rename variable)
- Use "insert" when NEW text needs to be added (e.g., new parameter, new property)

IMPORTANT - Infer the original value:
- Recent changes may show incremental keystrokes, not the full edit
- Look at the cursor line to see the NEW value after editing
- Find OTHER occurrences in the context that still have the OLD value
- The "find" should match those old occurrences exactly

Examples:

Variable rename (replace):
Recent changes: typing on line 10
Current context line 10: local config│ = {
Context line 20: print(configTest1)
Analysis: User changed "configTest1" to "config" on line 10. Line 20 still has old value.
Prediction: {"action": "replace", "find": "configTest1", "replace": "config"}

Add property to dataclass (insert):
Recent changes: added "age: int" on line 58
Current context line 58: age: int│
Context line 65: User(id=1, name=name, email=email)
Analysis: User added new "age" field to dataclass. Constructor call needs age parameter.
Prediction: {"action": "insert", "anchor": "email=email", "position": "after", "insert": ", age=0"}

Add function parameter (insert):
Recent changes: added "timeout: int" parameter on line 5
Current context line 5: def fetch(url: str, timeout: int│):
Context line 20: result = fetch("https://api.example.com")
Analysis: User added timeout parameter. Call site needs the argument.
Prediction: {"action": "insert", "anchor": "\"https://api.example.com\"", "position": "after", "insert": ", timeout=30"}

No prediction needed:
Recent changes: edits on line 10
Current context shows all occurrences are already updated
Prediction: {"action": null}
]]

---Fetch next-edit prediction from LLM
---@param buf number Buffer handle
---@param cursor_pos Stride.CursorPos
---@param callback fun(suggestion: Stride.RemoteSuggestion|nil)
function M.fetch_next_edit(buf, cursor_pos, callback)
  M.cancel()

  if not Config.options.api_key then
    Log.error("predictor: CEREBRAS_API_KEY not set")
    callback(nil)
    return
  end

  -- Get recent changes for current file only
  local file_path = _get_relative_path(buf)
  local changes_text = History.get_changes_for_prompt(Config.options.token_budget, file_path)
  if changes_text == "(no recent changes)" then
    Log.debug("predictor: no recent changes to analyze")
    callback(nil)
    return
  end

  M._request_id = M._request_id + 1
  local current_request_id = M._request_id
  local start_time = vim.loop.hrtime()

  -- Get buffer context centered on cursor
  local buffer_context, start_line, end_line = _get_buffer_context(buf, cursor_pos)

  local user_prompt = string.format(
    [[Recent changes:
%s

Current context (│ marks cursor position):
%s:%d:%d
%s

Predict the most likely next edit the user will make.]],
    changes_text,
    file_path,
    start_line,
    end_line,
    buffer_context
  )

  local messages = {
    { role = "system", content = SYSTEM_PROMPT },
    { role = "user", content = user_prompt },
  }

  local payload = {
    model = Config.options.model,
    messages = messages,
    temperature = 0,
    max_tokens = 256,
    reasoning_effort = "low",
  }

  Log.debug("===== PREDICTOR REQUEST =====")
  Log.debug("request_id=%d", current_request_id)
  Log.debug("cursor: line=%d col=%d", cursor_pos.line, cursor_pos.col)
  Log.debug("context: %s lines %d-%d", file_path, start_line, end_line)
  Log.debug("user_prompt:\n%s", user_prompt)

  M._active_job = curl.post(Config.options.endpoint, {
    body = vim.fn.json_encode(payload),
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. Config.options.api_key,
    },
    callback = vim.schedule_wrap(function(out)
      local elapsed_ms = (vim.loop.hrtime() - start_time) / 1e6

      Log.debug("===== PREDICTOR RESPONSE =====")
      Log.debug("request_id=%d elapsed=%.0fms", current_request_id, elapsed_ms)

      -- Check if request was cancelled
      if current_request_id ~= M._request_id then
        Log.debug("predictor: request cancelled")
        return
      end

      M._active_job = nil

      if not out or out.status >= 400 then
        Log.debug("predictor: API error status=%s", tostring(out and out.status))
        callback(nil)
        return
      end

      Log.debug("predictor: raw response: %s", out.body or "(empty)")

      local ok, decoded = pcall(vim.fn.json_decode, out.body)
      if not ok then
        Log.debug("predictor: failed to decode API response")
        callback(nil)
        return
      end

      if not decoded.choices or not decoded.choices[1] then
        Log.debug("predictor: no choices in response")
        callback(nil)
        return
      end

      local content = decoded.choices[1].message and decoded.choices[1].message.content or ""
      Log.debug("predictor: LLM content: %s", content)

      -- Strip markdown code fences if present
      content = content:gsub("^%s*```json%s*\n?", "")
      content = content:gsub("^%s*```%s*\n?", "")
      content = content:gsub("\n?%s*```%s*$", "")
      content = content:gsub("^%s+", ""):gsub("%s+$", "")

      -- Parse JSON response
      local json_ok, json_response = pcall(vim.fn.json_decode, content)
      if not json_ok then
        Log.debug("predictor: failed to parse LLM JSON: %s", content)
        callback(nil)
        return
      end

      -- Validate and create suggestion
      local suggestion = _validate_response(json_response, buf, cursor_pos)
      if suggestion then
        Log.debug(
          "predictor: valid suggestion for line %d: '%s' → '%s'",
          suggestion.line,
          suggestion.original,
          suggestion.new
        )
      end

      callback(suggestion)
    end),
  })

  Log.debug("predictor: request dispatched")
end

return M
