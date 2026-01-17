local M = {}

local Config = require("stride.config")
local Log = require("stride.log")
local curl = require("plenary.curl")

---@type {[1]: number, [2]: number}|nil Current request cursor position for stale check
M.active_request_cursor = nil

---@type table|nil Current active job handle
M.active_job = nil

---@type number Request ID to detect stale callbacks
M._request_id = 0

---@type string|nil Last prefix sent (for echo detection)
M._last_prefix = nil

---Cancel any in-flight request
function M.cancel()
  if M.active_job then
    Log.debug("cancel: invalidating request id=%d", M._request_id)
    M._request_id = M._request_id + 1 -- Invalidate current request
    M.active_job = nil
  end
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

---Internal fetch with retry logic
---@param context Stride.Context
---@param callback fun(text: string, row: number, col: number, buf: number)
---@param attempt number|nil
local function _do_fetch(context, callback, attempt)
  attempt = attempt or 1
  local max_retries = 3
  local start_time = vim.loop.hrtime()

  if not Config.options.api_key then
    Log.error("CEREBRAS_API_KEY not set")
    vim.notify("stride.nvim: CEREBRAS_API_KEY not set", vim.log.levels.ERROR, { title = "stride.nvim" })
    return
  end

  M._request_id = M._request_id + 1
  local current_request_id = M._request_id
  M.active_request_cursor = { context.row, context.col }
  local request_buf = context.buf

  -- Truncate context for the prompt (keep full context for echo detection)
  local prompt_prefix = _truncate_end(context.prefix, 30)
  local prompt_suffix = _truncate_start(context.suffix, 15)

  -- Store for echo detection
  M._last_prefix = context.prefix

  local system_prompt = [[You are a code completion engine. Predict what the user will type next.

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

  local agent_section = ""
  if context.agent_context then
    agent_section = string.format("<AgentContext>\n%s\n</AgentContext>\n\n", context.agent_context)
    Log.debug("including agent_context (%d chars)", #context.agent_context)
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

  local messages = {
    { role = "system", content = system_prompt },
    { role = "user", content = user_prompt },
  }

  local payload = {
    model = Config.options.model,
    messages = messages,
    temperature = 0,
    max_tokens = 128,
    stop = { "<|eot_id|>", "<|end_of_text|>" },
    reasoning_effort = "low",
  }

  Log.debug("===== API REQUEST START =====")
  Log.debug("request_id=%d attempt=%d/%d", current_request_id, attempt, max_retries)
  Log.debug("endpoint=%s model=%s", Config.options.endpoint, Config.options.model)
  Log.debug("context: buf=%d row=%d col=%d ft=%s", context.buf, context.row, context.col, context.filetype)
  Log.debug("prompt_prefix (%d chars, truncated from %d):\n%s", #prompt_prefix, #context.prefix, prompt_prefix)
  Log.debug("prompt_suffix (%d chars, truncated from %d):\n%s", #prompt_suffix, #context.suffix, prompt_suffix)
  Log.debug("payload: temp=%.1f max_tokens=%d", payload.temperature, payload.max_tokens)

  local body = vim.fn.json_encode(payload)

  M.active_job = curl.post(Config.options.endpoint, {
    body = body,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. Config.options.api_key,
    },
    callback = vim.schedule_wrap(function(out)
      local elapsed_ms = (vim.loop.hrtime() - start_time) / 1e6

      Log.debug("===== API RESPONSE =====")
      Log.debug("request_id=%d elapsed=%.0fms", current_request_id, elapsed_ms)

      -- Check if this request was cancelled
      if current_request_id ~= M._request_id then
        Log.debug("DISCARDED: request cancelled (current_id=%d, this_id=%d)", M._request_id, current_request_id)
        return
      end

      M.active_job = nil

      if not out then
        Log.debug("ERROR: no response object (network failure?)")
      else
        Log.debug("status=%d body_len=%d", out.status or -1, #(out.body or ""))
      end

      -- Network/server error (5xx) - retry with exponential backoff
      if not out or out.status >= 500 then
        Log.debug(
          "SERVER ERROR: status=%s, will retry=%s",
          tostring(out and out.status),
          tostring(attempt < max_retries)
        )
        if out and out.body then
          Log.debug("error body: %s", out.body)
        end
        if attempt < max_retries then
          local delay = 100 * attempt
          Log.debug("retrying in %dms", delay)
          vim.defer_fn(function()
            _do_fetch(context, callback, attempt + 1)
          end, delay)
        else
          Log.warn("API request failed after %d attempts", max_retries)
          vim.notify(
            "stride.nvim: API request failed after " .. max_retries .. " attempts",
            vim.log.levels.WARN,
            { title = "stride.nvim" }
          )
        end
        return
      end

      -- Client error (4xx) - don't retry
      if out.status >= 400 then
        Log.debug("CLIENT ERROR: status=%d", out.status)
        Log.debug("error body: %s", out.body or "(empty)")
        local msg = "stride.nvim: API error " .. out.status
        if out.status == 401 then
          msg = "stride.nvim: Invalid API key"
        end
        if out.status == 429 then
          msg = "stride.nvim: Rate limited"
        end
        vim.notify(msg, vim.log.levels.WARN, { title = "stride.nvim" })
        return
      end

      -- STALE CHECK: Did cursor move or buffer change?
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf ~= request_buf then
        Log.debug("DISCARDED: buffer changed (was=%d now=%d)", request_buf, cur_buf)
        return
      end

      local cur = vim.api.nvim_win_get_cursor(0)
      local r, c = cur[1] - 1, cur[2]
      if M.active_request_cursor[1] ~= r or M.active_request_cursor[2] ~= c then
        Log.debug(
          "DISCARDED: cursor moved (was=%d,%d now=%d,%d)",
          M.active_request_cursor[1],
          M.active_request_cursor[2],
          r,
          c
        )
        return
      end

      Log.debug("raw response body: %s", out.body or "(empty)")

      local ok, decoded = pcall(vim.fn.json_decode, out.body)
      if not ok then
        Log.debug("JSON PARSE ERROR: %s", tostring(decoded))
        return
      end

      if not decoded.choices or not decoded.choices[1] then
        Log.debug("INVALID RESPONSE: no choices array")
        Log.debug("decoded: %s", vim.inspect(decoded))
        return
      end

      local choice = decoded.choices[1]
      local content = choice.message and choice.message.content or ""
      local finish_reason = choice.finish_reason or "unknown"

      Log.debug("SUCCESS: finish_reason=%s content_len=%d", finish_reason, #content)
      Log.debug("raw completion text:\n%s", content)

      -- Strip markdown code fences if present
      local cleaned = content
      cleaned = cleaned:gsub("^%s*```[%w]*%s*\n?", "")
      cleaned = cleaned:gsub("\n?%s*```%s*$", "")

      if cleaned ~= content then
        Log.debug("stripped markdown fences, cleaned:\n%s", cleaned)
        content = cleaned
      end

      -- Strip leading/trailing whitespace
      content = content:gsub("^%s+", ""):gsub("%s+$", "")

      -- Echo detection: reject if response contains context
      if _is_echo_response(content, context.prefix, context.suffix) then
        Log.debug("REJECTED: response appears to echo context")
        return
      end

      if decoded.usage then
        Log.debug(
          "usage: prompt_tokens=%d completion_tokens=%d total=%d",
          decoded.usage.prompt_tokens or 0,
          decoded.usage.completion_tokens or 0,
          decoded.usage.total_tokens or 0
        )
      end

      Log.debug("===== CALLING UI RENDER =====")
      Log.debug("final content: %s", content)
      callback(content, r, c, request_buf)
    end),
  })

  Log.debug("request dispatched, job=%s", tostring(M.active_job))
end

---Fetch prediction from Cerebras API
---@param context Stride.Context
---@param callback fun(text: string, row: number, col: number, buf: number)
function M.fetch_prediction(context, callback)
  M.cancel() -- Cancel any in-flight request
  _do_fetch(context, callback)
end

return M
