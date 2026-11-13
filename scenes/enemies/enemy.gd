extends CharacterBody3D
## Enemy soldier.
## AI: patrol 4 waypoints -> chase when the player is visible within 30 m ->
## stop at 15 m and strafe while shooting every 0.8 s (reload after 10 shots)
## -> take cover when health drops under 40.
## Health 100, headshot x3 (see head_hitbox.gd), red flash on hit,
## death = fall + fade + dust, respawn after 5 s.

const WeaponFX := preload("res://scripts/weapon_fx.gd")
const MeshMerger := preload("res://scripts/mesh_merger.gd")
const EnemyFX := preload("res://scripts/enemy_fx.gd")

enum State { PATROL, CHASE, ATTACK, COVER, DEAD }

signal died(enemy: Node3D)
signal respawned(enemy: Node3D)
signal shot_fired(enemy: Node3D, hit_player: bool)

@export var vest_color: Color = Color(0.27, 0.32, 0.2)

@export_group("Health")
@export var max_health: float = 100.0
@export var headshot_multiplier: float = 3.0
@export var cover_health: float = 40.0
@export var respawn_delay: float = 5.0

@export_group("Senses")
@export var sight_range: float = 30.0
@export var attack_range: float = 15.0
@export var forget_time: float = 8.0

@export_group("Movement")
@export var patrol_speed: float = 2.2
@export var chase_speed: float = 4.5
@export var strafe_speed: float = 2.4
@export var patrol_radius: float = 8.0
@export var turn_speed: float = 8.0

@export_group("Weapon")
@export var fire_interval: float = 0.8
@export var magazine_size: int = 10
@export var reload_time: float = 2.0
@export var shot_damage: float = 8.0
@export var shot_spread_deg: float = 3.5

var state: State = State.PATROL
var health: float = 100.0
var shots_in_magazine: int = 10
var is_reloading: bool = false
## Patrol waypoints (world space). Filled automatically around the spawn point if empty.
var patrol_points: Array[Vector3] = []

var _player: Node3D
var _player_head: Node3D
var _spawn_transform: Transform3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _can_see: bool = false
var _player_distance: float = INF
var _time_since_seen: float = INF
var _last_seen_position: Vector3 = Vector3.ZERO

var _patrol_index: int = 0
var _patrol_wait: float = 0.0
var _fire_timer: float = 0.0
var _reload_left: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_timer: float = 0.0
var _cover_position: Vector3 = Vector3.ZERO
var _has_cover: bool = false
var _cover_timer: float = 0.0
var _flash_left: float = 0.0
var _death_tween: Tween

var _materials: Array[StandardMaterial3D] = []
var _muzzle: Marker3D
var _muzzle_flash: GPUParticles3D
var _hit_sparks: Node3D
var _blood: GPUParticles3D
var _death_dust: GPUParticles3D
var _impacts: Array[Node3D] = []
var _impact_index: int = 0

@onready var body: Node3D = $Body
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var head_hitbox: StaticBody3D = $HeadHitbox
@onready var head_shape: CollisionShape3D = $HeadHitbox/CollisionShape3D


func _ready() -> void:
	add_to_group("enemies")
	_spawn_transform = global_transform
	health = max_health
	shots_in_magazine = magazine_size
	_fire_timer = randf_range(0.2, fire_interval)
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0

	_build_body()
	_build_effects()

	if patrol_points.is_empty():
		var c := _spawn_transform.origin
		for offset in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
			patrol_points.append(Vector3(
				clampf(c.x + offset.x * patrol_radius, -44.0, 44.0),
				c.y,
				clampf(c.z + offset.y * patrol_radius, -44.0, 44.0)
			))
	_patrol_index = randi() % patrol_points.size()


func _physics_process(delta: float) -> void:
	_update_flash(delta)
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_find_player()
	_update_senses(delta)
	_update_weapon(delta)

	match state:
		State.PATROL:
			_state_patrol(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.COVER:
			_state_cover(delta)

	move_and_slide()


# ---------------------------------------------------------------------------
# Senses
# ---------------------------------------------------------------------------

func _find_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_player_head = _player.get_node_or_null("Head") as Node3D if _player != null else null


func _get_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.55, 0.0)


