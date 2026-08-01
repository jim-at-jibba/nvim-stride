-- Tests for history word-level diff formatting
describe("history._word_diff", function()
  local History = require("stride.history")

  local cases = {
    {
      desc = "rename mid-line",
      old = "print(configTest1)",
      new = "print(config)",
      want_old = "configTest1",
      want_new = "config",
    },
    {
      desc = "completely different strings",
      old = "apple",
      new = "orange",
      want_old = "apple",
      want_new = "orange",
    },
    {
      desc = "append at end of identifier",
      old = "local config = 1",
      new = "local configFoo = 1",
      want_old = "config",
      want_new = "configFoo",
    },
    {
      desc = "pure insertion of new argument",
      old = "fn(a, b)",
      new = "fn(a, b, c)",
      want_old = "b",
      want_new = "b, c",
    },
    {
      desc = "identical strings",
      old = "same",
      new = "same",
      want_old = "",
      want_new = "",
    },
  }

  for _, t in ipairs(cases) do
    it(t.desc, function()
      local got_old, got_new = History._word_diff(t.old, t.new)
      assert.equals(t.want_old, got_old)
      assert.equals(t.want_new, got_new)
    end)
  end
end)

describe("history._splice", function()
  local History = require("stride.history")

  it("replaces lines in place when counts match", function()
    local state = { "a", "b", "c" }
    History._splice(state, 2, 1, { "B" })
    assert.same({ "a", "B", "c" }, state)
  end)

  it("shrinks state when lines are deleted", function()
    local state = { "a", "b", "c", "d" }
    History._splice(state, 2, 2, { "X" })
    assert.same({ "a", "X", "d" }, state)
  end)

  it("grows state when lines are added", function()
    local state = { "a", "b" }
    History._splice(state, 2, 1, { "x", "y", "z" })
    assert.same({ "a", "x", "y", "z" }, state)
  end)

  it("handles pure deletion", function()
    local state = { "a", "b", "c" }
    History._splice(state, 2, 2, {})
    assert.same({ "a" }, state)
  end)
end)

describe("history incremental buffer state", function()
  local History = require("stride.history")
  local Config = require("stride.config")
  local buf
  local tmpfile

  before_each(function()
    Config.setup({ api_key = "test" })
    History.clear()
    tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line one", "line two", "line three" }, tmpfile)
    vim.cmd("edit " .. tmpfile)
    buf = vim.api.nvim_get_current_buf()
    History.attach_buffer(buf)
  end)

  after_each(function()
    History.clear()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    pcall(vim.fn.delete, tmpfile)
    History._attached_buffers = {}
    History._buffer_states = {}
  end)

  local function assert_state_synced()
    assert.same(vim.api.nvim_buf_get_lines(buf, 0, -1, false), History._buffer_states[buf])
  end

  it("keeps state in sync through single-line edits", function()
    vim.api.nvim_buf_set_text(buf, 0, 5, 0, 8, { "ONE" })
    assert_state_synced()
  end)

  it("keeps state in sync through line insertion", function()
    vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "inserted a", "inserted b" })
    assert_state_synced()
  end)

  it("keeps state in sync through line deletion", function()
    vim.api.nvim_buf_set_lines(buf, 0, 2, false, {})
    assert_state_synced()
  end)

  it("keeps state in sync through mixed sequential edits", function()
    vim.api.nvim_buf_set_text(buf, 0, 0, 0, 4, { "LINE" })
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "replaced", "extra" })
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
    assert_state_synced()
  end)

  it("records changes from buffer edits", function()
    vim.api.nvim_buf_set_text(buf, 0, 5, 0, 8, { "ONE" })
    assert.is_true(History.get_change_count() > 0)
    local changes = History.get_changes()
    assert.equals("line one", changes[1].old_text)
    assert.equals("line ONE", changes[1].new_text)
  end)
end)

describe("history._format_change_as_diff", function()
  local History = require("stride.history")

  it("emits fragment-level diff for single-line changes", function()
    local diff = History._format_change_as_diff({
      file = "test.lua",
      old_text = "print(oldName)",
      new_text = "print(newName)",
      range = { start_line = 5, start_col = 0, end_line = 5, end_col = 14 },
    })
    assert.equals("test.lua:5:5\n- oldName\n+ newName", diff)
  end)

  it("emits full lines for multi-line changes", function()
    local diff = History._format_change_as_diff({
      file = "test.lua",
      old_text = "line1\nline2",
      new_text = "line1\nchanged",
      range = { start_line = 1, start_col = 0, end_line = 2, end_col = 7 },
    })
    assert.is_not_nil(diff:find("- line1", 1, true))
    assert.is_not_nil(diff:find("+ changed", 1, true))
  end)

  it("emits full text for pure inserts", function()
    local diff = History._format_change_as_diff({
      file = "test.lua",
      old_text = "",
      new_text = "new line",
      range = { start_line = 3, start_col = 0, end_line = 3, end_col = 8 },
    })
    assert.equals("test.lua:3:3\n+ new line", diff)
  end)
end)
