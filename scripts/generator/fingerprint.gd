class_name Fingerprint
extends RefCounted
## Anti-repetition. `compute` hashes the solution structure canonically
## (identical up to board symmetry => same fingerprint). `features` gives a
## coarse vector used to reject puzzles that merely *feel* the same.

const SHAPE_BINS: Array[String] = [
	"empty", "end", "straight", "corner", "tee", "cross",
	"bend_sharp", "bend_wide", "fan", "tri",
]
const SIMILARITY_THRESHOLD := 0.12


static func compute(puzzle: Puzzle) -> String:
	var best := ""
	for t in _transform_count(puzzle):
		var s := _serialize(puzzle, t)
		if best == "" or s < best:
			best = s
	return best.sha256_text().substr(0, 16)


static func _transform_count(puzzle: Puzzle) -> int:
	if puzzle.topology.kind != Topology.Kind.SQUARE:
		return 1
	return 8 if puzzle.topology.width == puzzle.topology.height else 4


## Square board symmetries: 0 id, 1 mirror-x, 2 mirror-y, 3 rot180,
## 4 rot90, 5 rot270, 6 transpose, 7 anti-transpose.
static func _map(t: int, x: int, y: int, w: int, h: int) -> Vector2i:
	match t:
		1: return Vector2i(w - 1 - x, y)
		2: return Vector2i(x, h - 1 - y)
		3: return Vector2i(w - 1 - x, h - 1 - y)
		4: return Vector2i(h - 1 - y, x)
		5: return Vector2i(y, w - 1 - x)
		6: return Vector2i(y, x)
		7: return Vector2i(h - 1 - y, w - 1 - x)
	return Vector2i(x, y)


## Direction mapping matching _map (N=0, E=1, S=2, W=3).
static func _map_dir(t: int, d: int) -> int:
	match t:
		1: return [0, 3, 2, 1][d]
		2: return [2, 1, 0, 3][d]
		3: return (d + 2) % 4
		4: return (d + 1) % 4
		5: return (d + 3) % 4
		6: return [3, 2, 1, 0][d]
		7: return [1, 0, 3, 2][d]
	return d


static func _serialize(puzzle: Puzzle, t: int) -> String:
	var topo := puzzle.topology
	var w := topo.width
	var h := topo.height
	var nw := h if t >= 4 else w
	var nh := w if t >= 4 else h
	var n := topo.cell_count
	var cells := PackedInt32Array()
	cells.resize(n)
	cells.fill(-1)
	var tags := PackedInt32Array()
	tags.resize(n)
	for c in n:
		var p := _map(t, c % w, c / w, w, h)
		var dst := p.y * nw + p.x
		if puzzle.active[c] == 0:
			continue
		var m := puzzle.masks[c]
		var mm := 0
		if topo.kind == Topology.Kind.SQUARE:
			for d in 4:
				if (m >> d) & 1 == 1:
					mm |= 1 << _map_dir(t, d)
		else:
			mm = m
		cells[dst] = mm
		var tag := 0
		if puzzle.core_index[c] >= 0:
			tag |= 1
		if puzzle.portal_of[c] >= 0:
			tag |= 2
		if puzzle.locked[c] == 1:
			tag |= 4
		if puzzle.link_of[c] >= 0:
			tag |= 8
		tags[dst] = tag
	return "%s|%d|%d|%s|%s|%s" % [topo.kind_name(), nw, nh, GameMode.id_of(puzzle.mode), str(cells), str(tags)]


## Coarse feature vector: macro structure + piece distribution.
static func features(puzzle: Puzzle) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.append(float(puzzle.mode))
	f.append(float(puzzle.topology.kind))
	f.append(puzzle.topology.width / 10.0)
	f.append(puzzle.topology.height / 10.0)
	var act := maxf(1.0, puzzle.active_count())
	f.append(act / float(puzzle.cell_count()))
	var hist := PieceCatalog.histogram(puzzle)
	for bin in SHAPE_BINS:
		f.append(float(hist.get(bin, 0)) / act)
	f.append(puzzle.cores.size() / 4.0)
	f.append(puzzle.portal_count() / 4.0)
	f.append(puzzle.link_groups.size() / 4.0)
	f.append(1.0 if puzzle.unique else 0.0)
	return f


## 0 = identical feel. Mode / topology / size differences dominate.
static func distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return 1.0
	var d := 0.0
	d += 1.0 if a[0] != b[0] else 0.0
	d += 1.0 if a[1] != b[1] else 0.0
	for i in range(2, a.size()):
		d += absf(a[i] - b[i]) * (0.5 if i < 5 else 1.0)
	return d


static func too_similar(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	return distance(a, b) < SIMILARITY_THRESHOLD
