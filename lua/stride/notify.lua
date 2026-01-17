local M = {}

local Log = require("stride.log")

-- State
local current_win = nil
local current_buf = nil
local hide_timer = nil

-- Constants
local FADE_DURATION = 150 -- ms

---Check if nerd font is available
---@return boolean
local function _has_nerd_font()
  local ok = pcall(require, "nvim-web-devicons")
  return ok
end

---Get the stride icon
---@return string
local function _get_icon()
  return _has_nerd_font() and "󰷺" or ">"
end

---Stop the hide timer
local function _stop_timer()
  if hide_timer then
    pcall(vim.uv.timer_stop, hide_timer)
    pcall(vim.uv.close, hide_timer)
    hide_timer = nil
  end
end

---Close notification window and buffer (internal, synchronous)
local function _do_close()
  _stop_timer()
  if current_win and vim.api.nvim_win_is_valid(current_win) then
    pcall(vim.api.nvim_win_close, current_win, true)
  end
  if current_buf and vim.api.nvim_buf_is_valid(current_buf) then
    pcall(vim.api.nvim_buf_delete, current_buf, { force = true })
  end
  current_win = nil
  current_buf = nil
end

---Close notification window and buffer (schedules to avoid E565)
function M._close()
  _stop_timer()
  -- Schedule to avoid E565 when called during text change operations
  vim.schedule(_do_close)
end

---Hide notification with optional fade animation
---@param animate? boolean
function M.hide(animate)
  if not current_win or not vim.api.nvim_win_is_valid(current_win) then
    return
  end

  local ok, Snacks = pcall(require, "snacks")
  if animate and ok and Snacks.animate then
    Snacks.animate(0, 100, function(value, ctx)
      if current_win and vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_set_option_value("winblend", math.floor(value), { win = current_win })
        if ctx.done then
          M._close()
        end
      end
    end, { duration = FADE_DURATION, easing = "inQuad", id = "stride-notify-out" })
  else
    M._close()
  end
end

---Show notification at bottom-center
---@param msg string
---@param opts? { timeout?: number }
function M.show(msg, opts)
  opts = opts or {}
  local timeout = opts.timeout or 2000

  -- Close existing notification (synchronous to avoid race)
  _do_close()

  -- Calculate dimensions (use display width for multi-byte chars like icons)
  local content = " " .. msg .. " "
  local width = vim.fn.strdisplaywidth(content)
  local height = 1
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local col = math.floor((editor_width - width - 2) / 2) -- -2 for border
  local row = editor_height - 4 -- above statusline/cmdline

  -- Create buffer
  current_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, { content })

  -- Create window
  current_win = vim.api.nvim_open_win(current_buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 100,
    focusable = false,
  })

  -- Set highlights
  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:StrideNotify,FloatBorder:StrideNotifyBorder",
    { win = current_win }
  )

  -- Fade in with Snacks if available
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.animate then
    vim.api.nvim_set_option_value("winblend", 100, { win = current_win })
    Snacks.animate(100, 0, function(value)
      if current_win and vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_set_option_value("winblend", math.floor(value), { win = current_win })
      end
    end, { duration = FADE_DURATION, easing = "outQuad", id = "stride-notify-in" })
  end

  -- Schedule hide after timeout
  hide_timer = vim.uv.new_timer()
  hide_timer:start(
    timeout,
    0,
    vim.schedule_wrap(function()
      M.hide(true)
    end)
  )

  Log.debug("notify: showing '%s' for %dms", msg, timeout)
end

---Show tab suggestion notification
---@param direction? "up"|"down"
function M.tab_hint(direction)
  local Config = require("stride.config")
  local notify_cfg = Config.options.notify

  -- Check if disabled
  if notify_cfg == false or (notify_cfg and notify_cfg.enabled == false) then
    return
  end

  local icon = _get_icon()
  local arrow = ""
  if direction == "up" then
    arrow = "↑ "
  elseif direction == "down" then
    arrow = "↓ "
  end

  local msg = icon .. " " .. arrow .. "Tab to apply"
  local timeout = notify_cfg and notify_cfg.timeout or 2000

  M.show(msg, { timeout = timeout })
end

return M
