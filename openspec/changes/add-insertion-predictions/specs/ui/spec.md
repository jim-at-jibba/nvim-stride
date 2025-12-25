## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Ghost Text Rendering

The UI module SHALL render ghost text for local, remote replacement, and remote insertion suggestions.

#### Scenario: Render local suggestion
- **WHEN** completion text is received for current cursor position
- **THEN** inline ghost text SHALL be rendered after cursor
- **AND** multi-line suggestions SHALL use virtual lines

#### Scenario: Render remote replacement
- **WHEN** next-edit suggestion targets text to replace on a different line
- **THEN** original text on target line SHALL be highlighted with StrideReplace
- **AND** EOL virtual text SHALL show replacement with StrideRemoteSuggestion

#### Scenario: Render remote insertion
- **WHEN** next-edit suggestion targets an insertion point on a different line
- **THEN** insertion point SHALL be marked with StrideInsert
- **AND** virtual text SHALL preview inserted content with StrideRemoteSuggestion

#### Scenario: Clear any suggestion type
- **WHEN** clear() is called
- **THEN** all highlights and virtual text SHALL be removed regardless of suggestion type
