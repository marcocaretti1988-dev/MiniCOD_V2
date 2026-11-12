extends Control
## Screen-centre overlays drawn by code: hitmarker, beacon progress circle and
## damage direction indicators.

@export var hitmarker_time: float = 0.18
@export var indicator_time: float = 1.4
@export var indicator_radius: float = 120.0

## Player node, used to turn a world position into a screen direction.
var player: Node3D
## 0..1 while standing on a beacon, 0 hides the circle.
var beacon_progress: float = 0.0

var _hit_left: float = 0.0
var _hit_color: Color = Color.WHITE
var _hit_big: bool = false
var _indicators: Array = []  # each: { "pos": Vector3, "left": float }


func show_hitmarker(color: Color, big: bool = false) -> void:
	_hit_left = hitmarker_time * (1.6 if big else 1.0)
	_hit_color = color
	_hit_big = big


func show_damage_from(world_position: Vector3) -> void:
	_indicators.append({"pos": world_position, "left": indicator_time})
	if _indicators.size() > 6:
		_indicators.pop_front()


func _process(delta: float) -> void:
	_hit_left = maxf(_hit_left - delta, 0.0)
	for item in _indicators:
		item["left"] -= delta
	_indicators = _indicators.filter(func(item: Dictionary) -> bool: return item["left"] > 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5

	# Beacon progress circle.
	if beacon_progress > 0.001:
		draw_arc(c, 38.0, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 7.0, true)
		draw_arc(c, 38.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(beacon_progress, 0.0, 1.0), 48, Color(1.0, 0.82, 0.15, 0.95), 5.0, true)

	# Hitmarker: four diagonal ticks.
	if _hit_left > 0.0:
		var t := _hit_left / hitmarker_time
		var col := Color(_hit_color.r, _hit_color.g, _hit_color.b, clampf(t, 0.0, 1.0))
		var inner := 9.0 if not _hit_big else 11.0
		var outer := 19.0 if not _hit_big else 25.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir: Vector2 = d.normalized()
			draw_line(c + dir * inner, c + dir * outer, Color(0, 0, 0, col.a * 0.6), 5.0)
			draw_line(c + dir * inner, c + dir * outer, col, 2.5)

	# Damage direction indicators: red arcs pointing towards the attacker.
	if player != null and is_instance_valid(player):
		for item in _indicators:
			var to: Vector3 = item["pos"] - player.global_position
			var local := player.global_transform.basis.inverse() * to
			# 0 = in front (top of the screen), positive = to the right.
			var angle := atan2(local.x, -local.z) - PI * 0.5
			var alpha := clampf(float(item["left"]) / indicator_time, 0.0, 1.0)
			draw_arc(c, indicator_radius, angle - 0.32, angle + 0.32, 20, Color(0, 0, 0, 0.35 * alpha), 14.0, true)
			draw_arc(c, indicator_radius, angle - 0.3, angle + 0.3, 20, Color(1.0, 0.12, 0.08, 0.9 * alpha), 9.0, true)
			var tip := c + Vector2(cos(angle), sin(angle)) * (indicator_radius + 16.0)
			var side := Vector2(-sin(angle), cos(angle)) * 9.0
			var base := c + Vector2(cos(angle), sin(angle)) * (indicator_radius + 5.0)
			draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(1.0, 0.12, 0.08, 0.9 * alpha))
