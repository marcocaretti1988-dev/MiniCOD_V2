extends Node3D
## Main test scene. Lighting and environment live in main.tscn.
## Spawns the concrete blocks (cover), bakes the navigation mesh and
## spawns the enemies.

const ProcTex := preload("res://scripts/procedural_textures.gd")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

# position (x, z), size (x, y, z), rotation Y in degrees
const BLOCKS := [
	[Vector2(-8.0, -6.0), Vector3(3.0, 1.2, 1.0), 15.0],
	[Vector2(8.5, -10.0), Vector3(1.0, 2.5, 4.0), -10.0],
	[Vector2(-15.0, -22.0), Vector3(4.0, 3.0, 4.0), 30.0],
	[Vector2(3.0, -26.0), Vector3(2.0, 1.0, 2.0), 45.0],
	[Vector2(20.0, 4.0), Vector3(6.0, 2.0, 1.0), 0.0],
	[Vector2(-7.0, 14.0), Vector3(1.5, 1.5, 1.5), 60.0],
]

# spawn position (x, z), vest colour
const ENEMIES := [
	[Vector2(-22.0, -28.0), Color(0.27, 0.33, 0.19)],  # olive
	[Vector2(14.0, -34.0), Color(0.5, 0.4, 0.26)],     # desert tan
	[Vector2(32.0, -8.0), Color(0.16, 0.2, 0.3)],      # navy
	[Vector2(-32.0, 2.0), Color(0.42, 0.14, 0.12)],    # dark red
	[Vector2(-2.0, -40.0), Color(0.3, 0.3, 0.32)],     # grey
	[Vector2(28.0, 26.0), Color(0.12, 0.12, 0.13)],    # black
]


func _ready() -> void:
	# Lets the enemies find the player without touching the player scene.
	var player := get_node_or_null("Player")
	if player != null:
		player.add_to_group("player")

	var block_material := ProcTex.make_concrete_material(0.35, true, Color(0.9, 0.88, 0.84), 21)
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	for data in BLOCKS:
		props.add_child(_make_block(data[0], data[1], data[2], block_material))

	_bake_navigation(props)
	_spawn_enemies()


func _make_block(pos: Vector2, size: Vector3, rot_y_deg: float, material: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(pos.x, size.y * 0.5, pos.y)
	body.rotation_degrees.y = rot_y_deg
	# Enemies hide behind these when hurt.
	body.add_to_group("cover")
	body.set_meta("cover_radius", maxf(size.x, size.z) * 0.5)

	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


## Builds the navigation mesh from the ground and block colliders.
func _bake_navigation(props: Node3D) -> void:
	var ground := get_node_or_null("Ground")
	if ground != null:
		ground.add_to_group("navmesh_source")
	props.add_to_group("navmesh_source")

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

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = nav_mesh
	add_child(region)


func _spawn_enemies() -> void:
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	for i in ENEMIES.size():
		var data: Array = ENEMIES[i]
		var enemy := ENEMY_SCENE.instantiate()
		enemy.name = "Enemy%d" % (i + 1)
		enemy.vest_color = data[1]
		enemy.position = Vector3(data[0].x, 0.05, data[0].y)
		enemy.rotation.y = randf() * TAU
		enemies.add_child(enemy)
