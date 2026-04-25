extends Node3D

const ARESKUTAN_TOPPSTUGAN_SWEREF := Vector2(404867.81423292926, 7035230.670129072)

@onready var terrain_loader = $TerrainLoader
@onready var camera = $Camera


func _ready():
	var focus = terrain_loader.sweref_to_local(
		ARESKUTAN_TOPPSTUGAN_SWEREF.x,
		ARESKUTAN_TOPPSTUGAN_SWEREF.y
	)
	if focus == Vector3.ZERO:
		focus = terrain_loader.get_default_focus_position()

	terrain_loader.start_streaming(focus)

	focus.y = terrain_loader.get_height_at_position(focus)
	camera.set_orbit_center(focus)
	camera.set_orbit_angle(deg_to_rad(210.0))
	camera.snap_to_orbit()

	terrain_loader.set_stream_focus(camera.get_stream_focus_position())

	print("Åre terrain foundation scene")
	print("Orbiting Åreskutan / Toppstugan at SWEREF E %.3f N %.3f" % [
		ARESKUTAN_TOPPSTUGAN_SWEREF.x,
		ARESKUTAN_TOPPSTUGAN_SWEREF.y
	])
	print("Controls:")
	print("  TAB        Toggle orbit / fly camera")
	print("  W/S        Orbit zoom or fly forward/back")
	print("  A/D        Orbit rotation or fly strafe")
	print("  SPACE/SHIFT Orbit height or fly up/down")
	print("  CTRL       Fly boost")
	print("  Mouse      Look around in fly mode")


func _process(_delta):
	terrain_loader.set_stream_focus(camera.get_stream_focus_position())
