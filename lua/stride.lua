-- main module file
local module = require("stride.module")

---@class Stride.Config
---@field opt string Your config option
local config = {
  opt = "Hello!",
}

---@class Stride
local M = {}

---@type Stride.Config
M.config = config

---@param args Stride.Config?
-- you can define your setup function here. Usually configurations can be merged, accepting outside params and
-- you can also put some validation here for those.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

M.hello = function()
  return module.my_first_function(M.config.opt)
end

return M
