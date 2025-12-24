---@class Stride.RemoteSuggestion
---@field line number 1-indexed target line
---@field original string Text to replace
---@field new string Replacement text
---@field col_start number 0-indexed column start
---@field col_end number 0-indexed column end
---@field is_remote boolean Always true for remote suggestions

---@class Stride.Predictor
---Next-edit prediction module for V2
local M = {}

local Config = require("stride.config")
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

---Format edit history for prompt
---@param edits Stride.EditDiff[]
---@return string
local function _format_edits(edits)
  local parts = {}
  for _, edit in ipairs(edits) do
    if edit.change_type == "modification" then
      table.insert(parts, string.format('Line %d: "%s" → "%s"', edit.line, edit.original, edit.new))
    elseif edit.change_type == "insert" then
      table.insert(parts, string.format('Line %d: inserted "%s"', edit.line, edit.new))
    elseif edit.change_type == "delete" then
      table.insert(parts, string.format('Line %d: deleted "%s"', edit.line, edit.original))
    end
  end
  return table.concat(parts, "\n")
end

---Get buffer context around edits
---@param buf number Buffer handle
---@param context_lines number Lines of context
---@return string
local function _get_buffer_context(buf, context_lines)
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local start_line = 0
  local end_line = math.min(total_lines, context_lines * 2)

  local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)

  -- Add line numbers for context
  local numbered = {}
  for i, line in ipairs(lines) do
    table.insert(numbered, string.format("%d: %s", start_line + i, line))
  end

  return table.concat(numbered, "\n")
end

---Validate LLM response
---@param response table Parsed JSON response
---@param buf number Buffer handle
---@param edited_lines table<number, boolean> Lines that were just edited
---@return Stride.RemoteSuggestion|nil
local function _validate_response(response, buf, edited_lines)
  -- Check for null/no suggestion
  if not response.line or response.line == vim.NIL then
    Log.debug("predictor: LLM returned no suggestion")
    return nil
  end

  local line = tonumber(response.line)
  if not line then
    Log.debug("predictor: invalid line number in response")
    return nil
  end

  -- Check line exists
  local total_lines = vim.api.nvim_buf_line_count(buf)
  if line < 1 or line > total_lines then
    Log.debug("predictor: line %d out of range (1-%d)", line, total_lines)
    return nil
  end

  -- Reject self-edit (same line user just edited)
  if edited_lines[line] then
    Log.debug("predictor: rejecting self-edit on line %d", line)
    return nil
  end

  -- Validate original and new text exist
  if not response.original or not response.new then
    Log.debug("predictor: missing original or new text")
    return nil
  end

  -- Validate original text exists on target line
  local line_content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  local col_start, col_end = line_content:find(response.original, 1, true)

  if not col_start then
    Log.debug("predictor: original text '%s' not found on line %d", response.original, line)
    return nil
  end

  return {
    line = line,
    original = response.original,
    new = response.new,
    col_start = col_start - 1, -- Convert to 0-indexed
    col_end = col_end, -- End is exclusive in nvim_buf_set_text
    is_remote = true,
  }
end

---Fetch next-edit prediction from LLM
---@param edits Stride.EditDiff[] Recent edits
---@param buf number Buffer handle
---@param callback fun(suggestion: Stride.RemoteSuggestion|nil)
function M.fetch_next_edit(edits, buf, callback)
  M.cancel()

  if #edits == 0 then
    Log.debug("predictor: no edits to analyze")
    callback(nil)
    return
  end

  if not Config.options.api_key then
    Log.error("predictor: CEREBRAS_API_KEY not set")
    callback(nil)
    return
  end

  M._request_id = M._request_id + 1
  local current_request_id = M._request_id
  local start_time = vim.loop.hrtime()

  -- Track which lines were just edited (for self-edit rejection)
  local edited_lines = {}
  for _, edit in ipairs(edits) do
    edited_lines[edit.line] = true
  end

  local edit_summary = _format_edits(edits)
  local buffer_context = _get_buffer_context(buf, Config.options.context_lines or 30)

  local system_prompt = [[You are a code refactoring assistant. Analyze recent edits and identify ONE other location that likely needs the same change.

Rules:
- Return ONLY valid JSON, no markdown or explanation
- If a related edit is needed: {"line": N, "original": "text to replace", "new": "replacement text"}
- If no edit is needed: {"line": null}
- Focus on variable renames, function calls, and related references
- Do NOT suggest edits on lines that were just changed
- Suggest only ONE edit at a time]]

  local user_prompt = string.format(
    [[Recent edits:
%s

File context:
%s

Analyze the edits above. Is there another location that needs a similar change?
Return JSON only.]],
    edit_summary,
    buffer_context
  )

  local messages = {
    { role = "system", content = system_prompt },
    { role = "user", content = user_prompt },
  }

  local payload = {
    model = Config.options.model,
    messages = messages,
    temperature = 0,
    max_tokens = 128,
  }

  Log.debug("===== PREDICTOR REQUEST =====")
  Log.debug("request_id=%d", current_request_id)
  Log.debug("edits:\n%s", edit_summary)
  Log.debug("context_lines=%d", #vim.split(buffer_context, "\n"))

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
      local suggestion = _validate_response(json_response, buf, edited_lines)
      if suggestion then
        Log.debug("predictor: valid suggestion for line %d: '%s' → '%s'",
          suggestion.line, suggestion.original, suggestion.new)
      end

      callback(suggestion)
    end),
  })

  Log.debug("predictor: request dispatched")
end

return M
