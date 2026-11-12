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


## Small dust puff kicked up by each footstep.
static func make_step_puff() -> GPUParticles3D:
	var p := make_run_dust()
	p.name = "StepPuff"
	p.amount = 7
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	return p


static var _debris_materials: Dictionary = {}


static func _debris_material(kind: String) -> StandardMaterial3D:
	if not _debris_materials.has(kind):
		var mat := StandardMaterial3D.new()
		match kind:
			"wood":
				mat.albedo_color = Color(0.52, 0.36, 0.2)
				mat.roughness = 0.85
			"metal":
				# Ricochet sparks: bright additive streaks.
				mat = _get_puff_material().duplicate() as StandardMaterial3D
				mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_:
				mat.albedo_color = Color(0.56, 0.55, 0.52)
				mat.roughness = 0.9
		_debris_materials[kind] = mat
	return _debris_materials[kind]


## Surface-specific impact burst. kind: "concrete" (chips), "wood" (splinters),
## "metal" (ricochet sparks). Local +Y is the direction the debris flies.
static func make_debris(kind: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Debris_" + kind
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.particle_flag_rotate_y = true
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = 300.0
	m.angular_velocity_max = 900.0
	match kind:
		"wood":
			p.amount = 12
			p.lifetime = 0.8
			m.spread = 50.0
			m.initial_velocity_min = 1.5
			m.initial_velocity_max = 4.5
			m.gravity = Vector3(0, -9.8, 0)
			m.scale_min = 0.5
			m.scale_max = 1.5
			var splinter := BoxMesh.new()
			splinter.size = Vector3(0.012, 0.07, 0.006)
			splinter.material = _debris_material(kind)
			p.draw_pass_1 = splinter
		"metal":
			p.amount = 14
			p.lifetime = 0.35
			m.particle_flag_rotate_y = false
			m.angular_velocity_min = 0.0
			m.angular_velocity_max = 0.0
			m.spread = 35.0
			m.initial_velocity_min = 5.0
			m.initial_velocity_max = 13.0
			m.gravity = Vector3(0, -6.0, 0)
			m.scale_min = 0.4
			m.scale_max = 1.0
			m.color_ramp = _ramp(
				[0.0, 0.4, 1.0],
				[Color(1.0, 1.0, 0.85, 1.0), Color(1.0, 0.7, 0.2, 1.0), Color(1.0, 0.3, 0.0, 0.0)])
			var spark := QuadMesh.new()
			spark.size = Vector2(0.03, 0.03)
			spark.material = _debris_material(kind)
			p.draw_pass_1 = spark
		_:
			p.amount = 12
			p.lifetime = 0.9
			m.spread = 45.0
			m.initial_velocity_min = 1.2
			m.initial_velocity_max = 4.0
			m.gravity = Vector3(0, -9.8, 0)
			m.scale_min = 0.4
			m.scale_max = 1.4
			var chip := BoxMesh.new()
			chip.size = Vector3(0.03, 0.02, 0.025)
			chip.material = _debris_material(kind)
			p.draw_pass_1 = chip
	p.process_material = m
	return p
