extends Node3D
## Main menu: title, Play, quality selector and controls, over a slow camera
## fly-around of the shipyard. The background is the real level scene with the
## gameplay nodes removed, so it uses the same WorldEnvironment (sky, fog,
## bloom) and the same sun.

const MAP_SCENE := "res://scenes/maps/shipyard.tscn"
const GAMEPLAY_NODES := ["GameManager", "Polish"]
const LIVE_NODES := ["Enemies", "Player"]

const CONTROLS := [
	["W A S D", "Move"],
	["Mouse", "Look"],
	["Left click", "Shoot"],
	["Right click", "Aim"],
	["R", "Reload"],
	["1 / 2", "Weapons"],
	["Shift", "Sprint"],
	["C", "Crouch"],
	["Space", "Jump"],
	["Esc", "Pause"],
]

@export var orbit_radius: float = 36.0
@export var orbit_height: float = 15.0
@export var orbit_speed: float = 0.035
@export var look_target: Vector3 = Vector3(0.0, 2.0, 0.0)

var _angle: float = 0.7
var _play_button: Button

@onready var camera: Camera3D = $MenuCamera
@onready var ui: CanvasLayer = $UI


func _ready() -> void:
	get_tree().paused = false
	_build_background()
	_build_ui()
	camera.make_current()
	_update_camera(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.post != null:
		settings.post.reset()


func _process(delta: float) -> void:
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	_angle += orbit_speed * delta
	camera.position = Vector3(cos(_angle) * orbit_radius, orbit_height + sin(_angle * 0.7) * 2.0, sin(_angle) * orbit_radius)
	camera.look_at(look_target)


## Loads the level and strips everything that plays the game.
func _build_background() -> void:
	var packed := load(MAP_SCENE) as PackedScene
	if packed == null:
		return
	var map := packed.instantiate()
	map.name = "Background"
	for node_name in GAMEPLAY_NODES:
		var node := map.get_node_or_null(node_name)
		if node != null:
			map.remove_child(node)
			node.free()
	add_child(map)  # the map builds its geometry here
	for node_name in LIVE_NODES:
		var node := map.get_node_or_null(node_name)
		if node != null:
			node.free()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.04, 0.06, 0.62)
	panel_style.border_color = Color(1.0, 0.8, 0.2, 0.9)
	panel_style.border_width_left = 4
	panel_style.set_content_margin_all(32)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 60.0
	panel.offset_right = 530.0
	panel.offset_top = 50.0
	panel.offset_bottom = -50.0
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _label("SHIPYARD STRIKE", 46, Color(1.0, 0.82, 0.2))
	box.add_child(title)
	box.add_child(_label("Eliminate 10 enemies before the 5:00 timer runs out.", 17, Color(0.85, 0.88, 0.92)))

	_play_button = _button("PLAY", 28, Vector2(0, 56))
	_play_button.pressed.connect(_on_play)
	box.add_child(_play_button)

	# Quality selector.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(_label("QUALITY", 20, Color.WHITE))
	var quality := OptionButton.new()
	quality.add_item("Low")
	quality.add_item("Medium")
	quality.add_item("High")
	quality.select(_settings().get_quality_index())
	quality.custom_minimum_size = Vector2(170, 42)
	quality.add_theme_font_size_override("font_size", 20)
	quality.item_selected.connect(func(index: int) -> void:
		_settings().set_quality(_settings().QUALITIES[index])
		_sfx(&"ui_click", -6.0))
	row.add_child(quality)

	# Renderer selector: changing it restarts the game.
	var renderer_row := HBoxContainer.new()
	renderer_row.add_theme_constant_override("separation", 14)
	box.add_child(renderer_row)
	renderer_row.add_child(_label("RENDERER", 20, Color.WHITE))
	var renderer := OptionButton.new()
	renderer.add_item("Forward+ (full graphics)")
	renderer.add_item("Compatibility (old Macs)")
	renderer.select(_settings().get_renderer_index())
	renderer.custom_minimum_size = Vector2(250, 42)
	renderer.add_theme_font_size_override("font_size", 17)
	renderer.item_selected.connect(func(index: int) -> void:
		_settings().set_renderer(_settings().RENDERERS[index]))
	renderer_row.add_child(renderer)
	box.add_child(_label("Changing renderer restarts the game. The 0 key switches it at any time.", 13, Color(0.75, 0.78, 0.82)))

	# Controls.
	box.add_child(_spacer(2))
	box.add_child(_label("CONTROLS", 20, Color(1.0, 0.82, 0.2)))
	var grid := GridContainer.new()
	grid.columns = 4  # two key / action pairs per row so the list fits at 720p
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	for entry in CONTROLS:
		grid.add_child(_label(entry[0], 16, Color.WHITE))
		grid.add_child(_label(entry[1], 16, Color(0.78, 0.82, 0.86)))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	var quit := _button("QUIT", 18, Vector2(0, 38))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	_play_button.grab_focus()


func _on_play() -> void:
	_sfx(&"ui_click", -4.0)
	get_tree().change_scene_to_file(MAP_SCENE)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(font_size / 8, 3))
	return label


func _button(text: String, font_size: int, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


# The autoloads are reached through their node path, so this script also
# compiles and runs when it is checked or opened on its own.
func _sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0, pitch_random: float = 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play(sound, volume_db, pitch, pitch_random)


func _settings() -> Node:
	return get_node("/root/GameSettings")
