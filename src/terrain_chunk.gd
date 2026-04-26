extends StaticBody3D

static var terrain_material: ShaderMaterial

var heightmap_data: PackedFloat32Array
var data_size: int = 256
var height_scale: float = 1.0
var visual_lod_step: int = 4
var collision_lod_step: int = 8
var chunk_origin: Vector2i = Vector2i.ZERO
var mesh_generated: bool = false
var mesh_lod_step: int = 0
var mesh_has_collision: bool = false
var mesh_is_horizon: bool = false
var mesh_instance: MeshInstance3D = null
var collision_shape: CollisionShape3D = null
var mesh_last_x: int = 255
var mesh_last_z: int = 255
var _local_only_sampling: bool = false
var ortho_path: String = ""
var _albedo_texture: Texture2D = null


func _init():
	collision_layer = 1
	collision_mask = 1


func setup(
	origin_x: int,
	origin_z: int,
	chunk_path: String,
	scale: float = 1.0,
	visual_step: int = 4,
	collision_step: int = 8,
	ortho_path_in: String = ""
):
	chunk_origin = Vector2i(origin_x, origin_z)
	name = "Chunk_%d_%d" % [origin_x, origin_z]
	height_scale = scale
	visual_lod_step = max(1, visual_step)
	collision_lod_step = max(1, collision_step)
	ortho_path = ortho_path_in

	if chunk_path.ends_with(".raw"):
		_load_raw(chunk_path)
	elif chunk_path.ends_with(".png"):
		_load_png(chunk_path)
	else:
		push_error("Unknown chunk format: " + chunk_path)


func _load_raw(raw_path: String):
	var file = FileAccess.open(raw_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open raw chunk: " + raw_path)
		return

	var byte_count = file.get_length()
	var float_count = int(byte_count / 4)
	data_size = int(round(sqrt(float(float_count))))

	var raw = file.get_buffer(byte_count)
	file.close()

	heightmap_data = PackedFloat32Array()
	heightmap_data.resize(float_count)
	for i in range(float_count):
		heightmap_data[i] = raw.decode_float(i * 4) * height_scale
	_scan_valid_extent()


func _load_png(png_path: String):
	var img = Image.new()
	var err = img.load(png_path)
	if err != OK:
		push_error("Failed to load PNG: " + png_path)
		return

	img.convert(Image.FORMAT_RH)
	data_size = img.get_width()

	heightmap_data = PackedFloat32Array()
	heightmap_data.resize(data_size * data_size)

	for z in range(data_size):
		for x in range(data_size):
			var h = img.get_pixel(x, z).r * 65535.0
			heightmap_data[z * data_size + x] = h * height_scale / 65535.0
	_scan_valid_extent()


func generate(lod_step: int = 0, with_collision: bool = true, horizon: bool = false):
	if heightmap_data.is_empty():
		return

	var step = lod_step if lod_step > 0 else visual_lod_step
	if (
		mesh_generated
		and mesh_lod_step == step
		and mesh_has_collision == with_collision
		and mesh_is_horizon == horizon
	):
		return

	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null
	if collision_shape:
		collision_shape.queue_free()
		collision_shape = null

	_local_only_sampling = horizon
	_generate_visual_mesh(step, with_collision)
	if with_collision:
		_generate_collision_shape()
	_local_only_sampling = false

	mesh_lod_step = step
	mesh_has_collision = with_collision
	mesh_is_horizon = horizon
	mesh_generated = true


func _generate_visual_mesh(step: int, casts_shadow: bool):
	var arrays = _build_grid_arrays(step, true)
	if arrays.is_empty():
		return

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _resolve_material(casts_shadow))

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(mesh_instance)


func _resolve_material(want_texture: bool) -> ShaderMaterial:
	if not want_texture or ortho_path.is_empty():
		return _get_terrain_material()

	if _albedo_texture == null:
		var img = Image.new()
		if img.load(ortho_path) == OK:
			_albedo_texture = ImageTexture.create_from_image(img)
	if _albedo_texture == null:
		return _get_terrain_material()

	var per_chunk: ShaderMaterial = _get_terrain_material().duplicate()
	per_chunk.set_shader_parameter("albedo_tex", _albedo_texture)
	per_chunk.set_shader_parameter("use_albedo_tex", true)
	per_chunk.set_shader_parameter("chunk_world_size", float(data_size - 1))
	return per_chunk


