extends StaticBody3D
## Separate hitbox for the enemy head. The player's bullet ray hits this body
## and the damage is forwarded to the enemy multiplied (headshot).
## It lives on its own collision layer so it never blocks movement.


func take_damage(amount: float) -> void:
	var enemy := get_parent()
	if enemy != null and enemy.has_method("take_damage"):
		enemy.take_damage(amount * enemy.headshot_multiplier, true)
