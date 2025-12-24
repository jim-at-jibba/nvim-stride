# client Specification

## Purpose
TBD - created by archiving change implement-v1-ghost-text. Update Purpose after archive.
## Requirements
### Requirement: Cerebras API Integration
The plugin SHALL send completion requests to the Cerebras API.

#### Scenario: Successful request
- **WHEN** context is sent with valid API key
- **THEN** plugin receives and parses completion response

### Requirement: Request Cancellation
The plugin SHALL cancel in-flight requests when user continues typing.

#### Scenario: Cancel on keystroke
- **WHEN** new TextChangedI fires while request is pending
- **THEN** previous request is cancelled

### Requirement: Stale Response Guard
The plugin SHALL discard responses if cursor has moved since request was made.

#### Scenario: Cursor moved during request
- **WHEN** response arrives but cursor position differs from request time
- **THEN** response is discarded, no ghost text rendered

#### Scenario: Buffer changed during request
- **WHEN** response arrives but user switched buffers
- **THEN** response is discarded

### Requirement: Retry Logic
The plugin SHALL retry failed requests with exponential backoff.

#### Scenario: Server error
- **WHEN** API returns 5xx error
- **THEN** plugin retries up to 3 times (100ms, 200ms, 400ms delays)

#### Scenario: Client error
- **WHEN** API returns 4xx error
- **THEN** plugin does not retry and notifies user

### Requirement: Error Notifications
The plugin SHALL notify users of API errors.

#### Scenario: Invalid API key
- **WHEN** API returns 401
- **THEN** plugin shows "Invalid API key" notification

#### Scenario: Rate limited
- **WHEN** API returns 429
- **THEN** plugin shows "Rate limited" notification

