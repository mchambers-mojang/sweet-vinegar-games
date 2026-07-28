# Number Path — Implementation Specification

**Status:** Proposed  
**Working title:** Number Path  
**Classification:** Game  
**Game ID:** `number_path`  
**Ownership:** Isolated feature implementation; shared Collection registration is deferred to `logic-games-integration-spec.md`.

## Outcome

Add an unlimited generative path-deduction Game. The player draws one ordered path through every cell, with larger boards and edge barriers introducing progressively deeper connectivity deductions.

## Rules

- Begin at checkpoint `1`.
- Move only between orthogonally adjacent cells.
- Visit numbered checkpoints in strictly ascending order.
- Visit every board cell exactly once.
- Never cross a barrier between cells.
- Never revisit or cross the path.
- Finish on the highest-numbered checkpoint after covering the board.

Barriers block edges, not cells. Every cell remains traversable and must be covered.

## Player Experience

| Tier | Board | Barrier profile |
|---|---:|---|
| Easy | 5×5 | None |
| Medium | 6×6 | None |
| Hard | 7×7 | Sparse |
| Expert | 8×8 | Strong checkpoint/barrier interaction |

- Solver steps carry a stable reasoning rank:
  - Rank 1: endpoint degree, next checkpoint, or one-cell dead-end constraints force a move.
  - Rank 2: two local path constraints or one simple bottleneck force a move.
  - Rank 3: remaining-region connectivity or cut analysis across multiple cells forces a move.
  - Rank 4: a non-branching chain combines checkpoint order, barriers, and global connectivity.
- Easy puzzles use Rank 1 only; Medium require at least one Rank 2 step; Hard require at least one Rank 3 step; Expert require at least one Rank 4 step. No rank may use speculative path branching or guessing.
- Drag forward from checkpoint `1` to build the path.
- Drag backward over the current path to truncate it to that cell.
- Reject a gesture that revisits a cell, crosses a barrier, moves diagonally, or enters a checkpoint out of order.
- A hint immediately extends the current path by one correct adjacent cell. If the current path already contradicts every solution, the Game first highlights the contradiction rather than silently replacing player work.
- Structural input errors do not use strike-based failure. Assistance highlights trapped cells, disconnected remainder, or an invalid checkpoint frontier.

## Generation and Difficulty

`NumberPathGenerator.generate(tier, seed, cancel_check)` returns dimensions, checkpoints, barriers, unique solution path, seed, and solver analysis, or `{}`.

A generator may begin with a Hamiltonian path and derive clues, but accepted output must independently prove:

- exactly one full path satisfies all rules;
- checkpoint order and barriers are internally consistent;
- `NumberPathSolver` reaches the solution through supported human deductions without blind guessing;
- the solver reaches the named tier's required maximum reasoning rank;
- the same tier and seed reproduce identical puzzle data.

Human steps must include a reason, affected cells/edges, result, and reasoning rank. Techniques should include forced endpoint/degree moves, checkpoint frontier constraints, dead-end prevention, remaining-region connectivity, bottleneck/cut analysis, and barrier propagation. The exact solver and generator algorithms are flexible.

## Technical Boundaries

Use pure `NumberPathLogic`, `NumberPathGenerator`, and `NumberPathSolver` classes. Logic owns the path, move/truncate results, contradiction state, hints, completion, and `UndoStack`. Board input translates pointer movement into cell transitions; it does not decide rule validity. The Game Screen owns Platform side effects.

Suggested owned paths:

- `scripts/number_path/`
- `scenes/number_path_menu.tscn`
- `scenes/number_path_game.tscn`
- `scenes/number_path_stats.tscn`
- `assets/menu/number_path_menu.tres`, `assets/help/number_path_help.tres`, and other game-local resources
- `test/test_number_path_*.gd`

Provide game-local MenuConfig, save adapter, replay adapter, and stats resources. Do not create `assets/menu/number_path_entry.tres` and do not edit shared Scenes/GameRegistry, shared MenuConfig/LaunchParams, global replay lists/factory, achievement catalog, or server leaderboard registry. The final integration task creates the Hub `GameEntry`.

Before integration, validate navigation by loading the game-local Menu and Game scenes directly. Hub navigation is intentionally not testable on this feature branch.

## State and Session Persistence

Persist versioned dimensions, tier, seed, ordered checkpoints, edge barriers, solution path, current path, elapsed time, hints, completion state, and undo/redo state. Resume validation must reject duplicate/out-of-range checkpoints, invalid barriers, non-contiguous paths, revisited cells, and paths that violate checkpoint order.

## Replay

Record the initial generated state and:

- `path_extended` with the entered cell;
- `path_truncated` with the retained path length;
- `hint_applied`;
- `game_completed`.

The Replay Adapter reconstructs exact geometry, applies actions deterministically, and supports backward scrubbing without replaying drag effects.

## Platform Requirements

Support save/resume, undo/redo, deterministic seeds, immediate hints, timer, statistics, achievement hooks, replay, themes, haptics/effects, analytics/crash context, and time-based leaderboard readiness for `easy`, `medium`, `hard`, and `expert`.

## Accessibility and Layout

- Portrait-first full-board layout with no zoom at 8×8.
- Checkpoints require visible numbers, barriers require shape/line boundaries, and the path must remain visible in monochrome.
- Do not use color alone for current endpoint, visited cells, or invalid segments.
- Touch interpolation must not skip cells when pointer events are sparse.

## Performance and Cancellation

Target at most 500 ms median and 3 seconds p95 generation on target mobile hardware. Unique-path counting can be expensive and must be cancellable inside recursive search, connectivity checks, clue minimization, and human analysis. Use synchronized cancellation state, an animated spinner, and prompt teardown join. Never return an unverified path as fallback.

## Testing

Cover legal extension/truncation, sparse drag interpolation, checkpoint ordering, barriers, revisits, full coverage, unique solution counting, deterministic generation, solver-step validity, all tier geometries, save corruption, replay scrubbing, hint behavior on valid and contradictory paths, cancellation in recursive search, teardown timing, and monochrome drawing semantics.

## Non-goals

- Diagonal movement
- Blocked or omitted cells
- Drawing independent path segments
- Daily puzzles
- Shared Collection registration

## Acceptance Criteria

- [ ] All four tiers generate deterministic puzzles with the specified sizes and barrier profiles.
- [ ] Every accepted puzzle has exactly one full path and a human-style solution.
- [ ] Forward drag, backward truncation, checkpoint order, revisit prevention, and barriers work on mouse and touch.
- [ ] A hint extends by exactly one valid cell and records its use.
- [ ] Save/resume, undo/redo, and replay preserve the exact path state.
- [ ] The complete board remains usable without zoom and readable in monochrome.
- [ ] Performance, cancellation, and teardown budgets are regression-tested.
- [ ] Existing Games and shared registration files are unchanged.
