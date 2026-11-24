extends Control
class_name SettingsMenu2D
## 主菜单与游戏内 ESC 菜单共用的设置页：
## 左栏：音频（主音量 / 音效 / 背景音乐）+ 打击感（顿帧 / 采样 / 特写 / 震动）+ 小地图（形状 / 大小 / 缩放）；
## 右栏：数据显示（射速 / 护甲 RHA / 弹药）+ 镜头与光学特效（缩放 / 震屏 / 弹道 / 镜内模糊与畸变）。
## 两边读写同一份 Progress 存档，修改即时生效并自动保存。

signal closed

const LEFT_COL_WIDTH := 500.0
const RIGHT_COL_WIDTH := 530.0

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
var _minimap_shape_buttons: Dictionary = {}
var _minimap_scale_slider: HSlider
var _minimap_scale_value: Label
var _minimap_zoom_slider: HSlider
var _minimap_zoom_value: Label
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
	panel.offset_left = -565
	panel.offset_right = 565
	panel.offset_top = -415
	panel.offset_bottom = 415
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.emphasize(
		PixelUI.label(header, "系统设置 // SETTINGS", PixelUI.FS_TITLE, PixelUI.AMBER), 3, 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var esc_hint := PixelUI.rich_label(header,
		"[right]%s 关闭 · 修改自动保存[/right]" % PixelUI.bb("[ESC]", PixelUI.GOLD), 20, PixelUI.DIM, 1)
	esc_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	esc_hint.custom_minimum_size = Vector2(270, 26)
	esc_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.75))
	rows.add_child(divider)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	columns.add_child(_build_left_column())
	columns.add_child(_build_right_column())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(footer)
	var debug_button := PixelUI.button("调试模式 // DEBUG", 44)
	debug_button.custom_minimum_size.x = 220
	debug_button.pressed.connect(_open_debug)
	footer.add_child(debug_button)
	_back_button = PixelUI.primary_button("返回", 44)
	_back_button.custom_minimum_size.x = 220
	_back_button.pressed.connect(close_menu)
	footer.add_child(_back_button)


func _open_debug() -> void:
	if _debug_menu != null:
		_debug_menu.open()


func _column_box(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = width
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	return panel


func _sep(parent: Node, col: Color = PixelUI.AMBER) -> void:
	var d := HSeparator.new()
	d.add_theme_color_override("color", Color(col, 0.38))
	parent.add_child(d)


func _build_left_column() -> Control:
	var panel := _column_box(LEFT_COL_WIDTH)
	var rows: VBoxContainer = panel.get_child(0)

	PixelUI.section_bar(rows, "音频", "AUDIO", PixelUI.CYAN)
	_sep(rows, PixelUI.CYAN)
	_add_volume_row(rows, "主音量", "master")
	_add_volume_row(rows, "音效", "sfx")
	_add_volume_row(rows, "背景音乐", "music")

	_sep(rows, PixelUI.AMBER)
	PixelUI.section_bar(rows, "打击感", "IMPACT", PixelUI.AMBER)
	_add_hitstop_row(rows)
	_add_sample_row(rows)
	_add_hit_fx_row(rows)
	_add_shake_scale_row(rows)

	_sep(rows, PixelUI.OK)
	PixelUI.section_bar(rows, "小地图与雷达", "MINIMAP", PixelUI.OK)
	_add_minimap_shape_row(rows)
	_add_minimap_scale_row(rows)
	_add_minimap_zoom_row(rows)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	return panel


func _build_right_column() -> Control:
	var panel := _column_box(RIGHT_COL_WIDTH)
	var rows: VBoxContainer = panel.get_child(0)

	PixelUI.section_bar(rows, "数据显示", "HUD FORMAT", PixelUI.AMBER)
	_sep(rows, PixelUI.AMBER)

	PixelUI.label(rows, "武器射速显示", 19, PixelUI.DIM)
	var fire_row := HBoxContainer.new()
	fire_row.add_theme_constant_override("separation", 8)
	rows.add_child(fire_row)
	_interval_button = _option_button("秒/发 // INTERVAL")
	_interval_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_interval_button.pressed.connect(func() -> void: _set_fire_mode("interval"))
	fire_row.add_child(_interval_button)
	_rpm_button = _option_button("RPM // 发/分钟")
	_rpm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rpm_button.pressed.connect(func() -> void: _set_fire_mode("rpm"))
	fire_row.add_child(_rpm_button)

	PixelUI.label(rows, "护甲 / 穿深显示", 19, PixelUI.DIM)
	var armor_disp_row := HBoxContainer.new()
	armor_disp_row.add_theme_constant_override("separation", 8)
	rows.add_child(armor_disp_row)
	for entry in [["value", "穿深值 // 46"], ["rha_mm", "RHA // 4.6mm"]]:
		var mode := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _set_armor_display(mode))
		armor_disp_row.add_child(button)
		_armor_display_buttons[mode] = button

	PixelUI.label(rows, "弹药显示", 19, PixelUI.DIM)
	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 8)
	rows.add_child(ammo_row)
	for entry in [["both", "图文"], ["numeric", "数值"], ["graphic", "图形"]]:
		var mode := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _set_ammo_display(mode))
		ammo_row.add_child(button)
		_ammo_buttons[mode] = button

	_sep(rows, PixelUI.CYAN)
	PixelUI.section_bar(rows, "镜头与光学特效", "OPTICS & FX", PixelUI.CYAN)

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 10)
	rows.add_child(zoom_row)
	var z_lbl := PixelUI.label(zoom_row, "镜头缩放", 19, PixelUI.DIM)
	z_lbl.custom_minimum_size.x = 128
	_zoom_slider = _make_slider()
	_zoom_slider.min_value = 20.0
	_zoom_slider.max_value = 200.0
	_zoom_slider.step = 10.0
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	zoom_row.add_child(_zoom_slider)
	_zoom_value = PixelUI.emphasize(PixelUI.label(zoom_row, "100%", 19, PixelUI.GOLD), 2, 1)
	_zoom_value.custom_minimum_size.x = 64
	_zoom_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_add_toggle_row(rows, "屏幕震动", _shake_buttons, _set_screen_shake)
	_add_toggle_row(rows, "弹道线条效果", _trail_buttons, _set_bullet_trail)
	_add_toggle_row(rows, "镜内运动模糊", _scope_blur_buttons, _set_scope_blur)
	_add_toggle_row(rows, "镜内畸变", _scope_distortion_buttons, _set_scope_distortion)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	PixelUI.rich_label(rows,
		"%s 局内随时按 ESC 调整，小地图/音效/视野立即生效" % PixelUI.bb("●", PixelUI.OK),
		18, PixelUI.DIM, 1)
	return panel


