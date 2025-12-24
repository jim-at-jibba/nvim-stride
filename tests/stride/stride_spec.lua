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
      assert.equals("llama-3.3-70b", Config.options.model)
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
  end)

  describe("history", function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local apple = 1", "print(apple)", "return apple" })
      History.clear()
    end)

    after_each(function()
      History.clear()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    it("takes buffer snapshot", function()
      History.take_snapshot(buf)
      assert.is_not_nil(History._snapshot)
      assert.equals(3, #History._snapshot)
    end)

    it("detects no changes when buffer unchanged", function()
      History.take_snapshot(buf)
      local edits = History.compute_diff(buf)
      assert.same({}, edits)
    end)

    it("detects line modification", function()
      History.take_snapshot(buf)
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local orange = 1" })
      local edits = History.compute_diff(buf)
      assert.equals(1, #edits)
      assert.equals("modification", edits[1].change_type)
      assert.equals(1, edits[1].line)
      assert.equals("local apple = 1", edits[1].original)
      assert.equals("local orange = 1", edits[1].new)
    end)

    it("detects line insertion", function()
      History.take_snapshot(buf)
      vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "local banana = 2" })
      local edits = History.compute_diff(buf)
      assert.is_true(#edits >= 1)
      -- At least one insert should be detected
      local has_insert = false
      for _, edit in ipairs(edits) do
        if edit.change_type == "insert" then
          has_insert = true
          break
        end
      end
      assert.is_true(has_insert)
    end)

    it("clears history", function()
      History.take_snapshot(buf)
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local orange = 1" })
      History.compute_diff(buf)
      assert.is_true(#History.get_history() > 0)
      History.clear()
      assert.same({}, History.get_history())
      assert.is_nil(History._snapshot)
    end)

    it("maintains sliding window of edits", function()
      History.take_snapshot(buf)
      -- Make multiple edits
      for i = 1, 10 do
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local var" .. i .. " = " .. i })
        History.compute_diff(buf)
      end
      -- Should be limited to max history size (5)
      assert.is_true(#History.get_history() <= History._max_history)
    end)

    it("returns last edit", function()
      History.take_snapshot(buf)
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local orange = 1" })
      History.compute_diff(buf)
      local last = History.get_last_edit()
      assert.is_not_nil(last)
      assert.equals("modification", last.change_type)
    end)
  end)
end)
