extends Node3D

## Debug scene - loads a single chunk at origin to verify rendering

func _ready():
	print("Debug: Loading single chunk...")
	
	# Load a single chunk image
	var chunk_path = "res://terrain_data/processed/70275_4000_25/chunk_0000_0000.png"
	var image = Image.new()
	var error = image.load(chunk_path)
	
	if error != OK:
		print("ERROR: Could not load chunk image!")
		return
	
	print("Loaded image: %dx%d" % [image.get_width(), image.get_height()])
	
	# Create a simple test cube to verify rendering works
	var cube = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(100, 100, 100)
	cube.mesh = box_mesh
	cube.position = Vector3(0, 500, 0)
	add_child(cube)
	print("Added test cube at (0, 500, 0)")
	
	# Create terrain chunk
	var chunk = preload("res://src/terrain_chunk.gd").new()
	chunk.setup(0, 0, image, 150.0)
	chunk.position = Vector3(0, 0, 0)
	add_child(chunk)
	chunk.generate()
	print("Generated terrain chunk at origin")
	
	# Position camera to see the chunk
	$Camera.position = Vector3(500, 800, 500)
	$Camera.look_at(Vector3(0, 0, 0))
	print("Camera at: %s" % str($Camera.position))

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
