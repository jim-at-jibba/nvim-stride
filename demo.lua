-- Demo file for testing stride.nvim
-- Open this file in Neovim and run:
--   :luafile %
-- Then start typing in insert mode to see ghost text suggestions

-- Setup stride with a test configuration
-- MODE OPTIONS:
--   "completion" (V1) - ghost text at cursor (default)
--   "refactor"   (V2) - next-edit prediction
--   "both"            - V1 + V2 together
require("stride").setup({
  -- Uncomment and set your API key if not using env var:
  -- api_key = "your-cerebras-api-key",

  debounce_ms = 300, -- Wait 300ms after typing stops
  context_lines = 60, -- Lines of context to send
  use_treesitter = true, -- Use Treesitter for smart context
  disabled_filetypes = { "markdown" }, -- Disable for these filetypes

  -- V2: Refactor mode settings
  mode = "refactor", -- Try "refactor" or "both" for V2 features
  show_remote = true, -- Show remote suggestions
  debug = true, -- Enable debug logging (check :messages)

  -- V2: Tracking settings
  max_tracked_changes = 10, -- Max edits to track
  token_budget = 1000, -- Max tokens for change history in prompt
  small_file_threshold = 200, -- Files <= this send whole content
})

print("stride.nvim loaded! Mode: " .. require("stride.config").options.mode)
print("Press <Tab> to accept a suggestion.")
print("Press <Esc> to dismiss a remote suggestion.")

--------------------------------------------------------------------------------
-- V1 TEST AREA: Completion mode (ghost text at cursor)
--------------------------------------------------------------------------------
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
-- V2 TEST AREA: Refactor mode (next-edit prediction)
--------------------------------------------------------------------------------
-- HOW V2 WORKS:
-- 1. Edits are tracked in real-time via nvim_buf_attach
-- 2. On InsertLeave, stride predicts your next edit based on recent changes
-- 3. Remote suggestion appears: original strikethrough, replacement at EOL
-- 4. Press Tab to accept, Esc to dismiss
-- 5. :StrideClear clears all tracked changes

-- TEST 1: Variable rename propagation
-- 1. Go to line with "local apple" and change "apple" to "orange"
-- 2. Exit insert mode - stride predicts updating other "apple" references
-- 3. Press Tab to accept the suggestion

local apple = "fruit"
local apple_count = 5
print(apple)
print("I have " .. apple_count .. " " .. apple .. "s")

local function get_fruit()
  return apple
end

-- TEST 2: Function rename
-- 1. Rename "get_apple" to "get_fruit" above
-- 2. Exit insert mode - stride suggests updating the call below

local my_value = get_fruit()
print(my_value)

-- TEST 3: String/constant rename
-- 1. Change "error" to "warning" on the first log line
-- 2. Exit insert mode - stride suggests updating related occurrences

local function handle_response(status)
  if status == "error" then
    print("[error] Something went wrong")
    return "error"
  end
  return "success"
end
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

-- V2: Check tracked changes:
:lua print(vim.inspect(require("stride.history").get_changes()))

-- V2: Check change count:
:lua print(require("stride.history").get_change_count())

-- V2: Get changes formatted for prompt:
:lua print(require("stride.history").get_changes_for_prompt())

-- V2: Clear all tracked changes:
:lua require("stride.history").clear()
-- Or use command:
:StrideClear

--]]
