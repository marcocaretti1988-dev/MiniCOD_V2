extends Node3D
## Keeps this node on the active camera (used by the dust motes so the air
## around the player is always filled, wherever they walk).


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position
