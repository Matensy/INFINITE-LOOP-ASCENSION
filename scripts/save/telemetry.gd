class_name Telemetry
extends RefCounted
## Local-only telemetry ring buffer (never leaves the device). Used to
## balance the game from the debug screen.

const MAX_RECORDS := 300


static func record(save: Dictionary, entry: Dictionary) -> void:
	var list: Array = save.get("telemetry", [])
	var e := entry.duplicate()
	e["t"] = int(Time.get_unix_time_from_system())
	list.append(e)
	while list.size() > MAX_RECORDS:
		list.pop_front()
	save["telemetry"] = list


static func summary(save: Dictionary) -> Dictionary:
	var list: Array = save.get("telemetry", [])
	var solves := 0
	var abandons := 0
	var gen := 0.0
	var gen_n := 0
	var solve_time := 0.0
	var moves := 0
	var hints := 0
	var difficulty := 0.0
	for e in list:
		if e.has("generation_ms"):
			gen += float(e["generation_ms"])
			gen_n += 1
		match str(e.get("event", "")):
			"solve":
				solves += 1
				solve_time += float(e.get("solve_time", 0.0))
				moves += int(e.get("moves", 0))
				hints += int(e.get("hints", 0))
				difficulty += float(e.get("difficulty", 0.0))
			"abandon":
				abandons += 1
	return {
		"records": list.size(),
		"solves": solves,
		"abandons": abandons,
		"avg_generation_ms": gen / gen_n if gen_n > 0 else 0.0,
		"avg_solve_time": solve_time / solves if solves > 0 else 0.0,
		"avg_moves": float(moves) / solves if solves > 0 else 0.0,
		"avg_hints": float(hints) / solves if solves > 0 else 0.0,
		"avg_difficulty": difficulty / solves if solves > 0 else 0.0,
	}
