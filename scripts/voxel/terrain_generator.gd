## Deterministic landing-zone terrain: same seed + coordinates -> same blocks on every
## machine. That is what lets co-op clients generate terrain locally (GAME_DESIGN.md §10)
## and lets the mesher ask for border blocks of chunks that are not generated yet.
##
## Thread safety: after _init, this object is read-only. FastNoiseLite sampling does
## not mutate the noise object, so worker threads share one generator.
extends RefCounted

const Blocks = preload("res://scripts/voxel/blocks.gd")

const CS := 16      # chunk size
const MAP := 18     # column map width: 16 + 1-block border on each side
const CS3 := CS * CS * CS

var seed_value: int
var height_blocks: int
var base_height: float
var hill_amp: float
var mountain_amp: float
var sand_line: int
var snow_line: int

var shape := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var caves := FastNoiseLite.new()
var ore := FastNoiseLite.new()

## Shared all-air chunk. Never modified in place (edits duplicate first).
var empty_chunk := PackedByteArray()


func _init(p_seed: int, p_height_blocks: int) -> void:
	seed_value = p_seed
	height_blocks = p_height_blocks
	base_height = height_blocks * 0.28
	hill_amp = height_blocks * 0.10
	mountain_amp = height_blocks * 0.42
	sand_line = int(base_height - hill_amp * 0.5)
	snow_line = int(base_height + mountain_amp * 0.45)

	shape.seed = seed_value
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape.frequency = 0.006
	shape.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape.fractal_octaves = 4

	ridge.seed = seed_value + 1
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.frequency = 0.0035
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 3

	caves.seed = seed_value + 2
	caves.noise_type = FastNoiseLite.TYPE_SIMPLEX
	caves.frequency = 0.05
	caves.fractal_type = FastNoiseLite.FRACTAL_NONE

	ore.seed = seed_value + 3
	ore.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ore.frequency = 0.15
	ore.fractal_type = FastNoiseLite.FRACTAL_NONE

	empty_chunk.resize(CS3)
	empty_chunk.fill(0)


func surface_height(wx: int, wz: int) -> int:
	var s := shape.get_noise_2d(wx, wz)
	var r := (ridge.get_noise_2d(wx, wz) + 1.0) * 0.5
	var mountain_mask := clampf(s * 1.6 + 0.4, 0.0, 1.0)
	var h := base_height + s * hill_amp + r * r * r * mountain_amp * mountain_mask
	return clampi(int(h), 2, height_blocks - 12)


## Height of the alien plant growing on this column (0 = none).
func plant_height(wx: int, wz: int, h: int) -> int:
	if h <= sand_line or h >= snow_line:
		return 0
	var r := _hash(wx, wz)
	if r % 1000 >= 14:
		return 0
	return 2 + (r >> 10) % 4


func surface_block(h: int) -> int:
	if h <= sand_line:
		return Blocks.SAND
	if h >= snow_line:
		return Blocks.SNOW
	return Blocks.GRASS


## The single source of truth for "what block is here".
## h / ph are the column's surface and plant heights (from column_maps).
func block_at(wx: int, wy: int, wz: int, h: int, ph: int) -> int:
	if wy <= 0:
		return Blocks.BEDROCK
	if wy > h:
		if ph > 0 and wy <= h + ph:
			return Blocks.BULB if wy == h + ph else Blocks.STALK
		return Blocks.AIR
	var depth := h - wy
	if depth > 4 and wy > 2 and caves.get_noise_3d(wx, wy * 1.5, wz) > 0.6:
		return Blocks.AIR
	if depth == 0:
		return surface_block(h)
	if depth < 4:
		return Blocks.SAND if h <= sand_line else Blocks.DIRT
	if depth > 6 and ore.get_noise_3d(wx, wy, wz) > 0.62:
		return Blocks.ORE
	return Blocks.STONE


## Surface and plant heights for a chunk column plus a 1-block border ring.
## Index: (lx + 1) + (lz + 1) * MAP, with lx/lz in -1..16.
func column_maps(cx: int, cz: int) -> Array:
	var heights := PackedInt32Array()
	var plants := PackedInt32Array()
	heights.resize(MAP * MAP)
	plants.resize(MAP * MAP)
	var ox := cx * CS - 1
	var oz := cz * CS - 1
	for z in MAP:
		for x in MAP:
			var wx := ox + x
			var wz := oz + z
			var h := surface_height(wx, wz)
			heights[x + z * MAP] = h
			plants[x + z * MAP] = plant_height(wx, wz, h)
	return [heights, plants]


## Generates one 16^3 chunk. Index: x + y * 16 + z * 256.
## Returns the shared empty_chunk when the chunk is all air.
func generate_chunk(cx: int, cy: int, cz: int, maps: Array) -> PackedByteArray:
	var heights: PackedInt32Array = maps[0]
	var plants: PackedInt32Array = maps[1]
	var data := PackedByteArray()
	data.resize(CS3)
	data.fill(0)
	var y0 := cy * CS
	var any := false
	for lz in CS:
		for lx in CS:
			var mi := (lx + 1) + (lz + 1) * MAP
			var h := heights[mi]
			var ph := plants[mi]
			var top := h + ph
			if top < y0:
				continue
			var wx := cx * CS + lx
			var wz := cz * CS + lz
			var ymax := mini(CS - 1, top - y0)
			for ly in ymax + 1:
				var b := block_at(wx, y0 + ly, wz, h, ph)
				if b != Blocks.AIR:
					data[lx + (ly << 4) + (lz << 8)] = b
					any = true
	return data if any else empty_chunk


## Small integer hash (kept within 64-bit range on purpose, identical on every platform).
func _hash(x: int, z: int) -> int:
	var h := (x * 374761393 + z * 668265263 + seed_value * 982451653) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return h ^ (h >> 16)
