extends Control
class_name TalentTree2D
## 2D 战术天赋树（放射状分叉树视图）：
## 从左侧中央「DOLL-01 神经核心」向三条独立方向自然蔓延——
##   上枝 · 机体防线（青蓝）：生命强化 → 战术体能 → 护甲强化
##   中枝 · 火力弹道（琥珀）：枪械精度 → 快速换弹 → 弹匣扩容 ⇄（分叉：弹药储备 / 持续装填）
##   下枝 · 战地搜刮（翡翠）：搜刮专家 → 磁力拾取
## 支持画布拖拽平移与滚轮横向浏览，点击节点在底部查看彩色富文本说明与消耗。

signal closed

const ICON_ROOT := "res://assets/art/ui/talents/"
const CONTENT_SIZE := Vector2(1580, 516)
const CARD_SIZE := Vector2(252, 114)
const ROOT_POS := Vector2(24, 192)
const ROOT_SIZE := Vector2(150, 126)

const BRANCH_COLORS := {
	"survival": Color(0.32, 0.86, 1.0),
	"firepower": Color(1.0, 0.66, 0.26),
	"scavenge": Color(0.36, 0.94, 0.66),
}

const BRANCH_META := {
	"survival": {"tag": "▲ 机体防线 // SURVIVAL", "pos": Vector2(248, 8)},
	"firepower": {"tag": "◆ 火力弹道 // FIREPOWER", "pos": Vector2(270, 174)},
	"scavenge": {"tag": "▼ 战地搜刮 // SCAVENGE", "pos": Vector2(248, 338)},
}

const NODES: Array[Dictionary] = [
	# 上枝 · 机体防线（向上右攀升蔓延）
	{"id": &"hp", "branch": "survival", "title": "生命强化", "icon": "hp_boost",
		"desc": "生命上限 +15 / 级",
		"detail": "强化 DOLL 机体的承伤结构。每级提高生命上限 15 点，适合正面交火与长时间搜刮。",
		"pos": Vector2(248, 42), "prereq": &""},
	{"id": &"move", "branch": "survival", "title": "战术体能", "icon": "recon",
		"desc": "移动速度 +4% / 级",
		"detail": "优化腿部驱动与转向响应，提高行走与冲刺速度，便于快速穿越火线或撤离。",
		"pos": Vector2(578, 22), "prereq": &"hp"},
	{"id": &"armor", "branch": "survival", "title": "护甲强化", "icon": "armor_up",
		"desc": "护甲上限 +20 / 级",
		"detail": "为机体加装承力骨架与缓冲层，提高护甲耐久上限，让护甲能承受更多次命中。",
		"pos": Vector2(910, 10), "prereq": &"move"},
	# 中枝 · 火力弹道（主干向右延伸并在弹匣扩容处上下双分叉）
	{"id": &"gun", "branch": "firepower", "title": "枪械精度", "icon": "recoil_control",
		"desc": "基础散布 -6% / 级",
		"detail": "校准枪械瞄具与持握姿势，降低基础散布，让中远距离点射更稳定。",
		"pos": Vector2(270, 200), "prereq": &""},
	{"id": &"reload", "branch": "firepower", "title": "快速换弹", "icon": "pump_speed",
		"desc": "换弹时间 -6% / 级",
		"detail": "改进换弹流程与供弹机构，缩短每次换弹所需时间，对高射速武器收益更高。",
		"pos": Vector2(600, 200), "prereq": &"gun"},
	{"id": &"magazine", "branch": "firepower", "title": "弹匣扩容", "icon": "magazine_up",
		"desc": "弹匣容量 +8% / 级",
		"detail": "改造弹匣与供弹坡道，提高所有武器的弹匣容量（管仓武器则增加管仓容量）。",
		"pos": Vector2(930, 200), "prereq": &"reload"},
	{"id": &"reserve", "branch": "firepower", "title": "弹药储备", "icon": "ammo_reserve",
		"desc": "备弹上限 +20% / 级",
		"detail": "扩充弹药携行具与背包挂点，提高各口径备弹上限，显著缓解长局续航压力。",
		"pos": Vector2(1290, 112), "prereq": &"magazine"},
	{"id": &"loading", "branch": "firepower", "title": "持续装填", "icon": "ammo_carry",
		"desc": "长按 R 逐发续装（管仓）",
		"detail": "解锁管仓武器的连续装填手法：按住 R 会在一发装填完成后自动续压下一发，直到弹仓装满或备弹耗尽。仅对 M870、M1014 等管仓武器生效。",
		"pos": Vector2(1290, 286), "prereq": &"magazine"},
	# 下枝 · 战地搜刮（向下右展开蔓延）
	{"id": &"scavenge", "branch": "scavenge", "title": "搜刮专家", "icon": "scavenger",
		"desc": "撤离资源 +10% / 级",
		"detail": "提高战利品回收与折算效率，每次成功撤离可带回更多信用点。",
		"pos": Vector2(248, 366), "prereq": &""},
	{"id": &"magnet", "branch": "scavenge", "title": "磁力拾取", "icon": "magnet",
		"desc": "吸附范围 +20% / 级",
		"detail": "在拾取装置上加装磁力线圈，扩大掉落物自动吸附的范围，混战中更不容易漏捡。",
		"pos": Vector2(590, 392), "prereq": &"scavenge"},
]

