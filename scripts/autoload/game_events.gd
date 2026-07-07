extends Node

## Central event bus for domain events emitted by game screens.
## Platform listeners (analytics, stats, crash, replay) subscribe independently.
## Games emit typed signals here; adding a new listener never requires editing game screens.

## Emitted when a significant game move is made (piece placed, number input, rectangle placed, etc.).
## move_data must include "elapsed_time" (float) and "event_type" (String) plus game-specific payload.
signal move_made(game_id: String, move_data: Dictionary)

## Emitted when a new game session starts (not on resume).
## difficulty is -1 for games with no explicit difficulty.
## rules contains game-specific metadata (same data as analytics params).
signal game_started(game_id: String, difficulty: int, rules: Dictionary)

## Emitted when a game session ends for any reason (win, game_over, abandoned).
signal game_ended(game_id: String, outcome: String, duration: float)

## Emitted when a submittable leaderboard result is ready (win/completion only, not abandon/quit).
## game_id matches the server's game key (e.g., "sudoku", "shikaku", "blockudoku").
## mode matches the server's mode key (e.g., "easy", "5", "standard").
## value is seconds for time-based boards, raw score for score-based boards.
signal leaderboard_score_ready(game_id: String, mode: String, value: float)

## Emitted when a game's score changes.
signal score_changed(game_id: String, old_score: int, new_score: int)
