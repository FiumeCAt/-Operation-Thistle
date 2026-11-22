extends Control
class_name SettingsMenu2D
## 主菜单与游戏内 ESC 菜单共用的设置页：音频（主音量 / 音效 / 背景音乐）与游戏选项
## （射速单位、弹药显示、镜头缩放、屏幕震动、弹道线条效果）。
## 两边都是同一个组件，读写同一份 Progress 存档，选项与数值永远一致；
## 音量、缩放、屏幕震动修改后立即生效，修改自动保存。

signal closed

const COLUMN_WIDTH := 438.0

var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _interval_button: Button
var _rpm_button: Button
var _armor_display_buttons: Dictionary = {}
var _ammo_buttons: Dictionary = {}
var _shake_buttons: Dictionary = {}
var _trail_buttons: Dictionary = {}
var _scope_blur_buttons: Dictionary = {}
var _scope_distortion_buttons: Dictionary = {}
var _hitstop_buttons: Dictionary = {}
var _sample_buttons: Dictionary = {}
var _hit_fx_buttons: Dictionary = {}
var _shake_scale_slider: HSlider
var _shake_scale_edit: LineEdit
var _zoom_slider: HSlider
var _zoom_value: Label
var _back_button: Button
var _debug_menu: DebugMenu2D
var _save_timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	PixelUI.apply_theme(self)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.3
	_save_timer.timeout.connect(_save_settings)
	add_child(_save_timer)
	_build()
	_debug_menu = DebugMenu2D.new()
	_debug_menu.name = "DebugMenu2D"
	add_child(_debug_menu)
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -500
	panel.offset_right = 500
	panel.offset_top = -380
	panel.offset_bottom = 380
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "设置 // SETTINGS", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "ESC 关闭", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	columns.add_child(_build_audio())
	columns.add_child(_build_gameplay())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(footer)
	var debug_button := PixelUI.button("调试模式", 48)
	debug_button.custom_minimum_size.x = 200
	debug_button.pressed.connect(_open_debug)
	footer.add_child(debug_button)
	_back_button = PixelUI.button("返回", 48)
	_back_button.custom_minimum_size.x = 200
	_back_button.pressed.connect(close_menu)
	footer.add_child(_back_button)


func _open_debug() -> void:
	if _debug_menu != null:
		_debug_menu.open()


func _column(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = COLUMN_WIDTH
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)
	var header := PixelUI.label(rows, title, PixelUI.FS_BODY, PixelUI.AMBER)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	return panel


func _build_audio() -> Control:
	var panel := _column("音频 // AUDIO")
	var rows: VBoxContainer = panel.get_child(0)
	_add_volume_row(rows, "主音量", "master")
	_add_volume_row(rows, "音效", "sfx")
	_add_volume_row(rows, "背景音乐", "music")

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	PixelUI.label(rows, "打击感 // IMPACT", PixelUI.FS_BODY, PixelUI.AMBER)
	_add_hitstop_row(rows)
	_add_sample_row(rows)
	_add_hit_fx_row(rows)
	_add_shake_scale_row(rows)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	PixelUI.label(rows, "音量与打击感立即生效 · 自动保存", 20, PixelUI.DIM)
	return panel