var _panel: PanelContainer
var _summary: Label
var _summary_rich: RichTextLabel
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
var _drag_start := Vector2.ZERO
var _drag_origin := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	_build_confirm()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -590
	_panel.offset_right = 590
	_panel.offset_top = -425
	_panel.offset_bottom = 425
	add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	_panel.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := PixelUI.emphasize(
		PixelUI.label(header, "战术天赋树 // NEURAL SKILL TREE", PixelUI.FS_TITLE, PixelUI.AMBER), 3, 2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var close := PixelUI.button("返回", 44)
	close.custom_minimum_size.x = 136
	close.pressed.connect(close_tree)
	header.add_child(close)

	# 保留 _summary.text 供既有测试断言，视觉层用 _summary_rich 展示彩色高亮库存。
	_summary = PixelUI.label(layout, "", 18, PixelUI.DIM)
	_summary.visible = false
	_summary_rich = PixelUI.rich_label(layout, "", 20, PixelUI.DIM, 2)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.75))
	layout.add_child(divider)

	_tree_area = Control.new()
	_tree_area.custom_minimum_size = Vector2(1080, 520)
	_tree_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_area.clip_contents = true
	_tree_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_tree_area.gui_input.connect(_on_tree_gui_input)
	_tree_area.resized.connect(_refresh_pan_hint)
	layout.add_child(_tree_area)

	_content = Control.new()
	_content.custom_minimum_size = CONTENT_SIZE
	_content.size = CONTENT_SIZE
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.draw.connect(_draw_tree_canvas)
	_tree_area.add_child(_content)

	_build_root_card()
	for def in NODES:
		_build_node(def)

	_build_detail(layout)
	_build_bottom_bar(layout)


