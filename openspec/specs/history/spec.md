# history Specification

## Purpose
TBD - created by archiving change add-v2-next-edit-prediction. Update Purpose after archive.
## Requirements
### Requirement: Buffer Snapshotting

The history module SHALL capture buffer state on InsertEnter for diff computation.

#### Scenario: Snapshot on insert enter
- **WHEN** user enters insert mode
- **THEN** current buffer lines SHALL be stored as snapshot
- **AND** previous snapshot SHALL be discarded

#### Scenario: Snapshot per buffer
- **WHEN** user switches buffers in insert mode
- **THEN** snapshot SHALL be taken for the new buffer

### Requirement: Diff Computation

The history module SHALL compute structured diffs between snapshot and current buffer state.

#### Scenario: Single line modification
- **WHEN** user changes "local apple = 1" to "local orange = 1" on line 10
- **THEN** diff SHALL return EditDiff with change_type="modification", line=10, original="local apple = 1", new="local orange = 1"

#### Scenario: Line insertion
- **WHEN** user inserts a new line
- **THEN** diff SHALL return EditDiff with change_type="insert", line=N, original=nil, new="inserted text"

#### Scenario: Line deletion
- **WHEN** user deletes a line
- **THEN** diff SHALL return EditDiff with change_type="delete", line=N, original="deleted text", new=nil

#### Scenario: No changes
- **WHEN** buffer content matches snapshot
- **THEN** diff SHALL return empty array

#### Scenario: Multiple changes
- **WHEN** user makes multiple edits
- **THEN** diff SHALL return array of all EditDiff objects