func _generate_collision_shape():
	var arrays = _build_grid_arrays(collision_lod_step, false)
	if arrays.is_empty():
		return

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shape = mesh.create_trimesh_shape()
	if shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.shape = shape
		add_child(collision_shape)


func clear_mesh():
	if mesh_instance:
		mesh_instance.queue_free()
		mesh_instance = null
	if collision_shape:
		collision_shape.queue_free()
		collision_shape = null
	mesh_generated = false
	mesh_lod_step = 0
	mesh_has_collision = false
	mesh_is_horizon = false


func build_world_triangles(step: int) -> Array:
	if heightmap_data.is_empty():
		return []
	_local_only_sampling = true
	var indexed = _build_grid_arrays(step, true)
	_local_only_sampling = false
	if indexed.is_empty():
		return []

	var verts: PackedVector3Array = indexed[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = indexed[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = indexed[Mesh.ARRAY_INDEX]

	var ox = float(chunk_origin.x)
	var oz = float(chunk_origin.y)

	var n = indices.size()
	var tri_verts = PackedVector3Array()
	var tri_normals = PackedVector3Array()
	tri_verts.resize(n)
	tri_normals.resize(n)

	for i in n:
		var idx = indices[i]
		var v = verts[idx]
		tri_verts[i] = Vector3(v.x + ox, v.y, v.z + oz)
		tri_normals[i] = normals[idx]

	return [tri_verts, tri_normals]


static func get_shared_material() -> ShaderMaterial:
	return _build_shared_material()


func _get_terrain_material() -> ShaderMaterial:
	return _build_shared_material()


static func _build_shared_material() -> ShaderMaterial:
	if terrain_material:
		return terrain_material

	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_color : source_color = vec4(0.32, 0.40, 0.22, 1.0);
uniform vec4 tundra_color : source_color = vec4(0.42, 0.43, 0.30, 1.0);
uniform vec4 rock_color : source_color = vec4(0.36, 0.34, 0.30, 1.0);
uniform vec4 cliff_color : source_color = vec4(0.22, 0.21, 0.20, 1.0);
uniform float low_height = 500.0;
uniform float high_height = 1300.0;
uniform float rock_slope_start = 0.30;
uniform float rock_slope_end = 0.65;
uniform float cliff_slope_start = 0.70;
uniform float cliff_slope_end = 0.90;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_albedo_tex = false;
uniform float chunk_world_size = 256.0;

varying vec3 v_albedo;
varying float v_roughness;
varying float v_ao;
varying vec2 v_uv;

void vertex() {
	float world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	float world_up_y = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	float slope = 1.0 - clamp(world_up_y, 0.0, 1.0);
	float elevation = smoothstep(low_height, high_height, world_height);
	float rock_mix = smoothstep(rock_slope_start, rock_slope_end, slope);
	float cliff_mix = smoothstep(cliff_slope_start, cliff_slope_end, slope);

	vec3 ground = mix(grass_color.rgb, tundra_color.rgb, elevation);
	vec3 base = mix(ground, rock_color.rgb, rock_mix);
	v_albedo = mix(base, cliff_color.rgb, cliff_mix);
	v_roughness = mix(0.95, 0.78, rock_mix);
	v_ao = mix(1.0, 0.85, slope);
	v_uv = vec2(VERTEX.x, VERTEX.z) / chunk_world_size;
}

void fragment() {
	ALBEDO = use_albedo_tex ? texture(albedo_tex, v_uv).rgb : v_albedo;
	ROUGHNESS = v_roughness;
	SPECULAR = 0.05;
	AO = v_ao;
}
"""

	terrain_material = ShaderMaterial.new()
	terrain_material.shader = shader
	return terrain_material


func _build_grid_arrays(step: int, with_normals: bool) -> Array:
	var grid_x = _axis_samples(mesh_last_x, step)
	var grid_z = _axis_samples(mesh_last_z, step)
	var w = grid_x.size()
	var h = grid_z.size()
	if w < 2 or h < 2:
		return []

	var vertices = PackedVector3Array()
	vertices.resize(w * h)
	var normals: PackedVector3Array
	if with_normals:
		normals = PackedVector3Array()
		normals.resize(w * h)

	for zi in range(h):
		var pz: int = grid_z[zi]
		for xi in range(w):
			var px: int = grid_x[xi]
			var idx = zi * w + xi
			vertices[idx] = Vector3(px, _sample_world_height(px, pz), pz)
			if with_normals:
				normals[idx] = _vertex_normal(px, pz)

	var indices = PackedInt32Array()
	indices.resize((w - 1) * (h - 1) * 6)
	var ti = 0
	for zi in range(h - 1):
		var row0 = zi * w
		var row1 = row0 + w
		for xi in range(w - 1):
			var i00 = row0 + xi
			var i10 = i00 + 1
			var i01 = row1 + xi
			var i11 = i01 + 1
			indices[ti] = i00; ti += 1
			indices[ti] = i10; ti += 1
			indices[ti] = i01; ti += 1
			indices[ti] = i10; ti += 1
			indices[ti] = i11; ti += 1
			indices[ti] = i01; ti += 1

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if with_normals:
		arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _axis_samples(last: int, step: int) -> PackedInt32Array:
	var result = PackedInt32Array()
	var v = 0
	while v < last:
		result.append(v)
		v = min(v + step, last)
	result.append(last)
	return result


func _vertex_normal(x: int, z: int) -> Vector3:
	var hl = _sample_world_height(x - 1, z)
	var hr = _sample_world_height(x + 1, z)
	var hd = _sample_world_height(x, z - 1)
	var hu = _sample_world_height(x, z + 1)
	return Vector3((hl - hr) * 0.5, 1.0, (hd - hu) * 0.5).normalized()


func _sample_world_height(x: int, z: int) -> float:
	if _local_only_sampling:
		return _h(x, z)
	if x >= 0 and x < data_size and z >= 0 and z < data_size:
		var h = heightmap_data[z * data_size + x]
		if h != 0.0:
			return h
		var neighbor_h = _query_neighbor_height(x, z)
		if not is_nan(neighbor_h) and neighbor_h != 0.0:
			return neighbor_h
		return h
	var oob = _query_neighbor_height(x, z)
	if not is_nan(oob):
		return oob
	return _h(x, z)


func _query_neighbor_height(x: int, z: int) -> float:
	var loader = get_parent()
	if loader and loader.has_method("sample_height_int"):
		return loader.sample_height_int(chunk_origin.x + x, chunk_origin.y + z, self)
	return NAN


func sample_height_int(x: int, z: int) -> float:
	if x < 0 or x >= data_size or z < 0 or z >= data_size:
		return NAN
	return heightmap_data[z * data_size + x]


func _scan_valid_extent():
	mesh_last_x = data_size - 1
	mesh_last_z = data_size - 1
	if heightmap_data.is_empty():
		return

	for x in range(data_size - 1, -1, -1):
		var has_data = false
		for z in range(data_size):
			if heightmap_data[z * data_size + x] != 0.0:
				has_data = true
				break
		if has_data:
			mesh_last_x = min(x + 1, data_size - 1)
			break
		mesh_last_x = x

	for z in range(data_size - 1, -1, -1):
		var has_data = false
		for x in range(data_size):
			if heightmap_data[z * data_size + x] != 0.0:
				has_data = true
				break
		if has_data:
			mesh_last_z = min(z + 1, data_size - 1)
			break
		mesh_last_z = z


func _h(x: int, z: int) -> float:
	x = clamp(x, 0, data_size - 1)
	z = clamp(z, 0, data_size - 1)
	return heightmap_data[z * data_size + x]


func get_height_at(local_x: float, local_z: float) -> float:
	var x0 = clamp(int(floor(local_x)), 0, data_size - 1)
	var z0 = clamp(int(floor(local_z)), 0, data_size - 1)
	var x1 = min(x0 + 1, data_size - 1)
	var z1 = min(z0 + 1, data_size - 1)

	var h00 = _h(x0, z0)
	var h10 = _h(x1, z0)
	var h01 = _h(x0, z1)
	var h11 = _h(x1, z1)

	var fx = clamp(local_x - x0, 0.0, 1.0)
	var fz = clamp(local_z - z0, 0.0, 1.0)

	var h0 = lerp(h00, h10, fx)
	var h1 = lerp(h01, h11, fx)

	return lerp(h0, h1, fz)
