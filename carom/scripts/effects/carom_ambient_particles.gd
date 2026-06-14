class_name CaromAmbientParticles
extends Node3D

## Ambient floating neon particles for the Carom arena.
## Creates a subtle laser-lit dust-mote atmosphere without impeding gameplay.
## Add as a child of CaromArena and call setup() from _ready().

const PARTICLE_COUNT: int = 40
const PARTICLE_LIFETIME: float = 10.0
const SPEED_MIN: float = 0.2
const SPEED_MAX: float = 0.5

var _particles: GPUParticles3D = null


## Build and activate the ambient particle system for the given arena dimensions.
## Does nothing when particle effects are disabled in PlatformSettings.
func setup(arena_width: float, arena_depth: float) -> void:
	if not PlatformSettings.particle_effects_enabled:
		return
	_build_particles(arena_width, arena_depth)


func _build_particles(arena_width: float, arena_depth: float) -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "NeonMotes"
	_particles.amount = PARTICLE_COUNT
	_particles.lifetime = PARTICLE_LIFETIME
	_particles.emitting = true
	_particles.fixed_fps = 30
	_particles.preprocess = PARTICLE_LIFETIME  # pre-warm so motes fill the arena on load
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ParticleProcessMaterial.new()
	# Emit throughout the arena volume
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(arena_width * 0.5, 1.5, arena_depth * 0.5)
	# Slow upward drift with lateral spread for the dust-in-laser-light feel
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 60.0
	mat.initial_velocity_min = SPEED_MIN
	mat.initial_velocity_max = SPEED_MAX
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.04
	mat.scale_max = 0.09

	# Color ramp: cyan → magenta → cyan over each particle's lifetime, low alpha
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.0, 1.0, 1.0, 0.35),  # cyan
		Color(1.0, 0.0, 1.0, 0.45),  # magenta
		Color(0.0, 1.0, 1.0, 0.35),  # cyan (wraps back)
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	_particles.process_material = mat

	# Tiny sphere mesh — roughly the size of a dust mote in world units
	var draw_pass := SphereMesh.new()
	draw_pass.radius = 0.05
	draw_pass.height = 0.10
	_particles.draw_pass_1 = draw_pass

	# Unshaded, additive blend — particle color (from ramp) drives albedo
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color.WHITE
	mesh_mat.emission_energy_multiplier = 2.0
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_particles.material_override = mesh_mat

	add_child(_particles)
