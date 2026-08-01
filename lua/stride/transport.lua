---@class Stride.TransportRequest
---@field channel string Cancellation scope ("completion", "predictor", ...)
---@field payload table Chat completion request body
---@field on_result fun(content: string, decoded: table) Called with message content on success
---@field on_error? fun(kind: "rate_limited"|"http"|"network"|"parse", status?: number) Called on failure

---@class Stride.Transport
---Single HTTP transport for all Stride LLM requests.
---Responsibilities:
--- - Real request cancellation (kills the curl process, saving tokens)
--- - Global 429 backoff honoring Retry-After
--- - Min-interval throttle across all channels (latest request wins)
--- - Retry with backoff on 5xx/network errors
--- - JSON encode/decode and choices extraction
local M = {}

local Config = require("stride.config")
local Log = require("stride.log")
local curl = require("plenary.curl")

---@class Stride.TransportChannel
---@field id number Monotonic request id for staleness detection
---@field job table|nil Active plenary Job
---@field timer uv_timer_t|nil Pending throttled dispatch

---@type table<string, Stride.TransportChannel>
M._channels = {}

---@type number ms timestamp (vim.loop.now) until which all requests are blocked
M._backoff_until = 0

---@type number ms timestamp of last dispatched request
M._last_dispatch = 0

---@type boolean Whether we've notified the user for the current backoff window
M._backoff_notified = false

local MAX_RETRIES = 3

---Get (or create) channel state
---@param name string
---@return Stride.TransportChannel
local function _channel(name)
  local ch = M._channels[name]
  if not ch then
    ch = { id = 0, job = nil, timer = nil }
    M._channels[name] = ch
  end
  return ch
end

---Stop the pending throttle timer for a channel
---@param ch Stride.TransportChannel
local function _stop_timer(ch)
  if ch.timer then
    ch.timer:stop()
    ch.timer:close()
    ch.timer = nil
  end
end

---Kill an in-flight curl job so no tokens are wasted server-side
---@param ch Stride.TransportChannel
local function _kill_job(ch)
  if ch.job then
    pcall(function()
      ch.job:shutdown(0, 9) -- SIGKILL the curl process
    end)
    ch.job = nil
  end
end

---Cancel any pending or in-flight request on a channel
---@param channel string
function M.cancel(channel)
  local ch = M._channels[channel]
  if not ch then
    return
  end
  if ch.job or ch.timer then
    Log.debug("transport.cancel: channel=%s id=%d", channel, ch.id)
  end
  ch.id = ch.id + 1 -- Invalidate callbacks
  _stop_timer(ch)
  _kill_job(ch)
end

---Parse a header value from plenary's array-of-strings headers
---@param headers string[]|nil
---@param name string Lowercase header name
---@return string|nil
local function _header(headers, name)
  if not headers then
    return nil
  end
  for _, line in ipairs(headers) do
    local k, v = line:match("^([%w%-]+):%s*(.*)$")
    if k and k:lower() == name then
      return v
    end
  end
  return nil
end

---Enter a rate-limit backoff window
---@param headers string[]|nil Response headers (for Retry-After)
local function _enter_backoff(headers)
  local retry_after = tonumber(_header(headers, "retry-after"))
  local cooldown_ms
  if retry_after then
    cooldown_ms = math.ceil(retry_after * 1000)
  else
    cooldown_ms = Config.options.rate_limit_cooldown_ms or 15000
  end

  M._backoff_until = vim.loop.now() + cooldown_ms

  if not M._backoff_notified then
    M._backoff_notified = true
    vim.notify(
      string.format("stride.nvim: rate limited, pausing requests for %ds", math.ceil(cooldown_ms / 1000)),
      vim.log.levels.WARN,
      { title = "stride.nvim" }
    )
  end
  Log.debug("transport: rate limited, backoff for %dms", cooldown_ms)
end

---Compute delay (ms) before the next request may be dispatched
---@return number
local function _dispatch_delay()
  local now = vim.loop.now()
  local delay = 0

  -- Global rate-limit backoff
  if M._backoff_until > now then
    delay = M._backoff_until - now
  end

  -- Min interval between any two requests
  local min_interval = Config.options.min_request_interval_ms or 500
  local since_last = now - M._last_dispatch
  if since_last < min_interval then
    delay = math.max(delay, min_interval - since_last)
  end

  return delay
end

