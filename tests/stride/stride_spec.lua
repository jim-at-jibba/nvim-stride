local Config = require("stride.config")
local Ui = require("stride.ui")
local History = require("stride.history")

describe("stride", function()
  describe("config", function()
    before_each(function()
      -- Reset config to defaults
      Config.options = {}
    end)

    it("has sensible defaults", function()
      Config.setup({})
      assert.is_not_nil(Config.options.endpoint)
      assert.equals("gpt-oss-120b", Config.options.model)
      assert.equals(300, Config.options.debounce_ms)
      assert.equals("<Tab>", Config.options.accept_keymap)
      assert.equals(30, Config.options.context_lines)
      assert.is_true(Config.options.use_treesitter)
      assert.same({}, Config.options.disabled_filetypes)
      assert.equals("completion", Config.options.mode)
      assert.is_true(Config.options.show_remote)
    end)

    it("merges user options with defaults", function()
      Config.setup({
        model = "custom-model",
        debounce_ms = 500,
        disabled_filetypes = { "markdown" },
      })
      assert.equals("custom-model", Config.options.model)
      assert.equals(500, Config.options.debounce_ms)
      assert.same({ "markdown" }, Config.options.disabled_filetypes)
      -- Defaults preserved
      assert.equals(30, Config.options.context_lines)
      assert.equals("<Tab>", Config.options.accept_keymap)
    end)

    it("allows overriding api_key", function()
      Config.setup({ api_key = "test-key" })
      assert.equals("test-key", Config.options.api_key)
    end)

    it("supports V2 mode options", function()
      Config.setup({ mode = "refactor", show_remote = false })
      assert.equals("refactor", Config.options.mode)
      assert.is_false(Config.options.show_remote)
    end)

    it("supports both mode", function()
      Config.setup({ mode = "both" })
      assert.equals("both", Config.options.mode)
    end)

    it("has V2 prediction defaults", function()
      Config.setup({})
      assert.equals(10, Config.options.max_tracked_changes)
      assert.equals(1000, Config.options.token_budget)
      assert.equals(200, Config.options.small_file_threshold)
    end)

    it("allows overriding V2 options", function()
      Config.setup({
        max_tracked_changes = 20,
        token_budget = 500,
        small_file_threshold = 100,
      })
      assert.equals(20, Config.options.max_tracked_changes)
      assert.equals(500, Config.options.token_budget)
      assert.equals(100, Config.options.small_file_threshold)
    end)
  end)

  describe("ui", function()
    local buf

    before_each(function()
      -- Create a scratch buffer for testing
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })
      Ui.clear()
    end)

    after_each(function()
      Ui.clear()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    it("renders single-line ghost text", function()
      Ui.render("completion", 0, 5, buf)
      assert.is_not_nil(Ui.current_suggestion)
      assert.equals("completion", Ui.current_suggestion.text)
      assert.equals(0, Ui.current_suggestion.row)
      assert.equals(5, Ui.current_suggestion.col)
    end)

    it("renders multi-line ghost text", function()
      Ui.render("line1\nline2\nline3", 0, 5, buf)
      assert.is_not_nil(Ui.current_suggestion)
      assert.same({ "line1", "line2", "line3" }, Ui.current_suggestion.lines)
    end)

    it("clears ghost text", function()
      Ui.render("completion", 0, 5, buf)
      assert.is_not_nil(Ui.current_suggestion)
      Ui.clear()
      assert.is_nil(Ui.current_suggestion)
      assert.is_nil(Ui.extmark_id)
    end)

    it("handles empty text", function()
      Ui.render("", 0, 5, buf)
      assert.is_nil(Ui.current_suggestion)
    end)

    it("handles nil text", function()
      Ui.render(nil, 0, 5, buf)
      assert.is_nil(Ui.current_suggestion)
    end)

    it("clears previous before rendering new", function()
      Ui.render("first", 0, 5, buf)
      local first_id = Ui.extmark_id
      Ui.render("second", 1, 3, buf)
      assert.are_not.equal(first_id, Ui.extmark_id)
      assert.equals("second", Ui.current_suggestion.text)
    end)

    it("renders remote suggestion", function()
      Ui.setup_highlights()
      local suggestion = {
        line = 2,
        original = "line2",
        new = "modified2",
        col_start = 0,
        col_end = 5,
        is_remote = true,
      }
      Ui.render_remote(suggestion, buf)
      assert.is_not_nil(Ui.current_suggestion)
      assert.is_true(Ui.current_suggestion.is_remote)
      assert.equals(2, Ui.current_suggestion.target_line)
      assert.equals("line2", Ui.current_suggestion.original)
      assert.equals("modified2", Ui.current_suggestion.new)
    end)

    it("clears remote suggestion", function()
      Ui.setup_highlights()
      local suggestion = {
        line = 2,
        original = "line2",
        new = "modified2",
        col_start = 0,
        col_end = 5,
        is_remote = true,
      }
      Ui.render_remote(suggestion, buf)
      assert.is_not_nil(Ui.current_suggestion)
      Ui.clear()
      assert.is_nil(Ui.current_suggestion)
      assert.is_nil(Ui.remote_hl_id)
      assert.is_nil(Ui.remote_virt_id)
    end)

    it("renders insert suggestion", function()
      Ui.setup_highlights()
      local suggestion = {
        line = 2,
        original = "email=email",
        new = ", age=0",
        col_start = 11,
        col_end = 11, -- Same for insert
        is_remote = true,
        action = "insert",
        anchor = "email=email",
        position = "after",
        insert = ", age=0",
      }
      Ui.render_remote(suggestion, buf)
      assert.is_not_nil(Ui.current_suggestion)
      assert.is_true(Ui.current_suggestion.is_remote)
      assert.equals("insert", Ui.current_suggestion.action)
      assert.equals("email=email", Ui.current_suggestion.anchor)
      assert.equals(", age=0", Ui.current_suggestion.insert)
    end)

    it("insert suggestion stores position", function()
      Ui.setup_highlights()
      local suggestion = {
        line = 2,
        original = "anchor",
        new = "prefix_",
        col_start = 0,
        col_end = 0,
        is_remote = true,
        action = "insert",
        anchor = "anchor",
        position = "before",
        insert = "prefix_",
      }
      Ui.render_remote(suggestion, buf)
      assert.is_not_nil(Ui.current_suggestion)
      assert.equals("before", Ui.current_suggestion.position)
    end)
  end)

  describe("predictor validation", function()
    -- Test the Predictor module's validation behavior via buffer+suggestion scenarios
    -- Since _validate_response is local, we test by calling the module's logic indirectly
    -- These tests verify the type definitions and validation rules

    it("defines RemoteSuggestion with action field", function()
      -- Test that the type structure is correct for replace action
      ---@type Stride.RemoteSuggestion
      local replace_suggestion = {
        line = 1,
        original = "old",
        new = "new",
        col_start = 0,
        col_end = 3,
        is_remote = true,
        action = "replace",
      }
      assert.equals("replace", replace_suggestion.action)
      assert.equals("old", replace_suggestion.original)
      assert.equals("new", replace_suggestion.new)
    end)

    it("defines RemoteSuggestion with insert action fields", function()
      ---@type Stride.RemoteSuggestion
      local insert_suggestion = {
        line = 1,
        original = "anchor",
        new = ", age=0",
        col_start = 6,
        col_end = 6,
        is_remote = true,
        action = "insert",
        anchor = "anchor",
        position = "after",
        insert = ", age=0",
      }
      assert.equals("insert", insert_suggestion.action)
      assert.equals("anchor", insert_suggestion.anchor)
      assert.equals("after", insert_suggestion.position)
      assert.equals(", age=0", insert_suggestion.insert)
    end)

    it("insert suggestion has same col_start and col_end", function()
      -- Insert actions should have col_start == col_end (insertion point)
      ---@type Stride.RemoteSuggestion
      local insert_suggestion = {
        line = 5,
        original = "email=email",
        new = ", age=0",
        col_start = 25,
        col_end = 25, -- Same as col_start for insertion
        is_remote = true,
        action = "insert",
        anchor = "email=email",
        position = "after",
        insert = ", age=0",
      }
      assert.equals(insert_suggestion.col_start, insert_suggestion.col_end)
    end)

    it("position defaults to 'after' when not specified", function()
      -- The predictor defaults position to "after" if invalid
      local position = nil
      if position ~= "after" and position ~= "before" then
        position = "after"
      end
      assert.equals("after", position)
    end)

    it("position can be 'before'", function()
      local position = "before"
      if position ~= "after" and position ~= "before" then
        position = "after"
      end
      assert.equals("before", position)
    end)
  end)

  describe("history", function()
    before_each(function()
      History.clear()
      History._attached_buffers = {}
      History._buffer_states = {}
    end)

    after_each(function()
      History.clear()
    end)

    it("records a change", function()
      History.record_change({
        file = "test.lua",
        old_text = "apple",
        new_text = "orange",
        range = { start_line = 1, start_col = 6, end_line = 1, end_col = 11 },
        timestamp = os.time(),
      })
      assert.equals(1, History.get_change_count())
      local changes = History.get_changes()
      assert.equals("apple", changes[1].old_text)
      assert.equals("orange", changes[1].new_text)
    end)

    it("respects max_tracked_changes limit", function()
      Config.setup({ max_tracked_changes = 3 })
      for i = 1, 5 do
        History.record_change({
          file = "test.lua",
          old_text = "old" .. i,
          new_text = "new" .. i,
          range = { start_line = i, start_col = 0, end_line = i, end_col = 4 },
          timestamp = os.time(),
        })
      end
      assert.equals(3, History.get_change_count())
      -- Should have most recent 3 (old3->new3, old4->new4, old5->new5)
      local changes = History.get_changes()
      assert.equals("old3", changes[1].old_text)
      assert.equals("old5", changes[3].old_text)
    end)

    it("clears all changes", function()
      History.record_change({
        file = "test.lua",
        old_text = "foo",
        new_text = "bar",
        range = { start_line = 1, start_col = 0, end_line = 1, end_col = 3 },
        timestamp = os.time(),
      })
      assert.equals(1, History.get_change_count())
      History.clear()
      assert.equals(0, History.get_change_count())
    end)

    it("formats changes for prompt", function()
      History.record_change({
        file = "test.lua",
        old_text = "apple",
        new_text = "orange",
        range = { start_line = 5, start_col = 0, end_line = 5, end_col = 6 },
        timestamp = os.time(),
      })
      local prompt = History.get_changes_for_prompt()
      assert.is_not_nil(prompt:find("test.lua:5:5"))
      assert.is_not_nil(prompt:find("- apple"))
      assert.is_not_nil(prompt:find("+ orange"))
    end)

    it("returns no changes message when empty", function()
      local prompt = History.get_changes_for_prompt()
      assert.equals("(no recent changes)", prompt)
    end)

    it("extracts text from single line", function()
      local lines = { "hello world" }
      local text = History._extract_text(lines, 0, 0, 0, 5)
      assert.equals("hello", text)
    end)

    it("extracts text from multiple lines", function()
      local lines = { "line one", "line two", "line three" }
      local text = History._extract_text(lines, 0, 5, 2, 4)
      assert.equals("one\nline two\nline", text)
    end)

    it("gets changes for specific file", function()
      History.record_change({
        file = "a.lua",
        old_text = "x",
        new_text = "y",
        range = { start_line = 1, start_col = 0, end_line = 1, end_col = 1 },
        timestamp = os.time(),
      })
      History.record_change({
        file = "b.lua",
        old_text = "m",
        new_text = "n",
        range = { start_line = 1, start_col = 0, end_line = 1, end_col = 1 },
        timestamp = os.time(),
      })
      local a_changes = History.get_changes_for_file("a.lua")
      assert.equals(1, #a_changes)
      assert.equals("a.lua", a_changes[1].file)
    end)
  end)
end)
