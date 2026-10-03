class_name LevelPlanner
extends RefCounted
## Turns a PuzzleRequest into a LevelPlan (the difficulty vector).
##
## Variety: macro features (mode, shape) come from deterministic "decks" that
## are shuffled per block of levels, so consecutive levels never feel alike
## while any level can still be computed in O(1) without its predecessors.

const PLAN_SALT := 0x504C414E
const DECK_SIZE := 6
const MODE_DECK: Array[int] = [GameMode.LOOP, GameMode.CORE, GameMode.LOOP, GameMode.DARK, GameMode.CORE, GameMode.MULTI]
const IRREGULAR_SHAPES: Array[int] = [
	BoardShapes.Shape.DIAMOND, BoardShapes.Shape.ELLIPSE, BoardShapes.Shape.CROSS,
	BoardShapes.Shape.RING, BoardShapes.Shape.INFINITY, BoardShapes.Shape.STAR,
	BoardShapes.Shape.ORGANIC, BoardShapes.Shape.SPIRAL, BoardShapes.Shape.HOLES,
]
## Rough fraction of active cells that end up as rotatable tiles, per mode.
const OCCUPANCY: Array[float] = [0.8, 0.9, 0.88, 0.78]
## Reduced difficulty of the very first level that introduces a mechanic.
const INTRO_EASING := 0.7


static func plan(request: PuzzleRequest) -> LevelPlan:
	var p := LevelPlan.new()
	var rng := SeededRng.new(request.seed).fork(PLAN_SALT)
	var t := request.base_target()

	# --- Events (special levels at fixed intervals, endless) -------------
	if request.uses_progression():
		var ev := event_for_level(request.level)
		if not ev.is_empty():
			p.event = str(ev.get("id", ""))
			p.boss = bool(ev.get("boss", false))
			t *= float(ev.get("difficulty_mult", 1.0))

	# --- Mode -------------------------------------------------------------
	var intro := ""
	if request.force_mode >= 0:
		p.mode = clampi(request.force_mode, 0, GameMode.COUNT - 1)
	else:
		p.mode = _deck_mode(request, t)
		if request.uses_progression():
			intro = _intro_mechanic(request.level)
			match intro:
				"core":
					p.mode = GameMode.CORE
				"dark":
					p.mode = GameMode.DARK
				"multi":
					p.mode = GameMode.MULTI
				"portals":
					p.mode = GameMode.CORE
		p.mode = _event_mode(p.event, p.mode)
	if intro != "":
		t *= INTRO_EASING
	p.target = t

	var unl := DifficultyConfig.section("unlocks")
	var cfg := DifficultyConfig.section("planner")

	# --- Topology -----------------------------------------------------------
	var hex_unlock := float(unl.get("hex", 40))
	if request.force_topology >= 0:
		p.topology = request.force_topology
	elif intro == "hex":
		p.topology = Topology.Kind.HEX
	elif t >= hex_unlock:
		var hex_chance := clampf((t - hex_unlock) / 200.0, 0.12, float(cfg.get("hex_chance_max", 0.45)))
		p.topology = Topology.Kind.HEX if rng.chance(hex_chance) else Topology.Kind.SQUARE

	# --- Shape --------------------------------------------------------------
	var shape_unlock := float(unl.get("shapes", 12))
	if request.force_shape >= 0:
		p.shape = request.force_shape
	else:
		p.shape = _event_shape(p.event, -1)
		if p.shape < 0:
			p.shape = BoardShapes.Shape.RECT
			if t >= shape_unlock and intro == "":
				var shape_chance := clampf((t - shape_unlock) / 60.0, 0.15, float(cfg.get("shape_chance_max", 0.7)))
				if rng.chance(shape_chance):
					p.shape = _deck_shape(request)

	# --- Density / branching ------------------------------------------------
	match p.mode:
		GameMode.LOOP:
			var r := DifficultyConfig.range_of("planner", "loop_density", Vector2(0.5, 0.68))
			p.density = rng.range_float(r.x, r.y)
		GameMode.DARK:
			var r := DifficultyConfig.range_of("planner", "dark_density", Vector2(0.55, 0.85))
			p.density = rng.range_float(r.x, r.y)
		_:
			var r := DifficultyConfig.range_of("planner", "forest_fill", Vector2(0.82, 1.0))
			p.density = rng.range_float(r.x, r.y)
	var br := DifficultyConfig.range_of("planner", "branching", Vector2(0.15, 0.85))
	p.branching = rng.range_float(br.x, br.y)

	# --- Special mechanics --------------------------------------------------
	if p.mode == GameMode.CORE:
		p.cores = 1
	elif p.mode == GameMode.MULTI:
		var multi_unlock := float(unl.get("multi", 28))
		p.cores = clampi(2 + int((t - multi_unlock) / 70.0) + rng.range_int(-1, 1), 2, int(cfg.get("max_cores", 6)))
		if p.event == "fracture":
			p.cores = mini(p.cores + 2, int(cfg.get("max_cores", 6)))

	var unique_unlock := float(unl.get("unique", 22))
	# DARK boards almost never have a unique solution; their difficulty comes
	# from search depth instead, so PERFECT is only applied to other modes.
	if t >= unique_unlock and p.mode != GameMode.DARK:
		var uc := minf(float(cfg.get("unique_chance_max", 0.75)), 0.2 + (t - unique_unlock) * float(cfg.get("unique_chance_slope", 0.004)))
		p.require_unique = rng.chance(uc) or p.boss

	var portal_unlock := float(unl.get("portals", 50))
	if GameMode.uses_cores(p.mode) and (t >= portal_unlock or intro == "portals"):
		var base_portals := (t - portal_unlock) * float(cfg.get("portals_per_t", 0.012))
		p.portals = clampi(int(round(base_portals * rng.range_float(0.5, 1.5))) + 1, 1, int(cfg.get("max_portals", 8)))
		if intro == "portals":
			p.portals = 1

	var link_unlock := float(unl.get("links", 62))
	if t >= link_unlock or intro == "links" or p.event == "chaos":
		var base_links := (t - link_unlock) * float(cfg.get("links_per_t", 0.015))
		p.link_groups = clampi(int(round(base_links * rng.range_float(0.4, 1.4))) + 1, 1, int(cfg.get("max_link_groups", 14)))
		if p.event == "chaos":
			p.link_groups = mini(p.link_groups + 3, int(cfg.get("max_link_groups", 14)))
		if intro == "links":
			p.link_groups = 1
		p.link_size = 3 if t > 200.0 and rng.chance(0.4) else 2
		if rng.chance(0.35) and p.event != "chaos" and intro != "links":
			p.link_groups = 0

	if t < float(cfg.get("anchor_until", 8)):
		p.anchors = 1

	# --- Size ---------------------------------------------------------------
	_fit_size(p, rng, cfg)
	if p.mode == GameMode.LOOP and p.width * p.height > int(cfg.get("loop_unique_max_area", 500)):
		# Large LOOP boards are rarely unique; their size already carries the
		# difficulty, so PERFECT is reserved for smaller boards.
		p.require_unique = p.boss and p.width * p.height <= int(cfg.get("loop_unique_max_area", 500)) * 2
	if p.event == "mega_grid":
		p.width = mini(p.width + 2, int(cfg.get("max_side", 40)))
		p.height = mini(p.height + 3, int(cfg.get("max_side", 40)))

	p.max_attempts = int(cfg.get("max_attempts", 8))
	p.tolerance = float(cfg.get("tolerance", 0.18))
	p.node_limit = int(cfg.get("node_limit", 6000))
	p.theme = ThemeCatalog.theme_for(request, p.event)
	return p


