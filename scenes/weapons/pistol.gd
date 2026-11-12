extends "res://scripts/weapon.gd"
## Pistol: 12 rounds, semi-automatic, reload 1.1 s, damage 18.


func _setup() -> void:
	weapon_name = "PISTOL"
	magazine_size = 12
	damage = 18.0
	automatic = false
	fire_interval = 0.14  # fastest allowed tap rate
	reload_time = 1.1

	hip_spread_deg = 1.0
	ads_spread_deg = 0.25
	move_spread_deg = 1.6
	bloom_per_shot = 0.45

	recoil_pitch_deg = 1.6
	recoil_yaw_deg = 0.5
	shake_amount = 0.22
	ads_fov = 60.0

	hip_position = Vector3(0.15, -0.15, -0.38)
	ads_position = Vector3(0.0, -0.047, -0.34)
	kick_back = 0.03
	kick_up_deg = 7.0
	flash_size = 0.12
	shell_length = 0.018

	var metal := WeaponFX.make_metal_material(Color(0.22, 0.23, 0.25))
	var dark_metal := WeaponFX.make_metal_material(Color(0.12, 0.125, 0.14))
	var grip := WeaponFX.make_grip_material(Color(0.1, 0.09, 0.08))

	# Metal parts.
	_add_box(Vector3(0.03, 0.034, 0.19), Vector3(0, 0.02, -0.02), metal)              # slide
	_add_box(Vector3(0.028, 0.02, 0.15), Vector3(0, -0.006, -0.01), dark_metal)       # frame
	_add_cylinder(0.008, 0.03, Vector3(0, 0.02, -0.125), dark_metal)                  # barrel tip
	_add_box(Vector3(0.008, 0.008, 0.05), Vector3(0, -0.036, -0.005), dark_metal)     # trigger guard
	_add_box(Vector3(0.008, 0.02, 0.008), Vector3(0, -0.026, -0.03), dark_metal)      # trigger guard front

	# Sights.
	_add_box(Vector3(0.005, 0.008, 0.008), Vector3(-0.007, 0.041, 0.065), dark_metal)  # rear left
	_add_box(Vector3(0.005, 0.008, 0.008), Vector3(0.007, 0.041, 0.065), dark_metal)   # rear right
	_add_box(Vector3(0.004, 0.008, 0.006), Vector3(0, 0.041, -0.105), dark_metal)      # front

	# Grip.
	_add_box(Vector3(0.029, 0.1, 0.046), Vector3(0, -0.062, 0.05), grip, Vector3(12, 0, 0))

	muzzle.position = Vector3(0, 0.02, -0.15)
	eject.position = Vector3(0.02, 0.04, 0.0)
