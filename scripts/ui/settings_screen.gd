extends Control
## Settings: audio, haptics, visuals, accessibility, controls, language and
## data. Every change is applied live through Save.settings_changed.

var main: Node
var _confirm_reset := false
var _reset_btn: Button


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
	header.add_child(UiKit.icon_button("←", func(): main.back(), 80))
	var t := UiKit.title(tr("SETTINGS"), 40, p.ui_accent)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(t)
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
	body.add_child(UiKit.label(tr("CONTROLS_HELP"), 20, p.ui_dim, null, HORIZONTAL_ALIGNMENT_LEFT))

	_section(body, "SECTION_LANGUAGE")
	var langs := ["auto"]
	var lang_names := [tr("LANGUAGE_AUTO")]
	for loc in I18n.LOCALES:
		langs.append(loc)
		lang_names.append(tr("LANGUAGE_" + loc.to_upper()))
	_option(body, "LANGUAGE", "language", langs, lang_names)

	_section(body, "SECTION_DATA")
	_reset_btn = UiKit.button(tr("RESET_PROGRESS"), _on_reset, 80)
	body.add_child(_reset_btn)
	body.add_child(UiKit.label(tr("OFFLINE_NOTE"), 20, p.ui_dim))


func _section(parent: Control, key: String) -> void:
	parent.add_child(UiKit.spacer(10))
	parent.add_child(UiKit.label(tr(key), 24, Themes.palette.ui_accent, UiTheme.title_bold_font(), HORIZONTAL_ALIGNMENT_LEFT))
	parent.add_child(HSeparator.new())


func _toggle(parent: Control, label_key: String, setting: String) -> void:
	var cb := CheckButton.new()
	cb.text = tr(label_key)
	cb.button_pressed = bool(Save.setting(setting, false))
	cb.custom_minimum_size = Vector2(0, 70)
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool): Save.set_setting(setting, on))
	parent.add_child(cb)


func _slider(parent: Control, label_key: String, setting: String, lo: float, hi: float, step: float) -> void:
	var row := UiKit.hbox(12)
	var lbl := UiKit.label(tr(label_key), 26, Color(0, 0, 0, 0), null, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.custom_minimum_size = Vector2(250, 0)
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
	var val := UiKit.label("%.2f" % s.value, 22, Themes.palette.ui_dim)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v: float):
		val.text = "%.2f" % v
		Save.set_setting(setting, v)
	)
	row.add_child(s)
	row.add_child(val)
	parent.add_child(row)


func _option(parent: Control, label_key: String, setting: String, values: Array, names: Array) -> void:
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
	parent.add_child(row)


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_btn.text = tr("RESET_CONFIRM")
		return
	Save.reset_progress()
	main.toast(tr("PROGRESS_RESET"))
	main.goto("menu", false)


func on_back() -> bool:
	return false
