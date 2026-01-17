local Geo = require("stride.geo")
local Point = Geo.Point
local Range = Geo.Range

---@class Stride.FunctionInfo
---@field range stride.geo.Range
---@field text string
---@field name string|nil

local M = {}

local FUNCTION_NODES = {
  ["function_declaration"] = true,
  ["function_definition"] = true,
  ["arrow_function"] = true,
  ["method_definition"] = true,
  ["function_expression"] = true,
  ["method_declaration"] = true,
  ["function_item"] = true,
}

---@param buf number
---@param point stride.geo.Point
---@return Stride.FunctionInfo|nil
function M.get_containing_function(buf, point)
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { point:to_ts() },
  })
  if not ok or not node then
    return nil
  end

  while node do
    local node_type = node:type()
    if FUNCTION_NODES[node_type] then
      local start_row, start_col, end_row, end_col = node:range()

      local range = Range.new(buf, Point.from_ts(start_row, start_col), Point.from_ts(end_row, end_col))

      local lines = vim.api.nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, {})
      local text = table.concat(lines, "\n")

      local name = M._get_function_name(node, buf)

      return {
        range = range,
        text = text,
        name = name,
      }
    end
    node = node:parent()
  end

  return nil
end

---@param filetype string
---@return boolean
function M.is_supported(filetype)
  local ok, parser = pcall(vim.treesitter.get_parser, 0, filetype)
  return ok and parser ~= nil
end

---@param node TSNode
---@param buf number
---@return string|nil
function M._get_function_name(node, buf)
  for child in node:iter_children() do
    local child_type = child:type()
    if child_type == "name" or child_type == "identifier" then
      local start_row, start_col, end_row, end_col = child:range()
      local text = vim.api.nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, {})
      return text[1]
    end
  end
  return nil
end

return M
