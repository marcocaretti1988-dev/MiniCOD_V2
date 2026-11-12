extends Node3D
## Shipyard level (80 x 80 m). Lighting, environment, spawn markers, the player
## and the NavigationRegion3D live in shipyard.tscn; all the geometry is built
## here by code so every surface gets a procedural StandardMaterial3D.

const ProcTex := preload("res://scripts/procedural_textures.gd")
const ShipTex := preload("res://scripts/shipyard_textures.gd")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const ShipyardProps := preload("res://scripts/shipyard_props.gd")

const MAP_SIZE := 80.0
const HALF := 40.0

# Container size in metres (length, height, width).
const C_LEN := 6.0
const C_H := 2.6
const C_W := 2.4

const CONTAINER_COLORS := {
	"red": Color(0.62, 0.13, 0.1),
	"blue": Color(0.12, 0.27, 0.55),
	"orange": Color(0.85, 0.42, 0.08),
	"green": Color(0.15, 0.42, 0.22),
}

# 12 containers: x, z, rotation Y (degrees), colour, level (0 = ground, 1 = stacked on top).
const CONTAINERS := [
	[6.0, -24.0, 0.0, "red", 0],
	[6.0, -21.0, 0.0, "blue", 0],
	[6.4, -24.0, 0.0, "orange", 1],
	[26.0, -22.0, 90.0, "green", 0],
	[29.2, -22.0, 90.0, "red", 0],
	[26.0, -22.4, 90.0, "blue", 1],
	[18.0, -2.4, 0.0, "orange", 0],
	[18.0, 0.8, 0.0, "green", 0],
	[17.6, -2.4, 6.0, "red", 1],
	[30.0, 19.0, 90.0, "blue", 0],
	[30.0, 19.3, 84.0, "orange", 1],
	[9.0, 21.0, 20.0, "red", 0],
]

# Empty painted bays (x, z, width, depth).
const EMPTY_BAYS := [
	Rect2(14.0, 27.0, 6.8, 3.2),
	Rect2(14.0, 31.0, 6.8, 3.2),
	Rect2(22.0, 27.0, 6.8, 3.2),
	Rect2(22.0, 31.0, 6.8, 3.2),
	Rect2(10.0, -31.0, 6.8, 3.2),
]

# Enemy vest colours and patrol routes (one per EnemySpawn marker).
const ENEMY_VESTS := [
	Color(0.27, 0.33, 0.19),
	Color(0.5, 0.4, 0.26),
	Color(0.16, 0.2, 0.3),
	Color(0.42, 0.14, 0.12),
]
const ENEMY_PATROLS := [
	[Vector2(-28, -27), Vector2(-16, -27), Vector2(-16, -20), Vector2(-28, -20)],  # warehouse
	[Vector2(20, -33), Vector2(35, -33), Vector2(35, -17), Vector2(20, -17)],      # north-east yard
	[Vector2(26, -6), Vector2(36, -6), Vector2(36, 6), Vector2(26, 6)],            # east road
	[Vector2(-34, 2), Vector2(-26, 2), Vector2(-26, 24), Vector2(-34, 24)],        # west yard
]

## How tire marks are drawn. Real Decal nodes need the Forward+ or Mobile renderer;
## "auto" falls back to flat decal quads on the Compatibility renderer.
@export_enum("auto", "decal_nodes", "flat_quads") var tire_mark_mode: String = "auto"

var _geometry: Node3D
var _container_mats: Dictionary = {}
var _edge_mats: Dictionary = {}
var _wood_mats: Dictionary = {}
var _concrete_wall: StandardMaterial3D
var _dark_metal: StandardMaterial3D
var _sandbag_mat: StandardMaterial3D

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var player: Node3D = $Player
@onready var spawns: Node3D = $Spawns


