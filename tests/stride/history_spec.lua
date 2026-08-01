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
