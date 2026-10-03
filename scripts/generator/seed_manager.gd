class_name SeedManager
extends RefCounted
## Deterministic seed derivation and shareable puzzle codes.
##
## Codes are plain data. They are parsed with strict validation and never
## evaluated or executed.
##   ASCENSION-<level>-<seed>[-P<bias>|-M<bias>]   progression puzzle
##   ASCENSION-F<level>-<seed>[-P|-M<bias>]         free puzzle (zen, ...)
##   ASCENSION-<seed>                               custom seed, level derived
##   DAILY-YYYY-MM-DD                               daily puzzle

const MASTER_SEED := 0x41534345  # "ASCE"
const CODE_PREFIX := "ASCENSION"
const DAILY_PREFIX := "DAILY"
const SEED_MIN := 100000000000
const SEED_SPAN := 900000000000
const MAX_LEVEL := 1000000000000
const MAX_CODE_LENGTH := 64
const CUSTOM_LEVEL_SPAN := 10000
## Daily difficulty by weekday (Monday first): relaxed start, brutal Sunday.
const DAILY_LEVELS: Array[int] = [40, 80, 150, 300, 600, 1200, 2500]


## 12 digit seed of endless level N.
static func level_seed(level: int) -> int:
	return _twelve_digits(SeededRng.hash_ints([MASTER_SEED, level, 0x4C56]), SeededRng.hash_ints([level, MASTER_SEED, 0x5345]))


static func daily_seed(date_label: String) -> int:
	var h1 := SeededRng.hash_string("DAILY|" + date_label)
	var h2 := SeededRng.hash_string(date_label + "|" + str(MASTER_SEED))
	return _twelve_digits(h1, h2)


## Fresh random seed for zen/challenge puzzles (non deterministic input,
## deterministic output once chosen).
static func random_seed(entropy: int) -> int:
	return _twelve_digits(SeededRng.mix32(entropy & 0xFFFFFFFF), SeededRng.mix32((entropy >> 20) ^ 0x7F4A7C15))


static func _twelve_digits(h1: int, h2: int) -> int:
	var hi := h1 % 900000
	var lo := h2 % 1000000
	return SEED_MIN + hi * 1000000 + lo


static func level_request(level: int, bias: int = 0) -> PuzzleRequest:
	return PuzzleRequest.make(PuzzleRequest.Kind.LEVEL, level, level_seed(level), bias)


## date: Dictionary from Time.get_date_dict_from_system() (year, month, day,
## weekday where 0 = Sunday).
static func daily_request(date: Dictionary) -> PuzzleRequest:
	var label := "%04d-%02d-%02d" % [int(date.get("year", 2026)), int(date.get("month", 1)), int(date.get("day", 1))]
	var weekday := int(date.get("weekday", 1))
	var monday_first := posmod(weekday - 1, 7)
	var r := PuzzleRequest.make(PuzzleRequest.Kind.DAILY, DAILY_LEVELS[monday_first], daily_seed(label))
	r.label = label
	return r


static func make_code(request: PuzzleRequest) -> String:
	if request.kind == PuzzleRequest.Kind.DAILY and request.label != "":
		return "%s-%s" % [DAILY_PREFIX, request.label]
	var prefix := "" if request.uses_progression() else "F"
	var code := "%s-%s%d-%d" % [CODE_PREFIX, prefix, request.level, request.seed]
	if request.bias > 0:
		code += "-P%d" % request.bias
	elif request.bias < 0:
		code += "-M%d" % -request.bias
	return code


## Parses a share code. Returns null when the text is not a valid code.
static func parse_code(text: String) -> PuzzleRequest:
	var code := text.strip_edges().to_upper().replace(" ", "")
	if code.is_empty() or code.length() > MAX_CODE_LENGTH:
		return null
	for ch in code:
		if not (ch in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-"):
			return null
	var parts := code.split("-", false)
	if parts.is_empty():
		return null
	if parts[0] == DAILY_PREFIX:
		return _parse_daily(parts)
	if parts[0] != CODE_PREFIX:
		# Bare number: treat as a custom seed.
		if parts.size() == 1 and parts[0].is_valid_int():
			return _custom_from_seed(parts[0])
		return null
	if parts.size() == 2:
		return _custom_from_seed(parts[1])
	if parts.size() < 3 or parts.size() > 4:
		return null
	var progression := true
	if parts[1].begins_with("F"):
		progression = false
		parts[1] = parts[1].substr(1)
	if not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return null
	if parts[1].length() > 13 or parts[2].length() > 15:
		return null
	var level := parts[1].to_int()
	var seed_value := parts[2].to_int()
	if level < 1 or level > MAX_LEVEL or seed_value < 0:
		return null
	var bias := 0
	if parts.size() == 4:
		var b := parts[3]
		if b.length() < 2 or not b.substr(1).is_valid_int():
			return null
		var amount := b.substr(1).to_int()
		if amount > 300:
			return null
		if b[0] == "P":
			bias = amount
		elif b[0] == "M":
			bias = -mini(amount, 90)
		else:
			return null
	var req := PuzzleRequest.make(PuzzleRequest.Kind.CUSTOM, level, seed_value, bias)
	req.progression = progression
	return req


static func _custom_from_seed(text: String) -> PuzzleRequest:
	if not text.is_valid_int() or text.length() > 15:
		return null
	var seed_value := text.to_int()
	if seed_value < 0:
		return null
	var level := 1 + int(SeededRng.hash_ints([seed_value]) % CUSTOM_LEVEL_SPAN)
	return PuzzleRequest.make(PuzzleRequest.Kind.CUSTOM, level, seed_value)


static func _parse_daily(parts: PackedStringArray) -> PuzzleRequest:
	if parts.size() != 4:
		return null
	for i in range(1, 4):
		if not parts[i].is_valid_int():
			return null
	var y := parts[1].to_int()
	var m := parts[2].to_int()
	var d := parts[3].to_int()
	if y < 2000 or y > 9999 or m < 1 or m > 12 or d < 1 or d > 31:
		return null
	if d > days_in_month(y, m):
		return null
	var label := "%04d-%02d-%02d" % [y, m, d]
	var unix := Time.get_unix_time_from_datetime_string(label + "T12:00:00")
	return daily_request(Time.get_date_dict_from_unix_time(int(unix)))


static func days_in_month(year: int, month: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	if month in [4, 6, 9, 11]:
		return 30
	return 31