func _ready() -> void:
	# Lets the enemies find the player without touching the player scene.
	player.add_to_group("player")
	player.global_transform = spawns.get_node("PlayerSpawn").global_transform

	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	_geometry.add_to_group("navmesh_source")
	add_child(_geometry)

	_concrete_wall = ProcTex.make_concrete_material(0.35, true, Color(0.86, 0.85, 0.82), 21)
	_concrete_wall.roughness = 1.06  # walls a touch rougher than the ground (about 0.9)
	_dark_metal = ShipTex.make_painted_metal(Color(0.13, 0.14, 0.16), 90, false, Vector3(0.5, 0.5, 0.5), true, 0.9, 0.3, 0.6, 0.6)
	_sandbag_mat = ShipTex.make_sandbag_material()

	_build_ground()
	_build_perimeter()
	_build_containers()
	_build_warehouse()
	_build_cranes()
	_build_props()
	_build_puddles()
	_build_tire_marks()

	_bake_navigation()
	# Decoration only (no colliders), added after the navigation bake.
	ShipyardProps.build(self)
	_spawn_enemies()


# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

func _mesh_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_part(parent, mesh, pos, material, rot_deg)


func _mesh_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return _mesh_part(parent, mesh, pos, material, rot_deg)


func _mesh_part(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot_deg: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation_degrees = rot_deg
	parent.add_child(part)
	return part


## Static body with a box collider and a matching box mesh. pos = centre.
func _solid_box(size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO, with_mesh: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_geometry.add_child(body)
	if with_mesh:
		_mesh_box(body, size, Vector3.ZERO, material)
	return body


func _make_cover(body: Node3D, radius: float) -> void:
	body.add_to_group("cover")
	body.set_meta("cover_radius", radius)


# ---------------------------------------------------------------------------
# Ground and perimeter
# ---------------------------------------------------------------------------

func _build_ground() -> void:
	var ground := _solid_box(Vector3(MAP_SIZE, 1.0, MAP_SIZE), Vector3(0, -0.5, 0), null, Vector3.ZERO, false)
	ground.name = "Ground"

	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_SIZE, MAP_SIZE)
	# Concrete slabs: 20 tiles = 4 m slabs, roughness 0.85.
	var surface := _mesh_part(ground, plane, Vector3(0, 0.5, 0), ProcTex.make_concrete_material(20.0), Vector3.ZERO)
	surface.name = "Surface"

	# Painted lines on a transparent layer just above the concrete.
	var bays: Array = EMPTY_BAYS.duplicate()
	for c in CONTAINERS:
		var rot: float = c[2]
		if c[4] != 0 or (not is_equal_approx(rot, 0.0) and not is_equal_approx(rot, 90.0)):
			continue
		var along_x := is_equal_approx(rot, 0.0)
		var w := (C_LEN if along_x else C_W) + 0.8
		var d := (C_W if along_x else C_LEN) + 0.8
		bays.append(Rect2(c[0] - w * 0.5, c[1] - d * 0.5, w, d))
	var markings := _mesh_part(ground, plane, Vector3(0, 0.51, 0), ShipTex.make_ground_markings(bays), Vector3.ZERO)
	markings.name = "Markings"
	markings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_perimeter() -> void:
	var h := 4.0
	var t := 0.5
	var cap := ShipTex.make_painted_metal(Color(0.2, 0.2, 0.22), 91, false, Vector3(0.5, 0.5, 0.5), true, 0.5, 0.5, 0.8)
	for side in [-1.0, 1.0]:
		_solid_box(Vector3(MAP_SIZE + t, h, t), Vector3(0, h * 0.5, side * HALF), _concrete_wall).name = "WallZ"
		_solid_box(Vector3(t, h, MAP_SIZE + t), Vector3(side * HALF, h * 0.5, 0), _concrete_wall).name = "WallX"
		# Metal cap on top of each wall.
		_mesh_box(_geometry, Vector3(MAP_SIZE + t, 0.12, t + 0.12), Vector3(0, h + 0.06, side * HALF), cap)
		_mesh_box(_geometry, Vector3(t + 0.12, 0.12, MAP_SIZE + t), Vector3(side * HALF, h + 0.06, 0), cap)
		# Pillars every 8 m.
		var p := -HALF + 4.0
		while p < HALF:
			_mesh_box(_geometry, Vector3(0.7, h + 0.2, 0.3), Vector3(p, (h + 0.2) * 0.5, side * (HALF - t * 0.5 - 0.1)), _concrete_wall)
			_mesh_box(_geometry, Vector3(0.3, h + 0.2, 0.7), Vector3(side * (HALF - t * 0.5 - 0.1), (h + 0.2) * 0.5, p), _concrete_wall)
			p += 8.0


# ---------------------------------------------------------------------------
# Containers
# ---------------------------------------------------------------------------

func _build_containers() -> void:
	var seed_value := 10
	for name_key in CONTAINER_COLORS:
		var color: Color = CONTAINER_COLORS[name_key]
		# Corrugated body: metallic 0.6, roughness 0.4, rust from procedural noise.
		_container_mats[name_key] = ShipTex.make_painted_metal(
			color, seed_value, true, Vector3(1.0 / 2.0, 1.0 / C_H, 1.0 / 2.0), false, 0.65, 0.45)
		# Darker frame / edges.
		_edge_mats[name_key] = ShipTex.make_painted_metal(
			color.darkened(0.5), seed_value + 50, false, Vector3(1.0, 1.0, 1.0), false, 0.65, 0.45)
		seed_value += 1
	for c in CONTAINERS:
		_add_container(Vector3(c[0], c[4] * C_H, c[1]), c[2], c[3], c[4] == 0)


func _add_container(base: Vector3, rot_y_deg: float, color_key: String, is_cover: bool) -> void:
	var size := Vector3(C_LEN, C_H, C_W)
	var body := _solid_box(size, base + Vector3(0, C_H * 0.5, 0), _container_mats[color_key], Vector3(0, rot_y_deg, 0))
	body.name = "Container_%s" % color_key
	if is_cover:
		_make_cover(body, C_LEN * 0.5)

	var edge: Material = _edge_mats[color_key]
	var first_detail := body.get_child_count()
	var hx := C_LEN * 0.5
	var hy := C_H * 0.5
	var hz := C_W * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh_box(body, Vector3(0.16, C_H + 0.02, 0.16), Vector3(sx * (hx - 0.07), 0, sz * (hz - 0.07)), edge)   # corner posts
	for sy in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh_box(body, Vector3(C_LEN, 0.15, 0.15), Vector3(0, sy * (hy - 0.065), sz * (hz - 0.065)), edge)      # long rails
		for sx in [-1.0, 1.0]:
			_mesh_box(body, Vector3(0.14, 0.14, C_W), Vector3(sx * (hx - 0.06), sy * (hy - 0.06), 0), edge)         # short rails

	# Door end (+X): seam, lock rods and handles.
	_mesh_box(body, Vector3(0.03, C_H - 0.3, 0.04), Vector3(hx + 0.015, 0, 0), edge)
	for z in [-0.85, -0.28, 0.28, 0.85]:
		_mesh_cylinder(body, 0.025, C_H - 0.3, Vector3(hx + 0.035, 0, z), edge)
		_mesh_box(body, Vector3(0.05, 0.05, 0.22), Vector3(hx + 0.05, -0.2, z + 0.08), edge)
	# The frame and door hardware do not need their own shadows: the body already casts one.
	for i in range(first_detail, body.get_child_count()):
		var detail := body.get_child(i) as GeometryInstance3D
		if detail != null:
			detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# Warehouse (open doors, shelves, crates, barrels)
# ---------------------------------------------------------------------------

func _build_warehouse() -> void:
	var cx := -22.0
	var cz := -24.0
	var hx := 11.0
	var hz := 8.0
	var h := 6.0
	var t := 0.4
	var sheet := ShipTex.make_painted_metal(Color(0.42, 0.47, 0.5), 30, true, Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), true, 0.5, 0.5, 0.7)
	var roof_mat := ShipTex.make_painted_metal(Color(0.3, 0.32, 0.34), 31, true, Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0), true, 0.5, 0.5, 0.9)
	var door_mat := ShipTex.make_painted_metal(Color(0.6, 0.5, 0.12), 32, true, Vector3(1.0 / 1.5, 1.0 / 2.0, 1.0 / 1.5), false, 0.6, 0.4)

	# North and west walls (solid).
	_solid_box(Vector3(hx * 2.0 + t, h, t), Vector3(cx, h * 0.5, cz - hz), sheet).name = "WarehouseNorth"
	_solid_box(Vector3(t, h, hz * 2.0), Vector3(cx - hx, h * 0.5, cz), sheet).name = "WarehouseWest"

	# East wall with a side door (2.4 m wide, 3 m high).
	var side_w := 2.4
	var side_h := 3.0
	var seg := hz - side_w * 0.5
	_solid_box(Vector3(t, h, seg), Vector3(cx + hx, h * 0.5, cz - hz + seg * 0.5), sheet)
	_solid_box(Vector3(t, h, seg), Vector3(cx + hx, h * 0.5, cz + hz - seg * 0.5), sheet)
	_solid_box(Vector3(t, h - side_h, side_w), Vector3(cx + hx, side_h + (h - side_h) * 0.5, cz), sheet)

	# South wall with the main opening (7 m wide, 4.6 m high).
	var door_w := 7.0
	var door_h := 4.6
	var south_seg := hx - door_w * 0.5
	_solid_box(Vector3(south_seg + t * 0.5, h, t), Vector3(cx - hx + south_seg * 0.5 - t * 0.25, h * 0.5, cz + hz), sheet)
	_solid_box(Vector3(south_seg + t * 0.5, h, t), Vector3(cx + hx - south_seg * 0.5 + t * 0.25, h * 0.5, cz + hz), sheet)
	_solid_box(Vector3(door_w, h - door_h, t), Vector3(cx, door_h + (h - door_h) * 0.5, cz + hz), sheet)

	# Open door leaves, swung outwards.
	for side in [-1.0, 1.0]:
		var leaf := Vector3(door_w * 0.5, door_h, 0.12)
		var hinge := Vector3(cx + side * door_w * 0.5, 0, cz + hz + t * 0.5)
		var angle: float = 78.0 * side
		var dir := Vector3(cos(deg_to_rad(angle)) * float(side), 0, absf(sin(deg_to_rad(angle))))
		var door := _solid_box(leaf, hinge + dir * leaf.x * 0.5 + Vector3(0, door_h * 0.5, 0), door_mat, Vector3(0, -angle, 0))
		door.name = "WarehouseDoor"
		_mesh_box(door, Vector3(leaf.x, 0.12, 0.16), Vector3(0, door_h * 0.5 - 0.06, 0), _dark_metal)
		_mesh_box(door, Vector3(leaf.x, 0.12, 0.16), Vector3(0, -door_h * 0.5 + 0.06, 0), _dark_metal)

	# Roof (visual only) with two skylight strips and roof beams.
	_mesh_box(_geometry, Vector3(hx * 2.0 + 1.0, 0.25, hz * 2.0 + 1.0), Vector3(cx, h + 0.125, cz), roof_mat)
	for i in 4:
		_mesh_box(_geometry, Vector3(0.25, 0.4, hz * 2.0), Vector3(cx - hx + 2.75 + i * 5.5, h - 0.2, cz), _dark_metal)

	# Interior lamps (emissive + light).
	var lamp_mat := ShipTex.make_emissive_material(Color(1.0, 0.9, 0.7), 3.5)
	for lx in [cx - 5.0, cx + 5.0]:
		_mesh_box(_geometry, Vector3(1.4, 0.1, 0.3), Vector3(lx, h - 0.45, cz), lamp_mat)
		_add_light(Vector3(lx, h - 0.8, cz), Color(1.0, 0.9, 0.72), 2.2, 14.0)

	# Shelves along the north wall and one on the west wall.
	for i in 3:
		_add_shelf(Vector3(cx - 7.0 + i * 6.0, 0, cz - hz + 0.8), 0.0, i)
	_add_shelf(Vector3(cx - hx + 0.8, 0, cz + 2.5), 90.0, 3)

	# Crates and barrels inside.
	_add_crate_stack(Vector3(cx - 8.0, 0, cz + 4.0), 15.0, 1.0)
	_add_crate_stack(Vector3(cx + 7.5, 0, cz - 4.5), -20.0, 0.9)
	_add_crate(Vector3(cx + 3.0, 0, cz + 5.5), 0.7, 35.0)
	_add_barrel_group(Vector3(cx + 8.5, 0, cz + 5.5), 4, 5)
	_add_barrel_group(Vector3(cx - 2.0, 0, cz - 6.6), 3, 6)


