extends Node3D
class_name Bullet

@export var speed: float = 40.0
@export var gravity_scale: float = 0.3     # 0 = no gravity, 1 = full gravity
@export var max_range: float = 80.0        # despawn distance
@export var damage: float = 25.0

var _velocity: Vector3 = Vector3.ZERO
var _distance_traveled: float = 0.0
var _origin: Vector3 = Vector3.ZERO

signal hit_something(target, position, normal)


func _ready() -> void:
	_origin = global_position


func fire(direction: Vector3) -> void:
	_velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	# Apply gravity
	_velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_scale * delta

	var old_pos = global_position
	global_position += _velocity * delta
	_distance_traveled += old_pos.distance_to(global_position)

	# Despawn if out of range
	if _distance_traveled >= max_range:
		queue_free()
		return

	# Collision check with a shape cast or raycast
	_check_collision(old_pos, global_position)


func _check_collision(from: Vector3, to: Vector3) -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = []  # add shooter's RID here later to avoid self-hit

	var result = space.intersect_ray(query)
	if result:
		hit_something.emit(result.get("collider"), result.get("position"), result.get("normal"))
		_on_hit(result)
		queue_free()


func _on_hit(result: Dictionary) -> void:
	var collider = result.get("collider")
	if collider and collider.has_method("take_damage"):
		collider.take_damage(damage)
