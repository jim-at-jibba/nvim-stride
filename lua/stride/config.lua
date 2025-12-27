---@class Stride.SignConfig
---@field icon? string Gutter icon (default: "󰷺" if nerd font, ">" otherwise)
---@field hl? string Highlight group (default: "StrideSign")

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
---@field mode? "completion"|"refactor"|"both" Operational mode (default: "completion")
---@field show_remote? boolean Show remote suggestions in refactor mode (default: true)
---@field max_tracked_changes? number Max changes to track across buffers (default: 10)
---@field token_budget? number Max tokens (~3 chars each) for change history in prompt (default: 1000)
---@field small_file_threshold? number Send whole file if <= this many lines (default: 200)
---@field sign? Stride.SignConfig|false Gutter sign config (false to disable)

local M = {}

---@type Stride.Config
M.defaults = {
  api_key = os.getenv("CEREBRAS_API_KEY"),
  endpoint = "https://api.cerebras.ai/v1/chat/completions",
  model = "gpt-oss-120b",
  debounce_ms = 300,
  accept_keymap = "<Tab>",
  context_lines = 30,
  use_treesitter = true,
  disabled_filetypes = {},
  debug = false,
  mode = "completion",
  show_remote = true,
  max_tracked_changes = 10,
  token_budget = 1000,
  small_file_threshold = 200,
  sign = {
    icon = nil, -- nil = auto-detect nerd font
    hl = "StrideSign",
  },
}

---@type Stride.Config
M.options = {}

---@param opts Stride.Config|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
