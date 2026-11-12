extends Node
## Autoload "GameSettings": graphics quality (Low / Medium), saved between runs.
## Shadows, fog and bloom stay on at both levels.
##   Medium: 4x MSAA, 4096 shadow map with soft PCF filter, SSAO on, full resolution.
##   Low:    no MSAA, 2048 shadow map with a lighter filter, SSAO off, 75% 3D resolution.

signal quality_changed(quality: String)

const SAVE_PATH := "user://settings.cfg"
const QUALITIES := ["low", "medium"]

var quality: String = "medium"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var saved := str(config.get_value("graphics", "quality", quality))
		if saved in QUALITIES:
			quality = saved
	# Every WorldEnvironment that enters the tree gets the current quality.
	get_tree().node_added.connect(_on_node_added)
	apply()


func set_quality(value: String) -> void:
	if not value in QUALITIES or value == quality:
		return
	quality = value
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", quality)
	config.save(SAVE_PATH)
	apply()
	quality_changed.emit(quality)


func get_quality_index() -> int:
	return QUALITIES.find(quality)


func apply() -> void:
	var viewport := get_tree().root
	var low := quality == "low"
	viewport.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_4X
	viewport.scaling_3d_scale = 0.75 if low else 1.0
	RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if low else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_environment(node as WorldEnvironment)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_apply_environment.call_deferred(node)


func _apply_environment(world: WorldEnvironment) -> void:
	if world == null or not is_instance_valid(world) or world.environment == null:
		return
	world.environment.ssao_enabled = quality != "low"
