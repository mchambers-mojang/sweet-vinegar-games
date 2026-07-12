class_name GameEntry
extends Resource

## Declarative configuration for a single game shown in the Hub.
## Create one .tres per game; add it to GameRegistry.ENTRIES.

## Unique game identifier.
@export var id: String = ""

## Display title shown on the Hub button.
@export var title: String = ""

## Scene path of the game's menu (or game screen if no separate menu exists).
@export var menu_scene_path: String = ""

## Optional icon resource path (e.g. "res://assets/icons/sudoku.svg").
@export var icon: String = ""

## Unlock rule controlling button visibility.
## "" (empty)    — always visible (default)
## "secret_tap"  — hidden until the player taps the title area rapidly
@export var unlock_rule: String = ""

# --- Secret-tap unlock parameters (used when unlock_rule == "secret_tap") ---

## Number of mouse clicks required within tap_mouse_window_sec.
@export var tap_mouse_count: int = 5

## Time window in seconds for counting mouse clicks.
@export var tap_mouse_window_sec: float = 1.0

## Number of touch taps required within tap_touch_window_sec.
@export var tap_touch_count: int = 7

## Time window in seconds for counting touch taps.
@export var tap_touch_window_sec: float = 0.6
