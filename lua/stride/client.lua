local M = {}

local Config = require("stride.config")
local curl = require("plenary.curl")

---@type {[1]: number, [2]: number}|nil Current request cursor position for stale check
M.active_request_cursor = nil

---@type table|nil Current active job handle
M.active_job = nil

---Cancel any in-flight request
function M.cancel()
  if M.active_job then
    pcall(function()
      M.active_job:shutdown()
    end)
    M.active_job = nil
  end
end

---Internal fetch with retry logic
---@param context Stride.Context
---@param callback fun(text: string, row: number, col: number, buf: number)
---@param attempt number|nil
local function _do_fetch(context, callback, attempt)
  attempt = attempt or 1
  local max_retries = 3

  if not Config.options.api_key then
    vim.notify("stride.nvim: CEREBRAS_API_KEY not set", vim.log.levels.ERROR, { title = "stride.nvim" })
    return
  end

  M.active_request_cursor = { context.row, context.col }
  local request_buf = context.buf

  local messages = {
    {
      role = "system",
      content = "You are a precise code completion engine. Output ONLY the code that completes the current cursor position. Do not output markdown. Do not repeat the prefix. If no code is needed, output empty string.",
    },
    {
      role = "user",
      content = string.format(
        "Filetype: %s\n[PREFIX]\n%s\n[SUFFIX]\n%s\n[TASK]\nComplete the code starting exactly at the end of PREFIX.",
        context.filetype,
        context.prefix,
        context.suffix
      ),
    },
  }

  local payload = {
    model = Config.options.model,
    messages = messages,
    temperature = 0.1,
    max_tokens = 256,
    stop = { "<|eot_id|>", "<|end_of_text|>" },
  }

  M.active_job = curl.post(Config.options.endpoint, {
    body = vim.fn.json_encode(payload),
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. Config.options.api_key,
    },
    callback = vim.schedule_wrap(function(out)
      M.active_job = nil

      -- Network/server error (5xx) - retry with exponential backoff
      if not out or out.status >= 500 then
        if attempt < max_retries then
          vim.defer_fn(function()
            _do_fetch(context, callback, attempt + 1)
          end, 100 * attempt) -- 100ms, 200ms, 400ms
        else
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
        return
      end

      local cur = vim.api.nvim_win_get_cursor(0)
      local r, c = cur[1] - 1, cur[2]
      if M.active_request_cursor[1] ~= r or M.active_request_cursor[2] ~= c then
        return
      end

      local ok, decoded = pcall(vim.fn.json_decode, out.body)
      if ok and decoded.choices and decoded.choices[1] then
        callback(decoded.choices[1].message.content, r, c, request_buf)
      end
    end),
  })
end

---Fetch prediction from Cerebras API
---@param context Stride.Context
---@param callback fun(text: string, row: number, col: number, buf: number)
function M.fetch_prediction(context, callback)
  M.cancel() -- Cancel any in-flight request
  _do_fetch(context, callback)
end

return M
