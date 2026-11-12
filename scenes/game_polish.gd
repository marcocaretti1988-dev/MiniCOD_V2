extends Node
## Final polish layer. It does not change any gameplay code: it only listens to
## the signals the player, weapons, enemies, beacons and game manager already
## emit, and adds sound, extra particles, camera shake, weapon sway and bob,
## landing dip, depth of field when aiming and the pause menu.

const PolishFX := preload("res://scripts/polish_fx.gd")
const PAUSE_MENU := preload("res://scenes/ui/pause_menu.tscn")

@export var walk_stride: float = 2.1
@export var sprint_stride: float = 2.7
@export var crouch_stride: float = 1.5

var _player: CharacterBody3D
var _weapons: Node3D
var _step_distance: float = 0.0
var _was_on_floor: bool = true
var _air_time: float = 0.0
var _dust: GPUParticles3D
var _smokes: Array[GPUParticles3D] = []
var _smoke_index: int = 0
var _ready_done: bool = false
var _game: Node
var _camera: Camera3D
var _mouse_delta: Vector2 = Vector2.ZERO
var _sway: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0
var _dip: float = 0.0
var _dip_velocity: float = 0.0
var _dof: CameraAttributesPractical
var _debris: Dictionary = {}       # kind -> Array of emitters
var _debris_index: Dictionary = {}
var _step_puffs: Array[GPUParticles3D] = []
var _step_index: int = 0


func _ready() -> void:
	# The map and the game manager finish their own setup first.
	_setup.call_deferred()


func _setup() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		return
	_weapons = _player.get_node_or_null("Head/Camera3D/WeaponHolder") as Node3D

	if _weapons != null:
		_weapons.shot_hit.connect(_on_shot_hit)
		_weapons.weapon_changed.connect(_on_weapon_changed)
		for weapon in _weapons.weapons:
			weapon.fired.connect(_on_weapon_fired.bind(weapon))
			weapon.reload_started.connect(_on_reload_started.bind(weapon))
			weapon.reload_finished.connect(_on_reload_finished)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.died.connect(_on_enemy_died)
		enemy.shot_fired.connect(_on_enemy_shot)

	for beacon in get_tree().get_nodes_in_group("beacons"):
		beacon.activated.connect(_on_beacon_activated)

	var game := get_parent().get_node_or_null("GameManager")
	_game = game
	_camera = _player.get_node_or_null("Head/Camera3D") as Camera3D
	if game != null:
		game.game_ended.connect(_on_game_ended)
		if game.has_signal("player_damaged"):
			game.player_damaged.connect(_on_player_damaged)

	# Surface-specific impact debris and footstep puffs.
	for kind in ["concrete", "wood", "metal"]:
		_debris[kind] = []
		_debris_index[kind] = 0
		for i in 4:
			var emitter := PolishFX.make_debris(kind)
			add_child(emitter)
			_debris[kind].append(emitter)
	for i in 3:
		var puff := PolishFX.make_step_puff()
		add_child(puff)
		_step_puffs.append(puff)

	# Ground plane for bouncing shell casings (used by the Forward+ renderer).
	var floor_collision := GPUParticlesCollisionBox3D.new()
	floor_collision.size = Vector3(200.0, 2.0, 200.0)
	floor_collision.position = Vector3(0.0, -1.0, 0.0)
	add_child(floor_collision)

	# Depth of field while aiming (Forward+ / Mobile renderers only).
	var settings := get_node_or_null("/root/GameSettings")
	if _camera != null and settings != null and settings.get_current_renderer() != "gl_compatibility" and settings.quality != "low":
		_dof = CameraAttributesPractical.new()
		_dof.dof_blur_far_enabled = false
		_dof.dof_blur_far_distance = 40.0
		_dof.dof_blur_far_transition = 25.0
		_dof.dof_blur_amount = 0.07
		_camera.attributes = _dof
	if settings != null and settings.post != null:
		settings.post.reset()

	# Extra particles.
	_dust = PolishFX.make_run_dust()
	add_child(_dust)
	for i in 2:
		var smoke := PolishFX.make_reload_smoke()
		add_child(smoke)
		_smokes.append(smoke)

	add_child(PAUSE_MENU.instantiate())
	_ready_done = true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += (event as InputEventMouseMotion).relative


