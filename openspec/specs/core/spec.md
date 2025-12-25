# core Specification

## Purpose
TBD - created by archiving change implement-v1-ghost-text. Update Purpose after archive.
## Requirements
### Requirement: Plugin Setup
The plugin SHALL initialize via setup() function.

#### Scenario: Successful setup
- **WHEN** user calls require("stride").setup()
- **THEN** plugin registers autocmds and keymaps

#### Scenario: Missing plenary
- **WHEN** plenary.nvim is not installed
- **THEN** plugin throws error with clear message

#### Scenario: Missing treesitter warning
- **WHEN** use_treesitter is true but nvim-treesitter not found
- **THEN** plugin warns and falls back to text mode

### Requirement: Automatic Triggering

The plugin SHALL trigger predictions on text changes in insert mode, supporting both completion and refactor modes.

#### Scenario: Typing triggers prediction
- **WHEN** user types in insert mode and pauses
- **THEN** plugin fetches prediction after debounce period

#### Scenario: Disabled filetype skipped
- **WHEN** current filetype is in disabled_filetypes
- **THEN** no prediction is triggered

#### Scenario: Refactor mode triggers history
- **WHEN** mode is "refactor" or "both"
- **AND** user types in insert mode
- **THEN** plugin SHALL compute diff and fetch next-edit prediction

#### Scenario: Completion mode skips history
- **WHEN** mode is "completion"
- **THEN** plugin SHALL NOT compute diff or fetch next-edit prediction

### Requirement: Tab Acceptance

The plugin SHALL accept suggestions with Tab key, supporting both local and remote suggestions.

#### Scenario: Accept single-line suggestion
- **WHEN** ghost text is visible and user presses Tab
- **THEN** suggestion text is inserted at cursor

#### Scenario: Accept multi-line suggestion
- **WHEN** multi-line ghost text is visible and user presses Tab
- **THEN** all lines are inserted and cursor moves to end

#### Scenario: No suggestion fallback
- **WHEN** no ghost text is visible and user presses Tab
- **THEN** normal Tab behavior occurs (indent/completion)

#### Scenario: Accept remote suggestion
- **WHEN** remote suggestion is visible on line N and user presses Tab
- **THEN** cursor SHALL jump to line N
- **AND** original text SHALL be replaced with new text
- **AND** suggestion SHALL be cleared

### Requirement: Event Cleanup
The plugin SHALL clear state on cursor movement and mode changes.

#### Scenario: Insert mode exit
- **WHEN** user leaves insert mode
- **THEN** ghost text is cleared and pending requests cancelled

#### Scenario: Cursor movement
- **WHEN** cursor moves in insert mode (without typing)
- **THEN** ghost text is cleared

