extends StaticBody3D
## 100x100 m ground: tiled procedural concrete + a transparent layer with
## painted lines and tire marks drawn by code (see procedural_textures.gd).

const ProcTex := preload("res://scripts/procedural_textures.gd")

## How many times the concrete slab texture repeats across the ground (25 = 4 m slabs).
@export var concrete_tiles: float = 25.0

@onready var surface: MeshInstance3D = $Surface
@onready var markings: MeshInstance3D = $Markings


func _ready() -> void:
	surface.material_override = ProcTex.make_concrete_material(concrete_tiles)
	markings.material_override = ProcTex.make_markings_material()
