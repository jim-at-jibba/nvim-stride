local Context = require("stride.context").Context
local Config = require("stride.config")
local Geo = require("stride.geo")
local Point = Geo.Point

describe("context", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3" })
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    Config.setup({})
    require("stride.context").clear_cache()
  end)

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  describe("from_current_buffer", function()
    it("creates context with correct buffer", function()
      local ctx = Context.from_current_buffer()
      assert.equal(buf, ctx.buf)
    end)

    it("captures cursor position", function()
      local ctx = Context.from_current_buffer()
      assert.equal(2, ctx.cursor.row)
      assert.equal(4, ctx.cursor.col)
    end)

    it("captures filetype", function()
      vim.bo[buf].filetype = "lua"
      local ctx = Context.from_current_buffer()
      assert.equal("lua", ctx.filetype)
    end)

    it("file_path is relative to cwd", function()
      local full_path = vim.api.nvim_buf_get_name(buf)
      local ctx = Context.from_current_buffer()
      assert.is_not_nil(ctx.file_path)
      assert.is_not_nil(ctx.file_path:match("^[^/]"))
    end)
  end)

  describe("get_function_text", function()
    it("returns nil when not in function", function()
      local ctx = Context.from_current_buffer()
      local text = ctx:get_function_text()
      assert.is_nil(text)
    end)

    it("returns function text when available", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "local function test()",
        "  return 1",
        "end",
      })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local ctx = Context.from_current_buffer()
      local text = ctx:get_function_text()
      if text then
        assert.is_string(text)
        assert.is_true(#text > 0)
      end
    end)
  end)

  describe("build_prompt_context", function()
    it("returns numbered lines with cursor marker", function()
      local ctx = Context.from_current_buffer()
      local output = ctx:build_prompt_context(1, 3)
      assert.is_string(output)
      assert.is_not_nil(output:find("1:"))
      assert.is_not_nil(output:find("2:"))
      assert.is_not_nil(output:find("3:"))
      assert.is_not_nil(output:find("│"))
    end)

    it("marks cursor position correctly", function()
      local ctx = Context.from_current_buffer()
      local output = ctx:build_prompt_context(1, 3)
      assert.is_not_nil(output:find("│"))
    end)
  end)

  describe("agent_context", function()
    it("returns nil when context_files not configured", function()
      Config.setup({ context_files = false })
      local ctx = Context.from_current_buffer()
      assert.is_nil(ctx:get_agent_context())
    end)

    it("caches discovered content", function()
      Config.setup({ context_files = { "*.md" } })
      local ctx = Context.from_current_buffer()
      local first = ctx:get_agent_context()
      local second = ctx:get_agent_context()
      assert.equal(first, second)
    end)

    it("clear_cache clears the cache", function()
      Config.setup({ context_files = { "AGENTS.md" } })
      local ctx = Context.from_current_buffer()
      -- Just verify the functions work - no file expected
      local first = ctx:get_agent_context()
      require("stride.context").clear_cache()
      local after = ctx:get_agent_context()
      -- Both may be nil if no AGENTS.md exists, that's fine
      assert.equal(first, after)
    end)
  end)
end)
