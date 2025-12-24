# Change: Implement V1 Ghost Text Prediction

## Why

stride.nvim needs its core functionality: real-time code completion suggestions using the Cerebras API with Treesitter-aware context capture. Users currently have no prediction capabilities.

## What Changes

### Phase 1: Foundation
- Add config module with API, UX, and feature flag defaults
- Add utils module with debounce and basic context extraction

### Phase 2: Smart Context
- Add Treesitter-aware context expansion
- Ensure function/class boundaries aren't cut mid-block

### Phase 3: API Client
- Add Cerebras API integration via plenary.curl
- Implement race condition guards and retry logic
- Request cancellation on cursor move

### Phase 4: Ghost Text UI
- Add extmark-based virtual text rendering
- Support inline + virtual lines for multi-line completions

### Phase 5: Core Integration
- Wire autocmds (TextChangedI, CursorMovedI, InsertLeave)
- Implement Tab acceptance keymap
- Add filetype disabling

## Impact

- Affected specs: config, context, client, ui, core (all new)
- Affected code: `lua/stride/` (complete rewrite of module.lua, init.lua → new architecture)
- Breaking: replaces placeholder hello() API with real functionality