func _build_bottom_bar(parent: Node) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	parent.add_child(bar)

	_reset_one = PixelUI.button("重置所选", 42)
	_reset_one.custom_minimum_size.x = 152
	_reset_one.add_theme_font_size_override("font_size", 20)
	_reset_one.pressed.connect(_on_reset_selected)
	bar.add_child(_reset_one)

	_reset_all = PixelUI.button("重置全部", 42)
	_reset_all.custom_minimum_size.x = 152
	_reset_all.add_theme_font_size_override("font_size", 20)
	_reset_all.pressed.connect(_on_reset_all)
	bar.add_child(_reset_all)

	_feedback = PixelUI.emphasize(PixelUI.label(bar, "", 20, PixelUI.OK), 2, 1)
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_pan_hint = PixelUI.label(bar, "按住拖动 / 滚轮探索分支 →", 19, PixelUI.AMBER_BRIGHT)
	_pan_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pan_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_detail(parent: Node) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 104
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.40))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	panel.add_child(rows)
	_detail_title = PixelUI.emphasize(
		PixelUI.label(rows, "天赋说明", PixelUI.FS_BODY, PixelUI.AMBER_BRIGHT), 2, 1)
	_detail_body = PixelUI.label(rows, "", 19, PixelUI.TEXT)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_meta = PixelUI.label(rows, "", 19, PixelUI.GOLD)


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
	PixelUI.emphasize(PixelUI.label(rows, "确认重置全部天赋？", PixelUI.FS_TITLE, PixelUI.AMBER), 3, 2)
	var body := PixelUI.label(rows,
		"所有天赋等级归零，已投入的信用点与基础资源会全额返还。",
		PixelUI.FS_BODY, PixelUI.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(buttons)
	var confirm := PixelUI.primary_button("确认重置", 46)
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
	card.position = ROOT_POS
	card.size = ROOT_SIZE
	card.custom_minimum_size = ROOT_SIZE
	var style := PixelUI.panel_style(Color(0.06, 0.08, 0.11, 0.98), 2, PixelUI.AMBER_BRIGHT)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	_content.add_child(card)
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 6)
	card.add_child(rows)
	var tag := PixelUI.emphasize(PixelUI.label(rows, "DOLL-01", PixelUI.FS_BODY, PixelUI.AMBER_BRIGHT), 2, 1)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := PixelUI.label(rows, "神经核心", 18, PixelUI.CYAN)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := PixelUI.label(rows, "三向分支\n自由强化", 17, PixelUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_node(def: Dictionary) -> void:
	var id: StringName = def["id"]
	var branch := String(def.get("branch", "firepower"))
	var accent: Color = BRANCH_COLORS.get(branch, PixelUI.AMBER)

	var card := PanelContainer.new()
	card.position = def["pos"]
	card.size = CARD_SIZE
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_input.bind(id))

	var style := PixelUI.panel_style(Color(0.045, 0.060, 0.080, 0.97), 1, Color(accent, 0.45))
	style.border_width_top = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	var unlocked_style := style.duplicate() as StyleBoxFlat
	unlocked_style.bg_color = Color(
		lerpf(0.05, accent.r, 0.10),
		lerpf(0.065, accent.g, 0.10),
		lerpf(0.085, accent.b, 0.10),
		0.98)
	unlocked_style.border_color = Color(accent, 0.85)
	var selected := unlocked_style.duplicate() as StyleBoxFlat
	selected.border_color = accent.lightened(0.28)
	selected.set_border_width_all(2)
	selected.border_width_top = 4
	card.add_theme_stylebox_override("panel", style)
	_content.add_child(card)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	card.add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	rows.add_child(top)
	var icon := TextureRect.new()
	var path := ICON_ROOT + String(def["icon"]) + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top.add_child(icon)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 1)
	top.add_child(names)
	var title := PixelUI.emphasize(PixelUI.label(names, String(def["title"]), 20, accent.lightened(0.18)), 2, 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var level := PixelUI.label(names, "Lv.0 / 0", 15, PixelUI.DIM)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var desc := PixelUI.label(rows, String(def["desc"]), 16, PixelUI.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	desc.clip_text = true
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var buy := PixelUI.button("强化", 28)
	buy.custom_minimum_size.x = CARD_SIZE.x - 22.0
	buy.add_theme_font_size_override("font_size", 16)
	buy.pressed.connect(_buy.bind(id))
	rows.add_child(buy)

	_cards[id] = {
		"card": card, "level": level, "buy": buy, "accent": accent,
		"style": style, "style_unlocked": unlocked_style, "style_selected": selected,
	}


func open() -> void:
	visible = true
	move_to_front()
	_feedback.text = ""
	_selected = &""
	_confirm_layer.hide()
	_set_pan(0.0)
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
		_summary_rich.text = PixelUI.bb("存档未加载", PixelUI.DANGER)
		return
	var credits := int(p.credits())
	var xp := int(p.data.get("xp", 0))
	var slv := int(p.data.get("skill_level", 1))
	var elec := int(p.material_count(&"electronics"))
	var ener := int(p.material_count(&"energy"))
	var parts := int(p.material_count(&"parts"))
	_summary.text = "信用点 %d    XP %d    Lv.%d    %s %d / %s %d / %s %d" % [
		credits, xp, slv,
		ResourceDB.display_name(&"electronics"), elec,
		ResourceDB.display_name(&"energy"), ener,
		ResourceDB.display_name(&"parts"), parts]
	_summary_rich.text = "信用点 %s   ·   XP %s (%s)   ·   %s %s  /  %s %s  /  %s %s" % [
		PixelUI.bb(str(credits), PixelUI.GOLD),
		PixelUI.bb(str(xp), PixelUI.TEXT),
		PixelUI.bb("Lv.%d" % slv, PixelUI.AMBER_BRIGHT),
		PixelUI.bb(ResourceDB.display_name(&"electronics"), BRANCH_COLORS["firepower"]),
		PixelUI.bb(str(elec), PixelUI.TEXT),
		PixelUI.bb(ResourceDB.display_name(&"energy"), BRANCH_COLORS["survival"]),
		PixelUI.bb(str(ener), PixelUI.TEXT),
		PixelUI.bb(ResourceDB.display_name(&"parts"), BRANCH_COLORS["scavenge"]),
		PixelUI.bb(str(parts), PixelUI.TEXT),
	]
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
		var accent: Color = entry["accent"]
		total_levels += level

		var pips := ""
		for k in maximum:
			pips += "■" if k < level else "□"
		level_label.text = "%s  Lv.%d/%d" % [pips, level, maximum]
		level_label.add_theme_color_override(
			"font_color", accent if level > 0 else PixelUI.DIM)

		buy.disabled = cost < 0 or not prereq_ok \
			or credits < cost or p.material_count(material) < material_cost
		if cost < 0:
			buy.text = "★ 已满级"
		elif not prereq_ok:
			buy.text = "需 %s Lv.1" % _title(prereq)
		else:
			buy.text = "强化 · %d 点 + %s×%d" % [
				cost, ResourceDB.display_name(material).substr(0, 2), material_cost]
		card.modulate = Color(1, 1, 1, 1) if prereq_ok else Color(0.82, 0.85, 0.90, 0.55)
		var box: StyleBoxFlat = entry["style_selected"] if id == _selected \
			else (entry["style_unlocked"] if level > 0 else entry["style"])
		card.add_theme_stylebox_override("panel", box)

	_reset_all.disabled = total_levels == 0
	_reset_one.disabled = _selected == &"" or int(p.talent_2d_level(_selected)) == 0
	_refresh_detail(p)
	_content.queue_redraw()


func _refresh_detail(p: Node) -> void:
	if _selected == &"":
		_detail_title.text = "天赋说明 // 点击任意枝干节点查看详情"
		_detail_title.add_theme_color_override("font_color", PixelUI.AMBER_BRIGHT)
		_detail_body.text = "从左侧 DOLL-01 核心沿青蓝（机体防线）、琥珀（火力弹道）、翡翠（战地搜刮）三条技能方向蔓延。购买后下局生效，重置全额返还。"
		_detail_meta.text = ""
		return
	var def := _def(_selected)
	if def.is_empty():
		return
	var accent: Color = BRANCH_COLORS.get(String(def.get("branch", "firepower")), PixelUI.AMBER)
	var level := int(p.talent_2d_level(_selected))
	var maximum := int(p.talent_2d_max(_selected))
	var cost := int(p.talent_2d_cost(_selected))
	var material := StringName(p.talent_2d_material(_selected))
	var material_cost := int(p.talent_2d_material_cost(_selected))
	_detail_title.text = "%s   Lv.%d / %d" % [String(def["title"]), level, maximum]
	_detail_title.add_theme_color_override("font_color", accent.lightened(0.15))
	_detail_body.text = "%s\n当前效果：%s" % [
		String(def.get("detail", "")), _effect_text(_selected, level)]
	var prereq: StringName = def["prereq"]
	if cost < 0:
		_detail_meta.text = "★ 已满级 · 重置可全额返还已投入资源"
		_detail_meta.add_theme_color_override("font_color", PixelUI.OK)
	elif prereq != &"" and int(p.talent_2d_level(prereq)) < 1:
		_detail_meta.text = "下一级：%d 信用点 + %s×%d  ·  前置未解锁：需要 %s Lv.1" % [
			cost, ResourceDB.display_name(material), material_cost, _title(prereq)]
		_detail_meta.add_theme_color_override("font_color", PixelUI.DANGER)
	else:
		_detail_meta.text = "下一级消耗：%d 信用点 + %s×%d  ·  前置：%s" % [
			cost, ResourceDB.display_name(material), material_cost,
			"核心直连" if prereq == &"" else _title(prereq)]
		_detail_meta.add_theme_color_override("font_color", PixelUI.GOLD)


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


## 绘制背景神经网格、核心光晕、三条分支名称与有机贝塞尔技能树枝干。
func _draw_tree_canvas() -> void:
	var c := _content
	var sz := CONTENT_SIZE
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.014, 0.020, 0.030, 0.96), true)
	# 细微战术坐标网格，增强空间延展感。
	var grid := Color(0.28, 0.42, 0.56, 0.08)
	var x := 48.0
	while x < sz.x:
		c.draw_line(Vector2(x, 0), Vector2(x, sz.y), grid, 1.0)
		x += 64.0
	var y := 48.0
	while y < sz.y:
		c.draw_line(Vector2(0, y), Vector2(sz.x, y), grid, 1.0)
		y += 64.0

	# 核心右侧发散光晕。
	var root_out := ROOT_POS + Vector2(ROOT_SIZE.x, ROOT_SIZE.y * 0.5)
	c.draw_circle(root_out, 58.0, Color(PixelUI.AMBER, 0.06), true, -1.0, true)
	c.draw_circle(root_out, 28.0, Color(PixelUI.AMBER, 0.12), true, -1.0, true)

	# 分支方向标题标签。
	for branch_key in BRANCH_META:
		var meta: Dictionary = BRANCH_META[branch_key]
		var col: Color = BRANCH_COLORS[branch_key]
		var pos: Vector2 = meta["pos"]
		c.draw_string(PixelUI.FONT, pos + Vector2(0, 16), String(meta["tag"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col, 0.85))

	# 从核心引出的三条主枝干（平滑三次贝塞尔曲线，呈现放射蔓延感）。
	var p := get_node_or_null("/root/Progress")
	for def in NODES:
		var id: StringName = def["id"]
		var prereq: StringName = def["prereq"]
		var branch := String(def.get("branch", "firepower"))
		var accent: Color = BRANCH_COLORS.get(branch, PixelUI.AMBER)
		var to_pt := _left_center(id)
		var from_pt := root_out if prereq == &"" else _right_center(prereq)
		var unlocked := prereq == &"" or (p != null and int(p.talent_2d_level(prereq)) > 0)
		var active := p != null and int(p.talent_2d_level(id)) > 0
		_draw_branch_curve(from_pt, to_pt, accent, unlocked, active)


func _draw_branch_curve(from: Vector2, to: Vector2, accent: Color,
		unlocked: bool, active: bool) -> void:
	var dx := maxf((to.x - from.x) * 0.52, 48.0)
	var c1 := from + Vector2(dx, 0.0)
	var c2 := to - Vector2(dx, 0.0)
	const STEPS := 24
	var pts := PackedVector2Array()
	pts.resize(STEPS + 1)
	for i in STEPS + 1:
		var t := float(i) / float(STEPS)
		var omt := 1.0 - t
		pts[i] = omt * omt * omt * from \
			+ 3.0 * omt * omt * t * c1 \
			+ 3.0 * omt * t * t * c2 \
			+ t * t * t * to
	if active:
		_content.draw_polyline(pts, Color(accent, 0.24), 9.0, true)
		_content.draw_polyline(pts, accent.lightened(0.12), 3.0, true)
	elif unlocked:
		_content.draw_polyline(pts, Color(accent, 0.14), 6.0, true)
		_content.draw_polyline(pts, Color(accent, 0.65), 2.2, true)
	else:
		_content.draw_polyline(pts, Color(PixelUI.DIM, 0.30), 1.8, true)
	# 节点端连接点 + 方向小箭头。
	var dot_col := accent.lightened(0.15) if active else (Color(accent, 0.72) if unlocked else Color(PixelUI.DIM, 0.4))
	_content.draw_circle(from, 4.0, dot_col, true, -1.0, true)
	var arrow := PackedVector2Array([
		to,
		to + Vector2(-9.0, -4.5),
		to + Vector2(-9.0, 4.5),
	])
	_content.draw_colored_polygon(arrow, dot_col)


func _card_pos(id: StringName) -> Vector2:
	return _def(id).get("pos", Vector2.ZERO)


func _left_center(id: StringName) -> Vector2:
	return _card_pos(id) + Vector2(0.0, CARD_SIZE.y * 0.5)


func _right_center(id: StringName) -> Vector2:
	return _card_pos(id) + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5)


