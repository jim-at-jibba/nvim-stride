-- Tests for predictor.fetch_next_edit multi-edit response handling
-- (transport stubbed; must be loaded before predictor)
describe("predictor.fetch_next_edit", function()
  local captured
  local Predictor
  local History
  local Config
  local buf

  before_each(function()
    captured = nil
    package.loaded["stride.transport"] = {
      request = function(req)
        captured = req
      end,
      cancel = function() end,
    }
    package.loaded["stride.predictor"] = nil

    Config = require("stride.config")
    Config.setup({ api_key = "test" })
    History = require("stride.history")
    History.clear()
    Predictor = require("stride.predictor")

    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "local new_name = 1",
      "print(old_name)",
      "return old_name",
    })

    -- Seed a tracked change so fetch_next_edit doesn't bail early
    History.record_change({
      file = "[buffer]",
      old_text = "local old_name = 1",
      new_text = "local new_name = 1",
      range = { start_line = 1, start_col = 0, end_line = 1, end_col = 18 },
      timestamp = os.time(),
    })
  end)

  after_each(function()
    History.clear()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    package.loaded["stride.transport"] = nil
    package.loaded["stride.predictor"] = nil
  end)

  local cursor = { line = 1, col = 0 }

  it("returns the ordered edit list from an edits-array response", function()
    local got
    Predictor.fetch_next_edit(buf, cursor, function(edits)
      got = edits
    end)
    assert.is_truthy(captured, "transport.request not called")

    captured.on_result(vim.fn.json_encode({
      edits = {
        { action = "replace", line = 2, find = "old_name", replace = "new_name" },
        { action = "replace", line = 3, find = "old_name", replace = "new_name" },
      },
    }))

    assert.is_truthy(got)
    assert.equals(2, #got)
    assert.equals(2, got[1].line)
    assert.equals(3, got[2].line)
  end)

  it("wraps a legacy single-edit response into a list", function()
    local got
    Predictor.fetch_next_edit(buf, cursor, function(edits)
      got = edits
    end)

    captured.on_result(vim.fn.json_encode({
      action = "replace",
      line = 2,
      find = "old_name",
      replace = "new_name",
    }))

    assert.is_truthy(got)
    assert.equals(1, #got)
  end)

  it("returns nil for an empty edits array", function()
    local got = "unset"
    Predictor.fetch_next_edit(buf, cursor, function(edits)
      got = edits
    end)

    captured.on_result(vim.fn.json_encode({ edits = {} }))
    assert.is_nil(got)
  end)

  it("returns nil for unparseable content", function()
    local got = "unset"
    Predictor.fetch_next_edit(buf, cursor, function(edits)
      got = edits
    end)

    captured.on_result("not json at all")
    assert.is_nil(got)
  end)

  it("strips markdown fences before parsing", function()
    local got
    Predictor.fetch_next_edit(buf, cursor, function(edits)
      got = edits
    end)

    captured.on_result('```json\n{"edits": [{"action": "replace", "line": 2, "find": "old_name", "replace": "x"}]}\n```')
    assert.is_truthy(got)
    assert.equals(1, #got)
  end)
end)
