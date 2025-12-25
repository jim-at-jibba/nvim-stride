## MODIFIED Requirements

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

## ADDED Requirements

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
