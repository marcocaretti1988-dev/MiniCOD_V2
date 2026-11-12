extends Node
## Game mode: get 10 kills to win; lose if health reaches 0 or the 5:00 timer
## ends. Three beacons give +250 points each.
##
## The player, weapons and enemies are not modified: this node listens to the
## signals they already emit (enemy died / shot_fired, weapon shot_hit) and
## keeps the player's health itself.

const BEACON_SCRIPT := preload("res://scenes/beacon.gd")

signal game_ended(won: bool)
signal player_damaged(amount: float, from_position: Vector3)

@export_group("Rules")
@export var kills_to_win: int = 10
@export var match_time: float = 300.0
@export var max_health: float = 100.0

@export_group("Score")
@export var points_per_kill: int = 100
@export var headshot_bonus: int = 50
@export var points_per_beacon: int = 250

@export_group("Health regeneration")
## Seconds without taking damage before health starts to come back (0 = never).
@export var regen_delay: float = 6.0
@export var regen_per_second: float = 8.0

@export_group("Map")
@export var world_size: float = 80.0
@export var beacon_positions: Array[Vector3] = [
	Vector3(-24.0, 0.0, -21.0),
	Vector3(28.0, 0.0, -12.0),
	Vector3(-30.0, 0.0, 21.0),
]

var health: float = 100.0
var score: int = 0
var kills: int = 0
var time_left: float = 300.0
var beacons_active: int = 0
var is_game_over: bool = false
var beacons: Array = []

var _player: Node3D
var _hud: CanvasLayer
var _since_damage: float = 0.0
var _last_hit_headshot: Dictionary = {}  # enemy instance id -> bool
var _ready_done: bool = false


func _ready() -> void:
	health = max_health
	time_left = match_time
	# The map spawns the player group and the enemies in its own _ready, which
	# runs after this one: finish the setup once the whole scene is ready.
	_setup.call_deferred()


func _setup() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		push_warning("GameManager: no node in group 'player'.")
		return
	_hud = _player.get_node_or_null("HUD") as CanvasLayer

	var weapons := _player.get_node_or_null("Head/Camera3D/WeaponHolder")
	if weapons != null and weapons.has_signal("shot_hit"):
		weapons.shot_hit.connect(_on_shot_hit)

	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.died.connect(_on_enemy_died)
		enemy.shot_fired.connect(_on_enemy_shot)

	_spawn_beacons()

	if _hud != null:
		_hud.play_again_pressed.connect(_on_play_again)
		_hud.minimap.setup(get_parent(), _player, beacons, world_size)
		_refresh_hud()
		_hud.show_message("ELIMINATE %d ENEMIES" % kills_to_win, 3.5, Color.WHITE)
	_ready_done = true


func _spawn_beacons() -> void:
	var holder := Node3D.new()
	holder.name = "Beacons"
	get_parent().add_child(holder)
	for i in beacon_positions.size():
		var beacon := Node3D.new()
		beacon.set_script(BEACON_SCRIPT)
		beacon.name = "Beacon%d" % (i + 1)
		beacon.position = beacon_positions[i]
		holder.add_child(beacon)
		beacon.progress_changed.connect(_on_beacon_progress)
		beacon.activated.connect(_on_beacon_activated)
		beacons.append(beacon)


func _process(delta: float) -> void:
	if not _ready_done or is_game_over:
		return

	time_left -= delta
	if _hud != null:
		_hud.set_time(time_left)
	if time_left <= 0.0:
		_end_game(false, "TIME'S UP")
		return

	# Health comes back slowly when you stay out of fire.
	_since_damage += delta
	if regen_delay > 0.0 and _since_damage >= regen_delay and health < max_health:
		health = minf(health + regen_per_second * delta, max_health)
		if _hud != null:
			_hud.set_health(health, max_health)


func _refresh_hud() -> void:
	if _hud == null:
		return
	_hud.set_health(health, max_health)
	_hud.set_time(time_left)
	_hud.set_score(score)
	_hud.set_kills(kills, kills_to_win)
	_hud.set_beacons(beacons_active, beacons.size())


