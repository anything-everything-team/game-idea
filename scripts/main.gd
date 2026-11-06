## M0 tech spike entry point: builds environment, voxel world, player, and HUD.
##
## Command-line options (after `--`):
##   --seed=N               landing zone seed (default 1337)
##   --preset=web|desktop   force platform limits (see platform_preset.gd)
##   --threads=off          single-threaded chunk building, like the web build
##   --benchmark            auto-fly across the zone, print stats each second, then quit
##   --bench-seconds=N      benchmark duration (default 30)
extends Node3D

const PlatformPreset = preload("res://scripts/core/platform_preset.gd")
const InputSetup = preload("res://scripts/core/input_setup.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const Player = preload("res://scripts/player/player.gd")
const Hud = preload("res://scripts/ui/hud.gd")

## Survives scene reloads so "N" can start a fresh landing zone.
static var next_seed := -1

var preset: Dictionary
var world: VoxelWorld
var player: Player
var hud: Hud
var start_ms := 0

var benchmark := false
var bench_seconds := 30.0
var bench_time := 0.0
var bench_next_print := 0.0
var bench_min_fps := 1.0e9
var bench_fps_sum := 0.0
var bench_frames := 0


func _ready() -> void:
	start_ms = Time.get_ticks_msec()
	InputSetup.register()
	preset = PlatformPreset.current()

	var seed_value := 1337
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = arg.get_slice("=", 1).to_int()
		elif arg == "--benchmark":
			benchmark = true
		elif arg.begins_with("--bench-seconds="):
			bench_seconds = arg.get_slice("=", 1).to_float()
	if next_seed >= 0:
		seed_value = next_seed

	_setup_environment()

	world = VoxelWorld.new()
	world.name = "VoxelWorld"
	world.setup(preset, seed_value)
	add_child(world)

	player = Player.new()
	player.name = "Player"
	player.world = world
	var center := world.zone_center()
	player.position = Vector3(center.x, world.height_blocks + 2.0, center.y)
	add_child(player)

	hud = Hud.new()
	hud.world = world
	hud.player = player
	add_child(hud)

	world.set_focus(player.position)
	print("[starwright] preset=%s threads=%d seed=%d renderer=%s zone=%dx%dx%d view_radius=%d" % [
		preset["name"], preset["threads"], seed_value, PlatformPreset.renderer_name(),
		world.size_xz, world.size_xz, world.height_blocks, world.view_radius])


func _setup_environment() -> void:
	var horizon := Color(0.72, 0.62, 0.78)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.22, 0.45)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = Color(0.2, 0.17, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true

	# Fog hides the edge of the streamed area.
	var view := float(preset["view_radius"]) * 16.0
	env.fog_enabled = true
	env.fog_light_color = horizon
	env.fog_sky_affect = 0.0
	if "fog_mode" in env:
		env.set("fog_mode", 1)  # Environment.FOG_MODE_DEPTH
		env.fog_density = 1.0
		env.set("fog_depth_begin", view * 0.55)
		env.set("fog_depth_end", view * 0.95)
	else:
		env.fog_density = 2.0 / view

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.light_energy = 1.1
	sun.shadow_enabled = preset["shadows"]
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _process(delta: float) -> void:
	world.set_focus(player.position)

	if player.frozen and world.is_area_ready(player.position, 1):
		var top := world.top_solid_y(floori(player.position.x), floori(player.position.z))
		player.position.y = top + 1.05
		player.frozen = false
		world.spawn_ms = float(Time.get_ticks_msec() - start_ms)
		print("[starwright] spawn area ready in %.0f ms" % world.spawn_ms)
		if benchmark:
			player.fly = true
			player.autopilot = true
			player.position.y = top + 24.0

	if benchmark and not player.frozen:
		_benchmark_step(delta)


func _unhandled_input(event) -> void:
	if event is InputEventKey and event.is_action_pressed("new_seed"):
		next_seed = randi() % 1000000
		get_tree().reload_current_scene()


func _benchmark_step(delta: float) -> void:
	bench_time += delta
	var fps := Engine.get_frames_per_second()
	if bench_time > 2.0:  # FPS counter needs a moment to settle
		bench_min_fps = minf(bench_min_fps, fps)
		bench_fps_sum += fps
		bench_frames += 1

	# Bounce between the zone edges so the streamer keeps loading new columns.
	if player.position.z < 24.0:
		player.yaw = PI
	elif player.position.z > world.size_xz - 24.0:
		player.yaw = 0.0

	if bench_time >= bench_next_print:
		bench_next_print += 1.0
		var s := world.stats()
		print("[bench] t=%2.0fs fps=%4.0f process=%5.2fms columns=%d pending=%d building=%d meshes=%d tris=%d gen=%.2fms/col mesh=%.2fms/col (%.2fms/chunk) mem=%.0fMB" % [
			bench_time, fps, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			s["columns_loaded"], s["pending"], s["in_flight"], s["chunks_meshed"], s["tris"],
			s["gen_ms_per_column"], s["mesh_ms_per_column"], s["mesh_ms_per_chunk"],
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])

	if bench_time >= bench_seconds:
		var s := world.stats()
		print("[bench] SUMMARY preset=%s threads=%d spawn=%.0fms full_load=%.0fms avg_fps=%.0f min_fps=%.0f gen=%.2fms/col mesh=%.2fms/chunk" % [
			preset["name"], preset["threads"], s["spawn_ms"], s["full_load_ms"],
			bench_fps_sum / maxi(1, bench_frames), bench_min_fps if bench_frames > 0 else 0.0,
			s["gen_ms_per_column"], s["mesh_ms_per_chunk"]])
		get_tree().quit()
