-- Tests for ghost-text retention (ui.try_advance)
describe("ui.try_advance", function()
  local Ui = require("stride.ui")
  local buf

  before_each(function()
    -- Allow cursor one past EOL in normal mode (mimics insert-mode cursor)
    vim.o.virtualedit = "onemore"
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = " })
    -- Cursor at end of line 1 (col 10)
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    Ui.clear()
  end)

  after_each(function()
    Ui.clear()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("returns false when there is no suggestion", function()
    assert.is_false(Ui.try_advance())
  end)

  it("keeps suggestion when cursor has not moved", function()
    Ui.render("compute()", 0, 10, buf)
    assert.is_truthy(Ui.current_suggestion)
    assert.is_true(Ui.try_advance())
    assert.equals("compute()", Ui.current_suggestion.text)
  end)

  it("consumes typed characters matching the suggestion head", function()
    Ui.render("compute()", 0, 10, buf)

    -- User types "comp"
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = comp" })
    vim.api.nvim_win_set_cursor(0, { 1, 14 })

    assert.is_true(Ui.try_advance())
    assert.equals("ute()", Ui.current_suggestion.text)
    assert.equals(14, Ui.current_suggestion.col)
  end)

  it("rejects when typed text does not match", function()
    Ui.render("compute()", 0, 10, buf)

    -- User types "xyz"
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = xyz" })
    vim.api.nvim_win_set_cursor(0, { 1, 13 })

    assert.is_false(Ui.try_advance())
  end)

  it("clears when suggestion is fully consumed", function()
    Ui.render("comp", 0, 10, buf)

    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = comp" })
    vim.api.nvim_win_set_cursor(0, { 1, 14 })

    assert.is_false(Ui.try_advance())
    assert.is_nil(Ui.current_suggestion)
  end)

  it("rejects when cursor moves to a different row", function()
    Ui.render("compute()", 0, 10, buf)

    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = ", "next" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    assert.is_false(Ui.try_advance())
  end)

  it("rejects when cursor moves left of anchor (backspace)", function()
    Ui.render("compute()", 0, 10, buf)

    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x =" })
    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    assert.is_false(Ui.try_advance())
  end)

  it("advances multiline suggestions on first-line consumption", function()
    Ui.render("if x then\n  return x\nend", 0, 10, buf)

    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = if x" })
    vim.api.nvim_win_set_cursor(0, { 1, 14 })

    assert.is_true(Ui.try_advance())
    assert.equals(" then\n  return x\nend", Ui.current_suggestion.text)
  end)
end)
