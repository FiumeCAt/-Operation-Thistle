extends Control
class_name TalentTree2D
## 2D 战术天赋树：独立于 3D 成长线，购买后在开始行动时生效。
## 数据/资源/XP 走 Progress autoload；节点等级存于 talents_2d。
## 点击卡片在底部查看背景与效果说明；左下角可重置单个天赋或全部天赋。

signal closed

const ICON_ROOT := "res://assets/art/ui/talents/"
## 天赋画布比可视区宽：按住拖动可左右平移查看后续节点。
const CONTENT_SIZE := Vector2(1620, 500)
const NODES: Array[Dictionary] = [
	{"id": &"hp", "title": "生命强化", "icon": "hp_boost", "desc": "生命上限 +15/级（能量单元）",
		"detail": "强化 DOLL 机体的承伤结构。每级提高生命上限 15 点，适合正面交火与长时间搜刮。",
		"pos": Vector2(220, 10), "prereq": &""},
	{"id": &"move", "title": "战术体能", "icon": "recon", "desc": "移动速度 +4%/级（能量单元）",
		"detail": "优化腿部驱动与转向响应，提高行走与冲刺速度，便于快速穿越火线或撤离。",
		"pos": Vector2(580, 10), "prereq": &"hp"},
	{"id": &"armor", "title": "护甲强化", "icon": "armor_up", "desc": "护甲上限 +20/级",
		"detail": "为机体加装承力骨架与缓冲层，提高护甲耐久上限，让护甲能承受更多次命中。",
		"pos": Vector2(940, 10), "prereq": &"move"},
	{"id": &"gun", "title": "枪械精度", "icon": "recoil_control", "desc": "基础散布 -6%/级（电子元件）",
		"detail": "校准枪械瞄具与持握姿势，降低基础散布，让中远距离点射更稳定。",
		"pos": Vector2(220, 176), "prereq": &""},
	{"id": &"reload", "title": "快速换弹", "icon": "pump_speed", "desc": "换弹时间 -6%/级（电子元件）",
		"detail": "改进换弹流程与供弹机构，缩短每次换弹所需时间，对高射速武器收益更高。",
		"pos": Vector2(580, 176), "prereq": &"gun"},
	{"id": &"magazine", "title": "弹匣扩容", "icon": "magazine_up", "desc": "弹匣容量 +8%/级",
		"detail": "改造弹匣与供弹坡道，提高所有武器的弹匣容量（管仓武器则增加管仓容量）。",
		"pos": Vector2(940, 176), "prereq": &"reload"},
	{"id": &"reserve", "title": "弹药储备", "icon": "ammo_reserve", "desc": "备弹上限 +20%/级",
		"detail": "扩充弹药携行具与背包挂点，提高 9mm 与 12G 的备弹上限，减少续航压力。",
		"pos": Vector2(1300, 176), "prereq": &"magazine"},
	{"id": &"scavenge", "title": "搜刮专家", "icon": "scavenger", "desc": "撤离资源 +10%/级（机械零件）",
		"detail": "提高战利品回收与折算效率，每次成功撤离可带回更多信用点。",
		"pos": Vector2(220, 342), "prereq": &""},
	{"id": &"magnet", "title": "磁力拾取", "icon": "magnet", "desc": "吸附范围 +20%/级",
		"detail": "在拾取装置上加装磁力线圈，扩大掉落物自动吸附的范围，混战中更不容易漏捡。",
		"pos": Vector2(580, 342), "prereq": &"scavenge"},
	{"id": &"loading", "title": "持续装填", "icon": "ammo_carry", "desc": "长按 R 逐发续装（管仓）",
		"detail": "解锁管仓武器的连续装填手法：按住 R 会在一发装填完成后自动续压下一发，直到弹仓装满或备弹耗尽。仅对 M870、M1014 等管仓武器生效。",
		"pos": Vector2(940, 342), "prereq": &"magazine"},
]
const CARD_SIZE := Vector2(300, 156)

