local M = {}

local Config = require("stride.config")
local Log = require("stride.log")
local Transport = require("stride.transport")

---Channel name for completion requests
local CHANNEL = "completion"

---Cancel any in-flight request
function M.cancel()
  Transport.cancel(CHANNEL)
end

---Truncate text to last N lines
---@param text string
---@param max_lines number
---@return string
local function _truncate_end(text, max_lines)
  local lines = vim.split(text, "\n")
  if #lines <= max_lines then
    return text
  end
  local start_idx = #lines - max_lines + 1
  local truncated = {}
  for i = start_idx, #lines do
    table.insert(truncated, lines[i])
  end
  return table.concat(truncated, "\n")
end

---Truncate text to first N lines
---@param text string
---@param max_lines number
---@return string
local function _truncate_start(text, max_lines)
  local lines = vim.split(text, "\n")
  if #lines <= max_lines then
    return text
  end
  local truncated = {}
  for i = 1, max_lines do
    table.insert(truncated, lines[i])
  end
  return table.concat(truncated, "\n")
end

---Check if response is echoing the context
---@param response string
---@param prefix string
---@param suffix string
---@return boolean
local function _is_echo_response(response, prefix, suffix)
  -- Check if response contains last 30 chars of prefix
  if #prefix >= 30 then
    local prefix_tail = prefix:sub(-30)
    if response:find(prefix_tail, 1, true) then
      return true
    end
  end

  -- Check if response contains first 30 chars of suffix
  if #suffix >= 30 then
    local suffix_head = suffix:sub(1, 30)
    if response:find(suffix_head, 1, true) then
      return true
    end
  end

  return false
end

local SYSTEM_PROMPT = [[You are a code completion engine. Predict what the user will type next.

Rules:
- Output ONLY the characters to insert at cursor position
- Complete the current statement or expression, not entire blocks
- If a comment describes intent (e.g., "// log the id"), output code that fulfills it
- When cursor is mid-identifier, complete that identifier first
- Prefer variables, functions, and types visible in the surrounding code
- Match the naming conventions and style of the existing code
- Do NOT output code that already exists after the cursor
- Do NOT include markdown, code fences, or explanations
- Output empty string if no meaningful completion]]

---Process raw LLM output into a renderable completion
---@param content string Raw model output
---@param context Stride.Context
---@param row number 0-indexed cursor row
---@return string|nil Cleaned completion, or nil if rejected
local function _postprocess(content, context, row)
  -- Strip markdown code fences if present
  local cleaned = content
  cleaned = cleaned:gsub("^%s*```[%w]*%s*\n?", "")
  cleaned = cleaned:gsub("\n?%s*```%s*$", "")
  if cleaned ~= content then
    Log.debug("client: stripped markdown fences")
    content = cleaned
  end

  -- Strip leading/trailing whitespace
  content = content:gsub("^%s+", ""):gsub("%s+$", "")

  if content == "" then
    return nil
  end

  -- Comment-to-code: if cursor is at end of full-line comment and
  -- suggestion is code (not comment continuation), prepend newline with indent
  local Treesitter = require("stride.treesitter")
  if Treesitter.is_full_line_comment(context.buf, row) then
    local current_line = vim.api.nvim_buf_get_lines(context.buf, row, row + 1, false)[1] or ""
    local indent = current_line:match("^(%s*)") or ""

    local is_comment_continuation = content:match("^//")
      or content:match("^#")
      or content:match("^%-%-")
      or content:match("^/%*")
      or content:match("^%*")

    if not is_comment_continuation then
      content = "\n" .. indent .. content
      Log.debug("client: comment-to-code, prepended newline with indent '%s'", indent)
    end
  end

  -- Echo detection: reject if response contains context
  if _is_echo_response(content, context.prefix, context.suffix) then
    Log.debug("client: REJECTED echo response")
    return nil
  end

  return content
end

---Fetch prediction from the LLM
---@param context Stride.Context
---@param callback fun(text: string, row: number, col: number, buf: number)
function M.fetch_prediction(context, callback)
  -- Truncate context for the prompt
  local prompt_prefix = _truncate_end(context.prefix, 30)
  local prompt_suffix = _truncate_start(context.suffix, 15)

  local agent_section = ""
  if context.agent_context then
    agent_section = string.format("<AgentContext>\n%s\n</AgentContext>\n\n", context.agent_context)
    Log.debug("client: including agent_context (%d chars)", #context.agent_context)
  end

  local user_prompt = string.format(
    [[%sLanguage: %s

<code_before_cursor>
%s
</code_before_cursor>

<code_after_cursor>
%s
</code_after_cursor>]],
    agent_section,
    context.filetype,
    prompt_prefix,
    prompt_suffix
  )

  local payload = {
    model = Config.options.model,
    messages = {
      { role = "system", content = SYSTEM_PROMPT },
      { role = "user", content = user_prompt },
    },
    temperature = 0,
    max_tokens = 128,
    stop = { "<|eot_id|>", "<|end_of_text|>" },
    reasoning_effort = "low",
  }

  Log.debug("===== COMPLETION REQUEST =====")
  Log.debug("context: buf=%d row=%d col=%d ft=%s", context.buf, context.row, context.col, context.filetype)
  Log.debug("prompt_prefix (%d chars):\n%s", #prompt_prefix, prompt_prefix)
  Log.debug("prompt_suffix (%d chars):\n%s", #prompt_suffix, prompt_suffix)

  local request_buf = context.buf
  local request_row = context.row
  local request_col = context.col

  Transport.request({
    channel = CHANNEL,
    payload = payload,
    on_result = function(content)
      -- STALE CHECK: Did cursor move or buffer change?
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf ~= request_buf then
        Log.debug("client: DISCARDED, buffer changed (was=%d now=%d)", request_buf, cur_buf)
        return
      end

      local cur = vim.api.nvim_win_get_cursor(0)
      local r, c = cur[1] - 1, cur[2]
      if request_row ~= r or request_col ~= c then
        Log.debug("client: DISCARDED, cursor moved (was=%d,%d now=%d,%d)", request_row, request_col, r, c)
        return
      end

      Log.debug("client: raw completion:\n%s", content)

      local cleaned = _postprocess(content, context, r)
      if not cleaned then
        return
      end

      Log.debug("client: final content: %s", cleaned)
      callback(cleaned, r, c, request_buf)
    end,
  })
end

return M
