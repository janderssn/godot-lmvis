extends Node3D

signal terrain_ready

@export var height_directory: String = "res://terrain_data/raw_height"
@export var load_radius: int = 6
@export var unload_radius: int = 8
@export var chunk_size: int = 256
@export var overlap: int = 1
@export var height_scale: float = 1.0
@export var visual_lod_step: int = 4
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


func _ready():
	chunk_step = chunk_size - overlap
	_load_dataset_manifest()
	_load_all_manifests()
	_derive_default_focus()


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
	var load_distance = float(load_radius * chunk_step + chunk_size)
	var unload_distance = float(unload_radius * chunk_step + chunk_size)
	var load_dist_sq = load_distance * load_distance
	var unload_dist_sq = unload_distance * unload_distance
	var desired_meshes: Dictionary = {}
	var desired_data: Dictionary = {}

	var focus_cx = _cell_coord(int(round(pos.x)))
	var focus_cz = _cell_coord(int(round(pos.z)))
	var cell_radius = int(ceil(load_distance / float(chunk_size))) + 1
	for cz in range(focus_cz - cell_radius, focus_cz + cell_radius + 1):
		for cx in range(focus_cx - cell_radius, focus_cx + cell_radius + 1):
			var cell = Vector2i(cx, cz)
			if not spatial_index.has(cell):
				continue
			for origin in spatial_index[cell]:
				if desired_meshes.has(origin):
					continue
				var center = Vector2(
					float(origin.x) + chunk_size * 0.5,
					float(origin.y) + chunk_size * 0.5
				)
				if (center - focus_2d).length_squared() <= load_dist_sq:
					desired_meshes[origin] = true
					desired_data[origin] = true

	for desired in desired_meshes.keys():
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
					if other_origin == origin or desired_data.has(other_origin):
						continue
					if (
						abs(other_origin.x - origin.x) <= chunk_size
						and abs(other_origin.y - origin.y) <= chunk_size
					):
						desired_data[other_origin] = true

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
		if chunk.mesh_generated:
			continue
		if not _neighbors_data_loaded(origin):
			continue
		chunk.generate()
		mesh_budget -= 1

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
		collision_lod_step
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
