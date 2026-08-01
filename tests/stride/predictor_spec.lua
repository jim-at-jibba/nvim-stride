-- Tests for predictor response validation (line-anchored edits)
describe("predictor._validate_response", function()
  local Predictor = require("stride.predictor")
  local Config = require("stride.config")
  local buf

  before_each(function()
    Config.setup({ api_key = "test" })
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "local config = {}", -- 1
      "", -- 2
      "local function setup()", -- 3
      "  print(old_name)", -- 4
      "end", -- 5
      "", -- 6
      "local function teardown()", -- 7
      "  print(old_name)", -- 8
      "end", -- 9
    })
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  local cursor = { line = 1, col = 0 }

  it("anchors replace to the model-reported line", function()
    local suggestion = Predictor._validate_response({
      action = "replace",
      line = 8,
      find = "old_name",
      replace = "new_name",
    }, buf, cursor)

    assert.is_truthy(suggestion)
    assert.equals(8, suggestion.line)
    assert.equals("old_name", suggestion.original)
    assert.equals("new_name", suggestion.new)
  end)

  it("recovers when the model line is slightly off (fuzzy radius)", function()
    local suggestion = Predictor._validate_response({
      action = "replace",
      line = 5, -- actual occurrence is line 4
      find = "old_name",
      replace = "new_name",
    }, buf, cursor)

    assert.is_truthy(suggestion)
    assert.equals(4, suggestion.line)
  end)

  it("falls back to buffer-wide search when line is far off", function()
    local suggestion = Predictor._validate_response({
      action = "replace",
      line = 99,
      find = "old_name",
      replace = "new_name",
    }, buf, cursor)

    assert.is_truthy(suggestion)
    -- Nearest to cursor line 1 is line 4
    assert.equals(4, suggestion.line)
  end)

  it("still works without a line field (backward compat)", function()
    local suggestion = Predictor._validate_response({
      action = "replace",
      find = "old_name",
      replace = "new_name",
    }, buf, cursor)

    assert.is_truthy(suggestion)
    assert.equals(4, suggestion.line)
  end)

  it("returns nil when find text does not exist", function()
    local suggestion = Predictor._validate_response({
      action = "replace",
      line = 4,
      find = "does_not_exist",
      replace = "x",
    }, buf, cursor)

    assert.is_nil(suggestion)
  end)

  it("returns nil for action=null", function()
    local suggestion = Predictor._validate_response({ action = vim.NIL }, buf, cursor)
    assert.is_nil(suggestion)
  end)

  it("skips occurrences on the cursor line", function()
    local suggestion = Predictor._validate_response({
      action = "replace",
      line = 4,
      find = "old_name",
      replace = "new_name",
    }, buf, { line = 4, col = 0 })

    assert.is_truthy(suggestion)
    assert.equals(8, suggestion.line) -- fuzzy radius misses; falls back and picks line 8
  end)

  it("anchors insert to the model-reported line", function()
    local suggestion = Predictor._validate_response({
      action = "insert",
      line = 7,
      anchor = "teardown()",
      position = "after",
      insert = " -- cleanup",
    }, buf, cursor)

    assert.is_truthy(suggestion)
    assert.equals(7, suggestion.line)
    assert.equals("insert", suggestion.action)
  end)
end)
