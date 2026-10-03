class_name HexTopology
extends Topology
## Pointy-top hexagonal grid stored in "odd-r" offset coordinates (odd rows
## are shifted half a cell to the right). Directions clockwise from east:
## 0 = E, 1 = SE, 2 = SW, 3 = W, 4 = NW, 5 = NE. Circumradius is 1 unit.

const SQRT3 := 1.7320508075688772
const EVEN_ROW: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1),
]
const ODD_ROW: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]


func _init(w: int, h: int) -> void:
	kind = Kind.HEX
	width = maxi(1, w)
	height = maxi(1, h)
	dir_count = 6
	_build_neighbors()


func _offset(_x: int, y: int, d: int) -> Vector2i:
	return ODD_ROW[d] if (y & 1) == 1 else EVEN_ROW[d]


func cell_center(cell: int) -> Vector2:
	var x := cell % width
	var y := cell / width
	return Vector2(SQRT3 * (x + 0.5 * (y & 1)) + SQRT3 * 0.5, 1.0 + 1.5 * y)


func board_size() -> Vector2:
	var w := SQRT3 * (width + (0.5 if height > 1 else 0.0))
	return Vector2(w, 1.5 * (height - 1) + 2.0)


func apothem() -> float:
	return SQRT3 * 0.5


func circumradius() -> float:
	return 1.0


func dir_angle(dir: int) -> float:
	return deg_to_rad(60.0 * dir)


func cell_polygon(cell: int) -> PackedVector2Array:
	var c := cell_center(cell)
	var pts := PackedVector2Array()
	for k in 6:
		pts.append(c + Vector2.from_angle(deg_to_rad(30.0 + 60.0 * k)))
	return pts


func cell_at(point: Vector2) -> int:
	var row_guess := roundi((point.y - 1.0) / 1.5)
	var best := -1
	var best_d := INF
	for y in range(row_guess - 1, row_guess + 2):
		if y < 0 or y >= height:
			continue
		var col_guess := floori(point.x / SQRT3 - 0.5 * (y & 1))
		for x in range(col_guess - 1, col_guess + 2):
			if x < 0 or x >= width:
				continue
			var c := y * width + x
			var dist := cell_center(c).distance_squared_to(point)
			if dist < best_d:
				best_d = dist
				best = c
	if best_d > 1.0:
		return -1
	return best
