extends "res://scripts/weapon.gd"
## Assault rifle: 30 rounds, automatic, reload 1.8 s, damage 25.


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
	ads_fov = 48.0

	hip_position = Vector3(0.16, -0.17, -0.4)
	ads_position = Vector3(0.0, -0.066, -0.42)
	kick_back = 0.045
	kick_up_deg = 2.5
	flash_size = 0.18
	shell_length = 0.026

	var metal := WeaponFX.make_metal_material(Color(0.2, 0.21, 0.23))
	var dark_metal := WeaponFX.make_metal_material(Color(0.12, 0.125, 0.14))
	var grip := WeaponFX.make_grip_material(Color(0.11, 0.1, 0.09))

	# Metal parts.
	_add_box(Vector3(0.05, 0.07, 0.3), Vector3(0, 0, 0), metal)                       # receiver
	_add_box(Vector3(0.022, 0.008, 0.28), Vector3(0, 0.039, -0.01), dark_metal)       # top rail
	_add_cylinder(0.012, 0.34, Vector3(0, 0.005, -0.31), dark_metal)                  # barrel
	_add_cylinder(0.018, 0.055, Vector3(0, 0.005, -0.5), metal)                       # muzzle brake
	_add_box(Vector3(0.03, 0.15, 0.055), Vector3(0, -0.1, -0.04), dark_metal, Vector3(-10, 0, 0))  # magazine
	_add_box(Vector3(0.008, 0.012, 0.045), Vector3(0, -0.045, 0.045), dark_metal)     # trigger guard
	_add_box(Vector3(0.006, 0.02, 0.006), Vector3(0.027, 0.012, 0.03), dark_metal)    # charging handle

	# Iron sights.
	_add_box(Vector3(0.006, 0.024, 0.01), Vector3(-0.009, 0.054, 0.11), dark_metal)   # rear left
	_add_box(Vector3(0.006, 0.024, 0.01), Vector3(0.009, 0.054, 0.11), dark_metal)    # rear right
	_add_box(Vector3(0.004, 0.058, 0.008), Vector3(0, 0.037, -0.4), dark_metal)       # front post

	# Polymer parts.
	_add_box(Vector3(0.046, 0.052, 0.22), Vector3(0, 0.002, -0.25), grip)             # handguard
	_add_box(Vector3(0.036, 0.1, 0.045), Vector3(0, -0.078, 0.095), grip, Vector3(15, 0, 0))  # pistol grip
	_add_box(Vector3(0.04, 0.055, 0.2), Vector3(0, -0.02, 0.25), grip)               # stock
	_add_box(Vector3(0.042, 0.085, 0.03), Vector3(0, -0.035, 0.36), grip)               # butt pad

	muzzle.position = Vector3(0, 0.005, -0.54)
	eject.position = Vector3(0.03, 0.02, 0.02)