func _add_shelf(base: Vector3, rot_y_deg: float, seed_value: int) -> void:
	var length := 4.0
	var height := 2.6
	var depth := 0.8
	var body := _solid_box(Vector3(length, height, depth), base + Vector3(0, height * 0.5, 0), null, Vector3(0, rot_y_deg, 0), false)
	body.name = "Shelf"
	var board_size := Vector3(length, 0.06, depth)
	var board := _get_wood(board_size)
	# Metal uprights.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh_box(body, Vector3(0.07, height, 0.07), Vector3(sx * (length * 0.5 - 0.04), 0, sz * (depth * 0.5 - 0.04)), _dark_metal)
	# Wooden boards with small crates and barrels on them.
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + seed_value
	var barrel_mat := ShipTex.make_barrel_material(Color(0.12, 0.3, 0.5), 7)
	for level in 3:
		var y := -height * 0.5 + 0.35 + level * 0.95
		_mesh_box(body, board_size, Vector3(0, y, 0), board)
		var x := -length * 0.5 + 0.45
		while x < length * 0.5 - 0.3:
			var roll := rng.randf()
			if roll < 0.55:
				var s := rng.randf_range(0.42, 0.6)
				_mesh_box(body, Vector3(s, s, s), Vector3(x, y + 0.03 + s * 0.5, rng.randf_range(-0.06, 0.06)),
					_get_wood(Vector3(s, s, s)), Vector3(0, rng.randf_range(-12.0, 12.0), 0))
			elif roll < 0.75:
				_mesh_cylinder(body, 0.2, 0.55, Vector3(x, y + 0.03 + 0.275, 0), barrel_mat)
			x += rng.randf_range(0.65, 0.95)


