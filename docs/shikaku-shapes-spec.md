# Shikaku Shapes — Implementation Specification

**Status:** Proposed
**Working title:** Shikaku Shapes
**Classification:** Mode within Shikaku
**Game ID:** `shikaku`
**Mode key:** `shapes`
**Ownership:** Shikaku clue-model generalization and Mode implementation; shared Collection registration is deferred to `logic-games-integration-spec.md`.

## Outcome

Add a Shikaku-family Mode that partitions the board into clue-constrained rectangles. Unlike standard Shikaku, each anchor can constrain area, aspect class, or both. Reuse the existing rectangle drag experience and all Shikaku Platform behavior.

## Rules

- Partition the entire grid into non-overlapping axis-aligned rectangles.
- Every rectangle contains exactly one anchor.
- Every anchor contains at least one clue component:
  - an exact area;
  - a shape constraint;
  - or both.
- Shape constraints are:
  - `Square`: width equals height;
  - `Tall`: height is greater than width;
  - `Wide`: width is greater than height;
  - `Any`: no aspect-ratio restriction.
- A missing shape component is also unconstrained. Persist whether `Any` was explicit so replay/save presentation is stable, although validation semantics are identical.
- A missing area accepts any positive rectangle area consistent with all other clues.
- The Game is complete only when the board is fully covered and every anchor constraint is satisfied.

## Player Experience

- Reuse Shikaku's raw size selector: `5`, `7`, `8`, `10`, `12`, `15`.
- The feature owns a Standard/Shapes `OptionButton`, injected by `ShikakuMenu` using the existing Sudoku rule-set-row pattern; do not add an independent difficulty control.
- Carry Mode through `LaunchParams.rule_set` (`0 = Standard`, `1 = Shapes`) while preserving `launch(params: LaunchParams)` and existing callers. Do not change shared `LaunchParams` or `MenuConfig`.
- Larger boards may use more single-component clues and more ambiguous candidate rectangles.
- Reuse drag-to-place, tap-to-remove, undo/redo, completion, and board coloring.
- Structural illegal placements are rejected; contradictions are highlighted without strike-based failure.
- A hint immediately places one complete, solver-justified rectangle and records hint use.

## Generation and Difficulty

Generalize the solution partition into anchor clue objects, for example:

```text
{
  position: Vector2i,
  area: int or absent,
  shape: square | tall | wide | any or absent
}
```

The actual typed representation is an implementation choice, but absence must not be encoded as a valid area or shape value.

`ShikakuGenerator.generate(width, height, seed, rule_set, cancel_check)` (exact signature flexible) must:

- build a complete valid rectangle partition;
- assign one anchor per rectangle;
- derive and minimize area/shape clue components;
- retain at least one component per anchor;
- prove exactly one valid partition;
- pass a human-style solver without guessing;
- reproduce identical output for the same size, Mode, and seed.

The solver must support candidate-rectangle enumeration, fixed-candidate placement, cell ownership elimination, overlap/exact-cover propagation, area constraints, and shape constraints. Exact algorithms are flexible.

## Technical Boundaries

This feature may edit:

- `scripts/shikaku/`
- Shikaku Game/Menu scenes where required
- `scripts/save/shikaku_save_adapter.gd`
- `scripts/replays/shikaku_replay_adapter.gd`
- Shikaku-specific menu resources when unavoidable
- Shikaku tests

Generalize the clue model once; do not fork a second Board/Logic implementation. Standard Shikaku remains an area-only rule set over the same model.

Do not edit shared Scenes/GameRegistry, shared MenuConfig/LaunchParams, global replay allowlists/factory, achievement catalog, or server leaderboard registry.

The owned Shikaku Menu computes leaderboard-ready Mode strings from both selectors: Standard uses the existing size string and Shapes uses `shapes_<size>`. The final integration task registers matching server keys and verifies labels; it does not rebuild the selector.

## State and Session Persistence

Persist an explicit Mode key and versioned anchor clues, solution rectangles, placed rectangles, size, seed, timer, hints, and undo/redo state.

Migration rules:

- saves without Mode default to Standard;
- legacy `numbers` dictionaries migrate to area-only anchors;
- explicit `Any` versus absent shape survives round trips;
- anchors with neither component, invalid positions, non-positive areas, or unknown shapes are not resumable.

## Replay

New replay initial state stores the Mode and generalized clues. Legacy Shikaku replays default to Standard and convert numbers to area-only anchors. Existing placement/removal frames should remain compatible; add `hint_applied` metadata if needed. Backward scrubbing must reproduce clue presentation and placed rectangles exactly.

## Platform Requirements

Reuse Shikaku save/resume, undo/redo, deterministic seed, immediate hints, replay, timer, statistics, achievements hooks, themes, haptics/effects, analytics/crash context, and time-based leaderboard readiness. Shapes statistics and leaderboard modes must be distinguishable from Standard for each raw size.

## Accessibility and Layout

- Keep the complete board visible in portrait without zoom through 15×15.
- Shape clues require distinct icons plus accessible names; color alone is insufficient.
- Area text and shape icon must coexist at minimum cell size.
- `Square`, `Tall`, `Wide`, and `Any` remain distinguishable in monochrome.

## Performance and Cancellation

Target at most 500 ms median and 3 seconds p95 on target mobile hardware. Candidate enumeration, unique-solution counting, clue minimization, and human analysis must poll cancellation. Any background generation uses a synchronized flag, animated spinner, and prompt teardown join. Never accept an unverified fallback partition.

## Testing

Cover each clue form (area only, shape only, both), the at-least-one-component invariant, explicit Any round trips, aspect validation, candidate generation, unique partition counting, deterministic seeds, all six sizes, solver steps, standard-mode regression, save/replay migration, undo/redo, hint placement, cancellation, teardown, and monochrome clue metadata.

## Non-goals

- Non-rectangular patches
- Rotation of authored pieces
- A separate Game or duplicate Shikaku board
- A separate difficulty selector
- Daily puzzles
- Shared Collection registration

## Acceptance Criteria

- [ ] Shapes Mode uses the existing six raw Shikaku sizes.
- [ ] Every anchor has area, shape, or both; none are unconstrained.
- [ ] Generated puzzles have one partition and a human-style solution.
- [ ] Standard and Shapes use one generalized clue/solver/board model.
- [ ] Legacy Standard saves and replays migrate without behavior changes.
- [ ] Drag placement, hints, undo/redo, save/resume, and replay work in both Modes.
- [ ] All shape clues remain readable at 15×15 and in monochrome.
- [ ] Performance and cancellation budgets are regression-tested.
- [ ] Existing Standard Shikaku tests pass and shared registration files are unchanged.
