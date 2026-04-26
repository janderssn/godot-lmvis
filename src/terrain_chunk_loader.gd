extends Node3D

signal terrain_ready

@export var height_directory: String = "res://terrain_data/raw_height"
@export var ortho_directory: String = ""
@export var super_near_load_radius: int = 2
@export var load_radius: int = 6
@export var far_load_radius: int = 24
@export var horizon_load_radius: int = 60
@export var unload_radius: int = 64
@export var chunk_size: int = 256
@export var overlap: int = 1
@export var height_scale: float = 1.0
@export var super_near_visual_lod_step: int = 2
@export var visual_lod_step: int = 4
@export var far_visual_lod_step: int = 16
@export var horizon_visual_lod_step: int = 64
@export var collision_lod_step: int = 8
@export var max_data_loads_per_frame: int = 16
@export var max_mesh_gens_per_frame: int = 4

var chunk_step: int = 255
var loaded_chunks: Dictionary = {}
var chunk_index: Dictionary = {}
var chunk_entries: Array[Dictionary] = []
var spatial_index: Dictionary = {}
var dataset_manifest: Dictionary = {}
var default_focus_position: Vector3 = Vector3.ZERO

var streaming_enabled: bool = false
var has_emitted_ready: bool = false
var stream_focus_position: Vector3 = Vector3.ZERO

var _cached_desired_meshes: Dictionary = {}
var _cached_desired_data: Dictionary = {}
var _cached_focus_2d: Vector2 = Vector2(INF, INF)
var _desired_dirty: bool = true

var _horizon_origins: Dictionary = {}
var _horizon_chunk_arrays: Dictionary = {}
var _horizon_mesh_instance: MeshInstance3D = null
var _horizon_mesh_dirty: bool = false
var _horizon_thread: Thread = null

@export var max_horizon_builds_per_frame: int = 32

const TerrainChunk = preload("res://src/terrain_chunk.gd")


func _ready():
	chunk_step = chunk_size - overlap
	_load_dataset_manifest()
	_load_all_manifests()
	_derive_default_focus()


func _exit_tree():
	if _horizon_thread and _horizon_thread.is_started():
		_horizon_thread.wait_to_finish()
		_horizon_thread = null


func _process(_delta):
	if not streaming_enabled:
		return

	_stream_around_position(stream_focus_position, false)

	if not has_emitted_ready:
		has_emitted_ready = true
		terrain_ready.emit()


func start_streaming(initial_focus: Vector3):
	stream_focus_position = initial_focus
	streaming_enabled = true
	_stream_around_position(stream_focus_position, true)
	print("Terrain streaming started around %s with %d chunks loaded" % [str(initial_focus), loaded_chunks.size()])

	if not has_emitted_ready:
		has_emitted_ready = true
		terrain_ready.emit()


func set_stream_focus(pos: Vector3):
	stream_focus_position = pos

	if streaming_enabled:
		_stream_around_position(stream_focus_position, false)


func get_default_focus_position() -> Vector3:
	return default_focus_position


func get_stats() -> Dictionary:
	return {
		"loaded": loaded_chunks.size(),
		"horizon_origins": _horizon_origins.size(),
		"horizon_arrays": _horizon_chunk_arrays.size(),
		"indexed": chunk_index.size(),
	}


func sweref_to_local(easting: float, northing: float) -> Vector3:
	if dataset_manifest.is_empty():
		return Vector3.ZERO

	return Vector3(
		easting - float(dataset_manifest.get("origin_easting", 0.0)),
		0.0,
		float(dataset_manifest.get("max_northing", 0.0)) - northing
	)


func get_height_at_position(pos: Vector3) -> float:
	_ensure_chunk_loaded(pos)

	var origin = _find_containing_chunk_origin(pos)
	if not loaded_chunks.has(origin):
		return 0.0

	var chunk = loaded_chunks[origin]
	var local_x = pos.x - origin.x
	var local_z = pos.z - origin.y
	return chunk.get_height_at(local_x, local_z)


