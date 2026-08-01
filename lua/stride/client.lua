local M = {}

local Config = require("stride.config")
local Log = require("stride.log")
local Transport = require("stride.transport")

---Channel name for completion requests
local CHANNEL = "completion"

---Completion cache. Requests use temperature=0, so identical context yields
---an identical completion: caching is deterministic and safe.
---@type table<string, string> key -> cleaned completion
local _cache = {}
---@type string[] FIFO of cache keys for eviction
local _cache_keys = {}
local CACHE_MAX = 50

---@param context Stride.Context
---@return string
local function _cache_key(context)
  return vim.fn.sha256(context.filetype .. "\1" .. context.prefix .. "\1" .. context.suffix)
end

---@param key string
---@param content string
local function _cache_put(key, content)
  if _cache[key] == nil then
    table.insert(_cache_keys, key)
    if #_cache_keys > CACHE_MAX then
      local evicted = table.remove(_cache_keys, 1)
      _cache[evicted] = nil
    end
  end
  _cache[key] = content
end

---Clear the completion cache (for testing)
function M._clear_cache()
  _cache = {}
  _cache_keys = {}
end

---Cancel any in-flight request
function M.cancel()
  Transport.cancel(CHANNEL)
end

---Trim prefix to a char budget, cutting at a line boundary from the start
---@param text string
---@param max_chars number
---@return string
local function _cap_prefix(text, max_chars)
  if #text <= max_chars then
    return text
  end
  local trimmed = text:sub(-max_chars)
  -- Drop the (likely partial) first line
  local nl = trimmed:find("\n", 1, true)
  if nl then
    trimmed = trimmed:sub(nl + 1)
  end
  return trimmed
end

---Trim suffix to a char budget, cutting at a line boundary from the end
---@param text string
---@param max_chars number
---@return string
local function _cap_suffix(text, max_chars)
  if #text <= max_chars then
    return text
  end
  local trimmed = text:sub(1, max_chars)
  -- Drop the (likely partial) last line
  local last_nl
  for i = #trimmed, 1, -1 do
    if trimmed:sub(i, i) == "\n" then
      last_nl = i
      break
    end
  end
  if last_nl then
    trimmed = trimmed:sub(1, last_nl - 1)
  end
  return trimmed
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
  -- Cache hit: render immediately, no request
  local cache_key = _cache_key(context)
  local cached = _cache[cache_key]
  if cached then
    Log.debug("client: cache hit, skipping request")
    callback(cached, context.row, context.col, context.buf)
    return
  end

  -- Context is already windowed by utils.get_context (context_lines +
  -- treesitter expansion). Apply only a char-budget safety cap here so
  -- pathological files (minified JS, huge lines) can't blow up the prompt.
  -- Prefix gets 2/3 of the budget: what comes before the cursor matters most.
  local max_chars = Config.options.max_context_chars or 9000
  local prompt_prefix = _cap_prefix(context.prefix, math.floor(max_chars * 2 / 3))
  local prompt_suffix = _cap_suffix(context.suffix, math.floor(max_chars / 3))

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

      _cache_put(cache_key, cleaned)

      Log.debug("client: final content: %s", cleaned)
      callback(cleaned, r, c, request_buf)
    end,
  })
end

return M
