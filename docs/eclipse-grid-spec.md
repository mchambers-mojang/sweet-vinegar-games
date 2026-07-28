# Eclipse Grid — Implementation Specification

**Status:** Proposed
**Working title:** Eclipse Grid
**Classification:** Game
**Game ID:** `eclipse_grid`
**Ownership:** Isolated feature implementation; shared Collection registration is deferred to `logic-games-integration-spec.md`.

## Outcome

Add an unlimited generative binary-logic Game using large `+` and `−` glyphs. Sessions scale naturally from a compact introduction to a deeper 10×10 puzzle while retaining one clear rule set.

## Rules

- Every cell contains either `+` or `−`.
- Every row and column contains equal counts of both glyphs.
- No row or column contains three consecutive identical glyphs.
- `=` between adjacent cells requires equal glyphs.
- `≠` between adjacent cells requires different glyphs.
- Completed rows and columns are allowed to match one another; line uniqueness is not a rule.
- The Game is complete when all cells are filled and every rule is satisfied.

## Player Experience

Size is the difficulty selection:

| Size | Label |
|---|---|
| 4×4 | Easy |
| 6×6 | Medium |
| 8×8 | Hard |
| 10×10 | Expert |

- Solver steps carry a stable reasoning rank:
  - Rank 1: a quota, adjacent pair, sandwich, or direct relation determines one cell.
  - Rank 2: two local rules must be combined or a relation propagates one additional edge.
  - Rank 3: a relation chain or row/column interaction propagates through three or more cells.
  - Rank 4: a non-branching global quota/chain interaction spans multiple rows and columns.
- Easy puzzles use Rank 1 only; Medium require at least one Rank 2 step; Hard require at least one Rank 3 step; Expert require at least one Rank 4 step. No rank may use speculative placement or guessing.
- Tap cycles `Empty → + → − → Empty`.
- Given cells are immutable.
- Free assistance highlights broken balance, runs, and relation clues. Strict assistance rejects or penalizes incorrect entries consistently with other strict puzzle Games.
- A hint immediately applies one solver-supported glyph and increments hint statistics.
- `+` uses the theme primary color and `−` uses the theme secondary color, but glyph shape remains the authoritative distinction.

## Generation and Difficulty

`EclipseGridGenerator.generate(size, seed, cancel_check)` returns givens, adjacency clues, solution, seed, and solver analysis, or `{}`.

Generation must:

- build a complete board satisfying balance and no-three rules;
- select both fixed-cell and `=`/`≠` clues;
- minimize clues while preserving exactly one solution;
- require no blind guessing in `EclipseGridSolver`;
- validate the size label's required maximum reasoning rank;
- reproduce identical data for the same size and seed.

The human solver must return structured steps with a reason, affected cells, result, and reasoning rank. Its technique vocabulary should cover quota completion, pair/sandwich prevention, relation propagation, intersecting row/column constraints, and chained deductions. Exact algorithms and clue distributions remain implementation choices.

## Technical Boundaries

Use pure `EclipseGridLogic`, `EclipseGridGenerator`, and `EclipseGridSolver` classes. The Logic class owns state, validation, hint application, and `UndoStack` without autoload or Node dependencies. The Game Screen orchestrates Platform behavior and the Board owns presentation/input only.

Suggested owned paths:

- `scripts/eclipse_grid/`
- `scenes/eclipse_grid_menu.tscn`
- `scenes/eclipse_grid_game.tscn`
- `scenes/eclipse_grid_stats.tscn`
- `assets/menu/eclipse_grid_menu.tres`, `assets/help/eclipse_grid_help.tres`, and other game-local resources
- `test/test_eclipse_grid_*.gd`

Provide game-local MenuConfig, save adapter, replay adapter, stats screen, and resources. Do not create `assets/menu/eclipse_grid_entry.tres` and do not edit `Scenes`, `GameRegistry`, shared `MenuConfig`/`LaunchParams`, replay allowlists/factories, the achievement catalog, or leaderboard server registry. The final integration task creates the Hub `GameEntry`.

Before integration, validate navigation by loading the game-local Menu and Game scenes directly. Hub navigation is intentionally not testable on this feature branch.

## State and Session Persistence

Persist a versioned schema containing size, seed, givens, horizontal/vertical relations, solution, current cells, elapsed time, assistance mode, hints, completion/failure state, and undo/redo state. Validate all dimensions and relation endpoints before allowing resume.

## Replay

Record the initial generated state and:

- `glyph_changed`
- `hint_applied`
- `game_completed`

Playback must use an `EclipseGridReplayAdapter`, reproduce givens and relation clues exactly, and support backward scrubbing with effects suppressed.

## Platform Requirements

Support save/resume, undo/redo, deterministic seeds, immediate hints, timer, statistics, achievement hooks, replay, themes, haptics/effects, analytics/crash context, and time-based leaderboard readiness for size modes `4`, `6`, `8`, and `10`.

## Accessibility and Layout

- Portrait-first and fully visible without zoom at 10×10.
- Use large `+`/`−` silhouettes; never depend on primary/secondary color alone.
- Render `=` and `≠` with sufficient spacing and contrast at every size.
- Provide accessible names for cell state and relation clues.
- Respect effect and reduced-motion settings.

## Performance and Cancellation

Generation targets at most 500 ms median and 3 seconds p95 on target mobile hardware. Potentially long generation runs in a cancellable background Thread with an animated spinner. Cancellation must reach generation, solution counting, human solving, and minimization loops; teardown must synchronize, cancel, and join promptly.

## Testing

Cover each rule independently, explicit absence of line-uniqueness, all four sizes, relation clue orientation, deterministic generation, unique solution counting, solver-step correctness, tier acceptance, invalid save schemas, replay scrubbing, undo/redo, strict/free assistance, cancellation within solve/minimization, teardown timing, and monochrome UI semantics.

## Non-goals

- A rule requiring unique completed rows or columns
- Sun/moon branding
- Independent size and difficulty controls
- Daily puzzles
- Shared Collection registration

## Acceptance Criteria

- [ ] Sizes 4, 6, 8, and 10 map to Easy through Expert and generate deterministic puzzles.
- [ ] Every accepted puzzle has exactly one solution and is human-logic-solvable.
- [ ] Balance, no-three, `=`, and `≠` rules validate correctly without a line-uniqueness rule.
- [ ] Tap input, hints, strict/free assistance, and undo/redo are complete.
- [ ] Save/resume and replay preserve every clue and player action.
- [ ] `+`/`−` states remain distinguishable in monochrome and at 10×10.
- [ ] Performance and cancellation budgets are regression-tested.
- [ ] Existing Games and shared registration files are unchanged.