## Camera and viewmodel feel: weapon sway and bob, landing dip, DOF when aiming,
## low-health desaturation. Only offsets the weapon holder and camera extras;
## the player and weapon scripts keep doing their own work.
func _process(delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player) or _weapons == null:
		return
	var aim: float = _weapons.aim_amount
	var loose := 1.0 - 0.85 * aim  # everything calms down while aiming
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()

	# Sway: the weapon lags slightly behind the mouse.
	var target := Vector2(clampf(-_mouse_delta.x * 0.0009, -0.045, 0.045), clampf(_mouse_delta.y * 0.0009, -0.035, 0.035)) * loose
	_mouse_delta = Vector2.ZERO
	_sway = _sway.lerp(target, clampf(9.0 * delta, 0.0, 1.0))

	# Bob: small figure-of-eight in step with walking.
	var bob := Vector2.ZERO
	if _player.is_on_floor() and speed > 0.5:
		_bob_time += delta * speed * 1.9
		var amount := (0.0045 + 0.0006 * speed) * loose
		bob = Vector2(cos(_bob_time * 0.5) * amount, -absf(sin(_bob_time * 0.5)) * amount * 1.2)

	_weapons.position = _weapons.position.lerp(Vector3(bob.x + _sway.x * 0.35, bob.y - _sway.y * 0.25 + _dip * 0.5, 0.0), clampf(14.0 * delta, 0.0, 1.0))
	_weapons.rotation = Vector3(_sway.y * 0.9, _sway.x * 1.1, _sway.x * 0.8)

	# Landing dip: a damped spring on the camera's vertical offset.
	_dip_velocity += (-_dip * 90.0 - _dip_velocity * 14.0) * delta
	_dip += _dip_velocity * delta
	if _camera != null:
		_camera.v_offset = _dip

	# Depth of field: blur the distance while aiming.
	if _dof != null:
		_dof.dof_blur_far_enabled = aim > 0.02
		_dof.dof_blur_far_distance = lerpf(70.0, 28.0, aim)
		_dof.dof_blur_amount = 0.05 * aim

	# Low health drains the colour from the picture.
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.post != null and _game != null:
		settings.post.set_health_ratio(_game.health / maxf(_game.max_health, 1.0))


## Public: shake the camera (explosions, heavy impacts). amount 0..1.
func shake(amount: float) -> void:
	_add_shake(amount)


func _physics_process(delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player):
		return
	var on_floor := _player.is_on_floor()
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()

	# Landing thump + a little camera shake.
	if on_floor and not _was_on_floor and _air_time > 0.25:
		_sfx(&"land", -4.0, 1.0, 0.08)
		_add_shake(0.22)
		_dip_velocity = -clampf(0.5 + _air_time * 1.2, 0.5, 1.4)
		_step_distance = 0.0
		_emit_step_puff()
	_air_time = 0.0 if on_floor else _air_time + delta
	_was_on_floor = on_floor

	# Footsteps: one every stride of distance covered.
	if on_floor and speed > 1.0:
		_step_distance += speed * delta
		var stride := walk_stride
		var volume := -9.0
		if _player.is_crouching:
			stride = crouch_stride
			volume = -17.0
		elif _player.is_sprinting:
			stride = sprint_stride
			volume = -6.0
		if _step_distance >= stride:
			_step_distance = 0.0
			_sfx(&"footstep", volume, 1.0, 0.12)
			if not _player.is_crouching:
				_emit_step_puff()
	else:
		_step_distance = minf(_step_distance, walk_stride * 0.5)

	# Dust while sprinting.
	var sprinting: bool = on_floor and _player.is_sprinting and speed > 7.0
	_dust.emitting = sprinting
	if sprinting:
		var forward := -_player.global_transform.basis.z
		_dust.global_position = _player.global_position + Vector3(0.0, 0.06, 0.0) - forward * 0.25


func _emit_step_puff() -> void:
	var puff := _step_puffs[_step_index]
	_step_index = (_step_index + 1) % _step_puffs.size()
	puff.global_position = _player.global_position + Vector3(0.0, 0.05, 0.0)
	puff.restart()
	puff.emitting = true


