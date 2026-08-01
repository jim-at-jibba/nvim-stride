-- Tests for stride.transport: throttling, backoff, cancellation
local stub_curl = {
  posts = {}, -- captured requests
}

---Simulate a response to the most recent request
---@param out table|nil Response object
local function respond(out)
  local last = stub_curl.posts[#stub_curl.posts]
  assert(last, "no request captured")
  last.opts.callback(out)
end

describe("transport", function()
  local Transport
  local Config

  before_each(function()
    -- Stub plenary.curl before transport loads
    stub_curl.posts = {}
    package.loaded["plenary.curl"] = {
      post = function(url, opts)
        local job = {
          shutdown_called = false,
          shutdown = function(self)
            self.shutdown_called = true
          end,
        }
        table.insert(stub_curl.posts, { url = url, opts = opts, job = job })
        return job
      end,
    }

    package.loaded["stride.transport"] = nil
    package.loaded["stride.config"] = nil
    Config = require("stride.config")
    Config.setup({
      api_key = "test-key",
      min_request_interval_ms = 0, -- disable throttle unless test overrides
      rate_limit_cooldown_ms = 5000,
    })
    Transport = require("stride.transport")
    Transport._reset()

    -- Silence notifications
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function() end
  end)

  after_each(function()
    Transport._reset()
    package.loaded["plenary.curl"] = nil
    package.loaded["stride.transport"] = nil
  end)

  it("dispatches a request and delivers content", function()
    local got
    Transport.request({
      channel = "test",
      payload = { model = "m" },
      on_result = function(content)
        got = content
      end,
    })

    assert.equals(1, #stub_curl.posts)
    respond({
      status = 200,
      headers = {},
      body = vim.fn.json_encode({ choices = { { message = { content = "hello" } } } }),
    })
    vim.wait(100, function()
      return got ~= nil
    end)
    assert.equals("hello", got)
  end)

  it("kills in-flight job when a new request arrives on same channel", function()
    local first_result = nil
    Transport.request({
      channel = "test",
      payload = {},
      on_result = function(c)
        first_result = c
      end,
    })
    local first = stub_curl.posts[1]

    Transport.request({
      channel = "test",
      payload = {},
      on_result = function() end,
    })

    assert.is_true(first.job.shutdown_called)

    -- Late response from first request must be discarded
    first.opts.callback({
      status = 200,
      headers = {},
      body = vim.fn.json_encode({ choices = { { message = { content = "stale" } } } }),
    })
    vim.wait(50)
    assert.is_nil(first_result)
  end)

  it("enters backoff on 429 and drops requests during the window", function()
    local errored
    Transport.request({
      channel = "test",
      payload = {},
      on_result = function() end,
      on_error = function(kind)
        errored = kind
      end,
    })
    respond({ status = 429, headers = { "retry-after: 5" }, body = "" })
    vim.wait(100, function()
      return errored ~= nil
    end)
    assert.equals("rate_limited", errored)

    -- New request during backoff must not dispatch immediately
    Transport.request({
      channel = "test",
      payload = {},
      on_result = function() end,
    })
    vim.wait(50)
    assert.equals(1, #stub_curl.posts)
  end)

  it("throttles: second request within min interval is delayed", function()
    Config.options.min_request_interval_ms = 200

    Transport.request({ channel = "a", payload = {}, on_result = function() end })
    assert.equals(1, #stub_curl.posts)
    respond({
      status = 200,
      headers = {},
      body = vim.fn.json_encode({ choices = { { message = { content = "x" } } } }),
    })

    Transport.request({ channel = "b", payload = {}, on_result = function() end })
    -- Not dispatched yet (throttled)
    assert.equals(1, #stub_curl.posts)

    vim.wait(500, function()
      return #stub_curl.posts == 2
    end)
    assert.equals(2, #stub_curl.posts)
  end)

  it("retries on 5xx and succeeds on second attempt", function()
    local got
    Transport.request({
      channel = "test",
      payload = {},
      on_result = function(c)
        got = c
      end,
    })
    respond({ status = 500, headers = {}, body = "boom" })

    -- Retry is scheduled with 500ms backoff
    vim.wait(1500, function()
      return #stub_curl.posts == 2
    end)
    assert.equals(2, #stub_curl.posts)

    respond({
      status = 200,
      headers = {},
      body = vim.fn.json_encode({ choices = { { message = { content = "recovered" } } } }),
    })
    vim.wait(100, function()
      return got ~= nil
    end)
    assert.equals("recovered", got)
  end)
end)
