extends Node
class_name health_system

signal _health_changed (current_hp: int, max_hp: int)
signal _died()

@export var initial_max_hp = 100

var current_hp: int
var max_hp: int

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	max_hp = initial_max_hp
	current_hp = max_hp

func _take_damage(damage_amount: int) -> void:
	current_hp = max(0, current_hp - damage_amount)
	if current_hp > 0:
		_health_changed.emit(current_hp, max_hp)
	else:
		_died.emit()
	
func _heal(heal_amount: int) -> void:
	current_hp = min(current_hp + heal_amount, max_hp)
	_health_changed.emit(current_hp, max_hp)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
