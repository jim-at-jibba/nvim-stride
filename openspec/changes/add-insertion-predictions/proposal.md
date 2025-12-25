# Change: Add Insertion-Style Predictions

## Why

Current V2 only handles **replace** operations (find existing text → replace with new text). This misses a key use case: when a user adds something new (property, argument, import), related locations need **insertions**, not replacements.

**Example**: User adds `age: int` to a Python dataclass. The constructor calls `User(id=1, name=name, email=email)` need `age=25` inserted - there's no existing `age` text to find/replace.

This enables Cursor Tab-style "zero-entropy edits" - once intent is clear, predictable follow-up insertions should be suggested.

## What Changes

- **MODIFIED** `predictor.lua`: Extended response format with `action` field
  - Support `"replace"` action (existing behavior)
  - Support `"insert"` action with `anchor`, `position`, `insert` fields
  - Update SYSTEM_PROMPT with insertion examples
  - Validate anchor text exists in buffer

- **MODIFIED** `ui.lua`: Insertion rendering
  - New `StrideInsert` highlight group for insertion point marker
  - Render insertion preview as virtual text at anchor location
  - Handle both inline and multi-line insertions

- **MODIFIED** `init.lua` (core): Insertion acceptance
  - For insert action: locate anchor, insert text at position
  - Support `after` and `before` positioning relative to anchor

## Impact

- Affected specs: `predictor` (major), `ui` (minor)
- Affected code: `predictor.lua`, `ui.lua`, `init.lua`
- **Not breaking**: Current replace behavior unchanged; insertion is additive

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Response format | Explicit `action` field | Future-proof for more action types (delete, move) |
| Anchor strategy | Text match near cursor | Consistent with current find approach |
| Position options | `after` / `before` anchor | Covers most insertion patterns |
| Multi-line support | Newlines in `insert` text | No special handling needed |
| Backward compat | Missing `action` = `replace` | Existing prompts continue working |