## ---- 画布二维拖动与滚轮浏览 ----

func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin_drag()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_pan(_content.position.x + 88.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_pan(_content.position.x - 88.0)


func _begin_drag() -> void:
	if _content == null:
		return
	_dragging = true
	_drag_start = get_global_mouse_position()
	_drag_origin = _content.position


func _end_drag() -> void:
	_dragging = false


func _set_pan(value: float, value_y := NAN) -> void:
	if _content == null or _tree_area == null:
		return
	var min_x := minf(0.0, _tree_area.size.x - _content.size.x)
	_content.position.x = clampf(value, min_x, 0.0)
	if not is_nan(value_y):
		var min_y := minf(0.0, _tree_area.size.y - _content.size.y)
		_content.position.y = clampf(value_y, min_y, 0.0)
	else:
		var min_y := minf(0.0, _tree_area.size.y - _content.size.y)
		_content.position.y = clampf(_content.position.y, min_y, 0.0)
	_refresh_pan_hint()


func _refresh_pan_hint() -> void:
	if _pan_hint == null or _content == null or _tree_area == null:
		return
	_pan_hint.visible = _content.size.x > _tree_area.size.x + 1.0


func _input(event: InputEvent) -> void:
	if not visible or not _dragging:
		return
	if event is InputEventMouseMotion:
		var delta := get_global_mouse_position() - _drag_start
		_set_pan(_drag_origin.x + delta.x, _drag_origin.y + delta.y)
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
