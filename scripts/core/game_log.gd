class_name GameLog
extends RefCounted
## Category based logger usable from any thread and from pure logic code.
## Enabled automatically in debug builds, silent (errors only) in release.

static var enabled: bool = OS.is_debug_build()
static var verbose: bool = false
static var sink: Callable = Callable()


static func info(category: String, message: String) -> void:
	if not enabled:
		return
	_emit("[%s] %s" % [category, message])


static func debug(category: String, message: String) -> void:
	if not enabled or not verbose:
		return
	_emit("[%s] %s" % [category, message])


static func warn(category: String, message: String) -> void:
	if not enabled:
		return
	var line := "[%s] WARNING: %s" % [category, message]
	_emit(line)
	push_warning(line)


static func error(category: String, message: String) -> void:
	var line := "[%s] ERROR: %s" % [category, message]
	_emit(line)
	push_error(line)


static func _emit(line: String) -> void:
	if sink.is_valid():
		sink.call(line)
	else:
		print(line)