func _load_dataset_manifest():
	var manifest_path = height_directory.path_join("dataset_manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return

	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		dataset_manifest = json.data


func _load_all_manifests():
	var dir = DirAccess.open(height_directory)
	if dir == null:
		push_error("Could not open terrain directory: " + height_directory)
		return

	chunk_index.clear()
	chunk_entries.clear()

	dir.list_dir_begin()
	var folder = dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var manifest_path = height_directory.path_join(folder).path_join("chunks_manifest.json")
			if FileAccess.file_exists(manifest_path):
				_load_manifest(manifest_path, folder)
		folder = dir.get_next()

	_build_spatial_index()
	print("Indexed %d terrain chunks" % chunk_index.size())


func _build_spatial_index():
	spatial_index.clear()
	for entry in chunk_entries:
		var origin: Vector2i = entry["origin"]
		var min_cx = _cell_coord(origin.x)
		var min_cz = _cell_coord(origin.y)
		var max_cx = _cell_coord(origin.x + chunk_size - 1)
		var max_cz = _cell_coord(origin.y + chunk_size - 1)
		for cz in range(min_cz, max_cz + 1):
			for cx in range(min_cx, max_cx + 1):
				var cell = Vector2i(cx, cz)
				if not spatial_index.has(cell):
					spatial_index[cell] = []
				spatial_index[cell].append(origin)


func _cell_coord(world_v: int) -> int:
	return int(floor(float(world_v) / float(chunk_size)))


func _load_manifest(manifest_path: String, tile_folder: String):
	var file = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return

	for chunk_data in json.data.get("chunks", []):
		chunk_data["tile_folder"] = tile_folder
		var origin = _compute_chunk_origin(tile_folder, String(chunk_data["file"]))
		chunk_index[origin] = chunk_data
		chunk_entries.append({
			"origin": origin,
			"center": Vector2(
				float(origin.x) + chunk_size * 0.5,
				float(origin.y) + chunk_size * 0.5
			),
		})


func _derive_default_focus():
	if dataset_manifest.has("origin_easting") and dataset_manifest.has("max_easting") and dataset_manifest.has("origin_northing") and dataset_manifest.has("max_northing"):
		default_focus_position = Vector3(
			(float(dataset_manifest.get("max_easting", 0.0)) - float(dataset_manifest.get("origin_easting", 0.0))) * 0.5,
			0.0,
			(float(dataset_manifest.get("max_northing", 0.0)) - float(dataset_manifest.get("origin_northing", 0.0))) * 0.5
		)
		return

	if chunk_index.is_empty():
		default_focus_position = Vector3.ZERO
		return

	var min_x = INF
	var min_z = INF
	var max_x = -INF
	var max_z = -INF

	for origin in chunk_index.keys():
		min_x = min(min_x, origin.x)
		min_z = min(min_z, origin.y)
		max_x = max(max_x, origin.x + chunk_step)
		max_z = max(max_z, origin.y + chunk_step)

	default_focus_position = Vector3(
		(min_x + max_x) * 0.5,
		0.0,
		(min_z + max_z) * 0.5
	)


func _stream_around_position(pos: Vector3, bulk: bool):
	var focus_2d = Vector2(pos.x, pos.z)
	var unload_distance = float(unload_radius * chunk_step + chunk_size)
	var unload_dist_sq = unload_distance * unload_distance
	var recompute_threshold_sq = float(chunk_size) * float(chunk_size) * 0.25

	if (
		bulk
		or _desired_dirty
		or (focus_2d - _cached_focus_2d).length_squared() > recompute_threshold_sq
	):
		_recompute_desired(focus_2d)
		_cached_focus_2d = focus_2d
		_desired_dirty = false

	var desired_meshes = _cached_desired_meshes
	var desired_data = _cached_desired_data

	var data_budget = 999999 if bulk else max_data_loads_per_frame
	for origin in desired_data:
		if data_budget <= 0:
			break
		if not loaded_chunks.has(origin):
			_load_chunk_data(origin)
			data_budget -= 1

	var mesh_budget = 999999 if bulk else max_mesh_gens_per_frame
	for origin in desired_meshes:
		if mesh_budget <= 0:
			break
		if not loaded_chunks.has(origin):
			continue
		var chunk = loaded_chunks[origin]
		var params = desired_meshes[origin]
		var step: int = params["lod"]
		var collision: bool = params["collision"]
		var horizon: bool = params["horizon"]

		if horizon:
			if chunk.mesh_generated:
				chunk.clear_mesh()
				_horizon_mesh_dirty = true
			if not _horizon_origins.has(origin):
				_horizon_origins[origin] = true
				_horizon_mesh_dirty = true
			continue

		if _horizon_origins.has(origin):
			_horizon_origins.erase(origin)
			_horizon_mesh_dirty = true

		if (
			chunk.mesh_generated
			and chunk.mesh_lod_step == step
			and chunk.mesh_has_collision == collision
			and not chunk.mesh_is_horizon
		):
			continue
		if not _neighbors_data_loaded(origin):
			continue
		chunk.generate(step, collision, false)
		mesh_budget -= 1

	for origin in _horizon_origins.keys():
		if not desired_meshes.has(origin) or not desired_meshes[origin]["horizon"]:
			_horizon_origins.erase(origin)
			_horizon_mesh_dirty = true

	for origin in _horizon_chunk_arrays.keys():
		if not _horizon_origins.has(origin) or not loaded_chunks.has(origin):
			_horizon_chunk_arrays.erase(origin)
			_horizon_mesh_dirty = true

	var build_budget = 999999 if bulk else max_horizon_builds_per_frame
	for origin in _horizon_origins.keys():
		if build_budget <= 0:
			break
		if _horizon_chunk_arrays.has(origin):
			continue
		if not loaded_chunks.has(origin):
			continue
		var chunk = loaded_chunks[origin]
		var arrays = chunk.build_world_triangles(horizon_visual_lod_step)
		if arrays.is_empty():
			continue
		_horizon_chunk_arrays[origin] = arrays
		_horizon_mesh_dirty = true
		build_budget -= 1

	if _horizon_thread and not _horizon_thread.is_alive():
		var result: Array = _horizon_thread.wait_to_finish()
		_horizon_thread = null
		_apply_horizon_rebuild(result)

	if _horizon_mesh_dirty and _horizon_thread == null:
		_horizon_mesh_dirty = false
		_kick_horizon_rebuild(bulk)

	var stale_origins: Array[Vector2i] = []
	for origin in loaded_chunks.keys():
		if desired_data.has(origin):
			continue
		var dx = float(origin.x) + chunk_size * 0.5 - focus_2d.x
		var dz = float(origin.y) + chunk_size * 0.5 - focus_2d.y
		if dx * dx + dz * dz > unload_dist_sq:
			stale_origins.append(origin)

	for origin in stale_origins:
		_unload_chunk(origin)


func _recompute_desired(focus_2d: Vector2):
	var super_near_distance = float(super_near_load_radius * chunk_step + chunk_size)
	var near_distance = float(load_radius * chunk_step + chunk_size)
	var far_distance = float(far_load_radius * chunk_step + chunk_size)
	var horizon_distance = float(horizon_load_radius * chunk_step + chunk_size)
	var super_near_dist_sq = super_near_distance * super_near_distance
	var near_dist_sq = near_distance * near_distance
	var far_dist_sq = far_distance * far_distance
	var horizon_dist_sq = horizon_distance * horizon_distance

	_cached_desired_meshes.clear()
	_cached_desired_data.clear()

	var focus_cx = _cell_coord(int(round(focus_2d.x)))
	var focus_cz = _cell_coord(int(round(focus_2d.y)))
	var cell_radius = int(ceil(horizon_distance / float(chunk_size))) + 1
	for cz in range(focus_cz - cell_radius, focus_cz + cell_radius + 1):
		for cx in range(focus_cx - cell_radius, focus_cx + cell_radius + 1):
			var cell = Vector2i(cx, cz)
			if not spatial_index.has(cell):
				continue
			for origin in spatial_index[cell]:
				if _cached_desired_meshes.has(origin):
					continue
				var center = Vector2(
					float(origin.x) + chunk_size * 0.5,
					float(origin.y) + chunk_size * 0.5
				)
				var d_sq = (center - focus_2d).length_squared()
				if d_sq <= super_near_dist_sq:
					_cached_desired_meshes[origin] = {
						"lod": super_near_visual_lod_step,
						"collision": true,
						"horizon": false,
					}
					_cached_desired_data[origin] = true
				elif d_sq <= near_dist_sq:
					_cached_desired_meshes[origin] = {
						"lod": visual_lod_step,
						"collision": true,
						"horizon": false,
					}
					_cached_desired_data[origin] = true
				elif d_sq <= far_dist_sq:
					_cached_desired_meshes[origin] = {
						"lod": far_visual_lod_step,
						"collision": false,
						"horizon": false,
					}
					_cached_desired_data[origin] = true
				elif d_sq <= horizon_dist_sq:
					_cached_desired_meshes[origin] = {
						"lod": horizon_visual_lod_step,
						"collision": false,
						"horizon": true,
					}
					_cached_desired_data[origin] = true

	for desired in _cached_desired_meshes.keys():
		if _cached_desired_meshes[desired]["horizon"]:
			continue
		var origin: Vector2i = desired
		var min_cx = _cell_coord(origin.x - chunk_size)
		var min_cz = _cell_coord(origin.y - chunk_size)
		var max_cx = _cell_coord(origin.x + chunk_size * 2 - 1)
		var max_cz = _cell_coord(origin.y + chunk_size * 2 - 1)
		for cz in range(min_cz, max_cz + 1):
			for cx in range(min_cx, max_cx + 1):
				var cell = Vector2i(cx, cz)
				if not spatial_index.has(cell):
					continue
				for other_origin in spatial_index[cell]:
					if other_origin == origin or _cached_desired_data.has(other_origin):
						continue
					if (
						abs(other_origin.x - origin.x) <= chunk_size
						and abs(other_origin.y - origin.y) <= chunk_size
					):
						_cached_desired_data[other_origin] = true


func _neighbors_data_loaded(origin: Vector2i) -> bool:
	var min_cx = _cell_coord(origin.x - chunk_size)
	var min_cz = _cell_coord(origin.y - chunk_size)
	var max_cx = _cell_coord(origin.x + chunk_size * 2 - 1)
	var max_cz = _cell_coord(origin.y + chunk_size * 2 - 1)
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var cell = Vector2i(cx, cz)
			if not spatial_index.has(cell):
				continue
			for other_origin in spatial_index[cell]:
				if other_origin == origin:
					continue
				if (
					abs(other_origin.x - origin.x) <= chunk_size
					and abs(other_origin.y - origin.y) <= chunk_size
					and not loaded_chunks.has(other_origin)
				):
					return false
	return true


func _load_chunk(origin: Vector2i):
	_load_chunk_data(origin)
	if loaded_chunks.has(origin):
		var chunk = loaded_chunks[origin]
		if not chunk.mesh_generated:
			chunk.generate()


func _load_chunk_data(origin: Vector2i):
	if loaded_chunks.has(origin) or not chunk_index.has(origin):
		return

	var chunk_data = chunk_index[origin]
	var chunk_path = height_directory.path_join(chunk_data["tile_folder"]).path_join(chunk_data["file"])
	if not FileAccess.file_exists(chunk_path):
		push_warning("Missing chunk file: " + chunk_path)
		return

	var chunk = preload("res://src/terrain_chunk.gd").new()
	chunk.setup(
		origin.x,
		origin.y,
		chunk_path,
		height_scale,
		visual_lod_step,
		collision_lod_step,
		_ortho_path_for(chunk_data)
	)
	chunk.position = Vector3(origin.x, 0.0, origin.y)
	add_child(chunk)
	loaded_chunks[origin] = chunk

	if loaded_chunks.size() == 1:
		print("Loaded first terrain chunk at %s" % str(origin))


func sample_height_int(world_x: int, world_z: int, exclude_chunk: Node = null) -> float:
	var cell = Vector2i(_cell_coord(world_x), _cell_coord(world_z))
	if not spatial_index.has(cell):
		return NAN
	var fallback = NAN
	for origin in spatial_index[cell]:
		if (
			world_x < origin.x
			or world_x >= origin.x + chunk_size
			or world_z < origin.y
			or world_z >= origin.y + chunk_size
		):
			continue
		if not loaded_chunks.has(origin):
			continue
		var chunk = loaded_chunks[origin]
		if chunk == exclude_chunk:
			continue
		var h = chunk.sample_height_int(world_x - origin.x, world_z - origin.y)
		if is_nan(h):
			continue
		if h != 0.0:
			return h
		if is_nan(fallback):
			fallback = h
	return fallback


func _unload_chunk(origin: Vector2i):
	if not loaded_chunks.has(origin):
		return

	var chunk = loaded_chunks[origin]
	loaded_chunks.erase(origin)
	chunk.queue_free()
	if _horizon_origins.has(origin):
		_horizon_origins.erase(origin)
		_horizon_mesh_dirty = true


func _kick_horizon_rebuild(bulk: bool):
	var snapshot = _horizon_chunk_arrays.values().duplicate()
	if bulk:
		var result = _concat_horizon_arrays(snapshot)
		_apply_horizon_rebuild(result)
		return
	_horizon_thread = Thread.new()
	_horizon_thread.start(_concat_horizon_arrays.bind(snapshot))


static func _concat_horizon_arrays(snapshot: Array) -> Array:
	var all_verts = PackedVector3Array()
	var all_normals = PackedVector3Array()
	for arrays in snapshot:
		all_verts.append_array(arrays[0])
		all_normals.append_array(arrays[1])
	return [all_verts, all_normals]


func _apply_horizon_rebuild(result: Array):
	var all_verts: PackedVector3Array = result[0]
	var all_normals: PackedVector3Array = result[1]

	if all_verts.is_empty():
		if _horizon_mesh_instance:
			_horizon_mesh_instance.mesh = null
		return

	var merged: Array = []
	merged.resize(Mesh.ARRAY_MAX)
	merged[Mesh.ARRAY_VERTEX] = all_verts
	merged[Mesh.ARRAY_NORMAL] = all_normals

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
	mesh.surface_set_material(0, TerrainChunk.get_shared_material())

	if not _horizon_mesh_instance:
		_horizon_mesh_instance = MeshInstance3D.new()
		_horizon_mesh_instance.name = "HorizonMesh"
		_horizon_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_horizon_mesh_instance)

	_horizon_mesh_instance.mesh = mesh


