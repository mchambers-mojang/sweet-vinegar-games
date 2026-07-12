class_name EffectFactory

## Central gating layer for all 2D visual effects.
##
## Reads PlatformSettings once here so individual effect classes remain pure
## (no PlatformSettings dependency in their create methods).
##
## Usage: replace direct Effect.create() calls with EffectFactory.effect_name().
## This makes it trivial to add new effects and to test gating without mocking
## PlatformSettings globally.


## Spawn a [NeonBurst] particle burst at [param pos] inside [param parent].
## Gated by PlatformSettings.particle_effects_enabled.
static func neon_burst(parent: Node, pos: Vector2, color: Color, count: int = 16, intensity: float = 1.0) -> void:
	if not PlatformSettings.particle_effects_enabled:
		return
	NeonBurst.create(parent, pos, color, count, intensity)


## Spawn a [NeonRing] shockwave distortion centred on [param world_pos].
## Gated by PlatformSettings.shockwave_enabled.
static func neon_ring(parent: Node, world_pos: Vector2, color: Color, max_radius: float = 80.0, duration: float = 0.4, amplitude: float = 1.0) -> void:
	if not PlatformSettings.shockwave_enabled:
		return
	NeonRing.create(parent, world_pos, color, max_radius, duration, amplitude)


## Spawn a [NeonSweep] wipe across [param rect].
## Gated by PlatformSettings.particle_effects_enabled.
static func neon_sweep(parent: Node, rect: Rect2, horizontal: bool = true, color: Color = Color(0.0, 2.0, 1.5)) -> void:
	if not PlatformSettings.particle_effects_enabled:
		return
	NeonSweep.create(parent, rect, horizontal, color)


## Spawn a [GlassShatter] shard explosion covering [param rect].
## Gated by PlatformSettings.particle_effects_enabled.
static func glass_shatter(parent: Node, rect: Rect2, color: Color, shard_count: int = 12) -> void:
	if not PlatformSettings.particle_effects_enabled:
		return
	GlassShatter.create(parent, rect, color, shard_count)
