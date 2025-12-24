# context Specification

## Purpose
TBD - created by archiving change implement-v1-ghost-text. Update Purpose after archive.
## Requirements
### Requirement: Context Extraction
The plugin SHALL extract code context around the cursor for LLM prompts.

#### Scenario: Basic context capture
- **WHEN** cursor is at line 50 with 60-line context setting
- **THEN** plugin captures lines 0-110 (clamped to buffer bounds)

#### Scenario: Context split at cursor
- **WHEN** context is extracted
- **THEN** text before cursor is prefix, text after cursor is suffix

### Requirement: Treesitter Context Expansion
The plugin SHALL expand context boundaries to include complete function/class definitions when Treesitter is available.

#### Scenario: Function cut at top boundary
- **WHEN** naive top boundary cuts through a function definition
- **THEN** boundary expands upward to include full function signature

#### Scenario: Block cut at bottom boundary
- **WHEN** naive bottom boundary cuts through a code block
- **THEN** boundary expands downward to include block end

#### Scenario: Expansion limit
- **WHEN** expansion would exceed 50 additional lines
- **THEN** expansion is capped at 50 lines

#### Scenario: Treesitter unavailable
- **WHEN** buffer has no Treesitter parser
- **THEN** plugin falls back to naive line-based context

### Requirement: Debounce
The plugin SHALL debounce context extraction to avoid excessive API calls.

#### Scenario: Rapid typing
- **WHEN** user types multiple characters within 300ms
- **THEN** only one API request is made after typing stops

