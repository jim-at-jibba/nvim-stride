---@class Stride.SignConfig
---@field icon? string Gutter icon (default: "󰷺" if nerd font, ">" otherwise)
---@field hl? string Highlight group (default: "StrideSign")

---@class Stride.Config
---@field api_key? string Cerebras API key (defaults to CEREBRAS_API_KEY env var)
---@field endpoint? string API endpoint URL
---@field model? string Model name for completions
---@field debounce_ms? number Debounce delay in milliseconds (insert mode)
---@field debounce_normal_ms? number Debounce delay for normal mode edits (default: 500)
---@field accept_keymap? string Keymap to accept suggestion
---@field context_lines? number Base context window size (lines before/after cursor)
---@field use_treesitter? boolean Use Treesitter for smart context expansion
---@field disabled_filetypes? table<string, boolean> Filetypes to disable predictions (pattern keys, true = disabled)
---@field disabled_buftypes? table<string, boolean> Buffer types to disable predictions
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
  debounce_normal_ms = 500,
  accept_keymap = "<Tab>",
  context_lines = 30,
  use_treesitter = true,
  disabled_filetypes = {
    -- File explorers
    ["NvimTree"] = true,
    ["neo%-tree"] = true,
    ["oil"] = true,
    ["dirvish"] = true,
    ["netrw"] = true,
    ["minifiles"] = true,

    -- Fuzzy finders / pickers
    ["TelescopePrompt"] = true,
    ["TelescopeResults"] = true,
    ["fzf"] = true,
    ["snacks_picker_input"] = true,

    -- UI inputs / selects
    ["DressingInput"] = true,
    ["DressingSelect"] = true,
    ["snacks_input"] = true,
    ["prompt"] = true,

    -- Plugin UIs
    ["lazy"] = true,
    ["mason"] = true,
    ["lspinfo"] = true,
    ["checkhealth"] = true,
    ["help"] = true,
    ["man"] = true,
    ["qf"] = true,

    -- Completion menus
    ["cmp_menu"] = true,
    ["cmp_docs"] = true,
    ["blink%-cmp%-menu"] = true,

    -- Git
    ["fugitive"] = true,
    ["gitcommit"] = true,
    ["gitrebase"] = true,
    ["NeogitCommitMessage"] = true,
    ["Neogit.*"] = true,
    ["Diffview.*"] = true,

    -- DAP / debugging
    ["dapui_.*"] = true,
    ["dap%-repl"] = true,

    -- Dashboard / greeter
    ["alpha"] = true,
    ["dashboard"] = true,
    ["snacks_dashboard"] = true,
    ["startify"] = true,
    ["ministarter"] = true,

    -- Notifications / messages
    ["noice"] = true,
    ["notify"] = true,

    -- AI chat windows
    ["copilot%-chat"] = true,
    ["Avante"] = true,

    -- Misc
    ["Trouble"] = true,
    ["trouble"] = true,
    ["undotree"] = true,
    ["aerial"] = true,
    ["Outline"] = true,
    ["spectre_panel"] = true,
    ["toggleterm"] = true,
    ["harpoon"] = true,
    ["query"] = true,
  },
  disabled_buftypes = {
    ["terminal"] = true,
    ["nofile"] = true,
    ["quickfix"] = true,
    ["prompt"] = true,
  },
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

---Convert array-style list to table format for backwards compatibility
---@param tbl table|nil
---@return table<string, boolean>
local function normalize_disabled_list(tbl)
  if not tbl then
    return {}
  end
  local result = {}
  for k, v in pairs(tbl) do
    if type(k) == "number" and type(v) == "string" then
      -- Array format: { "oil", "foo" } -> { ["oil"] = true, ["foo"] = true }
      result[v] = true
    else
      -- Table format: { ["oil"] = true }
      result[k] = v
    end
  end
  return result
end

---@param opts Stride.Config|nil
function M.setup(opts)
  opts = opts or {}

  -- Normalize user's disabled lists (handle array format)
  local user_filetypes = normalize_disabled_list(opts.disabled_filetypes)
  local user_buftypes = normalize_disabled_list(opts.disabled_buftypes)

  -- Remove from opts so tbl_deep_extend doesn't overwrite defaults
  opts.disabled_filetypes = nil
  opts.disabled_buftypes = nil

  -- Merge other options with defaults
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)

  -- Merge disabled lists: defaults + user additions
  M.options.disabled_filetypes = vim.tbl_extend("force", M.defaults.disabled_filetypes, user_filetypes)
  M.options.disabled_buftypes = vim.tbl_extend("force", M.defaults.disabled_buftypes, user_buftypes)
end

return M
