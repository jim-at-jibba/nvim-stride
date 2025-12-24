local M = {}

local Config = require("stride.config")
local Utils = require("stride.utils")
local Client = require("stride.client")
local Ui = require("stride.ui")
local Log = require("stride.log")

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

  Log.debug("===== STRIDE SETUP =====")
  Log.debug("debug=%s", tostring(Config.options.debug))
  Log.debug("endpoint=%s", Config.options.endpoint)
  Log.debug("model=%s", Config.options.model)
  Log.debug("debounce_ms=%d", Config.options.debounce_ms)
  Log.debug("context_lines=%d", Config.options.context_lines)
  Log.debug("use_treesitter=%s", tostring(Config.options.use_treesitter))
  Log.debug("accept_keymap=%s", Config.options.accept_keymap)
  Log.debug("api_key=%s", Config.options.api_key and "(set)" or "(NOT SET)")
  Log.debug("disabled_filetypes=%s", vim.inspect(Config.options.disabled_filetypes))

  local augroup = vim.api.nvim_create_augroup("StrideGroup", { clear = true })

  -- Trigger prediction on text change (debounced)
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    callback = function()
      if _is_disabled() then
        Log.debug("TextChangedI: filetype disabled, skipping")
        return
      end
      Log.debug("TextChangedI: triggered, scheduling prediction")
      Ui.clear()
      Client.cancel()
      Utils.debounce(Config.options.debounce_ms, function()
        if _is_disabled() then
          return
        end
        Log.debug("debounce complete, fetching prediction")
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

  Log.debug("setup complete, keymap=%s, debounce=%dms", Config.options.accept_keymap, Config.options.debounce_ms)
end

---Accept current suggestion
---@return string Empty string if accepted, Tab key otherwise
function M.accept()
  local s = Ui.current_suggestion
  if s and s.text and s.text ~= "" then
    Log.debug("accept: inserting %d lines at row=%d col=%d", #s.lines, s.row, s.col)

    -- Capture values before clearing
    local buf = s.buf or vim.api.nvim_get_current_buf()
    local r, c = s.row, s.col
    local lines = s.lines

    Ui.clear()

    -- Defer buffer modification to avoid E565 in expr mappings
    vim.schedule(function()
      -- Insert first line at cursor position
      vim.api.nvim_buf_set_text(buf, r, c, r, c, { lines[1] })

      -- Insert remaining lines below
      if #lines > 1 then
        local extra = { unpack(lines, 2) }
        vim.api.nvim_buf_set_lines(buf, r + 1, r + 1, false, extra)
      end

      -- Move cursor to end of inserted text
      local last_len = #lines[#lines]
      local tr = r + #lines - 1
      local tc = (tr == r) and (c + last_len) or last_len
      vim.api.nvim_win_set_cursor(0, { tr + 1, tc })
    end)

    return ""
  else
    Log.debug("accept: no suggestion, fallback to Tab")
    -- Fallback to normal Tab behavior
    return vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
  end
end

return M