# ---------------------------------------------------------------------------
# Crates, barrels, sandbags
# ---------------------------------------------------------------------------

func _get_wood(size: Vector3) -> StandardMaterial3D:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _wood_mats.has(key):
		_wood_mats[key] = ShipTex.make_wood_material(size)
	return _wood_mats[key]


func _add_crate(base: Vector3, size: float, rot_y_deg: float) -> StaticBody3D:
	var s := Vector3(size, size, size)
	var crate := _solid_box(s, base + Vector3(0, size * 0.5, 0), _get_wood(s), Vector3(0, rot_y_deg, 0))
	crate.name = "Crate"
	return crate


## Two crates side by side with a third on top: enemy cover.
func _add_crate_stack(base: Vector3, rot_y_deg: float, size: float) -> void:
	var right := Vector3(cos(deg_to_rad(rot_y_deg)), 0, -sin(deg_to_rad(rot_y_deg)))
	var a := _add_crate(base - right * size * 0.52, size, rot_y_deg)
	_add_crate(base + right * size * 0.52, size, rot_y_deg + 4.0)
	_add_crate(base + Vector3(0, size, 0) + right * size * 0.1, size * 0.85, rot_y_deg + 17.0)
	_make_cover(a, size * 1.1)


func _add_barrel(base: Vector3, material: Material) -> void:
	var radius := 0.3
	var height := 0.9
	var body := StaticBody3D.new()
	body.name = "Barrel"
	body.position = base + Vector3(0, height * 0.5, 0)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_geometry.add_child(body)
	_mesh_cylinder(body, radius, height, Vector3.ZERO, material)
	# Rim.
	_mesh_cylinder(body, radius + 0.012, 0.04, Vector3(0, height * 0.5 - 0.02, 0), _dark_metal)


