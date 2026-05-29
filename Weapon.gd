extends Node3D
class_name Weapon

# Reload states for manual reload
enum ReloadState { IDLE, EJECTING, INSERTING, COCKING }

@export var magazine_size: int = 10
@export var max_reserve: int = 50
@export var fire_rate: float = 0.15        # seconds between shots
@export var eject_time: float = 0.4        # time to eject magazine
@export var insert_time: float = 0.6       # time to insert new magazine
@export var cock_time: float = 0.3         # time to cock the weapon
@export var bullet_scene: PackedScene

var ammo_in_mag: int = 0
var ammo_reserve: int = 0
var is_chambered: bool = false             # round in chamber after cocking
var reload_state: ReloadState = ReloadState.IDLE
var can_fire: bool = true

var _fire_timer: float = 0.0
var _reload_timer: float = 0.0

signal ammo_changed(in_mag, reserve, chambered)
signal reload_state_changed(state)
signal fired
signal jammed


func _ready() -> void:
	ammo_in_mag = magazine_size
	ammo_reserve = max_reserve
	is_chambered = true


func _process(delta: float) -> void:
	if _fire_timer > 0.0:
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			can_fire = true

	if reload_state != ReloadState.IDLE:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_advance_reload()


func try_fire(spawn_point: Node3D) -> void:
	if reload_state != ReloadState.IDLE or not can_fire:
		return

	if not is_chambered:
		# dry fire, no round in chamber
		return

	_do_fire(spawn_point)
	is_chambered = false
	can_fire = false
	_fire_timer = fire_rate
	ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)
	fired.emit()


func start_reload() -> void:
	if reload_state != ReloadState.IDLE:
		return
	if ammo_reserve <= 0:
		return
	if ammo_in_mag == magazine_size and is_chambered:
		return

	reload_state = ReloadState.EJECTING
	_reload_timer = eject_time
	reload_state_changed.emit(reload_state)


func _advance_reload() -> void:
	match reload_state:
		ReloadState.EJECTING:
			# Drop the old magazine (ammo in it is lost, we have to change this so it can be picked up and re-used) 
			ammo_in_mag = 0
			reload_state = ReloadState.INSERTING
			_reload_timer = insert_time
			reload_state_changed.emit(reload_state)

		ReloadState.INSERTING:
			var to_load = min(magazine_size, ammo_reserve)
			ammo_in_mag = to_load
			ammo_reserve -= to_load
			reload_state = ReloadState.COCKING
			_reload_timer = cock_time
			reload_state_changed.emit(reload_state)

		ReloadState.COCKING:
			is_chambered = true
			reload_state = ReloadState.IDLE
			reload_state_changed.emit(reload_state)
			ammo_changed.emit(ammo_in_mag, ammo_reserve, is_chambered)


# Override this in each weapon subclass
func _do_fire(spawn_point: Node3D) -> void:
	if bullet_scene == null:
		push_warning("Weapon: bullet_scene not set on " + name)
		return

	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = spawn_point.global_transform
	bullet.fire(spawn_point.global_transform.basis * Vector3.FORWARD * -1)
