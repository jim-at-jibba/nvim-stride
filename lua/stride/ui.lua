---@class Stride.Suggestion
---@field text string Full suggestion text
---@field row number 0-indexed row where suggestion starts
---@field col number 0-indexed column where suggestion starts
---@field lines string[] Split lines of suggestion
---@field buf number Buffer handle
---@field is_remote? boolean True if this is a remote (V2) suggestion
---@field target_line? number 1-indexed target line for remote suggestions
---@field original? string Original text to replace (remote only)
---@field new? string Replacement text (remote only)
---@field col_start? number 0-indexed column start (remote only)
---@field col_end? number 0-indexed column end (remote only)
---@field action? "replace"|"insert" Action type for remote suggestions
---@field anchor? string Anchor text for insertion (insert action only)
---@field position? "after"|"before" Insert position relative to anchor (insert action only)
---@field insert? string Text to insert (insert action only)

local M = {}

local Log = require("stride.log")

local ns_id = vim.api.nvim_create_namespace("StrideGhost")
local ns_id_remote = vim.api.nvim_create_namespace("StrideRemote")

---Notify via fidget.nvim if available (optional integration)
---@param current number Current edit index
---@param total number Total pending edits
local function _notify_fidget(current, total)
  local ok, fidget = pcall(require, "fidget")
  if not ok then
    return
  end

  if total > 1 then
    fidget.notify(
      string.format("Edit %d/%d", current, total),
      vim.log.levels.INFO,
      { annote = "Tab to apply", key = "stride-edits", ttl = 1.5 }
    )
  elseif total == 1 then
    fidget.notify("1 edit suggested", vim.log.levels.INFO, { annote = "Tab to apply", key = "stride-edits", ttl = 1.5 })
  end
end

---@type Stride.Suggestion|nil
M.current_suggestion = nil

---@type number|nil
M.current_buf = nil

---@type number|nil
M.extmark_id = nil

---@type number|nil Highlight extmark for remote suggestions
M.remote_hl_id = nil

---@type number|nil Virtual text extmark for remote suggestions
M.remote_virt_id = nil

---@type number|nil Extmark ID for gutter sign
M.sign_id = nil

---@type boolean Whether Esc keymap is currently set
M._esc_mapped = false

---@type number|nil Buffer where Esc mapping was set
M._esc_buf = nil

---Setup Esc keymap to dismiss suggestion
---@param buf number Buffer handle
local function _setup_esc_mapping(buf)
  if M._esc_mapped then
    return
  end

  -- Set buffer-local Esc mapping in normal mode
  vim.keymap.set("n", "<Esc>", function()
    M.clear()
    -- Re-feed Esc so it still works for other things (like clearing search highlight)
    return "<Esc>"
  end, { buffer = buf, expr = true, silent = true, desc = "Dismiss Stride suggestion" })

  M._esc_mapped = true
  M._esc_buf = buf
  Log.debug("ui: Esc mapping set for buf %d", buf)
end

---Remove Esc keymap
local function _clear_esc_mapping()
  if not M._esc_mapped or not M._esc_buf then
    return
  end

  -- Remove the buffer-local mapping
  pcall(vim.keymap.del, "n", "<Esc>", { buffer = M._esc_buf })
  M._esc_mapped = false
  M._esc_buf = nil
  Log.debug("ui: Esc mapping cleared")
end

---Check if nerd font is available
---@return boolean
local function _has_nerd_font()
  if vim.g.have_nerd_font ~= nil then
    return vim.g.have_nerd_font
  end
  local ok = pcall(require, "nvim-web-devicons")
  return ok
end

---Get configured sign icon
---@return string|nil icon or nil if disabled
local function _get_sign_icon()
  local Config = require("stride.config")
  local sign = Config.options.sign
  if sign == false then
    return nil
  end
  if sign and sign.icon then
    return sign.icon
  end
  return _has_nerd_font() and "󰷺" or ">"
end

---Place gutter sign at row
---@param buf number Buffer handle
---@param row number 0-indexed row
local function _place_sign(buf, row)
  local icon = _get_sign_icon()
  if not icon then
    return
  end

  local Config = require("stride.config")
  local hl = (Config.options.sign and Config.options.sign.hl) or "StrideSign"

  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, 0, {
    sign_text = icon,
    sign_hl_group = hl,
    priority = 200, -- High priority since temporary
  })
  if ok then
    M.sign_id = id
    Log.debug("ui: sign placed at row %d, extmark=%d", row, id)
  else
    Log.debug("ui: failed to place sign: %s", tostring(id))
  end
end

---Clear gutter sign
local function _clear_sign()
  if M.sign_id and M.current_buf then
    Log.debug("ui.clear: removing sign extmark %d", M.sign_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id, M.sign_id)
  end
  M.sign_id = nil
end