## Event definition for a level, or {} when the level is ordinary. Events
## recur forever at their interval (largest interval wins).
static func event_for_level(level: int) -> Dictionary:
	for ev in DifficultyConfig.list("events"):
		var every := int(ev.get("every", 0))
		if every > 0 and level % every == 0:
			return ev
	return {}


## The mechanic first introduced at this exact level, or "".
static func _intro_mechanic(level: int) -> String:
	var unl := DifficultyConfig.section("unlocks")
	for key in ["core", "dark", "multi", "hex", "portals", "links"]:
		if unl.has(key) and DifficultyCurve.level_for_target(float(unl[key])) == level:
			return key
	return ""


static func _deck_mode(request: PuzzleRequest, t: float) -> int:
	var unl := DifficultyConfig.section("unlocks")
	var index := request.level - 1
	if not request.uses_progression():
		index = int(SeededRng.mix32(request.seed & 0xFFFFFFFF) % 1000003)
	var block := index / DECK_SIZE
	var deck: Array = []
	for m in MODE_DECK:
		var allowed := m
		if m == GameMode.CORE and t < float(unl.get("core", 9)):
			allowed = GameMode.LOOP
		elif m == GameMode.DARK and t < float(unl.get("dark", 15)):
			allowed = GameMode.CORE if t >= float(unl.get("core", 9)) else GameMode.LOOP
		elif m == GameMode.MULTI and t < float(unl.get("multi", 28)):
			allowed = GameMode.CORE if t >= float(unl.get("core", 9)) else GameMode.LOOP
		deck.append(allowed)
	var deck_rng := SeededRng.new(SeededRng.hash_ints([SeedManager.MASTER_SEED, block, 0x4D4F4445]))
	deck_rng.shuffle(deck)
	return deck[index % DECK_SIZE]


