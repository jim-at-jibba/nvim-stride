## ADDED Requirements

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
