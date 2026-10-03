class_name AdaptiveDifficulty
extends RefCounted
## Observes how the player performs and nudges the *next* levels' difficulty
## (bias in percent). It never changes a puzzle after it was shown: the bias
## is locked into the PuzzleRequest when a level is first generated.

const MAX_BIAS := 25
const MIN_BIAS := -25
const SMOOTHING := 0.25
const HISTORY := 12


static func defaults() -> Dictionary:
	return {"modifier": 0.0, "history": []}


## Performance in [-1, 1]: positive = cruising, negative = struggling.
static func performance(info: Dictionary) -> float:
	var min_moves := maxf(1.0, float(info.get("min_moves", 1)))
	var moves := float(info.get("moves", min_moves))
	var time := float(info.get("time", 0.0))
	var hints := int(info.get("hints", 0))
	var difficulty := maxf(1.0, float(info.get("difficulty", 1.0)))
	# Expected seconds grow with the number of required taps and difficulty.
	var expected_time := 4.0 + min_moves * 1.2 + difficulty * 0.6
	var time_score := clampf((expected_time - time) / expected_time, -1.0, 1.0)
	var move_score := clampf((2.2 - moves / min_moves) / 1.2, -1.0, 1.0)
	var hint_score := -clampf(hints * 0.45, 0.0, 1.0)
	if bool(info.get("abandoned", false)):
		return -1.0
	return clampf(0.45 * time_score + 0.35 * move_score + hint_score + 0.1, -1.0, 1.0)


## Updates the adaptive state and returns the bias for upcoming levels.
static func update(state: Dictionary, info: Dictionary) -> int:
	var p := performance(info)
	var history: Array = state.get("history", [])
	history.append(snappedf(p, 0.01))
	while history.size() > HISTORY:
		history.pop_front()
	state["history"] = history
	var m := float(state.get("modifier", 0.0))
	m = m * (1.0 - SMOOTHING) + p * SMOOTHING
	state["modifier"] = clampf(m, -1.0, 1.0)
	return current_bias(state)


static func current_bias(state: Dictionary) -> int:
	var m := float(state.get("modifier", 0.0))
	return clampi(int(round(m * MAX_BIAS)), MIN_BIAS, MAX_BIAS)
