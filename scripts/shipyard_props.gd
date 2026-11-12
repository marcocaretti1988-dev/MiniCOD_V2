extends RefCounted
## Decorative detail pass for the shipyard: tires, pallets, traffic cones,
## chain-link fence, cables, ladders, roof units, signs, graffiti, dirt, grass,
## birds, dust motes, container lamps and occluders.
##
## Everything here is decoration only: no colliders are added, so the map
## layout, navigation and cover stay exactly as they were. Each prop is a
## single merged mesh (one draw call) with a distance cut-off, and small props
## do not cast shadows.
## Used through: const ShipyardProps := preload("res://scripts/shipyard_props.gd")

const MeshKit := preload("res://scripts/mesh_kit.gd")
const ShipTex := preload("res://scripts/shipyard_textures.gd")
const FOLLOW_CAMERA := preload("res://scripts/follow_camera.gd")

const FONT := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
}

static var _mats: Dictionary = {}


static func build(map: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Decor"
	map.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	_build_tires(root)
	_build_pallets(root)
	_build_cones(root)
	_build_fence(root)
	_build_cables(root)
	_build_ladders(root)
	_build_roof_units(root)
	_build_signs(root)
	_build_graffiti_and_dirt(root, rng)
	_build_grass(root, rng)
	_build_container_lamps(root, map)
	_build_particles(root)
	_build_occluders(map)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

static func _plain(key: String, color: Color, roughness: float, metallic: float = 0.0, normal_seed: int = -1) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# A light noise texture keeps even small props from being a flat colour.
	mat.albedo_texture = ShipTex.noise_texture(900, 0.05, 3, [0.0, 1.0], [Color(0.72, 0.72, 0.72), Color(1, 1, 1)], FastNoiseLite.TYPE_SIMPLEX_SMOOTH, false, 6.0, 256)
	mat.roughness = roughness
	mat.metallic = metallic
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
	if normal_seed >= 0:
		mat.normal_enabled = true
		mat.normal_texture = ShipTex.noise_texture(normal_seed, 0.08, 3, [0.0, 1.0], [Color(0, 0, 0), Color(1, 1, 1)], FastNoiseLite.TYPE_SIMPLEX_SMOOTH, true, 5.0, 256)
	_mats[key] = mat
	return mat


static func _emissive(key: String, color: Color, energy: float) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = ShipTex.make_emissive_material(color, energy)
	return _mats[key]


## Unlit-free alpha material for flat stickers (signs, graffiti, dirt).
static func _sticker(texture: Texture2D, scissor: bool = false, roughness: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if scissor else BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.alpha_scissor_threshold = 0.5
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat


static func _finish(instance: GeometryInstance3D, visible_range: float = 70.0, shadows: bool = false) -> void:
	instance.visibility_range_end = visible_range
	instance.visibility_range_end_margin = 6.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _quad(parent: Node, size: Vector2, pos: Vector3, rot_deg: Vector3, material: Material, visible_range: float = 80.0) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees = rot_deg
	parent.add_child(instance)
	_finish(instance, visible_range)
	return instance


# ---------------------------------------------------------------------------
# Tires, pallets, cones
# ---------------------------------------------------------------------------

static func _build_tires(root: Node3D) -> void:
	var rubber := _plain("rubber", Color(0.045, 0.045, 0.05), 0.92, 0.0, 910)
	var rim := _plain("rim", Color(0.4, 0.41, 0.43), 0.35, 0.9)
	# x, z, tires in the stack, leaning extra tire (0/1)
	var stacks := [
		[37.6, 9.5, 4, 1], [-37.8, -12.0, 3, 1], [10.4, -24.9, 3, 0], [-37.6, 30.5, 4, 0],
		[19.5, 37.8, 3, 1], [-15.0, 38.2, 2, 1], [36.0, -37.6, 4, 0], [-9.2, -15.2, 3, 0],
	]
	var tire_parts: Array = []
	var rim_parts: Array = []
	for s in stacks:
		for i in s[2]:
			var p := Vector3(s[0] + sin(i * 2.1) * 0.04, 0.13 + i * 0.25, s[1] + cos(i * 1.3) * 0.04)
			tire_parts.append(MeshKit.torus(0.2, 0.42, p))
			rim_parts.append(MeshKit.cylinder(0.2, 0.16, p, Vector3.ZERO, 12))
		if s[3] == 1:
			var lean := Vector3(s[0] + 0.62, 0.4, s[1] + 0.15)
			tire_parts.append(MeshKit.torus(0.2, 0.42, lean, Vector3(0, 20, 74)))
			rim_parts.append(MeshKit.cylinder(0.2, 0.16, lean, Vector3(0, 20, 74), 12))
	_finish(MeshKit.add(root, tire_parts, rubber), 75.0, true)
	_finish(MeshKit.add(root, rim_parts, rim), 60.0)


static func _pallet_parts(base: Vector3, rot_y: float, tilt: Vector3 = Vector3.ZERO) -> Array:
	var parts: Array = []
	var t := MeshKit.xform(base, Vector3(tilt.x, rot_y, tilt.z))
	for i in 5:   # top deck
		parts.append([_box_mesh(Vector3(1.2, 0.022, 0.14)), t * Transform3D(Basis(), Vector3(0, 0.133, -0.4 + i * 0.2))])
	for i in 3:   # runners
		parts.append([_box_mesh(Vector3(0.1, 0.09, 1.0)), t * Transform3D(Basis(), Vector3(-0.55 + i * 0.55, 0.077, 0))])
	for i in 3:   # bottom boards
		parts.append([_box_mesh(Vector3(1.2, 0.022, 0.1)), t * Transform3D(Basis(), Vector3(0, 0.011, -0.45 + i * 0.45))])
	return parts


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _build_pallets(root: Node3D) -> void:
	var wood := ShipTex.make_wood_material(Vector3(1.2, 1.2, 1.2))
	wood = wood.duplicate() as StandardMaterial3D
	wood.uv1_world_triplanar = true
	wood.uv1_scale = Vector3(1.4, 1.4, 1.4)
	var parts: Array = []
	# x, z, rotation, pallets stacked
	var stacks := [
		[-15.3, -14.2, 8.0, 4], [-26.5, -27.5, 0.0, 5], [-31.4, -26.0, 90.0, 3], [-8.9, -5.2, 30.0, 2],
		[21.0, 26.6, 5.0, 3], [36.8, 14.0, 80.0, 4], [-36.6, -24.0, 12.0, 2], [14.0, 36.9, 0.0, 3],
	]
	for s in stacks:
		for i in s[3]:
			parts.append_array(_pallet_parts(Vector3(s[0], i * 0.148, s[1]), s[2] + sin(i * 3.0) * 4.0))
	# A few leaning against walls.
	parts.append_array(_pallet_parts(Vector3(39.35, 0.52, -20.0), 90.0, Vector3(0, 0, 72)))
	parts.append_array(_pallet_parts(Vector3(-39.35, 0.52, 14.0), 90.0, Vector3(0, 0, -72)))
	parts.append_array(_pallet_parts(Vector3(-10.4, 0.52, -22.0), 90.0, Vector3(0, 0, -74)))
	_finish(MeshKit.add(root, parts, wood), 75.0, true)


static func _build_cones(root: Node3D) -> void:
	# Emissive orange so they glow a little at dusk.
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.36, 0.05)
	orange.emission_enabled = true
	orange.emission = Color(1.0, 0.3, 0.02)
	orange.emission_energy_multiplier = 0.55
	orange.roughness = 0.6
	var white := _emissive("cone_band", Color(0.95, 0.95, 0.9), 0.5)
	var black := _plain("cone_base", Color(0.06, 0.06, 0.06), 0.9)
	var spots := [
		Vector2(-26.4, -12.3), Vector2(-17.6, -12.3), Vector2(-22.0, -12.2), Vector2(4.5, 3.5), Vector2(-4.5, 3.5),
		Vector2(4.5, 10.5), Vector2(-4.5, 10.5), Vector2(5.0, -9.4), Vector2(35.0, -14.9), Vector2(1.2, 27.6),
		Vector2(3.9, 24.6), Vector2(13.6, -13.2), Vector2(-18.9, 5.0), Vector2(26.0, 12.6),
	]
	var body: Array = []
	var bands: Array = []
	var bases: Array = []
	for s in spots:
		var p := Vector3(s.x, 0.0, s.y)
		body.append(MeshKit.cylinder(0.15, 0.5, p + Vector3(0, 0.28, 0), Vector3.ZERO, 12, 0.03))
		bands.append(MeshKit.cylinder(0.112, 0.08, p + Vector3(0, 0.33, 0), Vector3.ZERO, 12, 0.093))
		bases.append(MeshKit.box(Vector3(0.36, 0.03, 0.36), p + Vector3(0, 0.015, 0), Vector3(0, s.x * 17.0, 0)))
	_finish(MeshKit.add(root, body, orange), 70.0, true)
	_finish(MeshKit.add(root, bands, white), 45.0)
	_finish(MeshKit.add(root, bases, black), 45.0)


# ---------------------------------------------------------------------------
# Chain-link fence on top of the perimeter walls
# ---------------------------------------------------------------------------

static func _chainlink_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.57, 0.6, 0.0))
	for y in size:
		for x in size:
			# Two sets of diagonal wires.
			var a := posmod(x + y, 16)
			var b := posmod(x - y, 16)
			if a < 2 or b < 2:
				var shade := 0.55 + 0.25 * float((x + y) % 5) / 5.0
				img.set_pixel(x, y, Color(shade, shade + 0.02, shade + 0.05, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _build_fence(root: Node3D) -> void:
	var wall_h := 4.12
	var fence_h := 1.5
	var mesh_mat := _sticker(_chainlink_texture(), true, 0.5)
	mesh_mat.metallic = 0.7
	mesh_mat.uv1_scale = Vector3(160.0, 3.0, 1.0)
	var steel := _plain("fence_steel", Color(0.4, 0.42, 0.45), 0.4, 0.85)
	var posts: Array = []
	for side in [-1.0, 1.0]:
		_quad(root, Vector2(80.0, fence_h), Vector3(0, wall_h + fence_h * 0.5, side * 40.0), Vector3.ZERO, mesh_mat, 200.0)
		_quad(root, Vector2(80.0, fence_h), Vector3(side * 40.0, wall_h + fence_h * 0.5, 0), Vector3(0, 90, 0), mesh_mat, 200.0)
		var p := -40.0
		while p <= 40.0:
			posts.append(MeshKit.cylinder(0.04, fence_h + 0.25, Vector3(p, wall_h + fence_h * 0.5 + 0.1, side * 40.0), Vector3.ZERO, 6))
			posts.append(MeshKit.cylinder(0.04, fence_h + 0.25, Vector3(side * 40.0, wall_h + fence_h * 0.5 + 0.1, p), Vector3.ZERO, 6))
			p += 4.0
		# Top rail and two barbed-wire strands.
		for h in [fence_h, fence_h + 0.12, fence_h + 0.22]:
			posts.append(MeshKit.cylinder(0.015, 80.0, Vector3(0, wall_h + h, side * 40.0), Vector3(0, 0, 90), 4))
			posts.append(MeshKit.cylinder(0.015, 80.0, Vector3(side * 40.0, wall_h + h, 0), Vector3(90, 0, 0), 4))
	_finish(MeshKit.add(root, posts, steel), 200.0)


# ---------------------------------------------------------------------------
# Cables, ladders, roof units
# ---------------------------------------------------------------------------

## Thick hose / cable lying on the ground along a polyline of XZ points.
static func _hose_parts(points: Array, radius: float) -> Array:
	var parts: Array = []
	for i in points.size() - 1:
		var a := Vector3(points[i].x, radius, points[i].y)
		var b := Vector3(points[i + 1].x, radius, points[i + 1].y)
		var mid := (a + b) * 0.5
		var dir := b - a
		var yaw := rad_to_deg(atan2(dir.x, dir.z))
		parts.append(MeshKit.cylinder(radius, dir.length() + radius, mid, Vector3(90, yaw, 0), 6))
	return parts


static func _curve(from: Vector2, to: Vector2, bend: float, steps: int = 10) -> Array:
	var points: Array = []
	var normal := (to - from).orthogonal().normalized()
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(from.lerp(to, t) + normal * sin(t * PI) * bend + normal * sin(t * PI * 3.0) * bend * 0.25)
	return points


static func _build_cables(root: Node3D) -> void:
	var black := _plain("cable", Color(0.04, 0.04, 0.045), 0.7)
	var yellow := _plain("hose", Color(0.75, 0.6, 0.08), 0.65)
	var red := _plain("hose_red", Color(0.5, 0.08, 0.06), 0.65)
	var cables: Array = []
	cables.append_array(_hose_parts(_curve(Vector2(-10.6, -24.0), Vector2(-2.6, -8.4), 1.4), 0.03))
	cables.append_array(_hose_parts(_curve(Vector2(5.4, -12.2), Vector2(12.0, -3.4), -1.1), 0.03))
	cables.append_array(_hose_parts(_curve(Vector2(-20.4, 4.4), Vector2(-10.4, 2.0), 0.9), 0.025))
	cables.append_array(_hose_parts(_curve(Vector2(34.6, -12.4), Vector2(27.6, -18.6), 0.8), 0.03))
	_finish(MeshKit.add(root, cables, black), 55.0)
	_finish(MeshKit.add(root, _hose_parts(_curve(Vector2(-12.0, -18.9), Vector2(-5.6, -10.0), -1.6, 14), 0.045), yellow), 55.0)
	_finish(MeshKit.add(root, _hose_parts(_curve(Vector2(14.6, 22.4), Vector2(23.0, 25.6), 1.2, 12), 0.04), red), 55.0)


static func _ladder_parts(base: Vector3, height: float, rot_y: float) -> Array:
	var parts: Array = []
	var t := MeshKit.xform(base, Vector3(0, rot_y, 0))
	for side in [-0.22, 0.22]:
		parts.append([_box_mesh(Vector3(0.04, height, 0.04)), t * Transform3D(Basis(), Vector3(side, height * 0.5, 0))])
	var rung := 0.3
	while rung < height:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.014
		mesh.bottom_radius = 0.014
		mesh.height = 0.44
		mesh.radial_segments = 6
		parts.append([mesh, t * MeshKit.xform(Vector3(0, rung, 0), Vector3(0, 0, 90))])
		rung += 0.3
	# Wall brackets.
	for h in [0.4, height - 0.4]:
		for side in [-0.22, 0.22]:
			parts.append([_box_mesh(Vector3(0.03, 0.03, 0.14)), t * Transform3D(Basis(), Vector3(side, h, -0.07))])
	return parts


static func _build_ladders(root: Node3D) -> void:
	var steel := _plain("ladder", Color(0.55, 0.5, 0.2), 0.45, 0.8)
	var parts: Array = []
	parts.append_array(_ladder_parts(Vector3(-13.4, 0, -15.66), 6.2, 0.0))     # warehouse south wall
	parts.append_array(_ladder_parts(Vector3(-10.66, 0, -29.6), 6.2, 90.0))    # warehouse east wall
	parts.append_array(_ladder_parts(Vector3(30.0, 0, 15.86), 5.3, 180.0))     # stacked containers
	parts.append_array(_ladder_parts(Vector3(2.86, 0, -24.0), 5.3, -90.0))     # container stack north
	_finish(MeshKit.add(root, parts, steel), 80.0, true)


static func _build_roof_units(root: Node3D) -> void:
	var casing := _plain("ac_casing", Color(0.62, 0.64, 0.66), 0.45, 0.7, 920)
	var dark := _plain("ac_dark", Color(0.08, 0.08, 0.09), 0.5, 0.6)
	var roof_y := 6.26
	var bodies: Array = []
	var darks: Array = []
	# AC units: casing, fan well, grille bars, pipe.
	for unit in [Vector3(-27.0, roof_y, -27.0), Vector3(-18.0, roof_y, -21.0), Vector3(-16.0, roof_y, -29.0)]:
		bodies.append(MeshKit.box(Vector3(1.8, 0.9, 1.2), unit + Vector3(0, 0.5, 0)))
		bodies.append(MeshKit.box(Vector3(1.9, 0.06, 1.3), unit + Vector3(0, 0.98, 0)))
		for leg in [Vector3(-0.8, 0.02, -0.5), Vector3(0.8, 0.02, -0.5), Vector3(-0.8, 0.02, 0.5), Vector3(0.8, 0.02, 0.5)]:
			darks.append(MeshKit.box(Vector3(0.12, 0.1, 0.12), unit + leg))
		darks.append(MeshKit.cylinder(0.38, 0.05, unit + Vector3(-0.35, 1.03, 0), Vector3.ZERO, 16))
		darks.append(MeshKit.cylinder(0.38, 0.05, unit + Vector3(0.5, 1.03, 0), Vector3.ZERO, 16))
		for i in 6:
			darks.append(MeshKit.box(Vector3(1.7, 0.05, 0.03), unit + Vector3(0, 0.25 + i * 0.1, 0.61)))
		bodies.append(MeshKit.cylinder(0.05, 2.4, unit + Vector3(1.4, 0.1, 0.3), Vector3(0, 0, 90), 8))
	# Mushroom vents.
	for vent in [Vector3(-22.0, roof_y, -28.5), Vector3(-29.5, roof_y, -20.0), Vector3(-14.0, roof_y, -18.5), Vector3(-24.0, roof_y, -18.0)]:
		bodies.append(MeshKit.cylinder(0.18, 0.7, vent + Vector3(0, 0.35, 0), Vector3.ZERO, 12))
		bodies.append(MeshKit.cylinder(0.36, 0.14, vent + Vector3(0, 0.76, 0), Vector3.ZERO, 12, 0.12))
	# Wall-mounted units and a vent grille on the south wall.
	for wall_unit in [Vector3(-30.0, 4.4, -15.5), Vector3(-14.5, 3.2, -15.5)]:
		bodies.append(MeshKit.box(Vector3(1.1, 0.7, 0.45), wall_unit))
		darks.append(MeshKit.cylinder(0.26, 0.04, wall_unit + Vector3(0, 0, 0.23), Vector3(90, 0, 0), 14))
		darks.append(MeshKit.box(Vector3(0.9, 0.06, 0.3), wall_unit + Vector3(0, -0.4, -0.05)))
	_finish(MeshKit.add(root, bodies, casing), 120.0, true)
	_finish(MeshKit.add(root, darks, dark), 80.0)


# ---------------------------------------------------------------------------
# Signs with worn text
# ---------------------------------------------------------------------------

static func _sign_texture(text: String, bg: Color, fg: Color, seed_value: int) -> ImageTexture:
	var scale := 6
	var margin := 14
	var w := text.length() * 6 * scale + margin * 2
	var h := 7 * scale + margin * 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	# Border.
	for r in [Rect2i(3, 3, w - 6, 3), Rect2i(3, h - 6, w - 6, 3), Rect2i(3, 3, 3, h - 6), Rect2i(w - 6, 3, 3, h - 6)]:
		img.fill_rect(r, fg)
	for i in text.length():
		var glyph: Array = FONT.get(text[i], [])
		for row in glyph.size():
			var line: String = glyph[row]
			for col in 5:
				if line[col] == "1":
					img.fill_rect(Rect2i(margin + (i * 6 + col) * scale, margin + row * scale, scale, scale), fg)
	# Wear: chipped paint and rust streaks running down.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rust := Color(0.36, 0.2, 0.1)
	for i in 160:
		img.fill_rect(Rect2i(rng.randi_range(0, w - 4), rng.randi_range(0, h - 4), rng.randi_range(1, 4), rng.randi_range(1, 3)),
			bg.lerp(rust, rng.randf_range(0.3, 0.9)))
	for i in 9:
		var x := rng.randi_range(4, w - 6)
		var top := rng.randi_range(0, h / 2)
		img.fill_rect(Rect2i(x, top, rng.randi_range(1, 2), rng.randi_range(8, h - top)), rust.lerp(bg, 0.35))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _add_sign(root: Node3D, text: String, bg: Color, fg: Color, pos: Vector3, rot_y: float, height: float, seed_value: int) -> void:
	var tex := _sign_texture(text, bg, fg, seed_value)
	var mat := _sticker(tex, false, 0.55)
	mat.metallic = 0.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var aspect := float(tex.get_width()) / float(tex.get_height())
	_quad(root, Vector2(height * aspect, height), pos, Vector3(0, rot_y, 0), mat, 90.0)


static func _build_signs(root: Node3D) -> void:
	var yellow := Color(0.9, 0.72, 0.1)
	var black := Color(0.06, 0.06, 0.06)
	var white := Color(0.88, 0.88, 0.84)
	var red := Color(0.65, 0.1, 0.08)
	var blue := Color(0.1, 0.25, 0.5)
	_add_sign(root, "WAREHOUSE 7", blue, white, Vector3(-22.0, 5.3, -15.74), 0.0, 0.8, 1)
	_add_sign(root, "DANGER", yellow, black, Vector3(-26.6, 2.4, -15.74), 0.0, 0.5, 2)
	_add_sign(root, "EXIT", Color(0.1, 0.4, 0.2), white, Vector3(-10.74, 3.5, -24.0), 90.0, 0.4, 3)
	_add_sign(root, "KEEP OUT", red, white, Vector3(39.72, 2.6, 0.0), -90.0, 0.6, 4)
	_add_sign(root, "KEEP OUT", red, white, Vector3(-39.72, 2.6, -18.0), 90.0, 0.6, 5)
	_add_sign(root, "ZONE A", yellow, black, Vector3(8.0, 2.8, -39.72), 0.0, 0.7, 6)
	_add_sign(root, "ZONE B", yellow, black, Vector3(16.0, 2.8, 39.72), 180.0, 0.7, 7)
	_add_sign(root, "BAY 1", white, black, Vector3(6.0, 1.9, -19.77), 0.0, 0.42, 8)
	_add_sign(root, "BAY 2", white, black, Vector3(18.0, 1.9, 2.03), 0.0, 0.42, 9)
	_add_sign(root, "BAY 3", white, black, Vector3(31.23, 1.9, 19.0), 90.0, 0.42, 10)
	_add_sign(root, "NO ENTRY", red, white, Vector3(0.0, 2.8, 39.72), 180.0, 0.6, 11)


# ---------------------------------------------------------------------------
# Graffiti, wall dirt, ground dirt
# ---------------------------------------------------------------------------

static func _graffiti_texture(seed_value: int) -> ImageTexture:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var palette := [Color(0.85, 0.15, 0.2), Color(0.1, 0.55, 0.85), Color(0.95, 0.75, 0.1), Color(0.3, 0.75, 0.3), Color(0.9, 0.9, 0.9), Color(0.6, 0.2, 0.7)]
	# Fat rounded strokes with a dark outline, like a spray-painted tag.
	for pass_index in 2:
		var stroke_rng := RandomNumberGenerator.new()
		stroke_rng.seed = seed_value * 7 + 1
		for stroke in 6:
			var color: Color = palette[stroke_rng.randi() % palette.size()]
			var p0 := Vector2(stroke_rng.randf_range(24, w - 24), stroke_rng.randf_range(26, h - 26))
			var p1 := p0 + Vector2(stroke_rng.randf_range(-70, 70), stroke_rng.randf_range(-45, 45))
			var p2 := p1 + Vector2(stroke_rng.randf_range(-70, 70), stroke_rng.randf_range(-45, 45))
			var radius := stroke_rng.randf_range(5.0, 9.0) + (3.0 if pass_index == 0 else 0.0)
			var paint := Color(0.05, 0.05, 0.07, 0.9) if pass_index == 0 else Color(color.r, color.g, color.b, 0.92)
			for i in 28:
				var t := float(i) / 27.0
				var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
				_disc(img, p, radius, paint)
	# Drips.
	for i in 7:
		var x := rng.randi_range(20, w - 20)
		var y := rng.randi_range(40, h - 30)
		if img.get_pixel(x, y).a > 0.5:
			img.fill_rect(Rect2i(x, y, 2, rng.randi_range(10, 28)), img.get_pixel(x, y))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _disc(img: Image, centre: Vector2, radius: float, color: Color) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x := int(centre.x) + dx
			var y := int(centre.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, color)


## Dark dirt climbing up from the bottom of a wall (alpha fades upwards).
static func _wall_dirt_texture() -> ImageTexture:
	var w := 256
	var h := 64
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.03
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var up := float(h - 1 - y) / float(h)   # 0 at the ground
		for x in w:
			var n := noise.get_noise_2d(x, y * 0.4) * 0.5 + 0.5
			# Wrap the noise horizontally so the strip tiles.
			var n2 := noise.get_noise_2d(x - w, y * 0.4) * 0.5 + 0.5
			n = lerpf(n, n2, float(x) / float(w))
			var a := clampf((1.0 - up * (1.3 + n * 1.6)), 0.0, 1.0) * 0.6
			img.set_pixel(x, y, Color(0.14, 0.11, 0.08, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _ground_dirt_material(seed_value: int) -> StandardMaterial3D:
	var size := 128
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(float(x) / size - 0.5, float(y) / size - 0.5).length() * 2.0
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((0.95 - d - (1.0 - n) * 0.6) * 2.2, 0.0, 1.0) * 0.55
			img.set_pixel(x, y, Color(0.3, 0.24, 0.17, a))
	img.generate_mipmaps()
	var mat := _sticker(ImageTexture.create_from_image(img), false, 0.95)
	mat.render_priority = 1
	return mat


static func _build_graffiti_and_dirt(root: Node3D, rng: RandomNumberGenerator) -> void:
	# Graffiti on the inside of the perimeter walls and on the warehouse.
	var tags := [
		[Vector3(-8.0, 1.6, 39.72), 180.0, 4.2], [Vector3(39.72, 1.5, 24.0), -90.0, 3.6], [Vector3(-39.72, 1.7, 0.0), 90.0, 3.6],
		[Vector3(24.0, 1.5, -39.72), 0.0, 3.8], [Vector3(-33.23, 1.6, -22.0), -90.0, 3.4], [Vector3(-39.72, 1.4, 34.0), 90.0, 3.0],
	]
	for i in tags.size():
		var mat := _sticker(_graffiti_texture(60 + i), false, 0.85)
		_quad(root, Vector2(tags[i][2], tags[i][2] * 0.5), tags[i][0], Vector3(0, tags[i][1], 0), mat, 90.0)

	# Dirt at the bottom of every perimeter wall and of the warehouse walls.
	var dirt := _sticker(_wall_dirt_texture(), false, 1.0)
	dirt.uv1_scale = Vector3(9.0, 1.0, 1.0)
	for side in [-1.0, 1.0]:
		_quad(root, Vector2(80.0, 1.5), Vector3(0, 0.75, side * 39.71), Vector3(0, 0 if side < 0 else 180, 0), dirt, 120.0)
		_quad(root, Vector2(80.0, 1.5), Vector3(side * 39.71, 0.75, 0), Vector3(0, 90 if side < 0 else -90, 0), dirt, 120.0)
	var short_dirt := dirt.duplicate() as StandardMaterial3D
	short_dirt.uv1_scale = Vector3(2.5, 1.0, 1.0)
	_quad(root, Vector2(22.0, 1.3), Vector3(-22.0, 0.65, -32.23), Vector3(0, 180, 0), short_dirt, 100.0)
	_quad(root, Vector2(16.0, 1.3), Vector3(-33.23, 0.65, -24.0), Vector3(0, -90, 0), short_dirt, 100.0)
	_quad(root, Vector2(7.2, 1.3), Vector3(-29.4, 0.65, -15.77), Vector3.ZERO, short_dirt, 100.0)
	_quad(root, Vector2(7.2, 1.3), Vector3(-14.6, 0.65, -15.77), Vector3.ZERO, short_dirt, 100.0)

	# Dust / dirt patches on the ground, mostly in corners and against walls.
	var patches := [_ground_dirt_material(71), _ground_dirt_material(72), _ground_dirt_material(73)]
	for i in 26:
		var along := rng.randf_range(-37.0, 37.0)
		var inset := rng.randf_range(35.0, 38.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		var pos := Vector3(along, 0.018, inset) if i % 2 == 0 else Vector3(inset, 0.018, along)
		if i >= 18:
			pos = Vector3(rng.randf_range(-30.0, 32.0), 0.018, rng.randf_range(-30.0, 30.0))
		var size := rng.randf_range(2.5, 5.5)
		_quad(root, Vector2(size, size * rng.randf_range(0.6, 1.0)), pos, Vector3(-90, rng.randf_range(0, 360), 0), patches[i % 3], 60.0)


# ---------------------------------------------------------------------------
# Grass tufts near the walls (one MultiMesh)
# ---------------------------------------------------------------------------

static func _grass_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.4, 0.45, 0.2, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for blade in 22:
		var x := rng.randf_range(8.0, 56.0)
		var lean := rng.randf_range(-0.35, 0.35)
		var height := rng.randi_range(26, 60)
		var tint := Color(0.36, 0.42, 0.16).lerp(Color(0.62, 0.58, 0.28), rng.randf())
		for i in height:
			var t := float(i) / float(height)
			var px := int(x + lean * i + sin(t * 3.0) * 1.5)
			var width := 2 if t < 0.55 else 1
			img.fill_rect(Rect2i(clampi(px, 0, size - 2), size - 1 - i, width, 1), Color(tint.r * (0.6 + 0.5 * t), tint.g * (0.6 + 0.5 * t), tint.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _build_grass(root: Node3D, rng: RandomNumberGenerator) -> void:
	var mat := _sticker(_grass_texture(), true, 0.9)
	# Two crossed quads per tuft.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.42)
	quad.center_offset = Vector3(0, 0.21, 0)
	var tuft := MeshKit.merge([[quad, Transform3D()], [quad, MeshKit.xform(Vector3.ZERO, Vector3(0, 90, 0))]])

	var spots: Array[Transform3D] = []
	for i in 340:
		var along := rng.randf_range(-39.0, 39.0)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var inset := side * rng.randf_range(38.9, 39.6)
		var pos := Vector3(along, 0.0, inset) if i % 2 == 0 else Vector3(inset, 0.0, along)
		spots.append(_tuft_transform(pos, rng))
	# Around the warehouse and a few slab joints.
	for i in 60:
		var pos := Vector3(rng.randf_range(-33.0, -11.0), 0.0, -32.5 - rng.randf_range(0.0, 0.5))
		if i % 2 == 0:
			pos = Vector3(-33.5 - rng.randf_range(0.0, 0.5), 0.0, rng.randf_range(-32.0, -16.0))
		spots.append(_tuft_transform(pos, rng))
	for i in 40:
		var joint := Vector3(snappedf(rng.randf_range(-36.0, 36.0), 4.0) + rng.randf_range(-0.1, 0.1), 0.0, rng.randf_range(-36.0, 36.0))
		if absf(joint.x) > 5.0 and (joint.z < 3.0 or joint.z > 11.0):
			spots.append(_tuft_transform(joint, rng, 0.6))

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = tuft
	multi.instance_count = spots.size()
	for i in spots.size():
		multi.set_instance_transform(i, spots[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = multi
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


static func _tuft_transform(pos: Vector3, rng: RandomNumberGenerator, size: float = 1.0) -> Transform3D:
	var s := rng.randf_range(0.7, 1.5) * size
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
	return Transform3D(basis, pos)


# ---------------------------------------------------------------------------
# Emissive lamps on containers
# ---------------------------------------------------------------------------

static func _build_container_lamps(root: Node3D, map: Node3D) -> void:
	var geometry := map.get_node_or_null("Geometry")
	if geometry == null:
		return
	var amber := _emissive("lamp_amber", Color(1.0, 0.6, 0.15), 4.0)
	var red := _emissive("lamp_red", Color(1.0, 0.1, 0.06), 4.0)
	var housing := _plain("lamp_housing", Color(0.1, 0.1, 0.11), 0.5, 0.7)
	var lamps_amber: Array = []
	var lamps_red: Array = []
	var housings: Array = []
	var index := 0
	for child in geometry.get_children():
		if not String(child.name).begins_with("Container"):
			continue
		var body := child as Node3D
		var t := body.global_transform
		# Above the doors, on the +X end of every container.
		var lamp := t * Vector3(3.03, 1.05, 0.0)
		var rot := Vector3(0, rad_to_deg(body.rotation.y), 0)
		housings.append(MeshKit.box(Vector3(0.1, 0.12, 0.34), lamp, rot))
		var glow := MeshKit.box(Vector3(0.06, 0.07, 0.26), t * Vector3(3.09, 1.05, 0.0), rot)
		if index % 3 == 0:
			lamps_red.append(glow)
		else:
			lamps_amber.append(glow)
		index += 1
	if not housings.is_empty():
		_finish(MeshKit.add(root, housings, housing), 60.0)
	if not lamps_amber.is_empty():
		_finish(MeshKit.add(root, lamps_amber, amber), 120.0)
	if not lamps_red.is_empty():
		_finish(MeshKit.add(root, lamps_red, red), 120.0)


# ---------------------------------------------------------------------------
# Birds and dust motes (GPUParticles3D)
# ---------------------------------------------------------------------------

static func _bird_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.05, 0.06, 0.0))
	for x in size:
		# A shallow "M": two wings meeting at the body.
		var wing := absf(float(x) - 15.5) / 15.5
		var y := int(12.0 + sin(wing * PI) * -5.0 + wing * 6.0)
		img.fill_rect(Rect2i(x, y, 1, 2 if wing < 0.8 else 1), Color(0.05, 0.05, 0.06, 1.0))
	img.fill_rect(Rect2i(14, 11, 4, 4), Color(0.05, 0.05, 0.06, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _particle_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


static func _build_particles(root: Node3D) -> void:
	# Birds drifting across the sky, far above the yard.
	var birds := GPUParticles3D.new()
	birds.name = "Birds"
	birds.amount = 16
	birds.lifetime = 26.0
	birds.preprocess = 26.0
	birds.position = Vector3(-55.0, 38.0, 0.0)
	birds.visibility_aabb = AABB(Vector3(-20, -20, -90), Vector3(240, 40, 180))
	birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := ParticleProcessMaterial.new()
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bm.emission_box_extents = Vector3(4.0, 7.0, 55.0)
	bm.direction = Vector3(1.0, 0.0, 0.15)
	bm.spread = 6.0
	bm.initial_velocity_min = 4.0
	bm.initial_velocity_max = 6.5
	bm.gravity = Vector3.ZERO
	bm.scale_min = 0.7
	bm.scale_max = 1.3
	birds.process_material = bm
	var bird_quad := QuadMesh.new()
	bird_quad.size = Vector2(1.3, 1.3)
	bird_quad.material = _particle_material(_bird_texture(), false)
	birds.draw_pass_1 = bird_quad
	root.add_child(birds)

	# Dust motes floating in the air around the camera, catching the low sun.
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 1.0])
	glow.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow
	glow_tex.width = 32
	glow_tex.height = 32
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(0.5, 0.0)

	var motes := GPUParticles3D.new()
	motes.name = "DustMotes"
	motes.amount = 160
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.local_coords = false
	motes.visibility_aabb = AABB(Vector3(-14, -6, -14), Vector3(28, 12, 28))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mm.emission_box_extents = Vector3(9.0, 2.6, 9.0)
	mm.direction = Vector3(1.0, 0.2, 0.3)
	mm.spread = 180.0
	mm.initial_velocity_min = 0.03
	mm.initial_velocity_max = 0.22
	mm.gravity = Vector3(0.05, -0.02, 0.02)
	mm.scale_min = 0.5
	mm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.6, 0.0), Color(1.0, 0.85, 0.6, 0.55), Color(1.0, 0.85, 0.6, 0.55), Color(1.0, 0.85, 0.6, 0.0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mm.color_ramp = ramp_tex
	motes.process_material = mm
	var mote_quad := QuadMesh.new()
	mote_quad.size = Vector2(0.022, 0.022)
	mote_quad.material = _particle_material(glow_tex, true)
	motes.draw_pass_1 = mote_quad
	motes.set_script(FOLLOW_CAMERA)
	root.add_child(motes)


# ---------------------------------------------------------------------------
# Occlusion culling
# ---------------------------------------------------------------------------

## Big solid boxes (containers, warehouse walls, perimeter) hide what is behind
## them, so the renderer can skip it.
static func _build_occluders(map: Node3D) -> void:
	var geometry := map.get_node_or_null("Geometry")
	if geometry == null:
		return
	for child in geometry.get_children():
		var body := child as StaticBody3D
		if body == null or String(body.name) == "Ground":
			continue
		for sub in body.get_children():
			var shape_node := sub as CollisionShape3D
			if shape_node == null or not shape_node.shape is BoxShape3D:
				continue
			var size: Vector3 = (shape_node.shape as BoxShape3D).size
			if size.y < 2.4 or minf(size.x, size.z) < 0.3 or maxf(size.x, size.z) < 2.3:
				continue
			var occluder := BoxOccluder3D.new()
			occluder.size = size * 0.94
			var instance := OccluderInstance3D.new()
			instance.occluder = occluder
			instance.transform = shape_node.transform
			body.add_child(instance)
