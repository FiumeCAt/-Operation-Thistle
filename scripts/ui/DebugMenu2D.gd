extends Control
class_name DebugMenu2D
## 调试模式：全局数值倍率调节（后坐力 / 散布 / 伤害 / 瞄准速度 / 移速 / 视野）。
## 倍率范围 0–100；滑条与文本框双向同步，文本框非法输入会提示并自动修正。
## 修改任意数值会自动启用调试，数值立即作用于运行时并随设置保存。

signal closed
signal minimap_bounds_changed(min_zoom: float, max_zoom: float)

const VALUES := [
	["recoil_v", "垂直后坐力"],
	["recoil_h", "水平后坐力"],
	["recoil_cap", "后坐力上限"],
	["spread", "散布"],
	["damage", "伤害"],
	["ads", "瞄准速度"],
	["move", "移动速度"],
	["vision", "视野倍率"],
]
const MAX_MUL := 100.0
const MIN_MUL := 0.0
const MM_MIN_LO := 0.40
const MM_MIN_HI := 2.00
const MM_MAX_LO := 1.00
const MM_MAX_HI := 3.00

var _p: Node
var _sliders: Dictionary = {}
var _edits: Dictionary = {}
var _enable_buttons: Dictionary = {}
var _minimap_zoom_min_slider: HSlider
var _minimap_zoom_min_edit: LineEdit
var _minimap_zoom_max_slider: HSlider
var _minimap_zoom_max_edit: LineEdit
var _status: Label
var _message: Label
var _syncing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_p = get_node_or_null("/root/Progress")
	_build()
	_load_values()
	visible = false


func open() -> void:
	_load_values()
	_set_message("数值实时生效；修改任意数值会自动启用调试", false)
	visible = true


