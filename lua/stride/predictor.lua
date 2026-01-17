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
local ContextModule = require("stride.context")
local Treesitter = require("stride.treesitter")

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

---Find all occurrences of text in buffer, excluding comments and strings
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

      local row = line_num - 1 -- 0-indexed for treesitter
      local col = col_start - 1 -- 0-indexed for treesitter

      -- Skip occurrences inside comments or strings
      if Treesitter.is_inside_comment_or_string(buf, row, col) then
        Log.debug("predictor: skipping occurrence in comment/string at line %d col %d", line_num, col_start)
      else
        table.insert(occurrences, {
          line = line_num,
          col_start = col_start - 1, -- 0-indexed
          col_end = col_end, -- exclusive
          line_text = line, -- store full line for insert detection
        })
      end
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
local SYSTEM_PROMPT = [[Predict the user's next edit based on their recent changes and cursor position.

Context is provided in XML tags for clarity:
- <RecentChanges> shows the user's recent edits in diff format
- <ContainingFunction> shows the function being edited (when detected)
- <Context> shows numbered lines around cursor with │ marking position
- <ProjectRules> contains project-specific guidelines (when available)
- <Cursor> shows exact cursor position

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
<RecentChanges>test.lua:10 typing</RecentChanges>
<Context>10: local config│ = {
20: print(configTest1)</Context>
Analysis: User changed "configTest1" to "config" on line 10. Line 20 still has old value.
Prediction: {"action": "replace", "find": "configTest1", "replace": "config"}

Add property (insert):
<RecentChanges>Added "age: int"</RecentChanges>
<ContainingFunction name="User">class User:
    id: int
    name: str
    age: int│</ContainingFunction>
<Context>65: User(id=1, name=name, email=email)</Context>
Analysis: User added "age" field. Constructor call needs the argument.
Prediction: {"action": "insert", "anchor": "email=email", "position": "after", "insert": ", age=0"}

No prediction needed:
<RecentChanges>edits on line 10</RecentChanges>
<Context>All occurrences already updated</Context>
Prediction: {"action": null}
]]

---Build structured prompt using XML tags
---@param ctx Stride.PredictionContext
---@param changes_text string
---@return string
local function _build_structured_prompt(ctx, changes_text)
  local parts = {}

  -- Recent changes
  table.insert(parts, "<RecentChanges>")
  table.insert(parts, changes_text)
  table.insert(parts, "</RecentChanges>")
  table.insert(parts, "")

  -- Containing function (if detected)
  if ctx.containing_function then
    local fn = ctx.containing_function
    local name_attr = fn.name and string.format(' name="%s"', fn.name) or ""
    local lines_attr = string.format(' lines="%d-%d"', fn.range.start.row, fn.range.end_.row)
    table.insert(parts, string.format("<ContainingFunction%s%s>", name_attr, lines_attr))
    table.insert(parts, fn.text)
    table.insert(parts, "</ContainingFunction>")
    table.insert(parts, "")
  end

  -- Buffer context
  local total_lines = vim.api.nvim_buf_line_count(ctx.buf)
  local context_lines = Config.options.context_lines or 30
  local small_threshold = Config.options.small_file_threshold or 200

  local start_line, end_line
  if total_lines <= small_threshold then
    start_line = 1
    end_line = total_lines
  else
    local before = math.floor(context_lines * 0.3)
    local after = context_lines - before
    start_line = math.max(1, ctx.cursor.row - before)
    end_line = math.min(total_lines, ctx.cursor.row + after)
  end

  local buffer_context = ctx:build_prompt_context(start_line, end_line)
  table.insert(parts, string.format('<Context file="%s" lines="%d-%d">', ctx.file_path, start_line, end_line))
  table.insert(parts, buffer_context)
  table.insert(parts, "</Context>")
  table.insert(parts, "")

  -- Project rules (if available)
  if ctx.agent_context then
    table.insert(parts, "<ProjectRules>")
    table.insert(parts, ctx.agent_context)
    table.insert(parts, "</ProjectRules>")
    table.insert(parts, "")
  end

  -- Cursor position
  table.insert(parts, string.format('<Cursor line="%d" col="%d" />', ctx.cursor.row, ctx.cursor.col))
  table.insert(parts, "")
  table.insert(parts, "Predict the most likely next edit the user will make.")

  return table.concat(parts, "\n")
end

---Fetch next-edit prediction from LLM
---@param buf number Buffer handle
---@param cursor_pos Stride.CursorPos
---@param callback fun(suggestion: Stride.RemoteSuggestion|nil)
function M.fetch_next_edit(buf, cursor_pos, callback)
  M.cancel()

  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("predictor: buffer %d no longer valid", buf)
    callback(nil)
    return
  end

  if not Config.options.api_key then
    Log.error("predictor: CEREBRAS_API_KEY not set")
    callback(nil)
    return
  end

  -- Build context using new Context module
  local ctx = ContextModule.Context.from_current_buffer()

  -- Get recent changes for current file only
  local changes_text = History.get_changes_for_prompt(Config.options.token_budget, ctx.file_path)
  if changes_text == "(no recent changes)" then
    Log.debug("predictor: no recent changes to analyze")
    callback(nil)
    return
  end

  M._request_id = M._request_id + 1
  local current_request_id = M._request_id
  local start_time = vim.loop.hrtime()

  -- Build structured prompt with XML tags
  local user_prompt = _build_structured_prompt(ctx, changes_text)

  local messages = {
    { role = "system", content = SYSTEM_PROMPT },
    { role = "user", content = user_prompt },
  }

  local payload = {
    model = Config.options.model,
    messages = messages,
    temperature = 0,
    max_tokens = 512,
    reasoning_effort = "low",
  }

  Log.debug("===== PREDICTOR REQUEST =====")
  Log.debug("request_id=%d", current_request_id)
  Log.debug("cursor: line=%d col=%d", ctx.cursor.row, ctx.cursor.col)
  Log.debug("context: %s", ctx.file_path)
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
