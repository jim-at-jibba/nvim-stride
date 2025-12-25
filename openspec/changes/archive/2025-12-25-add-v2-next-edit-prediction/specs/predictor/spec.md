## ADDED Requirements

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
