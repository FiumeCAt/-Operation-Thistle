extends Control
class_name CharacterMenu2D
## 主菜单角色整备与外观展示界面（角色 // OPERATOR）：
## 1) 左侧展示已实装的正式战术人形卡片（头像、代号、装扮特性与出击状态），点击即切换并持久化至 Progress；
## 2) 右侧嵌入独立 SubViewport 实时驱动真实 Doll2D（Modular Doll Rig v2 + WeaponRig2D），
##    支持四向朝向切换（正面/左侧/右侧/背面）与五大动作实机演示（待机/行走/冲刺/持枪/翻滚），
##    同步装配玩家当前主武器，直观预览发丝、高马尾、衣摆/裙摆次级物理与持枪姿态。

signal closed
signal character_changed(skin_id: String)

const PANEL_SIZE := Vector2(1140, 648)
const PREVIEW_SIZE := Vector2i(460, 344)
const FLOOR_TEX_PATH := "res://assets/art/env/pixel_floor_256.png"

const OPERATORS: Array[Dictionary] = [
	{
		"skin_id": "doll_v2",
		"code": "DOLL-01",
		"name": "灰蓝猫耳少女",
		"short_label": "灰蓝猫耳",
		"tagline": "K-17 标准潜入执行体 · 默认涂装",
		"outfit": "藏蓝长风衣 · 灰格百褶裙 · 灰蓝战术球鞋 · 背挂硬壳枪盒",
		"desc": "采用 128px×1 锁定色板与双节弹簧波波短发/风衣衣摆，低饱和战术配色在暗区走廊中隐蔽性极佳。",
		"portrait": "res://assets/art/characters/doll_v2/parts/head_front.png",
	},
	{
		"skin_id": "doll_thistle",
		"code": "THISTLE-02",
		"name": "蓟花战术白裙",
		"short_label": "蓟花白裙",
		"tagline": "蓟花行动特勤人形 · 第二套正式皮肤",
		"outfit": "银白高马尾 · 红白水手战术裙 · 战术腿带 · 哑光黑战靴",
		"desc": "严格遵循 1:1 换皮契约零代码继承全套骨骼与 18 支枪械姿态，高对比度银白高马尾与红白裙摆随冲刺与翻滚自然飘动。",
		"portrait": "res://assets/art/characters/doll_thistle/parts/head_front.png",
	},
]

const DIR_MODES: Array[Dictionary] = [
	{"id": 0, "label": "正面"},
	{"id": 2, "label": "左侧"},
	{"id": 3, "label": "右侧"},
	{"id": 1, "label": "背面"},
]

const POSE_MODES: Array[Dictionary] = [
	{"id": &"idle", "label": "待机"},
	{"id": &"walk", "label": "行走"},
	{"id": &"run", "label": "冲刺"},
	{"id": &"aim", "label": "持枪瞄准"},
	{"id": &"dodge", "label": "战术翻滚"},
]

var selected_skin_id := "doll_v2"
var preview_dir := 0
var preview_pose: StringName = &"aim"
var preview_doll: Doll2D
var operator_cards: Dictionary = {}
var dir_buttons: Dictionary = {}
var pose_buttons: Dictionary = {}

var _panel: PixelUI.PixelPanel
var _title_label: Label
var _divider: HSeparator
var _active_badge: Label
var _detail_name: Label
var _detail_outfit: Label
var _detail_desc: Label
var _weapon_note: Label
var _status_label: Label
var _back_button: Button
var _back_gear_btn: Button
var _preview_vp: SubViewport
var _preview_time := 0.0
var _dodge_cycle := 0.0


static func operator_short_label(skin_id: String) -> String:
	for op in OPERATORS:
		if String(op["skin_id"]) == skin_id:
			return String(op["short_label"])
	if skin_id == "mannequin":
		return "分色体模"
	return "灰蓝猫耳"


