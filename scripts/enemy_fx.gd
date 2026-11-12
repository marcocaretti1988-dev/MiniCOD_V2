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
	p.add_child(_make_lingering_smoke())
	return p


## Slow grey smoke that hangs over a fallen soldier for a few seconds.
static func _make_lingering_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "LingeringSmoke"
	p.amount = 22
	p.lifetime = 3.6
	p.one_shot = true
	p.explosiveness = 0.35
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(0.4, 0.1, 0.7)
	m.direction = Vector3(0, 1, 0)
	m.spread = 30.0
	m.initial_velocity_min = 0.25
	m.initial_velocity_max = 0.7
	m.gravity = Vector3(0.12, 0.18, 0.05)
	m.damping_min = 0.2
	m.damping_max = 0.5
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 1.0
	m.scale_max = 2.4
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.5, 0.5, 0.5, 0.0),
		Color(0.48, 0.47, 0.46, 0.3),
		Color(0.6, 0.6, 0.6, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	m.color_ramp = ramp_tex
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = _get_dust_material()
	p.draw_pass_1 = quad
	return p


## Short dark-red puff when a soldier is hit (no gore, just a puff).
static func make_blood_puff() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "BloodPuff"
	p.amount = 14
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.05
	m.direction = Vector3(0, 0.3, -1)
	m.spread = 55.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 2.4
	m.gravity = Vector3(0, -2.5, 0)
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.42, 0.02, 0.02, 0.75),
		Color(0.3, 0.015, 0.015, 0.55),
		Color(0.22, 0.01, 0.01, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	m.color_ramp = ramp_tex
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	quad.material = _get_dust_material()
	p.draw_pass_1 = quad
	return p


static var _camo_texture: ImageTexture


## Three-tone camouflage pattern (light grey, tinted by each material's colour).
static func get_camo_texture() -> ImageTexture:
	if _camo_texture != null:
		return _camo_texture
	var size := 128
	var big := FastNoiseLite.new()
	big.seed = 71
	big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	big.frequency = 0.035
	big.fractal_octaves = 2
	var small := FastNoiseLite.new()
	small.seed = 72
	small.noise_type = FastNoiseLite.TYPE_SIMPLEX
	small.frequency = 0.09
	var a := big.get_seamless_image(size, size)
	var b := small.get_seamless_image(size, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := 1.0                                   # base tone
			if a.get_pixel(x, y).r > 0.56:
				v = 0.55                                    # dark blotches
			elif b.get_pixel(x, y).r > 0.62:
				v = 0.75                                    # mid blotches
			elif a.get_pixel(x, y).r < 0.36:
				v = 1.25                                    # light blotches
			v *= rng.randf_range(0.93, 1.0)                 # fabric grain
			v = clampf(v * 0.78, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_camo_texture = ImageTexture.create_from_image(img)
	return _camo_texture
