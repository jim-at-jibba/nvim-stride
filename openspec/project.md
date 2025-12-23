# Project Context

## Purpose

nvim-stride is a next-edit suggestion plugin for Neovim. It predicts and suggests the user's next edit location, enabling faster navigation and editing workflows.

## Tech Stack

- Lua (100%)
- Neovim 0.10+
- nvim-treesitter (AST analysis)
- plenary.nvim (async utilities, testing)

## Project Conventions

### Code Style

- Formatter: stylua
- Indent: 2 spaces
- Line width: 120
- Quotes: double preferred
- Line endings: Unix
- Naming:
  - Functions/variables: `snake_case`
  - Private functions: `_underscore_prefix`
  - Constants: `UPPER_CASE`
  - Module table: `M`
  - Requires: `PascalCase` (e.g., `local Config = require(...)`)
- Type annotations (LuaLS/EmmyLua) required on all public functions

### Architecture Patterns

- Layered design: Public API → Features → Core → Utilities
- Module pattern: `local M = {} ... return M`
- Lazy module loading for heavy dependencies
- State machine for interactive sessions
- Facade pattern for public API

### Testing Strategy

- Framework: busted via plenary.nvim
- Run: `make test`
- Tests in `tests/stride/` mirroring `lua/stride/`
- Data-driven tests for repetitive cases
- Reset state in `before_each`

### Git Workflow

- Branching: feature branches → main
- Commits: conventional commits (feat:, fix:, docs:, refactor:, test:, chore:)
- Run `make test` before committing
- Use `gh` CLI for PR/issue operations

## Domain Context

- "Next edit" prediction: analyzing edit patterns to suggest where user will edit next
- Treesitter provides AST for understanding code structure
- Must integrate with Neovim's native editing commands
- Consider jump list, change list, and mark interactions

## Important Constraints

- **Performance critical**: suggestions must be near-instantaneous (<10ms)
- Neovim 0.10+ required (leverages newer APIs)
- Must not block UI thread
- Minimize memory footprint for large files

## External Dependencies

| Dependency | Purpose |
|------------|---------|
| nvim-treesitter | AST parsing, code structure analysis |
| plenary.nvim | Async utilities, test framework |
