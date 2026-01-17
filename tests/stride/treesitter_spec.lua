local Treesitter = require("stride.treesitter")
local Geo = require("stride.geo")
local Point = Geo.Point

describe("treesitter", function()
  local buf

  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  describe("get_containing_function", function()
    it("returns function info when cursor inside Lua function", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "local function foo()",
        "  local x = 1",
        "  return x",
        "end",
      })
      
      local point = Point.new(2, 3)
      local info = Treesitter.get_containing_function(buf, point)
      
      if info then
        assert.is_not_nil(info.range)
        assert.is_not_nil(info.text)
        assert.equals("foo", info.name)
      end
    end)
    
    it("returns nil when not inside function", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "local x = 1",
        "local y = 2",
      })
      
      local point = Point.new(1, 1)
      local info = Treesitter.get_containing_function(buf, point)
      assert.is_nil(info)
    end)
    
    it("returns innermost function when cursor in nested function", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "local function outer()",
        "  local function inner()",
        "    local x = 1",
        "    return x",
        "  end",
        "  return inner()",
        "end",
      })
      
      local point = Point.new(3, 5)
      local info = Treesitter.get_containing_function(buf, point)
      
      if info then
        assert.equals("inner", info.name)
      end
    end)
  end)

  describe("is_supported", function()
    it("returns true for lua", function()
      local supported = Treesitter.is_supported("lua")
      assert.is_boolean(supported)
    end)
    
    it("returns true for javascript", function()
      local supported = Treesitter.is_supported("javascript")
      assert.is_boolean(supported)
    end)
    
    it("returns true for typescript", function()
      local supported = Treesitter.is_supported("typescript")
      assert.is_boolean(supported)
    end)
    
    it("returns true for python", function()
      local supported = Treesitter.is_supported("python")
      assert.is_boolean(supported)
    end)
    
    it("returns true for go", function()
      local supported = Treesitter.is_supported("go")
      assert.is_boolean(supported)
    end)
    
    it("returns true for rust", function()
      local supported = Treesitter.is_supported("rust")
      assert.is_boolean(supported)
    end)
  end)

  describe("is_inside_comment_or_string", function()
    it("returns true for position inside lua comment", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "-- this is a comment",
        "local x = 1",
      })
      -- Force treesitter to parse
      vim.treesitter.get_parser(buf, "lua"):parse()

      local result = Treesitter.is_inside_comment_or_string(buf, 0, 5)
      assert.is_true(result)
    end)

    it("returns false for position in code", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "-- this is a comment",
        "local x = 1",
      })
      vim.treesitter.get_parser(buf, "lua"):parse()

      local result = Treesitter.is_inside_comment_or_string(buf, 1, 6)
      assert.is_false(result)
    end)

    it("returns true for position inside string", function()
      vim.bo[buf].filetype = "lua"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        'local msg = "hello world"',
      })
      vim.treesitter.get_parser(buf, "lua"):parse()

      local result = Treesitter.is_inside_comment_or_string(buf, 0, 15)
      assert.is_true(result)
    end)

    it("returns false when no parser available", function()
      vim.bo[buf].filetype = "unknown_filetype_xyz"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "-- comment",
      })

      local result = Treesitter.is_inside_comment_or_string(buf, 0, 5)
      assert.is_false(result)
    end)
  end)
end)