func _ortho_path_for(chunk_data: Dictionary) -> String:
	if ortho_directory.is_empty():
		return ""
	var stem: String = String(chunk_data["file"]).get_basename()
	var candidate := ortho_directory.path_join(chunk_data["tile_folder"]).path_join(stem + ".png")
	if not FileAccess.file_exists(candidate):
		return ""
	return candidate


func _ensure_chunk_loaded(pos: Vector3):
	var origin = _find_containing_chunk_origin(pos)
	if loaded_chunks.has(origin) or not chunk_index.has(origin):
		return

	_load_chunk(origin)


func _world_to_chunk_origin(pos: Vector3) -> Vector2i:
	var origin_x = int(floor(pos.x / float(chunk_step))) * chunk_step
	var origin_z = int(floor(pos.z / float(chunk_step))) * chunk_step
	return Vector2i(origin_x, origin_z)


func _find_containing_chunk_origin(pos: Vector3) -> Vector2i:
	for entry in chunk_entries:
		var origin: Vector2i = entry["origin"]
		if (
			pos.x >= origin.x
			and pos.x < origin.x + chunk_size
			and pos.z >= origin.y
			and pos.z < origin.y + chunk_size
		):
			return origin

	return _world_to_chunk_origin(pos)


func _compute_chunk_origin(tile_folder: String, chunk_file: String) -> Vector2i:
	var parts = tile_folder.split("_")
	if parts.size() < 3 or dataset_manifest.is_empty():
		return Vector2i.ZERO

	var south_northing = int(parts[0]) * 100
	var west_easting = int(parts[1]) * 100
	var tile_size_m = int(parts[2]) * 100
	var tile_top_northing = south_northing + tile_size_m

	var stem = chunk_file.get_basename().trim_prefix("chunk_")
	var row_col = stem.split("_")
	var row = int(row_col[0])
	var col = int(row_col[1])

	var local_x = west_easting - int(dataset_manifest.get("origin_easting", 0)) + col
	var local_z = int(dataset_manifest.get("max_northing", 0)) - tile_top_northing + row
	return Vector2i(local_x, local_z)
