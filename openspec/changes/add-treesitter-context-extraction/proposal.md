# Proposal: Add Treesitter Context Extraction

## Summary

Enhance stride's refactor mode predictions by using treesitter to extract semantic context (containing function) and adding structured XML tags to prompts for better LLM comprehension.

## Motivation

Currently, stride sends raw line windows centered around the cursor for context. This approach:
- May cut functions mid-body, losing semantic boundaries
- Provides no structured separation between context types
- Has no mechanism for project-specific rules

ThePrimeagen's [99 plugin](https://github.com/ThePrimeagen/99) demonstrates effective patterns:
- Treesitter-based function detection with custom queries
- Clean geometry abstractions (Point/Range) for coordinate handling
- AGENT.md file discovery for project context injection
- Structured prompts with clear semantic boundaries

## Goals

1. **Geometry module** - Centralize coordinate conversions (treesitter, vim, cursor)
2. **Treesitter extraction** - Find containing function at cursor position
3. **Request context pattern** - Encapsulate prediction state in single object
4. **AGENTS.md discovery** - Optional project-specific context injection
5. **Structured prompts** - Use XML tags for clear semantic boundaries

## Non-Goals

- Custom `.scm` query files per language (too complex for initial version)
- Provider abstraction (not needed yet)
- Rule/@mention system (overkill for stride's automatic prediction philosophy)

## Design Decisions

### Coordinate System

Internal storage uses 1-indexed (row, col) matching Lua conventions. Conversion methods handle:
- Treesitter (0,0 indexed)
- Vim buffer APIs (0,0 indexed)
- Cursor positions (1-indexed row, 0-indexed col)

### Function Detection

Use node type matching rather than custom query files:
- Walk up from cursor node to find function parent
- Match against known function node types per language
- Graceful fallback when treesitter unavailable

### Context Files

- Default: `false` (opt-in)
- Caching: Per session (static table keyed by absolute path)
- Discovery: Walk from file directory up to cwd

### Prompt Structure

Use XML tags for semantic clarity:
```xml
<RecentChanges>...</RecentChanges>
<ContainingFunction name="foo" lines="1-15">...</ContainingFunction>
<Context file="test.lua" lines="1-30">...</Context>
<ProjectRules>...</ProjectRules>
<Cursor line="2" col="14" />
```

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Treesitter unavailable | Graceful fallback to line-based context |
| Large functions | Cap function text at reasonable limit |
| Large AGENTS.md | Cap at ~2000 chars |
| Breaking V1 mode | Keep utils.get_context() unchanged |

## Success Criteria

- [ ] Geometry module with full test coverage
- [ ] Treesitter extraction works for Lua, JS/TS, Python, Go
- [ ] Context object encapsulates all prediction state
- [ ] AGENTS.md discovery works when configured
- [ ] Structured prompts improve prediction accuracy
- [ ] All existing tests pass
- [ ] No regression in V1 completion mode
