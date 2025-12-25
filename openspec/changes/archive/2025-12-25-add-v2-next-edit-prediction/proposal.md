# Change: Add V2 Next Edit Prediction

## Why

V1 is a stateless autocomplete — it predicts what the user will type at the cursor. V2 introduces stateful "next edit" prediction: when the user renames `apple` to `orange` on line 1, the plugin should proactively highlight line 5 and offer to update related occurrences.

This transforms stride from "typing faster" (autocomplete) to "editing smarter" (auto-refactor).

## What Changes

- **ADDED** `history.lua`: Buffer snapshot and diff computation module
  - Snapshots buffer on InsertEnter
  - Computes structured diffs on idle/InsertLeave
  - Uses `vim.diff()` for efficient comparison

- **ADDED** `predictor.lua`: Next-edit prediction module
  - New prompt strategy: "given this edit, what else needs changing?"
  - JSON response format for target line/replacement
  - Separate from V1 completion client

- **MODIFIED** `ui.lua`: Remote suggestion rendering
  - New `render_remote()` for suggestions away from cursor
  - Highlight groups: `StrideReplace`, `StrideRemoteSuggestion`
  - Track `is_remote` state on suggestions

- **MODIFIED** `init.lua` (core): Jump-and-apply acceptance
  - Tab on remote suggestion: jump to target line + apply edit
  - "Tab-tab-tab" flow for chained edits
  - New autocmds for history snapshots

- **MODIFIED** `config.lua`: New V2 options
  - `mode`: "completion" | "refactor" | "both"
  - `show_remote`: Enable/disable remote suggestions

## Impact

- Affected specs: `history` (new), `predictor` (new), `core`, `ui`, `config`
- Affected code: All `lua/stride/` modules
- **Not breaking**: V1 completion mode remains default and fully functional
