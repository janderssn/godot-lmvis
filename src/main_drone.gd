extends Node3D

@onready var terrain_loader = $TerrainLoader
@onready var camera = $Camera

func _ready():
	print("Åre Steep - Drone Camera Mode")
	print("")
	print("Controls:")
	print("  W/S - Camera height")
	print("  A/D - Camera distance")
	print("  SPACE - Speed up")
	print("  SHIFT - Slow down")
	print("  ESC - Quit")
	print("")
	print("Terrain loading...")

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	
	if event.is_action_pressed("move_forward"):
		camera.orbit_height += 50
	if event.is_action_pressed("move_back"):
		camera.orbit_height -= 50
	
	if event.is_action_pressed("move_left"):
		camera.orbit_radius -= 100
	if event.is_action_pressed("move_right"):
		camera.orbit_radius += 100
	
	if event.is_action_pressed("jump"):
		camera.orbit_speed = min(camera.orbit_speed + 0.01, 0.2)
	if event.is_action_pressed("brake"):
		camera.orbit_speed = max(camera.orbit_speed - 0.01, 0.0)
