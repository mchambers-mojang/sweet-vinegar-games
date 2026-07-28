# Crown Grid — Implementation Specification

**Status:** Proposed  
**Working title:** Crown Grid  
**Classification:** Game  
**Game ID:** `crown_grid`  
**Ownership:** Isolated feature implementation; shared Collection registration is deferred to `logic-games-integration-spec.md`.

## Outcome

Add an independently branded, unlimited generative region-placement Game. A session should be short, readable on a phone, replayable from a seed, and guaranteed to have one solution reachable without guessing.

The mechanic is inspired by region-based crown puzzles, but the name, presentation, progression, generated boards, and assets must be original to Sweet Vinegar Games.

## Rules

- The board is `N × N` and contains exactly `N` orthogonally connected regions.
- Place exactly one Crown in every row, column, and region.
- Two Crowns may not occupy diagonally adjacent cells.
- Crowns farther apart on the same diagonal are allowed.
- Excluded marks are player notes and do not affect solution validity.
- The Game is complete only when all `N` Crowns satisfy every rule.

## Player Experience

- Difficulty tiers map to board size:

  | Tier | Board |
  |---|---:|
  | Easy | 6×6 |
  | Medium | 7×7 |
  | Hard | 8×8 |
  | Expert | 9×9 |

  - Solver steps carry a stable reasoning rank:
    - Rank 1: one row, column, region, or adjacency constraint directly determines a cell.
    - Rank 2: a placement requires combining two constraint types.
    - Rank 3: a locked candidate set or region-line interaction propagates across multiple units.
    - Rank 4: a non-branching chain of three or more dependent eliminations is required.
  - Easy puzzles use Rank 1 only; Medium require at least one Rank 2 step; Hard require at least one Rank 3 step; Expert require at least one Rank 4 step. No rank may encode trial placement, speculative branching, or guessing.
  - Tapping a cell cycles `Empty → Excluded → Crown → Empty`.
- Dragging across cells paints Excluded marks without overwriting Crowns.
- An `auto_mark` Game Rule may mark the completed Crown's row, column, region, and diagonally adjacent cells as excluded. Automatically added marks must be undoable with the Crown placement.
- Free assistance highlights current contradictions. Strict assistance rejects or penalizes an incorrect Crown consistently with other strict puzzle Games.
- A hint immediately applies one logically justified Crown or Excluded mark and increments hint statistics.

## Generation and Difficulty

`CrownGridGenerator.generate(tier, seed, cancel_check)` returns the board, solution, region map, seed, and solver analysis, or `{}` on cancellation/exhaustion.

Every accepted puzzle must:

- contain exactly `N` non-empty, orthogonally connected regions;
- have exactly one valid Crown placement;
- be solvable by `CrownGridSolver` without blind guessing;
- match the tier's required maximum reasoning rank;
- reproduce identical puzzle data for the same seed and tier.

The solver must expose structured deduction steps with a reason, affected cells, result, and reasoning rank for generation analysis and hints. Supported reasoning should include row/column/region singles, adjacency elimination, intersecting constraint elimination, and combined candidate propagation. The exact generation and solving algorithms are implementation choices.

## Technical Boundaries

Use the existing pure puzzle pattern:

- `CrownGridLogic` owns state, validation, completion, hints, and `UndoStack`; it has no Node or autoload dependency.
- `CrownGridGenerator` owns deterministic generation and bounded retry.
- `CrownGridSolver` owns solution counting, human-style solving, next-step output, and difficulty analysis.
- `CrownGridBoard` owns drawing and input translation only.
- `CrownGridGameScreen` extends `GameScreen` and owns Platform side effects.
- `CrownGridMenu` uses `MenuConfig` and launches through `launch(params: LaunchParams)`.
- A `CrownGridSaveAdapter` and `CrownGridReplayAdapter` implement the existing adapter contracts.

Suggested owned paths:

- `scripts/crown_grid/`
- `scenes/crown_grid_menu.tscn`
- `scenes/crown_grid_game.tscn`
- `scenes/crown_grid_stats.tscn`
- `assets/menu/crown_grid_menu.tres`, `assets/help/crown_grid_help.tres`, and other game-local resources
- `test/test_crown_grid_*.gd`

Do not create `assets/menu/crown_grid_entry.tres` and do not edit `scripts/scenes.gd`, `scripts/menu/game_registry.gd`, `scripts/menu/menu_config.gd`, `scripts/menu/launch_params.gd`, global replay allowlists/factories, `scripts/achievements/achievement_catalog.gd`, or `server/signaling/db.ts`. The final integration task creates the Hub `GameEntry`.

Before integration, validate navigation by loading the game-local Menu and Game scenes directly. Hub navigation is intentionally not testable on this feature branch.

## State and Session Persistence

Persist a versioned state containing:

- tier, size, seed, region ID per cell, and solution;
- current Crown and Excluded states;
- elapsed time, assistance mode, hints used, and completion/failure state;
- undo/redo entries or enough action history to reconstruct them.

Resume must validate dimensions, region connectivity, array lengths, enum values, and solution compatibility. Invalid data is not resumable and must surface through existing adapter behavior.

## Replay

Record the initial generated state and the actions:

- `cell_state_changed`
- `exclusions_painted`
- `hint_applied`
- `game_completed`

Replay playback must reconstruct the exact board, filter non-visual ceremony, and support backward scrubbing without sound, haptics, or effects during suppressed playback.

## Platform Requirements

The Game must support save/resume, undo/redo, deterministic seeds, timer, immediate hints, statistics, achievements hooks, replay, themes, haptics/effects, analytics/crash context, and time-based leaderboard readiness. Game-local code may emit these events, but shared registration belongs to the final integration task.

## Accessibility and Layout

- Portrait-first board and controls; no zoom required at 9×9.
- Interactive targets should be 44 points where space permits.
- Region boundaries must remain identifiable in monochrome; color may reinforce but never define a region alone.
- Crown and Excluded glyphs require distinct silhouettes and accessible labels.
- Effects must honor Platform effect settings.

## Performance and Cancellation

- Target generation: at most 500 ms median and 3 seconds p95 on target mobile hardware.
- Generation that can exceed one frame runs on a background `Thread` with an animated spinner.
- Cancellation propagates through generator and solver loops using synchronized cross-thread state.
- Scene teardown cancels and joins promptly; it must not wait for a full solve.
- Exhaustion or cancellation returns `{}` and follows the existing generation-failure flow.

## Testing

Cover region connectivity, rule validation, adjacent-versus-long diagonal behavior, unique solution counting, deterministic seeds, solver-step validity, tier acceptance, undo/redo including auto-marks, save corruption, replay scrubbing, cancellation during expensive solver work, teardown timing, touch drag behavior, and monochrome rendering metadata.

## Non-goals

- Full chess-diagonal attacks
- Daily or curated puzzles
- Online competition
- Shared Collection registration
- Final public naming or art

## Acceptance Criteria

- [ ] All four tiers generate deterministic, uniquely solvable boards with the specified sizes.
- [ ] Every generated region is orthogonally connected and contains exactly one solution Crown.
- [ ] Only diagonally adjacent Crowns conflict; distant same-diagonal Crowns do not.
- [ ] Tap cycling, drag exclusion, optional auto-mark, hints, and undo/redo behave atomically.
- [ ] Save/resume and replay preserve the exact generated board and player state.
- [ ] The Game meets Platform, accessibility, and generation-performance requirements.
- [ ] Generation cancellation and scene teardown are bounded and regression-tested.
- [ ] Existing Games and shared registration files are unchanged.