func _get_player_target() -> Vector3:
	if _player_head != null:
		return _player_head.global_position - Vector3(0.0, 0.3, 0.0)
	return _player.global_position + Vector3(0.0, 1.2, 0.0)


func _update_senses(delta: float) -> void:
	_can_see = false
	_time_since_seen += delta
	if _player == null:
		_player_distance = INF
		return
	_player_distance = global_position.distance_to(_player.global_position)
	if _player_distance > sight_range:
		return
	var query := PhysicsRayQueryParameters3D.create(_get_eye_position(), _get_player_target(), 1)
	query.exclude = [get_rid(), head_hitbox.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] == _player:
		_can_see = true
		_time_since_seen = 0.0
		_last_seen_position = _player.global_position


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

func _state_patrol(delta: float) -> void:
	if _can_see:
		state = State.CHASE
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		_set_horizontal_velocity(Vector3.ZERO, delta)
		return
	var target := patrol_points[_patrol_index]
	if _horizontal_distance(target) < 1.2 or _move_to(target, patrol_speed, delta):
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_patrol_wait = randf_range(0.6, 1.6)


func _state_chase(delta: float) -> void:
	if health < cover_health:
		_enter_cover()
		return
	if _time_since_seen > forget_time:
		state = State.PATROL
		return
	if _can_see and _player_distance <= attack_range:
		state = State.ATTACK
		_strafe_timer = randf_range(1.0, 2.2)
		return
	_move_to(_last_seen_position, chase_speed, delta)
	if _can_see:
		_try_shoot()


func _state_attack(delta: float) -> void:
	if health < cover_health:
		_enter_cover()
		return
	if _time_since_seen > 1.0 or _player_distance > attack_range + 4.0:
		state = State.CHASE
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var forward := to_player.normalized()
	_face(forward, delta)

	# Strafe sideways, changing direction on a timer or when blocked.
	_strafe_timer -= delta
	if _strafe_timer <= 0.0 or is_on_wall():
		_strafe_sign = -_strafe_sign
		_strafe_timer = randf_range(1.0, 2.4)
	var side := Vector3(-forward.z, 0.0, forward.x) * _strafe_sign
	var move := side * strafe_speed
	# Keep roughly the engagement distance.
	if _player_distance < attack_range * 0.6:
		move -= forward * strafe_speed * 0.7
	elif _player_distance > attack_range:
		move += forward * strafe_speed * 0.7
	_set_horizontal_velocity(move, delta)

	if _can_see:
		_try_shoot()


func _state_cover(delta: float) -> void:
	_cover_timer -= delta
	if _cover_timer <= 0.0:
		_cover_timer = 1.2
		_choose_cover()

	if _has_cover and _horizontal_distance(_cover_position) > 0.9:
		_move_to(_cover_position, chase_speed, delta)
	else:
		# In cover (or no cover available): hold, face the threat, back off if exposed.
		var to_player := _last_seen_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.1:
			_face(to_player.normalized(), delta)
		if not _has_cover and _can_see and to_player.length() > 0.1:
			_set_horizontal_velocity(-to_player.normalized() * strafe_speed, delta)
		else:
			_set_horizontal_velocity(Vector3.ZERO, delta)

	if _can_see:
		_try_shoot()


func _enter_cover() -> void:
	state = State.COVER
	_cover_timer = 0.0


## Picks the closest spot hidden behind a "cover" object, on the far side from the player.
func _choose_cover() -> void:
	_has_cover = false
	if _player == null:
		return
	var threat := _player.global_position
	var best := INF
	for node in get_tree().get_nodes_in_group("cover"):
		var cover := node as Node3D
		if cover == null:
			continue
		var away := cover.global_position - threat
		away.y = 0.0
		if away.length() < 0.5:
			continue
		var radius: float = cover.get_meta("cover_radius", 1.5)
		var spot := cover.global_position + away.normalized() * (radius + 0.9)
		spot.y = global_position.y
		if absf(spot.x) > 46.0 or absf(spot.z) > 46.0:
			continue
		var cost := global_position.distance_to(spot)
		if cost < best:
			best = cost
			_cover_position = spot
			_has_cover = true


# ---------------------------------------------------------------------------
# Movement helpers
# ---------------------------------------------------------------------------

func _horizontal_distance(target: Vector3) -> float:
	return Vector2(target.x - global_position.x, target.z - global_position.z).length()


