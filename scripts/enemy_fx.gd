extends RefCounted
## Particle effects used by enemies (made by code).
## Used through: const EnemyFX := preload("res://scripts/enemy_fx.gd")

static var _puff_texture: GradientTexture2D
static var _dust_material: StandardMaterial3D


static func _get_dust_material() -> StandardMaterial3D:
	if _dust_material == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_puff_texture = GradientTexture2D.new()
		_puff_texture.gradient = grad
		_puff_texture.width = 64
		_puff_texture.height = 64
		_puff_texture.fill = GradientTexture2D.FILL_RADIAL
		_puff_texture.fill_from = Vector2(0.5, 0.5)
		_puff_texture.fill_to = Vector2(0.5, 0.0)

		_dust_material = StandardMaterial3D.new()
		_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_material.billboard_keep_scale = true
		_dust_material.vertex_color_use_as_albedo = true
		_dust_material.albedo_texture = _puff_texture
		_dust_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_dust_material.disable_receive_shadows = true
	return _dust_material


## Cloud of dust raised when a soldier falls to the ground.
static func make_death_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "DeathDust"
	p.amount = 28
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.5, 0.05, 0.9)
	m.direction = Vector3(0, 1, 0)
	m.spread = 75.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.8
	m.gravity = Vector3(0, 0.25, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.7
	m.scale_max = 1.8
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.66, 0.62, 0.55, 0.0),
		Color(0.66, 0.62, 0.55, 0.55),
		Color(0.7, 0.67, 0.6, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	m.color_ramp = ramp_tex
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = _get_dust_material()
	p.draw_pass_1 = quad
	return p
