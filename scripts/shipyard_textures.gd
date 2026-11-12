extends RefCounted
## Procedural textures and materials for the shipyard map (all made by code).
## Used through: const ShipTex := preload("res://scripts/shipyard_textures.gd")

const MAP_SIZE := 80.0

static var _cache: Dictionary = {}


static func _noise_image(size: int, seed_value: int, frequency: float, octaves: int = 4, type: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = type
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise.get_seamless_image(size, size)


# ---------------------------------------------------------------------------
# Painted metal (containers, cranes, warehouse sheets) with rust
# ---------------------------------------------------------------------------

## Returns { "albedo": ImageTexture, "normal": ImageTexture }.
## ribs=true draws vertical corrugation (container walls).
static func make_painted_metal_textures(color: Color, seed_value: int, ribs: bool, rust_amount: float = 1.0) -> Dictionary:
	var size := 256
	var rust_img := _noise_image(size, seed_value, 0.012, 4)
	var grain_img := _noise_image(size, seed_value + 7, 0.09, 2)
	var streak_img := _noise_image(size, seed_value + 13, 0.05, 2)
	var albedo := Image.create(size, size, false, Image.FORMAT_RGB8)
	var height := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rust_dark := Color(0.3, 0.15, 0.07)
	var rust_light := Color(0.52, 0.28, 0.12)
	var rib_period := 32

	for y in size:
		# More rust near the top and bottom edges.
		var edge := clampf(1.0 - float(mini(y, size - 1 - y)) / 46.0, 0.0, 1.0)
		for x in size:
			var n := rust_img.get_pixel(x, y).r
			var g := grain_img.get_pixel(x, y).r
			# Vertical streaks: sample the streak noise with a squashed Y.
			var s := streak_img.get_pixel(x, (y / 6) % size).r

			var h := 0.5
			var shade := 1.0
			if ribs:
				var t := float(x % rib_period) / float(rib_period)
				# Trapezoid profile: flat valley, slope, flat ridge, slope.
				if t < 0.15:
					h = t / 0.15
				elif t < 0.5:
					h = 1.0
				elif t < 0.65:
					h = 1.0 - (t - 0.5) / 0.15
				else:
					h = 0.0
				shade = 0.86 + 0.14 * h

			var rust := clampf((n - 0.6) * 4.5, 0.0, 1.0)
			rust = clampf(rust + edge * (n * 1.5 - 0.35) + (s - 0.62) * 1.6 * edge, 0.0, 1.0)
			rust *= rust_amount

			var paint := color * (shade * (0.88 + 0.2 * g))
			# Faded / dirty patches in the paint.
			paint = paint.lerp(paint * 0.7, clampf((0.42 - n) * 2.5, 0.0, 1.0))
			var rust_color := rust_dark.lerp(rust_light, g) * (0.8 + 0.2 * shade)
			var c := paint.lerp(rust_color, clampf(rust, 0.0, 1.0))
			albedo.set_pixel(x, y, Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)))

			var bump := clampf(h * 0.8 + (g - 0.5) * 0.12 * rust, 0.0, 1.0)
			height.set_pixel(x, y, Color(bump, bump, bump))

	albedo.generate_mipmaps()
	height.bump_map_to_normal_map(5.0 if ribs else 2.0)
	height.generate_mipmaps(true)
	return {
		"albedo": ImageTexture.create_from_image(albedo),
		"normal": ImageTexture.create_from_image(height),
	}


## Painted metal material using triplanar mapping.
## uv_scale = 1 / metres per texture tile on each axis.
static func make_painted_metal(color: Color, seed_value: int, ribs: bool, uv_scale: Vector3,
		world_space: bool, metallic: float = 0.6, roughness: float = 0.4, rust_amount: float = 1.0) -> StandardMaterial3D:
	var key := "metal_%s_%d_%s_%s" % [color.to_html(false), seed_value, ribs, rust_amount]
	if not _cache.has(key):
		_cache[key] = make_painted_metal_textures(color, seed_value, ribs, rust_amount)
	var tex: Dictionary = _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex["albedo"]
	mat.normal_enabled = true
	mat.normal_texture = tex["normal"]
	mat.normal_scale = 0.8
	mat.metallic = metallic
	mat.roughness = roughness
	mat.metallic_specular = 0.5
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = world_space
	mat.uv1_scale = uv_scale
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