func _set_horizontal_velocity(target: Vector3, delta: float) -> void:
	var t := clampf(10.0 * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, t)
	velocity.z = lerpf(velocity.z, target.z, t)


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


## Walks towards target using the navigation mesh. Returns true when the path is finished.
func _move_to(target: Vector3, speed: float, delta: float) -> bool:
	var map := nav_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		_set_horizontal_velocity(Vector3.ZERO, delta)
		return false
	if nav_agent.target_position.distance_to(target) > 0.5:
		nav_agent.target_position = target
	var next := nav_agent.get_next_path_position()
	var finished := nav_agent.is_navigation_finished()
	var direction := next - global_position
	direction.y = 0.0
	if finished or direction.length() < 0.05:
		# No path (or already there): go straight if still far away.
		direction = target - global_position
		direction.y = 0.0
		if direction.length() < 1.0:
			_set_horizontal_velocity(Vector3.ZERO, delta)
			return true
		if finished and not nav_agent.is_target_reachable():
			_set_horizontal_velocity(Vector3.ZERO, delta)
			return true
	direction = direction.normalized()
	_set_horizontal_velocity(direction * speed, delta)
	_face(direction, delta)
	return false


# ---------------------------------------------------------------------------
# Weapon
# ---------------------------------------------------------------------------

func _update_weapon(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			is_reloading = false
			shots_in_magazine = magazine_size


func _try_shoot() -> void:
	if is_reloading or _fire_timer > 0.0 or _player == null:
		return
	_fire_timer = fire_interval
	shots_in_magazine -= 1
	if shots_in_magazine <= 0:
		is_reloading = true
		_reload_left = reload_time

	WeaponFX.burst(_muzzle_flash)

	var from := _get_eye_position()
	var aim := (_get_player_target() - from).normalized()
	var spread := deg_to_rad(shot_spread_deg)
	var right := aim.cross(Vector3.UP).normalized()
	var up := right.cross(aim).normalized()
	var angle := randf() * TAU
	var radius := sqrt(randf()) * tan(spread)
	var direction := (aim + right * cos(angle) * radius + up * sin(angle) * radius).normalized()

	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 120.0, 1)
	query.exclude = [get_rid(), head_hitbox.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_player := false
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		hit_player = collider == _player
		_spawn_impact(hit["position"], hit["normal"])
		if collider is Node and not (collider as Node).is_in_group("enemies") and collider.has_method("take_damage"):
			collider.take_damage(shot_damage)
	shot_fired.emit(self, hit_player)


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var impact := _impacts[_impact_index]
	_impact_index = (_impact_index + 1) % _impacts.size()
	_place_along_normal(impact, point, normal)
	WeaponFX.burst(impact)


func _place_along_normal(node: Node3D, point: Vector3, normal: Vector3) -> void:
	var y := normal.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), point + y * 0.02)


# ---------------------------------------------------------------------------
# Damage, death, respawn
# ---------------------------------------------------------------------------

## Called by the player's bullets (body) and by head_hitbox.gd (headshot, already multiplied).
func take_damage(amount: float, is_headshot: bool = false) -> void:
	if state == State.DEAD:
		return
	health -= amount

	# Red flash + sparks where the bullet landed.
	_flash_left = 0.12
	for mat in _materials:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.08, 0.05)
		mat.emission_energy_multiplier = 2.0
	var height := 1.63 if is_headshot else 1.15
	var forward := -global_transform.basis.z
	var hit_point := global_position + Vector3(0.0, height, 0.0) + forward * 0.2
	_place_along_normal(_hit_sparks, hit_point, forward)
	WeaponFX.burst(_hit_sparks)
	# Dark red puff (no gore), pushed out towards the shooter.
	_blood.global_transform = Transform3D(global_transform.basis, hit_point)
	WeaponFX.burst(_blood)

	# Being shot reveals where the player is.
	if _player != null:
		_last_seen_position = _player.global_position
		_time_since_seen = 0.0
	if state == State.PATROL:
		state = State.CHASE

	if health <= 0.0:
		_die()


func _update_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		for mat in _materials:
			mat.emission_enabled = false


