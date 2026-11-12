extends Node3D
## Objective beacon. Stand inside its ring for 3 seconds to activate it.
## Yellow pulsing emissive StandardMaterial3D, light halo, GPUParticles3D burst
## on activation, then it turns green.

const ShipTex := preload("res://scripts/shipyard_textures.gd")

signal progress_changed(beacon: Node3D, progress: float)
signal activated(beacon: Node3D)

@export var activation_time: float = 3.0
@export var radius: float = 2.2
@export var idle_color: Color = Color(1.0, 0.8, 0.1)
@export var active_color: Color = Color(0.25, 1.0, 0.4)

var is_active: bool = false
var progress: float = 0.0

var _player: Node3D
var _time: float = 0.0
var _core_material: StandardMaterial3D
var _ring_material: StandardMaterial3D
var _halo_material: StandardMaterial3D
var _beam_material: StandardMaterial3D
var _light: OmniLight3D
var _burst: GPUParticles3D
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("beacons")
	_time = randf() * TAU
	_build()


func _process(delta: float) -> void:
	_time += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if not is_active:
		var inside := false
		if _player != null:
			var d := _player.global_position - global_position
			inside = Vector2(d.x, d.z).length() <= radius and absf(d.y) < 3.0
		var before := progress
		if inside:
			progress = minf(progress + delta / activation_time, 1.0)
		else:
			progress = maxf(progress - delta * 0.8, 0.0)
		if not is_equal_approx(before, progress):
			progress_changed.emit(self, progress)
		if progress >= 1.0:
			_activate()

	_update_glow()


func _update_glow() -> void:
	var color := active_color if is_active else idle_color
	# Slow pulse while idle, faster while being activated, steady once done.
	var speed := 2.4 + progress * 10.0
	var pulse := 1.0 if is_active else 0.5 + 0.5 * sin(_time * speed)
	_core_material.emission = color
	_core_material.emission_energy_multiplier = 1.4 + 2.6 * pulse
	_ring_material.emission = color
	_ring_material.emission_energy_multiplier = 1.0 + 2.0 * pulse + progress * 2.0
	_halo_material.albedo_color = Color(color.r, color.g, color.b, 0.25 + 0.3 * pulse)
	_beam_material.albedo_color = Color(color.r, color.g, color.b, 0.1 + 0.1 * pulse)
	_light.light_color = color
	_light.light_energy = 1.2 + 1.8 * pulse
	# The ground ring tightens as the activation fills up.
	var s := 1.0 - 0.25 * progress if not is_active else 0.6
	_ring.scale = Vector3(s, 1.0, s)


func _activate() -> void:
	is_active = true
	progress = 1.0
	_burst.restart()
	_burst.emitting = true
	progress_changed.emit(self, 0.0)
	activated.emit(self)


func _build() -> void:
	var metal := ShipTex.make_painted_metal(Color(0.16, 0.17, 0.19), 95, false, Vector3(1.0, 1.0, 1.0), false, 0.7, 0.4, 0.5)

	# Base and top cap (metal).
	_add_cylinder(0.55, 0.18, Vector3(0, 0.09, 0), metal)
	_add_cylinder(0.3, 0.12, Vector3(0, 0.24, 0), metal)
	_add_cylinder(0.22, 0.1, Vector3(0, 1.75, 0), metal)

	# Emissive core.
	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = Color(0.9, 0.75, 0.3)
	_core_material.emission_enabled = true
	_core_material.emission = idle_color
	_core_material.emission_energy_multiplier = 3.0
	_core_material.roughness = 0.3
	_add_cylinder(0.16, 1.4, Vector3(0, 1.0, 0), _core_material)

	# Ring on the ground marking the activation area.
	_ring_material = StandardMaterial3D.new()
	_ring_material.albedo_color = Color(0.9, 0.75, 0.3)
	_ring_material.emission_enabled = true
	_ring_material.emission = idle_color
	_ring_material.emission_energy_multiplier = 2.0
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.07
	torus.outer_radius = radius + 0.07
	torus.rings = 48
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _ring_material
	_ring.position = Vector3(0, 0.05, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# Light halo: additive billboard glow + a tall faint beam + a real light.
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	glow.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow
	glow_tex.width = 128
	glow_tex.height = 128
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)

	_halo_material = StandardMaterial3D.new()
	_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_material.albedo_texture = glow_tex
	_halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo_material.disable_receive_shadows = true
	_halo_material.disable_fog = true
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(3.6, 3.6)
	var halo := MeshInstance3D.new()
	halo.mesh = halo_quad
	halo.material_override = _halo_material
	halo.position = Vector3(0, 1.2, 0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_material.disable_receive_shadows = true
	_beam_material.disable_fog = true
	var beam := _add_cylinder(0.12, 16.0, Vector3(0, 9.8, 0), _beam_material)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.4, 0)
	_light.light_color = idle_color
	_light.light_energy = 2.0
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	add_child(_light)

	_burst = _make_burst(glow_tex)
	add_child(_burst)


func _add_cylinder(cyl_radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = cyl_radius
	mesh.bottom_radius = cyl_radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	add_child(part)
	return part


## Fountain of bright sparks fired when the beacon is activated.
func _make_burst(glow_tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ActivationBurst"
	p.amount = 90
	p.lifetime = 1.3
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.position = Vector3(0, 1.2, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, -7.0, 0)
	m.scale_min = 0.5
	m.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 1.0, 0.85, 1.0), Color(1.0, 0.85, 0.2, 1.0), Color(0.25, 1.0, 0.4, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	m.color_ramp = ramp_tex
	p.process_material = m

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = glow_tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = mat
	p.draw_pass_1 = quad
	return p
