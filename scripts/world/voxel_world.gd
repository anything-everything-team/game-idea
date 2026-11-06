## Streams a bounded landing zone of voxel chunks around a focus point.
##
## - Chunks are 16^3 and grouped in columns; a column is generated + meshed as one job.
## - Desktop: jobs run on WorkerThreadPool; the main thread only builds ArrayMeshes.
## - Web (no threads): jobs are stepped on the main thread within a per-frame budget.
## - Chunk data is kept after a column unloads (only meshes are freed), so edits persist.
## - Edits remesh synchronously so feedback is instant; a per-chunk version number
##   discards stale results from jobs that were in flight during the edit.
extends Node3D

const Blocks = preload("res://scripts/voxel/blocks.gd")
const TerrainGenerator = preload("res://scripts/voxel/terrain_generator.gd")
const ChunkBuilder = preload("res://scripts/voxel/chunk_builder.gd")
const VOXEL_SHADER = preload("res://shaders/voxel.gdshader")

const CS := 16
const OUT_OF_ZONE := -1
const UNKNOWN := -2
const QUEUED := 1
const LOADED := 2
const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var preset: Dictionary
var world_seed := 1337
var generator: TerrainGenerator
var builder: ChunkBuilder
var material: ShaderMaterial

var zone_xz := 0         # zone width in chunks
var zone_y := 0          # zone height in chunks
var size_xz := 0         # zone width in blocks
var height_blocks := 0   # zone height in blocks
var view_radius := 0     # chunks
var thread_count := 0
var frame_budget_usec := 0
var shadows := false

var chunk_data := {}     # Vector3i -> PackedByteArray
var chunk_version := {}  # Vector3i -> int
var chunk_meshes := {}   # Vector3i -> MeshInstance3D
var chunk_tris := {}     # Vector3i -> int
var columns := {}        # Vector2i -> QUEUED | LOADED
var pending: Array = []  # Vector2i, nearest first
var in_flight: Array = []  # [task_id, job]
var sync_job = null      # Dictionary while stepping a job on the main thread
var focus := Vector2i(-9999, -9999)

# Stats for the HUD / benchmark.
var total_tris := 0
var columns_done := 0
var gen_us_total := 0
var mesh_us_total := 0
var mesh_chunks := 0
var last_edit_ms := 0.0
var start_msec := 0
var spawn_ms := -1.0
var full_load_ms := -1.0


## Call before adding to the tree.
func setup(p_preset: Dictionary, p_seed: int) -> void:
	preset = p_preset
	world_seed = p_seed
	zone_xz = preset["zone_chunks_xz"]
	zone_y = preset["zone_chunks_y"]
	size_xz = zone_xz * CS
	height_blocks = zone_y * CS
	view_radius = preset["view_radius"]
	thread_count = preset["threads"]
	shadows = preset["shadows"]
	frame_budget_usec = int(float(preset["frame_budget_ms"]) * 1000.0)
	generator = TerrainGenerator.new(world_seed, height_blocks)
	builder = ChunkBuilder.new(generator, zone_xz, zone_y)
	material = ShaderMaterial.new()
	material.shader = VOXEL_SHADER
	start_msec = Time.get_ticks_msec()


func _exit_tree() -> void:
	for entry in in_flight:
		WorkerThreadPool.wait_for_task_completion(entry[0])
	in_flight.clear()


func zone_center() -> Vector2:
	return Vector2(size_xz * 0.5, size_xz * 0.5)


# --- Streaming ---------------------------------------------------------------

func set_focus(pos: Vector3) -> void:
	var c := Vector2i(floori(pos.x / CS), floori(pos.z / CS))
	if c == focus:
		return
	focus = c
	_refresh_columns()


func _in_zone(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < zone_xz and c.y < zone_xz


func _is_wanted(c: Vector2i, radius: int) -> bool:
	var d := c - focus
	return _in_zone(c) and d.x * d.x + d.y * d.y <= radius * radius


func _refresh_columns() -> void:
	var r := view_radius
	var candidates: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := focus + Vector2i(dx, dz)
			if dx * dx + dz * dz <= r * r and _in_zone(c) and not columns.has(c):
				candidates.append(c)
	var f := focus
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - f).length_squared() < (b - f).length_squared())
	pending = candidates
	# Unload with one chunk of hysteresis so walking along a border doesn't thrash.
	for c in columns.keys():
		if columns[c] == LOADED and not _is_wanted(c, r + 1):
			_unload_column(c)


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if thread_count > 0:
		_process_threaded(t0)
	else:
		_process_single(t0)
	if full_load_ms < 0.0 and pending.is_empty() and in_flight.is_empty() and sync_job == null and columns_done > 0:
		full_load_ms = float(Time.get_ticks_msec() - start_msec)


