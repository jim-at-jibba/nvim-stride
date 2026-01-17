# Demo Files

Test files for manually verifying stride.nvim functionality.

## Usage

1. Open a demo file in Neovim with stride configured
2. Follow the test instructions in comments
3. Check that predictions appear correctly

## Test Files

### node_fresh.ts

TypeScript file with 5 rename scenarios:

1. **Variable rename** - `app` → `server`
2. **Function rename** - `getUserById` → `fetchUser`
3. **Constant rename** - `MAX_RETRIES` → `RETRY_LIMIT`
4. **Type rename** - `ApiResponse` → `Response`
5. **Method rename** - `processItem` → `handleItem`

## Expected Behavior

- After renaming an identifier, stride should suggest updating other occurrences
- Comments and strings should be **skipped** (not suggested for replacement)
- Use `ciw` for best results (changes whole word at once)

## Debug Logging

Enable debug logging to see what stride is doing:

```lua
require("stride.log").set_level("DEBUG")
```

Check logs with `:messages` or tail the log file.
