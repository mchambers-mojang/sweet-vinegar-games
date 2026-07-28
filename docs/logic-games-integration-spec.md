# Generative Logic Games — Final Integration Specification

**Status:** Proposed
**Classification:** Collection integration
**Prerequisites:** Crown Grid, Eclipse Grid, Number Path, Mini Sudoku, and Shikaku Shapes feature branches are merged.
**Ownership:** Shared registration, cross-Game compatibility, and end-to-end validation only.

## Outcome

Integrate five independently implemented logic-puzzle features into one coherent Collection release without reimplementing their Game logic. This task is intentionally last so simultaneous feature agents do not collide in shared files.

## Inputs

The merged feature work must already provide:

- complete game-local implementations for Crown Grid, Eclipse Grid, and Number Path;
- Mini Sudoku inside Sudoku;
- Shikaku Shapes inside Shikaku;
- game-local scenes, MenuConfig resources, save/replay adapters, help content, stats behavior, tests, and event emission.

If a prerequisite is incomplete, fix it in that feature's owned module or send it back to the feature owner. Do not duplicate feature logic in shared integration code.

## Shared Registration

Register distinct Games:

- `crown_grid`
- `eclipse_grid`
- `number_path`

Update the shared surfaces required by the current architecture:

- `scripts/scenes.gd`
- `scripts/menu/game_registry.gd`
- `assets/menu/*_entry.tres`
- shared replay support lists in `scripts/replays/replays_screen.gd`
- Replay Adapter selection in `scripts/replays/replay_player.gd`
- `scripts/achievements/achievement_catalog.gd`
- leaderboard mode registry and tests in `server/signaling/`
- shared analytics, crash, stats, or display-name registries discovered during integration

Do not replace config-driven `GameMenu`, `MenuConfig`, `GameEntry`, `GameSaveAdapter`, or `GameReplayAdapter` with game-specific branching.

## Mode Integration

### Mini Sudoku

- Verify the already-merged Sudoku selector exposes Mini using the grid specification and `LaunchParams.rule_set`.
- Keep it incompatible with Anti-Knight, Anti-King, and Killer selections.
- Show one quick-play option, not the 9×9 difficulty list.
- Register time leaderboard mode `sudoku:mini`.
- Add Mini-specific help and achievement/stat presentation without creating a second Hub Game.

### Shikaku Shapes

- Verify the already-merged Standard/Shapes selector retains raw sizes `5`, `7`, `8`, `10`, `12`, and `15` and emits the expected Mode strings.
- Keep legacy Standard defaults.
- Register time leaderboard modes `shikaku:shapes_5`, `shikaku:shapes_7`, `shikaku:shapes_8`, `shikaku:shapes_10`, `shikaku:shapes_12`, and `shikaku:shapes_15`.
- Update help and stats presentation without creating a second Hub Game.

Both Mode features use the existing `LaunchParams.rule_set` pattern. Do not extend `MenuConfig` or `LaunchParams` unless a separately reviewed requirement appears after merge.

## Game Integration

Create Hub entries, Scenes constants, help access, replay playback, stats presentation, achievements, and time-based leaderboard modes:

| Game | Modes |
|---|---|
| Crown Grid | `easy`, `medium`, `hard`, `expert` |
| Eclipse Grid | `4`, `6`, `8`, `10` |
| Number Path | `easy`, `medium`, `hard`, `expert` |

Verify every game ID and leaderboard `(game, mode)` pair is unique. Configure server bounds appropriate to expected completion times and test both accepted and rejected scores.

## Platform Cohesion

For all five features, verify:

- Hub navigation to Game Menu and back;
- `launch(params: LaunchParams)` for new sessions;
- Session Persistence with simultaneous saves in distinct sections;
- no save or stats key collision between Games or Modes;
- replay listing, import, playback, and backward scrubbing;
- correct help topic from Menu and Game Screen;
- themes and monochrome-safe presentation;
- haptics/effects settings;
- analytics and crash action identifiers;
- achievements and category ordering;
- leaderboard submission and display;
- Settings return paths and SceneTransition behavior.

## Shared Tests

Add focused shared tests for:

- every GameRegistry entry and scene path loading;
- duplicate game IDs and duplicate leaderboard keys;
- replay allowlist/factory parity;
- help resources loading;
- save coexistence across all puzzle Games;
- LaunchParams backward compatibility;
- achievement trigger keys;
- leaderboard server bounds and sorting;
- Mode labels and option-to-mode mapping;
- legacy Sudoku and Shikaku launch behavior.

Run the complete Godot GUT suite and signaling server tests. Existing failures are not accepted as feature baselines without a documented, reproducible comparison to the pre-integration commit.

## Performance Validation

On representative target mobile hardware, collect enough samples per size/tier to verify each generator stays at or below 500 ms median and 3 seconds p95. Confirm:

- long generation displays an animated spinner;
- leaving during generation cancels and joins promptly;
- no worker callback targets a freed Game Screen;
- cancellation can interrupt uniqueness and human-solver analysis;
- generation failure returns to a safe Game Menu state.

The integration task may tune thresholds or orchestration, but algorithmic generator defects return to the owning feature.

## Accessibility Validation

Exercise every theme and a monochrome capture:

- Crown regions remain distinguishable without color.
- Eclipse `+`/`−` and `=`/`≠` remain distinct.
- Number Path checkpoints, barriers, visited cells, and endpoint remain distinct.
- Mini Sudoku 2×3 regions and pencil marks remain readable.
- Shikaku Shapes icons/text remain readable through 15×15.

All boards remain playable portrait-first without zoom.

## Non-goals

- Rewriting feature Logic, Generator, or Solver classes
- Daily challenges or curated puzzle delivery
- Final public naming/marketing work
- Word-based Games
- New Platform abstractions unrelated to integration

## Acceptance Criteria

- [ ] Crown Grid, Eclipse Grid, and Number Path appear once in the Hub and navigate correctly.
- [ ] Mini Sudoku appears only within Sudoku and Shikaku Shapes only within Shikaku.
- [ ] Every save, stats, replay, achievement, help, analytics, and leaderboard identifier is unique and wired.
- [ ] Replay listing/import/playback supports all new distinct Games and both new Modes.
- [ ] All leaderboard modes are registered and server-tested with correct sort/bounds.
- [ ] Existing Sudoku, Shikaku, Blockudoku, and Carom behavior remains intact.
- [ ] The full Godot and signaling test suites pass.
- [ ] Generation performance and cancellation meet the shared budget for every feature.
- [ ] All five features pass portrait and monochrome accessibility checks.
- [ ] No feature logic is duplicated into shared integration files.
