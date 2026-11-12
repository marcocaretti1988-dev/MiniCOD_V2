extends RefCounted
## Shared weapon materials and particle effect builders (all made by code).
## Used through: const WeaponFX := preload("res://scripts/weapon_fx.gd")

static var _grain_cache: Dictionary = {}
static var _glow_texture: GradientTexture2D
static var _flash_material: StandardMaterial3D
static var _spark_material: StandardMaterial3D
static var _dust_material: StandardMaterial3D
static var _brass_material: StandardMaterial3D


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

## Small brushed grain texture so weapon parts are not flat colours.
static func _grain_texture(seed_value: int, streaks: bool) -> ImageTexture:
	var key := "%d_%s" % [seed_value, streaks]
	if _grain_cache.has(key):
		return _grain_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		var row := rng.randf_range(0.86, 1.0) if streaks else 1.0
		for x in size:
			var v := clampf(row * rng.randf_range(0.88, 1.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_grain_cache[key] = tex
	return tex


## Metal parts: metallic 0.7, roughness 0.35.
static func make_metal_material(tint: Color = Color(0.2, 0.21, 0.23)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = _grain_texture(3, true)
	mat.metallic = 0.7
	mat.roughness = 0.35
	mat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	return mat


## Grip / polymer parts: roughness 0.8.
static func make_grip_material(tint: Color = Color(0.11, 0.1, 0.09)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = _grain_texture(9, false)
	mat.metallic = 0.0
	mat.roughness = 0.8
	mat.uv1_scale = Vector3(3.0, 3.0, 3.0)
	return mat


static func _get_glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = grad
		_glow_texture.width = 64
		_glow_texture.height = 64
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(0.5, 0.0)
	return _glow_texture


static func _make_billboard_material(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _get_glow_texture()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array(offsets)
	grad.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex


# ---------------------------------------------------------------------------
# Particle effects
# ---------------------------------------------------------------------------

## Muzzle flash: short additive burst pointing along -Z of the node.
static func make_muzzle_flash(flash_size: float = 0.16) -> GPUParticles3D:
	if _flash_material == null:
		_flash_material = _make_billboard_material(true)
	var p := GPUParticles3D.new()
	p.name = "MuzzleFlash"
	p.amount = 7
	p.lifetime = 0.06
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0, -1)
	m.spread = 22.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 4.0
	m.gravity = Vector3.ZERO
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color_ramp = _ramp(
		[0.0, 0.4, 1.0],
		[Color(1.0, 0.95, 0.75, 1.0), Color(1.0, 0.62, 0.18, 0.9), Color(1.0, 0.3, 0.05, 0.0)]
	)
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(flash_size, flash_size)
	quad.material = _flash_material
	p.draw_pass_1 = quad
	p.add_child(_make_muzzle_smoke(flash_size))
	return p


## Thin grey smoke that drifts off the muzzle for 0.4 s after each shot.
static func _make_muzzle_smoke(flash_size: float) -> GPUParticles3D:
	if _dust_material == null:
		_dust_material = _make_billboard_material(false)
	var p := GPUParticles3D.new()
	p.name = "MuzzleSmoke"
	p.amount = 6
	p.lifetime = 0.4
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 0.25, -1)
	m.spread = 16.0
	m.initial_velocity_min = 0.4
	m.initial_velocity_max = 1.6
	m.gravity = Vector3(0, 0.7, 0)
	m.damping_min = 1.5
	m.damping_max = 3.0
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color_ramp = _ramp(
		[0.0, 0.25, 1.0],
		[Color(0.75, 0.74, 0.72, 0.0), Color(0.72, 0.71, 0.7, 0.3), Color(0.8, 0.8, 0.8, 0.0)]
	)
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(flash_size * 0.75, flash_size * 0.75)
	quad.material = _dust_material
	p.draw_pass_1 = quad
	return p


## Impact effect: sparks + a small dust puff. Local +Y is the surface normal.
static func make_impact() -> Node3D:
	if _spark_material == null:
		_spark_material = _make_billboard_material(true)
	if _dust_material == null:
		_dust_material = _make_billboard_material(false)

	var root := Node3D.new()
	root.name = "Impact"

	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 16
	sparks.lifetime = 0.4
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.emitting = false
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 55.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 7.0
	sm.gravity = Vector3(0, -12.0, 0)
	sm.scale_min = 0.4
	sm.scale_max = 1.0
	sm.color_ramp = _ramp(
		[0.0, 0.3, 1.0],
		[Color(1.0, 0.97, 0.8, 1.0), Color(1.0, 0.65, 0.15, 1.0), Color(1.0, 0.25, 0.0, 0.0)]
	)
	sparks.process_material = sm
	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.035, 0.035)
	spark_quad.material = _spark_material
	sparks.draw_pass_1 = spark_quad
	root.add_child(sparks)

	var dust := GPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 5
	dust.lifetime = 0.55
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.emitting = false
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dm := ParticleProcessMaterial.new()
	dm.direction = Vector3(0, 1, 0)
	dm.spread = 35.0
	dm.initial_velocity_min = 0.3
	dm.initial_velocity_max = 1.2
	dm.gravity = Vector3(0, 0.4, 0)
	dm.angle_min = 0.0
	dm.angle_max = 360.0
	dm.scale_min = 0.6
	dm.scale_max = 1.4
	dm.color_ramp = _ramp(
		[0.0, 1.0],
		[Color(0.62, 0.6, 0.56, 0.5), Color(0.62, 0.6, 0.56, 0.0)]
	)
	dust.process_material = dm
	var dust_quad := QuadMesh.new()
	dust_quad.size = Vector2(0.22, 0.22)
	dust_quad.material = _dust_material
	dust.draw_pass_1 = dust_quad
	root.add_child(dust)
	return root


## One ejected brass shell flying towards local +X of the node (world space particles).
static func make_shell_emitter(shell_length: float = 0.022) -> GPUParticles3D:
	if _brass_material == null:
		_brass_material = StandardMaterial3D.new()
		_brass_material.albedo_color = Color(0.83, 0.62, 0.22)
		_brass_material.albedo_texture = _grain_texture(5, true)
		_brass_material.metallic = 0.85
		_brass_material.roughness = 0.3

	var p := GPUParticles3D.new()
	p.name = "Shell"
	p.amount = 1
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.collision_base_size = shell_length * 0.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var m := ParticleProcessMaterial.new()
	# Shells bounce on GPUParticlesCollision nodes (Forward+ / Mobile renderers).
	m.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	m.collision_bounce = 0.45
	m.collision_friction = 0.35
	m.direction = Vector3(1.0, 0.7, 0.15)
	m.spread = 12.0
	m.initial_velocity_min = 1.8
	m.initial_velocity_max = 2.8
	m.gravity = Vector3(0, -9.8, 0)
	m.particle_flag_rotate_y = true
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.angular_velocity_min = 500.0
	m.angular_velocity_max = 900.0
	p.process_material = m

	var shell := CylinderMesh.new()
	shell.top_radius = shell_length * 0.22
	shell.bottom_radius = shell_length * 0.24
	shell.height = shell_length
	shell.radial_segments = 8
	shell.rings = 1
	shell.material = _brass_material
	p.draw_pass_1 = shell
	return p


## Restarts a one-shot emitter (or every emitter under a node).
static func burst(node: Node) -> void:
	if node is GPUParticles3D:
		node.restart()
		node.emitting = true
	for child in node.get_children():
		burst(child)


# ---------------------------------------------------------------------------
# HD viewmodel materials (graphics upgrade)
# ---------------------------------------------------------------------------

## Black gun metal: metallic 0.8, roughness 0.35.
static func make_gun_metal(tint: Color = Color(0.085, 0.09, 0.1)) -> StandardMaterial3D:
	var mat := make_metal_material(tint)
	mat.metallic = 0.8
	mat.roughness = 0.35
	mat.metallic_specular = 0.6
	return mat


## Polymer furniture: roughness 0.6, with a stippled grip texture.
static func make_polymer(tint: Color = Color(0.07, 0.07, 0.075)) -> StandardMaterial3D:
	var mat := make_grip_material(tint)
	mat.roughness = 0.6
	mat.uv1_scale = Vector3(5.0, 5.0, 5.0)
	return mat


## Sight glass: transparent, metallic 1.0, roughness 0.05.
static func make_lens(tint: Color = Color(0.35, 0.55, 0.65, 0.2)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 1.0
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Small glowing dot (red dot sight, tritium night sights).
static func make_dot(color: Color = Color(1.0, 0.1, 0.05), energy: float = 4.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Tactical gloves and sleeves: fabric, roughness 0.9.
static func make_glove(tint: Color = Color(0.1, 0.1, 0.09)) -> StandardMaterial3D:
	var mat := make_grip_material(tint)
	mat.roughness = 0.9
	mat.uv1_scale = Vector3(6.0, 6.0, 6.0)
	return mat
