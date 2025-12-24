local Config = require("stride.config")
local Ui = require("stride.ui")

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
  end)
end)
