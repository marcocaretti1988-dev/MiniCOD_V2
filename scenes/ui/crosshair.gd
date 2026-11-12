extends Control
## Dynamic crosshair: four lines whose gap grows with movement and shooting.

@export var line_length: float = 9.0
@export var line_width: float = 2.0
@export var base_gap: float = 4.0
@export var pixels_per_degree: float = 9.0
@export var color: Color = Color(1, 1, 1, 0.9)
@export var outline_color: Color = Color(0, 0, 0, 0.6)

## Spread in degrees, set by the HUD every frame.
var spread_degrees: float = 0.0
## 0 = fully visible, 1 = hidden (aiming down sights).
var hide_amount: float = 0.0

var _gap: float = 4.0


func _process(delta: float) -> void:
	var target := base_gap + spread_degrees * pixels_per_degree
	_gap = lerpf(_gap, target, clampf(18.0 * delta, 0.0, 1.0))
	modulate.a = 1.0 - hide_amount
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var dirs := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for d in dirs:
		var a: Vector2 = c + d * _gap
		var b: Vector2 = c + d * (_gap + line_length)
		draw_line(a - d, b + d, outline_color, line_width + 2.0)
		draw_line(a, b, color, line_width)
	draw_circle(c, 2.0, outline_color)
	draw_circle(c, 1.0, color)
