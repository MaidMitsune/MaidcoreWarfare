extends Weapon

# The pistol uses the base Weapon reload system as-is.
# Override _do_fire here if you want spread, muzzle flash, sound, etc.

@export var spread: float = 0.01   # slight inaccuracy in radians

func _do_fire(spawn_point: Node3D) -> void:
	if bullet_scene == null:
		push_warning("Pistol: bullet_scene not assigned")
		return

	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = spawn_point.global_transform

	# Apply small random spread
	var dir = spawn_point.global_transform.basis * Vector3.FORWARD * -1
	dir.x += randf_range(-spread, spread)
	dir.y += randf_range(-spread, spread)

	bullet.fire(dir.normalized())
