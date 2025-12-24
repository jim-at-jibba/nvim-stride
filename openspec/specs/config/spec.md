# config Specification

## Purpose
TBD - created by archiving change add-debug-logging. Update Purpose after archive.
## Requirements
### Requirement: Debug Configuration Option

The plugin SHALL provide a `debug` configuration option that controls debug logging output.

#### Scenario: Debug disabled by default
- **WHEN** user calls `require("stride").setup()` without options
- **THEN** `Config.options.debug` SHALL be `false`
- **AND** no debug messages SHALL be written to `:messages`

#### Scenario: Debug enabled via config
- **WHEN** user calls `require("stride").setup({ debug = true })`
- **THEN** `Config.options.debug` SHALL be `true`
- **AND** debug messages SHALL be written to `:messages`

### Requirement: Configuration Defaults
The plugin SHALL provide sensible defaults for all configuration options.

#### Scenario: Default configuration
- **WHEN** user calls setup() with no arguments
- **THEN** plugin uses default values (300ms debounce, Tab accept, 60 context lines)

### Requirement: API Key Configuration
The plugin SHALL read the Cerebras API key from CEREBRAS_API_KEY environment variable.

#### Scenario: API key from environment
- **WHEN** CEREBRAS_API_KEY is set
- **THEN** plugin uses that value for API authentication

#### Scenario: API key missing
- **WHEN** CEREBRAS_API_KEY is not set
- **THEN** plugin notifies user with error on first request

### Requirement: Configuration Merging
The plugin SHALL deep-merge user options with defaults.

#### Scenario: Partial override
- **WHEN** user provides { debounce_ms = 500 }
- **THEN** debounce_ms is 500 and all other values remain default

### Requirement: Filetype Disabling
The plugin SHALL allow users to disable predictions for specific filetypes.

#### Scenario: Disabled filetype
- **WHEN** user sets disabled_filetypes = {"markdown"}
- **THEN** no predictions trigger in markdown buffers

### Requirement: Treesitter Feature Flag
The plugin SHALL provide use_treesitter option to enable/disable AST-aware context.

#### Scenario: Treesitter disabled
- **WHEN** use_treesitter = false
- **THEN** plugin uses naive line-based context only