static func _deck_shape(request: PuzzleRequest) -> int:
	var index := request.level - 1
	if not request.uses_progression():
		index = int(SeededRng.mix32((request.seed >> 3) & 0xFFFFFFFF) % 1000003)
	var count := IRREGULAR_SHAPES.size()
	var block := index / count
	var deck: Array = IRREGULAR_SHAPES.duplicate()
	var deck_rng := SeededRng.new(SeededRng.hash_ints([SeedManager.MASTER_SEED, block, 0x53484150]))
	deck_rng.shuffle(deck)
	return deck[index % count]


static func _event_mode(event: String, mode: int) -> int:
	match event:
		"fracture":
			return GameMode.MULTI
		"void":
			return GameMode.DARK
		"ascension":
			return GameMode.MULTI
	return mode


static func _event_shape(event: String, fallback: int) -> int:
	match event:
		"galaxy":
			return BoardShapes.Shape.SPIRAL
		"void":
			return BoardShapes.Shape.HOLES
		"ascension":
			return BoardShapes.Shape.INFINITY
		"fracture":
			return BoardShapes.Shape.STAR
	return fallback


## Chooses width/height so the expected difficulty of the board matches the
## target, after accounting for the cost of the chosen mechanics.
static func _fit_size(p: LevelPlan, rng: SeededRng, cfg: Dictionary) -> void:
	var sc := DifficultyConfig.section("score")
	var mode_mult := float((sc.get("mode_multiplier", {}) as Dictionary).get(GameMode.id_of(p.mode), 1.0))
	var topo_mult := float(sc.get("hex_multiplier", 1.3)) if p.topology == Topology.Kind.HEX else 1.0
	var uniq := 1.0 + (float(sc.get("unique_bonus", 0.12)) if p.require_unique else 0.0)
	var specials := p.portals * float(sc.get("portal_weight", 2.5))
	specials += p.link_groups * p.link_size * float(sc.get("link_member_weight", 1.6))
	specials += maxi(0, p.cores - 1) * float(sc.get("extra_core_weight", 1.5))
	specials -= p.anchors * float(sc.get("lock_discount", 0.4))
	var budget := maxf(1.0, p.target / uniq - specials)
	var factor := float(cfg.get("expected_tile_factor", 0.75)) * mode_mult * topo_mult
	var expo := float(cfg.get("expected_tile_exponent", 0.9))
	var n_rot := maxf(float(cfg.get("min_rotatable", 5)), pow(budget / factor, 1.0 / expo))
	var occupancy := OCCUPANCY[p.mode]
	if GameMode.uses_cores(p.mode):
		occupancy *= p.density
	var fill := BoardShapes.FILL_RATIO[p.shape]
	var area := n_rot / maxf(0.2, occupancy * fill)
	# Portrait boards: rows / columns ratio, corrected for hex cell geometry.
	var ratio := rng.range_float(1.0, 1.45)
	if p.topology == Topology.Kind.HEX:
		ratio *= 1.1547
	var min_side := int(cfg.get("min_side", 3))
	var max_side := int(cfg.get("max_side", 40))
	var w := clampi(int(round(sqrt(area / ratio))), min_side, max_side)
	var h := clampi(int(round(area / float(w))), min_side, max_side)
	if p.shape != BoardShapes.Shape.RECT and mini(w, h) < BoardShapes.MIN_SIDE[p.shape]:
		p.shape = BoardShapes.Shape.RECT
		area = n_rot / maxf(0.2, occupancy)
		w = clampi(int(round(sqrt(area / ratio))), min_side, max_side)
		h = clampi(int(round(area / float(w))), min_side, max_side)
	p.width = w
	p.height = h


## Scales the board area (used by the generator's closed-loop correction).
static func rescale(p: LevelPlan, factor: float) -> LevelPlan:
	var q := p.duplicate_plan()
	var cfg := DifficultyConfig.section("planner")
	var min_side := int(cfg.get("min_side", 3))
	var max_side := int(cfg.get("max_side", 40))
	var s := sqrt(clampf(factor, 0.3, 3.0))
	q.width = clampi(int(round(p.width * s)), min_side, max_side)
	q.height = clampi(int(round(p.height * s)), min_side, max_side)
	if q.width == p.width and q.height == p.height and absf(factor - 1.0) > 0.08:
		var step := 1 if factor > 1.0 else -1
		if q.height <= q.width:
			q.height = clampi(q.height + step, min_side, max_side)
		else:
			q.width = clampi(q.width + step, min_side, max_side)
	return q
