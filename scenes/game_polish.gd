extends Node
## Final polish layer. It does not change any gameplay code: it only listens to
## the signals the player, weapons, enemies, beacons and game manager already
## emit, and adds sound, extra particles, extra camera shake and the pause menu.

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
	if game != null:
		game.game_ended.connect(_on_game_ended)
		if game.has_signal("player_damaged"):
			game.player_damaged.connect(_on_player_damaged)

	# Extra particles.
	_dust = PolishFX.make_run_dust()
	add_child(_dust)
	for i in 2:
		var smoke := PolishFX.make_reload_smoke()
		add_child(smoke)
		_smokes.append(smoke)

	add_child(PAUSE_MENU.instantiate())
	_ready_done = true


func _physics_process(delta: float) -> void:
	if not _ready_done or not is_instance_valid(_player):
		return
	var on_floor := _player.is_on_floor()
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()

	# Landing thump + a little camera shake.
	if on_floor and not _was_on_floor and _air_time > 0.25:
		_sfx(&"land", -4.0, 1.0, 0.08)
		_add_shake(0.22)
		_step_distance = 0.0
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
	else:
		_step_distance = minf(_step_distance, walk_stride * 0.5)

	# Dust while sprinting.
	var sprinting: bool = on_floor and _player.is_sprinting and speed > 7.0
	_dust.emitting = sprinting
	if sprinting:
		var forward := -_player.global_transform.basis.z
		_dust.global_position = _player.global_position + Vector3(0.0, 0.06, 0.0) - forward * 0.25


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


func _on_shot_hit(_position: Vector3, collider: Object) -> void:
	if not collider is Node:
		return
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


func _on_beacon_activated(_beacon: Node3D) -> void:
	_sfx(&"beacon", -2.0)


func _on_game_ended(won: bool) -> void:
	_dust.emitting = false
	_sfx(&"victory" if won else &"defeat", 0.0)


# The autoloads are reached through their node path, so this script also
# compiles and runs when it is checked or opened on its own.
func _sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0, pitch_random: float = 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play(sound, volume_db, pitch, pitch_random)