func close_menu() -> void:
	visible = false
	if _p != null:
		_p.save_data()
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -395
	panel.offset_right = 395
	panel.offset_top = -345
	panel.offset_bottom = 345
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "调试模式 // DEBUG", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "倍率 0–100", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var enable_row := HBoxContainer.new()
	enable_row.add_theme_constant_override("separation", 8)
	rows.add_child(enable_row)
	PixelUI.label(enable_row, "启用调试", PixelUI.FS_BODY, PixelUI.DIM)
	for pair in [[true, "开"], [false, "关"]]:
		var enabled := bool(pair[0])
		var button := PixelUI.button(String(pair[1]), 36)
		button.custom_minimum_size.x = 92
		button.pressed.connect(_set_enabled.bind(enabled))
		enable_row.add_child(button)
		_enable_buttons[enabled] = button
	_status = PixelUI.label(enable_row, "", PixelUI.FS_BODY, PixelUI.DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(grid)
	for pair in VALUES:
		var key := String(pair[0])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.custom_minimum_size.x = 330
		grid.add_child(box)
		var label_row := HBoxContainer.new()
		label_row.add_theme_constant_override("separation", 6)
		box.add_child(label_row)
		var label := PixelUI.label(label_row, String(pair[1]), PixelUI.FS_BODY, PixelUI.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var edit := LineEdit.new()
		edit.custom_minimum_size = Vector2(78, 26)
		edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		edit.max_length = 7
		edit.text = "1.00"
		edit.add_theme_font_size_override("font_size", 15)
		edit.tooltip_text = "直接输入 0–100 的倍率，回车或失焦生效"
		edit.text_submitted.connect(func(_text: String) -> void: _apply_text(key))
		edit.focus_exited.connect(func() -> void: _apply_text(key))
		label_row.add_child(edit)
		_edits[key] = edit
		var slider := HSlider.new()
		slider.min_value = MIN_MUL
		slider.max_value = MAX_MUL
		slider.step = 0.1
		slider.value = 1.0
		slider.custom_minimum_size = Vector2(300, 24)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0.10, 0.11, 0.12)
		track.content_margin_top = 6
		track.content_margin_bottom = 6
		slider.add_theme_stylebox_override("slider", track)
		slider.value_changed.connect(_on_slider_changed.bind(key))
		box.add_child(slider)
		_sliders[key] = slider

	var mm_sep := HSeparator.new()
	mm_sep.add_theme_color_override("color", Color(PixelUI.CYAN, 0.55))
	rows.add_child(mm_sep)
	PixelUI.section_bar(rows, "小地图缩放上下限", "MINIMAP ZOOM BOUNDS (0.4×–3.0×)", PixelUI.CYAN)

	var mm_row := HBoxContainer.new()
	mm_row.add_theme_constant_override("separation", 18)
	rows.add_child(mm_row)
	_build_minimap_bound_control(mm_row, "最小缩放", true, MM_MIN_LO, MM_MIN_HI)
	_build_minimap_bound_control(mm_row, "最大缩放", false, MM_MAX_LO, MM_MAX_HI)

	_message = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 22

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(footer)
	var reset_button := PixelUI.button("重置为 1.0", 44)
	reset_button.custom_minimum_size.x = 200
	reset_button.pressed.connect(_reset_values)
	footer.add_child(reset_button)
	var back_button := PixelUI.button("返回设置", 44)
	back_button.custom_minimum_size.x = 200
	back_button.pressed.connect(close_menu)
	footer.add_child(back_button)


func _build_minimap_bound_control(parent: Node, title: String, is_min: bool,
		lo: float, hi: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var lbl := PixelUI.label(top, title, 20, PixelUI.TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(78, 26)
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.max_length = 5
	edit.text = "%.1f" % (0.8 if is_min else 2.5)
	edit.add_theme_font_size_override("font_size", 15)
	edit.tooltip_text = "输入 %.1f–%.1f 的小地图缩放边界" % [lo, hi]
	edit.text_submitted.connect(func(_t: String) -> void: _apply_minimap_bound_text(is_min))
	edit.focus_exited.connect(func() -> void: _apply_minimap_bound_text(is_min))
	top.add_child(edit)
	PixelUI.label(top, "×", 18, PixelUI.CYAN)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.1
	slider.value = 0.8 if is_min else 2.5
	slider.custom_minimum_size = Vector2(280, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.11, 0.12)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	slider.value_changed.connect(func(v: float) -> void: _on_minimap_bound_slider(is_min, v))
	box.add_child(slider)
	if is_min:
		_minimap_zoom_min_slider = slider
		_minimap_zoom_min_edit = edit
	else:
		_minimap_zoom_max_slider = slider
		_minimap_zoom_max_edit = edit


func _on_minimap_bound_slider(is_min: bool, value: float) -> void:
	if _syncing:
		return
	_commit_minimap_bound(is_min, value)


func _apply_minimap_bound_text(is_min: bool) -> void:
	if _syncing:
		return
	var edit := _minimap_zoom_min_edit if is_min else _minimap_zoom_max_edit
	var slider := _minimap_zoom_min_slider if is_min else _minimap_zoom_max_slider
	if edit == null or slider == null:
		return
	var lo := MM_MIN_LO if is_min else MM_MAX_LO
	var hi := MM_MIN_HI if is_min else MM_MAX_HI
	var raw := edit.text.strip_edges()
	var val := float(slider.value)
	if raw.is_valid_float():
		val = clampf(roundf(raw.to_float() * 10.0) / 10.0, lo, hi)
	else:
		_set_message("输入无效：请输入 %.1f–%.1f 的数值" % [lo, hi], true)
	_commit_minimap_bound(is_min, val)


func _commit_minimap_bound(is_min: bool, value: float) -> void:
	var zmin := 0.8
	var zmax := 2.5
	if _p != null:
		if is_min:
			_p.set_minimap_zoom_min(value)
		else:
			_p.set_minimap_zoom_max(value)
		zmin = float(_p.minimap_zoom_min())
		zmax = float(_p.minimap_zoom_max())
	else:
		zmin = clampf(value, MM_MIN_LO, MM_MIN_HI) if is_min else float(_minimap_zoom_min_slider.value)
		zmax = float(_minimap_zoom_max_slider.value) if is_min else clampf(value, MM_MAX_LO, MM_MAX_HI)
		if zmin > zmax:
			if is_min:
				zmax = zmin
			else:
				zmin = zmax
	_sync_minimap_bound_controls(zmin, zmax)
	_set_message("小地图缩放范围已更新：%.1f× – %.1f×" % [zmin, zmax], false)
	minimap_bounds_changed.emit(zmin, zmax)


func _sync_minimap_bound_controls(zmin: float, zmax: float) -> void:
	_syncing = true
	if _minimap_zoom_min_slider != null:
		_minimap_zoom_min_slider.set_value_no_signal(zmin)
	if _minimap_zoom_min_edit != null:
		_minimap_zoom_min_edit.text = "%.1f" % zmin
	if _minimap_zoom_max_slider != null:
		_minimap_zoom_max_slider.set_value_no_signal(zmax)
	if _minimap_zoom_max_edit != null:
		_minimap_zoom_max_edit.text = "%.1f" % zmax
	_syncing = false


## 滑条 → 文本框 + 运行时数值。
func _on_slider_changed(value: float, key: String) -> void:
	if _syncing:
		return
	_syncing = true
	var edit: LineEdit = _edits.get(key)
	if edit != null:
		edit.text = _format_value(value)
	_syncing = false
	_commit(key, value)


## 文本框 → 滑条 + 运行时数值；非法输入提示并自动修正。
func _apply_text(key: String) -> void:
	if _syncing:
		return
	var edit: LineEdit = _edits.get(key)
	var slider: HSlider = _sliders.get(key)
	if edit == null or slider == null:
		return
	var raw := edit.text.strip_edges()
	var corrected := float(slider.value)
	if raw.is_valid_float():
		corrected = raw.to_float()
		if corrected < MIN_MUL:
			corrected = MIN_MUL
			_set_message("输入低于 0，已自动修正为 0", true)
		elif corrected > MAX_MUL:
			corrected = MAX_MUL
			_set_message("输入超过 100，已自动修正为 100", true)
		else:
			_set_message("已应用 %s ×" % _format_value(corrected), false)
	else:
		_set_message("输入无效：仅允许 0–100 的数字，已恢复为 %.2f" % corrected, true)
	_syncing = true
	edit.text = _format_value(corrected)
	slider.set_value_no_signal(corrected)
	_syncing = false
	_commit(key, corrected)


func _commit(key: String, value: float) -> void:
	var clamped := clampf(value, MIN_MUL, MAX_MUL)
	if _p != null:
		if not bool(_p.debug_enabled()):
			_p.set_debug_enabled(true)
		_p.set_debug_value(key, clamped)
	_refresh_enable(true)
	if _p == null:
		return
	# 数值已写入运行时参数（Main2D / Doll2D / VisionFog2D 每帧或开火时读取）。


func _set_enabled(enabled: bool) -> void:
	if _p != null:
		_p.set_debug_enabled(enabled)
	_refresh_enable(enabled)
	_set_message("调试已启用，数值实时生效" if enabled else
		"调试已关闭，所有倍率按 1.0 计算", false if enabled else true)


func _reset_values() -> void:
	if _p != null:
		_p.reset_debug()
	_load_values()
	_set_message("已重置所有倍率为 1.0（小地图缩放恢复 0.8×–2.5×）", false)
	if _p != null:
		_p.save_data()
		minimap_bounds_changed.emit(float(_p.minimap_zoom_min()), float(_p.minimap_zoom_max()))


func _load_values() -> void:
	var enabled := false
	if _p != null:
		enabled = bool(_p.debug_enabled())
	_refresh_enable(enabled)
	_syncing = true
	for pair in VALUES:
		var key := String(pair[0])
		var value := 1.0
		if _p != null:
			value = float(_p.debug_value(key))
		var slider: HSlider = _sliders.get(key)
		if slider != null:
			slider.set_value_no_signal(value)
		var edit: LineEdit = _edits.get(key)
		if edit != null:
			edit.text = _format_value(value)
	_syncing = false
	var zmin := float(_p.minimap_zoom_min()) if (_p != null and _p.has_method("minimap_zoom_min")) else 0.8
	var zmax := float(_p.minimap_zoom_max()) if (_p != null and _p.has_method("minimap_zoom_max")) else 2.5
	_sync_minimap_bound_controls(zmin, zmax)


func _refresh_enable(enabled: bool) -> void:
	for key in _enable_buttons:
		var button: Button = _enable_buttons[key]
		var active := bool(key) == enabled
		button.text = ("▶ " if active else "   ") + ("开" if bool(key) else "关")
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)
	if _status != null:
		_status.text = "已启用 · 实时生效" if enabled else "未启用"
		_status.add_theme_color_override(
			"font_color", PixelUI.OK if enabled else PixelUI.DIM)


func _set_message(text: String, is_warning: bool) -> void:
	if _message == null:
		return
	_message.text = text
	_message.add_theme_color_override(
		"font_color", PixelUI.DANGER if is_warning else PixelUI.OK)


func _format_value(value: float) -> String:
	return "%.2f" % value


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