func _add_barrel_group(center: Vector3, count: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_value
	var colors := [Color(0.12, 0.3, 0.5), Color(0.55, 0.12, 0.1), Color(0.3, 0.32, 0.3), Color(0.75, 0.55, 0.1)]
	var offsets := [Vector2(0, 0), Vector2(0.66, 0.1), Vector2(0.3, 0.62), Vector2(-0.4, 0.55), Vector2(0.95, 0.7)]
	for i in mini(count, offsets.size()):
		var mat := ShipTex.make_barrel_material(colors[rng.randi() % colors.size()], 3 + rng.randi() % 3)
		_add_barrel(center + Vector3(offsets[i].x, 0, offsets[i].y), mat)


## Low wall of stacked sandbags (roughness 1.0): crouch-height cover.
func _add_sandbag_wall(center: Vector3, rot_y_deg: float, bags_long: int = 5) -> void:
	var bag_len := 0.62
	var bag_h := 0.24
	var rows := 4
	var length := bags_long * bag_len
	var body := _solid_box(Vector3(length, rows * bag_h, 0.45), center + Vector3(0, rows * bag_h * 0.5, 0), null, Vector3(0, rot_y_deg, 0), false)
	body.name = "Sandbags"
	_make_cover(body, length * 0.5)
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.17
	mesh.height = bag_len + 0.12
	mesh.radial_segments = 10
	mesh.rings = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center.x * 13.0 + center.z * 7.0)
	for row in rows:
		var count := bags_long if row % 2 == 0 else bags_long - 1
		var start := -(count - 1) * bag_len * 0.5
		for i in count:
			var bag := _mesh_part(body, mesh,
				Vector3(start + i * bag_len, -rows * bag_h * 0.5 + bag_h * 0.5 + row * bag_h, rng.randf_range(-0.03, 0.03)),
				_sandbag_mat, Vector3(rng.randf_range(-4.0, 4.0), rng.randf_range(-5.0, 5.0), 90.0))
			bag.scale = Vector3(0.72, 1.0, 1.25)


