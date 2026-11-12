extends Node3D
## Base weapon: ammo, fire rate, reload, viewmodel animation and fire effects.
## rifle.gd and pistol.gd extend this, set the stats and build the viewmodel.
## The hitscan ray, camera recoil and shake are handled by weapon_manager.gd.

const WeaponFX := preload("res://scripts/weapon_fx.gd")

signal ammo_changed(current: int, magazine: int)
signal fired
signal reload_started(duration: float)
signal reload_finished

# --- Stats (overridden by each weapon in _setup) ---
var weapon_name: String = "Weapon"
var magazine_size: int = 30
var damage: float = 25.0
var automatic: bool = true
var fire_interval: float = 0.1
var reload_time: float = 1.8
var max_range: float = 200.0

# Accuracy, in degrees.
var hip_spread_deg: float = 1.2
var ads_spread_deg: float = 0.15
var move_spread_deg: float = 2.2
var bloom_per_shot: float = 0.35

# Camera feedback.
var recoil_pitch_deg: float = 1.1
var recoil_yaw_deg: float = 0.45
var shake_amount: float = 0.3
var ads_fov: float = 50.0

# Viewmodel placement (relative to the camera).
var hip_position: Vector3 = Vector3(0.2, -0.2, -0.45)
var ads_position: Vector3 = Vector3(0.0, -0.06, -0.3)
var kick_back: float = 0.05
var kick_up_deg: float = 3.0
var flash_size: float = 0.16
var shell_length: float = 0.022

# --- State ---
var ammo: int = 0
var is_reloading: bool = false
var aim_amount: float = 0.0      # 0 = hip, 1 = aiming down sights (set by the manager)
var holster_amount: float = 0.0  # 0 = ready, 1 = lowered (set by the manager)

var muzzle: Marker3D
var eject: Marker3D

var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _kick: float = 0.0
var _flash_left: float = 0.0
var _flash_particles: GPUParticles3D
var _flash_light: OmniLight3D
var _shells: Array[GPUParticles3D] = []
var _shell_index: int = 0


func _ready() -> void:
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	add_child(muzzle)
	eject = Marker3D.new()
	eject.name = "Eject"
	add_child(eject)

	_setup()
	ammo = magazine_size

	_flash_particles = WeaponFX.make_muzzle_flash(flash_size)
	muzzle.add_child(_flash_particles)

	_flash_light = OmniLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.light_color = Color(1.0, 0.72, 0.35)
	_flash_light.light_energy = 3.0
	_flash_light.omni_range = 7.0
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	muzzle.add_child(_flash_light)

	for i in 8:
		var shell := WeaponFX.make_shell_emitter(shell_length)
		eject.add_child(shell)
		_shells.append(shell)

	_update_transform()


## Overridden by each weapon: set the stats and build the viewmodel.
func _setup() -> void:
	pass


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_light.visible = false
	_kick = lerpf(_kick, 0.0, clampf(14.0 * delta, 0.0, 1.0))
	_update_transform()


func _update_transform() -> void:
	var dip := 0.0
	if is_reloading and reload_time > 0.0:
		dip = sin(clampf(1.0 - _reload_left / reload_time, 0.0, 1.0) * PI)
	var pos := hip_position.lerp(ads_position, aim_amount)
	pos += Vector3(0.0, -0.12 * dip - 0.3 * holster_amount, kick_back * _kick)
	position = pos
	rotation_degrees = Vector3(
		kick_up_deg * _kick - 22.0 * dip - 40.0 * holster_amount,
		0.0,
		14.0 * dip
	)


## Fires one shot if possible. Returns true when a bullet actually left the gun.
func try_fire() -> bool:
	if is_reloading or _cooldown > 0.0 or holster_amount > 0.05 or ammo <= 0:
		return false
	ammo -= 1
	_cooldown = fire_interval
	_kick = 1.0
	_play_fire_fx()
	ammo_changed.emit(ammo, magazine_size)
	fired.emit()
	return true


func start_reload() -> void:
	if is_reloading or ammo >= magazine_size or holster_amount > 0.05:
		return
	is_reloading = true
	_reload_left = reload_time
	reload_started.emit(reload_time)


func cancel_reload() -> void:
	is_reloading = false
	_reload_left = 0.0


func get_reload_progress() -> float:
	if not is_reloading or reload_time <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_left / reload_time, 0.0, 1.0)


func _finish_reload() -> void:
	is_reloading = false
	ammo = magazine_size
	ammo_changed.emit(ammo, magazine_size)
	reload_finished.emit()


func _play_fire_fx() -> void:
	WeaponFX.burst(_flash_particles)
	_flash_light.visible = true
	_flash_left = 0.05
	WeaponFX.burst(_shells[_shell_index])
	_shell_index = (_shell_index + 1) % _shells.size()


## Called by the manager when the weapon is put away.
func deactivate() -> void:
	cancel_reload()
	_flash_light.visible = false
	_flash_left = 0.0
	visible = false
	set_process(false)


## Called by the manager when the weapon is drawn.
func activate() -> void:
	visible = true
	set_process(true)
	_update_transform()


# ---------------------------------------------------------------------------
# Viewmodel building helpers (BoxMesh / CylinderMesh + StandardMaterial3D)
# ---------------------------------------------------------------------------

func _add_box(size: Vector3, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_part(mesh, pos, material, rot_deg)


## Cylinder along the barrel axis (Z) by default.
func _add_cylinder(radius: float, length: float, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3 = Vector3(90, 0, 0)) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 1
	return _add_part(mesh, pos, material, rot_deg)


func _add_part(mesh: Mesh, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.rotation_degrees = rot_deg
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part
