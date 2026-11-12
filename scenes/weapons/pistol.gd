extends "res://scripts/weapon.gd"
## Pistol: 12 rounds, semi-automatic, reload 1.1 s, damage 18.
## Detailed viewmodel: serrated slide, polymer frame, night sights, gloved hands.


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
	ads_fov = 55.0

	hip_position = Vector3(0.14, -0.15, -0.36)
	ads_position = Vector3(0.0, -0.049, -0.33)
	kick_back = 0.03
	kick_up_deg = 7.0
	flash_size = 0.12
	shell_length = 0.018

	var metal := WeaponFX.make_gun_metal()
	var steel := WeaponFX.make_gun_metal(Color(0.2, 0.205, 0.22))
	var polymer := WeaponFX.make_polymer()
	var hole := WeaponFX.make_polymer(Color(0.012, 0.012, 0.014))
	var dot := WeaponFX.make_dot(Color(0.3, 1.0, 0.35), 3.0)
	var glove := WeaponFX.make_glove()
	var sleeve := WeaponFX.make_glove(Color(0.075, 0.085, 0.065))

	# --- Slide ---
	_add_box(Vector3(0.03, 0.03, 0.2), Vector3(0, 0.022, -0.02), metal)
	_add_box(Vector3(0.026, 0.006, 0.2), Vector3(0, 0.039, -0.02), metal)             # slide top flat
	for i in 6:
		_add_box(Vector3(0.0315, 0.022, 0.004), Vector3(0, 0.022, 0.035 + i * 0.008), steel)  # rear serrations
	_add_box(Vector3(0.002, 0.012, 0.035), Vector3(0.0155, 0.028, -0.03), hole)       # ejection port
	_add_cylinder(0.0085, 0.02, Vector3(0, 0.022, -0.128), steel)                     # barrel tip
	_add_cylinder(0.005, 0.004, Vector3(0, 0.022, -0.139), hole)                      # bore
	_add_cylinder(0.004, 0.02, Vector3(0, 0.006, -0.125), steel)                      # guide rod

	# --- Frame, rail, trigger ---
	_add_box(Vector3(0.028, 0.02, 0.165), Vector3(0, -0.002, -0.01), polymer)
	_add_box(Vector3(0.022, 0.008, 0.05), Vector3(0, -0.015, -0.085), polymer)        # accessory rail
	_add_box(Vector3(0.008, 0.007, 0.055), Vector3(0, -0.04, -0.015), polymer)        # trigger guard bottom
	_add_box(Vector3(0.008, 0.028, 0.007), Vector3(0, -0.026, -0.04), polymer)        # trigger guard front
	_add_box(Vector3(0.006, 0.018, 0.006), Vector3(0, -0.024, -0.008), steel, Vector3(15, 0, 0))  # trigger
	_add_box(Vector3(0.031, 0.006, 0.014), Vector3(0, 0.004, 0.03), steel)            # slide stop

	# --- Grip with magazine base ---
	_add_box(Vector3(0.03, 0.1, 0.048), Vector3(0, -0.062, 0.052), polymer, Vector3(12, 0, 0))
	_add_box(Vector3(0.032, 0.008, 0.052), Vector3(0, -0.113, 0.064), metal, Vector3(12, 0, 0))

	# --- Night sights (glowing dots) ---
	_add_box(Vector3(0.006, 0.009, 0.01), Vector3(-0.008, 0.0445, 0.07), metal)       # rear left
	_add_box(Vector3(0.006, 0.009, 0.01), Vector3(0.008, 0.0445, 0.07), metal)        # rear right
	_add_box(Vector3(0.0045, 0.009, 0.008), Vector3(0, 0.0445, -0.11), metal)         # front post
	_add_box(Vector3(0.0025, 0.0025, 0.001), Vector3(-0.008, 0.0455, 0.0755), dot)
	_add_box(Vector3(0.0025, 0.0025, 0.001), Vector3(0.008, 0.0455, 0.0755), dot)
	_add_box(Vector3(0.0025, 0.0025, 0.001), Vector3(0, 0.0455, -0.1055), dot)

	# --- Gloved hands and sleeves ---
	_add_box(Vector3(0.046, 0.085, 0.062), Vector3(0.002, -0.06, 0.055), glove, Vector3(12, 0, 0))   # right hand
	_add_box(Vector3(0.05, 0.06, 0.04), Vector3(-0.012, -0.07, 0.02), glove, Vector3(12, 12, 0))     # left support hand
	_add_box(Vector3(0.02, 0.02, 0.05), Vector3(-0.02, -0.012, 0.0), glove)                          # left thumb along the frame
	_add_limb(Vector3(0.004, -0.085, 0.07), Vector3(0.14, -0.32, 0.36), 0.036, sleeve)
	_add_limb(Vector3(-0.02, -0.085, 0.03), Vector3(-0.26, -0.32, 0.32), 0.036, sleeve)

	muzzle.position = Vector3(0, 0.022, -0.15)
	eject.position = Vector3(0.02, 0.04, 0.0)


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
