extends Node
## Autoload "GameSettings": renderer choice and graphics quality, saved between runs.
##
## RENDERER
##   Godot picks the renderer when the game starts, so changing it means
##   restarting: set_renderer() saves the choice and relaunches the game.
##   The project itself is set to Compatibility, so the Godot editor works on
##   every machine. "auto" (default) = when the game starts it relaunches itself
##   on Forward+ (full graphics), except on Macs with an Intel integrated GPU,
##   where Forward+ is broken and it stays on Compatibility.
##   The 0 key (or F9) toggles the two at any time.
##
## QUALITY (shadows, fog and bloom stay on at every level)
##   High:   4x MSAA, 4096 soft shadows, SSAO, grain + aberration,
##           and on Forward+ also SDFGI, SSR, volumetric fog, DOF when aiming.
##   Medium: 2x MSAA, 4096 shadows, SSAO, and on Forward+ SSR + volumetric fog.
##   Low:    no MSAA, 2048 shadows, no SSAO, 70% 3D resolution, vignette only.

signal quality_changed(quality: String)

const GraphicsFX := preload("res://scripts/graphics_fx.gd")
const PostFX := preload("res://scripts/post_fx.gd")

const SAVE_PATH := "user://settings.cfg"
const QUALITIES := ["low", "medium", "high"]
const RENDERERS := ["forward_plus", "gl_compatibility"]
const RESTART_FLAG := "--renderer-switched"

var quality: String = "medium"
## "auto", "forward_plus" or "gl_compatibility".
var renderer_preference: String = "auto"
var post: CanvasLayer
var _watchdog: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	var has_file := config.load(SAVE_PATH) == OK
	if has_file:
		var saved_renderer := str(config.get_value("graphics", "renderer", renderer_preference))
		if saved_renderer == "auto" or saved_renderer in RENDERERS:
			renderer_preference = saved_renderer
	var saved_quality := str(config.get_value("graphics", "quality", "")) if has_file else ""
	if saved_quality in QUALITIES:
		quality = saved_quality
	else:
		# First run: full quality on Forward+, medium on the Compatibility fallback.
		quality = "high" if get_desired_renderer() == "forward_plus" else "medium"

	post = CanvasLayer.new()
	post.set_script(PostFX)
	post.name = "PostFX"
	add_child(post)

	# Every WorldEnvironment that enters the tree gets the current look.
	get_tree().node_added.connect(_on_node_added)
	apply()
	_check_renderer.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	# 0 as well as F9: on MacBooks the F keys are media keys unless fn is held.
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_F9 or key.keycode == KEY_0 or key.physical_keycode == KEY_0):
		toggle_renderer()


# ---------------------------------------------------------------------------
# Renderer
# ---------------------------------------------------------------------------

func get_current_renderer() -> String:
	return RenderingServer.get_current_rendering_method()


func is_forward_plus() -> bool:
	return get_current_renderer() == "forward_plus"


## Forward+ needs working compute shaders: Intel integrated GPUs on macOS do not have them.
func is_forward_plus_known_broken() -> bool:
	return OS.get_name() == "macOS" and RenderingServer.get_video_adapter_name().to_lower().contains("intel")


func get_desired_renderer() -> String:
	if renderer_preference in RENDERERS:
		return renderer_preference
	return "gl_compatibility" if is_forward_plus_known_broken() else "forward_plus"


func get_renderer_index() -> int:
	return RENDERERS.find(get_current_renderer() if get_current_renderer() in RENDERERS else "forward_plus")


## Saves the choice and restarts the game on the chosen renderer.
func set_renderer(value: String) -> void:
	if not value in RENDERERS:
		return
	renderer_preference = value
	_save()
	if value != get_current_renderer():
		_restart_with(value)


func toggle_renderer() -> void:
	set_renderer("gl_compatibility" if get_current_renderer() != "gl_compatibility" else "forward_plus")


func _check_renderer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Only switch automatically once per launch (no restart loops if the
	# requested renderer is not available on this machine).
	if RESTART_FLAG in OS.get_cmdline_user_args():
		return
	var desired := get_desired_renderer()
	if desired != get_current_renderer():
		_restart_with(desired)


func _restart_with(method: String) -> void:
	# A browser or a phone cannot relaunch the game.
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		# Started from the Godot editor: the new process needs the project path.
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--rendering-method")
	args.append(method)
	if method == "gl_compatibility":
		args.append("--rendering-driver")
		args.append("opengl3")
	args.append("--")
	args.append(RESTART_FLAG)
	# Launch the new instance ourselves, then close this one. If the old
	# renderer is slow to shut down, a watchdog thread ends the process so two
	# copies of the game never stay open.
	OS.create_process(OS.get_executable_path(), args)
	_watchdog = Thread.new()
	_watchdog.start(func() -> void:
		OS.delay_msec(2500)
		OS.kill(OS.get_process_id()))
	get_tree().paused = false
	get_tree().quit()


# ---------------------------------------------------------------------------
# Quality
# ---------------------------------------------------------------------------

func set_quality(value: String) -> void:
	if not value in QUALITIES or value == quality:
		return
	quality = value
	_save()
	apply()
	quality_changed.emit(quality)


func get_quality_index() -> int:
	return QUALITIES.find(quality)


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", quality)
	config.set_value("graphics", "renderer", renderer_preference)
	config.save(SAVE_PATH)


func apply() -> void:
	var viewport := get_tree().root
	var low := quality == "low"
	var high := quality == "high"
	if low:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	else:
		viewport.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_2X
	viewport.scaling_3d_scale = 0.7 if low else 1.0
	viewport.use_occlusion_culling = true
	RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096, true)
	var filter := RenderingServer.SHADOW_QUALITY_SOFT_LOW
	if high:
		filter = RenderingServer.SHADOW_QUALITY_SOFT_HIGH  # 16 samples, the closest to PCF13
	elif not low:
		filter = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter)
	if post != null:
		post.apply_quality(quality)
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_apply_environment(node as WorldEnvironment)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_apply_environment.call_deferred(node)


func _apply_environment(world: WorldEnvironment) -> void:
	if world == null or not is_instance_valid(world) or not world.is_inside_tree() or world.environment == null:
		return
	GraphicsFX.setup_scene(world, quality, is_forward_plus())
