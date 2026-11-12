extends CanvasLayer
## HUD: health bar, ammo, weapon name, crosshair, hitmarker, killfeed, timer,
## score, objectives, minimap, low-health vignette, damage direction and the
## win / lose screen. The game manager drives it through the functions below.

signal play_again_pressed

@onready var crosshair: Control = $Crosshair
@onready var overlay: Control = $Overlay
@onready var vignette: TextureRect = $Vignette
@onready var minimap: Control = $Minimap
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var timer_label: Label = $TimerLabel
@onready var objective_label: Label = $ObjectiveLabel
@onready var score_label: Label = $ScoreLabel
@onready var killfeed: VBoxContainer = $Killfeed
@onready var message_label: Label = $MessageLabel
@onready var end_screen: Control = $EndScreen

var _weapons: Node
var _health: float = 100.0
var _max_health: float = 100.0
var _damage_flash: float = 0.0
var _message_left: float = 0.0
var _time: float = 0.0
var _feed: Array = []  # each: { "label": Label, "left": float }
var _bar_fill: StyleBoxFlat
var _end_title: Label
var _end_reason: Label
var _end_stats: Label
var _end_button: Button
var _kills: int = 0
var _kills_target: int = 10
var _beacons: int = 0
var _beacons_total: int = 3


func _ready() -> void:
	if owner != null:
		_weapons = owner.get_node_or_null("Head/Camera3D/WeaponHolder")
		overlay.player = owner as Node3D
		minimap.player = owner as Node3D

	_setup_health_bar()
	_setup_vignette()
	_build_end_screen()
	message_label.modulate.a = 0.0
	set_health(100.0, 100.0)
	set_time(300.0)
	set_score(0)
	_refresh_objectives()


func _process(delta: float) -> void:
	_time += delta
	_update_weapon()

	# Vignette: steady red pulse under 35 HP + a short flash when hit.
	_damage_flash = maxf(_damage_flash - delta * 1.8, 0.0)
	var low := clampf((35.0 - _health) / 35.0, 0.0, 1.0)
	var pulse := 0.7 + 0.3 * sin(_time * 5.0)
	vignette.modulate.a = clampf(low * 0.85 * pulse + _damage_flash * 0.6, 0.0, 1.0)

	if _message_left > 0.0:
		_message_left -= delta
		message_label.modulate.a = clampf(_message_left / 0.5, 0.0, 1.0)

	for item in _feed:
		item["left"] -= delta
		(item["label"] as Label).modulate.a = clampf(float(item["left"]) / 0.6, 0.0, 1.0)
	while not _feed.is_empty() and _feed[0]["left"] <= 0.0:
		(_feed[0]["label"] as Label).queue_free()
		_feed.pop_front()


func _update_weapon() -> void:
	if _weapons == null or _weapons.current == null:
		return
	var weapon: Node3D = _weapons.current
	crosshair.spread_degrees = _weapons.get_spread_degrees()
	crosshair.hide_amount = _weapons.aim_amount
	weapon_label.text = weapon.weapon_name
	if weapon.is_reloading:
		ammo_label.text = "RELOADING"
	else:
		ammo_label.text = "%d / %d" % [weapon.ammo, weapon.magazine_size]
	ammo_label.modulate = Color(1.0, 0.45, 0.35) if weapon.ammo == 0 and not weapon.is_reloading else Color.WHITE


# ---------------------------------------------------------------------------
# API used by the game manager
# ---------------------------------------------------------------------------

func set_health(value: float, max_value: float) -> void:
	_health = value
	_max_health = maxf(max_value, 1.0)
	health_bar.max_value = _max_health
	health_bar.value = clampf(value, 0.0, _max_health)
	health_label.text = "%d" % int(ceil(maxf(value, 0.0)))
	var ratio := clampf(value / _max_health, 0.0, 1.0)
	# Green -> yellow -> red.
	var color := Color(0.9, 0.2, 0.15).lerp(Color(0.95, 0.8, 0.2), clampf(ratio * 2.0, 0.0, 1.0))
	if ratio > 0.5:
		color = Color(0.95, 0.8, 0.2).lerp(Color(0.35, 0.85, 0.4), (ratio - 0.5) * 2.0)
	_bar_fill.bg_color = color


