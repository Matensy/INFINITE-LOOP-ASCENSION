class_name DiagnosticsPanel
extends RefCounted
## Builds the bug-report panel: device info + engine logs with a copy button.


static func build(include_previous: bool, on_close: Callable, crashed: bool) -> Control:
	var p: Palette = (Engine.get_main_loop() as SceneTree).root.get_node("Themes").palette
	var box := UiKit.vbox(16)
	var title := UiKit.title(TranslationServer.translate("DIAGNOSTICS"), 38, p.ui_text)
	box.add_child(title)
	var msg := TranslationServer.translate("CRASH_DETECTED" if crashed else "DIAGNOSTICS_HELP")
	box.add_child(UiKit.label(msg, 22, Color(p.ui_text, 0.7)))
	var text := Diagnostics.report(include_previous)
	var view := TextEdit.new()
	view.text = text
	view.editable = false
	view.custom_minimum_size = Vector2(0, 420)
	view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(view)
	box.add_child(UiKit.primary_button(TranslationServer.translate("COPY_REPORT"), func():
		DisplayServer.clipboard_set(text)
		var main: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Main")
		if main and main.has_method("toast"):
			main.toast(TranslationServer.translate("REPORT_COPIED"))
	, p.lit, p.lit2, 92))
	box.add_child(UiKit.button(TranslationServer.translate("CLOSE"), on_close, 80))
	return box
