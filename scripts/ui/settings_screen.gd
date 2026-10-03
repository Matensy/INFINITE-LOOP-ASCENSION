extends Control
## Settings: audio, haptics, visuals, accessibility, controls, language and
## data. Every change is applied live through Save.settings_changed.

var main: Node
var _confirm_reset := false
var _reset_btn: Button
var _section_box: VBoxContainer
var _overlay: Control


func _ready() -> void:
	UiKit.full_rect(self)
	var p := Themes.palette
	var safe := UiKit.safe_margins(get_viewport())
	var root := UiKit.margin(null, 36 + int(safe.position.x), 30 + int(safe.position.y), 36 + int(safe.size.x), 24 + int(safe.size.y))
	UiKit.full_rect(root)
	add_child(root)
	var col := UiKit.vbox(12)
	root.add_child(col)
	var header := UiKit.hbox(12)
	header.add_child(UiKit.icon_button("back", func(): main.back(), 80))
	var t := UiKit.title(tr("SETTINGS"), 44, p.ui_text)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
	header.add_child(UiKit.spacer(0))
	header.get_child(2).custom_minimum_size = Vector2(80, 0)
	col.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body := UiKit.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_section(body, "SECTION_AUDIO")
	_toggle(body, "SOUND", "sound")
	_slider(body, "SFX_VOLUME", "sfx_volume", 0.0, 1.0, 0.05)
	_toggle(body, "MUSIC", "music")
	_slider(body, "MUSIC_VOLUME", "music_volume", 0.0, 1.0, 0.05)

	_section(body, "SECTION_FEEDBACK")
	_toggle(body, "HAPTICS", "haptics")
	_slider(body, "HAPTIC_STRENGTH", "haptic_strength", 0.2, 1.0, 0.1)

	_section(body, "SECTION_VISUAL")
	var theme_ids := ["auto"]
	var theme_names := [tr("THEME_AUTO")]
	var unlocked: Array = Save.data.get("unlocked_themes", [])
	for id in ThemeCatalog.ids():
		if unlocked.has(id) or ThemeCatalog.is_unlocked(id, Save.highest_level()):
			theme_ids.append(id)
			theme_names.append(tr("THEME_" + id.to_upper()))
	_option(body, "THEME", "theme", theme_ids, theme_names)
	_option(body, "EFFECTS", "effects", ["high", "low"], [tr("EFFECTS_HIGH"), tr("EFFECTS_LOW")])
	_slider(body, "ANIMATION_SPEED", "animation_speed", 0.5, 2.0, 0.1)

	_section(body, "SECTION_ACCESSIBILITY")
	_toggle(body, "REDUCE_MOTION", "reduce_motion")
	_toggle(body, "HIGH_CONTRAST", "high_contrast")
	_toggle(body, "COLORBLIND", "colorblind")
	_slider(body, "UI_SCALE", "ui_scale", 0.8, 1.4, 0.05)

	_section(body, "SECTION_CONTROLS")
	_toggle(body, "LEFT_HANDED", "left_handed")
	_toggle(body, "SHOW_TIMER", "show_timer")
	_option(body, "DOUBLE_TAP", "double_tap", ["pin", "none"], [tr("DOUBLE_TAP_PIN"), tr("DOUBLE_TAP_ROTATE")])
	_option(body, "TWO_FINGER_TAP", "two_finger_tap", ["undo", "reset", "none"], [tr("ACTION_UNDO"), tr("ACTION_RESET"), tr("ACTION_NONE")])
	_section_box.add_child(UiKit.label(tr("CONTROLS_HELP"), 20, Color(p.ui_text, 0.5), null, HORIZONTAL_ALIGNMENT_LEFT))

	_section(body, "SECTION_LANGUAGE")
	var langs := ["auto"]
	var lang_names := [tr("LANGUAGE_AUTO")]
	for loc in I18n.LOCALES:
		langs.append(loc)
		lang_names.append(tr("LANGUAGE_" + loc.to_upper()))
	_option(body, "LANGUAGE", "language", langs, lang_names)

	_section(body, "SECTION_DATA")
	_section_box.add_child(UiKit.button(tr("DIAGNOSTICS"), _on_diagnostics, 80))
	_reset_btn = UiKit.button(tr("RESET_PROGRESS"), _on_reset, 80)
	_reset_btn.add_theme_color_override("font_color", p.warn)
	_section_box.add_child(_reset_btn)
	body.add_child(UiKit.label(tr("OFFLINE_NOTE"), 20, Color(p.ui_text, 0.4)))
	body.add_child(UiKit.spacer(20))


## Starts a titled card; following rows are added inside it.
func _section(parent: Control, key: String) -> void:
	parent.add_child(UiKit.spacer(8))
	parent.add_child(UiKit.caption(tr(key), Color(Themes.palette.lit, 0.9), 19))
	_section_box = UiKit.vbox(6)
	parent.add_child(UiKit.card(_section_box, 30, 22))


func _toggle(_parent: Control, label_key: String, setting: String) -> void:
	var cb := CheckButton.new()
	cb.text = tr(label_key)
	cb.button_pressed = bool(Save.setting(setting, false))
	cb.custom_minimum_size = Vector2(0, 70)
	cb.focus_mode = Control.FOCUS_NONE
	# Align the label with slider / option rows (no pill padding).
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		cb.add_theme_stylebox_override(state, flat)
	cb.add_theme_font_size_override("font_size", 26)
	cb.toggled.connect(func(on: bool): Save.set_setting(setting, on))
	_section_box.add_child(cb)


func _slider(_parent: Control, label_key: String, setting: String, lo: float, hi: float, step: float) -> void:
	var row := UiKit.hbox(12)
	var lbl := UiKit.label(tr(label_key), 26, Color(0, 0, 0, 0), null, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.custom_minimum_size = Vector2(230, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(lbl)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Save.setting(setting, hi))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 60)
	s.focus_mode = Control.FOCUS_NONE
	var val := UiKit.label(_format_value(s.value, hi), 21, Color(Themes.palette.ui_text, 0.5))
	val.custom_minimum_size = Vector2(76, 0)
	val.autowrap_mode = TextServer.AUTOWRAP_OFF
	s.value_changed.connect(func(v: float):
		val.text = _format_value(v, hi)
		Save.set_setting(setting, v)
	)
	row.add_child(s)
	row.add_child(val)
	_section_box.add_child(row)


## Volumes and strengths read as percentages, speeds and scales as factors.
static func _format_value(v: float, hi: float) -> String:
	if hi <= 1.0:
		return "%d%%" % roundi(v * 100.0)
	return "%.1f×" % v


func _option(_parent: Control, label_key: String, setting: String, values: Array, names: Array) -> void:
	var row := UiKit.hbox(12)
	var lbl := UiKit.label(tr(label_key), 26, Color(0, 0, 0, 0), null, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(280, 76)
	ob.focus_mode = Control.FOCUS_NONE
	var current := str(Save.setting(setting, values[0]))
	for i in values.size():
		ob.add_item(str(names[i]), i)
		if str(values[i]) == current:
			ob.select(i)
	ob.item_selected.connect(func(i: int): Save.set_setting(setting, values[i]))
	row.add_child(ob)
	_section_box.add_child(row)


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_btn.text = tr("RESET_CONFIRM")
		return
	Save.reset_progress()
	main.toast(tr("PROGRESS_RESET"))
	main.goto("menu", false)


func _on_diagnostics() -> void:
	_close_overlay()
	_overlay = UiKit.modal(self, DiagnosticsPanel.build(true, _close_overlay, false))


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func on_back() -> bool:
	if _overlay:
		_close_overlay()
		return true
	return false