func _build_props() -> void:
	# Crate stacks around the yard.
	_add_crate_stack(Vector3(-7.0, 0, -7.0), 25.0, 1.0)
	_add_crate_stack(Vector3(11.0, 0, 13.5), -10.0, 0.9)
	_add_crate_stack(Vector3(-11.0, 0, 24.0), 40.0, 1.0)
	_add_crate_stack(Vector3(22.0, 0, 24.5), 5.0, 1.0)
	_add_crate_stack(Vector3(-30.0, 0, -6.0), -30.0, 0.9)
	_add_crate_stack(Vector3(33.0, 0, -32.0), 60.0, 1.0)
	_add_crate(Vector3(-5.2, 0, -8.6), 0.7, 50.0)
	_add_crate(Vector3(12.6, 0, 12.2), 0.6, 20.0)

	# Barrels.
	_add_barrel_group(Vector3(5.5, 0, -11.5), 4, 1)
	_add_barrel_group(Vector3(-11.0, 0, 1.5), 3, 2)
	_add_barrel_group(Vector3(14.5, 0, 23.0), 5, 3)
	_add_barrel_group(Vector3(36.5, 0, 34.5), 4, 4)
	_add_barrel_group(Vector3(-36.0, 0, -36.0), 3, 8)

	# Sandbag walls.
	_add_sandbag_wall(Vector3(-5.5, 0, 24.0), 0.0)
	_add_sandbag_wall(Vector3(12.0, 0, -7.5), 90.0)
	_add_sandbag_wall(Vector3(-13.0, 0, -9.5), 20.0, 6)
	_add_sandbag_wall(Vector3(27.0, 0, 3.2), 0.0)
	_add_sandbag_wall(Vector3(-28.0, 0, 12.5), -15.0)
	_add_sandbag_wall(Vector3(5.5, 0, 29.5), 0.0, 4)


# ---------------------------------------------------------------------------
# Cranes with emissive lights
# ---------------------------------------------------------------------------

func _add_light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	add_child(light)


func _build_cranes() -> void:
	_add_gantry_crane(Vector3(20.0, 0, -12.0), 0.0, 30.0, 11.0, 0.25)
	_add_gantry_crane(Vector3(-20.0, 0, 16.0), 90.0, 24.0, 9.0, -0.3)


