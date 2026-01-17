local Geo = require("stride.geo")
local Point = Geo.Point
local Range = Geo.Range

describe("geo", function()
  describe("Point", function()
    describe("new", function()
      it("creates a point with 1-indexed row and col", function()
        local p = Point.new(1, 1)
        assert.equal(1, p.row)
        assert.equal(1, p.col)
      end)

      it("stores coordinates as provided", function()
        local p = Point.new(5, 10)
        assert.equal(5, p.row)
        assert.equal(10, p.col)
      end)
    end)

    describe("from_cursor", function()
      it("converts from cursor format (1-indexed row, 0-indexed col)", function()
        -- Mock nvim_win_get_cursor
        local mock_cursor = { 3, 5 }
        vim.api.nvim_win_get_cursor = function()
          return mock_cursor
        end

        local p = Point.from_cursor()
        assert.equal(3, p.row)  -- row stays 1-indexed
        assert.equal(6, p.col)  -- col becomes 1-indexed (5 + 1)
      end)

      it("handles cursor at position 0", function()
        vim.api.nvim_win_get_cursor = function()
          return { 1, 0 }
        end

        local p = Point.from_cursor()
        assert.equal(1, p.row)
        assert.equal(1, p.col)
      end)
    end)

    describe("from_ts", function()
      it("converts from treesitter 0-indexed to 1-indexed", function()
        local p = Point.from_ts(0, 0)
        assert.equal(1, p.row)
        assert.equal(1, p.col)
      end)

      it("handles arbitrary positions", function()
        local p = Point.from_ts(4, 7)
        assert.equal(5, p.row)   -- 4 + 1
        assert.equal(8, p.col)   -- 7 + 1
      end)
    end)

    describe("to_vim", function()
      it("converts to 0-indexed for vim buffer APIs", function()
        local p = Point.new(1, 1)
        local r, c = p:to_vim()
        assert.equal(0, r)
        assert.equal(0, c)
      end)

      it("converts arbitrary positions", function()
        local p = Point.new(5, 10)
        local r, c = p:to_vim()
        assert.equal(4, r)   -- 5 - 1
        assert.equal(9, c)   -- 10 - 1
      end)
    end)

    describe("to_ts", function()
      it("converts to 0-indexed for treesitter", function()
        local p = Point.new(1, 1)
        local r, c = p:to_ts()
        assert.equal(0, r)
        assert.equal(0, c)
      end)

      it("handles arbitrary positions", function()
        local p = Point.new(3, 7)
        local r, c = p:to_ts()
        assert.equal(2, r)   -- 3 - 1
        assert.equal(6, c)   -- 7 - 1
      end)
    end)

    describe("to_cursor", function()
      it("converts to cursor format (1-indexed row, 0-indexed col)", function()
        local p = Point.new(1, 1)
        local r, c = p:to_cursor()
        assert.equal(1, r)
        assert.equal(0, c)
      end)

      it("handles arbitrary positions", function()
        local p = Point.new(4, 8)
        local r, c = p:to_cursor()
        assert.equal(4, r)   -- row stays 1-indexed
        assert.equal(7, c)   -- col becomes 0-indexed (8 - 1)
      end)
    end)

    describe("__eq", function()
      it("returns true for equal points", function()
        local p1 = Point.new(3, 5)
        local p2 = Point.new(3, 5)
        assert.is_true(p1 == p2)
      end)

      it("returns false for different rows", function()
        local p1 = Point.new(3, 5)
        local p2 = Point.new(4, 5)
        assert.is_false(p1 == p2)
      end)

      it("returns false for different cols", function()
        local p1 = Point.new(3, 5)
        local p2 = Point.new(3, 6)
        assert.is_false(p1 == p2)
      end)
    end)

    describe("__lt", function()
      it("returns true when row is less", function()
        local p1 = Point.new(2, 10)
        local p2 = Point.new(3, 1)
        assert.is_true(p1 < p2)
      end)

      it("returns false when row is greater", function()
        local p1 = Point.new(4, 1)
        local p2 = Point.new(3, 10)
        assert.is_false(p1 < p2)
      end)

      it("compares by col when rows are equal", function()
        local p1 = Point.new(3, 2)
        local p2 = Point.new(3, 5)
        assert.is_true(p1 < p2)
      end)

      it("returns false for equal points", function()
        local p1 = Point.new(3, 5)
        local p2 = Point.new(3, 5)
        assert.is_false(p1 < p2)
      end)

      it("handles same row with larger col", function()
        local p1 = Point.new(3, 8)
        local p2 = Point.new(3, 5)
        assert.is_false(p1 < p2)
      end)
    end)

    describe("roundtrip conversions", function()
      it("Point.new -> to_vim -> Point.from_ts preserves position", function()
        local original = Point.new(5, 10)
        local r, c = original:to_vim()
        local recovered = Point.from_ts(r, c)
        assert.equal(original.row, recovered.row)
        assert.equal(original.col, recovered.col)
      end)

      it("Point.new -> to_ts -> Point.from_ts preserves position", function()
        local original = Point.new(3, 7)
        local r, c = original:to_ts()
        local recovered = Point.from_ts(r, c)
        assert.equal(original.row, recovered.row)
        assert.equal(original.col, recovered.col)
      end)
    end)
  end)

  describe("Range", function()
    local buf

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if buf then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)

    describe("new", function()
      it("creates a range with buffer and start/end points", function()
        local start = Point.new(1, 1)
        local end_ = Point.new(3, 10)
        local r = Range.new(buf, start, end_)
        assert.equal(buf, r.buf)
        assert.equal(start, r.start)
        assert.equal(end_, r.end_)
      end)
    end)

    describe("from_ts_node", function()
      it("creates range from treesitter node with range() method", function()
        local mock_node = {
          range = function()
            return 1, 2, 4, 8  -- sr, sc, er, ec (0-indexed)
          end
        }

        local r = Range.from_ts_node(mock_node, buf)
        assert.equal(buf, r.buf)
        assert.equal(2, r.start.row)   -- 1 + 1
        assert.equal(3, r.start.col)   -- 2 + 1
        assert.equal(5, r.end_.row)    -- 4 + 1
        assert.equal(9, r.end_.col)    -- 8 + 1
      end)

      it("handles node at (0,0)", function()
        local mock_node = {
          range = function()
            return 0, 0, 0, 5
          end
        }

        local r = Range.from_ts_node(mock_node, buf)
        assert.equal(1, r.start.row)
        assert.equal(1, r.start.col)
        assert.equal(1, r.end_.row)
        assert.equal(6, r.end_.col)
      end)
    end)

    describe("contains", function()
      it("returns true for point inside range", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local inside = Point.new(3, 5)
        assert.is_true(r:contains(inside))
      end)

      it("returns true for point on start boundary", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local on_start = Point.new(2, 3)
        assert.is_true(r:contains(on_start))
      end)

      it("returns true for point on end boundary", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local on_end = Point.new(5, 7)
        assert.is_true(r:contains(on_end))
      end)

      it("returns false for point before range", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local before = Point.new(2, 2)
        assert.is_false(r:contains(before))
      end)

      it("returns false for point after range", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local after = Point.new(5, 8)
        assert.is_false(r:contains(after))
      end)

      it("returns false for point on previous row", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local prev_row = Point.new(1, 10)
        assert.is_false(r:contains(prev_row))
      end)

      it("returns false for point on next row", function()
        local start = Point.new(2, 3)
        local end_ = Point.new(5, 7)
        local r = Range.new(buf, start, end_)

        local next_row = Point.new(6, 1)
        assert.is_false(r:contains(next_row))
      end)

      it("handles single-line range", function()
        local start = Point.new(3, 2)
        local end_ = Point.new(3, 8)
        local r = Range.new(buf, start, end_)

        local inside = Point.new(3, 5)
        assert.is_true(r:contains(inside))

        local before = Point.new(3, 1)
        assert.is_false(r:contains(before))

        local after = Point.new(3, 9)
        assert.is_false(r:contains(after))
      end)
    end)

    describe("to_text", function()
      it("extracts single-line text from buffer", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "hello world", "line3" })

        local start = Point.new(2, 1)
        local end_ = Point.new(2, 11)
        local r = Range.new(buf, start, end_)

        local text = r:to_text()
        assert.equal("hello world", text)
      end)

      it("extracts partial single-line text", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "hello world", "line3" })

        local start = Point.new(2, 4)
        local end_ = Point.new(2, 8)
        local r = Range.new(buf, start, end_)

        local text = r:to_text()
        assert.equal("lo wo", text)
      end)

      it("extracts multi-line text", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first line", "middle line", "last line" })

        local start = Point.new(1, 1)
        local end_ = Point.new(3, 9)
        local r = Range.new(buf, start, end_)

        local text = r:to_text()
        assert.equal("first line\nmiddle line\nlast line", text)
      end)

      it("extracts partial multi-line text", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first line", "middle line", "last line" })

        local start = Point.new(1, 4)
        local end_ = Point.new(3, 4)
        local r = Range.new(buf, start, end_)

        local text = r:to_text()
        assert.equal("st line\nmiddle line\nlast", text)
      end)

      it("handles single-character range", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2" })

        local start = Point.new(1, 5)
        local end_ = Point.new(1, 5)
        local r = Range.new(buf, start, end_)

        local text = r:to_text()
        assert.equal("1", text)
      end)
    end)

    describe("replace_text", function()
      it("replaces single-line text", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "hello world", "line3" })

        local start = Point.new(2, 4)
        local end_ = Point.new(2, 8)
        local r = Range.new(buf, start, end_)

        r:replace_text({ "NEW" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "line1", "helNEWrld", "line3" }, lines)
      end)

      it("replaces with multiple lines", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "hello world", "line3" })

        local start = Point.new(2, 4)
        local end_ = Point.new(2, 8)
        local r = Range.new(buf, start, end_)

        r:replace_text({ "NEW1", "NEW2" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "line1", "helNEW1", "NEW2rld", "line3" }, lines)
      end)

      it("replaces multi-line range", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "line2", "line3", "line4" })

        local start = Point.new(2, 1)
        local end_ = Point.new(3, 5)
        local r = Range.new(buf, start, end_)

        r:replace_text({ "NEW" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "line1", "NEW", "line4" }, lines)
      end)

      it("deletes text when replacing with empty", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "hello world", "line3" })

        local start = Point.new(2, 4)
        local end_ = Point.new(2, 8)
        local r = Range.new(buf, start, end_)

        r:replace_text({ "" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "line1", "helrld", "line3" }, lines)
      end)

      it("inserts text at position when start == end", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line1", "hello world", "line3" })

        local start = Point.new(2, 6)
        local end_ = Point.new(2, 6)
        local r = Range.new(buf, start, end_)

        r:replace_text({ " NEW" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "line1", "hello NEWworld", "line3" }, lines)
      end)
    end)

    describe("line_count", function()
      it("returns 1 for single-line range", function()
        local start = Point.new(3, 2)
        local end_ = Point.new(3, 8)
        local r = Range.new(buf, start, end_)

        assert.equal(1, r:line_count())
      end)

      it("returns number of lines for multi-line range", function()
        local start = Point.new(2, 5)
        local end_ = Point.new(5, 3)
        local r = Range.new(buf, start, end_)

        assert.equal(4, r:line_count())  -- rows 2, 3, 4, 5
      end)

      it("handles range on consecutive rows", function()
        local start = Point.new(1, 1)
        local end_ = Point.new(2, 1)
        local r = Range.new(buf, start, end_)

        assert.equal(2, r:line_count())
      end)

      it("handles empty range on single line", function()
        local start = Point.new(3, 5)
        local end_ = Point.new(3, 5)
        local r = Range.new(buf, start, end_)

        assert.equal(1, r:line_count())
      end)
    end)

    describe("Range operations with buffers", function()
      it("extracts and replaces text correctly", function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "original text" })

        local start = Point.new(1, 1)
        local end_ = Point.new(1, 8)
        local r = Range.new(buf, start, end_)

        local original = r:to_text()
        assert.equal("original", original)

        r:replace_text({ "replaced" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "replaced text" }, lines)
      end)

      it("works with complex multi-line scenario", function()
        local content = {
          "function test()",
          "  local x = 1",
          "  return x",
          "end"
        }
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

        -- Extract function body
        local start = Point.new(2, 1)
        local end_ = Point.new(3, 10)
        local r = Range.new(buf, start, end_)

        local body = r:to_text()
        assert.equal("  local x = 1\n  return x", body)

        -- Replace body
        r:replace_text({ "  local y = 2", "  return y * 2" })

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.same({ "function test()", "  local y = 2", "  return y * 2", "end" }, lines)
      end)
    end)
  end)
end)
