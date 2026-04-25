extends CharacterBody3D

## Physics-based skiing/snowboarding controller
## Inspired by Steep's feel: gravity-based, edge control, carving

@export_group("Movement")
@export var max_speed: float = 40.0  # m/s (about 144 km/h, realistic for downhill)
@export var turn_speed: float = 3.0  # How fast the skier can turn
@export var edge_control_power: float = 2.0  # How much edge control affects direction
@export var friction_snow: float = 0.02  # Low friction on snow
@export var friction_ice: float = 0.005  # Even lower on ice
@export var air_resistance: float = 0.3  # Air drag at high speeds

@export_group("Physics")
@export var gravity: float = 9.8
@export var slope_gravity_multiplier: float = 1.5  # Extra pull down steep slopes
@export var jump_force: float = 8.0
@export var mass: float = 70.0  # kg

@export_group("State")
@export var is_snowboard: bool = false  # Snowboard vs skis (affects turning)

# Internal state
var velocity_3d: Vector3 = Vector3.ZERO
var forward_direction: Vector3 = Vector3.FORWARD
var is_grounded: bool = false
var is_jumping: bool = false
var is_carving: bool = false
var edge_angle: float = 0.0  # -1 (left edge) to 1 (right edge)
var current_speed: float = 0.0
var terrain_normal: Vector3 = Vector3.UP

# Component references
@onready var terrain_loader = get_node_or_null("/root/Main/TerrainLoader")
@onready var mesh = $SkierMesh
@onready var ground_check = $GroundCheck

enum State {
	SKIING,
	JUMPING,
	TRICKING,
	CRASHED,
	RAGDOLL
}

var current_state: State = State.SKIING

func _ready():
	add_to_group("player")
	
	# Initial position check
	if terrain_loader:
		var height = terrain_loader.get_terrain_height(global_position)
		global_position.y = height + 1.0

func _physics_process(delta):
	match current_state:
		State.SKIING:
			_process_skiing(delta)
		State.JUMPING:
			_process_jumping(delta)
		State.TRICKING:
			_process_tricking(delta)
		State.CRASHED, State.RAGDOLL:
			_process_ragdoll(delta)
	
	# Update animation/visuals
	_update_visuals(delta)

func _process_skiing(delta):
	# Check if grounded
	_update_ground_state()
	
	# Get input
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var turn_input = input_dir.x
	var lean_input = input_dir.y
	
	# Calculate slope and terrain
	var slope_direction = _calculate_slope_direction()
	var slope_angle = slope_direction.angle_to(Vector3.UP)
	
	# Apply gravity down the slope
	if is_grounded:
		# Gravity pulls down the slope
		var gravity_force = slope_direction * gravity * slope_gravity_multiplier * mass
		velocity_3d += gravity_force * delta / mass
		
		# Edge control - carving
		if abs(turn_input) > 0.1:
			is_carving = true
			edge_angle = clamp(turn_input, -1.0, 1.0)
			
			# Carving redirects velocity
			var carve_direction = _calculate_carve_direction(turn_input)
			velocity_3d = velocity_3d.lerp(carve_direction * velocity_3d.length(), 
				edge_control_power * delta * abs(turn_input))
		else:
			is_carving = false
			edge_angle = lerp(edge_angle, 0.0, 5.0 * delta)
		
		# Ground friction
		velocity_3d *= (1.0 - friction_snow)
		
		# Align velocity with slope
		velocity_3d = velocity_3d.slide(terrain_normal)
	else:
		# Air physics
		velocity_3d.y -= gravity * delta
		velocity_3d *= (1.0 - air_resistance * delta)
		
		# Air steering
		if abs(turn_input) > 0.1:
			var air_turn = Vector3.UP.cross(forward_direction) * turn_input * 2.0 * delta
			velocity_3d += air_turn
	
	# Air resistance at high speeds
	var speed = velocity_3d.length()
	if speed > 20.0:
		var drag = air_resistance * (speed - 20.0) / 20.0 * delta
		velocity_3d *= (1.0 - drag)
	
	# Limit max speed
	if velocity_3d.length() > max_speed:
		velocity_3d = velocity_3d.normalized() * max_speed
	
	# Apply movement
	velocity = velocity_3d
	move_and_slide()
	
	# Update velocity from collision response
	velocity_3d = velocity
	
	# Update forward direction based on velocity
	if velocity_3d.length() > 0.5:
		forward_direction = velocity_3d.normalized()
		forward_direction.y = 0
		forward_direction = forward_direction.normalized()
	
	current_speed = velocity_3d.length()
	
	# Jump input
	if Input.is_action_just_pressed("jump") and is_grounded:
		_jump()
	
	# Check for crash
	if _should_crash():
		_crash()