func _process_threaded(t0: int) -> void:
	var i := 0
	while i < in_flight.size():
		var entry: Array = in_flight[i]
		var task_id: int = entry[0]
		if WorkerThreadPool.is_task_completed(task_id):
			WorkerThreadPool.wait_for_task_completion(task_id)
			in_flight.remove_at(i)
			_apply_job(entry[1])
			if Time.get_ticks_usec() - t0 > frame_budget_usec:
				break
		else:
			i += 1
	while in_flight.size() < thread_count and not pending.is_empty():
		var job := _make_job(pending.pop_front())
		var task_id := WorkerThreadPool.add_task(builder.run.bind(job), false, "chunk column")
		in_flight.append([task_id, job])


func _process_single(t0: int) -> void:
	while Time.get_ticks_usec() - t0 < frame_budget_usec:
		if sync_job == null:
			if pending.is_empty():
				return
			sync_job = _make_job(pending.pop_front())
		if builder.step(sync_job):
			var job: Dictionary = sync_job
			sync_job = null
			_apply_job(job)


func _make_job(c: Vector2i) -> Dictionary:
	columns[c] = QUEUED
	var source := {}
	var versions := {}
	for cy in zone_y:
		var k := Vector3i(c.x, cy, c.y)
		versions[k] = chunk_version.get(k, 0)
		if chunk_data.has(k):
			source[k] = chunk_data[k]
		for off: Vector2i in NEIGHBORS:
			var nk := Vector3i(c.x + off.x, cy, c.y + off.y)
			if chunk_data.has(nk):
				source[nk] = chunk_data[nk]
	return builder.new_column_job(c, source, versions)


func _apply_job(job: Dictionary) -> void:
	var c: Vector2i = job["col"]
	if not job.get("done", false):
		push_error("Chunk column job failed at %s" % c)
		columns[c] = LOADED  # don't retry forever
		return
	var generated: Dictionary = job["generated"]
	for k in generated:
		if not chunk_data.has(k):
			chunk_data[k] = generated[k]
	columns_done += 1
	gen_us_total += int(job["gen_us"])
	mesh_us_total += int(job["mesh_us"])
	mesh_chunks += int(job["chunks_meshed"])

	if not _is_wanted(c, view_radius + 1):
		columns.erase(c)  # player moved away while it was building; data is kept
		return
	var meshes: Dictionary = job["meshes"]
	var versions: Dictionary = job["versions"]
	for k in meshes:
		if versions.get(k, 0) != chunk_version.get(k, 0):
			_remesh_now(k)  # edited while the job ran
		else:
			_set_mesh(k, meshes[k])
	columns[c] = LOADED


func _unload_column(c: Vector2i) -> void:
	for cy in zone_y:
		var k := Vector3i(c.x, cy, c.y)
		var mi: MeshInstance3D = chunk_meshes.get(k)
		if mi:
			mi.queue_free()
			chunk_meshes.erase(k)
		var old_tris: int = chunk_tris.get(k, 0)
		total_tris -= old_tris
		chunk_tris.erase(k)
	columns.erase(c)


func _set_mesh(k: Vector3i, arrays: Array) -> void:
	var mi: MeshInstance3D = chunk_meshes.get(k)
	var old_tris: int = chunk_tris.get(k, 0)
	if arrays.is_empty():
		if mi:
			mi.queue_free()
			chunk_meshes.erase(k)
		total_tris -= old_tris
		chunk_tris.erase(k)
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = Vector3(k * CS)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		chunk_meshes[k] = mi
	mi.mesh = mesh
	var index_array: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tris := index_array.size() / 3
	total_tris += tris - old_tris
	chunk_tris[k] = tris


func _remesh_now(k: Vector3i) -> void:
	if not chunk_data.has(k):
		return
	var maps: Array = generator.column_maps(k.x, k.z)
	_set_mesh(k, builder.mesh_chunk(chunk_data, k, maps))


# --- Block access ------------------------------------------------------------

