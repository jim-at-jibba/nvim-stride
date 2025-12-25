## Context

V1 stride.nvim is a stateless autocomplete: on each keystroke, it captures buffer context and asks "what comes next at cursor?" V2 shifts to stateful prediction: track what the user changed, then predict what else needs changing elsewhere in the file.

**Stakeholders**: Neovim users wanting intelligent refactoring assistance.

**Constraints**:
- Must not break V1 functionality
- Must remain performant (<100ms for suggestions)
- Must work without external LSP dependencies

## Goals / Non-Goals

**Goals**:
- Track edit history within insert sessions
- Predict related edits based on recent changes
- Render suggestions at remote locations
- Enable "tab-tab-tab" flow for chained edits

**Non-Goals**:
- Cross-file refactoring (single buffer only)
- LSP integration (pure LLM-based)
- Undo/redo integration (standard Neovim undo)

## Decisions

### Decision 1: Diff Strategy

**Choice**: Use `vim.diff()` on full buffer snapshot vs current state.

**Alternatives**:
- **On-change tracking**: Track each `TextChangedI` delta. More complex, harder to batch.
- **Visible-only diff**: Limit to visible lines. Faster but misses context.

**Rationale**: `vim.diff()` is built-in, fast, and handles all edge cases. Full buffer ensures we catch all relevant changes. Can optimize later if perf issues arise.

### Decision 2: Prompt Strategy

**Choice**: Structured prompt with explicit JSON schema.

```
[RECENT EDIT]
Line 10: "local apple = 1" → "local orange = 1"

[FILE CONTEXT]
<buffer excerpt>

[TASK]
Return JSON: {"line": N, "original": "...", "new": "..."} or {"line": null}
```

**Alternatives**:
- Free-form response: Harder to parse, more hallucination risk.
- Multiple suggestions: More complex UI, decision fatigue.

**Rationale**: Single JSON object is easy to validate and render. One suggestion at a time keeps UX simple.

### Decision 3: V1/V2 Coexistence

**Choice**: `mode` config option with values `"completion"` | `"refactor"` | `"both"`.

- `completion` (default): V1 behavior only
- `refactor`: V2 behavior only
- `both`: V1 at cursor + V2 remote (may be noisy)

**Rationale**: Gradual rollout; users can opt-in to V2. Default remains V1 for stability.

### Decision 4: Remote UI Rendering

**Choice**: EOL virtual text with inline highlight.

```lua
-- On target line:
-- 1. Highlight `apple` with StrideReplace (red/strikethrough)
-- 2. Add EOL virt_text: "→ orange" with StrideRemoteSuggestion (cyan)
```

**Alternatives**:
- Virtual lines below: More intrusive, shifts content.
- Floating window: Complex, positioning issues.
- Just highlight: Unclear what the replacement is.

**Rationale**: EOL text is non-intrusive and clearly shows both what to replace and the replacement.

### Decision 5: Acceptance Flow

**Choice**: Tab jumps to target + applies edit atomically.

```lua
if suggestion.is_remote then
  vim.api.nvim_win_set_cursor(0, { suggestion.line, col })
  vim.api.nvim_buf_set_text(buf, line-1, col_start, line-1, col_end, { new_text })
end
```

**Alternatives**:
- Two-step (Tab to jump, Tab again to apply): Slower UX.
- Apply without jumping: User loses context.

**Rationale**: Single Tab minimizes friction. User sees result immediately.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| LLM returns garbage JSON | Strict validation, fallback to no suggestion |
| False positives annoy users | Conservative prompts, easy dismiss (any key) |
| Performance regression for large files | Limit diff to visible window + margins if needed |
| User confusion (suggestion not at cursor) | Distinct highlight colors, help message on first use |

## Resolved Questions

1. **Multi-edit chaining**: Auto-trigger next prediction after accepting a remote edit. Enables "tab-tab-tab" flow.
2. **Dismiss keybind**: Any key (except Tab) dismisses remote suggestion while staying in insert mode.
3. **History depth**: Sliding window of recent edits (configurable, default 5). Provides better context for LLM.
4. **Cross-session persistence**: Clear history on InsertLeave. Each insert session starts fresh.
