extends Control
class_name SettingsMenu2D
## 主菜单与游戏内 ESC 菜单共用的设置页：
## 左栏：音频（主音量 / 音效 / 背景音乐）+ 打击感（顿帧 / 采样 / 特写 / 震动）+ 小地图（形状 / 大小 / 缩放）；
## 右栏：数据显示（射速 / 护甲 RHA / 弹药）+ 镜头与光学特效（缩放 / 震屏 / 弹道 / 镜内模糊与畸变）。
## 两边读写同一份 Progress 存档，修改即时生效并自动保存。

signal closed

const LEFT_COL_WIDTH := 590.0
const RIGHT_COL_WIDTH := 590.0
const PREVIEW_BOX_SIZE := Vector2(236.0, 200.0)
const TYPEWRITER_SAMPLE := "▶ [K-17] 战术终端链路就绪 · 正在解码实验性逐字输出..."

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
var _muzzle_flash_buttons: Dictionary = {}
var _minimap_shape_buttons: Dictionary = {}
var _minimap_scale_slider: HSlider
var _minimap_scale_value: Label
var _minimap_zoom_slider: HSlider
var _minimap_zoom_value: Label
var _minimap_zoom_hint: Label
var _minimap_preview: Minimap2D
var _minimap_preview_frame: PanelContainer
var _preview_angle := 0.0
var _typewriter_buttons: Dictionary = {}
var _typewriter_speed_slider: HSlider
var _typewriter_speed_value: Label
var _typewriter_replay_button: Button
var _typewriter_preview: RichTextLabel
var _ammo_exact_buttons: Dictionary = {}
var _fps_buttons: Dictionary = {}
var _pickup_merge_slider: HSlider
var _pickup_merge_value: Label
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
	_debug_menu.minimap_bounds_changed.connect(_on_debug_minimap_bounds_changed)
	_debug_menu.closed.connect(_refresh_minimap_zoom_bounds)
	add_child(_debug_menu)
	visible = false
	set_process(true)


