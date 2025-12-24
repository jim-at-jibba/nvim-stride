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
The plugin SHALL trigger predictions on text changes in insert mode.

#### Scenario: Typing triggers prediction
- **WHEN** user types in insert mode and pauses
- **THEN** plugin fetches prediction after debounce period

#### Scenario: Disabled filetype skipped
- **WHEN** current filetype is in disabled_filetypes
- **THEN** no prediction is triggered

### Requirement: Tab Acceptance
The plugin SHALL accept suggestions with Tab key.

#### Scenario: Accept single-line suggestion
- **WHEN** ghost text is visible and user presses Tab
- **THEN** suggestion text is inserted at cursor

#### Scenario: Accept multi-line suggestion
- **WHEN** multi-line ghost text is visible and user presses Tab
- **THEN** all lines are inserted and cursor moves to end

#### Scenario: No suggestion fallback
- **WHEN** no ghost text is visible and user presses Tab
- **THEN** normal Tab behavior occurs (indent/completion)

### Requirement: Event Cleanup
The plugin SHALL clear state on cursor movement and mode changes.

#### Scenario: Insert mode exit
- **WHEN** user leaves insert mode
- **THEN** ghost text is cleared and pending requests cancelled

#### Scenario: Cursor movement
- **WHEN** cursor moves in insert mode (without typing)
- **THEN** ghost text is cleared