## What a bullet hit, judged from the collider: "wood", "metal", "concrete" or "" (enemy / unknown).
func _surface_kind(collider: Object) -> String:
	var node := collider as Node
	if node == null:
		return ""
	if node.is_in_group("enemies") or (node.get_parent() != null and node.get_parent().is_in_group("enemies")):
		return ""
	var node_name := String(node.name)
	if node_name.begins_with("Crate") or node_name.begins_with("Shelf"):
		return "wood"
	if node_name.begins_with("Ground") or node_name.begins_with("Wall") or node_name.begins_with("Sandbags"):
		return "concrete"
	return "metal"  # containers, barrels, cranes, warehouse sheets


## Adds to the weapon manager's existing camera shake.
func _add_shake(amount: float) -> void:
	if _weapons != null and "_trauma" in _weapons:
		_weapons._trauma = minf(_weapons._trauma + amount, 1.0)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_weapon_fired(weapon: Node3D) -> void:
	if weapon.automatic:
		_sfx(&"gunshot_rifle", -2.0, 1.0, 0.05)
	else:
		_sfx(&"gunshot_pistol", -3.0, 1.0, 0.05)


func _on_reload_started(_duration: float, weapon: Node3D) -> void:
	_sfx(&"reload_out", -3.0, 1.0, 0.04)
	var smoke := _smokes[_smoke_index]
	_smoke_index = (_smoke_index + 1) % _smokes.size()
	var anchor: Node3D = weapon.eject if weapon.eject != null else weapon
	smoke.global_position = anchor.global_position
	smoke.restart()
	smoke.emitting = true


func _on_reload_finished() -> void:
	_sfx(&"reload_in", -3.0, 1.0, 0.04)


func _on_weapon_changed(_weapon: Node3D) -> void:
	if _ready_done:
		_sfx(&"weapon_switch", -6.0)


func _on_shot_hit(hit_position: Vector3, collider: Object) -> void:
	if not collider is Node:
		return
	# Debris that matches the surface: chips, splinters or ricochet sparks.
	var kind := _surface_kind(collider)
	if kind != "":
		var pool: Array = _debris[kind]
		var emitter: GPUParticles3D = pool[_debris_index[kind]]
		_debris_index[kind] = (_debris_index[kind] + 1) % pool.size()
		# Throw the debris back towards the shooter and upwards.
		var back := (_player.global_position + Vector3(0, 1.4, 0) - hit_position).normalized()
		var up := (back + Vector3.UP * 0.8).normalized()
		var side := up.cross(Vector3.FORWARD)
		if side.length() < 0.01:
			side = up.cross(Vector3.RIGHT)
		side = side.normalized()
		emitter.global_transform = Transform3D(Basis(side, up, side.cross(up).normalized()), hit_position + back * 0.03)
		emitter.restart()
		emitter.emitting = true
		if kind == "metal" and randf() < 0.35:
			_sfx(&"ricochet", -12.0, 1.0, 0.25)
	var node := collider as Node
	if node.is_in_group("enemies"):
		_sfx(&"hit", -5.0, 1.0, 0.06)
	elif node.get_parent() != null and node.get_parent().is_in_group("enemies"):
		_sfx(&"headshot", -3.0)


func _on_enemy_died(_enemy: Node3D) -> void:
	_sfx(&"death", -4.0, 1.0, 0.08)


func _on_enemy_shot(enemy: Node3D, _hit_player: bool) -> void:
	var distance := enemy.global_position.distance_to(_player.global_position)
	_sfx(&"gunshot_enemy", lerpf(-7.0, -24.0, clampf(distance / 50.0, 0.0, 1.0)), 1.0, 0.08)


func _on_player_damaged(_amount: float, _from: Vector3) -> void:
	_sfx(&"hurt", -3.0, 1.0, 0.1)
	_add_shake(0.45)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.post != null:
		settings.post.flash_hit(1.0)


func _on_beacon_activated(_beacon: Node3D) -> void:
	_sfx(&"beacon", -2.0)
	_add_shake(0.5)


func _on_game_ended(won: bool) -> void:
	_dust.emitting = false
	_sfx(&"victory" if won else &"defeat", 0.0)


# The autoloads are reached through their node path, so this script also
# compiles and runs when it is checked or opened on its own.
func _sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0, pitch_random: float = 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play(sound, volume_db, pitch, pitch_random)
