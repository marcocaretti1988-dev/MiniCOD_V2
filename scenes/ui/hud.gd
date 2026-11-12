extends CanvasLayer
## HUD: dynamic crosshair + weapon name and ammo counter.

@onready var crosshair: Control = $Crosshair
@onready var ammo_label: Label = $AmmoLabel

var _manager: Node


func _ready() -> void:
	if owner != null:
		_manager = owner.get_node_or_null("Head/Camera3D/WeaponHolder")


func _process(_delta: float) -> void:
	if _manager == null or _manager.current == null:
		return
	var weapon: Node3D = _manager.current
	crosshair.spread_degrees = _manager.get_spread_degrees()
	crosshair.hide_amount = _manager.aim_amount

	if weapon.is_reloading:
		ammo_label.text = "%s   RELOADING" % weapon.weapon_name
	else:
		ammo_label.text = "%s   %d / %d" % [weapon.weapon_name, weapon.ammo, weapon.magazine_size]
	ammo_label.modulate = Color(1.0, 0.45, 0.35) if weapon.ammo == 0 and not weapon.is_reloading else Color.WHITE
