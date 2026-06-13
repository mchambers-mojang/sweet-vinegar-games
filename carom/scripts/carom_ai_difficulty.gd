class_name CaromAIDifficulty
extends Resource

## Defines AI behavior parameters for a given difficulty tier.

@export var difficulty_name: String = "Medium"

## Time (seconds) before AI reacts to puck movement changes.
@export var reaction_delay: float = 0.3

## Random aim offset cone in degrees (larger = less accurate).
@export var aim_spread_degrees: float = 12.0

## Multiplier on base fire interval (lower = shoots faster).
@export var fire_interval_multiplier: float = 1.0

## Probability (0-1) of choosing the optimal state vs. a random/suboptimal one.
@export var decision_quality: float = 0.7

## Whether AI attempts bank shots off walls.
@export var bank_shots_enabled: bool = false

## How well AI times reloads to safe windows (0 = random, 1 = perfect).
@export var reload_timing_quality: float = 0.5

## Speed multiplier for aim tracking (lower = sluggish aim).
@export var aim_tracking_speed: float = 0.7

## Minimum ammo before AI considers reloading (higher = more conservative).
@export var reload_threshold: int = 2

## Base fire interval in seconds (before multiplier).
@export var base_fire_interval: float = 1.0


static func easy() -> CaromAIDifficulty:
	var d := CaromAIDifficulty.new()
	d.difficulty_name = "Easy"
	d.reaction_delay = 0.6
	d.aim_spread_degrees = 25.0
	d.fire_interval_multiplier = 1.4
	d.decision_quality = 0.4
	d.bank_shots_enabled = false
	d.reload_timing_quality = 0.2
	d.aim_tracking_speed = 0.5
	d.reload_threshold = 1
	d.base_fire_interval = 1.2
	return d


static func medium() -> CaromAIDifficulty:
	var d := CaromAIDifficulty.new()
	d.difficulty_name = "Medium"
	d.reaction_delay = 0.3
	d.aim_spread_degrees = 12.0
	d.fire_interval_multiplier = 1.0
	d.decision_quality = 0.7
	d.bank_shots_enabled = false
	d.reload_timing_quality = 0.5
	d.aim_tracking_speed = 0.7
	d.reload_threshold = 2
	d.base_fire_interval = 1.0
	return d


static func hard() -> CaromAIDifficulty:
	var d := CaromAIDifficulty.new()
	d.difficulty_name = "Hard"
	d.reaction_delay = 0.15
	d.aim_spread_degrees = 5.0
	d.fire_interval_multiplier = 0.75
	d.decision_quality = 0.9
	d.bank_shots_enabled = true
	d.reload_timing_quality = 0.8
	d.aim_tracking_speed = 0.9
	d.reload_threshold = 3
	d.base_fire_interval = 0.8
	return d


static func brutal() -> CaromAIDifficulty:
	var d := CaromAIDifficulty.new()
	d.difficulty_name = "Brutal"
	d.reaction_delay = 0.05
	d.aim_spread_degrees = 2.0
	d.fire_interval_multiplier = 0.6
	d.decision_quality = 0.97
	d.bank_shots_enabled = true
	d.reload_timing_quality = 0.95
	d.aim_tracking_speed = 1.0
	d.reload_threshold = 4
	d.base_fire_interval = 0.65
	return d


static func get_preset(level: int) -> CaromAIDifficulty:
	match level:
		0: return easy()
		1: return medium()
		2: return hard()
		3: return brutal()
		_: return medium()