## Block id at a world position. Returns OUT_OF_ZONE outside the zone's sides and
## UNKNOWN where the chunk hasn't been generated yet.
func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= height_blocks:
		return Blocks.AIR
	if x < 0 or z < 0 or x >= size_xz or z >= size_xz:
		return OUT_OF_ZONE
	var data = chunk_data.get(Vector3i(x >> 4, y >> 4, z >> 4))
	if data == null:
		return UNKNOWN
	return data[(x & 15) + ((y & 15) << 4) + ((z & 15) << 8)]


## Zone walls and ungenerated chunks count as solid so the player can't fall out.
func is_solid(x: int, y: int, z: int) -> bool:
	return get_block(x, y, z) != Blocks.AIR


func set_block(p: Vector3i, id: int) -> bool:
	if p.y <= 0 or p.y >= height_blocks or p.x < 0 or p.z < 0 or p.x >= size_xz or p.z >= size_xz:
		return false
	var k := Vector3i(p.x >> 4, p.y >> 4, p.z >> 4)
	if not chunk_data.has(k):
		return false
	var idx := (p.x & 15) + ((p.y & 15) << 4) + ((p.z & 15) << 8)
	var current: PackedByteArray = chunk_data[k]
	if current[idx] == id:
		return false
	# Duplicate before writing: chunk arrays may be shared with in-flight jobs or be
	# the generator's shared empty chunk.
	var data := current.duplicate()
	data[idx] = id
	chunk_data[k] = data

	var t0 := Time.get_ticks_usec()
	var affected := [k]
	var local := Vector3i(p.x & 15, p.y & 15, p.z & 15)
	for axis in 3:
		if local[axis] == 0 or local[axis] == CS - 1:
			var nk := k
			nk[axis] += -1 if local[axis] == 0 else 1
			affected.append(nk)
	for ak: Vector3i in affected:
		if ak.x < 0 or ak.y < 0 or ak.z < 0 or ak.x >= zone_xz or ak.y >= zone_y or ak.z >= zone_xz:
			continue
		chunk_version[ak] = int(chunk_version.get(ak, 0)) + 1
		if columns.get(Vector2i(ak.x, ak.z), 0) == LOADED:
			_remesh_now(ak)
	last_edit_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return true


func top_solid_y(x: int, z: int) -> int:
	for y in range(height_blocks - 1, -1, -1):
		if get_block(x, y, z) > 0:
			return y
	return 0


func is_area_ready(pos: Vector3, radius: int) -> bool:
	var c := Vector2i(floori(pos.x / CS), floori(pos.z / CS))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var n := c + Vector2i(dx, dz)
			if _in_zone(n) and columns.get(n, 0) != LOADED:
				return false
	return true


## Voxel ray march (Amanatides & Woo). Returns {} or
## {"block": Vector3i, "normal": Vector3i, "distance": float, "id": int}.
func raycast(origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var dir := direction.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a in 3:
		if dir[a] > 0.0:
			step[a] = 1
			t_max[a] = (floorf(origin[a]) + 1.0 - origin[a]) / dir[a]
			t_delta[a] = 1.0 / dir[a]
		elif dir[a] < 0.0:
			step[a] = -1
			t_max[a] = (origin[a] - floorf(origin[a])) / -dir[a]
			t_delta[a] = -1.0 / dir[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance:
		var b := get_block(cell.x, cell.y, cell.z)
		if b > 0:
			return {"block": cell, "normal": normal, "distance": t, "id": b}
		if b < 0 and t > 0.0:
			return {}  # left the zone or hit unloaded terrain
		var axis := 0
		if t_max.x < t_max.y:
			axis = 0 if t_max.x < t_max.z else 2
		else:
			axis = 1 if t_max.y < t_max.z else 2
		cell[axis] += step[axis]
		t = t_max[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}


func stats() -> Dictionary:
	var loaded := 0
	for c in columns:
		if columns[c] == LOADED:
			loaded += 1
	var done := maxi(1, columns_done)
	return {
		"columns_loaded": loaded,
		"pending": pending.size(),
		"in_flight": in_flight.size() + (1 if sync_job != null else 0),
		"chunks_meshed": chunk_meshes.size(),
		"chunks_stored": chunk_data.size(),
		"tris": total_tris,
		"gen_ms_per_column": gen_us_total / 1000.0 / done,
		"mesh_ms_per_column": mesh_us_total / 1000.0 / done,
		"mesh_ms_per_chunk": mesh_us_total / 1000.0 / maxi(1, mesh_chunks),
		"last_edit_ms": last_edit_ms,
		"spawn_ms": spawn_ms,
		"full_load_ms": full_load_ms,
	}
