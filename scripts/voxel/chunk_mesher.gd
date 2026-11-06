## Greedy mesher: merges coplanar faces of the same block type into large quads.
##
## Input is a padded 18^3 block array (the chunk plus a 1-block border from its
## neighbors) so faces on chunk edges are culled correctly without touching other
## chunks. Index: x + y * 18 + z * 324 with x/y/z in 0..17; the chunk is 1..16.
##
## Pure function of its input: safe to call from worker threads.
## Winding: Godot treats clockwise triangles (seen from the front) as front faces.
extends RefCounted

const Blocks = preload("res://scripts/voxel/blocks.gd")

const CS := 16
const P := 18
const STRIDES := [1, 18, 324]  # padded strides for x, y, z


## Returns mesh arrays (Mesh.ARRAY_MAX long) or an empty Array when nothing is visible.
static func build(padded: PackedByteArray) -> Array:
	var colors: PackedColorArray = Blocks.vertex_colors
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	var mask := PackedInt32Array()
	mask.resize(CS * CS)
	var base := 1 + P + P * P  # padded index of chunk-local (0, 0, 0)

	for d in 3:
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var sd: int = STRIDES[d]
		var su: int = STRIDES[u]
		var sv: int = STRIDES[v]
		for side in 2:
			var back := side == 0
			var nstep := -sd if back else sd
			var nrm := Vector3.ZERO
			nrm[d] = -1.0 if back else 1.0
			for slice in CS:
				# 1) Mask of visible faces in this slice.
				var n := 0
				var any := false
				var row_base := base + slice * sd
				for j in CS:
					var idx := row_base + j * sv
					for i in CS:
						var b := padded[idx]
						if b != 0 and padded[idx + nstep] == 0:
							mask[n] = b
							any = true
						else:
							mask[n] = 0
						n += 1
						idx += su
				if not any:
					continue

				# 2) Greedily merge the mask into rectangles.
				var plane := float(slice) if back else float(slice + 1)
				n = 0
				for j in CS:
					var i := 0
					while i < CS:
						var b := mask[n]
						if b == 0:
							i += 1
							n += 1
							continue
						var w := 1
						while i + w < CS and mask[n + w] == b:
							w += 1
						var h := 1
						var stop := false
						while j + h < CS:
							var row := n + h * CS
							for k in w:
								if mask[row + k] != b:
									stop = true
									break
							if stop:
								break
							h += 1
						for hh in h:
							var row2 := n + hh * CS
							for k in w:
								mask[row2 + k] = 0

						# 3) Emit the quad.
						var c0 := Vector3.ZERO
						c0[d] = plane
						c0[u] = float(i)
						c0[v] = float(j)
						var c1 := c0
						c1[u] = float(i + w)
						var c2 := c1
						c2[v] = float(j + h)
						var c3 := c0
						c3[v] = float(j + h)
						var vi := verts.size()
						verts.append(c0)
						verts.append(c1)
						verts.append(c2)
						verts.append(c3)
						var col := colors[b]
						for q in 4:
							normals.append(nrm)
							cols.append(col)
						# cross(u, v) points along +d, so (c0, c1, c2) is counter-clockwise
						# seen from +d. Front faces must be clockwise from the viewer.
						if back:
							indices.append(vi)
							indices.append(vi + 1)
							indices.append(vi + 2)
							indices.append(vi)
							indices.append(vi + 2)
							indices.append(vi + 3)
						else:
							indices.append(vi)
							indices.append(vi + 2)
							indices.append(vi + 1)
							indices.append(vi)
							indices.append(vi + 3)
							indices.append(vi + 2)
						i += w
						n += w

	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
