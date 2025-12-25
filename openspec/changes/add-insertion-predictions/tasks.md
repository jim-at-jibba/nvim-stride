## 1. Predictor Response Format

- [x] 1.1 Define `Stride.InsertionSuggestion` type with anchor, position, insert fields
- [x] 1.2 Update `Stride.RemoteSuggestion` to include optional `action` field
- [x] 1.3 Update SYSTEM_PROMPT with insertion examples and format
- [x] 1.4 Implement `_find_anchor()` to locate anchor text in buffer (via `_find_all_occurrences()`)
- [x] 1.5 Update `_validate_response()` to handle both replace and insert actions
- [x] 1.6 Add backward compat: missing `action` defaults to `replace`

## 2. UI Rendering

- [x] 2.1 Define `StrideInsert` highlight group (green/italic)
- [x] 2.2 Implement `render_insertion()` in ui.lua
- [x] 2.3 Show insertion marker at anchor position
- [x] 2.4 Display virtual text preview of inserted content
- [x] 2.5 Handle multi-line insertion preview
- [x] 2.6 Update `clear()` to handle insertion extmarks

## 3. Accept Flow

- [x] 3.1 Update `accept()` to check `suggestion.action`
- [x] 3.2 Implement `_apply_insertion()` for insert action
- [x] 3.3 Handle `after` positioning (insert after anchor)
- [x] 3.4 Handle `before` positioning (insert before anchor)
- [x] 3.5 Auto-trigger next prediction after insertion accepted

## 4. Testing

- [x] 4.1 Unit tests for anchor finding logic (via predictor validation tests)
- [x] 4.2 Unit tests for insertion validation
- [ ] 4.3 Manual test: add dataclass property → insertion suggested
- [ ] 4.4 Manual test: add function parameter → insertion suggested
- [ ] 4.5 Manual test: tab-tab-tab flow with mixed replace/insert

## 5. Documentation

- [x] 5.1 Update demos/python.py with insertion test case
- [ ] 5.2 Add insertion example to README
