# logging Specification

## Purpose
TBD - created by archiving change add-debug-logging. Update Purpose after archive.
## Requirements
### Requirement: Centralized Debug Logging

The plugin SHALL provide a centralized logging module (`lua/stride/log.lua`) for consistent debug output across all modules.

#### Scenario: Log module API
- **WHEN** any module requires `stride.log`
- **THEN** it SHALL expose `debug()`, `info()`, `warn()`, `error()` functions
- **AND** each function SHALL accept a format string and optional arguments

#### Scenario: Debug output format
- **WHEN** `log.debug("message")` is called with debug enabled
- **THEN** output SHALL be prefixed with `[stride]`
- **AND** output SHALL include the message text

#### Scenario: Debug output suppressed when disabled
- **WHEN** `Config.options.debug` is `false`
- **THEN** `log.debug()` calls SHALL produce no output
- **AND** `log.info()` calls SHALL produce no output

### Requirement: Module Instrumentation

All plugin modules SHALL emit debug logs at key execution points when debug mode is enabled.

#### Scenario: Init module logging
- **WHEN** debug is enabled
- **THEN** `init.lua` SHALL log: setup completion, autocmd triggers, filetype checks

#### Scenario: Client module logging
- **WHEN** debug is enabled
- **THEN** `client.lua` SHALL log: request start (with cursor position), retry attempts, stale response discards, successful response receipt

#### Scenario: Utils module logging
- **WHEN** debug is enabled
- **THEN** `utils.lua` SHALL log: context extraction (line counts), Treesitter expansion (before/after line numbers)

#### Scenario: UI module logging
- **WHEN** debug is enabled
- **THEN** `ui.lua` SHALL log: render calls (with position), clear calls, buffer validation failures

