extends GutTest

## Unit tests for CaromAmbientParticles — setup, particle settings, and settings integration.

const AmbientParticlesScript := preload("res://carom/scripts/effects/carom_ambient_particles.gd")


func _make_ambient() -> CaromAmbientParticles:
	var node: CaromAmbientParticles = AmbientParticlesScript.new()
	add_child_autoqfree(node)
	return node


# --- Default constants ---

func test_particle_count_in_range() -> void:
	assert_between(CaromAmbientParticles.PARTICLE_COUNT, 20, 40,
		"Particle count must be in the 20–40 range per spec")


func test_speed_min_in_range() -> void:
	assert_between(CaromAmbientParticles.SPEED_MIN, 0.2, 0.5,
		"Speed min must be in the 0.2–0.5 range per spec")


func test_speed_max_in_range() -> void:
	assert_between(CaromAmbientParticles.SPEED_MAX, 0.2, 0.5,
		"Speed max must be in the 0.2–0.5 range per spec")


# --- setup() with particle effects enabled ---

func test_setup_creates_particles_node_when_enabled() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes")
	assert_not_null(particles, "NeonMotes GPUParticles3D should be created when particles enabled")


func test_setup_particles_is_gpu_particles() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes")
	assert_true(particles is GPUParticles3D, "NeonMotes should be a GPUParticles3D")


func test_setup_particles_emitting() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	assert_true(particles.emitting, "Particles should be emitting after setup")


func test_setup_particle_amount() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	assert_eq(particles.amount, CaromAmbientParticles.PARTICLE_COUNT)


func test_setup_no_shadow_cast() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	assert_eq(particles.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"Ambient particles must not cast shadows")


func test_setup_has_process_material() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	assert_not_null(particles.process_material, "Process material must be set")


func test_setup_emission_box_uses_arena_width() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	var mat := particles.process_material as ParticleProcessMaterial
	assert_almost_eq(mat.emission_box_extents.x, 10.0, 0.001,
		"Emission box x should be half arena_width")


func test_setup_emission_box_uses_arena_depth() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	var mat := particles.process_material as ParticleProcessMaterial
	assert_almost_eq(mat.emission_box_extents.z, 6.0, 0.001,
		"Emission box z should be half arena_depth")


func test_setup_zero_gravity() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	var mat := particles.process_material as ParticleProcessMaterial
	assert_eq(mat.gravity, Vector3.ZERO, "Ambient particles should float — no gravity")


func test_setup_material_override_is_unshaded() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	var mat := particles.material_override as StandardMaterial3D
	assert_not_null(mat, "material_override should be a StandardMaterial3D")
	assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
		"Material must be unshaded for neon emissive look")


func test_setup_material_blend_mode_additive() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = true
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes") as GPUParticles3D
	var mat := particles.material_override as StandardMaterial3D
	assert_eq(mat.blend_mode, BaseMaterial3D.BLEND_MODE_ADD,
		"Material must use additive blending per spec")


# --- setup() with particle effects disabled ---

func test_setup_skipped_when_particles_disabled() -> void:
	var ambient := _make_ambient()
	PlatformSettings.particle_effects_enabled = false
	ambient.setup(20.0, 12.0)
	var particles := ambient.get_node_or_null("NeonMotes")
	assert_null(particles, "No particles should be created when particle effects are disabled")
	# Restore default
	PlatformSettings.particle_effects_enabled = true