func _die() -> void:
	state = State.DEAD
	health = 0.0
	velocity = Vector3.ZERO
	is_reloading = false
	collision.set_deferred("disabled", true)
	head_shape.set_deferred("disabled", true)

	_death_dust.global_position = global_position + Vector3(0.0, 0.1, 0.0)
	WeaponFX.burst(_death_dust)
	died.emit(self)

	if _death_tween != null:
		_death_tween.kill()
	_death_tween = create_tween()
	# Fall backwards...
	_death_tween.tween_property(body, "rotation:x", PI * 0.5, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.parallel().tween_property(body, "position:y", 0.14, 0.55)
	# ...lie there, then fade out.
	_death_tween.tween_interval(1.2)
	_death_tween.tween_callback(_set_fade_enabled.bind(true))
	_death_tween.tween_method(_set_alpha, 1.0, 0.0, 1.5)
	_death_tween.tween_callback(func() -> void: body.visible = false)
	# Respawn respawn_delay seconds after dying.
	_death_tween.tween_interval(maxf(respawn_delay - 3.25, 0.05))
	_death_tween.tween_callback(_respawn)


func _set_fade_enabled(enabled: bool) -> void:
	for mat in _materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if enabled else BaseMaterial3D.TRANSPARENCY_DISABLED


func _set_alpha(alpha: float) -> void:
	for mat in _materials:
		mat.albedo_color.a = alpha


func _respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	shots_in_magazine = magazine_size
	is_reloading = false
	_fire_timer = fire_interval
	_time_since_seen = INF
	_can_see = false
	_has_cover = false
	_patrol_wait = 0.0
	_flash_left = 0.0
	for mat in _materials:
		mat.emission_enabled = false
	_set_alpha(1.0)
	_set_fade_enabled(false)
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	body.visible = true
	collision.set_deferred("disabled", false)
	head_shape.set_deferred("disabled", false)
	state = State.PATROL
	respawned.emit(self)


# ---------------------------------------------------------------------------
# Soldier body (boxes and capsules with StandardMaterial3D)
# ---------------------------------------------------------------------------

func _make_material(tint: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := WeaponFX.make_grip_material(tint)  # textured base, not a flat colour
	mat.roughness = roughness
	mat.metallic = metallic
	_materials.append(mat)
	return mat


func _make_camo(tint: Color) -> StandardMaterial3D:
	var mat := _make_material(tint, 0.85)
	mat.albedo_texture = EnemyFX.get_camo_texture()
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(2.2, 2.2, 2.2)
	return mat


func _build_body() -> void:
	# Camouflage uniform in a colour derived from the vest, so squads stay readable.
	var camo_tint := vest_color.lerp(Color(0.45, 0.44, 0.34), 0.55).lightened(0.35)
	var camo := _make_camo(camo_tint)
	var vest := _make_material(vest_color, 0.9)
	var helmet := _make_camo(vest_color.lerp(Color(0.35, 0.36, 0.28), 0.5).lightened(0.15))
	helmet.roughness = 0.5
	helmet.metallic = 0.3
	var skin := _make_material(Color(0.78, 0.6, 0.48), 0.7)
	var boots := _make_material(Color(0.07, 0.06, 0.06), 0.8)
	var gloves := _make_material(Color(0.09, 0.09, 0.08), 0.9)
	var strap := _make_material(Color(0.13, 0.12, 0.1), 0.9)
	var face_dark := _make_material(Color(0.1, 0.07, 0.06), 0.7)
	var gun_metal := WeaponFX.make_gun_metal(Color(0.1, 0.105, 0.115))
	_materials.append(gun_metal)
	var gun_polymer := WeaponFX.make_polymer()
	_materials.append(gun_polymer)
	# Reflective visor / goggles.
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.08, 0.12, 0.16)
	visor.metallic = 1.0
	visor.roughness = 0.08
	visor.metallic_specular = 1.0
	_materials.append(visor)

	# --- Legs, knee pads, boots ---
	for side in [-1.0, 1.0]:
		_add_capsule(0.095, 0.48, Vector3(0.11 * side, 0.66, 0.0), camo)                    # thigh
		_add_capsule(0.08, 0.46, Vector3(0.11 * side, 0.3, 0.01), camo)                     # shin
		_add_box(Vector3(0.13, 0.11, 0.06), Vector3(0.11 * side, 0.47, -0.075), strap)      # knee pad
		_add_box(Vector3(0.13, 0.16, 0.2), Vector3(0.11 * side, 0.1, -0.01), boots)         # boot shaft
		_add_box(Vector3(0.13, 0.08, 0.14), Vector3(0.11 * side, 0.06, -0.15), boots)       # boot toe
		_add_box(Vector3(0.14, 0.03, 0.31), Vector3(0.11 * side, 0.015, -0.06), strap)      # sole
		_add_box(Vector3(0.1, 0.12, 0.05), Vector3(0.2 * side, 0.74, 0.0), vest)            # thigh pouch

	# --- Torso: uniform, belt, vest with pouches and straps ---
	_add_box(Vector3(0.38, 0.2, 0.22), Vector3(0.0, 0.9, 0.0), camo)                        # hips
	_add_box(Vector3(0.4, 0.05, 0.24), Vector3(0.0, 0.99, 0.0), strap)                      # belt
	_add_box(Vector3(0.4, 0.5, 0.23), Vector3(0.0, 1.22, 0.0), camo)                        # chest (uniform)
	_add_box(Vector3(0.44, 0.4, 0.29), Vector3(0.0, 1.2, 0.0), vest)                        # plate carrier
	for x in [-0.14, 0.0, 0.14]:
		_add_box(Vector3(0.11, 0.15, 0.06), Vector3(x, 1.1, -0.17), vest)                   # magazine pouches
		_add_box(Vector3(0.112, 0.03, 0.065), Vector3(x, 1.165, -0.172), strap)             # pouch flaps
	_add_box(Vector3(0.12, 0.09, 0.05), Vector3(-0.13, 1.3, -0.165), vest)                  # admin pouch
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.07, 0.1, 0.3), Vector3(0.13 * side, 1.43, 0.0), vest)            # shoulder straps
		_add_capsule(0.085, 0.2, Vector3(0.27 * side, 1.42, 0.0), camo, Vector3(0, 0, 90))  # shoulders
	_add_box(Vector3(0.2, 0.06, 0.22), Vector3(0.0, 1.47, 0.02), camo)                      # collar

	# --- Backpack, bedroll, radio with antenna ---
	_add_box(Vector3(0.32, 0.36, 0.14), Vector3(0.0, 1.22, 0.2), camo)
	_add_capsule(0.06, 0.34, Vector3(0.0, 1.44, 0.2), strap, Vector3(0, 0, 90))             # bedroll
	_add_box(Vector3(0.09, 0.16, 0.06), Vector3(0.13, 1.36, 0.25), boots)                   # radio
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.004
	antenna.bottom_radius = 0.007
	antenna.height = 0.55
	antenna.radial_segments = 6
	_add_part(antenna, Vector3(0.15, 1.7, 0.25), boots, Vector3(0, 0, -6))

	# --- Arms holding the rifle, gloves ---
	_add_capsule(0.065, 0.36, Vector3(0.28, 1.27, -0.07), camo, Vector3(-38, 0, 8))         # right upper arm
	_add_capsule(0.055, 0.38, Vector3(0.2, 1.13, -0.3), camo, Vector3(-80, -25, 0))         # right forearm
	_add_capsule(0.065, 0.36, Vector3(-0.28, 1.27, -0.09), camo, Vector3(-46, 0, -8))       # left upper arm
	_add_capsule(0.055, 0.42, Vector3(-0.17, 1.14, -0.36), camo, Vector3(-85, 35, 0))       # left forearm
	_add_box(Vector3(0.075, 0.06, 0.1), Vector3(0.09, 1.1, -0.44), gloves)                  # right hand
	_add_box(Vector3(0.075, 0.06, 0.11), Vector3(-0.02, 1.12, -0.6), gloves)                # left hand

	# --- Head with a simple face ---
	_add_capsule(0.058, 0.16, Vector3(0.0, 1.53, 0.0), skin)                                # neck
	_add_capsule(0.112, 0.27, Vector3(0.0, 1.65, 0.0), skin)                                # head
	_add_box(Vector3(0.026, 0.045, 0.03), Vector3(0.0, 1.635, -0.118), skin)                # nose
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.03, 0.014, 0.012), Vector3(0.042 * side, 1.672, -0.105), face_dark)   # eyes
		_add_box(Vector3(0.042, 0.01, 0.012), Vector3(0.042 * side, 1.692, -0.104), face_dark)   # eyebrows
		_add_box(Vector3(0.02, 0.05, 0.03), Vector3(0.112 * side, 1.65, 0.0), skin)              # ears
	_add_box(Vector3(0.05, 0.008, 0.012), Vector3(0.0, 1.59, -0.103), face_dark)            # mouth
	_add_box(Vector3(0.07, 0.03, 0.02), Vector3(0.0, 1.56, -0.095), skin)                   # chin

	# --- Helmet with goggles (reflective visor) and chin strap ---
	var dome := SphereMesh.new()
	dome.radius = 0.15
	dome.height = 0.21
	dome.radial_segments = 14
	dome.rings = 7
	_add_part(dome, Vector3(0.0, 1.76, 0.01), helmet, Vector3.ZERO)
	_add_box(Vector3(0.28, 0.07, 0.3), Vector3(0.0, 1.735, 0.012), helmet)                  # helmet rim
	_add_box(Vector3(0.21, 0.055, 0.03), Vector3(0.0, 1.765, -0.148), visor)                # goggles
	_add_box(Vector3(0.24, 0.02, 0.035), Vector3(0.0, 1.765, -0.14), strap)                 # goggle strap
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.012, 0.15, 0.02), Vector3(0.118 * side, 1.64, -0.03), strap)     # chin strap

	# --- Rifle (metal + polymer) ---
	_add_box(Vector3(0.045, 0.07, 0.3), Vector3(0.06, 1.165, -0.36), gun_metal)             # receiver
	_add_box(Vector3(0.048, 0.055, 0.22), Vector3(0.06, 1.165, -0.6), gun_polymer)          # handguard
	_add_box(Vector3(0.04, 0.065, 0.2), Vector3(0.06, 1.15, -0.1), gun_polymer)             # stock
	_add_box(Vector3(0.03, 0.15, 0.05), Vector3(0.06, 1.06, -0.4), gun_metal, Vector3(-12, 0, 0))  # magazine
	_add_box(Vector3(0.03, 0.08, 0.04), Vector3(0.06, 1.1, -0.27), gun_polymer, Vector3(15, 0, 0))  # grip
	_add_box(Vector3(0.03, 0.04, 0.06), Vector3(0.06, 1.22, -0.36), gun_metal)              # optic
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.012
	barrel.bottom_radius = 0.012
	barrel.height = 0.26
	barrel.radial_segments = 10
	_add_part(barrel, Vector3(0.06, 1.175, -0.82), gun_metal, Vector3(90, 0, 0))
	var brake := CylinderMesh.new()
	brake.top_radius = 0.018
	brake.bottom_radius = 0.018
	brake.height = 0.07
	brake.radial_segments = 10
	_add_part(brake, Vector3(0.06, 1.175, -0.96), gun_metal, Vector3(90, 0, 0))

	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.06, 1.175, -1.01)
	body.add_child(_muzzle)

	# The soldier moves as one piece: join its parts into
	# one mesh per material (about 43 draw calls -> 12).
	MeshMerger.merge_tree(body, 0.0, true)


func _build_effects() -> void:
	_muzzle_flash = WeaponFX.make_muzzle_flash(0.22)
	_muzzle.add_child(_muzzle_flash)

	# World-space effects (kept as children so they are freed with the enemy).
	_hit_sparks = WeaponFX.make_impact()
	_hit_sparks.name = "HitSparks"
	_hit_sparks.top_level = true
	add_child(_hit_sparks)

	_blood = EnemyFX.make_blood_puff()
	_blood.top_level = true
	add_child(_blood)

	_death_dust = EnemyFX.make_death_dust()
	_death_dust.top_level = true
	add_child(_death_dust)

	for i in 3:
		var impact := WeaponFX.make_impact()
		impact.name = "ShotImpact%d" % i
		impact.top_level = true
		add_child(impact)
		_impacts.append(impact)


func _add_box(size: Vector3, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_part(mesh, pos, material, rot_deg)


func _add_capsule(radius: float, height: float, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	return _add_part(mesh, pos, material, rot_deg)


func _add_part(mesh: Mesh, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation_degrees = rot_deg
	body.add_child(part)
	return part
