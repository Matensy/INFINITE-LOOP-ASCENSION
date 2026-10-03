extends TestCase


func test_rotate_mask_square() -> void:
	# N (bit0) rotated clockwise becomes E (bit1).
	assert_eq(Topology.rotate_mask(0b0001, 1, 4), 0b0010)
	assert_eq(Topology.rotate_mask(0b1000, 1, 4), 0b0001, "W -> N wraps")
	assert_eq(Topology.rotate_mask(0b0011, 2, 4), 0b1100)
	assert_eq(Topology.rotate_mask(0b0011, -1, 4), 0b1001, "counter-clockwise")
	assert_eq(Topology.rotate_mask(0b0101, 4, 4), 0b0101, "full turn is identity")


func test_rotate_mask_hex() -> void:
	assert_eq(Topology.rotate_mask(0b000001, 1, 6), 0b000010)
	assert_eq(Topology.rotate_mask(0b100000, 1, 6), 0b000001)
	assert_eq(Topology.rotate_mask(0b000011, 3, 6), 0b011000)


func test_period() -> void:
	assert_eq(Topology.period(0b0000, 4), 1, "empty")
	assert_eq(Topology.period(0b1111, 4), 1, "cross")
	assert_eq(Topology.period(0b0101, 4), 2, "straight")
	assert_eq(Topology.period(0b0011, 4), 4, "corner")
	assert_eq(Topology.period(0b010101, 6), 2, "hex tri")
	assert_eq(Topology.period(0b001001, 6), 3, "hex straight")
	assert_eq(Topology.period(0b000011, 6), 6, "hex bend")


func test_canonical_and_names() -> void:
	assert_eq(PieceCatalog.shape_name(0b0110, 4), "corner")
	assert_eq(PieceCatalog.shape_name(0b1010, 4), "straight")
	assert_eq(PieceCatalog.shape_name(0b1110, 4), "tee")
	assert_eq(PieceCatalog.shape_name(0b0100, 4), "end")
	assert_eq(PieceCatalog.shape_name(0b100100, 6), "straight")
	assert_eq(PieceCatalog.shape_name(0b101010, 6), "tri")


func test_square_neighbors() -> void:
	var t := SquareTopology.new(3, 2)
	# Cell 1 = (1, 0).
	assert_eq(t.neighbor(1, 0), -1, "north of top row")
	assert_eq(t.neighbor(1, 1), 2, "east")
	assert_eq(t.neighbor(1, 2), 4, "south")
	assert_eq(t.neighbor(1, 3), 0, "west")
	assert_eq(t.opposite(0), 2)
	assert_eq(t.opposite(3), 1)


func test_hex_neighbors_are_symmetric() -> void:
	var t := HexTopology.new(5, 6)
	for c in t.cell_count:
		for d in 6:
			var n := t.neighbor(c, d)
			if n >= 0:
				assert_eq(t.neighbor(n, t.opposite(d)), c, "hex neighbour symmetry c=%d d=%d" % [c, d])
				var dist := t.cell_center(c).distance_to(t.cell_center(n))
				assert_between(dist, 1.70, 1.76, "hex neighbour distance")


func test_hex_direction_angles_match_geometry() -> void:
	var t := HexTopology.new(4, 4)
	var c := t.index_of(1, 1)
	for d in 6:
		var n := t.neighbor(c, d)
		assert_true(n >= 0)
		var v := (t.cell_center(n) - t.cell_center(c)).normalized()
		assert_true(v.distance_to(t.dir_vector(d)) < 0.01, "dir %d vector" % d)


func test_square_direction_angles_match_geometry() -> void:
	var t := SquareTopology.new(3, 3)
	for d in 4:
		var n := t.neighbor(4, d)
		var v := (t.cell_center(n) - t.cell_center(4)).normalized()
		assert_true(v.distance_to(t.dir_vector(d)) < 0.01, "dir %d vector" % d)


func test_cell_at_roundtrip() -> void:
	for topo in [SquareTopology.new(6, 7), HexTopology.new(6, 7)]:
		var t: Topology = topo
		for c in t.cell_count:
			assert_eq(t.cell_at(t.cell_center(c)), c, "%s cell_at(center)" % t.kind_name())
		assert_eq(t.cell_at(Vector2(-5, -5)), -1)


func test_shapes_are_connected_and_nonempty() -> void:
	var rng := SeededRng.new(42)
	for kind in [Topology.Kind.SQUARE, Topology.Kind.HEX]:
		for shape in BoardShapes.NAMES.size():
			var t := TopologyFactory.create(kind, 11, 13)
			var active := BoardShapes.build(shape, t, rng)
			var count := 0
			for c in t.cell_count:
				count += active[c]
			assert_true(count >= 2, "shape %s not empty" % BoardShapes.shape_name(shape))
			# Flood fill from first active cell reaches all active cells.
			var start := active.find(1)
			var seen := {start: true}
			var stack := [start]
			while not stack.is_empty():
				var c: int = stack.pop_back()
				for d in t.dir_count:
					var n := t.neighbor(c, d)
					if n >= 0 and active[n] == 1 and not seen.has(n):
						seen[n] = true
						stack.append(n)
			assert_eq(seen.size(), count, "shape %s connected" % BoardShapes.shape_name(shape))
