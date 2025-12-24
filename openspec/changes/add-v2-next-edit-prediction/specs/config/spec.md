## MODIFIED Requirements

### Requirement: Configuration Options

The plugin SHALL provide configuration options for customizing behavior, including V2 features.

#### Scenario: Default configuration
- **WHEN** user calls setup() without options
- **THEN** defaults SHALL be applied including mode="completion"

#### Scenario: Custom configuration
- **WHEN** user provides options to setup()
- **THEN** provided options SHALL override defaults

#### Scenario: API key from environment
- **WHEN** api_key is not provided
- **THEN** CEREBRAS_API_KEY environment variable SHALL be used

## ADDED Requirements

### Requirement: Mode Configuration

The plugin SHALL support multiple operational modes via the mode option.

#### Scenario: Completion mode (default)
- **WHEN** mode is "completion" or not specified
- **THEN** plugin SHALL only provide cursor-local autocomplete (V1 behavior)
- **AND** history tracking SHALL be disabled

#### Scenario: Refactor mode
- **WHEN** mode is "refactor"
- **THEN** plugin SHALL only provide next-edit predictions (V2 behavior)
- **AND** cursor-local autocomplete SHALL be disabled

#### Scenario: Both mode
- **WHEN** mode is "both"
- **THEN** plugin SHALL provide both cursor-local autocomplete and next-edit predictions
- **AND** both suggestion types may be displayed simultaneously

### Requirement: Remote Suggestion Toggle

The plugin SHALL allow disabling remote suggestions via the show_remote option.

#### Scenario: Show remote enabled (default)
- **WHEN** show_remote is true or not specified
- **AND** mode includes refactor capability
- **THEN** remote suggestions SHALL be displayed

#### Scenario: Show remote disabled
- **WHEN** show_remote is false
- **THEN** remote suggestions SHALL NOT be displayed
- **AND** next-edit predictions SHALL still be computed (for future use)
