# Sweet Vinegar Games

An AI game-making side project for private use. A mobile puzzle game collection featuring Sudoku and Shikaku, built with Godot 4.6.

Replay system draft details: `docs/replay-system.md`

## Analytics

The project includes a local-first `AnalyticsManager` autoload that records gameplay/settings events to `user://analytics_events.json` using a bounded rolling window, with a pluggable sink interface for future remote providers.
## Crash reporting

Crash and runtime error reports are written to `user://crash_logs/` (rolling history, newest 15). Reports include timestamp, scene, device/OS info, memory usage, recent user actions, and registered game/replay state hooks.
`Ctrl+Shift+C` copies the latest crash report JSON to clipboard for sharing during debugging.
