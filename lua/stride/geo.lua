---@class stride.geo.Point
---@field row number
---@field col number
local Point = {}
Point.__index = Point

---@param row number
---@param col number
---@return stride.geo.Point
function Point.new(row, col)
  return setmetatable({ row = row, col = col }, Point)
end

---@return stride.geo.Point
function Point.from_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return Point.new(cursor[1], cursor[2] + 1)
end

---@param row number 0-indexed from treesitter
---@param col number 0-indexed from treesitter
---@return stride.geo.Point
function Point.from_ts(row, col)
  return Point.new(row + 1, col + 1)
end

---@return number, number (row-1, col-1) for nvim_buf_* APIs
function Point:to_vim()
  return self.row - 1, self.col - 1
end

---@return number, number (row-1, col-1) for treesitter
function Point:to_ts()
  return self.row - 1, self.col - 1
end

---@return number, number (row, col-1) for nvim_win_set_cursor
function Point:to_cursor()
  return self.row, self.col - 1
end

---@param other stride.geo.Point
---@return boolean
function Point:__eq(other)
  return self.row == other.row and self.col == other.col
end

---@param other stride.geo.Point
---@return boolean
function Point:__lt(other)
  return self.row < other.row or (self.row == other.row and self.col < other.col)
end

---@param other stride.geo.Point
---@return boolean
function Point:__le(other)
  return self.row < other.row or (self.row == other.row and self.col <= other.col)
end

---@class stride.geo.Range
---@field buf number
---@field start stride.geo.Point
---@field end_ stride.geo.Point
local Range = {}
Range.__index = Range

---@param buf number
---@param start_point stride.geo.Point
---@param end_point stride.geo.Point
---@return stride.geo.Range
function Range.new(buf, start_point, end_point)
  return setmetatable({ buf = buf, start = start_point, end_ = end_point }, Range)
end

---@param node TSNode
---@param buf number
---@return stride.geo.Range
function Range.from_ts_node(node, buf)
  local start_row, start_col, end_row, end_col = node:range()
  return Range.new(buf, Point.from_ts(start_row, start_col), Point.from_ts(end_row, end_col))
end

---@param point stride.geo.Point
---@return boolean
function Range:contains(point)
  return self.start <= point and point <= self.end_
end

---@return string
function Range:to_text()
  local start_row, start_col = self.start:to_vim()
  local end_row, end_col = self.end_:to_vim()
  return table.concat(vim.api.nvim_buf_get_text(self.buf, start_row, start_col, end_row, end_col + 1, {}), "\n")
end

---@param lines string[]
function Range:replace_text(lines)
  local start_row, start_col = self.start:to_vim()
  local end_row, end_col = self.end_:to_vim()
  vim.api.nvim_buf_set_text(self.buf, start_row, start_col, end_row, end_col + 1, lines)
end

---@return number
function Range:line_count()
  return self.end_.row - self.start.row + 1
end

local M = {}
M.Point = Point
M.Range = Range
return M
