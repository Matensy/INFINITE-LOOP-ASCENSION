class_name DifficultyCurve
extends RefCounted
## Maps level numbers to target difficulty and scores to named tiers.
## T(N) grows without bound: there is no last level.


static func target(level: int) -> float:
	var base := DifficultyConfig.num("curve", "base", 4.0)
	var scale := DifficultyConfig.num("curve", "scale", 5.0)
	var exponent := DifficultyConfig.num("curve", "exponent", 2.5)
	var l := log(float(maxi(level, 1)) + 1.0) / log(10.0)
	return base + scale * pow(l, exponent)


## Smallest level whose target reaches `t` (inverse of target()).
static func level_for_target(t: float) -> int:
	if t <= target(1):
		return 1
	var lo := 1
	var hi := 2
	while target(hi) < t and hi < 1 << 52:
		lo = hi
		hi *= 2
	while hi - lo > 1:
		var mid := lo + (hi - lo) / 2
		if target(mid) < t:
			lo = mid
		else:
			hi = mid
	return hi


static func tiers() -> Array:
	return DifficultyConfig.list("tiers")


## Tier id ("tutorial" ... "ascension") of a difficulty score.
static func tier_id(score: float) -> String:
	var id := "tutorial"
	for t in tiers():
		if score >= float(t.get("min", 0)):
			id = str(t.get("id", id))
	return id


static func tier_index(score: float) -> int:
	var idx := 0
	var list := tiers()
	for i in list.size():
		if score >= float(list[i].get("min", 0)):
			idx = i
	return idx


## Translation key for the tier name.
static func tier_key(score: float) -> String:
	return "TIER_" + tier_id(score).to_upper()
