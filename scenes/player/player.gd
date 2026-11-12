extends CharacterBody3D
## First person player.
## PC: mouse look, WASD, sprint, crouch, jump.
## Touch: left joystick, drag look, buttons.
## Gameplay values are the same on both.

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var max_pitch_degrees: float = 88.0

@export_group("Movement")
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 3.0
@export var ground_acceleration: float = 12.0
@export var air_acceleration: float = 3.0
@export var jump_velocity: float = 5.5
@export var gravity_multiplier: float = 1.6

@export_group("Crouch")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.1
# eyes this far below the top of the capsule
@export var eye_offset: float = 0.2
@export var crouch_lerp_speed: float = 10.0

@export_group("Head Bob")
@export var bob_enabled: bool = true
@export var bob_frequency: float = 1.9
@export var bob_amplitude: float = 0.055

@export_group("Camera")
@export var base_fov: float = 75.0
@export var sprint_fov: float = 82.0

@export_group("Touch")
@export var joy_radius: float = 60.0
@export var joy_deadzone: float = 0.15
@export var joy_sprint: float = 0.92
@export var button_size: float = 64.0
@export var touch_look_scale: float = 1.0
@export var aim_assist: bool = true
@export var aim_magnetism: float = 0.15
@export var aim_assist_angle: float = 7.0
@export var aim_assist_range: float = 45.0

const GRAV := "physics/3d/default_gravity"
const WEAPONS := "Head/Camera3D/WeaponHolder"
# name: [text, corner x, corner y, off x, off y, size]
# corner 1 = right / bottom, 0 = left / top.
# offsets and size are in button units.
const BUTTONS := {
	"fire": ["FIRE", 1, 1, -1.9, -2.0, 1.5],
	"aim": ["AIM", 1, 1, -3.4, -1.2, 1.0],
	"jump": ["JUMP", 1, 1, -0.65, -3.0, 1.0],
	"crouch": ["CRCH", 1, 1, -0.65, -0.7, 1.0],
	"reload": ["RLD", 1, 1, -3.1, -3.3, 1.0],
	"swap": ["1/2", 1, 1, -1.9, -4.0, 1.0],
	"pause": ["II", 1, 0, -0.7, 0.7, 1.0],
	"assist": ["AA", 1, 0, -1.9, 0.7, 1.0],
}
const HOLD := {
	"fire": "shoot",
	"jump": "jump",
	"reload": "reload",
}

var is_crouching: bool = false
var is_sprinting: bool = false
var is_mobile: bool = false

var _gravity: float = ProjectSettings.get_setting(GRAV)
var _current_height: float = 1.8
var _bob_time: float = 0.0

# Touch state.
var _touch_mode: bool = false
var _scale: float = 1.0
var _joy_id: int = -1
var _joy_origin: Vector2 = Vector2.ZERO
var _joy: Vector2 = Vector2.ZERO
var _look_id: int = -1
var _held: Dictionary = {}    # touch index -> action
var _touch_crouch: bool = false
var _touch_aim: bool = false
var _ui: CanvasLayer
var _panels: Dictionary = {}  # name -> Panel
var _joy_base: Panel
var _joy_knob: Panel

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = \
	collision.shape.duplicate()


func _ready() -> void:
	collision.shape = _capsule
	_current_height = stand_height
	_apply_height()
	camera.fov = base_fov
	is_mobile = detect_mobile()
	if is_mobile:
		_build_touch_ui()
		if DisplayServer.is_touchscreen_available():
			_enable_touch_mode()
	else:
		# Not in _ready: runs one frame later, and
		# never for the copy used as menu background
		# (that one is freed before this call).
		_capture_mouse.call_deferred()


static func detect_mobile() -> bool:
	return DisplayServer.is_touchscreen_available() \
		or OS.has_feature("web") \
		or OS.has_feature("mobile") \
		or OS.has_feature("android") \
		or OS.has_feature("ios")


func _capture_mouse() -> void:
	if is_mobile or get_tree().paused:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Called at start on touch devices, or by the first
## real touch. Makes the game work without a captured
## mouse and stops fake mouse clicks from shooting.
func _enable_touch_mode() -> void:
	if _touch_mode:
		return
	_touch_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for action in ["shoot", "aim"]:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)
	var weapons := get_node_or_null(WEAPONS)
	if weapons != null:
		weapons.set("require_mouse_capture", false)


func _exit_tree() -> void:
	_release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_release_all()


# -----------------------------------------------------
# PC input (mouse + keyboard)
# -----------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _touch_mode:
		return
	var mode := Input.mouse_mode
	var captured := mode == Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and captured:
		_look(event.relative * mouse_sensitivity)

	# Esc frees the mouse; click to capture again.
	if event.is_action_pressed("pause"):
		if captured:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton \
			and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _look(amount: Vector2) -> void:
	rotate_y(-amount.x)
	var limit := deg_to_rad(max_pitch_degrees)
	head.rotation.x = clampf(
		head.rotation.x - amount.y, -limit, limit)


# -----------------------------------------------------
# Touch input
# -----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_mobile:
		return
	if event is InputEventScreenTouch:
		_enable_touch_mode()
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event)


