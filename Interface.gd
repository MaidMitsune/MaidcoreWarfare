extends Control
 
# References to the two sub-scenes.
# Paths must match the node names in interface.tscn exactly.
@onready var hp_counter    = $HBoxContainer/HP_counter
@onready var ammo_counter  = $HBoxContainer2/Ammo_counter
 
func _ready() -> void:
	var pistol = get_tree().get_first_node_in_group("weapon")
	if pistol:
		pistol.ammo_changed.connect(_on_ammo_changed)
		pistol.state_changed.connect(_on_reload_state_changed)
		ammo_counter.update_ammo(pistol.ammo_in_mag, pistol.ammo_reserve)
	else:
		push_warning("Interface: no node found in group 'weapon'.")

	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.health_changed.connect(_on_health_changed)
		hp_counter.update_hp(player.health)
	else:
		push_warning("Interface: no node found in group 'player'.")
 
# Fired by the weapon whenever ammo changes (after shooting or reloading).
func _on_ammo_changed(in_mag: int, reserve: int, _chambered: bool) -> void:
	ammo_counter.update_ammo(in_mag, reserve)
 
# Fired by the weapon every time the reload advances a step.
func _on_reload_state_changed(state) -> void:
	ammo_counter.update_reload_state(state)
 
# Fired by the player whenever health changes.
func _on_health_changed(new_hp: float) -> void:
	hp_counter.update_hp(new_hp)
	
