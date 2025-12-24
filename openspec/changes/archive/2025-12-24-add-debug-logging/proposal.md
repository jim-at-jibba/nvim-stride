# Change: Add debug logging system

## Why

Users cannot tell if stride.nvim is working correctly. There's no visibility into:
- When predictions are triggered
- What context is sent to the API
- API request/response lifecycle
- Why suggestions may be discarded (stale checks)
- UI rendering events

## What Changes

- Add `debug` boolean config option (default: false)
- Create centralized `log` module with leveled logging (DEBUG, INFO, WARN, ERROR)
- Instrument all modules with comprehensive debug logging:
  - `init.lua`: autocmd triggers, filetype checks
  - `utils.lua`: context extraction, Treesitter expansion
  - `client.lua`: API requests, retries, stale checks, responses
  - `ui.lua`: render/clear events, extmark lifecycle
- Logs write to `:messages` when `debug = true`

## Impact

- Affected specs: config, logging (new capability)
- Affected code: `lua/stride/config.lua`, `lua/stride/log.lua` (new), all existing modules
