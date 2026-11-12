extends CanvasLayer
## Pause menu (Esc): Resume, Restart, quality selector, Main Menu, Quit.

const MENU_SCENE := "res://scenes/ui/menu.tscn"

var _root: Control
var _resume_button: Button
var _quality: OptionButton


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _root.visible:
		resume()
	elif not get_tree().paused:
		pause()
	else:
		return  # paused by something else (win / lose screen)
	# Stop the player script from toggling the mouse on the same key press.
	get_viewport().set_input_as_handled()


func pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_quality.select(_settings().get_quality_index())
	_root.visible = true
	_resume_button.grab_focus()
	_sfx(&"ui_click", -6.0)


func resume() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_sfx(&"ui_click", -6.0)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	centre.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	_resume_button = _add_button(box, "RESUME", resume)
	_add_button(box, "RESTART", _restart)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var label := Label.new()
	label.text = "QUALITY"
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	_quality = OptionButton.new()
	_quality.add_item("Low")
	_quality.add_item("Medium")
	_quality.custom_minimum_size = Vector2(150, 40)
	_quality.add_theme_font_size_override("font_size", 20)
	_quality.select(_settings().get_quality_index())
	_quality.item_selected.connect(func(index: int) -> void:
		_settings().set_quality(_settings().QUALITIES[index]))
	row.add_child(_quality)

	_add_button(box, "MAIN MENU", _main_menu)
	_add_button(box, "QUIT", func() -> void: get_tree().quit())


func _add_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


# The autoloads are reached through their node path, so this script also
# compiles and runs when it is checked or opened on its own.
func _sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0, pitch_random: float = 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play(sound, volume_db, pitch, pitch_random)


func _settings() -> Node:
	return get_node("/root/GameSettings")
