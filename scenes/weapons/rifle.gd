extends "res://scripts/weapon.gd"
## Assault rifle: 30 rounds, automatic, reload 1.8 s, damage 25.
## Detailed viewmodel: vented handguard, suppressor, ribbed magazine, stock,
## red-dot sight with a glass lens and gloved hands.


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

	hip_position = Vector3(0.15, -0.165, -0.38)
	ads_position = Vector3(0.0, -0.0865, -0.3)
	kick_back = 0.045
	kick_up_deg = 2.5
	flash_size = 0.18
	shell_length = 0.026

	var metal := WeaponFX.make_gun_metal()
	var steel := WeaponFX.make_gun_metal(Color(0.16, 0.165, 0.18))
	var polymer := WeaponFX.make_polymer()
	var hole := WeaponFX.make_polymer(Color(0.012, 0.012, 0.014))
	var lens := WeaponFX.make_lens()
	var dot := WeaponFX.make_dot()
	var glove := WeaponFX.make_glove()
	var sleeve := WeaponFX.make_glove(Color(0.075, 0.085, 0.065))

	# --- Receiver ---
	_add_box(Vector3(0.046, 0.046, 0.3), Vector3(0, 0.014, 0), metal)                 # upper receiver
	_add_box(Vector3(0.042, 0.04, 0.19), Vector3(0, -0.026, 0.03), metal)             # lower receiver
	_add_box(Vector3(0.002, 0.016, 0.05), Vector3(0.0235, 0.018, 0.0), hole)          # ejection port
	_add_box(Vector3(0.012, 0.01, 0.03), Vector3(0.026, 0.03, 0.09), steel)           # charging handle
	_add_box(Vector3(0.008, 0.008, 0.05), Vector3(0, -0.062, 0.05), metal)            # trigger guard
	_add_box(Vector3(0.008, 0.02, 0.008), Vector3(0, -0.053, 0.027), metal)           # trigger guard front
	_add_box(Vector3(0.006, 0.02, 0.008), Vector3(0, -0.05, 0.055), steel, Vector3(18, 0, 0))  # trigger

	# --- Top rail with teeth ---
	_add_box(Vector3(0.02, 0.006, 0.52), Vector3(0, 0.04, -0.11), metal)
	for i in 13:
		_add_box(Vector3(0.022, 0.005, 0.012), Vector3(0, 0.0455, 0.13 - i * 0.04), steel)

	# --- Barrel, gas block, suppressor ---
	_add_cylinder(0.011, 0.32, Vector3(0, 0.012, -0.33), steel)
	_add_box(Vector3(0.026, 0.03, 0.03), Vector3(0, 0.018, -0.39), metal)             # gas block
	_add_cylinder(0.021, 0.17, Vector3(0, 0.012, -0.575), metal)                      # suppressor body
	_add_cylinder(0.0225, 0.012, Vector3(0, 0.012, -0.5), steel)                      # suppressor rear ring
	_add_cylinder(0.0225, 0.012, Vector3(0, 0.012, -0.655), steel)                    # suppressor front ring
	_add_cylinder(0.008, 0.004, Vector3(0, 0.012, -0.662), hole)                      # bore

	# --- Handguard with ventilation holes ---
	_add_box(Vector3(0.048, 0.05, 0.25), Vector3(0, 0.008, -0.275), polymer)
	for i in 6:
		var z := -0.17 - i * 0.04
		_add_box(Vector3(0.0495, 0.011, 0.024), Vector3(0, 0.02, z), hole)            # side slots (both sides)
		_add_box(Vector3(0.018, 0.0515, 0.022), Vector3(0, 0.008, z), hole)           # bottom / top slots
	_add_box(Vector3(0.03, 0.03, 0.05), Vector3(0, -0.035, -0.3), polymer, Vector3(8, 0, 0))  # foregrip stub

	# --- Magazine with ribs ---
	_add_box(Vector3(0.028, 0.09, 0.056), Vector3(0, -0.085, -0.035), metal, Vector3(-8, 0, 0))
	_add_box(Vector3(0.028, 0.08, 0.054), Vector3(0, -0.158, -0.052), metal, Vector3(-18, 0, 0))
	for i in 5:
		_add_box(Vector3(0.03, 0.004, 0.05), Vector3(0, -0.075 - i * 0.026, -0.034 - i * 0.006), steel, Vector3(-8 - i * 2.5, 0, 0))
	_add_box(Vector3(0.031, 0.01, 0.058), Vector3(0, -0.198, -0.065), polymer, Vector3(-18, 0, 0))  # base plate

	# --- Pistol grip and stock ---
	_add_box(Vector3(0.034, 0.1, 0.044), Vector3(0, -0.085, 0.1), polymer, Vector3(16, 0, 0))
	_add_cylinder(0.015, 0.2, Vector3(0, 0.01, 0.25), steel)                          # buffer tube
	_add_box(Vector3(0.036, 0.078, 0.13), Vector3(0, -0.012, 0.3), polymer)           # stock body
	_add_box(Vector3(0.03, 0.03, 0.09), Vector3(0, -0.045, 0.24), polymer, Vector3(-28, 0, 0))  # stock strut
	_add_box(Vector3(0.04, 0.095, 0.022), Vector3(0, -0.015, 0.372), hole)            # butt pad

	# --- Red-dot sight: mount, housing, glass lens, emissive dot ---
	_add_box(Vector3(0.03, 0.014, 0.06), Vector3(0, 0.05, 0.03), metal)               # mount
	_add_box(Vector3(0.044, 0.006, 0.05), Vector3(0, 0.06, 0.03), metal)              # housing floor
	_add_box(Vector3(0.044, 0.006, 0.05), Vector3(0, 0.106, 0.03), metal)             # housing roof
	_add_box(Vector3(0.005, 0.046, 0.05), Vector3(-0.0195, 0.083, 0.03), metal)       # housing left
	_add_box(Vector3(0.005, 0.046, 0.05), Vector3(0.0195, 0.083, 0.03), metal)        # housing right
	_add_box(Vector3(0.034, 0.04, 0.002), Vector3(0, 0.083, 0.012), lens)             # front glass
	_add_box(Vector3(0.0035, 0.0035, 0.001), Vector3(0, 0.0865, 0.0135), dot)         # red dot
	_add_cylinder(0.006, 0.012, Vector3(0.026, 0.07, 0.03), steel, Vector3(0, 0, 90)) # brightness knob

	# --- Gloved hands and sleeves ---
	# Right hand on the pistol grip.
	_add_box(Vector3(0.05, 0.075, 0.056), Vector3(0.004, -0.08, 0.104), glove, Vector3(16, 0, 0))
	_add_box(Vector3(0.022, 0.03, 0.06), Vector3(0.012, -0.045, 0.062), glove, Vector3(10, 0, 0))   # trigger finger
	_add_limb(Vector3(0.006, -0.1, 0.12), Vector3(0.14, -0.34, 0.4), 0.036, sleeve)
	# Left hand under the handguard.
	_add_box(Vector3(0.062, 0.04, 0.095), Vector3(-0.004, -0.032, -0.25), glove)
	_add_box(Vector3(0.016, 0.05, 0.085), Vector3(-0.032, 0.0, -0.25), glove)                       # fingers wrapping up
	_add_limb(Vector3(-0.012, -0.05, -0.24), Vector3(-0.3, -0.33, 0.1), 0.036, sleeve)

	muzzle.position = Vector3(0, 0.012, -0.68)
	eject.position = Vector3(0.03, 0.02, 0.0)


func _add_capsule(radius: float, length: float, pos: Vector3, material: StandardMaterial3D, rot_deg: Vector3) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length, radius * 2.0)
	mesh.radial_segments = 12
	mesh.rings = 4
	return _add_part(mesh, pos, material, rot_deg)


## Sleeve / forearm: a capsule stretched between two points.
func _add_limb(from: Vector3, to: Vector3, radius: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = from.distance_to(to) + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 4
	var part := _add_part(mesh, (from + to) * 0.5, material, Vector3.ZERO)
	var y := (to - from).normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	part.basis = Basis(x, y, x.cross(y).normalized())
	return part