func _process(delta: float) -> void:
	if not visible:
		return
	_preview_angle = fposmod(_preview_angle + delta * 0.55, TAU)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -630
	panel.offset_right = 630
	panel.offset_top = -430
	panel.offset_bottom = 430
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.emphasize(
		PixelUI.label(header, "系统设置 // SETTINGS", 32, PixelUI.AMBER), 3, 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var esc_hint := PixelUI.rich_label(header,
		"[right]%s 关闭 · 修改自动保存[/right]" % PixelUI.bb("[ESC]", PixelUI.GOLD), 18, PixelUI.DIM, 1)
	esc_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	esc_hint.custom_minimum_size = Vector2(270, 24)
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
	var debug_button := PixelUI.button("调试模式 // DEBUG", 38)
	debug_button.custom_minimum_size.x = 220
	debug_button.pressed.connect(_open_debug)
	footer.add_child(debug_button)
	_back_button = PixelUI.primary_button("返回", 38)
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
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
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
	_add_muzzle_flash_row(rows)
	_add_shake_scale_row(rows)

	_sep(rows, PixelUI.OK)
	PixelUI.section_bar(rows, "小地图与雷达", "MINIMAP", PixelUI.OK)
	var mm_split := HBoxContainer.new()
	mm_split.add_theme_constant_override("separation", 12)
	rows.add_child(mm_split)

	var mm_ctrl := VBoxContainer.new()
	mm_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mm_ctrl.add_theme_constant_override("separation", 8)
	mm_split.add_child(mm_ctrl)
	_add_minimap_shape_row(mm_ctrl)
	_add_minimap_scale_row(mm_ctrl)
	_add_minimap_zoom_row(mm_ctrl)
	_minimap_zoom_hint = PixelUI.label(mm_ctrl, "范围 0.8×–2.5× · 调试可扩至 3.0×", 16, PixelUI.DIM)
	_minimap_zoom_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_build_minimap_preview_box(mm_split)

	_sep(rows, PixelUI.CYAN)
	PixelUI.section_bar(rows, "性能监测", "PERFORMANCE", PixelUI.CYAN)
	_add_toggle_row(rows, "显示 FPS 帧率", _fps_buttons, _set_show_fps)
	var fps_hint := PixelUI.label(rows, "开启后在右上角实时显示帧率与帧耗时（自动避让小地图）", 15, PixelUI.DIM)
	fps_hint.clip_text = true

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	return panel


func _build_minimap_preview_box(parent: Node) -> void:
	_minimap_preview_frame = PanelContainer.new()
	_minimap_preview_frame.custom_minimum_size = PREVIEW_BOX_SIZE + Vector2(8, 28)
	_minimap_preview_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := PixelUI.panel_style(Color(0.012, 0.018, 0.026, 0.96), 1, Color(PixelUI.OK, 0.48))
	st.content_margin_left = 4
	st.content_margin_right = 4
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	_minimap_preview_frame.add_theme_stylebox_override("panel", st)
	parent.add_child(_minimap_preview_frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_minimap_preview_frame.add_child(box)

	var cap := PixelUI.label(box, "LIVE PREVIEW // 实时预览", 14, PixelUI.OK)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var stage := Control.new()
	stage.custom_minimum_size = PREVIEW_BOX_SIZE
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stage)

	_minimap_preview = Minimap2D.new()
	_minimap_preview.name = "MinimapLivePreview"
	_minimap_preview.process_mode = Node.PROCESS_MODE_ALWAYS
	_minimap_preview.preview_mode = true
	_minimap_preview.preview_box_size = PREVIEW_BOX_SIZE
	_minimap_preview.set_snapshot_provider(_build_preview_snapshot)
	stage.add_child(_minimap_preview)


func _build_preview_snapshot() -> Dictionary:
	var tile := float(GameUnits.TILE)
	var map_w := 30.0 * tile
	var map_h := 22.0 * tile
	var player_pos := Vector2(14.5, 11.2) * tile
	var aim_dir := Vector2.from_angle(_preview_angle)
	return {
		"map_size": Vector2(map_w, map_h),
		"tile_size": tile,
		"floor_rects": [
			Rect2i(2, 2, 26, 18),
		],
		"rooms": [
			{"rect": Rect2(Vector2(3, 3) * tile, Vector2(7, 6) * tile)},
			{"rect": Rect2(Vector2(12, 3) * tile, Vector2(6, 5) * tile)},
			{"rect": Rect2(Vector2(20, 4) * tile, Vector2(7, 6) * tile)},
			{"rect": Rect2(Vector2(4, 12) * tile, Vector2(8, 6) * tile)},
			{"rect": Rect2(Vector2(16, 13) * tile, Vector2(9, 5) * tile)},
		],
		"player_pos": player_pos,
		"aim_dir": aim_dir,
		"containers": [
			{"position": Vector2(6.5, 6.0) * tile, "searched": false},
			{"position": Vector2(15.0, 5.2) * tile, "searched": false},
			{"position": Vector2(22.5, 7.0) * tile, "searched": false},
			{"position": Vector2(8.0, 15.0) * tile, "searched": false},
		],
		"power_on": false,
		"power_position": Vector2(15.0, 5.5) * tile,
		"switch_exit_position": Vector2(23.5, 15.5) * tile,
		"exit_position": Vector2(25.5, 7.0) * tile,
		"tracking": false,
		"enemy_positions": [
			Vector2(18.0, 9.8) * tile,
			Vector2(11.5, 13.8) * tile,
			Vector2(17.2, 14.5) * tile,
		],
	}


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

	PixelUI.label(rows, "弹药显示（局内 J 键切换）", 19, PixelUI.DIM)
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

	_add_pickup_merge_row(rows)

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

	_sep(rows, PixelUI.PURPLE)
	PixelUI.section_bar(rows, "实验性功能", "EXPERIMENTAL", PixelUI.PURPLE)
	_add_toggle_row(rows, "打字机文本", _typewriter_buttons, _set_typewriter_enabled)
	_add_typewriter_speed_row(rows)

	var tw_box := PanelContainer.new()
	var tw_st := PixelUI.panel_style(Color(0.012, 0.018, 0.026, 0.92), 1, Color(PixelUI.PURPLE, 0.45))
	tw_st.content_margin_left = 10
	tw_st.content_margin_right = 10
	tw_st.content_margin_top = 6
	tw_st.content_margin_bottom = 6
	tw_box.add_theme_stylebox_override("panel", tw_st)
	rows.add_child(tw_box)
	_typewriter_preview = PixelUI.rich_label(tw_box,
		PixelUI.bb(TYPEWRITER_SAMPLE, PixelUI.CYAN), 16, PixelUI.TEXT, 1)
	_typewriter_preview.custom_minimum_size.y = 24

	_add_toggle_row(rows, "真实逐发弹匣", _ammo_exact_buttons, _set_ammo_exact_rounds)
	var exact_hint := PixelUI.label(
		rows, "默认关闭 · 开启后按双排交错 / 螺旋弹鼓逐颗显示全部实弹", 14, PixelUI.DIM)
	exact_hint.clip_text = true

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	PixelUI.rich_label(rows,
		"%s 局内随时按 ESC 调整，小地图/音效/视野立即生效" % PixelUI.bb("●", PixelUI.OK),
		16, PixelUI.DIM, 1)
	return panel


func _add_pickup_merge_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var label := PixelUI.label(line, "拾取合并窗口", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 128
	_pickup_merge_slider = _make_slider()
	_pickup_merge_slider.min_value = 0.0
	_pickup_merge_slider.max_value = 10.0
	_pickup_merge_slider.step = 0.5
	_pickup_merge_slider.value_changed.connect(_on_pickup_merge_changed)
	line.add_child(_pickup_merge_slider)
	_pickup_merge_value = PixelUI.emphasize(PixelUI.label(line, "3.0s", 19, PixelUI.OK), 2, 1)
	_pickup_merge_value.custom_minimum_size.x = 64
	_pickup_merge_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _on_pickup_merge_changed(value: float) -> void:
	var sec := clampf(roundf(value * 2.0) / 2.0, 0.0, 10.0)
	if _pickup_merge_value != null:
		_pickup_merge_value.text = "关闭" if sec <= 0.01 else "%.1fs" % sec
		_pickup_merge_value.add_theme_color_override(
			"font_color", PixelUI.DIM if sec <= 0.01 else PixelUI.OK)
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.data["pickup_merge_window"] = sec
	_save_timer.start()


func _add_typewriter_speed_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "打字速度", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 136
	_typewriter_speed_slider = _make_slider()
	_typewriter_speed_slider.min_value = 15.0
	_typewriter_speed_slider.max_value = 140.0
	_typewriter_speed_slider.step = 5.0
	_typewriter_speed_slider.custom_minimum_size.x = 140
	_typewriter_speed_slider.value_changed.connect(_on_typewriter_speed_changed)
	line.add_child(_typewriter_speed_slider)
	_typewriter_speed_value = PixelUI.emphasize(PixelUI.label(line, "48字/s", 17, PixelUI.PURPLE), 2, 1)
	_typewriter_speed_value.custom_minimum_size.x = 68
	_typewriter_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_typewriter_replay_button = _option_button("试播")
	_typewriter_replay_button.custom_minimum_size = Vector2(64, 32)
	_typewriter_replay_button.pressed.connect(_replay_typewriter_preview)
	line.add_child(_typewriter_replay_button)


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


func _add_muzzle_flash_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	var label := PixelUI.label(line, "开枪火光", 19, PixelUI.DIM)
	label.custom_minimum_size.x = 116
	for entry in [["full", "完全"], ["partial", "部分"], ["off", "关闭"]]:
		var mode := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.custom_minimum_size.x = 76
		button.pressed.connect(func() -> void: _set_muzzle_flash_mode(mode))
		line.add_child(button)
		_muzzle_flash_buttons[mode] = button


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
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	var label := PixelUI.label(line, "形状", 18, PixelUI.DIM)
	label.custom_minimum_size.x = 58
	for entry in [["square", "方形"], ["circle", "圆形"]]:
		var shape := String(entry[0])
		var button := _option_button(String(entry[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _set_minimap_shape(shape))
		line.add_child(button)
		_minimap_shape_buttons[shape] = button


func _add_minimap_scale_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	var label := PixelUI.label(line, "比例", 18, PixelUI.DIM)
	label.custom_minimum_size.x = 58
	_minimap_scale_slider = _make_slider()
	_minimap_scale_slider.custom_minimum_size.x = 120
	_minimap_scale_slider.min_value = 70.0
	_minimap_scale_slider.max_value = 150.0
	_minimap_scale_slider.step = 5.0
	_minimap_scale_slider.value_changed.connect(_on_minimap_scale_changed)
	line.add_child(_minimap_scale_slider)
	_minimap_scale_value = PixelUI.emphasize(PixelUI.label(line, "100%", 18, PixelUI.OK), 2, 1)
	_minimap_scale_value.custom_minimum_size.x = 54
	_minimap_scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _add_minimap_zoom_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	var label := PixelUI.label(line, "缩放", 18, PixelUI.DIM)
	label.custom_minimum_size.x = 58
	_minimap_zoom_slider = _make_slider()
	_minimap_zoom_slider.custom_minimum_size.x = 120
	_minimap_zoom_slider.min_value = 80.0
	_minimap_zoom_slider.max_value = 250.0
	_minimap_zoom_slider.step = 10.0
	_minimap_zoom_slider.value_changed.connect(_on_minimap_zoom_changed)
	line.add_child(_minimap_zoom_slider)
	_minimap_zoom_value = PixelUI.emphasize(PixelUI.label(line, "1.0×", 18, PixelUI.CYAN), 2, 1)
	_minimap_zoom_value.custom_minimum_size.x = 54
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
	var button := PixelUI.button(text, 30)
	button.add_theme_font_size_override("font_size", 17)
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := button.get_theme_stylebox(st_name)
		if sb is StyleBoxFlat:
			var dup := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			dup.content_margin_top = 4
			dup.content_margin_bottom = 4
			button.add_theme_stylebox_override(st_name, dup)
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
	var sc := clampf(roundf(value / 5.0) * 0.05, 0.70, 1.50)
	_minimap_scale_value.text = "%d%%" % int(round(sc * 100.0))
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.data["minimap_scale"] = sc
	_sync_minimap_preview()
	_save_timer.start()


func _on_minimap_zoom_changed(value: float) -> void:
	var bounds := _minimap_zoom_bounds()
	var z := clampf(roundf(value / 10.0) * 0.1, bounds.x, bounds.y)
	_minimap_zoom_value.text = "%.1f×" % z
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.data["minimap_zoom"] = z
	_sync_minimap_preview()
	_save_timer.start()


func _minimap_zoom_bounds() -> Vector2:
	var p := get_node_or_null("/root/Progress")
	var lo := float(p.minimap_zoom_min()) if (p != null and p.has_method("minimap_zoom_min")) else 0.80
	var hi := float(p.minimap_zoom_max()) if (p != null and p.has_method("minimap_zoom_max")) else 2.50
	return Vector2(lo, maxf(hi, lo))


func _on_debug_minimap_bounds_changed(_zmin: float, _zmax: float) -> void:
	_refresh_minimap_zoom_bounds()


func _refresh_minimap_zoom_bounds() -> void:
	var bounds := _minimap_zoom_bounds()
	var p := get_node_or_null("/root/Progress")
	var z := float(p.minimap_zoom()) if (p != null and p.has_method("minimap_zoom")) else 1.0
	z = clampf(z, bounds.x, bounds.y)
	if _minimap_zoom_slider != null:
		_minimap_zoom_slider.min_value = roundf(bounds.x * 100.0)
		_minimap_zoom_slider.max_value = roundf(bounds.y * 100.0)
		_minimap_zoom_slider.set_value_no_signal(roundf(z * 100.0))
	if _minimap_zoom_value != null:
		_minimap_zoom_value.text = "%.1f×" % z
	if _minimap_zoom_hint != null:
		_minimap_zoom_hint.text = "范围 %.1f×–%.1f× · 调试可调 0.4×–3.0×" % [bounds.x, bounds.y]
	_sync_minimap_preview()


func _sync_minimap_preview() -> void:
	if _minimap_preview == null:
		return
	var p := get_node_or_null("/root/Progress")
	var shape := String(p.minimap_shape()) if (p != null and p.has_method("minimap_shape")) else "square"
	var sc := clampf(roundf(_minimap_scale_slider.value / 5.0) * 0.05, 0.70, 1.50) if _minimap_scale_slider != null else 1.0
	var bounds := _minimap_zoom_bounds()
	var zm := clampf(roundf(_minimap_zoom_slider.value / 10.0) * 0.1, bounds.x, bounds.y) if _minimap_zoom_slider != null else 1.0
	_minimap_preview.configure(shape, sc, zm)


func _set_typewriter_enabled(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_typewriter_enabled"):
		p.set_typewriter_enabled(enabled)
	else:
		PixelUI.set_typewriter_config(enabled, PixelUI.typewriter_speed())
	_refresh_typewriter_buttons(enabled)
	_replay_typewriter_preview()


func _on_typewriter_speed_changed(value: float) -> void:
	var cps := clampf(roundf(value), 15.0, 140.0)
	if _typewriter_speed_value != null:
		_typewriter_speed_value.text = "%d字/s" % int(cps)
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.data["typewriter_speed"] = cps
		PixelUI.set_typewriter_config(bool(p.typewriter_enabled()), cps)
	else:
		PixelUI.set_typewriter_config(PixelUI.typewriter_enabled(), cps)
	_replay_typewriter_preview()
	_save_timer.start()


func _replay_typewriter_preview() -> void:
	if _typewriter_preview == null:
		return
	var p := get_node_or_null("/root/Progress")
	var enabled := bool(p.typewriter_enabled()) if (p != null and p.has_method("typewriter_enabled")) else PixelUI.typewriter_enabled()
	var cps := float(p.typewriter_speed()) if (p != null and p.has_method("typewriter_speed")) else PixelUI.typewriter_speed()
	_typewriter_preview.text = PixelUI.bb(TYPEWRITER_SAMPLE, PixelUI.CYAN if enabled else PixelUI.DIM)
	if enabled:
		PixelUI.play_typewriter(_typewriter_preview, true, cps)
	else:
		PixelUI.finish_typewriter(_typewriter_preview)


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
	_sync_minimap_preview()


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


func _set_muzzle_flash_mode(mode: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_muzzle_flash_mode"):
		p.set_muzzle_flash_mode(mode)
	_refresh_muzzle_flash_buttons(mode)


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
	var muzzle_flash_mode := "partial"
	var mm_shape := "square"
	var mm_scale := 1.0
	var mm_zoom := 1.0
	var tw_enabled := false
	var tw_speed := 48.0
	var ammo_exact := false
	var show_fps := false
	var pickup_merge := 3.0
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
		muzzle_flash_mode = String(p.muzzle_flash_mode()) if p.has_method("muzzle_flash_mode") else "partial"
		mm_shape = String(p.minimap_shape()) if p.has_method("minimap_shape") else "square"
		mm_scale = float(p.minimap_scale()) if p.has_method("minimap_scale") else 1.0
		mm_zoom = float(p.minimap_zoom()) if p.has_method("minimap_zoom") else 1.0
		tw_enabled = bool(p.typewriter_enabled()) if p.has_method("typewriter_enabled") else false
		tw_speed = float(p.typewriter_speed()) if p.has_method("typewriter_speed") else 48.0
		ammo_exact = bool(p.ammo_exact_rounds()) if p.has_method("ammo_exact_rounds") else false
		show_fps = bool(p.show_fps()) if p.has_method("show_fps") else false
		pickup_merge = float(p.pickup_merge_window()) if p.has_method("pickup_merge_window") else 3.0
	_set_slider("master", master * 100.0)
	_set_slider("sfx", sfx * 100.0)
	_set_slider("music", music * 100.0)
	_zoom_slider.set_value_no_signal(zoom)
	_zoom_value.text = "%d%%" % int(round(zoom))
	_shake_scale_slider.set_value_no_signal(shake_scale)
	_shake_scale_edit.text = str(int(round(shake_scale)))
	_minimap_scale_slider.set_value_no_signal(mm_scale * 100.0)
	_minimap_scale_value.text = "%d%%" % int(round(mm_scale * 100.0))
	_refresh_minimap_zoom_bounds()
	_minimap_zoom_slider.set_value_no_signal(mm_zoom * 100.0)
	_minimap_zoom_value.text = "%.1f×" % mm_zoom
	_typewriter_speed_slider.set_value_no_signal(tw_speed)
	_typewriter_speed_value.text = "%d字/s" % int(round(tw_speed))
	if _pickup_merge_slider != null:
		_pickup_merge_slider.set_value_no_signal(pickup_merge)
	if _pickup_merge_value != null:
		_pickup_merge_value.text = "关闭" if pickup_merge <= 0.01 else "%.1fs" % pickup_merge
		_pickup_merge_value.add_theme_color_override(
			"font_color", PixelUI.DIM if pickup_merge <= 0.01 else PixelUI.OK)
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
	_refresh_muzzle_flash_buttons(muzzle_flash_mode)
	_refresh_minimap_shape_buttons(mm_shape)
	_refresh_typewriter_buttons(tw_enabled)
	_refresh_ammo_exact_buttons(ammo_exact)
	_refresh_fps_buttons(show_fps)
	_sync_minimap_preview()
	_replay_typewriter_preview()


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
	var bounds := _minimap_zoom_bounds()
	p.data["minimap_scale"] = clampf(roundf(_minimap_scale_slider.value / 5.0) * 0.05, 0.70, 1.50)
	p.data["minimap_zoom"] = clampf(roundf(_minimap_zoom_slider.value / 10.0) * 0.1, bounds.x, bounds.y)
	if _typewriter_speed_slider != null:
		p.data["typewriter_speed"] = clampf(roundf(_typewriter_speed_slider.value), 15.0, 140.0)
	if _pickup_merge_slider != null:
		p.data["pickup_merge_window"] = clampf(roundf(_pickup_merge_slider.value * 2.0) / 2.0, 0.0, 10.0)
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


func _set_ammo_exact_rounds(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_ammo_exact_rounds"):
		p.set_ammo_exact_rounds(enabled)
	_refresh_ammo_exact_buttons(enabled)


func _set_show_fps(enabled: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_show_fps"):
		p.set_show_fps(enabled)
	_refresh_fps_buttons(enabled)


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
	var names := {"square": "方形", "circle": "圆形"}
	for key in _minimap_shape_buttons:
		var button: Button = _minimap_shape_buttons[key]
		button.text = ("▶ " if key == shape else "   ") + String(names.get(key, key))
		button.add_theme_color_override(
			"font_color", PixelUI.OK if key == shape else PixelUI.TEXT)


func _refresh_typewriter_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_typewriter_buttons, enabled)


func _refresh_ammo_exact_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_ammo_exact_buttons, enabled)


func _refresh_fps_buttons(enabled: bool) -> void:
	_refresh_toggle_buttons(_fps_buttons, enabled)


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


func _refresh_muzzle_flash_buttons(mode: String) -> void:
	var names := {"full": "完全", "partial": "部分", "off": "关闭"}
	for key in _muzzle_flash_buttons:
		var button: Button = _muzzle_flash_buttons[key]
		var active := String(key) == mode
		button.text = ("▶ " if active else "   ") + String(names.get(String(key), "部分"))
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