# ---------------------------------------------------------------------------
# Wood (crates, shelves)
# ---------------------------------------------------------------------------

static func _make_wood_texture() -> ImageTexture:
	if _cache.has("wood"):
		return _cache["wood"]
	var size := 128
	var grain := FastNoiseLite.new()
	grain.seed = 41
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.02
	grain.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var plank_tint: Array[float] = []
	for i in 4:
		plank_tint.append(rng.randf_range(0.82, 1.08))
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var base := Color(0.56, 0.38, 0.2)
	var border := 14
	for y in size:
		for x in size:
			var in_frame := x < border or y < border or x >= size - border or y >= size - border
			var plank := y / 32
			var gap := y % 32 < 2
			# Stretched noise = wood grain. Frame planks run the other way.
			var gx := float(x)
			var gy := float(y)
			var n := grain.get_noise_2d(gx * 0.6, gy * 9.0) if not in_frame else grain.get_noise_2d(gx * 9.0 + 300.0, gy * 0.6)
			var v := (0.92 + n * 0.28) * plank_tint[plank]
			if in_frame:
				v *= 0.78
				# Inner edge shadow of the frame.
				if x == border - 1 or y == border - 1 or x == size - border or y == size - border:
					v *= 0.6
			elif gap:
				v *= 0.45
			var c := base * v
			img.set_pixel(x, y, Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)))
	# Nails in the frame corners.
	for corner in [Vector2i(7, 7), Vector2i(size - 8, 7), Vector2i(7, size - 8), Vector2i(size - 8, size - 8)]:
		img.fill_rect(Rect2i(corner.x - 1, corner.y - 1, 3, 3), Color(0.16, 0.14, 0.13))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["wood"] = tex
	return tex


## Wood material, roughness 0.8. box_size maps one texture per box face.
static func make_wood_material(box_size: Vector3) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_wood_texture()
	mat.roughness = 0.8
	mat.metallic = 0.0
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(1.0 / box_size.x, 1.0 / box_size.y, 1.0 / box_size.z)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


# ---------------------------------------------------------------------------
# Barrels, sandbags
# ---------------------------------------------------------------------------

## Metal barrel. CylinderMesh maps its side on the top half of the texture.
static func make_barrel_material(color: Color, seed_value: int) -> StandardMaterial3D:
	var key := "barrel_%s_%d" % [color.to_html(false), seed_value]
	if not _cache.has(key):
		var size := 128
		var rust_img := _noise_image(size, seed_value, 0.03, 3)
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		var rust_color := Color(0.4, 0.2, 0.09)
		for y in size:
			var band := false
			if y < size / 2:
				var v := float(y) / float(size / 2)
				band = absf(v - 0.33) < 0.035 or absf(v - 0.67) < 0.035 or v < 0.05 or v > 0.95
			for x in size:
				var n := rust_img.get_pixel(x, y).r
				var c := color * (0.85 + 0.25 * n)
				if band:
					c = c * 0.62
				c = c.lerp(rust_color * (0.7 + 0.6 * n), clampf((n - 0.62) * 5.0, 0.0, 1.0))
				img.set_pixel(x, y, Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)))
		img.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _cache[key]
	mat.metallic = 0.7
	mat.roughness = 0.35
	return mat


## Burlap sandbag, roughness 1.0.
static func make_sandbag_material() -> StandardMaterial3D:
	if not _cache.has("sandbag"):
		var size := 64
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var img := Image.create(size, size, false, Image.FORMAT_RGB8)
		var base := Color(0.6, 0.53, 0.38)
		for y in size:
			for x in size:
				# Weave: alternate brighter warp and weft threads.
				var weave := 1.0 if (x / 2 + y / 2) % 2 == 0 else 0.86
				var v := weave * rng.randf_range(0.85, 1.05)
				var c := base * v
				img.set_pixel(x, y, Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0)))
		img.generate_mipmaps()
		_cache["sandbag"] = ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _cache["sandbag"]
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(4.0, 3.0, 1.0)
	return mat


