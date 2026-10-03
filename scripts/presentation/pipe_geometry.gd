class_name PipeGeometry
extends RefCounted
## Pre-tessellated pipe pieces (triangle lists in cell-local board units).
##
## Every tile is assembled from a few templates - a half curve per ordered
## pair of arms, a straight spoke per arm, discs and end beads - so drawing
## a board is only `Transform2D * PackedVector2Array` plus `append_array`
## (all native code). UV.x runs across the stroke (0..1) so a 1-D profile
## texture gives anti-aliased edges (core) or a soft halo (glow); discs use
## UV.x = 0.5 at the centre and 0 on the rim, which yields a radial falloff.

const ARC_STEP := PI / 24.0
const DISC_SEGMENTS := 20
const CAP_SEGMENTS := 8

static var _cache: Dictionary = {}

var dir_count := 4
var apothem := 0.5
var unit := 1.0
## half[a * dir_count + b] -> [points, uvs]: the half of the a-b connection
## that starts at arm a and ends at the connection midpoint.
var half_core: Array = []
var half_glow: Array = []
var spoke_core: Array = []
var spoke_glow: Array = []
## Soft round ends for glow halos, so a halo never ends in a hard edge:
## at an open arm tip, at the cell centre (spokes) and at a curve midpoint.
var tip_cap_glow: Array = []
## Round anti-aliased end for a core stroke at an open arm tip.
var tip_cap_core: Array = []
var centre_cap_glow: Array = []
var mid_cap_glow: Array = []
var core_width := 0.0
var glow_width := 0.0


static func for_topology(topo: Topology) -> PipeGeometry:
	var key := topo.kind
	if not _cache.has(key):
		_cache[key] = PipeGeometry.new(topo)
	return _cache[key]


func _init(topo: Topology) -> void:
	dir_count = topo.dir_count
	apothem = topo.apothem()
	unit = apothem * 2.0
	core_width = 0.16 * unit
	glow_width = 0.7 * unit
	var glow_half := glow_width * 0.5
	half_core.resize(dir_count * dir_count)
	half_glow.resize(dir_count * dir_count)
	mid_cap_glow.resize(dir_count * dir_count)
	for a in dir_count:
		var da := topo.dir_vector(a)
		for b in dir_count:
			if a == b:
				continue
			var db := topo.dir_vector(b)
			var key := a * dir_count + b
			if da.dot(db) < -0.999:
				# Opposite arms: a straight half from the edge to the centre.
				var line := PackedVector2Array([da * apothem, Vector2.ZERO])
				half_core[key] = strip(line, core_width, false, false)
				half_glow[key] = strip(line, glow_width, false, false)
				mid_cap_glow[key] = cap(Vector2.ZERO, -da, glow_half)
			else:
				half_core[key] = half_arc(da, db, core_width)
				half_glow[key] = half_arc(da, db, glow_width)
				var arc := arc_frame(da, db)
				var x: Vector2 = arc[0]
				var mid_dir := Vector2.from_angle(float(arc[2]) + float(arc[3]) * 0.5)
				var travel := mid_dir.rotated(signf(float(arc[3])) * PI * 0.5)
				mid_cap_glow[key] = cap(x + mid_dir * float(arc[1]), travel, glow_half)
	for d in dir_count:
		var dv := topo.dir_vector(d)
		var tip := dv * apothem
		var line := PackedVector2Array([Vector2.ZERO, tip])
		spoke_core.append(strip(line, core_width, false, false))
		spoke_glow.append(strip(line, glow_width, false, false))
		tip_cap_glow.append(cap(tip, dv, glow_half))
		tip_cap_core.append(cap(tip, dv, core_width * 0.5))
		centre_cap_glow.append(cap(Vector2.ZERO, -dv, glow_half))


## Circular arc joining the midpoints of two cell edges, tangent to both
## arm directions: [centre, radius, start angle, signed sweep]. The centre
## is where the two edge lines meet (a cell corner for neighbouring arms).
func arc_frame(da: Vector2, db: Vector2) -> Array:
	var x := (da + db) * (apothem / (1.0 + da.dot(db)))
	var pa := da * apothem
	var pb := db * apothem
	var a0 := (pa - x).angle()
	var sweep := wrapf((pb - x).angle() - a0, -PI, PI)
	return [x, (pa - x).length(), a0, sweep]


