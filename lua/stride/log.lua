---@class Stride.Log
---Centralized logging module for stride.nvim
local M = {}

---@type file*|nil
M._file = nil

---Get log file path
---@return string
local function _get_log_path()
  local cache_dir = vim.fn.stdpath("cache")
  return cache_dir .. "/stride.log"
end

---Ensure log file is open
---@return file*|nil
local function _ensure_file()
  if M._file then
    return M._file
  end

  local path = _get_log_path()
  local file, err = io.open(path, "a")
  if not file then
    vim.notify("[stride] Failed to open log file: " .. (err or "unknown"), vim.log.levels.WARN)
    return nil
  end

  M._file = file
  return file
end

---Format and output a log message to file
---@param level string Log level prefix
---@param msg string Format string
---@param ... any Format arguments
local function _log(level, msg, ...)
  local Config = require("stride.config")
  if not Config.options.debug then
    return
  end

  local file = _ensure_file()
  if not file then
    return
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local formatted = string.format(msg, ...)
  local output = string.format("[%s] %s: %s\n", timestamp, level, formatted)

  file:write(output)
  file:flush()
end

---Log debug message (only when debug=true)
---@param msg string Format string
---@param ... any Format arguments
function M.debug(msg, ...)
  _log("DEBUG", msg, ...)
end

---Log info message (only when debug=true)
---@param msg string Format string
---@param ... any Format arguments
function M.info(msg, ...)
  _log("INFO", msg, ...)
end

---Log warning message (always shown in :messages, also logged to file)
---@param msg string Format string
---@param ... any Format arguments
function M.warn(msg, ...)
  local formatted = string.format(msg, ...)
  vim.notify("[stride] " .. formatted, vim.log.levels.WARN, { title = "stride.nvim" })
  _log("WARN", msg, ...)
end

---Log error message (always shown in :messages, also logged to file)
---@param msg string Format string
---@param ... any Format arguments
function M.error(msg, ...)
  local formatted = string.format(msg, ...)
  vim.notify("[stride] " .. formatted, vim.log.levels.ERROR, { title = "stride.nvim" })
  _log("ERROR", msg, ...)
end

---Get the log file path (useful for users)
---@return string
function M.get_path()
  return _get_log_path()
end

---Close the log file
function M.close()
  if M._file then
    M._file:close()
    M._file = nil
  end
end

return M
