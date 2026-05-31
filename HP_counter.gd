extends NinePatchRect

@onready var label = $Label

# Call this function from Interface.gd whenever the player's HP changes.
# new_hp = the new health value to display
func update_hp(new_hp: float) -> void:
	label.text = str(int(new_hp))
