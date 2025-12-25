# ui Specification

## Purpose
TBD - created by archiving change implement-v1-ghost-text. Update Purpose after archive.
## Requirements
### Requirement: Ghost Text Rendering

The UI module SHALL render ghost text for both local (at-cursor) and remote (away-from-cursor) suggestions.

#### Scenario: Render local suggestion
- **WHEN** completion text is received for current cursor position
- **THEN** inline ghost text SHALL be rendered after cursor
- **AND** multi-line suggestions SHALL use virtual lines

#### Scenario: Render remote suggestion
- **WHEN** next-edit suggestion targets a different line
- **THEN** original text on target line SHALL be highlighted with StrideReplace
- **AND** EOL virtual text SHALL show replacement with StrideRemoteSuggestion
- **AND** is_remote flag SHALL be set on suggestion state

#### Scenario: Clear remote suggestion
- **WHEN** clear() is called with remote suggestion active
- **THEN** both highlight and virtual text SHALL be removed

### Requirement: Ghost Text Clearing
The plugin SHALL clear ghost text on cursor movement or mode change.

#### Scenario: Cursor moves
- **WHEN** CursorMovedI event fires
- **THEN** ghost text is cleared

#### Scenario: Leave insert mode
- **WHEN** InsertLeave event fires
- **THEN** ghost text is cleared

### Requirement: Ghost Text Styling
The plugin SHALL render ghost text with Comment highlight group.

#### Scenario: Visual appearance
- **WHEN** ghost text is rendered
- **THEN** it uses "Comment" highlight group for dimmed appearance

### Requirement: Buffer Validity Check
The plugin SHALL verify buffer is valid before rendering.

#### Scenario: Buffer closed
- **WHEN** render is called with invalid buffer
- **THEN** plugin silently skips rendering

### Requirement: Insertion Rendering

The UI module SHALL render insertion suggestions with distinct visual styling.

#### Scenario: StrideInsert highlight group
- **WHEN** insertion suggestion is rendered
- **THEN** insertion point marker SHALL use StrideInsert highlight group
- **AND** highlight SHALL visually indicate insertion location (green/italic)

#### Scenario: Render inline insertion
- **WHEN** insertion suggestion targets text on a single line
- **THEN** insertion point SHALL be marked after/before anchor text
- **AND** virtual text SHALL preview the inserted content

#### Scenario: Render multi-line insertion
- **WHEN** insertion text contains newlines
- **THEN** virtual lines SHALL preview the full inserted content
- **AND** insertion marker SHALL indicate where content will appear

#### Scenario: Clear insertion suggestion
- **WHEN** clear() is called with insertion suggestion active
- **THEN** insertion marker and virtual text SHALL be removed

### Requirement: Remote Suggestion Highlighting

The UI module SHALL provide distinct visual styling for remote suggestions.

#### Scenario: StrideReplace highlight
- **WHEN** remote suggestion is rendered
- **THEN** original text SHALL be highlighted with StrideReplace group
- **AND** highlight SHALL visually indicate text to be replaced (red/strikethrough)

#### Scenario: StrideRemoteSuggestion highlight
- **WHEN** remote suggestion is rendered
- **THEN** EOL virtual text SHALL use StrideRemoteSuggestion group
- **AND** highlight SHALL visually indicate replacement text (cyan)

#### Scenario: Default highlight colors
- **WHEN** user has not customized highlight groups
- **THEN** StrideReplace SHALL default to red foreground
- **AND** StrideRemoteSuggestion SHALL default to cyan foreground

