extends Control
## Top-down minimap: obstacles, beacons and the player arrow. North (-Z) is up.

@export var world_size: float = 80.0
@export var background: Color = Color(0.05, 0.07, 0.09, 0.62)
@export var obstacle_color: Color = Color(0.62, 0.66, 0.7, 0.75)
@export var player_color: Color = Color(0.35, 0.85, 1.0)
@export var beacon_color: Color = Color(1.0, 0.82, 0.15)
@export var beacon_done_color: Color = Color(0.3, 0.95, 0.4)

var player: Node3D
var beacons: Array = []

var _polygons: Array[PackedVector2Array] = []  # in world XZ metres
var _circles: Array[Vector3] = []              # x, z, radius
var _time: float = 0.0
# All the obstacles as one mesh: one draw call instead of
# one per obstacle. Coordinates go from 0 to 1.
var _static_mesh: ArrayMesh


## Collects the footprint of every static collider under root (called once).
func setup(root: Node, player_node: Node3D, beacon_nodes: Array, map_size: float) -> void:
	player = player_node
	beacons = beacon_nodes
	world_size = map_size
	_polygons.clear()
	_circles.clear()
	if root != null:
		_collect(root)
	_build_static_mesh()
	queue_redraw()


func _build_static_mesh() -> void:
	_static_mesh = null
	var verts := PackedVector2Array()
	var indices := PackedInt32Array()
	for poly in _polygons:
		var base := verts.size()
		for p in poly:
			verts.append(_to_unit(p.x, p.y))
		for i in range(1, poly.size() - 1):
			indices.append(base)
			indices.append(base + i)
			indices.append(base + i + 1)
	var steps := 10
	for circle in _circles:
		var base := verts.size()
		var centre := _to_unit(circle.x, circle.y)
		var radius := maxf(circle.z, 0.6) / world_size
		verts.append(centre)
		for i in steps:
			var angle := TAU * float(i) / float(steps)
			verts.append(centre + Vector2.from_angle(angle) * radius)
		for i in steps:
			indices.append(base)
			indices.append(base + 1 + i)
			indices.append(base + 1 + (i + 1) % steps)
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	_static_mesh = ArrayMesh.new()
	_static_mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, arrays)


func _to_unit(x: float, z: float) -> Vector2:
	return Vector2(x / world_size + 0.5, z / world_size + 0.5)


func _collect(node: Node) -> void:
	if node is CollisionShape3D and node.get_parent() is StaticBody3D and node.shape != null:
		var xf: Transform3D = node.global_transform
		if node.shape is BoxShape3D:
			var s: Vector3 = node.shape.size
			# Skip the ground slab and anything floating above head height (stacked containers).
			var is_ground := s.x > world_size * 0.7 and s.z > world_size * 0.7
			if not is_ground and xf.origin.y - s.y * 0.5 < 1.5:
				var poly := PackedVector2Array()
				for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var p := xf * Vector3(corner.x * s.x * 0.5, 0.0, corner.y * s.z * 0.5)
					poly.append(Vector2(p.x, p.z))
				_polygons.append(poly)
		elif node.shape is CylinderShape3D:
			_circles.append(Vector3(xf.origin.x, xf.origin.z, node.shape.radius))
	for child in node.get_children():
		_collect(child)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _to_map(x: float, z: float) -> Vector2:
	return Vector2((x / world_size + 0.5) * size.x, (z / world_size + 0.5) * size.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background)

	if _static_mesh != null:
		var fit := Transform2D(0.0, size, 0.0, Vector2.ZERO)
		draw_mesh(_static_mesh, null, fit, obstacle_color)

	# Beacons: pulsing yellow, steady green when activated.
	for beacon in beacons:
		if not is_instance_valid(beacon):
			continue
		var pos := _to_map(beacon.global_position.x, beacon.global_position.z)
		if beacon.is_active:
			draw_circle(pos, 5.0, beacon_done_color)
		else:
			var pulse := 0.5 + 0.5 * sin(_time * 4.0)
			draw_circle(pos, 6.0 + pulse * 4.0, Color(beacon_color.r, beacon_color.g, beacon_color.b, 0.3))
			draw_circle(pos, 4.5, beacon_color)
		draw_arc(pos, 5.5, 0.0, TAU, 16, Color(0, 0, 0, 0.7), 1.0, true)

	# Player arrow.
	if player != null and is_instance_valid(player):
		var centre := _to_map(player.global_position.x, player.global_position.z)
		var forward3 := -player.global_transform.basis.z
		var forward := Vector2(forward3.x, forward3.z).normalized()
		var right := Vector2(-forward.y, forward.x)
		var arrow := PackedVector2Array([
			centre + forward * 9.0,
			centre - forward * 6.0 + right * 6.0,
			centre - forward * 2.5,
			centre - forward * 6.0 - right * 6.0,
		])
		draw_colored_polygon(arrow, player_color)
		draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color(0, 0, 0, 0.8), 1.2, true)

	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55), false, 2.0)
