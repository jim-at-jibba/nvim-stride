## ADDED Requirements

### Requirement: Next Edit Prediction

The predictor module SHALL analyze recent edits and predict related changes needed elsewhere in the file.

#### Scenario: Rename propagation
- **WHEN** user renames variable "apple" to "orange" on line 10
- **AND** "apple" appears on line 20
- **THEN** predictor SHALL suggest changing line 20 to use "orange"

#### Scenario: No related edits
- **WHEN** user makes an isolated edit with no related occurrences
- **THEN** predictor SHALL return null suggestion

#### Scenario: Invalid response handling
- **WHEN** LLM returns malformed JSON
- **THEN** predictor SHALL return null suggestion without error

### Requirement: JSON Response Format

The predictor SHALL require strict JSON output from the LLM.

#### Scenario: Valid suggestion response
- **WHEN** LLM identifies a needed edit
- **THEN** response SHALL be JSON: {"line": N, "original": "text", "new": "replacement"}

#### Scenario: No suggestion response
- **WHEN** LLM determines no edit is needed
- **THEN** response SHALL be JSON: {"line": null}

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
