extends CanvasLayer
## Full-screen post-processing drawn between the 3D view and the HUD:
## vignette, film grain, subtle chromatic aberration, low-health desaturation
## and a red hit flash. One small screen shader, works on every renderer.

const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vignette = 0.25;
uniform float grain = 0.08;
uniform float aberration = 0.02;
uniform float desaturation = 0.0;
uniform float hit_flash = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float r2 = dot(d, d);

	// Chromatic aberration: grows towards the corners.
	vec2 shift = d * aberration * r2 * 0.6;
	vec3 col;
	col.r = texture(screen_tex, uv + shift).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - shift).b;

	// Low health: drain the colour.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), desaturation);

	// Film grain.
	float n = fract(sin(dot(uv * vec2(1920.0, 1080.0) + vec2(TIME * 61.0, TIME * 37.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	col += n * grain * 0.45;

	// Vignette, tinted red when hit.
	float edge = smoothstep(0.12, 0.62, r2 * 1.7);
	col *= 1.0 - edge * vignette * 1.6;
	col = mix(col, vec3(0.75, 0.03, 0.02), clamp(hit_flash * edge * 0.75, 0.0, 1.0));

	COLOR = vec4(col, 1.0);
}
"""

var _rect: ColorRect
var _material: ShaderMaterial
var _hit: float = 0.0
var _desaturation_target: float = 0.0
var _desaturation: float = 0.0


func _ready() -> void:
	layer = 0  # above the 3D world, below the HUD (layer 1) and menus
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect = ColorRect.new()
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func apply_quality(quality: String, mobile: bool = false) -> void:
	# Low keeps only the vignette (cheapest path); medium and high get everything.
	var low := quality == "low"
	if mobile:
		# Phones: the full-screen pass is skipped on low and
		# kept to the vignette on medium.
		visible = not low
		low = quality != "high"
	_material.set_shader_parameter("vignette", 0.25)
	_material.set_shader_parameter("grain", 0.0 if low else 0.08)
	_material.set_shader_parameter("aberration", 0.0 if low else 0.02)


## 0..1 health ratio: under 35% the picture loses colour.
func set_health_ratio(ratio: float) -> void:
	_desaturation_target = clampf((0.35 - ratio) / 0.35, 0.0, 1.0) * 0.75


func flash_hit(strength: float = 1.0) -> void:
	_hit = maxf(_hit, strength)


func reset() -> void:
	_hit = 0.0
	_desaturation = 0.0
	_desaturation_target = 0.0


func _process(delta: float) -> void:
	_hit = maxf(_hit - delta * 2.2, 0.0)
	_desaturation = lerpf(_desaturation, _desaturation_target, clampf(4.0 * delta, 0.0, 1.0))
	_material.set_shader_parameter("hit_flash", _hit)
	_material.set_shader_parameter("desaturation", _desaturation)
