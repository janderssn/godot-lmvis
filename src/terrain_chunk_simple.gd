extends StaticBody3D

## A single terrain chunk

@export var chunk_size: int = 256
@export var world_size: float = 256.0
@export var height_scale: float = 150.0

var heightmap_image: Image
var heightmap_data: PackedFloat32Array

var chunk_x: int = 0
var chunk_z: int = 0

func _init():
	collision_layer = 1

func setup(x: int, z: int, image: Image, scale: float = 150.0):
	chunk_x = x
	chunk_z = z
	heightmap_image = image
	height_scale = scale
	name = "Chunk_%d_%d" % [x, z]

func generate():
	if heightmap_image == null:
		push_error("No heightmap image set")
		return
	
	var width = heightmap_image.get_width()
	var height = heightmap_image.get_height()
	
	# Create mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(world_size, world_size)
	plane_mesh.subdivide_width = width - 2
	plane_mesh.subdivide_depth = height - 2
	
	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.9, 0.95)
	material.roughness = 0.8
	plane_mesh.material = material
	
	# Create mesh instance
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = plane_mesh
	mesh_instance.cast_shadow = GeometryShape3D.SHADOW_CASTING_SETTING_ON
	
	# Apply height data using a shader or displacement
	# For now, just add it flat
	add_child(mesh_instance)
	
	# Create collision
	_create_collision()
	
	print("Generated chunk at %s with size %s" % [str(global_position), str(world_size)])

func _create_collision():
	var collision = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(world_size, 10, world_size)
	collision.shape = box_shape
	collision.position.y = 5
	add_child(collision)

func get_height_at_world(world_pos: Vector3) -> float:
	return 0.0
