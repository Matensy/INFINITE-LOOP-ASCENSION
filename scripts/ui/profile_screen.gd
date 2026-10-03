extends Control
## Profile: rank hero card, statistics grid, favourites and achievements.

var main: Node


func _ready() -> void:
	UiKit.full_rect(self)
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 36 + int(safe.position.x), 30 + int(safe.position.y), 36 + int(safe.size.x), 24 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(14)
	root.add_child(col)
	var header := UiKit.hbox(12)
	header.add_child(UiKit.icon_button("back", func(): main.back(), 80))
	var t := UiKit.title(tr("PROFILE"), 44, p.ui_text)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
	var pad := UiKit.spacer(0)
	pad.custom_minimum_size = Vector2(80, 0)
	header.add_child(pad)
	col.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := UiKit.vbox(16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var stats: Dictionary = Save.stats()
	var hero := UiKit.vbox(6)
	hero.add_child(UiKit.caption(tr("RANK"), Color(p.ui_text, 0.5), 18, HORIZONTAL_ALIGNMENT_CENTER))
	hero.add_child(UiKit.gradient_title(tr(Game.title_key()), 54, p.lit, p.lit2))
	var chips := UiKit.hbox(8)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UiKit.chip("%s %s" % [tr("LEVEL"), I18n.format_int(Save.current_level())], p.lit))
	var stars := Game.prestige_stars()
	if stars > 0:
		chips.add_child(UiKit.chip("✦ %d" % stars, p.lit2, true))
	hero.add_child(chips)
	if stars > 0:
		hero.add_child(UiKit.label(tr("PRESTIGE_HELP"), 19, Color(p.ui_text, 0.45)))
	body.add_child(UiKit.card(hero, 36, 30))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var best_time := float(stats.get("fastest_solve", -1.0))
	var fewest := int(stats.get("fewest_moves", -1))
	var none := Color(0, 0, 0, 0)
	var tiles := [
		[I18n.format_int(int(stats.get("total_solved", 0))), "PUZZLES_SOLVED", p.lit],
		[I18n.format_int(Save.highest_level()), "HIGHEST_LEVEL", p.lit2],
		[str(int(round(float(stats.get("hardest_solve", 0.0))))), "HARDEST_PUZZLE", p.lit],
		[I18n.format_int(int(stats.get("perfect_solves", 0))), "PERFECT_SOLVES", p.lit2],
		[I18n.format_time(best_time) if best_time >= 0.0 else "—", "BEST_TIME", none],
		[str(fewest) if fewest >= 0 else "—", "FEWEST_MOVES", none],
		[I18n.format_int(int(stats.get("total_moves", 0))), "TOTAL_MOVES", none],
		["%.1f" % Statistics.average_moves(stats), "AVERAGE_MOVES", none],
		["%d · %d" % [int(stats.get("current_streak", 0)), int(stats.get("longest_streak", 0))], "STREAK", none],
		[I18n.format_int(int(stats.get("no_hint_solves", 0))), "NO_HINT_SOLVES", none],
		[I18n.format_int(int(stats.get("daily_solved", 0))), "DAILY_SOLVED", none],
		[I18n.format_int(int(stats.get("boss_solved", 0))), "BOSSES", none],
	]
	for tile in tiles:
		grid.add_child(UiKit.stat_tile(tile[0], tr(tile[1]), p, tile[2]))
	body.add_child(grid)
	body.add_child(UiKit.stat_tile(I18n.format_time(float(stats.get("total_time", 0.0))), tr("TOTAL_TIME"), p))

	var hardest := str(stats.get("hardest_code", ""))
	if hardest != "":
		body.add_child(UiKit.button(tr("REPLAY_HARDEST"), _replay_code.bind(hardest), 82))

	var favs: Array = Game.favorites()
	if not favs.is_empty():
		body.add_child(UiKit.caption("%s · %d" % [tr("FAVORITES"), favs.size()], Color(p.lit, 0.9), 19))
		for i in range(favs.size() - 1, maxi(-1, favs.size() - 11), -1):
			var b := UiKit.button("★  " + str(favs[i]), _replay_code.bind(str(favs[i])), 72)
			b.add_theme_font_size_override("font_size", 22)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			body.add_child(b)

	var unlocked: Dictionary = Save.data.get("achievements", {})
	var defs := AchievementSystem.definitions()
	body.add_child(UiKit.caption("%s · %d/%d" % [tr("ACHIEVEMENTS"), unlocked.size(), defs.size()], Color(p.lit, 0.9), 19))
	var ach_grid := GridContainer.new()
	ach_grid.columns = 2
	ach_grid.add_theme_constant_override("h_separation", 12)
	ach_grid.add_theme_constant_override("v_separation", 12)
	ach_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for def in defs:
		var id := str(def.get("id", ""))
		var got := unlocked.has(id)
		var row := UiKit.hbox(12)
		var badge := VectorIcon.new("trophy" if got else "lock", p.lit if got else Color(p.ui_text, 0.35))
		badge.custom_minimum_size = Vector2(40, 40)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var texts := UiKit.vbox(2)
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_child(UiKit.label(tr("ACH_" + id.to_upper()), 21, p.ui_text if got else Color(p.ui_text, 0.5),
				UiTheme.semi_font(), HORIZONTAL_ALIGNMENT_LEFT))
		texts.add_child(UiKit.label(tr("ACH_" + id.to_upper() + "_DESC"), 16, Color(p.ui_text, 0.45), null, HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(texts)
		var c := UiKit.card(row, 26, 18)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.modulate.a = 1.0 if got else 0.7
		ach_grid.add_child(c)
	body.add_child(ach_grid)
	body.add_child(UiKit.spacer(20))


func _replay_code(code: String) -> void:
	var req := SeedManager.parse_code(code)
	if req:
		Game.pending_request = req
		main.goto("game")


func on_back() -> bool:
	return false
