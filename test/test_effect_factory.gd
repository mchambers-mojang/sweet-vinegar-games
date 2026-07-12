extends GutTest

## Tests for EffectFactory — verifies that gating logic lives in the factory,
## not in individual effect classes.

var _original_particles_enabled: bool
var _original_shockwave_enabled: bool


func before_each() -> void:
	_original_particles_enabled = PlatformSettings.particle_effects_enabled
	_original_shockwave_enabled = PlatformSettings.shockwave_enabled


func after_each() -> void:
	PlatformSettings.particle_effects_enabled = _original_particles_enabled
	PlatformSettings.shockwave_enabled = _original_shockwave_enabled


# --- EffectFactory.neon_burst ---

func test_neon_burst_spawns_child_when_particles_enabled() -> void:
	PlatformSettings.particle_effects_enabled = true
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.neon_burst(parent, Vector2.ZERO, Color.WHITE, 4, 1.0)
	assert_eq(parent.get_child_count(), 1, "Expected one NeonBurst child")


func test_neon_burst_skips_child_when_particles_disabled() -> void:
	PlatformSettings.particle_effects_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.neon_burst(parent, Vector2.ZERO, Color.WHITE, 4, 1.0)
	assert_eq(parent.get_child_count(), 0, "No child should be added when particles are disabled")


# --- EffectFactory.neon_ring ---

func test_neon_ring_spawns_child_when_shockwave_enabled() -> void:
	PlatformSettings.shockwave_enabled = true
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.neon_ring(parent, Vector2.ZERO, Color.WHITE)
	assert_eq(parent.get_child_count(), 1, "Expected one NeonRing child")


func test_neon_ring_skips_child_when_shockwave_disabled() -> void:
	PlatformSettings.shockwave_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.neon_ring(parent, Vector2.ZERO, Color.WHITE)
	assert_eq(parent.get_child_count(), 0, "No child should be added when shockwave is disabled")


# --- EffectFactory.neon_sweep ---

func test_neon_sweep_spawns_child_when_particles_enabled() -> void:
	PlatformSettings.particle_effects_enabled = true
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.neon_sweep(parent, Rect2(Vector2.ZERO, Vector2(100, 20)))
	assert_eq(parent.get_child_count(), 1, "Expected one NeonSweep child")


func test_neon_sweep_skips_child_when_particles_disabled() -> void:
	PlatformSettings.particle_effects_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.neon_sweep(parent, Rect2(Vector2.ZERO, Vector2(100, 20)))
	assert_eq(parent.get_child_count(), 0, "No child should be added when particles are disabled")


# --- EffectFactory.glass_shatter ---

func test_glass_shatter_spawns_child_when_particles_enabled() -> void:
	PlatformSettings.particle_effects_enabled = true
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.glass_shatter(parent, Rect2(Vector2.ZERO, Vector2(40, 40)), Color.WHITE, 4)
	assert_eq(parent.get_child_count(), 1, "Expected one GlassShatter child")


func test_glass_shatter_skips_child_when_particles_disabled() -> void:
	PlatformSettings.particle_effects_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	EffectFactory.glass_shatter(parent, Rect2(Vector2.ZERO, Vector2(40, 40)), Color.WHITE, 4)
	assert_eq(parent.get_child_count(), 0, "No child should be added when particles are disabled")


# --- Pure effect classes bypass gating ---

func test_neon_burst_create_always_spawns_regardless_of_settings() -> void:
	PlatformSettings.particle_effects_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	NeonBurst.create(parent, Vector2.ZERO, Color.WHITE, 4, 1.0)
	assert_eq(parent.get_child_count(), 1, "NeonBurst.create() should always spawn — gating lives in EffectFactory")


func test_neon_sweep_create_always_spawns_regardless_of_settings() -> void:
	PlatformSettings.particle_effects_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	NeonSweep.create(parent, Rect2(Vector2.ZERO, Vector2(100, 20)))
	assert_eq(parent.get_child_count(), 1, "NeonSweep.create() should always spawn — gating lives in EffectFactory")


func test_glass_shatter_create_always_spawns_regardless_of_settings() -> void:
	PlatformSettings.particle_effects_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	GlassShatter.create(parent, Rect2(Vector2.ZERO, Vector2(40, 40)), Color.WHITE, 4)
	assert_eq(parent.get_child_count(), 1, "GlassShatter.create() should always spawn — gating lives in EffectFactory")


func test_neon_ring_create_always_spawns_regardless_of_settings() -> void:
	PlatformSettings.shockwave_enabled = false
	var parent := Node2D.new()
	add_child_autofree(parent)
	NeonRing.create(parent, Vector2.ZERO, Color.WHITE)
	assert_eq(parent.get_child_count(), 1, "NeonRing.create() should always spawn — gating lives in EffectFactory")
