# Sweet Vinegar Games

An AI game-making side project for private use. A mobile puzzle game collection featuring Sudoku and Shikaku, built with Godot 4.6.

## Analytics

The project includes a local-first `AnalyticsManager` autoload that records gameplay/settings events to `user://analytics_events.json` using a bounded rolling window, with a pluggable sink interface for future remote providers.
