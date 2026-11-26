extends Control
class_name DebugMenu2D
## 调试模式（Phase 5B 三页分页重构）：
## 1) 战斗与视野：8 项核心倍率（0–100）+ 小地图缩放上下限（0.4×–3.0×）；
## 2) 生存与恢复：生命/护甲上限倍率（0.1–100×）、生命/护甲自动恢复（点/秒，绝对值）与一键满血满甲；
## 3) 资源与等级：信用点、3 基础材料、4 进阶材料、经验/等级快捷增减与设值（直接写入当前存档）。

signal closed
signal minimap_bounds_changed(min_zoom: float, max_zoom: float)

const TABS := [
	["combat", "1. 战斗与视野"],
	["survival", "2. 生存与恢复"],
	["resources", "3. 资源与等级"],
]
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
## 生存与恢复配置：[key, 标签, 最小值, 滑条最大值, 文本最大值, 步长, 单位, 是否绝对值]
const SURVIVAL_SPECS := [
	["hp_max_mul", "生命上限倍率", 0.1, 20.0, 100.0, 0.1, "×", false],
	["armor_max_mul", "护甲上限倍率", 0.1, 20.0, 100.0, 0.1, "×", false],
	["hp_regen", "生命自动恢复", 0.0, 100.0, 1000.0, 1.0, "点/秒", true],
	["armor_regen", "护甲自动恢复", 0.0, 100.0, 1000.0, 1.0, "点/秒", true],
]
const MAX_MUL := 100.0
const MIN_MUL := 0.0
const MM_MIN_LO := 0.40
const MM_MIN_HI := 2.00
const MM_MAX_LO := 1.00
const MM_MAX_HI := 3.00

var _p: Node
## 保留原 8 项战斗/视野倍率字典契约（供 settings_2d_test 校验 _sliders.size() == 8）。
var _sliders: Dictionary = {}
var _edits: Dictionary = {}
var _survival_sliders: Dictionary = {}
var _survival_edits: Dictionary = {}
var _resource_edits: Dictionary = {}
var _enable_buttons: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _tab_pages: Dictionary = {}
var _active_tab := "combat"
var _minimap_zoom_min_slider: HSlider
var _minimap_zoom_min_edit: LineEdit
var _minimap_zoom_max_slider: HSlider
var _minimap_zoom_max_edit: LineEdit
var _live_vitals_label: Label
var _full_restore_button: Button
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
	switch_tab("combat")
	visible = false


func open() -> void:
	_load_values()
	_refresh_live_vitals()
	_set_message("数值实时生效；修改战斗/生存参数会自动启用调试", false)
	visible = true


func close_menu() -> void:
	visible = false
	if _p != null:
		_p.save_data()
	closed.emit()


func current_tab() -> String:
	return _active_tab


func switch_tab(tab_id: String) -> void:
	if not _tab_pages.has(tab_id):
		return
	_active_tab = tab_id
	for id in _tab_pages:
		var page: Control = _tab_pages[id]
		page.visible = (String(id) == tab_id)
	for id in _tab_buttons:
		var btn: Button = _tab_buttons[id]
		var active := (String(id) == tab_id)
		var label_text := _tab_title(String(id))
		btn.text = ("▶ " if active else "  ") + label_text
		btn.add_theme_color_override("font_color",
			PixelUI.AMBER_BRIGHT if active else PixelUI.DIM)
	if tab_id == "survival":
		_refresh_live_vitals()
	elif tab_id == "resources":
		_load_resource_values()


