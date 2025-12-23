# Design: V1 Ghost Text Architecture

## Context

Building a real-time code completion plugin that must:
- Provide sub-10ms UI response (debounce handles API latency)
- Integrate with Treesitter for intelligent context
- Handle race conditions from rapid typing
- Work across all filetypes with graceful degradation

## Goals / Non-Goals

**Goals:**
- Ultra-low latency ghost text rendering
- Smart context capture via Treesitter
- Robust API error handling with retries
- Clean Tab acceptance UX

**Non-Goals:**
- Streaming responses (V2)
- Multiple completion providers (V2)
- Caching/prediction prefetching (V2)
- Custom highlight groups (V2)

## Decisions

### Module Architecture

```
lua/stride/
├── init.lua      # Public API, setup(), autocmds
├── config.lua    # User defaults, options merging
├── utils.lua     # Context extraction, Treesitter expansion, debounce
├── client.lua    # Cerebras API, request lifecycle
└── ui.lua        # Extmark rendering, ghost text state
```

**Rationale:** Matches flash.nvim pattern. Clear separation of concerns. Each module testable in isolation.

### Context Expansion Strategy

```
1. Calculate naive window: cursor ± 60 lines
2. If Treesitter available:
   - Find node at top boundary
   - Walk up to function/class parent
   - Expand start_line to include full signature
   - Same for bottom boundary
3. Cap expansion at ±50 lines extra (prevent payload explosion)
```

**Rationale:** LLM needs full function signatures for accurate completions. Blind context produces hallucinated arguments.

### Race Condition Handling

```
Request lifecycle:
1. TextChangedI → cancel pending request + clear UI
2. Debounce 300ms
3. Capture cursor position at request time
4. On response: verify cursor hasn't moved, buffer unchanged
5. Render only if valid
```

**Rationale:** Rapid typing creates overlapping requests. Stale responses cause jarring ghost text jumps.

### API Retry Strategy

- 5xx errors: retry up to 3x with exponential backoff (100ms, 200ms, 400ms)
- 4xx errors: no retry (user/config error)
- Cancel in-flight on new keystroke

**Rationale:** Cerebras may have transient failures. Don't spam user with errors for momentary issues.

### Extmark Rendering

```lua
-- Line 1: inline after cursor
virt_text = { { first_line, "Comment" } }
virt_text_pos = "inline"

-- Lines 2+: virtual lines below
virt_lines = { { { line, "Comment" } }, ... }
```

**Rationale:** Inline for seamless appearance. Virtual lines for multi-line without shifting buffer content.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Treesitter parser missing | Graceful fallback to naive context |
| API key not set | Clear error notification, no crash |
| Large file perf | Limit context expansion, lazy parsing |
| plenary.curl unavailable | Error on setup, require plenary |

## Migration Plan

1. Delete placeholder `module.lua`
2. Replace `lua/stride.lua` with `lua/stride/init.lua`
3. Update `plugin/stride.lua` if needed
4. Update tests

## Open Questions

None - V1 spec is comprehensive.
