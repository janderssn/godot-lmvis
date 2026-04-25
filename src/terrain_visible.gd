extends Node3D

## Terrain test with orbit camera controls

var camera_angle: float = 0.0
var camera_height: float = 400.0
var camera_distance: float = 400.0
var rotation_speed: float = 1.0

func _ready():
	print("Terrain loaded! Use A/D to rotate, W/S for height, Q/E for distance")
	_update_camera()

func _input(event):
	# Camera controls
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		camera_angle -= 0.2
		_update_camera()
	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		camera_angle += 0.2
		_update_camera()
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		camera_height += 50
		_update_camera()
	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		camera_height -= 50
		_update_camera()
	
	# Distance controls
	if event.is_action_pressed("ui_page_up"):
		camera_distance -= 50
		_update_camera()
	if event.is_action_pressed("ui_page_down"):
		camera_distance += 50
		_update_camera()
	
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _update_camera():
	var cam = $Camera3D
	var center = Vector3(128, 50, 128)  # Center of terrain
	
	# Calculate camera position
	var x = center.x + cos(camera_angle) * camera_distance
	var z = center.z + sin(camera_angle) * camera_distance
	var y = camera_height
	
	cam.position = Vector3(x, y, z)
	cam.look_at(center)

func _process(delta):
	# Auto-rotate slowly
	if Input.is_action_pressed("ui_select"):  # Space
		camera_angle += rotation_speed * delta
		_update_camera()