func _touch_down(index: int, pos: Vector2) -> void:
	var button := _button_at(pos)
	if button != "":
		_press_button(button, index)
		# The fire finger can also drag the view.
		if button == "fire" and _look_id == -1:
			_look_id = index
		return
	var half := get_viewport().get_visible_rect().size.x
	half *= 0.5
	if pos.x < half:
		if _joy_id == -1:
			_joy_id = index
			_joy_origin = pos
			_joy = Vector2.ZERO
			_update_joy_visual(pos)
	elif _look_id == -1:
		_look_id = index


func _touch_up(index: int) -> void:
	if index == _joy_id:
		_joy_id = -1
		_joy = Vector2.ZERO
		_layout()
	if index == _look_id:
		_look_id = -1
	if _held.has(index):
		Input.action_release(_held[index])
		_held.erase(index)
		_set_lit("fire", Input.is_action_pressed("shoot"))


func _touch_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joy_id:
		var radius := joy_radius * _scale
		var offset: Vector2 = event.position - _joy_origin
		var value := (offset / radius).limit_length(1.0)
		if value.length() < joy_deadzone:
			value = Vector2.ZERO
		_joy = value
		_update_joy_visual(event.position)
	elif event.index == _look_id:
		var k := mouse_sensitivity * touch_look_scale
		_look(event.relative * k)


func _button_at(pos: Vector2) -> String:
	for key in _panels:
		var panel: Panel = _panels[key]
		if panel.get_global_rect().has_point(pos):
			return key
	return ""


func _press_button(button: String, index: int) -> void:
	if HOLD.has(button):
		_hold(index, HOLD[button])
		_set_lit("fire", Input.is_action_pressed("shoot"))
	elif button == "swap":
		var weapons := get_node_or_null(WEAPONS)
		var slot := 0
		if weapons != null:
			slot = int(weapons.get("current_index"))
		_hold(index, "weapon_1" if slot == 1 else "weapon_2")
	elif button == "crouch":
		_touch_crouch = not _touch_crouch
		_set_lit("crouch", _touch_crouch)
	elif button == "aim":
		_touch_aim = not _touch_aim
		if _touch_aim:
			Input.action_press("aim")
		else:
			Input.action_release("aim")
		_set_lit("aim", _touch_aim)
	elif button == "assist":
		aim_assist = not aim_assist
		_set_lit("assist", aim_assist)
	elif button == "pause":
		var ev := InputEventAction.new()
		ev.action = "pause"
		ev.pressed = true
		# Deferred: sent after this touch is done.
		Input.parse_input_event.call_deferred(ev)


func _hold(index: int, action: String) -> void:
	if not InputMap.has_action(action):
		return
	_held[index] = action
	Input.action_press(action)


func _release_all() -> void:
	for index in _held:
		Input.action_release(_held[index])
	_held.clear()
	if _touch_aim:
		Input.action_release("aim")
		_touch_aim = false
	_joy_id = -1
	_look_id = -1
	_joy = Vector2.ZERO
	if _ui != null:
		_set_lit("fire", false)
		_set_lit("aim", false)


# -----------------------------------------------------
# Movement (same values as the PC version)
# -----------------------------------------------------

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Gravity.
	if not on_floor:
		velocity.y -= _gravity * gravity_multiplier * delta

	# Crouch: hold on PC, toggle on touch.
	# Stay crouched if there is no room to stand up.
	if Input.is_action_pressed("crouch") or _touch_crouch:
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	_update_height(delta)

	# Jump.
	if Input.is_action_just_pressed("jump") \
			and on_floor and not is_crouching:
		velocity.y = jump_velocity

	# Horizontal movement.
	var input_dir := Input.get_vector(
		"move_left", "move_right",
		"move_forward", "move_back")
	var wants_sprint := Input.is_action_pressed("sprint")
	if _joy != Vector2.ZERO:
		input_dir = _joy
		wants_sprint = _joy.length() > joy_sprint
	var local_dir := Vector3(input_dir.x, 0.0, input_dir.y)
	var direction := (transform.basis * local_dir).normalized()

	is_sprinting = wants_sprint \
		and not is_crouching and input_dir.y < 0.0
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed

	var accel := air_acceleration
	if on_floor:
		accel = ground_acceleration
	var target := direction * speed
	var t := clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, t)
	velocity.z = lerpf(velocity.z, target.z, t)

	move_and_slide()

	if _touch_mode and aim_assist:
		_update_aim_assist(delta)
	_update_head_bob(delta)
	_update_fov(delta)


func _update_height(delta: float) -> void:
	var target := stand_height
	if is_crouching:
		target = crouch_height
	if is_equal_approx(_current_height, target):
		return
	var t := clampf(crouch_lerp_speed * delta, 0.0, 1.0)
	_current_height = lerpf(_current_height, target, t)
	if absf(_current_height - target) < 0.005:
		_current_height = target
	_apply_height()