var _panel: PanelContainer
var _summary: Label
var _feedback: Label
var _tree_area: Control
var _content: Control
var _pan_hint: Label
var _cards := {}
var _selected: StringName = &""
var _detail_title: Label
var _detail_body: Label
var _detail_meta: Label
var _reset_one: Button
var _reset_all: Button
var _confirm_layer: Control
var _dragging := false
var _drag_start_x := 0.0
var _drag_origin := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	_build_confirm()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -520
	_panel.offset_right = 520
	_panel.offset_top = -430
	_panel.offset_bottom = 430
	add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	_panel.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := PixelUI.label(header, "战术天赋 // TALENTS", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var close := PixelUI.button("返回", 48)
	close.custom_minimum_size.x = 140
	close.pressed.connect(close_tree)
	header.add_child(close)

	_summary = PixelUI.label(layout, "", PixelUI.FS_BODY, PixelUI.DIM)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	layout.add_child(divider)

	_tree_area = Control.new()
	_tree_area.custom_minimum_size = Vector2(960, 500)
	_tree_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_area.clip_contents = true
	_tree_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_tree_area.gui_input.connect(_on_tree_gui_input)
	_tree_area.resized.connect(_refresh_pan_hint)
	layout.add_child(_tree_area)

	# 画布实际比可视区宽，卡片与连线都放在 _content 里一起平移。
	_content = Control.new()
	_content.custom_minimum_size = CONTENT_SIZE
	_content.size = CONTENT_SIZE
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.draw.connect(_draw_tree_lines)
	_tree_area.add_child(_content)

	_build_root_card()
	for def in NODES:
		_build_node(def)

	_build_detail(layout)
	_build_bottom_bar(layout)


## 左下角底部栏：单个重置 / 全部重置（全部重置带二次确认）+ 操作反馈 + 拖动提示。
func _build_bottom_bar(parent: Node) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	parent.add_child(bar)

	_reset_one = PixelUI.button("重置所选", 46)
	_reset_one.custom_minimum_size.x = 160
	_reset_one.add_theme_font_size_override("font_size", 20)
	_reset_one.pressed.connect(_on_reset_selected)
	bar.add_child(_reset_one)

	_reset_all = PixelUI.button("重置全部", 46)
	_reset_all.custom_minimum_size.x = 160
	_reset_all.add_theme_font_size_override("font_size", 20)
	_reset_all.pressed.connect(_on_reset_all)
	bar.add_child(_reset_all)

	_feedback = PixelUI.label(bar, "", 20, PixelUI.OK)
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_pan_hint = PixelUI.label(bar, "按住拖动查看 →", 20, PixelUI.DIM)
	_pan_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pan_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_detail(parent: Node) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 112
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	_detail_title = PixelUI.label(rows, "天赋说明", PixelUI.FS_BODY, PixelUI.AMBER)
	_detail_body = PixelUI.label(rows, "", 20, PixelUI.TEXT)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_meta = PixelUI.label(rows, "", 20, PixelUI.DIM)


## 全部重置的二次确认层。
func _build_confirm() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -140
	panel.offset_bottom = 140
	_confirm_layer.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	PixelUI.label(rows, "确认重置全部天赋？", PixelUI.FS_TITLE, PixelUI.AMBER)
	var body := PixelUI.label(rows,
		"所有天赋等级归零，已投入的信用点与基础资源会全额返还。",
		PixelUI.FS_BODY, PixelUI.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(buttons)
	var confirm := PixelUI.button("确认重置", 46)
	confirm.custom_minimum_size.x = 220
	confirm.pressed.connect(_confirm_reset_all)
	buttons.add_child(confirm)
	var cancel := PixelUI.button("取消", 46)
	cancel.custom_minimum_size.x = 220
	cancel.pressed.connect(func() -> void: _confirm_layer.hide())
	buttons.add_child(cancel)

	_confirm_layer.hide()


func _build_root_card() -> void:
	var card := PanelContainer.new()
	card.position = Vector2(10, 170)
	card.size = Vector2(160, CARD_SIZE.y)
	card.custom_minimum_size = card.size
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.5))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	_content.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	card.add_child(rows)
	PixelUI.label(rows, "DOLL-01", PixelUI.FS_BODY, PixelUI.AMBER)
	PixelUI.label(rows, "作战核心\n基础属性\n全部可强化", PixelUI.FS_BODY, PixelUI.DIM)