## 命中顿帧开关：默认关闭，由玩家主动开启。
func _add_hitstop_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var label := PixelUI.label(line, "命中顿帧", 20, PixelUI.DIM)
	label.custom_minimum_size.x = 88
	for entry in [[true, "开"], [false, "关"]]:
		var enabled := bool(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 72
		button.pressed.connect(func() -> void: _set_hitstop(enabled))
		line.add_child(button)
		_hitstop_buttons[enabled] = button


## 外部采样命中：关掉即退回程序化三层，方便 A/B 对比与回退。
func _add_sample_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var label := PixelUI.label(line, "采样命中音效", 20, PixelUI.DIM)
	label.custom_minimum_size.x = 88
	for entry in [[true, "开"], [false, "关"]]:
		var enabled := bool(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 72
		button.pressed.connect(func() -> void: _set_sample_impacts(enabled))
		line.add_child(button)
		_sample_buttons[enabled] = button


## 命中特写：完整 / 减弱（默认）/ 关闭，只影响命中粒子，省性能。
func _add_hit_fx_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "命中特写", 20, PixelUI.DIM)
	label.custom_minimum_size.x = 88
	for entry in [[2, "完整"], [1, "减弱"], [0, "关"]]:
		var level := int(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 66
		button.pressed.connect(func() -> void: _set_hit_fx_level(level))
		line.add_child(button)
		_hit_fx_buttons[level] = button


## 开火震动幅度：滑块 0–1000%，右侧输入框可直接键入精确数值。
func _add_shake_scale_row(parent: Node) -> void:
	var label := PixelUI.label(parent, "开火震动幅度", 20, PixelUI.DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)

	_shake_scale_slider = _make_slider()
	_shake_scale_slider.min_value = 0.0
	_shake_scale_slider.max_value = 1000.0
	_shake_scale_slider.step = 5.0
	_shake_scale_slider.value_changed.connect(_on_shake_scale_changed)
	line.add_child(_shake_scale_slider)

	_shake_scale_edit = LineEdit.new()
	_shake_scale_edit.custom_minimum_size = Vector2(74, 32)
	_shake_scale_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shake_scale_edit.max_length = 5
	_shake_scale_edit.add_theme_font_override("font", PixelUI.FONT)
	_shake_scale_edit.add_theme_font_size_override("font_size", 19)
	_shake_scale_edit.add_theme_color_override("font_color", PixelUI.TEXT)
	_shake_scale_edit.add_theme_color_override("caret_color", PixelUI.AMBER_BRIGHT)
	_shake_scale_edit.add_theme_stylebox_override("normal", _input_style(false))
	_shake_scale_edit.add_theme_stylebox_override("focus", _input_style(true))
	_shake_scale_edit.text_submitted.connect(func(_text: String) -> void: _commit_shake_scale())
	_shake_scale_edit.focus_exited.connect(_commit_shake_scale)
	line.add_child(_shake_scale_edit)
	PixelUI.label(line, "%", 20, PixelUI.TEXT)


## 数字输入框的像素风底框：黑底 + 琥珀描边，聚焦时描边提亮。
func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.11)
	style.border_color = PixelUI.AMBER_BRIGHT if focused else Color(PixelUI.AMBER, 0.55)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _build_gameplay() -> Control:
	var panel := _column("游戏 // GAMEPLAY")
	var rows: VBoxContainer = panel.get_child(0)

	PixelUI.label(rows, "武器射速显示", 20, PixelUI.DIM)
	var fire_row := HBoxContainer.new()
	fire_row.add_theme_constant_override("separation", 8)
	rows.add_child(fire_row)
	_interval_button = _option_button("秒/发 // INTERVAL")
	_interval_button.pressed.connect(func() -> void: _set_fire_mode("interval"))
	fire_row.add_child(_interval_button)
	_rpm_button = _option_button("RPM // 发/分钟")
	_rpm_button.pressed.connect(func() -> void: _set_fire_mode("rpm"))
	fire_row.add_child(_rpm_button)

	PixelUI.label(rows, "护甲 / 穿深显示", 20, PixelUI.DIM)
	var armor_disp_row := HBoxContainer.new()
	armor_disp_row.add_theme_constant_override("separation", 8)
	rows.add_child(armor_disp_row)
	for entry in [["value", "穿深值 // 46"], ["rha_mm", "RHA // 4.6mm"]]:
		var mode := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.pressed.connect(func() -> void: _set_armor_display(mode))
		armor_disp_row.add_child(button)
		_armor_display_buttons[mode] = button

	PixelUI.label(rows, "弹药显示", 20, PixelUI.DIM)
	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 8)
	rows.add_child(ammo_row)
	for entry in [["both", "图文"], ["numeric", "数值"], ["graphic", "图形"]]:
		var mode := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.pressed.connect(func() -> void: _set_ammo_display(mode))
		ammo_row.add_child(button)
		_ammo_buttons[mode] = button

	PixelUI.label(rows, "镜头缩放", 20, PixelUI.DIM)
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 10)
	rows.add_child(zoom_row)
	_zoom_slider = _make_slider()
	_zoom_slider.min_value = 20.0
	_zoom_slider.max_value = 200.0
	_zoom_slider.step = 10.0
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	zoom_row.add_child(_zoom_slider)
	_zoom_value = PixelUI.label(zoom_row, "100%", 20, PixelUI.TEXT)
	_zoom_value.custom_minimum_size.x = 64
	_zoom_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_add_toggle_row(rows, "屏幕震动", _shake_buttons, _set_screen_shake)
	_add_toggle_row(rows, "弹道线条效果", _trail_buttons, _set_bullet_trail)
	_add_toggle_row(rows, "镜内运动模糊", _scope_blur_buttons, _set_scope_blur)
	_add_toggle_row(rows, "镜内畸变", _scope_distortion_buttons, _set_scope_distortion)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	PixelUI.label(rows, "全菜单共用同一份设置 · 修改立即保存", 20, PixelUI.DIM)
	return panel