## First half (arm a -> midpoint) of the arc a-b as a stroke of `width`.
## The inner edge is clamped at the arc centre, so wide glow halos on tight
## curves become a clean pie slice instead of folding into spikes.
func half_arc(da: Vector2, db: Vector2, width: float) -> Array:
	var arc := arc_frame(da, db)
	var x: Vector2 = arc[0]
	var r: float = arc[1]
	var a0: float = arc[2]
	var sweep: float = float(arc[3]) * 0.5
	var half := width * 0.5
	var inner := maxf(r - half, 0.0)
	var outer := r + half
	var u_in := 0.5 + (r - inner) / width
	var n := maxi(3, ceili(absf(sweep) / ARC_STEP))
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in n:
		var d0 := Vector2.from_angle(a0 + sweep * float(i) / n)
		var d1 := Vector2.from_angle(a0 + sweep * float(i + 1) / n)
		var o0 := x + d0 * outer
		var o1 := x + d1 * outer
		pts.append_array([o0, x + d0 * inner, x + d1 * inner, o0, x + d1 * inner, o1])
		uvs.append_array([Vector2(0, 0), Vector2(u_in, 0), Vector2(u_in, 1), Vector2(0, 0), Vector2(u_in, 1), Vector2(0, 1)])
	return [pts, uvs]


## Half-disc end cap facing `dir` (radial uv: 0.5 at `at`, 0 on the rim).
static func cap(at: Vector2, dir: Vector2, radius: float) -> Array:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	_cap(pts, uvs, at, dir.normalized(), radius)
	return [pts, uvs]


## Triangle list for a polyline of constant width, optional round caps.
static func strip(line: PackedVector2Array, width: float, cap_start: bool, cap_end: bool) -> Array:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var n := line.size()
	var half := width * 0.5
	var normals := PackedVector2Array()
	normals.resize(n)
	for i in n:
		var d := Vector2.ZERO
		if i > 0:
			d += (line[i] - line[i - 1]).normalized()
		if i < n - 1:
			d += (line[i + 1] - line[i]).normalized()
		d = d.normalized()
		normals[i] = Vector2(-d.y, d.x) * half
	for i in n - 1:
		var l0 := line[i] + normals[i]
		var r0 := line[i] - normals[i]
		var l1 := line[i + 1] + normals[i + 1]
		var r1 := line[i + 1] - normals[i + 1]
		pts.append_array([l0, r0, r1, l0, r1, l1])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	if cap_start:
		_cap(pts, uvs, line[0], -(line[1] - line[0]).normalized(), half)
	if cap_end:
		_cap(pts, uvs, line[n - 1], (line[n - 1] - line[n - 2]).normalized(), half)
	return [pts, uvs]


static func _cap(pts: PackedVector2Array, uvs: PackedVector2Array, at: Vector2, dir: Vector2, half: float) -> void:
	var base := dir.angle() - PI * 0.5
	for i in CAP_SEGMENTS:
		var a0 := base + PI * float(i) / CAP_SEGMENTS
		var a1 := base + PI * float(i + 1) / CAP_SEGMENTS
		pts.append_array([at, at + Vector2.from_angle(a0) * half, at + Vector2.from_angle(a1) * half])
		uvs.append_array([Vector2(0.5, 0), Vector2(0, 0), Vector2(0, 0)])


## 1-D cross-section profile: crisp anti-aliased core (`sharp`) or a soft
## gaussian-like glow. UV.x of every template samples it.
static func profile_texture(sharp: bool) -> ImageTexture:
	var w := 64
	var img := Image.create(w, 4, false, Image.FORMAT_RGBA8)
	for x in w:
		var u := absf(((x + 0.5) / w) * 2.0 - 1.0)
		var a := clampf((1.0 - u) * 6.0, 0.0, 1.0) if sharp else pow(1.0 - u, 2.2)
		for y in 4:
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Disc (fan) of a given radius: centre uv 0.5, rim uv 0.
static func disc(radius: float, segments: int = DISC_SEGMENTS) -> Array:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		pts.append_array([Vector2.ZERO, Vector2.from_angle(a0) * radius, Vector2.from_angle(a1) * radius])
		uvs.append_array([Vector2(0.5, 0), Vector2(0, 0), Vector2(0, 0)])
	return [pts, uvs]


## Ring between two radii (two triangles per segment, uv across the ring).
static func ring(r_in: float, r_out: float, segments: int = DISC_SEGMENTS) -> Array:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in segments:
		var a0 := Vector2.from_angle(TAU * float(i) / segments)
		var a1 := Vector2.from_angle(TAU * float(i + 1) / segments)
		pts.append_array([a0 * r_out, a0 * r_in, a1 * r_in, a0 * r_out, a1 * r_in, a1 * r_out])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	return [pts, uvs]