static func operator_code(skin_id: String) -> String:
	for op in OPERATORS:
		if String(op["skin_id"]) == skin_id:
			return String(op["code"])
	if skin_id == "mannequin":
		return "TEST-RIG"
	return "DOLL-01"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	PixelUI.apply_theme(self)
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -PANEL_SIZE.x * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5
	_panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_bottom = PANEL_SIZE.y * 0.5
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)

	# 顶部标题栏
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	rows.add_child(header)
	_title_label = PixelUI.emphasize(
		PixelUI.label(header, "角色整备 // OPERATOR", PixelUI.FS_TITLE, PixelUI.theme_accent()), 2, 1)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_badge = PixelUI.label(header, "", 18, PixelUI.theme_accent_bright())
	_active_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var esc_hint := PixelUI.label(header, "ESC 关闭", PixelUI.FS_BODY, PixelUI.theme_dim())
	esc_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_divider = HSeparator.new()
	_divider.add_theme_color_override("color", PixelUI.theme_accent())
	rows.add_child(_divider)

	# 主体双栏：左侧角色列表 + 右侧实机动态展示台
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)

	body.add_child(_build_roster_column())
	body.add_child(_build_showcase_column())

	# 底部状态与返回按钮
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	rows.add_child(footer)
	_status_label = PixelUI.label(footer, "选择出击人形后自动保存至当前存档，进入战场即刻生效", 16, PixelUI.theme_dim())
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_back_button = PixelUI.button("确认并返回", 44)
	_back_button.custom_minimum_size.x = 220
	_back_button.pressed.connect(close_menu)
	footer.add_child(_back_button)


func _build_roster_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 452
	col.add_theme_constant_override("separation", 10)

	var hdr := PixelUI.label(col, "可选出击人形 // ROSTER", 17, PixelUI.theme_accent())
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	for op in OPERATORS:
		var sid := String(op["skin_id"])
		var card := _build_operator_card(op)
		col.add_child(card)
		operator_cards[sid] = card

	# 选中角色详细档案卡
	var detail_box := PanelContainer.new()
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var st := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.theme_accent(), 0.35))
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	detail_box.add_theme_stylebox_override("panel", st)
	col.add_child(detail_box)

	var d_rows := VBoxContainer.new()
	d_rows.add_theme_constant_override("separation", 6)
	detail_box.add_child(d_rows)

	_detail_name = PixelUI.emphasize(PixelUI.label(d_rows, "-", 20, PixelUI.theme_text()), 2, 1)
	_detail_outfit = PixelUI.label(d_rows, "-", 15, PixelUI.theme_accent_bright())
	_detail_outfit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc = PixelUI.label(d_rows, "-", 15, PixelUI.theme_dim())
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_weapon_note = PixelUI.label(d_rows, "", 14, PixelUI.CYAN)
	_weapon_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return col


func _build_operator_card(op: Dictionary) -> Button:
	var sid := String(op["skin_id"])
	var btn := PixelUI.button("", 108)
	btn.name = "OperatorCard_" + sid
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(select_character.bind(sid))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	btn.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(82, 82)
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p_st := StyleBoxFlat.new()
	p_st.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	p_st.border_color = Color(PixelUI.theme_accent(), 0.55)
	p_st.set_border_width_all(1)
	p_st.content_margin_left = 4
	p_st.content_margin_right = 4
	p_st.content_margin_top = 4
	p_st.content_margin_bottom = 4
	portrait_frame.add_theme_stylebox_override("panel", p_st)
	row.add_child(portrait_frame)

	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ppath := String(op["portrait"])
	if ResourceLoader.exists(ppath):
		portrait.texture = load(ppath) as Texture2D
	portrait_frame.add_child(portrait)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var top_line := HBoxContainer.new()
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(top_line)
	var code_lbl := PixelUI.label(top_line, String(op["code"]), 15, PixelUI.theme_accent())
	code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var badge := PixelUI.label(top_line, "", 15, PixelUI.OK)
	badge.name = "Badge"

	var name_lbl := PixelUI.emphasize(PixelUI.label(info, String(op["name"]), 22, PixelUI.theme_text()), 2, 1)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_lbl := PixelUI.label(info, String(op["tagline"]), 14, PixelUI.theme_dim())
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.set_meta(&"badge_label", badge)
	return btn