# ---------------------------------------------------------------------------
# Puddles and tire marks
# ---------------------------------------------------------------------------

## Reflective puddle: metallic, very low roughness, irregular alpha shape.
static func make_puddle_material(seed_value: int) -> StandardMaterial3D:
	var key := "puddle_%d" % seed_value
	if not _cache.has(key):
		var size := 128
		var shape := FastNoiseLite.new()
		shape.seed = seed_value
		shape.frequency = 0.025
		shape.fractal_octaves = 3
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var p := Vector2(float(x) / size - 0.5, float(y) / size - 0.5)
				var d := p.length() * 2.0 + shape.get_noise_2d(x, y) * 0.45
				var a := clampf((0.78 - d) * 7.0, 0.0, 1.0) * 0.88
				# Light albedo: a metallic surface tints its reflection with the albedo.
				img.set_pixel(x, y, Color(0.6, 0.66, 0.72, a))
		img.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _cache[key]
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 1.0
	mat.roughness = 0.04
	mat.metallic_specular = 1.0
	mat.render_priority = 2
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Tire mark texture: two tread bands along U, fading at the ends.
static func make_tire_mark_texture(seed_value: int) -> ImageTexture:
	var key := "tire_%d" % seed_value
	if _cache.has(key):
		return _cache[key]
	var w := 512
	var h := 128
	var breakup := FastNoiseLite.new()
	breakup.seed = seed_value
	breakup.frequency = 0.02
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.04, 0.045, 0.0))
	for y in h:
		# Two bands: rows 8..48 and 80..120.
		var band_v := -1.0
		if y >= 8 and y < 48:
			band_v = float(y - 8) / 40.0
		elif y >= 80 and y < 120:
			band_v = float(y - 80) / 40.0
		if band_v < 0.0:
			continue
		var edge := clampf(sin(band_v * PI) * 2.2, 0.0, 1.0)
		for x in w:
			var fade := clampf(sin(float(x) / float(w) * PI) * 2.5, 0.0, 1.0)
			# Chevron tread pattern.
			var tread := 1.0 if posmod(x + int(absf(band_v - 0.5) * 36.0), 12) < 8 else 0.45
			var n := breakup.get_noise_2d(x, y * 3.0) * 0.5 + 0.5
			var a := clampf(edge * fade * tread * (0.55 + n * 0.7), 0.0, 1.0) * 0.92
			img.set_pixel(x, y, Color(0.02, 0.02, 0.022, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Flat material used when real Decal nodes are not supported by the renderer.
static func make_tire_mark_material(seed_value: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = make_tire_mark_texture(seed_value)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.75
	mat.metallic = 0.0
	mat.render_priority = 1
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


## Emissive lamp material (glows with bloom).
static func make_emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 0.3
	return mat


# ---------------------------------------------------------------------------
# Painted ground lines (transparent layer over the concrete)
# ---------------------------------------------------------------------------

static func _px(m: float, size: int) -> int:
	return int(round((m + MAP_SIZE * 0.5) / MAP_SIZE * float(size)))


static func _rect(img: Image, size: int, x0: float, z0: float, x1: float, z1: float, color: Color) -> void:
	var p0 := Vector2i(_px(minf(x0, x1), size), _px(minf(z0, z1), size))
	var p1 := Vector2i(_px(maxf(x0, x1), size), _px(maxf(z0, z1), size))
	var r := Rect2i(p0, Vector2i(maxi(p1.x - p0.x, 2), maxi(p1.y - p0.y, 2)))
	img.fill_rect(r.intersection(Rect2i(0, 0, size, size)), color)


static func _outline(img: Image, size: int, x0: float, z0: float, x1: float, z1: float, w: float, color: Color) -> void:
	_rect(img, size, x0, z0, x1, z0 + w, color)
	_rect(img, size, x0, z1 - w, x1, z1, color)
	_rect(img, size, x0, z0, x0 + w, z1, color)
	_rect(img, size, x1 - w, z0, x1, z1, color)


static func _hazard(img: Image, size: int, x0: float, z0: float, x1: float, z1: float, color: Color) -> void:
	var p0 := Vector2i(_px(x0, size), _px(z0, size))
	var p1 := Vector2i(_px(x1, size), _px(z1, size))
	for y in range(p0.y, p1.y):
		for x in range(p0.x, p1.x):
			if posmod(x + y, 26) < 10:
				img.set_pixel(x, y, color)
	_outline(img, size, x0, z0, x1, z1, 0.15, color)


## bays: Array of Rect2 (x, z, width, depth) in metres, outlined as container bays.
static func make_ground_markings(bays: Array) -> StandardMaterial3D:
	var size := 2048
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.9, 0.85, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var white := Color(0.92, 0.92, 0.88, 0.9)
	var yellow := Color(0.95, 0.72, 0.1, 0.9)
	var rail := Color(0.3, 0.3, 0.32, 0.85)

	# Perimeter safety line.
	_outline(img, size, -37.5, -37.5, 37.5, 37.5, 0.18, yellow)

	# North-south road (x -4..4) with dashed centre line.
	_rect(img, size, -4.1, -36.0, -3.9, 3.9, white)
	_rect(img, size, 3.9, -36.0, 4.1, 3.9, white)
	_rect(img, size, -4.1, 10.1, -3.9, 36.0, white)
	_rect(img, size, 3.9, 10.1, 4.1, 36.0, white)
	var z := -35.0
	while z < 35.0:
		if z + 2.5 < 3.5 or z > 10.5:
			_rect(img, size, -0.08, z, 0.08, z + 2.5, yellow)
		z += 5.0

	# East-west road (z 4..10).
	for side in [[-36.0, -4.1], [4.1, 36.0]]:
		_rect(img, size, side[0], 3.9, side[1], 4.1, white)
		_rect(img, size, side[0], 9.9, side[1], 10.1, white)
		var x: float = side[0] + 1.0
		while x + 2.5 < side[1]:
			_rect(img, size, x, 6.92, x + 2.5, 7.08, yellow)
			x += 5.0

	# Crosswalk on the north-south road.
	var cx := -3.5
	while cx < 3.5:
		_rect(img, size, cx, 14.0, cx + 0.5, 16.5, white)
		cx += 1.0

	# Hazard stripes in front of the warehouse doors.
	_hazard(img, size, -26.0, -15.6, -18.0, -12.6, yellow)

	# Crane rails (two parallel lines under each gantry).
	_rect(img, size, 3.0, -14.2, 37.0, -13.9, rail)
	_rect(img, size, 3.0, -10.1, 37.0, -9.8, rail)
	_rect(img, size, -22.1, 2.0, -21.8, 30.0, rail)
	_rect(img, size, -18.2, 2.0, -17.9, 30.0, rail)

	# Container bays.
	for bay in bays:
		var r: Rect2 = bay
		_outline(img, size, r.position.x, r.position.y, r.position.x + r.size.x, r.position.y + r.size.y, 0.14, white)

	# Wear: chip paint away.
	var clear := Color(0.9, 0.9, 0.85, 0.0)
	for i in 9000:
		img.fill_rect(Rect2i(rng.randi_range(0, size - 4), rng.randi_range(0, size - 4), rng.randi_range(1, 3), rng.randi_range(1, 3)), clear)

	# Oil stains.
	for i in 14:
		var c := Vector2i(rng.randi_range(120, size - 120), rng.randi_range(120, size - 120))
		var radius := rng.randi_range(10, 30)
		var strength := rng.randf_range(0.25, 0.6)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var d := Vector2(dx, dy).length() / float(radius)
				if d >= 1.0:
					continue
				var a := (1.0 - d * d) * strength * rng.randf_range(0.7, 1.0)
				var under := img.get_pixel(c.x + dx, c.y + dy)
				img.set_pixel(c.x + dx, c.y + dy, under.blend(Color(0.05, 0.045, 0.04, a)))

	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.7
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat
