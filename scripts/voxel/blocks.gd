## Block type registry. A block is one byte in chunk data; 0 is air.
## Colors are sRGB here and converted to linear once for vertex colors.
## Emissive blocks are flagged through vertex-color alpha = 0 (see voxel.gdshader).
extends RefCounted

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const SAND := 4
const SNOW := 5
const BEDROCK := 6
const ORE := 7
const STALK := 8
const BULB := 9
const HULL := 10
const LIGHT := 11

const COUNT := 12

const NAMES := [
	"Air", "Grass", "Dirt", "Stone", "Sand", "Snow",
	"Bedrock", "Ore", "Stalk", "Bulb", "Hull", "Light",
]

const EMISSIVE := [
	false, false, false, false, false, false,
	false, false, false, true, false, true,
]

static var COLORS: Array = [
	Color(0.0, 0.0, 0.0),     # air (unused)
	Color(0.31, 0.70, 0.60),  # grass: teal alien turf
	Color(0.48, 0.33, 0.27),  # dirt
	Color(0.43, 0.42, 0.50),  # stone: violet-grey
	Color(0.85, 0.77, 0.54),  # sand
	Color(0.93, 0.95, 0.97),  # snow
	Color(0.16, 0.15, 0.20),  # bedrock
	Color(0.91, 0.69, 0.23),  # ore
	Color(0.56, 0.31, 0.69),  # stalk: purple flora stem
	Color(1.00, 0.37, 0.82),  # bulb: glowing flora tip
	Color(0.79, 0.81, 0.84),  # hull plate
	Color(0.50, 0.91, 1.00),  # light panel
]

## Linear vertex colors, alpha 0 = emissive. Built once at script load (main thread),
## read-only afterwards, so worker threads can share it.
static var vertex_colors: PackedColorArray = _build_vertex_colors()


static func _build_vertex_colors() -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(256)
	for i in 256:
		out[i] = Color(1.0, 0.0, 1.0)  # unknown ids show up magenta
	for i in COUNT:
		var c: Color = COLORS[i]
		var lin := c.srgb_to_linear()
		lin.a = 0.0 if EMISSIVE[i] else 1.0
		out[i] = lin
	return out
