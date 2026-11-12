extends CharacterBody3D
## First person player: mouse look, WASD, sprint, crouch, jump, gravity, head bob.

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
@export var eye_offset: float = 0.2  # eyes this far below the top of the capsule
@export var crouch_lerp_speed: float = 10.0

@export_group("Head Bob")
@export var bob_enabled: bool = true
@export var bob_frequency: float = 1.9
@export var bob_amplitude: float = 0.055

@export_group("Camera")
@export var base_fov: float = 75.0
@export var sprint_fov: float = 82.0

var is_crouching: bool = false
var is_sprinting: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_height: float = 1.8
var _bob_time: float = 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = collision.shape.duplicate()


func _ready() -> void:
	collision.shape = _capsule
	_current_height = stand_height
	_apply_height()
	camera.fov = base_fov
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-max_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)

	# Esc frees the mouse (real pause menu comes later); click to capture again.
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Gravity.
	if not on_floor:
		velocity.y -= _gravity * gravity_multiplier * delta

	# Crouch (hold). Stay crouched if there is no room to stand up.
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	_update_height(delta)

	# Jump.
	if Input.is_action_just_pressed("jump") and on_floor and not is_crouching:
		velocity.y = jump_velocity

	# Horizontal movement.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and input_dir.y < 0.0
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed

	var accel := ground_acceleration if on_floor else air_acceleration
	var target := direction * speed
	velocity.x = lerpf(velocity.x, target.x, clampf(accel * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target.z, clampf(accel * delta, 0.0, 1.0))

	move_and_slide()

	_update_head_bob(delta)
	_update_fov(delta)


func _update_height(delta: float) -> void:
	var target := crouch_height if is_crouching else stand_height
	if is_equal_approx(_current_height, target):
		return
	_current_height = lerpf(_current_height, target, clampf(crouch_lerp_speed * delta, 0.0, 1.0))
	if absf(_current_height - target) < 0.005:
		_current_height = target
	_apply_height()


func _apply_height() -> void:
	_capsule.height = _current_height
	collision.position.y = _current_height * 0.5
	head.position.y = _current_height - eye_offset


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * (_current_height - 0.05)
	var to := global_position + Vector3.UP * (stand_height + 0.05)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _update_head_bob(delta: float) -> void:
	var target := Vector3.ZERO
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if bob_enabled and is_on_floor() and horizontal_speed > 0.5:
		_bob_time += delta * horizontal_speed * bob_frequency
		var amplitude := bob_amplitude * (0.6 if is_crouching else 1.0)
		target = Vector3(cos(_bob_time * 0.5) * amplitude * 0.6, sin(_bob_time) * amplitude, 0.0)
	camera.position = camera.position.lerp(target, clampf(10.0 * delta, 0.0, 1.0))


func _update_fov(delta: float) -> void:
	var target := sprint_fov if is_sprinting and is_on_floor() else base_fov
	camera.fov = lerpf(camera.fov, target, clampf(8.0 * delta, 0.0, 1.0))