---Dispatch the HTTP request (no throttling; caller handles that)
---@param req Stride.TransportRequest
---@param ch Stride.TransportChannel
---@param request_id number
---@param attempt number
local function _dispatch(req, ch, request_id, attempt)
  if not Config.options.api_key then
    Log.error("transport: API key not set")
    vim.notify("stride.nvim: CEREBRAS_API_KEY not set", vim.log.levels.ERROR, { title = "stride.nvim" })
    return
  end

  M._last_dispatch = vim.loop.now()
  local start_time = vim.loop.hrtime()

  Log.debug("transport: dispatch channel=%s id=%d attempt=%d/%d", req.channel, request_id, attempt, MAX_RETRIES)

  ch.job = curl.post(Config.options.endpoint, {
    body = vim.fn.json_encode(req.payload),
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = "Bearer " .. Config.options.api_key,
    },
    on_error = vim.schedule_wrap(function(err)
      -- Killed/cancelled curl also lands here; only act if still current
      if request_id ~= ch.id then
        return
      end
      ch.job = nil
      Log.debug("transport: curl error channel=%s: %s", req.channel, err.message or "?")
      if attempt < MAX_RETRIES then
        local delay = 500 * 2 ^ (attempt - 1)
        vim.defer_fn(function()
          if request_id == ch.id then
            _dispatch(req, ch, request_id, attempt + 1)
          end
        end, delay)
      elseif req.on_error then
        req.on_error("network")
      end
    end),
    callback = vim.schedule_wrap(function(out)
      local elapsed_ms = (vim.loop.hrtime() - start_time) / 1e6
      Log.debug("transport: response channel=%s id=%d status=%s elapsed=%.0fms", req.channel, request_id, tostring(out and out.status), elapsed_ms)

      if request_id ~= ch.id then
        Log.debug("transport: DISCARDED stale response (current=%d this=%d)", ch.id, request_id)
        return
      end
      ch.job = nil

      -- Rate limited: enter global backoff, do not retry
      if out and out.status == 429 then
        _enter_backoff(out.headers)
        if req.on_error then
          req.on_error("rate_limited", 429)
        end
        return
      end

      -- Server error: retry with exponential backoff
      if not out or out.status >= 500 then
        if out and out.body then
          Log.debug("transport: server error body: %s", out.body)
        end
        if attempt < MAX_RETRIES then
          local delay = 500 * 2 ^ (attempt - 1)
          Log.debug("transport: retrying in %dms", delay)
          vim.defer_fn(function()
            if request_id == ch.id then
              _dispatch(req, ch, request_id, attempt + 1)
            end
          end, delay)
        else
          Log.warn("transport: request failed after %d attempts", MAX_RETRIES)
          if req.on_error then
            req.on_error("http", out and out.status)
          end
        end
        return
      end

      -- Client error: don't retry
      if out.status >= 400 then
        Log.debug("transport: client error status=%d body=%s", out.status, out.body or "(empty)")
        if out.status == 401 then
          vim.notify("stride.nvim: Invalid API key", vim.log.levels.WARN, { title = "stride.nvim" })
        end
        if req.on_error then
          req.on_error("http", out.status)
        end
        return
      end

      -- Success: clear backoff-notified flag for the next window
      M._backoff_notified = false

      local ok, decoded = pcall(vim.fn.json_decode, out.body)
      if not ok or type(decoded) ~= "table" then
        Log.debug("transport: JSON parse error: %s", tostring(decoded))
        if req.on_error then
          req.on_error("parse")
        end
        return
      end

      local choice = decoded.choices and decoded.choices[1]
      if not choice then
        Log.debug("transport: no choices in response")
        if req.on_error then
          req.on_error("parse")
        end
        return
      end

      if decoded.usage then
        Log.debug(
          "transport: usage prompt=%d completion=%d total=%d",
          decoded.usage.prompt_tokens or 0,
          decoded.usage.completion_tokens or 0,
          decoded.usage.total_tokens or 0
        )
      end

      local content = choice.message and choice.message.content or ""
      req.on_result(content, decoded)
    end),
  })
end

---Submit a request. Cancels any pending/in-flight request on the same channel.
---Throttled: waits out rate-limit backoff and min request interval, latest wins.
---@param req Stride.TransportRequest
function M.request(req)
  local ch = _channel(req.channel)

  -- Latest request wins: cancel pending + in-flight
  ch.id = ch.id + 1
  local request_id = ch.id
  _stop_timer(ch)
  _kill_job(ch)

  local delay = _dispatch_delay()
  if delay <= 0 then
    _dispatch(req, ch, request_id, 1)
    return
  end

  Log.debug("transport: throttled channel=%s, dispatching in %dms", req.channel, delay)
  ch.timer = vim.loop.new_timer()
  ch.timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      _stop_timer(ch)
      if request_id ~= ch.id then
        return
      end
      -- Re-check backoff (a 429 may have arrived while waiting)
      local now = vim.loop.now()
      if M._backoff_until > now then
        Log.debug("transport: still in backoff, dropping request channel=%s", req.channel)
        return
      end
      _dispatch(req, ch, request_id, 1)
    end)
  )
end

---Cancel everything (used by :StrideDisable)
function M.cancel_all()
  for name in pairs(M._channels) do
    M.cancel(name)
  end
end

---Reset state (for testing)
function M._reset()
  M.cancel_all()
  M._channels = {}
  M._backoff_until = 0
  M._last_dispatch = 0
  M._backoff_notified = false
end

return M
