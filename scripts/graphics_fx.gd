extends RefCounted
## Scene-wide graphics setup: sunset sky with procedural clouds, ACES tone
## mapping, sun + fill lights, fog, bloom, SSAO, colour grading and, on the
## Forward+ renderer only, SDFGI, SSR, volumetric fog.
## Called by the GameSettings autoload for every WorldEnvironment that enters
## the tree, so the menu and the level always look the same.
## Used through: const GraphicsFX := preload("res://scripts/graphics_fx.gd")

static var _cloud_texture: ImageTexture
static var _grade_texture: GradientTexture1D


## Equirectangular cloud layer (added on top of the sky gradient).
static func get_cloud_texture() -> ImageTexture:
	if _cloud_texture != null:
		return _cloud_texture
	var w := 512
	var h := 256
	var noise := FastNoiseLite.new()
	noise.seed = 404
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.1
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.55
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var lit := Color(1.0, 0.56, 0.3)      # underside lit by the low sun
	var shade := Color(0.42, 0.3, 0.42)   # violet body
	for y in h:
		var v := float(y) / float(h)          # 0 = zenith, 0.5 = horizon
		var lat := (0.5 - v) * PI
		# Clouds only above the horizon, thinning out towards the zenith.
		var band := clampf((0.5 - v) / 0.06, 0.0, 1.0) * clampf(0.35 + v * 1.6, 0.0, 1.0)
		if band <= 0.0:
			continue
		var cl := cos(lat)
		var sl := sin(lat)
		for x in w:
			var lon := float(x) / float(w) * TAU
			# Sample 3D noise on the sphere (stretched horizontally) so the texture wraps.
			var n := noise.get_noise_3d(cos(lon) * cl, sl * 3.2, sin(lon) * cl) * 0.5 + 0.5
			var a := clampf((n - 0.47) * 4.5, 0.0, 1.0) * band
			if a <= 0.0:
				continue
			var c := shade.lerp(lit, clampf((n - 0.5) * 3.0 + (v - 0.25) * 1.5, 0.0, 1.0)) * (a * 0.6)
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	_cloud_texture = ImageTexture.create_from_image(img)
	return _cloud_texture


## Colour grade: slightly cool shadows, warm highlights.
static func get_grade_texture() -> GradientTexture1D:
	if _grade_texture == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(0.0, 0.0, 0.02), Color(0.5, 0.495, 0.49), Color(1.0, 0.97, 0.9)])
		_grade_texture = GradientTexture1D.new()
		_grade_texture.gradient = grad
		_grade_texture.width = 64
	return _grade_texture


static func _set_if_present(object: Object, property: String, value: Variant) -> void:
	if property in object:
		object.set(property, value)