func _build_showcase_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)

	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 10)
	col.add_child(hdr_row)
	var hdr := PixelUI.label(hdr_row, "实机骨骼动态预览 // LIVE PREVIEW", 17, PixelUI.theme_accent())
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_gear_btn = PixelUI.button("背挂：显示", 28)
	_back_gear_btn.add_theme_font_size_override("font_size", 14)
	_back_gear_btn.custom_minimum_size.x = 176
	_back_gear_btn.pressed.connect(_toggle_preview_back_gear)
	hdr_row.add_child(_back_gear_btn)

	# 实时像素光栅化展示框
	var stage_frame := PanelContainer.new()
	stage_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.11, 1.0)
	st.border_color = Color(PixelUI.theme_accent(), 0.7)
	st.set_border_width_all(2)
	st.content_margin_left = 4
	st.content_margin_right = 4
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	stage_frame.add_theme_stylebox_override("panel", st)
	col.add_child(stage_frame)

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage_frame.add_child(vpc)

	_preview_vp = SubViewport.new()
	_preview_vp.name = "CharacterPreviewViewport"
	_preview_vp.size = PREVIEW_SIZE
	_preview_vp.transparent_bg = false
	_preview_vp.msaa_2d = Viewport.MSAA_DISABLED
	_preview_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_vp.disable_3d = true
	vpc.add_child(_preview_vp)

	_build_preview_scene(_preview_vp)

	# 朝向切换行
	var dir_row := HBoxContainer.new()
	dir_row.add_theme_constant_override("separation", 8)
	col.add_child(dir_row)
	var dir_lbl := PixelUI.label(dir_row, "朝向", 16, PixelUI.theme_dim())
	dir_lbl.custom_minimum_size.x = 46
	dir_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for d in DIR_MODES:
		var did := int(d["id"])
		var btn := PixelUI.button(String(d["label"]), 36)
		btn.add_theme_font_size_override("font_size", 15)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(set_preview_direction.bind(did))
		dir_row.add_child(btn)
		dir_buttons[did] = btn

	# 动作切换行
	var pose_row := HBoxContainer.new()
	pose_row.add_theme_constant_override("separation", 8)
	col.add_child(pose_row)
	var pose_lbl := PixelUI.label(pose_row, "姿态", 16, PixelUI.theme_dim())
	pose_lbl.custom_minimum_size.x = 46
	pose_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for pm in POSE_MODES:
		var pid: StringName = pm["id"]
		var btn := PixelUI.button(String(pm["label"]), 36)
		btn.add_theme_font_size_override("font_size", 15)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(set_preview_pose.bind(pid))
		pose_row.add_child(btn)
		pose_buttons[pid] = btn
	return col


func _build_preview_scene(vp: SubViewport) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.13, 0.17, 1.0)
	bg.size = Vector2(PREVIEW_SIZE)
	vp.add_child(bg)

	if ResourceLoader.exists(FLOOR_TEX_PATH):
		var ftex := load(FLOOR_TEX_PATH) as Texture2D
		for y in range(0, PREVIEW_SIZE.y + 256, 256):
			for x in range(0, PREVIEW_SIZE.x + 256, 256):
				var tile := Sprite2D.new()
				tile.texture = ftex
				tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tile.centered = false
				tile.position = Vector2(x, y)
				tile.modulate = Color(0.86, 0.88, 0.92, 1.0)
				vp.add_child(tile)

	# 脚底聚焦地台线
	var floor_line := ColorRect.new()
	floor_line.color = Color(0.45, 0.65, 0.78, 0.45)
	floor_line.position = Vector2(48, 294)
	floor_line.size = Vector2(PREVIEW_SIZE.x - 96, 2)
	vp.add_child(floor_line)

	var stage := Node2D.new()
	stage.name = "Stage"
	vp.add_child(stage)


func _ensure_preview_doll() -> void:
	if preview_doll != null and is_instance_valid(preview_doll):
		return
	if _preview_vp == null:
		return
	var stage := _preview_vp.get_node_or_null("Stage") as Node2D
	if stage == null:
		return
	var doll_scene := load("res://scenes/actors/Doll2D.tscn") as PackedScene
	if doll_scene != null:
		preview_doll = doll_scene.instantiate() as Doll2D
		stage.add_child(preview_doll)
		preview_doll.position = Vector2(PREVIEW_SIZE.x * 0.5, 294.0)
		preview_doll.scale = Vector2(1.92, 1.92)
		preview_doll.set_physics_process(false)
		preview_doll.equip_weapon_id(&"akm")


func open() -> void:
	_ensure_preview_doll()
	var p := get_node_or_null("/root/Progress")
	var saved := String(p.character_skin()) if (p != null and p.has_method("character_skin")) else "doll_v2"
	selected_skin_id = saved if _is_formal_operator(saved) else "doll_v2"
	_sync_preview_weapon(p)
	_apply_preview_skin(selected_skin_id)
	_refresh_theme()
	_refresh_ui()
	_preview_time = 0.0
	_dodge_cycle = 0.0
	visible = true
	set_process(true)
	if _back_button != null:
		_back_button.grab_focus()


func close_menu() -> void:
	visible = false
	set_process(false)
	closed.emit()


func select_character(skin_id: String) -> bool:
	if not _is_formal_operator(skin_id):
		return false
	selected_skin_id = skin_id
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_character_skin"):
		p.set_character_skin(skin_id)
	_apply_preview_skin(skin_id)
	_refresh_ui()
	if _status_label != null:
		_status_label.text = "已切换出击人形：%s（%s），进入行动后自动生效" % [
			operator_short_label(skin_id), operator_code(skin_id)
		]
	character_changed.emit(skin_id)
	return true


func set_preview_direction(dir_idx: int) -> void:
	preview_dir = clampi(dir_idx, 0, 3)
	_refresh_control_buttons()


func set_preview_pose(pose_id: StringName) -> void:
	preview_pose = pose_id
	_dodge_cycle = 0.0
	_refresh_control_buttons()


func _is_formal_operator(skin_id: String) -> bool:
	for op in OPERATORS:
		if String(op["skin_id"]) == skin_id:
			return true
	return false


func _sync_preview_weapon(p: Node) -> void:
	if preview_doll == null:
		return
	var weapon_id := &"akm"
	if p != null and p.has_method("loadout_2d"):
		var lo: Array = p.loadout_2d()
		if not lo.is_empty():
			weapon_id = StringName(lo[0])
	preview_doll.equip_weapon_id(weapon_id)
	preview_doll.set_skin(selected_skin_id)
	if _weapon_note != null:
		var wd := WeaponDB.get_weapon(weapon_id)
		var wname := wd.display_name.split(" // ")[0] if wd != null else String(weapon_id).to_upper()
		_weapon_note.text = "当前携行主武器预览：%s（与武备库同步）" % wname


func _apply_preview_skin(skin_id: String) -> void:
	if preview_doll != null and preview_doll.has_method("set_skin"):
		preview_doll.set_skin(skin_id)


func _toggle_preview_back_gear() -> void:
	if preview_doll == null or not preview_doll.has_extra_component_asset(&"back_gear"):
		return
	var next_on := not preview_doll.is_extra_component_visible(&"back_gear")
	preview_doll.set_extra_component_visible(&"back_gear", next_on)
	_refresh_control_buttons()


func _refresh_theme() -> void:
	if _panel != null:
		_panel.apply_active_theme()
	var acc := PixelUI.theme_accent()
	if _title_label != null:
		_title_label.add_theme_color_override("font_color", acc)
	if _divider != null:
		_divider.add_theme_color_override("color", acc)
	if _active_badge != null:
		_active_badge.add_theme_color_override("font_color", PixelUI.theme_accent_bright())
	if _back_button != null:
		PixelUI.style_button(_back_button)


func _refresh_ui() -> void:
	var acc := PixelUI.theme_accent()
	if _active_badge != null:
		_active_badge.text = "当前出击：%s // %s" % [operator_code(selected_skin_id), operator_short_label(selected_skin_id)]

	for op in OPERATORS:
		var sid := String(op["skin_id"])
		var active := sid == selected_skin_id
		if active:
			if _detail_name != null:
				_detail_name.text = "%s · %s" % [String(op["code"]), String(op["name"])]
			if _detail_outfit != null:
				_detail_outfit.text = "装扮：" + String(op["outfit"])
			if _detail_desc != null:
				_detail_desc.text = String(op["desc"])
		var btn: Button = operator_cards.get(sid)
		if btn != null:
			var st := StyleBoxFlat.new()
			st.bg_color = Color(acc, 0.22) if active else Color(0.05, 0.065, 0.09, 0.92)
			st.border_color = acc if active else Color(acc, 0.35)
			st.set_border_width_all(2 if active else 1)
			var hov := st.duplicate() as StyleBoxFlat
			hov.bg_color = Color(acc, 0.28) if active else Color(acc, 0.14)
			hov.border_color = PixelUI.theme_accent_bright()
			btn.add_theme_stylebox_override("normal", st)
			btn.add_theme_stylebox_override("hover", hov)
			btn.add_theme_stylebox_override("pressed", hov)
			var badge := btn.get_meta(&"badge_label", null) as Label
			if badge != null:
				badge.text = "[当前出击]" if active else "点击切换"
				badge.add_theme_color_override("font_color", PixelUI.OK if active else PixelUI.theme_dim())
	_refresh_control_buttons()


