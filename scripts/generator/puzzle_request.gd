class_name PuzzleRequest
extends RefCounted
## Everything the generator needs to rebuild a puzzle deterministically:
## Puzzle = Generator(seed, level, bias, overrides).

enum Kind { LEVEL, DAILY, CUSTOM, ZEN, CHALLENGE, DEBUG }

const KIND_IDS: Array[String] = ["level", "daily", "custom", "zen", "challenge", "debug"]

var kind: int = Kind.LEVEL
var level: int = 1
var seed: int = 0
## Adaptive difficulty bias in percent, applied to the target difficulty.
var bias: int = 0
## Optional overrides (debug tools / challenge modes). -1 = planner decides.
var force_mode: int = -1
var force_topology: int = -1
var force_shape: int = -1
var force_target: float = -1.0
## Free label, e.g. the daily date "2026-10-03".
var label: String = ""
## Planner indexing for non-LEVEL kinds. Progression puzzles derive mode
## decks, events and mechanic introductions from the level number (exactly
## like the endless progression); free puzzles derive them from the seed.
var progression: bool = false


static func make(kind_value: int, level_value: int, seed_value: int, bias_value: int = 0) -> PuzzleRequest:
	var r := PuzzleRequest.new()
	r.kind = kind_value
	r.level = maxi(1, level_value)
	r.seed = seed_value
	r.bias = bias_value
	return r


func kind_id() -> String:
	return KIND_IDS[clampi(kind, 0, KIND_IDS.size() - 1)]


## True when the planner indexes decks/events by level number.
func uses_progression() -> bool:
	return kind == Kind.LEVEL or progression


## Target difficulty after bias and overrides (events are applied by the
## planner).
func base_target() -> float:
	if force_target > 0.0:
		return force_target
	return DifficultyCurve.target(level) * (1.0 + bias / 100.0)


func duplicate_request() -> PuzzleRequest:
	var r := PuzzleRequest.new()
	r.kind = kind
	r.level = level
	r.seed = seed
	r.bias = bias
	r.force_mode = force_mode
	r.force_topology = force_topology
	r.force_shape = force_shape
	r.force_target = force_target
	r.label = label
	r.progression = progression
	return r


func to_dict() -> Dictionary:
	return {
		"kind": kind_id(), "level": level, "seed": seed, "bias": bias,
		"force_mode": force_mode, "force_topology": force_topology,
		"force_shape": force_shape, "force_target": force_target, "label": label,
		"progression": progression,
	}


static func from_dict(d: Dictionary) -> PuzzleRequest:
	var r := PuzzleRequest.new()
	r.kind = maxi(0, KIND_IDS.find(str(d.get("kind", "level"))))
	r.level = maxi(1, int(d.get("level", 1)))
	r.seed = int(d.get("seed", 0))
	r.bias = clampi(int(d.get("bias", 0)), -90, 300)
	r.force_mode = int(d.get("force_mode", -1))
	r.force_topology = int(d.get("force_topology", -1))
	r.force_shape = int(d.get("force_shape", -1))
	r.force_target = float(d.get("force_target", -1.0))
	r.label = str(d.get("label", ""))
	r.progression = bool(d.get("progression", false))
	return r


## Stable key for caches.
func cache_key() -> String:
	return "%s:%d:%d:%d:%d:%d:%d:%.2f:%d" % [kind_id(), level, seed, bias, force_mode, force_topology,
			force_shape, force_target, int(uses_progression())]
