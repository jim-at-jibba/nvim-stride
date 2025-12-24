## 1. Core Infrastructure

- [x] 1.1 Add `debug` field to `Stride.Config` type annotation
- [x] 1.2 Add `debug = false` to `M.defaults` in config.lua

## 2. Logging Module

- [x] 2.1 Create `lua/stride/log.lua` with leveled logging (DEBUG, INFO, WARN, ERROR)
- [x] 2.2 Implement `log.debug()`, `log.info()`, `log.warn()`, `log.error()` functions
- [x] 2.3 Conditionally output based on `Config.options.debug`
- [x] 2.4 Format messages with `[stride]` prefix

## 3. Instrument Modules

- [x] 3.1 Add logging to `init.lua`: setup complete, autocmd triggers, filetype disabled
- [x] 3.2 Add logging to `utils.lua`: context extraction, Treesitter expansion details
- [x] 3.3 Add logging to `client.lua`: request start, retry attempts, stale discards, response received
- [x] 3.4 Add logging to `ui.lua`: render called, clear called, buffer validation

## 4. Validation

- [x] 4.1 Add tests for log module (debug on/off behavior)
- [x] 4.2 Manual test: enable debug, verify output in `:messages`
- [x] 4.3 Run `make test` to ensure no regressions