## quality: "low", "medium" or "high". forward_plus: true when running on Forward+.
## mobile: phone profile (lighter shadows, no SSAO).
static func setup_scene(world: WorldEnvironment, quality: String,
		forward_plus: bool, mobile: bool = false) -> void:
	var env := world.environment
	if env == null:
		return
	var low := quality == "low"
	var high := quality == "high"

	# --- Sky: sunset gradient + clouds ---
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = Color(0.1, 0.2, 0.48)
		sky.sky_horizon_color = Color(1.0, 0.56, 0.3)
		sky.sky_curve = 0.085
		sky.ground_horizon_color = Color(0.95, 0.5, 0.28)
		sky.ground_bottom_color = Color(0.2, 0.15, 0.14)
		sky.ground_curve = 0.04
		sky.sun_angle_max = 22.0
		sky.sun_curve = 0.12
		sky.sky_cover = get_cloud_texture()
		sky.sky_cover_modulate = Color(1.0, 1.0, 1.0)
		env.sky.radiance_size = Sky.RADIANCE_SIZE_128 if low else Sky.RADIANCE_SIZE_256
		if mobile:
			env.sky.radiance_size = Sky.RADIANCE_SIZE_64 \
				if low else Sky.RADIANCE_SIZE_128

	# --- Tone mapping and colour grading ---
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# 1.1 on Forward+; the Compatibility renderer clips highlights sooner, so it runs lower.
	env.tonemap_exposure = 1.1 if forward_plus else 0.8
	env.tonemap_white = 14.0  # keeps the sunlit concrete from clipping to white
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.05
	env.adjustment_color_correction = get_grade_texture()
	env.ambient_light_energy = 0.55

	# --- Bloom ---
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.75
	_set_if_present(env, "glow_strength", 0.6)
	env.glow_bloom = 0.08
	if mobile and low:
		env.glow_enabled = false

	# --- SSAO ---
	env.ssao_enabled = not low and not mobile
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.4

	# --- Forward+ only: SSR, SDFGI, volumetric fog ---
	env.ssr_enabled = forward_plus and not low
	_set_if_present(env, "ssr_max_steps", 40)
	env.sdfgi_enabled = forward_plus and high
	if env.sdfgi_enabled:
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_use_occlusion = true
		env.sdfgi_energy = 1.0
		RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_4)
		RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
		RenderingServer.gi_set_use_half_resolution(true)
	var volumetric := forward_plus and not low
	env.volumetric_fog_enabled = volumetric
	if volumetric:
		env.volumetric_fog_density = 0.015
		env.volumetric_fog_albedo = Color(0.92, 0.86, 0.8)
		env.volumetric_fog_sky_affect = 0.2
		env.volumetric_fog_ambient_inject = 0.3
		env.volumetric_fog_length = 90.0
		env.volumetric_fog_gi_inject = 0.6
		env.volumetric_fog_anisotropy = 0.5

	# --- Distance + height fog ---
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.68, 0.5)
	env.fog_density = 0.003 if volumetric else 0.011
	env.fog_height = 3.5
	env.fog_height_density = 0.05
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.2
	env.fog_sun_scatter = 0.25

	_setup_lights(world.get_parent(), quality)
	if mobile:
		_setup_mobile_sun(world.get_parent(), quality)


## Phone shadows: fewer cascades over a shorter distance.
## Every cascade redraws all the shadow casters, so this is
## the setting that costs the most on a phone.
static func _setup_mobile_sun(root: Node, quality: String) -> void:
	if root == null:
		return
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	var two := DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	var four := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = false
	if quality == "low":
		sun.directional_shadow_mode = two
		sun.directional_shadow_max_distance = 35.0
	elif quality == "medium":
		sun.directional_shadow_mode = two
		sun.directional_shadow_max_distance = 50.0
	else:
		sun.directional_shadow_mode = four
		sun.directional_shadow_max_distance = 80.0


static func _setup_lights(root: Node, quality: String) -> void:
	if root == null:
		return
	# --- Sun: low, warm, long soft shadows ---
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-21.0, -38.0, 0.0)
		sun.light_color = Color(1.0, 0.72, 0.46)
		sun.light_energy = 3.0
		sun.light_angular_distance = 0.7
		sun.shadow_enabled = true
		sun.shadow_bias = 0.015
		sun.shadow_normal_bias = 1.2
		sun.shadow_blur = 1.2
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 150.0
		sun.directional_shadow_blend_splits = quality != "low"
		sun.directional_shadow_fade_start = 0.85

	# --- Hemisphere fill: blue from the sky, brown bounce from the ground ---
	if root.get_node_or_null("FillSky") == null:
		for data in [["FillSky", -90.0, Color(0.5, 0.68, 1.0)], ["FillGround", 90.0, Color(0.55, 0.4, 0.26)]]:
			var fill := DirectionalLight3D.new()
			fill.name = data[0]
			fill.rotation_degrees = Vector3(data[1], 0.0, 0.0)
			fill.light_color = data[2]
			fill.light_energy = 0.4
			fill.light_specular = 0.0
			fill.shadow_enabled = false
			fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
			root.add_child(fill)

	# --- Point lights (warehouse lamps, crane floodlights): warm, no shadows ---
	for child in root.get_children():
		var omni := child as OmniLight3D
		if omni != null:
			omni.light_color = Color(1.0, 0.8, 0.55)
			omni.omni_range = 20.0
			omni.omni_attenuation = 1.3
			omni.light_energy = 3.2
			omni.shadow_enabled = false