func _add_toggle_row(parent: Node, title: String, store: Dictionary, callback: Callable) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, title, 20, PixelUI.DIM)
	label.custom_minimum_size.x = 136
	for entry in [[true, "开"], [false, "关"]]:
		var enabled := bool(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 92
		button.pressed.connect(func() -> void: callback.call(enabled))
		line.add_child(button)
		store[enabled] = button


func _option_button(text: String) -> Button:
	var button := PixelUI.button(text, 42)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.custom_minimum_size = Vector2(220, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.11, 0.12)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PixelUI.AMBER
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	return slider


func _add_volume_row(parent: Node, title: String, key: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var label := PixelUI.label(line, title, 20, PixelUI.DIM)
	label.custom_minimum_size.x = 88
	var slider := _make_slider()
	line.add_child(slider)
	var value := PixelUI.label(line, "80%", 20, PixelUI.TEXT)
	value.custom_minimum_size.x = 56
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sliders[key] = slider
	_values[key] = value
	slider.value_changed.connect(_on_volume_changed.bind(key))


func _on_volume_changed(value: float, key: String) -> void:
	var label: Label = _values.get(key)
	if label != null:
		label.text = "%d%%" % int(value)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if key == "music":
			sfx.apply_music_volume(value / 100.0)
		else:
			sfx.apply_volumes(
				_sliders["master"].value / 100.0, _sliders["sfx"].value / 100.0)
	_save_timer.start()


func _on_zoom_changed(value: float) -> void:
	_zoom_value.text = "%d%%" % int(value)
	_save_timer.start()


func _on_shake_scale_changed(value: float) -> void:
	if _shake_scale_edit != null:
		_shake_scale_edit.text = str(int(round(value)))
	_save_timer.start()


## 输入框提交：解析数字并夹到 0–1000，滑块同步到同一档位。
func _commit_shake_scale() -> void:
	if _shake_scale_slider == null or _shake_scale_edit == null:
		return
	var text := _shake_scale_edit.text.strip_edges()
	var value := _shake_scale_slider.value
	if text.is_valid_float():
		value = float(text)
	value = clampf(roundf(value), 0.0, 1000.0)
	_shake_scale_slider.set_value_no_signal(value)
	_shake_scale_edit.text = str(int(value))
	_save_timer.start()


func _set_hitstop(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_hitstop_enabled(enabled)
	_refresh_hitstop_buttons(enabled)


func _set_sample_impacts(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_sample_impacts(enabled)
	_refresh_sample_buttons(enabled)


func _set_hit_fx_level(level: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_hit_fx_level(level)
	_refresh_hit_fx_buttons(level)


func open() -> void:
	visible = true
	move_to_front()
	_load_values()
	# 接管焦点，避免 Enter 触发主菜单里仍处于焦点状态的「开始行动」。
	if _back_button != null:
		_back_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	if _debug_menu != null:
		_debug_menu.visible = false
	visible = false
	_save_settings()
	closed.emit()


func _load_values() -> void:
	var p := get_node_or_null("/root/Progress")
	var master := 0.8
	var sfx := 0.8
	var music := 0.8
	var fire_mode := "interval"
	var armor_mode := "value"
	var ammo_mode := "both"
	var zoom := 100.0
	var shake := true
	var bullet_trail := true
	var scope_blur := true
	var scope_distortion := true
	var hitstop := false
	var shake_scale := 100.0
	var sample_impacts := true
	var hit_fx_level := 1
	if p != null:
		master = float(p.data.get("volume", 0.8))
		sfx = float(p.data.get("sfx_volume", 0.8))
		music = float(p.data.get("music_volume", 0.8))
		fire_mode = String(p.data.get("fire_rate_display", "interval"))
		armor_mode = String(p.armor_display()) if p.has_method("armor_display") else "value"
		ammo_mode = String(p.data.get("ammo_display", "both"))
		zoom = float(p.data.get("view_zoom", 100))
		shake = bool(p.data.get("screen_shake", true))
		bullet_trail = bool(p.data.get("bullet_trail_enabled", true))
		scope_blur = bool(p.data.get("scope_motion_blur", true))
		scope_distortion = bool(p.data.get("scope_lens_distortion", true))
		hitstop = bool(p.data.get("hitstop_enabled", false))
		shake_scale = clampf(float(p.data.get("shake_scale", 100.0)), 0.0, 1000.0)
		sample_impacts = bool(p.data.get("sample_impacts", true))
		hit_fx_level = clampi(int(p.data.get("hit_fx_level", 1)), 0, 2)
	_set_slider("master", master * 100.0)
	_set_slider("sfx", sfx * 100.0)
	_set_slider("music", music * 100.0)
	_zoom_slider.set_value_no_signal(zoom)
	_zoom_value.text = "%d%%" % int(round(zoom))
	_shake_scale_slider.set_value_no_signal(shake_scale)
	_shake_scale_edit.text = str(int(round(shake_scale)))
	_refresh_fire_buttons(fire_mode)
	_refresh_armor_display_buttons(armor_mode)
	_refresh_ammo_buttons(ammo_mode)
	_refresh_shake_buttons(shake)
	_refresh_trail_buttons(bullet_trail)
	_refresh_scope_blur_buttons(scope_blur)
	_refresh_scope_distortion_buttons(scope_distortion)
	_refresh_hitstop_buttons(hitstop)
	_refresh_sample_buttons(sample_impacts)
	_refresh_hit_fx_buttons(hit_fx_level)


func _set_slider(key: String, value: float) -> void:
	var slider: HSlider = _sliders.get(key)
	if slider == null:
		return
	slider.set_value_no_signal(value)
	var label: Label = _values.get(key)
	if label != null:
		label.text = "%d%%" % int(round(value))


func _save_settings() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	p.data["volume"] = _sliders["master"].value / 100.0
	p.data["sfx_volume"] = _sliders["sfx"].value / 100.0
	p.data["music_volume"] = _sliders["music"].value / 100.0
	p.data["shake_scale"] = clampf(roundf(_shake_scale_slider.value), 0.0, 1000.0)
	p.data["view_zoom"] = clampf(roundf(_zoom_slider.value / 10.0) * 10.0, 20.0, 200.0)
	p.save_data()


func _set_fire_mode(mode: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_fire_rate_display(mode)
	_refresh_fire_buttons(mode)


func _set_armor_display(mode: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_armor_display"):
		p.set_armor_display(mode)
	_refresh_armor_display_buttons(mode)


func _set_ammo_display(mode: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_ammo_display(mode)
	_refresh_ammo_buttons(mode)


func _set_screen_shake(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_screen_shake(enabled)
	_refresh_shake_buttons(enabled)


## 弹道线条：仅影响枪口到弹丸的长曳光线，弹丸实体与飞行/命中逻辑保持不变。
func _set_bullet_trail(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_bullet_trail_enabled(enabled)
	_refresh_trail_buttons(enabled)


func _set_scope_blur(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_scope_motion_blur(enabled)
	_refresh_scope_blur_buttons(enabled)


func _set_scope_distortion(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_scope_lens_distortion(enabled)
	_refresh_scope_distortion_buttons(enabled)


func _refresh_fire_buttons(mode: String) -> void:
	_interval_button.text = ("▶ " if mode == "interval" else "   ") + "秒/发 // INTERVAL"
	_rpm_button.text = ("▶ " if mode == "rpm" else "   ") + "RPM // 发/分钟"
	_interval_button.add_theme_color_override(
		"font_color", PixelUI.AMBER_BRIGHT if mode == "interval" else PixelUI.TEXT)
	_rpm_button.add_theme_color_override(
		"font_color", PixelUI.AMBER_BRIGHT if mode == "rpm" else PixelUI.TEXT)


func _refresh_armor_display_buttons(mode: String) -> void:
	var names := {"value": "穿深值 // 46", "rha_mm": "RHA // 4.6mm"}
	for key in _armor_display_buttons:
		var button: Button = _armor_display_buttons[key]
		button.text = ("▶ " if key == mode else "   ") + String(names.get(key, key))
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if key == mode else PixelUI.TEXT)


func _refresh_ammo_buttons(mode: String) -> void:
	var names := {"both": "图文", "numeric": "数值", "graphic": "图形"}
	for key in _ammo_buttons:
		var button: Button = _ammo_buttons[key]
		button.text = ("▶ " if key == mode else "   ") + String(names.get(key, key))
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if key == mode else PixelUI.TEXT)


func _refresh_shake_buttons(enabled: bool) -> void:
	for key in _shake_buttons:
		var button: Button = _shake_buttons[key]
		var active := bool(key) == enabled
		button.text = ("▶ " if active else "   ") + ("开" if bool(key) else "关")
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)


func _refresh_scope_blur_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_scope_blur_buttons, enabled)


func _refresh_trail_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_trail_buttons, enabled)


func _refresh_scope_distortion_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_scope_distortion_buttons, enabled)


func _refresh_toggle_buttons(buttons: Dictionary, enabled: bool) -> void:
	for key in buttons:
		var button: Button = buttons[key]
		var active := bool(key) == enabled
		button.text = ("▶ " if active else "   ") + ("开" if bool(key) else "关")
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)


func _refresh_hitstop_buttons(enabled: bool) -> void:
	for key in _hitstop_buttons:
		var button: Button = _hitstop_buttons[key]
		var active := bool(key) == enabled
		button.text = ("▶ " if active else "   ") + ("开" if bool(key) else "关")
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)


func _refresh_sample_buttons(enabled: bool) -> void:
	for key in _sample_buttons:
		var button: Button = _sample_buttons[key]
		var active := bool(key) == enabled
		button.text = ("▶ " if active else "   ") + ("开" if bool(key) else "关")
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)


func _refresh_hit_fx_buttons(level: int) -> void:
	var names := {2: "完整", 1: "减弱", 0: "关"}
	for key in _hit_fx_buttons:
		var button: Button = _hit_fx_buttons[key]
		var active := int(key) == level
		button.text = ("▶ " if active else "   ") + String(names.get(int(key), "关"))
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _debug_menu != null and _debug_menu.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
