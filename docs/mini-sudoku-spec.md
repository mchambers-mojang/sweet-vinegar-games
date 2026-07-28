# Mini Sudoku — Implementation Specification

**Status:** Proposed  
**Working title:** Mini Sudoku  
**Classification:** Mode within Sudoku  
**Game ID:** `sudoku`  
**Mode key:** `mini`  
**Ownership:** Sudoku engine generalization and Mode implementation; shared Collection registration is deferred to `logic-games-integration-spec.md`.

## Outcome

Add a single quick-play 6×6 standard Sudoku Mode while replacing hard-coded 9×9 assumptions with an explicit grid specification. Existing 9×9 Sudoku, variants, saves, replays, and behavior must remain backward compatible.

## Rules

- Use a 6×6 grid with digits `1–6`.
- Divide the grid into six regions, each two rows by three columns.
- Every row, column, and region contains each digit exactly once.
- Fixed givens cannot be edited.
- Provide one quick-play difficulty only.
- Anti-Knight, Anti-King, and Killer combinations are not part of this Mode.

## Player Experience

Mini Sudoku reuses Sudoku's cell selection, number-first/cell-first input, pencil marks, coloring, strict/free assistance, auto-removal, timer, hints, pause, completion flow, and Game Menu. The Game Menu exposes Mini as a standard rule-set/grid option without presenting irrelevant 9×9 difficulty or variant combinations.

A hint immediately places one solver-supported digit and records hint use.

## Grid Specification

Introduce a typed, immutable grid description (working name `SudokuGridSpec`) carrying at least:

- stable ID (`standard_9x9`, `mini_6x6`);
- grid width/height;
- region width/height;
- symbol minimum/maximum;
- cell count and symbols.

All grid-dependent code must derive row, column, region, peers, candidates, serialization limits, and board layout from this object. Do not scatter `size == 6` branches.

The default specification is 9×9 with 3×3 regions. Existing public APIs may retain backward-compatible overloads/defaults, but new internals must not assume `81`, `9`, or `3`.

## Generation and Solving

`SudokuGenerator`, `SudokuSolver`, and `SudokuLogic` accept the grid specification. Mini generation must:

- be deterministic for a seed;
- produce exactly one solution;
- be solvable by the human-style solver without guessing;
- satisfy the single quick-play technique profile;
- reject invalid or exhausted output rather than returning a partial puzzle.

Existing constraint APIs must continue working for 9×9. This spec does not require adapting variant constraints to 6×6 beyond ensuring Mini explicitly selects no extra constraints.

## Technical Boundaries

This feature may edit:

- `scripts/sudoku/`
- Sudoku Game/Menu scenes where required
- `scripts/save/sudoku_save_adapter.gd`
- `scripts/replays/sudoku_replay_adapter.gd`
- Sudoku-specific menu resources when unavoidable
- Sudoku tests

It must preserve `launch(params: LaunchParams)`. Add a Sudoku-owned `RULE_SET_MINI` value and carry it through the existing `LaunchParams.rule_set` field; Mini always selects `mini_6x6`, ignores the 9×9 difficulty selector, and has no additional constraint. Do not change shared `LaunchParams`.

Do not edit `scripts/scenes.gd`, `scripts/menu/game_registry.gd`, global replay allowlists/factory, `scripts/achievements/achievement_catalog.gd`, or `server/signaling/db.ts`. Final label/help/leaderboard registration belongs to integration.

## State and Session Persistence

New saves persist the grid-spec ID and Mode key. Every cell-sized collection must match the selected spec.

Migration rules:

- a save without grid metadata defaults to `standard_9x9`;
- existing 9×9 save versions remain resumable;
- Mini saves validate 36 cells, symbols `0–6`, 2×3 regions, and Mini-compatible settings;
- corrupt or unknown grid specifications are not resumable.

Undo/redo, pencil marks, colors, solution, givens, elapsed time, strikes, and hints must serialize for either grid.

## Replay

New Sudoku replays persist the grid-spec ID in initial state. Legacy replays without it default to 9×9. `SudokuReplayAdapter` must construct the correct board dimensions and support all existing frame types and backward scrubbing for both grids.

## Platform Requirements

Retain save/resume, undo/redo, deterministic seed, immediate hints, replay, timer, statistics, achievement hooks, themes, haptics/effects, analytics/crash context, and time-based leaderboard readiness. Mini statistics must be distinguishable from standard difficulty statistics without breaking historical counters.

## Accessibility and Layout

- Reflow the shared Sudoku board from the grid specification.
- Keep existing portrait-first layout and minimum touch targets.
- Render 2×3 region boundaries clearly in every theme and in monochrome.
- Pencil marks for six symbols must remain readable without zoom.

## Performance and Cancellation

Mini generation should normally complete within one frame, but it remains subject to the common target of at most 500 ms median and 3 seconds p95. Any background path must use the existing cancellable-generation lifecycle. Solver and generator cancellation cannot regress Killer Sudoku threading behavior.

## Testing

Add parameterized coverage for row/column/region indexing, peers, candidates, generator uniqueness, solver techniques, Logic actions, board layout, save migration, replay migration/scrubbing, and Mini completion. Run all existing standard, Anti-Knight, Anti-King, Killer, save, replay, and Sudoku UI tests unchanged.

Explicitly test:

- legacy saves/replays default to 9×9;
- 6×6 and 9×9 state never leak between sessions;
- all prior 9×9 APIs preserve behavior;
- invalid cell counts and symbols are rejected;
- no 6×6 variant combinations appear.

## Non-goals

- Multiple Mini difficulty tiers
- 6×6 Anti-Knight, Anti-King, or Killer
- Arbitrary Sudoku dimensions beyond the two specified grids
- Rebranding Sudoku as a new Game
- Shared Collection registration

## Acceptance Criteria

- [ ] Mini Sudoku plays as one 6×6 quick-play Mode with 2×3 regions.
- [ ] One grid specification drives all size-dependent generator, solver, logic, board, save, and replay behavior.
- [ ] Mini puzzles are deterministic, unique, and human-logic-solvable.
- [ ] Legacy saves/replays default to 9×9 and remain valid.
- [ ] Existing 9×9 standard and variant behavior is unchanged.
- [ ] Sudoku Platform features work fully in both grids.
- [ ] Mini is portrait-readable, monochrome-safe, and requires no zoom.
- [ ] The complete existing Sudoku test suite plus new parameterized tests passes.
- [ ] Shared integration files remain unchanged.