func _refresh_control_buttons() -> void:
	var acc := PixelUI.theme_accent()
	for did in dir_buttons:
		var btn: Button = dir_buttons[did]
		_style_toggle_chip(btn, int(did) == preview_dir, acc)
	for pid in pose_buttons:
		var btn: Button = pose_buttons[pid]
		_style_toggle_chip(btn, pid == preview_pose, acc)
	if _back_gear_btn != null:
		var has_gear := preview_doll != null and preview_doll.has_extra_component_asset(&"back_gear")
		_back_gear_btn.disabled = not has_gear
		if has_gear:
			var gear_on := preview_doll.is_extra_component_visible(&"back_gear")
			_back_gear_btn.text = "背挂组件：显示" if gear_on else "背挂组件：隐藏"
			_style_toggle_chip(_back_gear_btn, gear_on, acc)
		else:
			_back_gear_btn.text = "背挂组件：无（轻装）"
			_style_toggle_chip(_back_gear_btn, false, acc)
			_back_gear_btn.add_theme_color_override("font_color", PixelUI.theme_dim())


func _style_toggle_chip(btn: Button, active: bool, acc: Color) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(acc, 0.28) if active else Color(0.05, 0.065, 0.09, 0.90)
	st.border_color = acc if active else Color(acc, 0.38)
	st.set_border_width_all(2 if active else 1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	var hov := st.duplicate() as StyleBoxFlat
	hov.bg_color = Color(acc, 0.35)
	hov.border_color = PixelUI.theme_accent_bright()
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_color_override("font_color", PixelUI.theme_accent_bright() if active else PixelUI.theme_text())


func _process(delta: float) -> void:
	if not visible or preview_doll == null or preview_doll.rig_v2 == null:
		return
	var dt := clampf(delta, 0.005, 0.05)
	_preview_time += dt

	var face_vec := _dir_to_vec(preview_dir)
	var vel := Vector2.ZERO
	var armed := false
	var holstered := true
	var ads_on := false
	var dodging := false
	var dodge_u := 0.0
	var dodge_dir := Vector2.RIGHT if preview_dir != 2 else Vector2.LEFT

	match preview_pose:
		&"idle":
			vel = Vector2.ZERO
			armed = false
			holstered = true
		&"walk":
			vel = face_vec * 235.0
			armed = false
			holstered = true
		&"run":
			vel = face_vec * 375.0
			armed = false
			holstered = true
		&"aim":
			vel = Vector2.ZERO
			armed = true
			holstered = false
			ads_on = true
		&"dodge":
			_dodge_cycle = fmod(_dodge_cycle + dt, 1.05)
			if _dodge_cycle < 0.62:
				dodging = true
				dodge_u = clampf(_dodge_cycle / 0.62, 0.02, 0.98)
				vel = dodge_dir * 420.0
			else:
				dodging = false
				vel = Vector2.ZERO
			armed = true
			holstered = false

	var rv2 := preview_doll.rig_v2
	var wr := preview_doll.weapon_rig
	var aim_world := preview_doll.global_position + face_vec * 240.0
	rv2.update_rig(vel, 250.0, 380.0, aim_world, true, armed, holstered, ads_on,
		dodging, dodge_u, dodge_dir, dt)
	preview_doll.direction = rv2.upper_direction
	if wr != null:
		wr.holstered = holstered
		wr.visible = armed and not holstered
		wr.aim_world = aim_world
		wr.aim_enabled = true
		wr.aiming = armed and not holstered and vel.length() < 10.0
		wr.body_direction = rv2.upper_direction
		wr.ads = ads_on
		wr.sprinting = vel.length() > 300.0
		wr.dodging = dodging
		wr.dynamic_shoulder_offset = rv2.get_weapon_shoulder_offset()
		wr.dodge_pose_rot = rv2.get_dodge_weapon_rotation()
	# 收枪状态下隐藏多余背枪避免遮挡预览舞台，仅持枪/翻滚展示武器
	if preview_doll._weapon_sprite != null:
		preview_doll._weapon_sprite.visible = false


static func _dir_to_vec(dir_idx: int) -> Vector2:
	match dir_idx:
		0: return Vector2.DOWN
		1: return Vector2.UP
		2: return Vector2.LEFT
		_: return Vector2.RIGHT
