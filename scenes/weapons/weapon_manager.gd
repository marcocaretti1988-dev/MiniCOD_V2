extends Node3D
## Holds the weapons under the player camera: switching (1 / 2), reload (R),
## aim down sights (right mouse), hitscan shooting, recoil and camera shake.
## It never touches player movement: it only reads the player state, adds a
## rotation offset to the camera and scales the player's FOV values to zoom.

const WeaponFX := preload("res://scripts/weapon_fx.gd")
const WEAPON_SCENES := [
	preload("res://scenes/weapons/rifle.tscn"),
	preload("res://scenes/weapons/pistol.tscn"),
]
const SWITCH_ACTIONS := ["weapon_1", "weapon_2"]

signal weapon_changed(weapon: Node3D)
signal shot_hit(position: Vector3, collider: Object)

@export var aim_speed: float = 9.0
@export var switch_time: float = 0.18
@export var max_shake_degrees: float = 1.6
@export var recoil_recover_speed: float = 7.0
## Only react to input while the mouse is captured (disable for automated tests).
@export var require_mouse_capture: bool = true

var weapons: Array[Node3D] = []
var current: Node3D
var current_index: int = -1
var aim_amount: float = 0.0
var is_switching: bool = false

var _base_fov: float = 75.0
var _sprint_fov: float = 82.0
var _recoil: Vector2 = Vector2.ZERO         # applied camera offset (pitch, yaw) in radians
var _recoil_target: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _bloom: float = 0.0
var _was_captured: bool = false
var _impacts: Array[Node3D] = []
var _impact_index: int = 0
var _switch_tween: Tween

@onready var camera: Camera3D = get_parent() as Camera3D
@onready var player: CharacterBody3D = owner as CharacterBody3D


func _ready() -> void:
	_base_fov = player.base_fov
	_sprint_fov = player.sprint_fov

	for scene in WEAPON_SCENES:
		var weapon: Node3D = scene.instantiate()
		add_child(weapon)
		weapon.deactivate()
		weapons.append(weapon)

	# Pool of impact effects living in world space.
	for i in 10:
		var impact := WeaponFX.make_impact()
		impact.top_level = true
		add_child(impact)
		_impacts.append(impact)

	_equip(0)


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not require_mouse_capture
	# Ignore the click that re-captures the mouse.
	var can_input := captured and (_was_captured or not require_mouse_capture)
	_was_captured = captured

	if can_input:
		_handle_input()

	_update_aim(delta, can_input)
	_update_camera_feedback(delta)


func _handle_input() -> void:
	for i in SWITCH_ACTIONS.size():
		if Input.is_action_just_pressed(SWITCH_ACTIONS[i]):
			switch_to(i)

	if current == null or is_switching:
		return

	if Input.is_action_just_pressed("reload"):
		current.start_reload()

	var wants_fire := false
	if current.automatic:
		wants_fire = Input.is_action_pressed("shoot")
	else:
		wants_fire = Input.is_action_just_pressed("shoot")

	if wants_fire:
		if current.ammo <= 0:
			if Input.is_action_just_pressed("shoot"):
				current.start_reload()
		elif current.try_fire():
			_shoot()


func _update_aim(delta: float, can_input: bool) -> void:
	var wants_aim: bool = can_input and current != null and Input.is_action_pressed("aim") \
		and not current.is_reloading and not is_switching and not player.is_sprinting
	aim_amount = move_toward(aim_amount, 1.0 if wants_aim else 0.0, aim_speed * delta)
	if current != null:
		current.aim_amount = aim_amount
		# Zoom by scaling the FOV values the player script lerps towards.
		var zoom := lerpf(1.0, current.ads_fov / _base_fov, aim_amount)
		player.base_fov = _base_fov * zoom
		player.sprint_fov = _sprint_fov * zoom


func _update_camera_feedback(delta: float) -> void:
	_recoil = _recoil.lerp(_recoil_target, clampf(28.0 * delta, 0.0, 1.0))
	_recoil_target = _recoil_target.lerp(Vector2.ZERO, clampf(recoil_recover_speed * delta, 0.0, 1.0))
	_trauma = maxf(_trauma - 2.8 * delta, 0.0)
	_bloom = maxf(_bloom - 2.5 * delta, 0.0)

	var shake := _trauma * _trauma * deg_to_rad(max_shake_degrees)
	camera.rotation = Vector3(
		_recoil.x + randf_range(-1.0, 1.0) * shake,
		_recoil.y + randf_range(-1.0, 1.0) * shake,
		randf_range(-1.0, 1.0) * shake * 0.6
	)


# ---------------------------------------------------------------------------
# Shooting
# ---------------------------------------------------------------------------

## Current bullet spread in degrees (also drives the crosshair size).
func get_spread_degrees() -> float:
	if current == null:
		return 0.0
	var spread: float = lerpf(current.hip_spread_deg, current.ads_spread_deg, aim_amount)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := clampf(speed / maxf(player.sprint_speed, 0.01), 0.0, 1.0)
	spread += current.move_spread_deg * moving * (1.0 - 0.7 * aim_amount)
	if not player.is_on_floor():
		spread += 1.5
	spread += _bloom * (1.0 - 0.6 * aim_amount)
	return spread


func _shoot() -> void:
	var spread := deg_to_rad(get_spread_degrees())
	var cam_basis := camera.global_transform.basis
	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(spread)
	var direction := (-cam_basis.z + cam_basis.x * cos(angle) * radius + cam_basis.y * sin(angle) * radius).normalized()

	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * current.max_range)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_spawn_impact(hit["position"], hit["normal"])
		var collider: Object = hit["collider"]
		if collider != null and collider.has_method("take_damage"):
			collider.take_damage(current.damage)
		shot_hit.emit(hit["position"], collider)

	# Recoil (less while aiming), shake and crosshair bloom.
	var recoil_scale := lerpf(1.0, 0.65, aim_amount)
	_recoil_target.x += deg_to_rad(current.recoil_pitch_deg) * recoil_scale
	_recoil_target.y += deg_to_rad(randf_range(-current.recoil_yaw_deg, current.recoil_yaw_deg)) * recoil_scale
	_recoil_target.x = minf(_recoil_target.x, deg_to_rad(9.0))
	_trauma = minf(_trauma + current.shake_amount, 1.0)
	_bloom = minf(_bloom + current.bloom_per_shot, 3.0)


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var impact := _impacts[_impact_index]
	_impact_index = (_impact_index + 1) % _impacts.size()
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	impact.global_transform = Transform3D(Basis(x, y, z), point + y * 0.02)
	WeaponFX.burst(impact)


# ---------------------------------------------------------------------------
# Switching
# ---------------------------------------------------------------------------

func switch_to(index: int) -> void:
	if index == current_index or index < 0 or index >= weapons.size() or is_switching:
		return
	is_switching = true
	current.cancel_reload()
	if _switch_tween != null:
		_switch_tween.kill()
	_switch_tween = create_tween()
	_switch_tween.tween_property(current, "holster_amount", 1.0, switch_time)
	_switch_tween.tween_callback(_equip.bind(index))
	_switch_tween.tween_method(_set_holster, 1.0, 0.0, switch_time)
	_switch_tween.tween_callback(func() -> void: is_switching = false)


func _set_holster(value: float) -> void:
	if current != null:
		current.holster_amount = value


func _equip(index: int) -> void:
	if current != null:
		current.deactivate()
	current_index = index
	current = weapons[index]
	current.holster_amount = 1.0 if is_switching else 0.0
	current.aim_amount = aim_amount
	current.activate()
	weapon_changed.emit(current)