## Gantry crane: two A-shaped legs, a top girder, trolley, cables, spreader and lights.
func _add_gantry_crane(center: Vector3, rot_y_deg: float, span: float, height: float, trolley_pos: float) -> void:
	var paint := ShipTex.make_painted_metal(Color(0.85, 0.6, 0.08), 60, false, Vector3(0.5, 0.5, 0.5), true, 0.9, 0.3, 0.8, 1.0)
	var flood := ShipTex.make_emissive_material(Color(1.0, 0.93, 0.75), 4.0)
	var beacon := ShipTex.make_emissive_material(Color(1.0, 0.08, 0.05), 5.0)
	var cabin_glass := ShipTex.make_emissive_material(Color(0.45, 0.75, 1.0), 1.2)

	var root := Node3D.new()
	root.name = "Crane"
	root.position = center
	root.rotation_degrees.y = rot_y_deg
	_geometry.add_child(root)

	var leg_spread := 2.0
	for sx in [-1.0, 1.0]:
		var x: float = sx * span * 0.5
		for sz in [-1.0, 1.0]:
			# Leg post (solid).
			var post := StaticBody3D.new()
			post.position = Vector3(x, height * 0.5, sz * leg_spread)
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.6, height, 0.6)
			var col := CollisionShape3D.new()
			col.shape = shape
			post.add_child(col)
			root.add_child(post)
			_mesh_box(post, shape.size, Vector3.ZERO, paint)
			# Wheel truck at the base.
			_mesh_box(root, Vector3(0.9, 0.5, 1.3), Vector3(x, 0.25, sz * leg_spread), _dark_metal)
		# Cross braces between the two posts of a leg.
		_mesh_box(root, Vector3(0.3, 0.3, leg_spread * 2.0), Vector3(x, height * 0.45, 0), paint)
		_mesh_box(root, Vector3(0.3, 0.3, leg_spread * 2.0), Vector3(x, height - 0.9, 0), paint)
		_mesh_box(root, Vector3(0.2, 0.2, leg_spread * 2.6), Vector3(x, height * 0.7, 0), paint, Vector3(38, 0, 0))

	# Top girder (double beam) with walkway.
	for sz in [-1.0, 1.0]:
		_mesh_box(root, Vector3(span + 3.0, 1.1, 0.7), Vector3(0, height + 0.55, sz * 1.1), paint)
	_mesh_box(root, Vector3(span + 3.0, 0.1, 1.5), Vector3(0, height + 0.05, 0), _dark_metal)

	# Trolley, cabin, cables and spreader.
	var tx := trolley_pos * span
	_mesh_box(root, Vector3(2.4, 0.7, 3.0), Vector3(tx, height + 1.45, 0), _dark_metal)
	_mesh_box(root, Vector3(1.6, 1.5, 1.6), Vector3(tx + 2.2, height - 0.85, 1.9), paint)
	_mesh_box(root, Vector3(1.3, 0.7, 0.06), Vector3(tx + 2.2, height - 0.75, 2.72), cabin_glass)
	var cable_len := height * 0.42
	for cxo in [-0.9, 0.9]:
		for czo in [-0.6, 0.6]:
			_mesh_cylinder(root, 0.03, cable_len, Vector3(tx + cxo, height - cable_len * 0.5, czo), _dark_metal)
	_mesh_box(root, Vector3(5.6, 0.3, 2.2), Vector3(tx, height - cable_len - 0.15, 0), paint)
	_mesh_box(root, Vector3(5.8, 0.12, 0.2), Vector3(tx, height - cable_len - 0.36, 1.0), _dark_metal)
	_mesh_box(root, Vector3(5.8, 0.12, 0.2), Vector3(tx, height - cable_len - 0.36, -1.0), _dark_metal)

	# Emissive floodlights under the girder + red warning beacons on top.
	for fx in [-span * 0.28, span * 0.28]:
		_mesh_box(root, Vector3(1.0, 0.25, 0.6), Vector3(fx, height - 0.15, 0), flood)
		var world := root.transform * Vector3(fx, height - 1.2, 0)
		_add_light(world, Color(1.0, 0.92, 0.75), 2.6, 20.0)
	for sx in [-1.0, 1.0]:
		_mesh_box(root, Vector3(0.3, 0.3, 0.3), Vector3(sx * (span * 0.5 + 1.2), height + 1.3, 0), beacon)
	_mesh_box(root, Vector3(0.3, 0.3, 0.3), Vector3(tx, height + 1.95, 0), beacon)


# ---------------------------------------------------------------------------
# Puddles and tire marks
# ---------------------------------------------------------------------------

