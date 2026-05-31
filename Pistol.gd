extends Weapon

# Semi-auto magazine-fed pistol.
# Inherits the full Beyond Citadel reload system from Weapon.gd:
#   X (unload) → R (reload) → C (cock)
# Speed reload: press R without unloading first — old mag is lost.

func _ready() -> void:
	magazine_size   = 10
	max_reserve     = 50
	fire_rate       = 0.18
	load_time       = 0.55
	cock_time       = 0.22
	base_spread     = 0.008
	condition_drain = 0.6    # pistol degrades slower than heavier weapons
	super._ready()
