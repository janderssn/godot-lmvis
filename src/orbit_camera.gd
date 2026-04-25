extends Node3D

## Drone orbit camera - flies around the mountain to showcase terrain

@export var center_point: Vector3 = Vector3(1250, 0, 1250)
@export var orbit_radius: float = 800.0
@export var orbit_height: float = 600.0
@export var orbit_speed: float = 0.02

var angle: float = 0.0

func _ready():
	_update_position()
	print("Camera ready at: %s" % str(global_position))

func _process(delta):
	angle += orbit_speed * delta
	if angle > TAU:
		angle -= TAU
	
	_update_position()

func _update_position():
	var x = center_point.x + cos(angle) * orbit_radius
	var z = center_point.z + sin(angle) * orbit_radius
	var y = center_point.y + orbit_height
	
	global_position = Vector3(x, y, z)
	look_at(center_point)

func set_center(pos: Vector3):
	center_point = pos
