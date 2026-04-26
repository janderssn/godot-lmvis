extends Node3D

const ARESKUTAN_TOPPSTUGAN_SWEREF := Vector2(404867.81423292926, 7035230.670129072)
const BENCH_DURATION_SEC := 15.0
const BENCH_WARMUP_SEC := 2.0
const BENCH_PATH_RADIUS := 3000.0

@onready var terrain_loader = $TerrainLoader
@onready var camera = $Camera

var _perf_label: Label
var _ascot_origin: Vector3 = Vector3.ZERO

var _bench_active: bool = false
var _bench_warmup_done: bool = false
var _bench_start_msec: int = 0
var _bench_frame_times: PackedFloat32Array = PackedFloat32Array()


func _ready():
	var focus = terrain_loader.sweref_to_local(
		ARESKUTAN_TOPPSTUGAN_SWEREF.x,
		ARESKUTAN_TOPPSTUGAN_SWEREF.y
	)
	if focus == Vector3.ZERO:
		focus = terrain_loader.get_default_focus_position()
	_ascot_origin = focus

	terrain_loader.start_streaming(focus)

	focus.y = terrain_loader.get_height_at_position(focus)
	camera.set_orbit_center(focus)
	camera.set_orbit_angle(deg_to_rad(210.0))
	camera.snap_to_orbit()

	terrain_loader.set_stream_focus(camera.get_stream_focus_position())

	_setup_perf_overlay()

	if "--bench" in OS.get_cmdline_user_args():
		print("BENCH godot-lmvis: warming up %.1fs, then sampling %.1fs" % [BENCH_WARMUP_SEC, BENCH_DURATION_SEC])
		_bench_active = true
		_bench_start_msec = Time.get_ticks_msec()
		camera.auto_orbit = false
		return

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
	print("  F3         Toggle perf overlay")


func _process(delta):
	terrain_loader.set_stream_focus(camera.get_stream_focus_position())
	_update_perf_overlay()
	if _bench_active:
		_drive_bench(delta)


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_perf_label.visible = not _perf_label.visible


# --- perf overlay -------------------------------------------------------------

func _setup_perf_overlay():
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	_perf_label = Label.new()
	_perf_label.position = Vector2(12, 12)
	_perf_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_perf_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_perf_label.add_theme_constant_override("outline_size", 4)
	canvas.add_child(_perf_label)


func _update_perf_overlay():
	if _perf_label == null or not _perf_label.visible:
		return
	var fps = Engine.get_frames_per_second()
	var ft_ms = 1000.0 / max(fps, 1)
	var draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var stats: Dictionary = terrain_loader.get_stats()
	_perf_label.text = (
		"FPS %d  %.1f ms\n"
		+ "draws %d  prims %d\n"
		+ "loaded %d / %d  horizon %d (arrays %d)"
	) % [
		fps, ft_ms, draws, prims,
		int(stats["loaded"]), int(stats["indexed"]),
		int(stats["horizon_origins"]), int(stats["horizon_arrays"]),
	]


# --- benchmark mode ----------------------------------------------------------

func _drive_bench(delta_s: float):
	var elapsed = (Time.get_ticks_msec() - _bench_start_msec) / 1000.0
	var t_path = clamp(elapsed - BENCH_WARMUP_SEC, 0.0, BENCH_DURATION_SEC)

	# Move the focus on a deterministic loop around Åreskutan to exercise
	# streaming + LOD transitions across the full LOD pyramid.
	var phase = (t_path / BENCH_DURATION_SEC) * TAU * 2.0
	var radius = BENCH_PATH_RADIUS * (0.5 + 0.5 * sin(t_path / BENCH_DURATION_SEC * PI))
	var new_focus = _ascot_origin + Vector3(cos(phase) * radius, 0.0, sin(phase) * radius)
	new_focus.y = terrain_loader.get_height_at_position(new_focus)
	camera.set_orbit_center(new_focus)
	camera.set_orbit_angle(phase)

	if elapsed < BENCH_WARMUP_SEC:
		return  # warmup: drive camera but don't sample

	if not _bench_warmup_done:
		_bench_warmup_done = true
		print("BENCH sampling start")
		_bench_frame_times.clear()

	_bench_frame_times.append(delta_s * 1000.0)

	if elapsed - BENCH_WARMUP_SEC >= BENCH_DURATION_SEC:
		_finish_bench()


func _finish_bench():
	_bench_active = false
	var n = _bench_frame_times.size()
	if n == 0:
		print("BENCH end frames=0")
		get_tree().quit()
		return

	var sorted = _bench_frame_times.duplicate()
	sorted.sort()
	var sum = 0.0
	var minv = sorted[0]
	var maxv = sorted[n - 1]
	for v in sorted:
		sum += v
	var avg = sum / n
	var p50 = sorted[int(n * 0.50)]
	var p95 = sorted[int(n * 0.95)]
	var p99 = sorted[min(int(n * 0.99), n - 1)]
	var stats: Dictionary = terrain_loader.get_stats()

	print("BENCH end frames=%d duration_s=%.2f" % [n, sum / 1000.0])
	print(
		"BENCH stats avg_ms=%.2f min_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f fps_avg=%.1f"
		% [avg, minv, p50, p95, p99, maxv, 1000.0 / avg]
	)
	print(
		"BENCH chunks loaded=%d horizon_origins=%d horizon_arrays=%d indexed=%d"
		% [int(stats["loaded"]), int(stats["horizon_origins"]), int(stats["horizon_arrays"]), int(stats["indexed"])]
	)
	get_tree().quit()
