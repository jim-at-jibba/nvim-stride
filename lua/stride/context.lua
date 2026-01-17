local Geo = require("stride.geo")
local Point = Geo.Point
local Treesitter = require("stride.treesitter")
local Config = require("stride.config")

local function _get_relative_path(buf)
  local full_path = vim.api.nvim_buf_get_name(buf)
  if full_path == "" then
    return "[buffer]"
  end
  local cwd = vim.fn.getcwd()
  local cwd_with_slash = cwd .. "/"
  if full_path:sub(1, #cwd_with_slash) == cwd_with_slash then
    return full_path:sub(#cwd_with_slash + 1)
  end
  return full_path
end

local _agent_cache = {}

local function _discover_agent_context(file_path)
  local context_files = Config.options.context_files
  if not context_files or context_files == false then
    return nil
  end

  if type(context_files) ~= "table" then
    context_files = { "AGENTS.md" }
  end

  if file_path == "[buffer]" then
    return nil
  end

  local cwd = vim.fn.getcwd()
  local current_dir = cwd .. "/" .. vim.fn.fnamemodify(file_path, ":h")

  while current_dir ~= cwd and current_dir ~= current_dir:match("^(.*)/") do
    for _, filename in ipairs(context_files) do
      local file_path_full = current_dir .. "/" .. filename
      local stat = vim.loop.fs_stat(file_path_full)
      if stat and stat.type == "file" then
        if _agent_cache[file_path_full] then
          return _agent_cache[file_path_full]
        end

        local ok, lines = pcall(vim.fn.readfile, file_path_full)
        if ok then
          local content = table.concat(lines, "\n")
          if #content > 2000 then
            content = content:sub(1, 2000)
          end

          _agent_cache[file_path_full] = content
          return content
        end
      end
    end

    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end

  -- Also check the project root (cwd) itself
  for _, filename in ipairs(context_files) do
    local file_path_full = cwd .. "/" .. filename
    local stat = vim.loop.fs_stat(file_path_full)
    if stat and stat.type == "file" then
      if _agent_cache[file_path_full] then
        return _agent_cache[file_path_full]
      end
      local ok, lines = pcall(vim.fn.readfile, file_path_full)
      if ok then
        local content = table.concat(lines, "\n")
        if #content > 2000 then
          content = content:sub(1, 2000)
        end
        _agent_cache[file_path_full] = content
        return content
      end
    end
  end

  return nil
end

---@class Stride.PredictionContext
---@field buf number
---@field cursor stride.geo.Point
---@field filetype string
---@field file_path string Relative path from cwd
---@field containing_function? Stride.FunctionInfo
---@field agent_context? string
local Context = {}
Context.__index = Context

---@return Stride.PredictionContext
function Context.from_current_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = Point.from_cursor()
  local filetype = vim.bo[buf].filetype
  local file_path = _get_relative_path(buf)
  local containing_function = Treesitter.get_containing_function(buf, cursor)
  local agent_context = _discover_agent_context(file_path)

  local self = setmetatable({
    buf = buf,
    cursor = cursor,
    filetype = filetype,
    file_path = file_path,
    containing_function = containing_function,
    agent_context = agent_context,
  }, Context)

  return self
end

---@return string|nil
function Context:get_function_text()
  if self.containing_function then
    return self.containing_function.text
  end
  return nil
end

---@return string|nil
function Context:get_agent_context()
  return self.agent_context
end
---@param start_line number
---@param end_line number
---@return string
function Context:build_prompt_context(start_line, end_line)
  local vim_start = start_line - 1
  local vim_end = end_line
  local lines = vim.api.nvim_buf_get_lines(self.buf, vim_start, vim_end, false)

  local result = {}
  for i, line in ipairs(lines) do
    local line_num = start_line + i - 1
    local display_line = line

    -- Mark cursor position with │
    if line_num == self.cursor.row then
      local col = math.min(self.cursor.col - 1, #line)
      display_line = line:sub(1, col) .. "│" .. line:sub(col + 1)
    end

    table.insert(result, string.format("%d: %s", line_num, display_line))
  end

  return table.concat(result, "\n")
end

local M = {}
M.Context = Context
M.clear_cache = function()
  _agent_cache = {}
end

return M
