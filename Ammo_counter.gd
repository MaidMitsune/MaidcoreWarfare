extends NinePatchRect
# References to the two labels inside Ammo_counter.
# "Mag" shows bullets in the current magazine.
# "Reserve" shows bullets left in reserve.
@onready var mag_label     = $Mag
@onready var reserve_label = $Reserve
 
# Call this function from Interface.gd whenever ammo changes.
# in_mag = bullets in the current magazine
# reserve = bullets left in reserve
func update_ammo(in_mag: int, reserve: int) -> void:
	mag_label.text     = str(in_mag)
	reserve_label.text = str(reserve)
 
# Call this to show/hide reload state text.
# You could also drive an animation from here if you want later.
func update_reload_state(state) -> void:
	match state:
		Weapon.State.NO_MAG:     mag_label.text = "---"
		Weapon.State.LOADING:    mag_label.text = "..."
		Weapon.State.COCKING:    mag_label.text = "~~"
		Weapon.State.JAMMED:     mag_label.text = "JAM"
		Weapon.State.IDLE:       pass
