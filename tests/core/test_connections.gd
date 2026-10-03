extends TestCase
## Rotation, connection and win-condition rules on hand-built boards.

const N := 1
const E := 2
const S := 4
const W := 8


func _square(w: int, h: int, masks: Array, mode: int = GameMode.LOOP) -> Puzzle:
	var p := Puzzle.create(SquareTopology.new(w, h))
	for i in masks.size():
		p.masks[i] = masks[i]
	p.mode = mode
	p.finalize()
	return p


func test_two_ends_connect() -> void:
	var p := _square(2, 1, [E, W])
	assert_true(Validator.is_solved_rot(p, PackedInt32Array([0, 0])))
	assert_false(Validator.is_solved_rot(p, PackedInt32Array([1, 0])), "rotated away")


func test_boundary_connector_is_invalid() -> void:
	var p := _square(1, 1, [N])
	assert_false(Validator.is_solved_rot(p, PackedInt32Array([0])))
	var empty := _square(1, 1, [0])
	assert_true(Validator.is_solved_rot(empty, PackedInt32Array([0])))


func test_square_loop() -> void:
	# 2x2 ring of corners.
	var p := _square(2, 2, [E | S, W | S, N | E, N | W])
	assert_true(Validator.is_solved_rot(p, PackedInt32Array([0, 0, 0, 0])))
	assert_false(Validator.is_solved_rot(p, PackedInt32Array([1, 0, 0, 0])))
	assert_true(Validator.is_solved_rot(p, PackedInt32Array([4, 0, 8, 0])), "full turns")


func test_board_state_rotation_and_reset() -> void:
	var p := _square(2, 1, [E, W])
	p.start_rot = PackedInt32Array([1, 3])
	p.finalize()
	var s := BoardState.new(p)
	assert_false(s.is_solved())
	assert_eq(s.mask(0), S, "E rotated once is S")
	s.rotate(0, 3)
	assert_eq(s.mask(0), E)
	s.rotate(1, -3)
	assert_true(s.is_solved())
	s.reset()
	assert_false(s.is_solved())


func test_locked_tile_refuses_rotation() -> void:
	var p := _square(2, 1, [E, W])
	p.locked[0] = 1
	p.finalize()
	var s := BoardState.new(p)
	assert_eq(s.rotate(0, 1).size(), 0)
	assert_eq(s.rotate(1, 1).size(), 1)


func test_linked_group_rotates_together() -> void:
	var p := _square(3, 1, [E, E | W, W])
	p.link_groups = [PackedInt32Array([0, 2])]
	p.finalize()
	var s := BoardState.new(p)
	var changed := s.rotate(2, 1)
	assert_eq(changed.size(), 2)
	assert_eq(s.rot[0], 1)
	assert_eq(s.rot[2], 1)


func test_dark_mode_rules() -> void:
	var p := _square(2, 1, [E, 0], GameMode.DARK)
	assert_true(Validator.is_solved_rot(p, PackedInt32Array([0, 0])), "connector into empty neighbour")
	var q := _square(2, 1, [E, W], GameMode.DARK)
	assert_false(Validator.is_solved_rot(q, PackedInt32Array([0, 0])), "facing connectors")
	assert_false(Validator.is_solved_rot(q, PackedInt32Array([1, 2])), "connector off board")


func test_core_mode_requires_power_everywhere() -> void:
	# Line of three; core on the left.
	var p := _square(3, 1, [E, E | W, W], GameMode.CORE)
	p.cores = PackedInt32Array([0])
	p.finalize()
	assert_true(Validator.is_solved_rot(p, PackedInt32Array([0, 0, 0])))
	var owner := Connectivity.power(p, Validator.current_masks(p, PackedInt32Array([0, 0, 0])))
	assert_eq(Array(owner), [0, 0, 0])


func test_core_mode_rejects_unpowered_island() -> void:
	# Two separate dominoes, only one has a core: locally fine, globally not.
	var p := _square(2, 2, [E, W, E, W], GameMode.CORE)
	p.cores = PackedInt32Array([0])
	p.finalize()
	var masks := Validator.current_masks(p, PackedInt32Array([0, 0, 0, 0]))
	assert_eq(Validator.local_violations(p, masks, RuleSet.for_mode(GameMode.CORE)), 0)
	assert_false(Validator.is_solved(p, masks))


func test_multi_core_rejects_joined_cores() -> void:
	var p := _square(2, 1, [E, W], GameMode.MULTI)
	p.cores = PackedInt32Array([0, 1])
	p.finalize()
	assert_false(Validator.is_solved_rot(p, PackedInt32Array([0, 0])))
	var q := _square(4, 1, [E, W, E, W], GameMode.MULTI)
	q.cores = PackedInt32Array([0, 3])
	q.finalize()
	assert_true(Validator.is_solved_rot(q, PackedInt32Array([0, 0, 0, 0])))
	var owner := Connectivity.power(q, Validator.current_masks(q, PackedInt32Array([0, 0, 0, 0])))
	assert_eq(Array(owner), [0, 0, 1, 1])


func test_portal_links_components() -> void:
	# Cells 0 and 2 are far apart; a portal joins them.
	var p := _square(3, 1, [0, 0, 0], GameMode.CORE)
	p.cores = PackedInt32Array([0])
	p.portal_pairs = PackedInt32Array([0, 2])
	p.finalize()
	var masks := Validator.current_masks(p, PackedInt32Array([0, 0, 0]))
	var owner := Connectivity.power(p, masks)
	assert_eq(owner[2], 0, "powered through portal")
	assert_eq(owner[1], -1)


func test_matched_mask_and_distances() -> void:
	var p := _square(3, 1, [E, E | W, 0])
	var masks := Validator.current_masks(p, PackedInt32Array([0, 0, 0]))
	var good := Connectivity.matched_mask(p, masks)
	assert_eq(good[0], E)
	assert_eq(good[1], W, "east arm of middle is dangling")
	var dist := Connectivity.distances(p, masks, PackedInt32Array([0]))
	assert_eq(Array(dist), [0, 1, -1])


func test_puzzle_serialization_roundtrip() -> void:
	var p := _square(3, 2, [E, E | W | S, W, 0, N, 0], GameMode.CORE)
	p.cores = PackedInt32Array([1])
	p.start_rot = PackedInt32Array([1, 2, 3, 0, 1, 0])
	p.locked[4] = 1
	p.link_groups = [PackedInt32Array([0, 2])]
	p.meta = {"seed": 123, "level": 7}
	p.finalize()
	var q := Puzzle.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_not_null(q)
	assert_eq(Array(q.masks), Array(p.masks))
	assert_eq(Array(q.start_rot), Array(p.start_rot))
	assert_eq(q.locked[4], 1)
	assert_eq(Array(q.cores), [1])
	assert_eq(q.link_groups.size(), 1)
	assert_eq(int(q.meta["seed"]), 123)
	assert_eq(q.mode, GameMode.CORE)


func test_from_dict_rejects_garbage() -> void:
	assert_eq(Puzzle.from_dict({}), null)
	assert_eq(Puzzle.from_dict({"format": 1, "width": 2, "height": 2, "masks": [1]}), null)
	var bad := {"format": 1, "topology": "square", "width": 1, "height": 1, "mode": "loop",
		"active": Marshalls.raw_to_base64(PackedByteArray([1])), "locked": Marshalls.raw_to_base64(PackedByteArray([0])),
		"masks": [99], "start_rot": [0]}
	assert_eq(Puzzle.from_dict(bad), null, "mask out of range")
