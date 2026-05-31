extends NinePatchRect

@onready var HP_label = $HP

# Call this function from Interface.gd whenever the player's HP changes.
# new_hp = the new health value to display
func update_hp(new_hp: float) -> void:
	HP_label.text = str(int(new_hp))
