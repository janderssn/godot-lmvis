extends Camera3D

enum CameraMode {
	ORBIT,
	FLY,
}

@export_group("Orbit")
@export var orbit_radius: float = 850.0
@export var orbit_height: float = 260.0
@export var orbit_speed: float = 0.14
@export var auto_orbit: bool = true
@export var orbit_zoom_speed: float = 450.0
@export var orbit_height_speed: float = 240.0

@export_group("Fly")
@export var fly_speed: float = 220.0
@export var fly_boost_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.003

var mode: CameraMode = CameraMode.ORBIT
var orbit_center: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var fly_yaw: float = 0.0
var fly_pitch: float = deg_to_rad(-18.0)


func _ready():
	current = true
	_update_orbit_camera()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_mode()
		get_viewport().set_input_as_handled()
		return

	if InputMap.has_action("camera_toggle_mode") and event.is_action_pressed("camera_toggle_mode"):
		_toggle_mode()
		get_viewport().set_input_as_handled()
		return

	if mode == CameraMode.FLY and event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		fly_yaw -= event.relative.x * mouse_sensitivity
		fly_pitch = clamp(
			fly_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)
		rotation = Vector3(fly_pitch, fly_yaw, 0.0)
	elif mode == CameraMode.FLY and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("ui_cancel") and mode == CameraMode.FLY:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(delta):
	if mode == CameraMode.ORBIT:
		_update_orbit(delta)
	else:
		_update_fly(delta)


func set_orbit_center(center: Vector3):
	orbit_center = center
	if mode == CameraMode.ORBIT:
		_update_orbit_camera()


func snap_to_orbit():
	_update_orbit_camera()


func set_orbit_angle(angle: float):
	orbit_angle = angle
	if mode == CameraMode.ORBIT:
		_update_orbit_camera()


func get_stream_focus_position() -> Vector3:
	if mode == CameraMode.ORBIT:
		return orbit_center

	return global_position


func _toggle_mode():
	if mode == CameraMode.ORBIT:
		mode = CameraMode.FLY
		var euler = basis.get_euler()
		fly_pitch = euler.x
		fly_yaw = euler.y
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		mode = CameraMode.ORBIT
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_update_orbit_camera()


func _update_orbit(delta: float):
	var orbit_input = Input.get_axis("move_left", "move_right")
	var zoom_input = Input.get_axis("move_back", "move_forward")
	var height_input = 0.0
	if Input.is_action_pressed("jump"):
		height_input += 1.0
	if Input.is_action_pressed("brake"):
		height_input -= 1.0

	if auto_orbit:
		orbit_angle += orbit_speed * delta

	orbit_angle += orbit_input * orbit_speed * 2.2 * delta
	orbit_radius = clamp(orbit_radius - zoom_input * orbit_zoom_speed * delta, 250.0, 2400.0)
	orbit_height = clamp(orbit_height + height_input * orbit_height_speed * delta, 80.0, 1400.0)

	_update_orbit_camera()


func _update_orbit_camera():
	var x = orbit_center.x + cos(orbit_angle) * orbit_radius
	var z = orbit_center.z + sin(orbit_angle) * orbit_radius
	var y = orbit_center.y + orbit_height

	global_position = Vector3(x, y, z)
	look_at(orbit_center)


func _update_fly(delta: float):
	rotation = Vector3(fly_pitch, fly_yaw, 0.0)

	var movement = Vector3.ZERO
	movement += -global_transform.basis.z * Input.get_axis("move_back", "move_forward")
	movement += global_transform.basis.x * Input.get_axis("move_left", "move_right")

	if Input.is_action_pressed("jump"):
		movement += Vector3.UP
	if Input.is_action_pressed("brake"):
		movement += Vector3.DOWN

	if movement.length() > 1.0:
		movement = movement.normalized()

	var speed = fly_speed
	if Input.is_key_pressed(KEY_CTRL) or (
		InputMap.has_action("camera_boost") and Input.is_action_pressed("camera_boost")
	):
		speed *= fly_boost_multiplier

	global_position += movement * speed * delta
