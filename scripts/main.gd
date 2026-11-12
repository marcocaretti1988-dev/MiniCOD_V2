extends Node3D
## Main test scene. Lighting and environment live in main.tscn.
## A few concrete blocks are spawned here only as visual reference for
## shadows / SSAO (no weapons, no enemies yet).

const ProcTex := preload("res://scripts/procedural_textures.gd")

# position (x, z), size (x, y, z), rotation Y in degrees
const BLOCKS := [
	[Vector2(-8.0, -6.0), Vector3(3.0, 1.2, 1.0), 15.0],
	[Vector2(8.5, -10.0), Vector3(1.0, 2.5, 4.0), -10.0],
	[Vector2(-15.0, -22.0), Vector3(4.0, 3.0, 4.0), 30.0],
	[Vector2(3.0, -26.0), Vector3(2.0, 1.0, 2.0), 45.0],
	[Vector2(20.0, 4.0), Vector3(6.0, 2.0, 1.0), 0.0],
	[Vector2(-7.0, 14.0), Vector3(1.5, 1.5, 1.5), 60.0],
]


func _ready() -> void:
	var block_material := ProcTex.make_concrete_material(0.35, true, Color(0.9, 0.88, 0.84), 21)
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	for data in BLOCKS:
		props.add_child(_make_block(data[0], data[1], data[2], block_material))


func _make_block(pos: Vector2, size: Vector3, rot_y_deg: float, material: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = Vector3(pos.x, size.y * 0.5, pos.y)
	body.rotation_degrees.y = rot_y_deg

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
