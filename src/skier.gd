extends CharacterBody3D

@export var max_speed: float = 50.0
@export var acceleration: float = 15.0
@export var brake_force: float = 20.0
@export var turn_speed: float = 3.0
@export var jump_force: float = 12.0
@export var gravity: float = 25.0
@export var air_control: float = 0.3

var current_speed: float = 0.0
var is_grounded: bool = true
var terrain_loader: Node

func _ready():
	terrain_loader = get_tree().current_scene.get_node("TerrainLoader")

func _physics_process(delta):
	var input_dir = Vector3.ZERO
	
	if Input.is_action_pressed("steer_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("steer_right"):
		input_dir.x += 1
	if Input.is_action_pressed("brake"):
		input_dir.z -= 1
	
	if is_grounded:
		_apply_ground_physics(delta, input_dir)
	else:
		_apply_air_physics(delta, input_dir)
	
	if Input.is_action_just_pressed("jump") and is_grounded:
		velocity.y = jump_force
		is_grounded = false
	
	move_and_slide()
	
	_update_grounded_state()

func _apply_ground_physics(delta: float, input_dir: Vector3):
	var slope_dir = _get_slope_direction()
	var slope_angle = acos(clamp(-slope_dir.y, -1.0, 1.0))
	var slope_steepness = sin(slope_angle)
	
	var forward = -global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var gravity_accel = slope_steepness * gravity * 0.5
	velocity += slope_dir * gravity_accel * delta
	
	if input_dir.x != 0:
		rotate_y(-input_dir.x * turn_speed * delta)
	
	if input_dir.z < 0:
		current_speed = max(0, current_speed - brake_force * delta)
	
	current_speed = min(current_speed + acceleration * delta * slope_steepness, max_speed)
	
	var ground_vel = velocity
	ground_vel.y = 0
	var current_ground_speed = ground_vel.length()
	
	if current_ground_speed < current_speed:
		velocity += forward * acceleration * delta
	
	velocity.y -= gravity * delta * 0.1

func _apply_air_physics(delta: float, input_dir: Vector3):
	velocity.y -= gravity * delta
	
	if input_dir.x != 0:
		rotate_y(-input_dir.x * turn_speed * air_control * delta)

func _get_slope_direction() -> Vector3:
	if not terrain_loader:
		return Vector3(0, -1, 0)
	
	var pos = global_position
	var height = terrain_loader.get_height_at_position(pos)
	
	var check_dist = 5.0
	var height_right = terrain_loader.get_height_at_position(pos + Vector3(check_dist, 0, 0))
	var height_forward = terrain_loader.get_height_at_position(pos + Vector3(0, 0, check_dist))
	
	var slope_x = (height_right - height) / check_dist
	var slope_z = (height_forward - height) / check_dist
	
	return Vector3(-slope_x, -1, -slope_z).normalized()

func _update_grounded_state():
	if is_on_floor():
		is_grounded = true
		return
	
	var ground_height = terrain_loader.get_height_at_position(global_position) if terrain_loader else 0
	if global_position.y <= ground_height + 1.0:
		is_grounded = true
		global_position.y = ground_height + 1.0
		velocity.y = max(0, velocity.y)

func spawn_at_position(pos: Vector3):
	global_position = pos
	if terrain_loader:
		var ground_height = terrain_loader.get_height_at_position(pos)
		global_position.y = ground_height + 2.0
	velocity = Vector3.ZERO
	current_speed = 0.0
	is_grounded = true
