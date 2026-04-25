extends Node3D

## Simple terrain test using Godot's HeightMap

func _ready():
	print("Loading heightmap...")
	
	# Load heightmap image
	var image = Image.load_from_file("res://terrain_data/processed/70275_4000_25/chunk_0000_0000.png")
	if image == null:
		print("ERROR: Could not load heightmap")
		return
	
	print("Loaded heightmap: %dx%d" % [image.get_width(), image.get_height()])
	
	# Create terrain mesh using Godot's heightmap approach
	var terrain = _create_terrain_from_image(image)
	terrain.position = Vector3(0, 0, 0)
	add_child(terrain)
	
	# Add a marker cube at terrain center
	var marker = MeshInstance3D.new()
	marker.mesh = BoxMesh.new()
	marker.mesh.size = Vector3(20, 20, 20)
	marker.position = Vector3(128, 200, 128)  # Center of 256x256 chunk, elevated
	add_child(marker)
	
	# Position camera to see both
	$Camera3D.position = Vector3(400, 500, 400)
	$Camera3D.look_at(Vector3(128, 100, 128))
	
	print("Terrain created at origin")

func _create_terrain_from_image(image: Image) -> MeshInstance3D:
	var width = image.get_width()
	var height = image.get_height()
	var height_scale = 150.0
	
	# Create array mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	
	# Generate vertices
	for z in range(height):
		for x in range(width):
			var pixel = image.get_pixel(x, z)
			var h = pixel.r * height_scale
			vertices.append(Vector3(x, h, z))
			uvs.append(Vector2(float(x) / width, float(z) / height))
			normals.append(Vector3.UP)  # Simplified normals
	
	# Generate indices for triangles
	for z in range(height - 1):
		for x in range(width - 1):
			var i = z * width + x
			
			# First triangle
			indices.append(i)
			indices.append(i + width)
			indices.append(i + 1)
			
			# Second triangle
			indices.append(i + 1)
			indices.append(i + width)
			indices.append(i + width + 1)
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	# Create mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 1.0)  # Snow white
	material.roughness = 0.9
	array_mesh.surface_set_material(0, material)
	
	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	return mesh_instance

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