# ---------------------------------------------------------------------------
# Player damage
# ---------------------------------------------------------------------------

func damage_player(amount: float, from_position: Vector3) -> void:
	if is_game_over:
		return
	health = maxf(health - amount, 0.0)
	_since_damage = 0.0
	player_damaged.emit(amount, from_position)
	if _hud != null:
		_hud.set_health(health, max_health)
		_hud.show_damage(from_position)
	if health <= 0.0:
		_end_game(false, "YOU WERE KILLED")


func _on_enemy_shot(enemy: Node3D, hit_player: bool) -> void:
	if hit_player:
		damage_player(enemy.shot_damage, enemy.global_position)


# ---------------------------------------------------------------------------
# Kills and score
# ---------------------------------------------------------------------------

func _find_enemy(collider: Object) -> Dictionary:
	if collider is Node:
		var node := collider as Node
		if node.is_in_group("enemies"):
			return {"enemy": node, "headshot": false}
		var parent := node.get_parent()
		if parent != null and parent.is_in_group("enemies"):
			return {"enemy": parent, "headshot": true}
	return {}


func _on_shot_hit(_position: Vector3, collider: Object) -> void:
	var hit := _find_enemy(collider)
	if hit.is_empty():
		return
	var enemy: Node = hit["enemy"]
	_last_hit_headshot[enemy.get_instance_id()] = hit["headshot"]
	if _hud != null and not is_game_over:
		_hud.show_hitmarker(false, hit["headshot"])


func _on_enemy_died(enemy: Node3D) -> void:
	# The weapon reports the hit right after the enemy dies: wait for it so we
	# know whether the killing shot was a headshot.
	_register_kill.call_deferred(enemy)


func _register_kill(enemy: Node3D) -> void:
	if is_game_over:
		return
	var headshot: bool = _last_hit_headshot.get(enemy.get_instance_id(), false)
	kills += 1
	score += points_per_kill + (headshot_bonus if headshot else 0)
	if _hud != null:
		_hud.show_hitmarker(true, headshot)
		var text := "YOU  »  %s" % String(enemy.name).replace("Enemy", "ENEMY ")
		if headshot:
			text += "   HEADSHOT +%d" % (points_per_kill + headshot_bonus)
		else:
			text += "   +%d" % points_per_kill
		_hud.add_killfeed(text, Color(1.0, 0.8, 0.3) if headshot else Color.WHITE)
		_hud.set_score(score)
		_hud.set_kills(kills, kills_to_win)
	if kills >= kills_to_win:
		_end_game(true, "%d ENEMIES ELIMINATED" % kills)


# ---------------------------------------------------------------------------
# Beacons
# ---------------------------------------------------------------------------

func _on_beacon_progress(_beacon: Node3D, _progress: float) -> void:
	if _hud == null:
		return
	var best := 0.0
	for beacon in beacons:
		if not beacon.is_active:
			best = maxf(best, beacon.progress)
	_hud.set_beacon_progress(best)


func _on_beacon_activated(_beacon: Node3D) -> void:
	beacons_active += 1
	score += points_per_beacon
	if _hud != null:
		_hud.set_beacon_progress(0.0)
		_hud.set_score(score)
		_hud.set_beacons(beacons_active, beacons.size())
		_hud.show_message("BEACON ACTIVATED  +%d" % points_per_beacon, 2.5)
		_hud.add_killfeed("BEACON %d / %d   +%d" % [beacons_active, beacons.size(), points_per_beacon], Color(0.4, 1.0, 0.5))


# ---------------------------------------------------------------------------
# End of the match
# ---------------------------------------------------------------------------

func _end_game(won: bool, reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _hud != null:
		var elapsed := int(round(match_time - maxf(time_left, 0.0)))
		var stats := "SCORE %d      KILLS %d / %d      BEACONS %d / %d      TIME %d:%02d" % [
			score, kills, kills_to_win, beacons_active, beacons.size(), elapsed / 60, elapsed % 60]
		_hud.show_end_screen(won, reason, stats)
	game_ended.emit(won)


func _on_play_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