## Red flash + direction arc pointing to where the shot came from.
func show_damage(from_world_position: Vector3) -> void:
	_damage_flash = 1.0
	overlay.show_damage_from(from_world_position)


func set_time(seconds: float) -> void:
	var total := int(ceil(maxf(seconds, 0.0)))
	timer_label.text = "%d:%02d" % [total / 60, total % 60]
	timer_label.modulate = Color(1.0, 0.4, 0.3) if seconds <= 30.0 else Color.WHITE


func set_score(score: int) -> void:
	score_label.text = "SCORE  %d" % score


func set_kills(kills: int, target: int) -> void:
	_kills = kills
	_kills_target = target
	_refresh_objectives()


func set_beacons(active: int, total: int) -> void:
	_beacons = active
	_beacons_total = total
	_refresh_objectives()


func _refresh_objectives() -> void:
	objective_label.text = "KILLS  %d / %d      BEACONS  %d / %d" % [_kills, _kills_target, _beacons, _beacons_total]


func show_hitmarker(is_kill: bool, is_headshot: bool) -> void:
	var color := Color.WHITE
	if is_kill:
		color = Color(1.0, 0.2, 0.15)
	elif is_headshot:
		color = Color(1.0, 0.75, 0.2)
	overlay.show_hitmarker(color, is_kill)


func set_beacon_progress(progress: float) -> void:
	overlay.beacon_progress = progress


func add_killfeed(text: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	killfeed.add_child(label)
	_feed.append({"label": label, "left": 5.0})
	if _feed.size() > 5:
		(_feed[0]["label"] as Label).queue_free()
		_feed.pop_front()


func show_message(text: String, duration: float = 2.5, color: Color = Color(1.0, 0.85, 0.25)) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.modulate.a = 1.0
	_message_left = duration


func show_end_screen(won: bool, reason: String, stats: String) -> void:
	_end_title.text = "VICTORY" if won else "DEFEAT"
	_end_title.add_theme_color_override("font_color", Color(0.4, 0.95, 0.45) if won else Color(1.0, 0.3, 0.25))
	_end_reason.text = reason
	_end_stats.text = stats
	crosshair.visible = false
	overlay.beacon_progress = 0.0
	end_screen.visible = true
	_end_button.grab_focus()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _setup_health_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.07, 0.7)
	bg.border_color = Color(1, 1, 1, 0.55)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(3)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = Color(0.35, 0.85, 0.4)
	_bar_fill.set_corner_radius_all(2)
	_bar_fill.set_content_margin_all(0)
	health_bar.add_theme_stylebox_override("background", bg)
	health_bar.add_theme_stylebox_override("fill", _bar_fill)


func _setup_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0.8, 0.0, 0.0, 0.0), Color(0.8, 0.0, 0.0, 0.0), Color(0.85, 0.02, 0.0, 0.9)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, -0.12)
	vignette.texture = tex
	vignette.modulate.a = 0.0


func _styled_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	return label


func _build_end_screen() -> void:
	end_screen.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_screen.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_screen.add_child(centre)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	centre.add_child(box)

	_end_title = _styled_label("VICTORY", 84)
	box.add_child(_end_title)
	_end_reason = _styled_label("", 28)
	box.add_child(_end_reason)
	_end_stats = _styled_label("", 22)
	box.add_child(_end_stats)

	_end_button = Button.new()
	_end_button.text = "PLAY AGAIN"
	_end_button.custom_minimum_size = Vector2(260, 60)
	_end_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_end_button.add_theme_font_size_override("font_size", 26)
	_end_button.pressed.connect(func() -> void: play_again_pressed.emit())
	box.add_child(_end_button)
