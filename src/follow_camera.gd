extends Camera3D

@export var follow_distance: float = 15.0
@export var follow_height: float = 8.0
@export var follow_speed: float = 5.0
@export var look_ahead: float = 5.0

var target: Node3D

func _physics_process(delta):
	if not target:
		return
	
	var target_pos = target.global_position
	var behind_dir = -target.global_transform.basis.z
	behind_dir.y = 0
	behind_dir = behind_dir.normalized()
	
	var desired_pos = target_pos + behind_dir * follow_distance
	desired_pos.y = target_pos.y + follow_height
	
	global_position = global_position.lerp(desired_pos, follow_speed * delta)
	
	var look_target = target_pos + target.global_transform.basis.z * look_ahead
	look_at(look_target)