---Clear current ghost text
function M.clear()
  -- Clear gutter sign
  _clear_sign()

  -- Clear local suggestion extmark
  if M.extmark_id and M.current_buf then
    Log.debug("ui.clear: removing extmark %d", M.extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id, M.extmark_id)
  end

  -- Clear remote suggestion extmarks
  if M.remote_hl_id and M.current_buf then
    Log.debug("ui.clear: removing remote highlight %d", M.remote_hl_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id_remote, M.remote_hl_id)
  end
  if M.remote_virt_id and M.current_buf then
    Log.debug("ui.clear: removing remote virt_text %d", M.remote_virt_id)
    pcall(vim.api.nvim_buf_del_extmark, M.current_buf, ns_id_remote, M.remote_virt_id)
  end

  M.extmark_id = nil
  M.remote_hl_id = nil
  M.remote_virt_id = nil
  M.current_suggestion = nil
  M.current_buf = nil

  _clear_esc_mapping()
end

---Render ghost text at position
---@param text string|nil Suggestion text
---@param row number 0-indexed row
---@param col number 0-indexed column
---@param buf number Buffer handle
function M.render(text, row, col, buf)
  Log.debug("===== UI RENDER CALLED =====")
  Log.debug("row=%d col=%d buf=%d", row, col, buf)

  M.clear()
  if not text or text == "" then
    Log.debug("SKIP: empty/nil text received")
    return
  end

  Log.debug("text (%d chars): %s", #text, text)

  -- Verify buffer is still valid and current
  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("SKIP: buffer %d is invalid", buf)
    return
  end
  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= buf then
    Log.debug("SKIP: buffer changed (request=%d current=%d)", buf, current_buf)
    return
  end

  -- Log current mode (but don't block - mode check happens earlier in flow)
  local mode = vim.api.nvim_get_mode().mode
  Log.debug("current mode=%s", mode)

  -- Log cursor position (but don't block - stale check happens in client)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cur_row, cur_col = cursor[1] - 1, cursor[2]
  Log.debug("cursor position: row=%d col=%d (expected row=%d col=%d)", cur_row, cur_col, row, col)

  local lines = vim.split(text, "\n")
  Log.debug("rendering %d lines as ghost text", #lines)

  -- Line 1: Inline after cursor
  local virt_text = { { lines[1], "Comment" } }

  -- Line 2+: Virtual lines below
  local virt_lines = {}
  if #lines > 1 then
    for i = 2, #lines do
      table.insert(virt_lines, { { lines[i], "Comment" } })
    end
  end

  local opts = {
    virt_text = virt_text,
    virt_text_pos = "inline",
    hl_mode = "combine",
  }
  if #virt_lines > 0 then
    opts.virt_lines = virt_lines
  end

  local ok, extmark = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, col, opts)
  if not ok then
    Log.debug("ERROR: failed to set extmark: %s", tostring(extmark))
    return
  end

  M.extmark_id = extmark
  M.current_buf = buf
  M.current_suggestion = {
    text = text,
    row = row,
    col = col,
    lines = lines,
    buf = buf,
  }

  -- Place gutter sign
  _place_sign(buf, row)

  Log.debug("SUCCESS: extmark_id=%d created", M.extmark_id)
end

---Get namespace ID (for testing)
---@return number
function M.get_ns_id()
  return ns_id
end

---Define highlight groups (called on setup and colorscheme change)
---Uses default=true so users can override these in their config
local function _define_highlights()
  -- Get theme colors (fallback to hardcoded if not available)
  local red = vim.api.nvim_get_hl(0, { name = "DiagnosticError" }).fg
  local green = vim.api.nvim_get_hl(0, { name = "DiagnosticOk" }).fg
    or vim.api.nvim_get_hl(0, { name = "String" }).fg

  -- StrideReplace: red foreground for text to be replaced
  vim.api.nvim_set_hl(0, "StrideReplace", {
    default = true,
    fg = red,
    strikethrough = true,
  })
  -- StrideRemoteSuggestion: green for replacement text
  vim.api.nvim_set_hl(0, "StrideRemoteSuggestion", {
    default = true,
    fg = green,
    italic = true,
  })
  -- StrideInsert: green/italic for insertion point marker
  vim.api.nvim_set_hl(0, "StrideInsert", {
    default = true,
    fg = green,
    italic = true,
  })
  -- StrideSign: gutter icon for active suggestions (green)
  vim.api.nvim_set_hl(0, "StrideSign", {
    default = true,
    fg = green,
  })
  Log.debug("ui: highlight groups defined")
end

---Setup highlight groups for remote suggestions
function M.setup_highlights()
  _define_highlights()

  -- Reapply highlights when colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("StrideHighlights", { clear = true }),
    callback = _define_highlights,
  })
end

---Render a remote suggestion (V2) - supports both replace and insert actions
---@param suggestion Stride.RemoteSuggestion
---@param buf number Buffer handle
---@param current? number Current edit index (1-based), for count display
---@param total? number Total pending edits, for count display
function M.render_remote(suggestion, buf, current, total)
  local action = suggestion.action or "replace"
  Log.debug("===== UI RENDER REMOTE =====")
  Log.debug("action=%s line=%d", action, suggestion.line)

  M.clear()

  if not vim.api.nvim_buf_is_valid(buf) then
    Log.debug("SKIP: buffer %d is invalid", buf)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  if current_buf ~= buf then
    Log.debug("SKIP: buffer changed (request=%d current=%d)", buf, current_buf)
    return
  end

  local row = suggestion.line - 1 -- Convert to 0-indexed

  -- Include count indicator if multiple edits pending
  local suffix = ""
  if total and total > 1 and current then
    suffix = string.format(" [%d/%d]", current, total)
  end

  if action == "insert" then
    -- INSERT action: mark insertion point and show preview
    Log.debug("insert: anchor='%s' position=%s insert='%s'", suggestion.anchor, suggestion.position, suggestion.insert)

    -- 1. Highlight the anchor text with StrideInsert (to show context)
    local anchor_start = suggestion.col_start
    local anchor_end = suggestion.col_end
    if suggestion.position == "after" then
      -- col_start/col_end is the insertion point (after anchor)
      -- We need to find anchor start for highlighting
      anchor_start = suggestion.col_start - #suggestion.anchor
      anchor_end = suggestion.col_start
    else
      -- position == "before": insertion point is at anchor start
      anchor_end = suggestion.col_start + #suggestion.anchor
    end

    -- Clamp to valid range
    anchor_start = math.max(0, anchor_start)

    local ok_hl, hl_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, anchor_start, {
      end_col = anchor_end,
      hl_group = "StrideInsert",
    })
    if ok_hl then
      M.remote_hl_id = hl_id
      Log.debug("insert highlight extmark=%d", hl_id)
    end

    -- 2. Show insertion preview as virtual text at insertion point
    local insert_text = suggestion.insert or suggestion.new
    local virt_col = suggestion.col_start

    -- Handle multi-line insertions
    local insert_lines = vim.split(insert_text, "\n")
    local preview_text = insert_lines[1]
    if #insert_lines > 1 then
      preview_text = preview_text .. " (+" .. (#insert_lines - 1) .. " lines)"
    end

    local ok_virt, virt_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, virt_col, {
      virt_text = { { " ← " .. preview_text .. suffix, "StrideRemoteSuggestion" } },
      virt_text_pos = "inline",
    })
    if ok_virt then
      M.remote_virt_id = virt_id
      Log.debug("insert virt_text extmark=%d", virt_id)
    end
  else
    -- REPLACE action: highlight original and show replacement
    Log.debug("replace: original='%s' new='%s'", suggestion.original, suggestion.new)

    -- 1. Highlight the original text with StrideReplace
    local ok_hl, hl_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, suggestion.col_start, {
      end_col = suggestion.col_end,
      hl_group = "StrideReplace",
    })
    if ok_hl then
      M.remote_hl_id = hl_id
      Log.debug("remote highlight extmark=%d", hl_id)
    else
      Log.debug("ERROR: failed to set remote highlight: %s", tostring(hl_id))
    end

    -- 2. Add inline virtual text showing the replacement (right after original)
    local ok_virt, virt_id = pcall(vim.api.nvim_buf_set_extmark, buf, ns_id_remote, row, suggestion.col_end, {
      virt_text = { { " → " .. suggestion.new .. suffix, "StrideRemoteSuggestion" } },
      virt_text_pos = "inline",
    })
    if ok_virt then
      M.remote_virt_id = virt_id
      Log.debug("remote virt_text extmark=%d", virt_id)
    else
      Log.debug("ERROR: failed to set remote virt_text: %s", tostring(virt_id))
    end
  end

  M.current_buf = buf
  M.current_suggestion = {
    text = suggestion.new,
    row = row,
    col = suggestion.col_start,
    lines = vim.split(suggestion.new, "\n"),
    buf = buf,
    is_remote = true,
    target_line = suggestion.line,
    original = suggestion.original,
    new = suggestion.new,
    col_start = suggestion.col_start,
    col_end = suggestion.col_end,
    action = action,
    anchor = suggestion.anchor,
    position = suggestion.position,
    insert = suggestion.insert,
  }

  _setup_esc_mapping(buf)

  -- Place gutter sign
  _place_sign(buf, row)

  -- Notify via fidget if available
  if current and total then
    _notify_fidget(current, total)
  end

  Log.debug("SUCCESS: remote %s suggestion rendered for line %d", action, suggestion.line)
end

---Get remote namespace ID (for testing)
---@return number
function M.get_ns_id_remote()
  return ns_id_remote
end

return M
