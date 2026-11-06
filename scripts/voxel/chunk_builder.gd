## Builds chunk columns (generate + mesh) as resumable jobs.
##
## A job is a Dictionary owned by exactly one thread at a time. `step()` does one small
## unit of work so the single-threaded web build can spread a column over several
## frames; `run()` loops `step()` to completion on a worker thread (desktop).
##
## Only reads immutable state (generator, zone size) plus the job's own data.
extends RefCounted

const Mesher = preload("res://scripts/voxel/chunk_mesher.gd")

const CS := 16
const P := 18
const PSTR := [1, 18, 324]   # padded strides
const LSTR := [1, 16, 256]   # chunk-local strides

var generator   # terrain_generator.gd
var zone_xz: int
var zone_y: int


func _init(p_generator, p_zone_xz: int, p_zone_y: int) -> void:
	generator = p_generator
	zone_xz = p_zone_xz
	zone_y = p_zone_y


## `source` maps Vector3i -> PackedByteArray: already-known chunks of this column and its
## four neighbor columns. Generated chunks are added to it as the job runs.
func new_column_job(col: Vector2i, source: Dictionary, versions: Dictionary) -> Dictionary:
	return {
		"col": col,
		"source": source,
		"versions": versions,
		"phase": 0,
		"layer": 0,
		"maps": [],
		"generated": {},
		"meshes": {},
		"gen_us": 0,
		"mesh_us": 0,
		"chunks_meshed": 0,
		"done": false,
	}


func run(job: Dictionary) -> void:
	while not step(job):
		pass


## Does one unit of work. Returns true when the job is complete.
func step(job: Dictionary) -> bool:
	var t0 := Time.get_ticks_usec()
	var col: Vector2i = job["col"]
	var phase: int = job["phase"]

	if phase == 0:
		job["maps"] = generator.column_maps(col.x, col.y)
		job["phase"] = 1
		job["gen_us"] += Time.get_ticks_usec() - t0
		return false

	var layer: int = job["layer"]
	var k := Vector3i(col.x, layer, col.y)
	var source: Dictionary = job["source"]
	var maps: Array = job["maps"]

	if phase == 1:
		if not source.has(k):
			var data: PackedByteArray = generator.generate_chunk(col.x, layer, col.y, maps)
			source[k] = data
			job["generated"][k] = data
		job["gen_us"] += Time.get_ticks_usec() - t0
		layer += 1
		if layer >= zone_y:
			job["phase"] = 2
			job["layer"] = 0
		else:
			job["layer"] = layer
		return false

	var arrays := mesh_chunk(source, k, maps)
	job["meshes"][k] = arrays
	if not arrays.is_empty():
		job["chunks_meshed"] += 1
	job["mesh_us"] += Time.get_ticks_usec() - t0
	layer += 1
	if layer >= zone_y:
		job["done"] = true
		return true
	job["layer"] = layer
	return false


## Meshes chunk `k` using `source` for neighbor borders (falling back to the generator).
## `maps` must be the column maps of k's column.
func mesh_chunk(source: Dictionary, k: Vector3i, maps: Array) -> Array:
	var center: PackedByteArray = source[k]
	if center == generator.empty_chunk:
		return []
	return Mesher.build(build_padded(source, k, maps))


func build_padded(source: Dictionary, k: Vector3i, maps: Array) -> PackedByteArray:
	var padded := PackedByteArray()
	padded.resize(P * P * P)
	padded.fill(0)
	var center: PackedByteArray = source[k]
	for lz in CS:
		for ly in CS:
			var src := (ly << 4) + (lz << 8)
			var dst := 1 + (ly + 1) * P + (lz + 1) * P * P
			for lx in CS:
				padded[dst + lx] = center[src + lx]
	for axis in 3:
		_fill_face(padded, source, k, axis, -1, maps)
		_fill_face(padded, source, k, axis, 1, maps)
	return padded


## Fills one 16x16 border face of the padded array from the neighbor chunk.
func _fill_face(padded: PackedByteArray, source: Dictionary, k: Vector3i, axis: int, side: int, maps: Array) -> void:
	var nk := k
	nk[axis] += side
	var b: int = (axis + 1) % 3
	var c: int = (axis + 2) % 3
	var pa: int = PSTR[axis]
	var pb: int = PSTR[b]
	var pc: int = PSTR[c]
	var p_base := (0 if side < 0 else P - 1) * pa

	if axis == 1:
		if nk.y < 0:
			# Below the zone floor counts as solid so no bottom faces are built.
			for j in CS:
				for i in CS:
					padded[p_base + (i + 1) * pb + (j + 1) * pc] = 1
			return
		if nk.y >= zone_y:
			return  # open sky above the zone
	elif nk.x < 0 or nk.z < 0 or nk.x >= zone_xz or nk.z >= zone_xz:
		return  # outside the landing zone is air, so the zone edge shows as a cliff

	if source.has(nk):
		var nd: PackedByteArray = source[nk]
		var la: int = LSTR[axis]
		var lb: int = LSTR[b]
		var lc: int = LSTR[c]
		var n_base := (CS - 1 if side < 0 else 0) * la
		for j in CS:
			for i in CS:
				padded[p_base + (i + 1) * pb + (j + 1) * pc] = nd[n_base + i * lb + j * lc]
		return

	# Neighbor not generated yet: the generator is deterministic, so ask it directly.
	var heights: PackedInt32Array = maps[0]
	var plants: PackedInt32Array = maps[1]
	var origin := k * CS
	for j in CS:
		for i in CS:
			var w := origin
			w[axis] += -1 if side < 0 else CS
			w[b] += i
			w[c] += j
			var mi := (w.x - origin.x + 1) + (w.z - origin.z + 1) * P
			padded[p_base + (i + 1) * pb + (j + 1) * pc] = generator.block_at(w.x, w.y, w.z, heights[mi], plants[mi])