func _apply_height() -> void:
	_capsule.height = _current_height
	collision.position.y = _current_height * 0.5
	head.position.y = _current_height - eye_offset


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var up := Vector3.UP
	var from := global_position + up * (_current_height - 0.05)
	var to := global_position + up * (stand_height + 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _update_head_bob(delta: float) -> void:
	var target := Vector3.ZERO
	var h_speed := Vector2(velocity.x, velocity.z).length()
	if bob_enabled and is_on_floor() and h_speed > 0.5:
		_bob_time += delta * h_speed * bob_frequency
		var amp := bob_amplitude
		if is_crouching:
			amp *= 0.6
		target = Vector3(
			cos(_bob_time * 0.5) * amp * 0.6,
			sin(_bob_time) * amp,
			0.0)
	var t := clampf(10.0 * delta, 0.0, 1.0)
	camera.position = camera.position.lerp(target, t)


func _update_fov(delta: float) -> void:
	var target := base_fov
	if is_sprinting and is_on_floor():
		target = sprint_fov
	var t := clampf(8.0 * delta, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, target, t)


# -----------------------------------------------------
# Aim assist (touch only)
# -----------------------------------------------------

## Pulls the view gently towards the enemy closest to
## the crosshair, if it is visible and in range.
func _update_aim_assist(delta: float) -> void:
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var best: Node3D = null
	var best_point := Vector3.ZERO
	var best_angle := deg_to_rad(aim_assist_angle)
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var hp: Variant = enemy.get("health")
		if hp != null and float(hp) <= 0.0:
			continue
		var point := enemy.global_position
		point.y += 1.2
		var to := point - from
		var dist := to.length()
		if dist < 1.0 or dist > aim_assist_range:
			continue
		var angle := forward.angle_to(to)
		if angle < best_angle:
			best_angle = angle
			best = enemy
			best_point = point
	if best == null:
		return

	# Needs a clear line of sight.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		from, best_point)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var body := hit["collider"] as Node
		if body != best and not best.is_ancestor_of(body):
			return

	var to_target := best_point - from
	var flat := Vector2(to_target.x, to_target.z).length()
	var yaw := atan2(-to_target.x, -to_target.z)
	var pitch := atan2(to_target.y, flat)
	var t := clampf(aim_magnetism * 20.0 * delta, 0.0, 1.0)
	rotation.y = lerp_angle(rotation.y, yaw, t)
	head.rotation.x = lerp_angle(head.rotation.x, pitch, t)


# -----------------------------------------------------
# Touch UI (built in code, no extra scene needed)
# -----------------------------------------------------

func _build_touch_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "TouchUI"
	_ui.layer = 5
	add_child(_ui)

	_joy_base = _make_panel("", Color(1, 1, 1, 0.12))
	_joy_knob = _make_panel("", Color(1, 1, 1, 0.35))
	for key in BUTTONS:
		var text: String = BUTTONS[key][0]
		_panels[key] = _make_panel(text, _color(false))
	_set_lit("assist", aim_assist)

	get_viewport().size_changed.connect(_layout)
	_layout()


func _color(lit: bool) -> Color:
	if lit:
		return Color(1.0, 0.8, 0.2, 0.55)
	return Color(0.05, 0.06, 0.08, 0.45)


func _make_panel(text: String, color: Color) -> Panel:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1, 1, 1, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	_ui.add_child(panel)
	if text != "":
		var label := Label.new()
		label.name = "Label"
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = \
			HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = \
			VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT)
		panel.add_child(label)
	return panel


func _set_lit(key: String, lit: bool) -> void:
	if not _panels.has(key):
		return
	var panel: Panel = _panels[key]
	var style: StyleBoxFlat = \
		panel.get_theme_stylebox("panel")
	style.bg_color = _color(lit)


## Places every control. Runs again when the screen
## size changes (rotation, browser bars).
func _layout() -> void:
	if _ui == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var shortest := minf(screen.x, screen.y)
	_scale = clampf(shortest / 400.0, 1.0, 4.0)
	var unit := button_size * _scale

	for key in _panels:
		var d: Array = BUTTONS[key]
		var side: float = maxf(unit * float(d[5]), 64.0)
		var corner := Vector2(
			screen.x * float(d[1]), screen.y * float(d[2]))
		var centre := corner \
			+ Vector2(float(d[3]), float(d[4])) * unit
		var panel: Panel = _panels[key]
		panel.size = Vector2(side, side)
		panel.position = centre - panel.size * 0.5
		var label: Label = panel.get_node("Label")
		label.add_theme_font_size_override(
			"font_size", int(side * 0.26))

	if _joy_id == -1:
		var radius := joy_radius * _scale
		var rest := Vector2(
			radius * 2.2, screen.y - radius * 2.2)
		_joy_origin = rest
		_update_joy_visual(rest)


func _update_joy_visual(finger: Vector2) -> void:
	var radius := joy_radius * _scale
	_joy_base.size = Vector2(radius, radius) * 2.0
	_joy_base.position = _joy_origin - _joy_base.size * 0.5
	var offset := (finger - _joy_origin).limit_length(radius)
	_joy_knob.size = Vector2(radius, radius)
	_joy_knob.position = \
		_joy_origin + offset - _joy_knob.size * 0.5
