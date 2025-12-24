---@class Stride.Config
---@field api_key? string Cerebras API key (defaults to CEREBRAS_API_KEY env var)
---@field endpoint? string API endpoint URL
---@field model? string Model name for completions
---@field debounce_ms? number Debounce delay in milliseconds
---@field accept_keymap? string Keymap to accept suggestion
---@field context_lines? number Base context window size (lines before/after cursor)
---@field use_treesitter? boolean Use Treesitter for smart context expansion
---@field disabled_filetypes? string[] Filetypes to disable predictions
---@field debug? boolean Enable debug logging output

local M = {}

---@type Stride.Config
M.defaults = {
  api_key = os.getenv("CEREBRAS_API_KEY"),
  endpoint = "https://api.cerebras.ai/v1/chat/completions",
  model = "llama-3.3-70b",
  debounce_ms = 300,
  accept_keymap = "<Tab>",
  context_lines = 30,
  use_treesitter = true,
  disabled_filetypes = {},
  debug = false,
}

---@type Stride.Config
M.options = {}

---@param opts Stride.Config|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
