local M = {}

local Config = require("stride.config")
local Utils = require("stride.utils")
local Client = require("stride.client")
local Ui = require("stride.ui")

---Check if current filetype is disabled
---@return boolean
local function _is_disabled()
  local ft = vim.bo.filetype
  for _, disabled_ft in ipairs(Config.options.disabled_filetypes or {}) do
    if ft == disabled_ft then
      return true
    end
  end
  return false
end

---Setup stride.nvim
---@param opts Stride.Config|nil
function M.setup(opts)
  -- Check dependencies
  if not pcall(require, "plenary") then
    error("stride.nvim requires plenary.nvim")
  end

  -- Optional warning for Treesitter
  if opts and opts.use_treesitter and not pcall(require, "nvim-treesitter") then
    vim.notify("stride.nvim: Treesitter enabled but nvim-treesitter not found. Using built-in.", vim.log.levels.WARN)
  end

  Config.setup(opts)

  local augroup = vim.api.nvim_create_augroup("StrideGroup", { clear = true })

  -- Trigger prediction on text change (debounced)
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function()
      if _is_disabled() then
        return
      end
      Ui.clear()
      Client.cancel()
      Utils.debounce(Config.options.debounce_ms, function()
        if _is_disabled() then
          return
        end
        local ctx = Utils.get_context(Config.options.context_lines)
        Client.fetch_prediction(ctx, Ui.render)
      end)
    end,
  })

  -- Clear on cursor move, mode change, or leaving insert
  vim.api.nvim_create_autocmd({ "CursorMovedI", "InsertLeave", "ModeChanged" }, {
    group = augroup,
    callback = function()
      Ui.clear()
      Client.cancel()
    end,
  })

  -- Tab keymap: accept suggestion or fallback to normal Tab
  vim.keymap.set("i", Config.options.accept_keymap, function()
    return M.accept()
  end, { expr = true, silent = true })
end

---Accept current suggestion
---@return string Empty string if accepted, Tab key otherwise
function M.accept()
  local s = Ui.current_suggestion
  if s and s.text and s.text ~= "" then
    local buf = s.buf or vim.api.nvim_get_current_buf()
    local r, c = s.row, s.col

    -- Insert first line at cursor position
    vim.api.nvim_buf_set_text(buf, r, c, r, c, { s.lines[1] })

    -- Insert remaining lines below
    if #s.lines > 1 then
      local extra = { unpack(s.lines, 2) }
      vim.api.nvim_buf_set_lines(buf, r + 1, r + 1, false, extra)
    end

    -- Move cursor to end of inserted text
    local last_len = #s.lines[#s.lines]
    local tr = r + #s.lines - 1
    local tc = (tr == r) and (c + last_len) or last_len
    vim.api.nvim_win_set_cursor(0, { tr + 1, tc })

    Ui.clear()
    return ""
  else
    -- Fallback to normal Tab behavior
    return vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
  end
end

return M
