-- Demo file for testing stride.nvim
-- Open this file in Neovim and run:
--   :luafile %
-- Then start typing in insert mode to see ghost text suggestions

-- Setup stride with a test configuration
require("stride").setup({
  -- Uncomment and set your API key if not using env var:
  -- api_key = "your-cerebras-api-key",

  debounce_ms = 300, -- Wait 300ms after typing stops
  context_lines = 60, -- Lines of context to send
  use_treesitter = true, -- Use Treesitter for smart context
  disabled_filetypes = { "markdown" }, -- Disable for these filetypes
})

print("stride.nvim loaded! Start typing in insert mode to see suggestions.")
print("Press <Tab> to accept a suggestion.")

--------------------------------------------------------------------------------
-- TEST AREA: Try typing below this line in insert mode
--------------------------------------------------------------------------------
local apple = "test"
print(apple)
-- Example 1: Try completing a function
-- Type "local function calc" and wait...
local function calculate_sum(a, b)
  -- Try typing "return" here and wait for suggestion
end

-- Example 2: Try completing a table
-- Position cursor after the comma and type a new key
local configTest1 = {
  name = "test",
  enabled = true,
  -- try typing here
}

print("Hello, World!", configTest1)

-- Example 3: Try completing a loop
-- Type "for i" and wait...
-- Example 4: Try completing an if statement
-- Type "if x" and wait...
-- Example 5: Try inside a function body
local function process_data(items)
  local results = {}
  -- Try typing "for" here and wait for the loop suggestion
  return results
end

-- Example 6: Multi-line completion test
-- Try typing "local M = {}" and see if it suggests module pattern
--------------------------------------------------------------------------------
-- Manual testing commands (run in command mode with :lua)
--------------------------------------------------------------------------------
--[[

-- Check if stride is loaded:
:lua print(vim.inspect(require("stride")))

-- Check current config:
:lua print(vim.inspect(require("stride.config").options))

-- Manually trigger context extraction:
:lua print(vim.inspect(require("stride.utils").get_context(10)))

-- Check UI state:
:lua print(vim.inspect(require("stride.ui").current_suggestion))

-- Clear any ghost text:
:lua require("stride.ui").clear()

--]]