func _add_hitstop_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "命中顿帧", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	for entry in [[true, "开"], [false, "关"]]:
		var enabled := bool(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 84
		button.pressed.connect(func() -> void: _set_hitstop(enabled))
		line.add_child(button)
		_hitstop_buttons[enabled] = button


func _add_sample_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "采样命中音效", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	for entry in [[true, "开"], [false, "关"]]:
		var enabled := bool(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 84
		button.pressed.connect(func() -> void: _set_sample_impacts(enabled))
		line.add_child(button)
		_sample_buttons[enabled] = button


func _add_hit_fx_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "命中特写", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	for entry in [[2, "完整"], [1, "减弱"], [0, "关"]]:
		var level := int(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 76
		button.pressed.connect(func() -> void: _set_hit_fx_level(level))
		line.add_child(button)
		_hit_fx_buttons[level] = button


func _add_shake_scale_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "开火震动幅度", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	_shake_scale_slider = _make_slider()
	_shake_scale_slider.min_value = 0.0
	_shake_scale_slider.max_value = 1000.0
	_shake_scale_slider.step = 5.0
	_shake_scale_slider.value_changed.connect(_on_shake_scale_changed)
	line.add_child(_shake_scale_slider)
	_shake_scale_edit = LineEdit.new()
	_shake_scale_edit.custom_minimum_size = Vector2(68, 30)
	_shake_scale_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shake_scale_edit.max_length = 5
	_shake_scale_edit.add_theme_font_override("font", PixelUI.FONT)
	_shake_scale_edit.add_theme_font_size_override("font_size", 18)
	_shake_scale_edit.add_theme_color_override("font_color", PixelUI.GOLD)
	_shake_scale_edit.add_theme_color_override("caret_color", PixelUI.AMBER_BRIGHT)
	_shake_scale_edit.add_theme_stylebox_override("normal", _input_style(false))
	_shake_scale_edit.add_theme_stylebox_override("focus", _input_style(true))
	_shake_scale_edit.text_submitted.connect(func(_text: String) -> void: _commit_shake_scale())
	_shake_scale_edit.focus_exited.connect(_commit_shake_scale)
	line.add_child(_shake_scale_edit)
	PixelUI.label(line, "%", 19, PixelUI.DIM)


func _add_minimap_shape_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "小地图形状", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	for entry in [["square", "方形地图"], ["circle", "圆形雷达"]]:
		var shape := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _set_minimap_shape(shape))
		line.add_child(button)
		_minimap_shape_buttons[shape] = button


func _add_minimap_scale_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "小地图比例", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	_minimap_scale_slider = _make_slider()
	_minimap_scale_slider.min_value = 70.0
	_minimap_scale_slider.max_value = 150.0
	_minimap_scale_slider.step = 5.0
	_minimap_scale_slider.value_changed.connect(_on_minimap_scale_changed)
	line.add_child(_minimap_scale_slider)
	_minimap_scale_value = PixelUI.emphasize(PixelUI.label(line, "100%", 19, PixelUI.OK), 2, 1)
	_minimap_scale_value.custom_minimum_size.x = 60
	_minimap_scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _add_minimap_zoom_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "小地图缩放", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	_minimap_zoom_slider = _make_slider()
	_minimap_zoom_slider.min_value = 80.0
	_minimap_zoom_slider.max_value = 250.0
	_minimap_zoom_slider.step = 10.0
	_minimap_zoom_slider.value_changed.connect(_on_minimap_zoom_changed)
	line.add_child(_minimap_zoom_slider)
	_minimap_zoom_value = PixelUI.emphasize(PixelUI.label(line, "1.0×", 19, PixelUI.CYAN), 2, 1)
	_minimap_zoom_value.custom_minimum_size.x = 60
	_minimap_zoom_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12)
	style.border_color = PixelUI.AMBER_BRIGHT if focused else Color(PixelUI.AMBER, 0.55)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _add_toggle_row(parent: Node, title: String, store: Dictionary, callback: Callable) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, title, 19, PixelUI.DIM)
	label.custom_minimum_size.x = 136
	for entry in [[true, "开"], [false, "关"]]:
		var enabled := bool(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 100
		button.pressed.connect(func() -> void: callback.call(enabled))
		line.add_child(button)
		store[enabled] = button


func _option_button(text: String) -> Button:
	var button := PixelUI.button(text, 36)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.custom_minimum_size = Vector2(180, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.12, 0.15)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PixelUI.AMBER
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	return slider


func _add_volume_row(parent: Node, title: String, key: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var label := PixelUI.label(line, title, 19, PixelUI.DIM)
	label.custom_minimum_size.x = 88
	var slider := _make_slider()
	line.add_child(slider)
	var value := PixelUI.emphasize(PixelUI.label(line, "80%", 19, PixelUI.GOLD), 2, 1)
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


func _on_minimap_scale_changed(value: float) -> void:
	_minimap_scale_value.text = "%d%%" % int(round(value))
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.data["minimap_scale"] = clampf(roundf(value / 5.0) * 0.05, 0.70, 1.50)
	_save_timer.start()


func _on_minimap_zoom_changed(value: float) -> void:
	var z := clampf(roundf(value / 10.0) * 0.1, 0.80, 2.50)
	_minimap_zoom_value.text = "%.1f×" % z
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.data["minimap_zoom"] = z
	_save_timer.start()


func _on_shake_scale_changed(value: float) -> void:
	if _shake_scale_edit != null:
		_shake_scale_edit.text = str(int(round(value)))
	_save_timer.start()


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


func _set_minimap_shape(shape: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_minimap_shape"):
		p.set_minimap_shape(shape)
	_refresh_minimap_shape_buttons(shape)


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
	var mm_shape := "square"
	var mm_scale := 1.0
	var mm_zoom := 1.0
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
		mm_shape = String(p.minimap_shape()) if p.has_method("minimap_shape") else "square"
		mm_scale = float(p.minimap_scale()) if p.has_method("minimap_scale") else 1.0
		mm_zoom = float(p.minimap_zoom()) if p.has_method("minimap_zoom") else 1.0
	_set_slider("master", master * 100.0)
	_set_slider("sfx", sfx * 100.0)
	_set_slider("music", music * 100.0)
	_zoom_slider.set_value_no_signal(zoom)
	_zoom_value.text = "%d%%" % int(round(zoom))
	_shake_scale_slider.set_value_no_signal(shake_scale)
	_shake_scale_edit.text = str(int(round(shake_scale)))
	_minimap_scale_slider.set_value_no_signal(mm_scale * 100.0)
	_minimap_scale_value.text = "%d%%" % int(round(mm_scale * 100.0))
	_minimap_zoom_slider.set_value_no_signal(mm_zoom * 100.0)
	_minimap_zoom_value.text = "%.1f×" % mm_zoom
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
	_refresh_minimap_shape_buttons(mm_shape)


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
	p.data["minimap_scale"] = clampf(roundf(_minimap_scale_slider.value / 5.0) * 0.05, 0.70, 1.50)
	p.data["minimap_zoom"] = clampf(roundf(_minimap_zoom_slider.value / 10.0) * 0.1, 0.80, 2.50)
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


func _refresh_minimap_shape_buttons(shape: String) -> void:
	var names := {"square": "方形地图", "circle": "圆形雷达"}
	for key in _minimap_shape_buttons:
		var button: Button = _minimap_shape_buttons[key]
		button.text = ("▶ " if key == shape else "   ") + String(names.get(key, key))
		button.add_theme_color_override(
			"font_color", PixelUI.OK if key == shape else PixelUI.TEXT)


func _refresh_shake_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_shake_buttons, enabled)


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
	_refresh_toggle_buttons(_hitstop_buttons, enabled)


func _refresh_sample_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_sample_buttons, enabled)


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