func _build_node(def: Dictionary) -> void:
	var id: StringName = def["id"]
	var card := PanelContainer.new()
	card.position = def["pos"]
	card.size = CARD_SIZE
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(id))
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.4))
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	var selected := style.duplicate() as StyleBoxFlat
	selected.border_color = PixelUI.AMBER_BRIGHT
	selected.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", style)
	_content.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	card.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	var icon := TextureRect.new()
	var path := ICON_ROOT + String(def["icon"]) + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.add_child(icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var title := PixelUI.label(names, String(def["title"]), PixelUI.FS_BODY, PixelUI.AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var level := PixelUI.label(names, "Lv.0 / 0", 20, PixelUI.DIM)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var desc := PixelUI.label(rows, String(def["desc"]), PixelUI.FS_BODY, PixelUI.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var buy := PixelUI.button("强化", 38)
	buy.custom_minimum_size.x = 260
	buy.add_theme_font_size_override("font_size", 20)
	buy.pressed.connect(_buy.bind(id))
	rows.add_child(buy)
	_cards[id] = {
		"card": card, "level": level, "buy": buy,
		"style": style, "style_selected": selected,
	}


func open() -> void:
	visible = true
	move_to_front()
	_feedback.text = ""
	_selected = &""
	_confirm_layer.hide()
	_refresh()
	_refresh_pan_hint()


func close_tree() -> void:
	if not visible:
		return
	_end_drag()
	_confirm_layer.hide()
	visible = false
	closed.emit()


func _refresh() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_summary.text = "存档未加载"
		return
	_summary.text = "信用点 %d    XP %d    Lv.%d    %s %d / %s %d / %s %d" % [
		p.credits(), int(p.data.get("xp", 0)), int(p.data.get("skill_level", 1)),
		ResourceDB.display_name(&"electronics"), p.material_count(&"electronics"),
		ResourceDB.display_name(&"energy"), p.material_count(&"energy"),
		ResourceDB.display_name(&"parts"), p.material_count(&"parts")]
	var total_levels := 0
	for def in NODES:
		var id: StringName = def["id"]
		var entry: Dictionary = _cards.get(id, {})
		var level := int(p.talent_2d_level(id))
		var maximum := int(p.talent_2d_max(id))
		var cost := int(p.talent_2d_cost(id))
		var material: StringName = p.talent_2d_material(id)
		var material_cost := int(p.talent_2d_material_cost(id))
		var prereq: StringName = def["prereq"]
		var prereq_ok := prereq == &"" or int(p.talent_2d_level(prereq)) > 0
		var level_label: Label = entry["level"]
		var buy: Button = entry["buy"]
		var card: PanelContainer = entry["card"]
		total_levels += level
		level_label.text = "Lv.%d / %d" % [level, maximum]
		if material_cost > 0:
			level_label.text += "   %s×%d" % [
				ResourceDB.display_name(material), material_cost]
		buy.disabled = cost < 0 or not prereq_ok \
			or p.credits() < cost or p.material_count(material) < material_cost
		if cost < 0:
			buy.text = "已满级"
		elif not prereq_ok:
			buy.text = "需要 %s Lv.1" % _title(prereq)
		else:
			buy.text = "强化 · %d 信用点" % cost
		card.modulate = Color(1, 1, 1, 1) if prereq_ok else Color(1, 1, 1, 0.55)
		card.add_theme_stylebox_override(
			"panel", entry["style_selected"] if id == _selected else entry["style"])
	_reset_all.disabled = total_levels == 0
	_reset_one.disabled = _selected == &"" or int(p.talent_2d_level(_selected)) == 0
	_refresh_detail(p)
	_content.queue_redraw()


## 底部说明区：背景描述 + 当前效果 + 下一级消耗。
func _refresh_detail(p: Node) -> void:
	if _selected == &"":
		_detail_title.text = "天赋说明"
		_detail_body.text = "点击任意天赋卡片查看背景与效果说明。购买后开始行动时生效；重置会全额返还已投入的信用点与基础资源。"
		_detail_meta.text = ""
		return
	var def := _def(_selected)
	if def.is_empty():
		return
	var level := int(p.talent_2d_level(_selected))
	var maximum := int(p.talent_2d_max(_selected))
	var cost := int(p.talent_2d_cost(_selected))
	var material := StringName(p.talent_2d_material(_selected))
	var material_cost := int(p.talent_2d_material_cost(_selected))
	_detail_title.text = "%s   Lv.%d / %d" % [String(def["title"]), level, maximum]
	_detail_body.text = "%s\n当前效果：%s" % [
		String(def.get("detail", "")), _effect_text(_selected, level)]
	var prereq: StringName = def["prereq"]
	if cost < 0:
		_detail_meta.text = "已满级 · 重置可返还已投入资源"
	elif prereq != &"" and int(p.talent_2d_level(prereq)) < 1:
		_detail_meta.text = "下一级：%d 信用点 + %s×%d · 需要 %s Lv.1" % [
			cost, ResourceDB.display_name(material), material_cost, _title(prereq)]
	else:
		_detail_meta.text = "下一级：%d 信用点 + %s×%d · 前置：%s" % [
			cost, ResourceDB.display_name(material), material_cost,
			"无" if prereq == &"" else _title(prereq)]


func _effect_text(id: StringName, level: int) -> String:
	match id:
		&"hp":
			return "生命上限 %d（基础 100）" % (100 + level * 15)
		&"move":
			return "移动速度 +%d%%" % (level * 4)
		&"gun":
			return "基础散布 -%d%%" % (level * 6)
		&"reload":
			return "换弹时间 -%d%%" % (level * 6)
		&"scavenge":
			return "撤离资源 +%d%%" % (level * 10)
		&"armor":
			return "护甲上限 +%d" % (level * 20)
		&"magazine":
			return "弹匣容量 +%d%%" % (level * 8)
		&"reserve":
			return "备弹上限 +%d%%" % (level * 20)
		&"magnet":
			return "掉落吸附范围 +%d%%" % (level * 20)
		&"loading":
			return "持续装填已解锁" if level > 0 else "持续装填未解锁"
	return ""


func _on_card_input(event: InputEvent, id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = id
		_begin_drag()
		_feedback.text = ""
		_refresh()


func _buy(id: StringName) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	_selected = id
	if p.buy_talent_2d(id):
		_feedback.text = "已强化「%s」· 开始行动后生效" % _title(id)
		_feedback.add_theme_color_override("font_color", PixelUI.OK)
	else:
		_feedback.text = "信用点或基础资源不足，或前置未解锁"
		_feedback.add_theme_color_override("font_color", PixelUI.DANGER)
	_refresh()


## 单个重置：连同依赖该节点的天赋一起清空，避免出现无效加点。
func _on_reset_selected() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null or _selected == &"":
		return
	var result: Dictionary = p.reset_talent_2d(_selected)
	var nodes: Array = result["nodes"]
	if nodes.is_empty():
		_feedback.text = "所选天赋没有可重置的等级"
		_feedback.add_theme_color_override("font_color", PixelUI.DIM)
		_refresh()
		return
	var extra := ""
	if nodes.size() > 1:
		extra = "（含依赖节点 %d 个）" % (nodes.size() - 1)
	_feedback.text = "已重置「%s」%s · 返还 %d 信用点与材料" % [
		_title(_selected), extra, int(result["credits"])]
	_feedback.add_theme_color_override("font_color", PixelUI.OK)
	_refresh()


func _on_reset_all() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	_confirm_layer.show()
	_confirm_layer.move_to_front()


func _confirm_reset_all() -> void:
	_confirm_layer.hide()
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	var result: Dictionary = p.reset_all_talents_2d()
	_selected = &""
	if (result["nodes"] as Array).is_empty():
		_feedback.text = "当前没有已投入的天赋"
		_feedback.add_theme_color_override("font_color", PixelUI.DIM)
	else:
		_feedback.text = "已重置全部天赋 · 返还 %d 信用点与材料" % int(result["credits"])
		_feedback.add_theme_color_override("font_color", PixelUI.OK)
	_refresh()


func _def(id: StringName) -> Dictionary:
	for def in NODES:
		if def["id"] == id:
			return def
	return {}


func _title(id: StringName) -> String:
	return String(_def(id).get("title", String(id)))


## 连线画在卡片下层、卡片之间的空隙里；端点取卡片边缘中心，避免被卡片盖住。
func _draw_tree_lines() -> void:
	var amber := Color(PixelUI.AMBER, 0.55)
	var dim := Color(PixelUI.DIM, 0.35)
	var root_center := Vector2(170, 248)
	_content.draw_line(root_center, _left_center(&"hp"), amber, 2.0)
	_content.draw_line(root_center, _left_center(&"gun"), amber, 2.0)
	_content.draw_line(root_center, _left_center(&"scavenge"), amber, 2.0)
	_link(&"hp", _right_center(&"hp"), _left_center(&"move"))
	_link(&"move", _right_center(&"move"), _left_center(&"armor"))
	_link(&"gun", _right_center(&"gun"), _left_center(&"reload"))
	_link(&"reload", _right_center(&"reload"), _left_center(&"magazine"))
	_link(&"magazine", _right_center(&"magazine"), _left_center(&"reserve"))
	_link(&"scavenge", _right_center(&"scavenge"), _left_center(&"magnet"))
	# 持续装填在弹匣扩容正下方，竖线落在两行卡片之间的空隙里。
	_content.draw_line(_bottom_center(&"magazine"), _top_center(&"loading"),
		_link_color(&"magazine"), 2.0)


func _card_pos(id: StringName) -> Vector2:
	return _def(id).get("pos", Vector2.ZERO)


func _left_center(id: StringName) -> Vector2:
	return _card_pos(id) + Vector2(0.0, CARD_SIZE.y * 0.5)


func _right_center(id: StringName) -> Vector2:
	return _card_pos(id) + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5)


func _bottom_center(id: StringName) -> Vector2:
	return _card_pos(id) + Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)


func _top_center(id: StringName) -> Vector2:
	return _card_pos(id) + Vector2(CARD_SIZE.x * 0.5, 0.0)


func _link_color(prereq: StringName) -> Color:
	var p := get_node_or_null("/root/Progress")
	var on := p != null and int(p.talent_2d_level(prereq)) > 0
	return Color(PixelUI.AMBER, 0.55) if on else Color(PixelUI.DIM, 0.35)


func _link(prereq: StringName, from: Vector2, to: Vector2) -> void:
	_content.draw_line(from, to, _link_color(prereq), 2.0)


## ---- 画布左右拖动 ----

func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_drag()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_pan(_content.position.x + 80.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_pan(_content.position.x - 80.0)


func _begin_drag() -> void:
	if _content == null:
		return
	_dragging = true
	_drag_start_x = get_global_mouse_position().x
	_drag_origin = _content.position.x


func _end_drag() -> void:
	_dragging = false


func _set_pan(value: float) -> void:
	if _content == null or _tree_area == null:
		return
	var min_x := minf(0.0, _tree_area.size.x - _content.size.x)
	_content.position.x = clampf(value, min_x, 0.0)
	_refresh_pan_hint()


func _refresh_pan_hint() -> void:
	if _pan_hint == null or _content == null or _tree_area == null:
		return
	_pan_hint.visible = _content.size.x > _tree_area.size.x + 1.0


## 拖动时鼠标可能滑到卡片上，所以在根节点统一接管移动与松开。
func _input(event: InputEvent) -> void:
	if not visible or not _dragging:
		return
	if event is InputEventMouseMotion:
		_set_pan(_drag_origin + get_global_mouse_position().x - _drag_start_x)
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirm_layer != null and _confirm_layer.visible:
			_confirm_layer.hide()
		else:
			close_tree()
		get_viewport().set_input_as_handled()