func _process_jumping(delta):
	# Air physics
	velocity_3d.y -= gravity * delta
	velocity_3d *= (1.0 - air_resistance * delta)
	
	# Air control
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	if abs(input_dir.x) > 0.1:
		# Spin/rotate in air
		rotate_y(-input_dir.x * 2.0 * delta)
		
	if abs(input_dir.y) > 0.1:
		# Pitch control
		var pitch_axis = transform.basis.x
		velocity_3d += pitch_axis * input_dir.y * 5.0 * delta
	
	velocity = velocity_3d
	move_and_slide()
	velocity_3d = velocity
	
	# Check landing
	_update_ground_state()
	if is_grounded and velocity_3d.y < 0:
		_land()

func _process_tricking(delta):
	# Tricks handled by trick system
	pass

func _process_ragdoll(delta):
	# Physics handled by ragdoll
	pass

func _update_ground_state():
	ground_check.force_raycast_update()
	
	if ground_check.is_colliding():
		var collision_point = ground_check.get_collision_point()
		var distance = global_position.y - collision_point.y
		
		is_grounded = distance < 0.3
		terrain_normal = ground_check.get_collision_normal()
	else:
		is_grounded = false
		terrain_normal = Vector3.UP

func _calculate_slope_direction() -> Vector3:
	"""Calculate which direction gravity pulls on this slope."""
	if terrain_normal == Vector3.UP:
		return Vector3.DOWN
	
	# Project gravity onto the terrain plane
	var gravity_vec = Vector3.DOWN * gravity
	var slope_dir = gravity_vec.slide(terrain_normal)
	
	if slope_dir.length() < 0.01:
		return Vector3.DOWN
	
	return slope_dir.normalized()

func _calculate_carve_direction(turn_input: float) -> Vector3:
	"""Calculate the direction to carve based on input."""
	# Carve direction is perpendicular to velocity, on the slope plane
	var turn_axis = terrain_normal
	var turn_angle = turn_input * turn_speed * 0.5
	
	# Rotate forward direction around terrain normal
	return forward_direction.rotated(turn_axis, turn_angle)

func _jump():
	is_jumping = true
	current_state = State.JUMPING
	velocity_3d.y = jump_force
	
	# Add forward momentum
	velocity_3d += forward_direction * 2.0

func _land():
	is_jumping = false
	current_state = State.SKIING
	
	# Check landing quality
	var impact_speed = -velocity_3d.y
	var landing_angle = abs(velocity_3d.angle_to(terrain_normal) - PI/2)
	
	if impact_speed > 15.0 or landing_angle > 1.0:
		# Hard landing
		_crash()

func _crash():
	current_state = State.CRASHED
	velocity_3d *= 0.5
	
	# TODO: Trigger ragdoll
	print("CRASH! Speed: %.1f" % current_speed)
	
	# Recover after delay
	await get_tree().create_timer(2.0).timeout
	_recover()

func _recover():
	current_state = State.SKIING
	velocity_3d = Vector3.ZERO
	
	# Reset position slightly above ground
	if terrain_loader:
		var height = terrain_loader.get_terrain_height(global_position)
		global_position.y = height + 1.0

func _should_crash() -> bool:
	"""Check if current conditions should trigger a crash."""
	# Crash if hitting something at high speed with bad angle
	var collision = get_last_slide_collision()
	if collision:
		var collision_angle = velocity_3d.angle_to(collision.get_normal())
		if current_speed > 15.0 and collision_angle < 0.5:
			return true
	
	return false

func _update_visuals(delta):
	# Rotate mesh to face movement direction
	if mesh and velocity_3d.length() > 0.1:
		var target_rotation = atan2(forward_direction.x, forward_direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_rotation, 10.0 * delta)
		
		# Lean into turns
		if is_carving:
			var lean_angle = edge_angle * 0.5
			mesh.rotation.z = lerp(mesh.rotation.z, lean_angle, 5.0 * delta)
		else:
			mesh.rotation.z = lerp(mesh.rotation.z, 0.0, 5.0 * delta)

func get_speed_kmh() -> float:
	return current_speed * 3.6  # Convert m/s to km/h
