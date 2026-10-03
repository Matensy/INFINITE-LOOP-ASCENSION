class_name BoardGlyphs
extends RefCounted
## Immediate-mode vector glyphs drawn over the board: core and portal rings,
## link badges and small labels. Pure functions of their arguments (board
## units), kept apart from BoardView's state, batching and input handling.


## Centered text of a given height in board units.
static func label(ci: CanvasItem, at: Vector2, text: String, height: float, col: Color) -> void:
	var font := UiTheme.bold_font()
	var px := 32
	var s := height / float(px)
	ci.draw_set_transform(at, 0.0, Vector2(s, s))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	ci.draw_string(font, Vector2(-w * 0.5, px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Anchored tiles get a small diamond on the hub, pinned tiles a ring.
static func anchor_marks(ci: CanvasItem, puzzle: Puzzle, state: BoardState, session: GameSession,
		palette: Palette, unit: float) -> void:
	var topo := puzzle.topology
	for c in puzzle.cell_count():
		if puzzle.active[c] == 0:
			continue
		if puzzle.locked[c] == 1 and state.mask(c) != 0:
			var p := topo.cell_center(c)
			var r := 0.075 * unit
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]),
					Color(palette.ui_text, 0.85))
		if session and session.pinned.size() > c and session.pinned[c] == 1:
			ci.draw_arc(topo.cell_center(c), 0.44 * unit, 0.0, TAU, 32, Color(palette.ui_accent, 0.6), 0.03 * unit, true)


## Linked tiles: a coloured badge per group (letters in colour-blind mode).
static func link_badges(ci: CanvasItem, puzzle: Puzzle, palette: Palette, unit: float) -> void:
	var topo := puzzle.topology
	for g in puzzle.link_groups.size():
		var col := palette.group_color(g)
		for c in puzzle.link_groups[g]:
			var p := topo.cell_center(c) + Vector2(0.31, -0.31) * unit
			ci.draw_circle(p, 0.075 * unit, col, true, -1.0, true)
			ci.draw_arc(p, 0.11 * unit, 0.0, TAU, 20, Color(col, 0.45), 0.02 * unit, true)
			if palette.colorblind:
				label(ci, p + Vector2(0.0, 0.2 * unit), char(65 + g % 26), 0.16 * unit, col)


## Three spinning arc segments around every energy core.
static func core_rings(ci: CanvasItem, puzzle: Puzzle, palette: Palette, time: float, unit: float) -> void:
	var topo := puzzle.topology
	for i in puzzle.cores.size():
		var p := topo.cell_center(puzzle.cores[i])
		var col := palette.core_color(i)
		var spin := time * 0.9 + i
		for seg in 3:
			var a0 := spin + seg * TAU / 3.0
			ci.draw_arc(p, 0.31 * unit, a0, a0 + TAU / 4.5, 12, Color(col, 0.85), 0.035 * unit, true)
		if palette.colorblind and puzzle.cores.size() > 1:
			label(ci, p + Vector2(0, 0.05 * unit), str(i + 1), 0.2 * unit, palette.bg_bottom)


## Portals: counter-rotating rings, paired by colour and letter.
static func portals(ci: CanvasItem, puzzle: Puzzle, palette: Palette, time: float, unit: float) -> void:
	var topo := puzzle.topology
	for i in puzzle.portal_count():
		var col := palette.group_color(i + 3)
		for k in 2:
			var p := topo.cell_center(puzzle.portal_pairs[i * 2 + k])
			for ring in 2:
				var r := (0.3 - ring * 0.08) * unit
				var spin := time * (1.4 if ring == 0 else -2.0)
				for seg in 3:
					var a0 := spin + seg * TAU / 3.0
					ci.draw_arc(p, r, a0, a0 + TAU / 5.0, 10, Color(col, 0.95 - ring * 0.3), 0.04 * unit, true)
			label(ci, p + Vector2(0.3, 0.38) * unit, char(65 + i % 26), 0.17 * unit, col)
