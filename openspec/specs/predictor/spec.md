# predictor Specification

## Purpose
TBD - created by archiving change add-insertion-predictions. Update Purpose after archive.
## Requirements
### Requirement: Insertion Action Support

The predictor module SHALL support insertion predictions in addition to replacement predictions.

#### Scenario: Property addition triggers insertion
- **WHEN** user adds a new property to a class definition
- **AND** constructor calls exist that need the new property
- **THEN** predictor SHALL suggest inserting the property at call sites

#### Scenario: Parameter addition triggers insertion
- **WHEN** user adds a new parameter to a function signature
- **AND** function calls exist without the new parameter
- **THEN** predictor SHALL suggest inserting the argument at call sites

#### Scenario: Insert after anchor
- **WHEN** LLM returns action "insert" with position "after"
- **THEN** predictor SHALL locate anchor text and prepare insertion after it

#### Scenario: Insert before anchor
- **WHEN** LLM returns action "insert" with position "before"
- **THEN** predictor SHALL locate anchor text and prepare insertion before it

### Requirement: Extended Response Format

The predictor SHALL accept an extended JSON response format with explicit action types.

#### Scenario: Replace action format
- **WHEN** LLM identifies text to replace
- **THEN** response SHALL be: {"action": "replace", "find": "text", "replace": "new_text"}

#### Scenario: Insert action format
- **WHEN** LLM identifies text to insert
- **THEN** response SHALL be: {"action": "insert", "anchor": "text", "position": "after"|"before", "insert": "new_text"}

#### Scenario: No action format
- **WHEN** LLM determines no edit is needed
- **THEN** response SHALL be: {"action": null}

#### Scenario: Backward compatibility
- **WHEN** LLM returns old format without action field
- **AND** find and replace fields are present
- **THEN** predictor SHALL treat as replace action

### Requirement: Anchor Validation

The predictor SHALL validate anchor text for insertion predictions.

#### Scenario: Anchor exists
- **WHEN** LLM suggests insertion with anchor text
- **AND** anchor text exists in buffer (not on cursor line)
- **THEN** suggestion SHALL be accepted

#### Scenario: Anchor not found
- **WHEN** LLM suggests insertion with anchor text
- **AND** anchor text does not exist in buffer
- **THEN** suggestion SHALL be rejected

#### Scenario: Multiple anchors
- **WHEN** anchor text appears multiple times in buffer
- **THEN** predictor SHALL select occurrence closest to cursor (preferring after cursor)

### Requirement: Next Edit Prediction

The predictor module SHALL analyze recent edits and predict related changes needed elsewhere in the file, including both replacements and insertions.

#### Scenario: Rename propagation
- **WHEN** user renames variable "apple" to "orange" on line 10
- **AND** "apple" appears on line 20
- **THEN** predictor SHALL suggest replacing "apple" with "orange" on line 20

#### Scenario: Property addition propagation
- **WHEN** user adds field "age: int" to a dataclass on line 10
- **AND** constructor call exists on line 20 without age parameter
- **THEN** predictor SHALL suggest inserting "age=value" at the call site

#### Scenario: No related edits
- **WHEN** user makes an isolated edit with no related occurrences
- **THEN** predictor SHALL return null suggestion

#### Scenario: Invalid response handling
- **WHEN** LLM returns malformed JSON
- **THEN** predictor SHALL return null suggestion without error

### Requirement: Response Validation

The predictor SHALL validate LLM responses before returning suggestions.

#### Scenario: Line exists validation
- **WHEN** LLM suggests edit on line N
- **AND** line N does not exist in buffer
- **THEN** suggestion SHALL be rejected

#### Scenario: Original text validation
- **WHEN** LLM suggests replacing "foo" on line N
- **AND** line N does not contain "foo"
- **THEN** suggestion SHALL be rejected

#### Scenario: Self-edit rejection
- **WHEN** LLM suggests edit on the same line user just edited
- **THEN** suggestion SHALL be rejected (avoid circular suggestions)

