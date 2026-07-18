class_name GameReplayAdapter extends RefCounted

## Base interface for game-specific replay adapters.
## Each game provides one concrete subclass that knows how to:
##   - Normalize legacy initial state from replay metadata
##   - Set up the visual board from the initial state
##   - Apply a single replay frame to the board
##   - Reset the board back to initial state (enables backward scrubbing)
##   - Report which event types are visually meaningful

## Return the initial state used to build and reset the replay visual.
## Games may override this to recover legacy recordings from other metadata.
func get_initial_state(replay: Dictionary) -> Dictionary:
	var header: Dictionary = replay.get("header", {})
	var initial_state: Dictionary = header.get("initial_state", {})
	return initial_state.duplicate(true)


## Called once when playback starts.
## Create and configure the game's board/visual, then return it.
## The returned node will be added to the ReplayPlayer scene tree.
func setup_playback(initial_state: Dictionary) -> Control:
	return null


## Apply a single frame's action to the visual.
## suppress_effects=true should skip non-stateful visual side effects (shake, particles, etc.).
func apply_frame(frame: Dictionary, visual: Control, suppress_effects: bool = false) -> void:
	pass


## Reset the visual to the initial state.
## Called when scrubbing backward or replaying from the beginning.
func reset_to_state(initial_state: Dictionary, visual: Control) -> void:
	pass


## Which frame event types are visually meaningful (worth stepping through)?
## Return an empty array to include all frame types.
func get_visual_event_types() -> Array[String]:
	return []


## Fine-grained frame filter called after get_visual_event_types() passes.
## Return false to discard a frame at collection time (e.g. notes-mode inputs).
## Default accepts every frame that passed the type filter.
func should_include_frame(_frame: Dictionary) -> bool:
	return true