func _tab_title(tab_id: String) -> String:
	for pair in TABS:
		if String(pair[0]) == tab_id:
			return String(pair[1])
	return tab_id


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.90)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -450
	panel.offset_right = 450
	panel.offset_top = -365
	panel.offset_bottom = 365
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "调试模式 // DEBUG", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "三页调试终端 · ESC 返回", 18, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	# 全局启用开关行（作用于战斗/视野与生存/恢复参数）。
	var enable_row := HBoxContainer.new()
	enable_row.add_theme_constant_override("separation", 8)
	rows.add_child(enable_row)
	PixelUI.label(enable_row, "启用调试", 20, PixelUI.DIM)
	for pair in [[true, "开"], [false, "关"]]:
		var enabled := bool(pair[0])
		var button := PixelUI.button(String(pair[1]), 34)
		button.add_theme_font_size_override("font_size", 18)
		button.custom_minimum_size.x = 88
		button.pressed.connect(_set_enabled.bind(enabled))
		enable_row.add_child(button)
		_enable_buttons[enabled] = button
	_status = PixelUI.label(enable_row, "", 19, PixelUI.DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 三页标签栏
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	rows.add_child(tab_bar)
	for pair in TABS:
		var tid := String(pair[0])
		var tbtn := PixelUI.button(String(pair[1]), 36)
		tbtn.add_theme_font_size_override("font_size", 18)
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbtn.pressed.connect(switch_tab.bind(tid))
		tab_bar.add_child(tbtn)
		_tab_buttons[tid] = tbtn

	var body_host := PanelContainer.new()
	body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var host_style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	host_style.content_margin_left = 14
	host_style.content_margin_right = 14
	host_style.content_margin_top = 10
	host_style.content_margin_bottom = 10
	body_host.add_theme_stylebox_override("panel", host_style)
	rows.add_child(body_host)

	_tab_pages["combat"] = _build_combat_tab(body_host)
	_tab_pages["survival"] = _build_survival_tab(body_host)
	_tab_pages["resources"] = _build_resources_tab(body_host)

	_message = PixelUI.label(rows, "", 18, PixelUI.DIM)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.y = 22

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(footer)
	var reset_button := PixelUI.button("重置倍率与恢复", 42)
	reset_button.add_theme_font_size_override("font_size", 18)
	reset_button.custom_minimum_size.x = 220
	reset_button.pressed.connect(_reset_values)
	footer.add_child(reset_button)
	var back_button := PixelUI.primary_button("返回设置", 42)
	back_button.add_theme_font_size_override("font_size", 18)
	back_button.custom_minimum_size.x = 220
	back_button.pressed.connect(close_menu)
	footer.add_child(back_button)


## ---- 第 1 页：战斗与视野（原有 8 倍率 + 小地图缩放边界）----

func _build_combat_tab(parent: Node) -> Control:
	var page := VBoxContainer.new()
	page.name = "CombatTab"
	page.add_theme_constant_override("separation", 8)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(page)

	PixelUI.section_bar(page, "战斗与视野倍率", "COMBAT & VISION (0–100×)", PixelUI.AMBER)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	for pair in VALUES:
		var key := String(pair[0])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(box)
		var label_row := HBoxContainer.new()
		label_row.add_theme_constant_override("separation", 6)
		box.add_child(label_row)
		var label := PixelUI.label(label_row, String(pair[1]), 19, PixelUI.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var edit := _make_num_edit("1.00", 7, "直接输入 0–100 的倍率，回车或失焦生效")
		edit.text_submitted.connect(func(_text: String) -> void: _apply_text(key))
		edit.focus_exited.connect(func() -> void: _apply_text(key))
		label_row.add_child(edit)
		_edits[key] = edit
		var slider := _make_slider(MIN_MUL, MAX_MUL, 0.1, 1.0)
		slider.value_changed.connect(_on_slider_changed.bind(key))
		box.add_child(slider)
		_sliders[key] = slider

	var mm_sep := HSeparator.new()
	mm_sep.add_theme_color_override("color", Color(PixelUI.CYAN, 0.55))
	page.add_child(mm_sep)
	PixelUI.section_bar(page, "小地图缩放上下限", "MINIMAP ZOOM BOUNDS (0.4×–3.0×)", PixelUI.CYAN)

	var mm_row := HBoxContainer.new()
	mm_row.add_theme_constant_override("separation", 20)
	page.add_child(mm_row)
	_build_minimap_bound_control(mm_row, "最小缩放", true, MM_MIN_LO, MM_MIN_HI)
	_build_minimap_bound_control(mm_row, "最大缩放", false, MM_MAX_LO, MM_MAX_HI)
	return page


## ---- 第 2 页：生存与恢复（上限倍率 / 绝对值点每秒恢复 / 一键满血满甲）----

func _build_survival_tab(parent: Node) -> Control:
	var page := VBoxContainer.new()
	page.name = "SurvivalTab"
	page.add_theme_constant_override("separation", 10)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(page)

	var status_box := PanelContainer.new()
	var st := PixelUI.panel_style(Color(0.014, 0.024, 0.032, 0.90), 1, Color(PixelUI.OK, 0.45))
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	status_box.add_theme_stylebox_override("panel", st)
	page.add_child(status_box)
	_live_vitals_label = PixelUI.label(status_box, "当前状态：待检测", 18, PixelUI.OK)

	PixelUI.section_bar(page, "生命与护甲上限倍率", "MAX VITALS MULTIPLIER (0.1–100×)", PixelUI.OK)
	var mul_grid := GridContainer.new()
	mul_grid.columns = 2
	mul_grid.add_theme_constant_override("h_separation", 20)
	mul_grid.add_theme_constant_override("v_separation", 8)
	page.add_child(mul_grid)
	for i in 2:
		_build_survival_control(mul_grid, SURVIVAL_SPECS[i])

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(PixelUI.CYAN, 0.50))
	page.add_child(sep)
	PixelUI.section_bar(page, "生命与护甲自动恢复（绝对值）", "AUTO REGEN (PTS / SEC)", PixelUI.CYAN)
	var regen_grid := GridContainer.new()
	regen_grid.columns = 2
	regen_grid.add_theme_constant_override("h_separation", 20)
	regen_grid.add_theme_constant_override("v_separation", 8)
	page.add_child(regen_grid)
	for i in range(2, 4):
		_build_survival_control(regen_grid, SURVIVAL_SPECS[i])

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 12)
	page.add_child(quick_row)
	_full_restore_button = PixelUI.primary_button("一键满血满甲 // FULL RESTORE", 44)
	_full_restore_button.add_theme_font_size_override("font_size", 18)
	_full_restore_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full_restore_button.pressed.connect(func() -> void: full_restore_player())
	quick_row.add_child(_full_restore_button)

	var reset_surv := PixelUI.button("恢复默认生存 (1.0× / 0)", 44)
	reset_surv.add_theme_font_size_override("font_size", 17)
	reset_surv.custom_minimum_size.x = 240
	reset_surv.pressed.connect(_reset_survival_only)
	quick_row.add_child(reset_surv)

	var tip := PixelUI.label(page,
		"说明：调整上限倍率时会实时按比例缩放/钳制当前生命与护甲（降低倍率不会误杀）；\n自动恢复为每秒固定点数，支持小数累加，角色阵亡后自动停止。",
		16, PixelUI.DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return page


func _build_survival_control(parent: Node, spec: Array) -> void:
	var key := String(spec[0])
	var title := String(spec[1])
	var lo := float(spec[2])
	var slider_hi := float(spec[3])
	var hard_hi := float(spec[4])
	var step := float(spec[5])
	var unit := String(spec[6])
	var is_flat := bool(spec[7])
	var def_val := 0.0 if is_flat else 1.0

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var lbl := PixelUI.label(top, title, 19, PixelUI.TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit := _make_num_edit(_format_survival(def_val, is_flat), 8,
		"输入 %.1f–%.0f %s（滑条拖动 %.1f–%.0f，文本框可输更大值）" % [lo, hard_hi, unit, lo, slider_hi])
	edit.text_submitted.connect(func(_t: String) -> void: _apply_survival_text(key))
	edit.focus_exited.connect(func() -> void: _apply_survival_text(key))
	top.add_child(edit)
	var u_lbl := PixelUI.label(top, unit, 16, PixelUI.CYAN if is_flat else PixelUI.OK)
	u_lbl.custom_minimum_size.x = 42
	_survival_edits[key] = edit

	var slider := _make_slider(lo, slider_hi, step, def_val)
	slider.allow_greater = true
	slider.value_changed.connect(_on_survival_slider_changed.bind(key))
	box.add_child(slider)
	_survival_sliders[key] = slider


## ---- 第 3 页：资源与等级（直接写入当前存档）----

func _build_resources_tab(parent: Node) -> Control:
	var page := VBoxContainer.new()
	page.name = "ResourcesTab"
	page.add_theme_constant_override("separation", 8)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(page)

	# 醒目持久化警告条
	var warn := PanelContainer.new()
	var wst := PixelUI.panel_style(Color(0.16, 0.04, 0.03, 0.92), 1, PixelUI.DANGER)
	wst.border_width_left = 4
	wst.content_margin_left = 10
	wst.content_margin_right = 10
	wst.content_margin_top = 5
	wst.content_margin_bottom = 5
	warn.add_theme_stylebox_override("panel", wst)
	page.add_child(warn)
	PixelUI.label(warn, "[!] 警告：本页修改将直接写入当前存档并立即生效！（建议先在「存档管理」备份）",
		16, PixelUI.AMBER_BRIGHT)

	# 顶部：信用点 + 经验与等级
	var top_grid := HBoxContainer.new()
	top_grid.add_theme_constant_override("separation", 12)
	page.add_child(top_grid)

	var cred_box := _mini_card(top_grid, "信用点 // CREDITS", PixelUI.GOLD)
	var cred_row := HBoxContainer.new()
	cred_row.add_theme_constant_override("separation", 6)
	cred_box.add_child(cred_row)
	PixelUI.icon(cred_row, "res_credit", 20)
	var cred_edit := _make_num_edit("0", 9, "输入信用点整数，回车或失焦写入存档")
	cred_edit.custom_minimum_size.x = 96
	cred_edit.text_submitted.connect(func(_t: String) -> void: _commit_credits_text())
	cred_edit.focus_exited.connect(_commit_credits_text)
	cred_row.add_child(cred_edit)
	_resource_edits["credits"] = cred_edit
	_add_delta_btn(cred_row, "-1K", func() -> void: _adjust_credits(-1000))
	_add_delta_btn(cred_row, "+1K", func() -> void: _adjust_credits(1000))
	_add_delta_btn(cred_row, "+10K", func() -> void: _adjust_credits(10000))

	var xp_box := _mini_card(top_grid, "经验与等级 // XP & LEVEL", PixelUI.CYAN)
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	xp_box.add_child(xp_row)
	PixelUI.label(xp_row, "XP", 16, PixelUI.DIM)
	var xp_edit := _make_num_edit("0", 8, "直接设置总经验值 XP")
	xp_edit.custom_minimum_size.x = 76
	xp_edit.text_submitted.connect(func(_t: String) -> void: _commit_xp_text())
	xp_edit.focus_exited.connect(_commit_xp_text)
	xp_row.add_child(xp_edit)
	_resource_edits["xp"] = xp_edit
	_add_delta_btn(xp_row, "+100", func() -> void: _adjust_xp(100))
	PixelUI.label(xp_row, "Lv.", 16, PixelUI.CYAN)
	var lv_edit := _make_num_edit("1", 4, "直接设置等级（同步更新 XP）")
	lv_edit.custom_minimum_size.x = 52
	lv_edit.text_submitted.connect(func(_t: String) -> void: _commit_level_text())
	lv_edit.focus_exited.connect(_commit_level_text)
	xp_row.add_child(lv_edit)
	_resource_edits["level"] = lv_edit
	_add_delta_btn(xp_row, "-1", func() -> void: _adjust_level(-1))
	_add_delta_btn(xp_row, "+1", func() -> void: _adjust_level(1))
	_add_delta_btn(xp_row, "+5", func() -> void: _adjust_level(5))

	# 中部左右两栏：3 基础材料 + 4 进阶材料
	var mat_cols := HBoxContainer.new()
	mat_cols.add_theme_constant_override("separation", 12)
	mat_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(mat_cols)

	var basic_card := _mini_card(mat_cols, "基础材料 // BASIC (3)", PixelUI.OK)
	for id in ResourceDB.BASIC:
		_add_material_row(basic_card, id, [-10, 10, 100])

	var adv_card := _mini_card(mat_cols, "进阶材料 // ADVANCED (4)", PixelUI.PURPLE)
	for id in ResourceDB.ADVANCED:
		_add_material_row(adv_card, id, [-5, 10, 50])

	# 底部快捷补给行
	var bundle_row := HBoxContainer.new()
	bundle_row.add_theme_constant_override("separation", 10)
	page.add_child(bundle_row)
	var all_mat_btn := PixelUI.button("全部材料 +100", 34)
	all_mat_btn.add_theme_font_size_override("font_size", 16)
	all_mat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_mat_btn.pressed.connect(_grant_all_materials.bind(100))
	bundle_row.add_child(all_mat_btn)
	var rich_btn := PixelUI.button("信用点 +50000", 34)
	rich_btn.add_theme_font_size_override("font_size", 16)
	rich_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rich_btn.pressed.connect(func() -> void: _adjust_credits(50000))
	bundle_row.add_child(rich_btn)
	return page


func _mini_card(parent: Node, title: String, accent: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := PixelUI.panel_style(Color(0.022, 0.030, 0.042, 0.94), 1, Color(accent, 0.42))
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", st)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	PixelUI.label(box, title, 16, accent)
	return box


func _add_material_row(parent: Node, id: StringName, deltas: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	PixelUI.icon(row, "res_" + String(id), 18)
	var name_lbl := PixelUI.label(row, ResourceDB.display_name(id), 16, ResourceDB.color_of(id))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	var edit := _make_num_edit("0", 7, "输入 %s 数量，回车或失焦写入存档" % ResourceDB.display_name(id))
	edit.custom_minimum_size = Vector2(66, 26)
	edit.text_submitted.connect(func(_t: String) -> void: _commit_material_text(id))
	edit.focus_exited.connect(func() -> void: _commit_material_text(id))
	row.add_child(edit)
	_resource_edits[String(id)] = edit
	for d in deltas:
		var delta := int(d)
		var txt := "+%d" % delta if delta > 0 else str(delta)
		_add_delta_btn(row, txt, func() -> void: _adjust_material(id, delta))


func _add_delta_btn(parent: Node, text: String, cb: Callable) -> Button:
	var btn := PixelUI.button(text, 26)
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(46, 26)
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


func _make_num_edit(initial: String, max_len: int, tip: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(78, 26)
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit.max_length = max_len
	edit.text = initial
	edit.add_theme_font_size_override("font_size", 15)
	edit.tooltip_text = tip
	return edit


func _make_slider(lo: float, hi: float, step: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(260, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.11, 0.12)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	return slider


func _build_minimap_bound_control(parent: Node, title: String, is_min: bool,
		lo: float, hi: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	var lbl := PixelUI.label(top, title, 18, PixelUI.TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var edit := _make_num_edit("%.1f" % (0.8 if is_min else 2.5), 5,
		"输入 %.1f–%.1f 的小地图缩放边界" % [lo, hi])
	edit.text_submitted.connect(func(_t: String) -> void: _apply_minimap_bound_text(is_min))
	edit.focus_exited.connect(func() -> void: _apply_minimap_bound_text(is_min))
	top.add_child(edit)
	PixelUI.label(top, "×", 17, PixelUI.CYAN)
	var slider := _make_slider(lo, hi, 0.1, 0.8 if is_min else 2.5)
	slider.value_changed.connect(func(v: float) -> void: _on_minimap_bound_slider(is_min, v))
	box.add_child(slider)
	if is_min:
		_minimap_zoom_min_slider = slider
		_minimap_zoom_min_edit = edit
	else:
		_minimap_zoom_max_slider = slider
		_minimap_zoom_max_edit = edit


## ---- 小地图缩放上下限回调 ----

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


## ---- 战斗与视野倍率回调 ----

func _on_slider_changed(value: float, key: String) -> void:
	if _syncing:
		return
	_syncing = true
	var edit: LineEdit = _edits.get(key)
	if edit != null:
		edit.text = _format_value(value)
	_syncing = false
	_commit(key, value)


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


## ---- 生存与恢复回调 ----

func _survival_spec(key: String) -> Array:
	for s in SURVIVAL_SPECS:
		if String(s[0]) == key:
			return s
	return []


func _on_survival_slider_changed(value: float, key: String) -> void:
	if _syncing:
		return
	var spec := _survival_spec(key)
	if spec.is_empty():
		return
	var is_flat := bool(spec[7])
	_syncing = true
	var edit: LineEdit = _survival_edits.get(key)
	if edit != null:
		edit.text = _format_survival(value, is_flat)
	_syncing = false
	_commit_survival(key, value)


func _apply_survival_text(key: String) -> void:
	if _syncing:
		return
	var spec := _survival_spec(key)
	if spec.is_empty():
		return
	var edit: LineEdit = _survival_edits.get(key)
	var slider: HSlider = _survival_sliders.get(key)
	if edit == null or slider == null:
		return
	var lo := float(spec[2])
	var hard_hi := float(spec[4])
	var unit := String(spec[6])
	var is_flat := bool(spec[7])
	var raw := edit.text.strip_edges()
	var corrected := float(slider.value)
	if raw.is_valid_float():
		corrected = raw.to_float()
		if corrected < lo:
			corrected = lo
			_set_message("输入低于 %.1f，已自动修正" % lo, true)
		elif corrected > hard_hi:
			corrected = hard_hi
			_set_message("输入超过 %.0f，已自动修正" % hard_hi, true)
		else:
			_set_message("已应用 %s %s" % [_format_survival(corrected, is_flat), unit], false)
	else:
		_set_message("输入无效：请输入 %.1f–%.0f 的数字" % [lo, hard_hi], true)
	_syncing = true
	edit.text = _format_survival(corrected, is_flat)
	slider.set_value_no_signal(corrected)
	_syncing = false
	_commit_survival(key, corrected)


func _commit_survival(key: String, value: float) -> void:
	var spec := _survival_spec(key)
	if spec.is_empty():
		return
	var clamped := clampf(value, float(spec[2]), float(spec[4]))
	if _p != null:
		if not bool(_p.debug_enabled()):
			_p.set_debug_enabled(true)
		_p.set_debug_value(key, clamped)
	_refresh_enable(true)
	_sync_live_player_vitals()


func _active_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _sync_live_player_vitals() -> void:
	var player := _active_player()
	if player != null and _p != null and player.has_method("sync_debug_vitals"):
		player.sync_debug_vitals(
			float(_p.debug_mul("hp_max_mul")),
			float(_p.debug_mul("armor_max_mul")))
		_sync_live_hud(player)
	_refresh_live_vitals()


func _sync_live_hud(player: Node) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var hud = tree.current_scene.get("hud")
	if hud != null and is_instance_valid(hud):
		if hud.has_method("set_hp"):
			hud.set_hp(int(player.get("hp")), int(player.get("hp_max")))
		if hud.has_method("set_armor"):
			hud.set_armor(int(player.get("armor")), int(player.get("armor_max")))


func full_restore_player() -> bool:
	var player := _active_player()
	if player == null or not player.has_method("full_restore"):
		_set_message("仅在行动局内生效（当前不在战斗场景中）", true)
		_refresh_live_vitals()
		return false
	player.full_restore()
	_sync_live_hud(player)
	_refresh_live_vitals()
	_set_message("已补满生命与护甲：HP %d/%d · 护甲 %d/%d" % [
		int(player.get("hp")), int(player.get("hp_max")),
		int(player.get("armor")), int(player.get("armor_max")),
	], false)
	return true


func _refresh_live_vitals() -> void:
	if _live_vitals_label == null:
		return
	var player := _active_player()
	if player == null:
		_live_vitals_label.text = "当前位于基地菜单 · 上限倍率与自动恢复将在进入行动后实时生效"
		_live_vitals_label.add_theme_color_override("font_color", PixelUI.DIM)
		return
	_live_vitals_label.text = "当前局内状态：HP %d / %d  ·  护甲 %d / %d" % [
		int(player.get("hp")), int(player.get("hp_max")),
		int(player.get("armor")), int(player.get("armor_max")),
	]
	_live_vitals_label.add_theme_color_override("font_color", PixelUI.OK)


func _reset_survival_only() -> void:
	if _p != null:
		_p.set_debug_value("hp_max_mul", 1.0)
		_p.set_debug_value("armor_max_mul", 1.0)
		_p.set_debug_value("hp_regen", 0.0)
		_p.set_debug_value("armor_regen", 0.0)
		_p.save_data()
	_load_survival_values()
	_sync_live_player_vitals()
	_set_message("生存与恢复参数已恢复默认（上限 1.0×，恢复 0 点/秒）", false)


## ---- 资源与等级回调（直接写入当前存档）----

func _adjust_credits(delta: int) -> void:
	if _p == null:
		return
	_p.adjust_credits_raw(delta)
	_load_resource_values()
	_set_message("已写入当前存档：信用点 = %d" % int(_p.credits()), false)


func _commit_credits_text() -> void:
	if _syncing or _p == null:
		return
	var edit: LineEdit = _resource_edits.get("credits")
	if edit == null:
		return
	var raw := edit.text.strip_edges()
	if raw.is_valid_int():
		_p.set_credits(maxi(0, raw.to_int()))
		_set_message("已写入当前存档：信用点 = %d" % int(_p.credits()), false)
	else:
		_set_message("输入无效：信用点必须为非负整数", true)
	_load_resource_values()


func _adjust_xp(delta: int) -> void:
	if _p == null:
		return
	var cur := int(_p.data.get("xp", 0))
	_p.set_xp(maxi(0, cur + delta))
	_load_resource_values()
	_set_message("已写入当前存档：XP = %d (Lv.%d)" % [
		int(_p.data.get("xp", 0)), int(_p.data.get("skill_level", 1))], false)


func _commit_xp_text() -> void:
	if _syncing or _p == null:
		return
	var edit: LineEdit = _resource_edits.get("xp")
	if edit == null:
		return
	var raw := edit.text.strip_edges()
	if raw.is_valid_int():
		_p.set_xp(maxi(0, raw.to_int()))
		_set_message("已写入当前存档：XP = %d (Lv.%d)" % [
			int(_p.data.get("xp", 0)), int(_p.data.get("skill_level", 1))], false)
	else:
		_set_message("输入无效：XP 必须为非负整数", true)
	_load_resource_values()


func _adjust_level(delta: int) -> void:
	if _p == null:
		return
	var cur := int(_p.data.get("skill_level", 1))
	_p.set_skill_level(maxi(1, cur + delta))
	_load_resource_values()
	_set_message("已写入当前存档：等级 = Lv.%d (XP %d)" % [
		int(_p.data.get("skill_level", 1)), int(_p.data.get("xp", 0))], false)


func _commit_level_text() -> void:
	if _syncing or _p == null:
		return
	var edit: LineEdit = _resource_edits.get("level")
	if edit == null:
		return
	var raw := edit.text.strip_edges()
	if raw.is_valid_int():
		_p.set_skill_level(maxi(1, raw.to_int()))
		_set_message("已写入当前存档：等级 = Lv.%d (XP %d)" % [
			int(_p.data.get("skill_level", 1)), int(_p.data.get("xp", 0))], false)
	else:
		_set_message("输入无效：等级必须为 >= 1 的整数", true)
	_load_resource_values()


func _adjust_material(id: StringName, delta: int) -> void:
	if _p == null:
		return
	_p.adjust_material_count(id, delta)
	_load_resource_values()
	var count := int(_p.material_count(id)) if ResourceDB.is_basic(id) else int(_p.advanced_count(id))
	_set_message("已写入当前存档：%s = %d" % [ResourceDB.display_name(id), count], false)


func _commit_material_text(id: StringName) -> void:
	if _syncing or _p == null:
		return
	var edit: LineEdit = _resource_edits.get(String(id))
	if edit == null:
		return
	var raw := edit.text.strip_edges()
	if raw.is_valid_int():
		_p.set_material_count(id, maxi(0, raw.to_int()))
		var count := int(_p.material_count(id)) if ResourceDB.is_basic(id) else int(_p.advanced_count(id))
		_set_message("已写入当前存档：%s = %d" % [ResourceDB.display_name(id), count], false)
	else:
		_set_message("输入无效：材料数量必须为非负整数", true)
	_load_resource_values()


func _grant_all_materials(amount: int) -> void:
	if _p == null:
		return
	for id in ResourceDB.BASIC:
		_p.adjust_material_count(id, amount)
	for id in ResourceDB.ADVANCED:
		_p.adjust_material_count(id, amount)
	_load_resource_values()
	_set_message("已写入当前存档：全部 7 种基础与进阶材料 +%d" % amount, false)


## ---- 全局开关 / 重置 / 同步读取 ----

func _set_enabled(enabled: bool) -> void:
	if _p != null:
		_p.set_debug_enabled(enabled)
	_refresh_enable(enabled)
	_sync_live_player_vitals()
	_set_message("调试已启用，战斗与生存参数实时生效" if enabled else
		"调试已关闭，所有倍率按 1.0、恢复按 0 计算", false if enabled else true)


func _reset_values() -> void:
	if _p != null:
		_p.reset_debug()
	_load_values()
	_sync_live_player_vitals()
	_set_message("已重置所有战斗/生存倍率与自动恢复（小地图缩放恢复 0.8×–2.5×）", false)
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
	_load_survival_values()
	_load_resource_values()
	var zmin := float(_p.minimap_zoom_min()) if (_p != null and _p.has_method("minimap_zoom_min")) else 0.8
	var zmax := float(_p.minimap_zoom_max()) if (_p != null and _p.has_method("minimap_zoom_max")) else 2.5
	_sync_minimap_bound_controls(zmin, zmax)


func _load_survival_values() -> void:
	_syncing = true
	for spec in SURVIVAL_SPECS:
		var key := String(spec[0])
		var is_flat := bool(spec[7])
		var value := 0.0 if is_flat else 1.0
		if _p != null:
			value = float(_p.debug_value(key))
		var slider: HSlider = _survival_sliders.get(key)
		if slider != null:
			slider.set_value_no_signal(value)
		var edit: LineEdit = _survival_edits.get(key)
		if edit != null:
			edit.text = _format_survival(value, is_flat)
	_syncing = false


func _load_resource_values() -> void:
	if _p == null:
		return
	_syncing = true
	if _resource_edits.has("credits"):
		(_resource_edits["credits"] as LineEdit).text = str(int(_p.credits()))
	if _resource_edits.has("xp"):
		(_resource_edits["xp"] as LineEdit).text = str(int(_p.data.get("xp", 0)))
	if _resource_edits.has("level"):
		(_resource_edits["level"] as LineEdit).text = str(int(_p.data.get("skill_level", 1)))
	for id in ResourceDB.BASIC:
		var key := String(id)
		if _resource_edits.has(key):
			(_resource_edits[key] as LineEdit).text = str(int(_p.material_count(id)))
	for id in ResourceDB.ADVANCED:
		var key := String(id)
		if _resource_edits.has(key):
			(_resource_edits[key] as LineEdit).text = str(int(_p.advanced_count(id)))
	_syncing = false


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


func _format_survival(value: float, is_flat: bool) -> String:
	return "%.1f" % value if is_flat else "%.2f" % value


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