func _build_puddles() -> void:
	# x, z, size x, size z, rotation
	var puddles := [
		[2.5, 26.0, 4.5, 3.0, 20.0],
		[-7.5, 6.5, 3.5, 2.6, -35.0],
		[12.5, -15.0, 5.0, 3.2, 10.0],
		[-17.0, -11.5, 3.2, 2.4, 70.0],
		[24.5, 11.0, 4.0, 2.8, -15.0],
		[-30.0, 29.0, 5.5, 3.6, 40.0],
		[0.5, -29.0, 3.8, 2.6, 0.0],
		[33.0, -5.0, 3.0, 2.2, 55.0],
	]
	for i in puddles.size():
		var p: Array = puddles[i]
		var plane := PlaneMesh.new()
		plane.size = Vector2(p[2], p[3])
		var puddle := _mesh_part(self, plane, Vector3(p[0], 0.022, p[1]), ShipTex.make_puddle_material(200 + i % 4), Vector3(0, p[4], 0))
		puddle.name = "Puddle%d" % (i + 1)
		puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _use_decal_nodes() -> bool:
	if tire_mark_mode == "decal_nodes":
		return true
	if tire_mark_mode == "flat_quads":
		return false
	# Decal nodes are not drawn by the Compatibility (OpenGL) renderer.
	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	if RenderingServer.has_method("get_current_rendering_method"):
		method = str(RenderingServer.call("get_current_rendering_method"))
	return method != "gl_compatibility"


func _build_tire_marks() -> void:
	# x, z, length, width, rotation Y (0 = along X)
	var marks := [
		[0.6, 20.0, 12.0, 2.2, 90.0],
		[-1.2, -8.0, 14.0, 2.2, 86.0],
		[1.5, -24.0, 10.0, 2.2, 95.0],
		[-16.0, 7.2, 13.0, 2.2, 2.0],
		[18.0, 6.6, 15.0, 2.2, -3.0],
		[-21.5, -11.5, 9.0, 2.2, 78.0],
		[5.5, 9.5, 8.0, 2.2, 42.0],
		[-6.0, 3.5, 7.0, 2.2, -50.0],
		[30.0, -12.0, 9.0, 2.2, 0.0],
		[24.0, 30.5, 8.0, 2.2, 8.0],
	]
	var use_decals := _use_decal_nodes()
	var holder := Node3D.new()
	holder.name = "TireMarks"
	add_child(holder)
	for i in marks.size():
		var m: Array = marks[i]
		if use_decals:
			var decal := Decal.new()
			decal.texture_albedo = ShipTex.make_tire_mark_texture(300 + i % 3)
			decal.size = Vector3(m[2], 0.6, m[3])
			decal.position = Vector3(m[0], 0.1, m[1])
			decal.rotation_degrees.y = m[4]
			decal.upper_fade = 0.0
			decal.lower_fade = 0.0
			holder.add_child(decal)
		else:
			var plane := PlaneMesh.new()
			plane.size = Vector2(m[2], m[3])
			var quad := _mesh_part(holder, plane, Vector3(m[0], 0.016, m[1]), ShipTex.make_tire_mark_material(300 + i % 3), Vector3(0, m[4], 0))
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# Navigation and enemies
# ---------------------------------------------------------------------------

## Bakes the navigation mesh from every static collider under Geometry.
func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = &"navmesh_source"
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.75
	nav_mesh.agent_max_climb = 0.25

	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	nav_region.navigation_mesh = nav_mesh


func _spawn_enemies() -> void:
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	var index := 0
	for marker in spawns.get_children():
		if not marker.name.begins_with("EnemySpawn"):
			continue
		var enemy := ENEMY_SCENE.instantiate()
		enemy.name = "Enemy%d" % (index + 1)
		enemy.vest_color = ENEMY_VESTS[index % ENEMY_VESTS.size()]
		var route: Array[Vector3] = []
		for point in ENEMY_PATROLS[index % ENEMY_PATROLS.size()]:
			route.append(Vector3(point.x, 0.0, point.y))
		enemy.patrol_points = route
		enemy.transform = (marker as Node3D).global_transform
		enemies.add_child(enemy)
		index += 1
