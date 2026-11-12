extends RefCounted
## Extra particle effects for the final polish pass: dust kicked up while
## sprinting and smoke when reloading. StandardMaterial3D billboards.
## Used through: const PolishFX := preload("res://scripts/polish_fx.gd")

static var _puff_material: StandardMaterial3D


static func _get_puff_material() -> StandardMaterial3D:
	if _puff_material == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		_puff_material = StandardMaterial3D.new()
		_puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_puff_material.billboard_keep_scale = true
		_puff_material.vertex_color_use_as_albedo = true
		_puff_material.albedo_texture = tex
		_puff_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_puff_material.disable_receive_shadows = true
	return _puff_material


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(offsets)
	grad.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


## Continuous dust trail at the player's feet (toggle `emitting` while sprinting).
static func make_run_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "RunDust"
	p.amount = 26
	p.lifetime = 0.8
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.22, 0.02, 0.22)
	m.direction = Vector3(0, 1, 0)
	m.spread = 60.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 1.1
	m.gravity = Vector3(0, 0.3, 0)
	m.damping_min = 0.8
	m.damping_max = 1.6
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.6
	m.scale_max = 1.5
	m.color_ramp = _ramp(
		[0.0, 0.2, 1.0],
		[Color(0.68, 0.64, 0.57, 0.0), Color(0.68, 0.64, 0.57, 0.4), Color(0.72, 0.69, 0.62, 0.0)])
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	quad.material = _get_puff_material()
	p.draw_pass_1 = quad
	return p


## One-shot wisp of smoke rising from the weapon when a reload starts.
static func make_reload_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "ReloadSmoke"
	p.amount = 12
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.7
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.03
	m.direction = Vector3(0, 1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 0.15
	m.initial_velocity_max = 0.5
	m.gravity = Vector3(0, 0.5, 0)
	m.damping_min = 0.3
	m.damping_max = 0.8
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color_ramp = _ramp(
		[0.0, 0.15, 1.0],
		[Color(0.85, 0.85, 0.85, 0.0), Color(0.82, 0.82, 0.82, 0.38), Color(0.9, 0.9, 0.9, 0.0)])
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = _get_puff_material()
	p.draw_pass_1 = quad
	return p
