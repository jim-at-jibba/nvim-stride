---@class Stride.RemoteSuggestion
---@field line number 1-indexed target line
---@field original string Text to replace (the "find" text)
---@field new string Replacement text
---@field col_start number 0-indexed column start
---@field col_end number 0-indexed column end
---@field is_remote boolean Always true for remote suggestions

---@class Stride.CursorPos
---@field line number 1-indexed line
---@field col number 0-indexed column

---@class Stride.Predictor
---Next-edit prediction module for V2 (magenta-style)
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
---@return {line: number, col_start: number, col_end: number}[]
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
      })
      start_pos = col_start + 1
    end
  end

  return occurrences
end

---Select best match near cursor
---@param occurrences {line: number, col_start: number, col_end: number}[]
---@param cursor_pos Stride.CursorPos
---@return {line: number, col_start: number, col_end: number}|nil
local function _select_best_match(occurrences, cursor_pos)
  if #occurrences == 0 then
    return nil
  end

  if #occurrences == 1 then
    return occurrences[1]
  end

  -- Priority: cursor line > after cursor > before cursor
  -- Within same priority: closest to cursor wins
  local best = nil
  local best_distance = math.huge

  for _, occ in ipairs(occurrences) do
    local distance = math.abs(occ.line - cursor_pos.line)

    -- Prefer matches after cursor over before
    if occ.line >= cursor_pos.line then
      distance = distance * 0.9 -- Slight preference for after
    end

    if distance < best_distance then
      best = occ
      best_distance = distance
    end
  end

  return best
end

---Validate LLM response (find/replace format)
---@param response table Parsed JSON response
---@param buf number Buffer handle
---@param cursor_pos Stride.CursorPos
---@return Stride.RemoteSuggestion|nil
local function _validate_response(response, buf, cursor_pos)
  -- Check for null/no suggestion
  if not response.find or response.find == vim.NIL then
    Log.debug("predictor: LLM returned no suggestion")
    return nil
  end

  if not response.replace then
    Log.debug("predictor: missing replace text")
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

  Log.debug("predictor: found %d occurrences, selected line %d", #occurrences, best.line)

  return {
    line = best.line,
    original = find_text,
    new = replace_text,
    col_start = best.col_start,
    col_end = best.col_end,
    is_remote = true,
  }
end

---System prompt for general next-edit prediction (magenta-style)
local SYSTEM_PROMPT = [[Predict the user's next edit based on their recent changes and cursor position (marked by │).

Rules:
- Return ONLY valid JSON, no markdown
- Format: {"find": "text_to_find", "replace": "replacement_text"}
- Remove │ from find and replace text
- The "find" text must exist in the current context
- If no prediction is possible: {"find": null, "replace": null}
- Predict any likely edit, not just renames

Examples:

Recent changes show function signature change:
- function myFunction(a: string, b: number) {
+ function myFunction({a, b}: {a: string, b: number}) {
Context has: myFunction("hello", 2)
Prediction: {"find": "myFunction(\"hello\", 2)", "replace": "myFunction({a: \"hello\", b: 2})"}

Recent changes show variable rename:
- const apple = "fruit"
+ const orange = "fruit"
Context has: console.log(apple)
Prediction: {"find": "apple", "replace": "orange"}

User typing console.log and cursor at console│
Prediction: {"find": "console\n", "replace": "console.log();\n"}
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

  -- Get recent changes
  local changes_text = History.get_changes_for_prompt(Config.options.token_budget)
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
  local file_path = _get_relative_path(buf)

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
