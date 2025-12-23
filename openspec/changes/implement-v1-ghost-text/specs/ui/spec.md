## ADDED Requirements

### Requirement: Ghost Text Rendering
The plugin SHALL render completion suggestions as virtual text.

#### Scenario: Single-line completion
- **WHEN** completion is one line
- **THEN** plugin renders inline virtual text after cursor

#### Scenario: Multi-line completion
- **WHEN** completion spans multiple lines
- **THEN** first line is inline, remaining lines are virtual lines below

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
