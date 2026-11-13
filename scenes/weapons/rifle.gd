extends "res://scripts/weapon.gd"
## Assault rifle: 30 rounds, automatic, reload 1.8 s,
## damage 25. Stats are the same as before.
## Viewmodel: animated M4 with arms and gloves
## (assets/models/m4). The model is a first-person rig
## built around its own camera joint: _build_model() lines
## that joint up with the game camera.

const MODEL := preload(
	"res://assets/models/m4/m4_animations.glb")
# Each clip starts with a long still part: these are the
# seconds where the action really is.
const IDLE_AT := 7.5
const FIRE_FROM := 7.57
const RELOAD_LENGTH := 3.67

var _anim: AnimationPlayer


func _setup() -> void:
	weapon_name = "RIFLE"
	magazine_size = 30
	damage = 25.0
	automatic = true
	fire_interval = 0.1  # 600 rounds per minute
	reload_time = 1.8

	hip_spread_deg = 1.3
	ads_spread_deg = 0.15
	move_spread_deg = 2.4
	bloom_per_shot = 0.3

	recoil_pitch_deg = 1.0
	recoil_yaw_deg = 0.45
	shake_amount = 0.28
	ads_fov = 55.0

	# The rig already sits where the artist wanted it.
	hip_position = Vector3(0.02, -0.025, 0.0)
	# Aiming: bring the iron sights to the screen centre.
	ads_position = Vector3(-0.07, 0.004, 0.0)
	kick_back = 0.045
	kick_up_deg = 2.5
	flash_size = 0.18
	shell_length = 0.026
	reload_dip = false  # the model has a real reload

	_build_model()
	muzzle.position = Vector3(0.068, -0.075, -0.74)
	eject.position = Vector3(0.105, -0.05, -0.2)

	fired.connect(_on_fired)
	reload_started.connect(_on_reload_started)
	_play_idle()


func _build_model() -> void:
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	var joint := model.find_child(
		"FPS_Camera", true, false) as Node3D
	if joint != null:
		# The rig looks along +X of its camera joint and is
		# in centimetres; the game camera looks along -Z.
		var to_game := Basis(Vector3.UP, PI * 0.5)
		var joint_space := MeshMerger._relative(joint, model)
		model.transform = Transform3D(
			to_game.scaled(Vector3.ONE * 0.01), Vector3.ZERO) \
			* joint_space.affine_inverse()
	for node in model.find_children(
			"*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The bare forearm burns out to white in the
		# sunset light: tone the skin down.
		var skin := mesh.get_active_material(0) \
			as BaseMaterial3D
		if skin != null and skin.resource_name == "Hand_D":
			skin.albedo_color = Color(0.62, 0.55, 0.5)
	_anim = model.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer


func _play_idle() -> void:
	if _anim == null:
		return
	_anim.play("Fire", -1.0, 1.0)
	_anim.seek(IDLE_AT, true)
	_anim.pause()


func _on_fired() -> void:
	if _anim == null:
		return
	_anim.play("Fire", -1.0, 1.0)
	_anim.seek(FIRE_FROM, true)


func _on_reload_started(duration: float) -> void:
	if _anim == null:
		return
	# The clip is squeezed into the gameplay reload time.
	var speed := RELOAD_LENGTH / maxf(duration, 0.1)
	_anim.play("Reload", -1.0, speed)
	_anim.seek(0.0, true)


func cancel_reload() -> void:
	super()
	_play_idle()
