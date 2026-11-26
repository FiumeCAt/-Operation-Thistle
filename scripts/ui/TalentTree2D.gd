extends Control
class_name TalentTree2D
## 2D 战术天赋树（大画布放射状分叉树视图）：
## 从左侧中央「DOLL-01 神经核心」向三条独立方向自然蔓延——
##   上枝 · 机体防线（生存绿）：生命强化 ⇄（战术体能 → 护甲强化 / 声纹感知）
##   中枝 · 火力弹道（火力橙）：枪械精度 → 快速换弹 → 弹匣扩容 ⇄（弹药储备 / 持续装填）
##   下枝 · 战地搜刮（搜刮青）：搜刮专家 → 磁力拾取
## 每张节点卡片内置自适应竖向格栅等级条（自动适配任意等级上限，自下而上充能发光）；
## 支持大画布自由二维拖拽平移与滚轮浏览，点击节点在底部查看彩色富文本说明与消耗。

signal closed

const ICON_ROOT := "res://assets/art/ui/talents/"
const CONTENT_SIZE := Vector2(1880, 968)
const CARD_SIZE := Vector2(280, 128)
const ROOT_POS := Vector2(44, 468)
const ROOT_SIZE := Vector2(168, 152)
const DRAG_THRESHOLD := 5.0

const BRANCH_COLORS := {
	"survival": Color(0.32, 0.94, 0.56),
	"firepower": Color(1.0, 0.64, 0.24),
	"scavenge": Color(0.28, 0.88, 1.0),
}

const BRANCH_META := {
	"survival": {"tag": "▲ 机体防线 // SURVIVAL", "pos": Vector2(324, 8)},
	"firepower": {"tag": "◆ 火力弹道 // FIREPOWER", "pos": Vector2(348, 480)},
	"scavenge": {"tag": "▼ 战地搜刮 // SCAVENGE", "pos": Vector2(324, 788)},
}

const NODES: Array[Dictionary] = [
	# 上枝 · 机体防线（生存绿，生命强化分叉出体能防线与感知侦察线；均严格由左向右展开）
	{"id": &"hp", "branch": "survival", "title": "生命强化", "icon": "hp_boost",
		"desc": "生命上限 +15% / 级（+15）",
		"detail": "强化 DOLL 机体的承伤结构。每级提高生命上限 15%（+15 点，上限 5 级 +75%，与被动「机体适应」加算），适合正面交火与长线作战。",
		"pos": Vector2(324, 194), "prereq": &""},
	{"id": &"move", "branch": "survival", "title": "战术体能", "icon": "recon",
		"desc": "移动速度 +5% / 级",
		"detail": "优化腿部驱动与转向响应，每级提高行走与冲刺速度 5%（满级 +25%），便于快速穿越火线或撤离。",
		"pos": Vector2(716, 86), "prereq": &"hp"},
	{"id": &"armor", "branch": "survival", "title": "护甲强化", "icon": "armor_up",
		"desc": "护甲上限 +20% / 级（+20）",
		"detail": "为机体加装承力骨架与缓冲层，每级提高护甲耐久上限 20%（+20 点，满级 +100%），承受更多次命中。",
		"pos": Vector2(1112, 34), "prereq": &"move"},
	{"id": &"dodge_dist", "branch": "survival", "title": "战术步幅", "icon": "recon",
		"desc": "闪避翻滚距离 +8% / 级",
		"detail": "强化推进蹬踏力度，每级提升闪避翻滚位移距离 8%（满级 +40%），更易一步跨出敌方火力扇区与爆炸范围。",
		"pos": Vector2(1112, 174), "prereq": &"move"},
	{"id": &"dodge_cd", "branch": "survival", "title": "疾闪回气", "icon": "pump_speed",
		"desc": "闪避翻滚冷却 -8% / 级",
		"detail": "优化翻滚落地后的姿态衔接与气压回收，每级缩短闪避翻滚冷却时间 8%（满级 -40%），连续机动更流畅。",
		"pos": Vector2(1508, 174), "prereq": &"dodge_dist"},
	{"id": &"hearing", "branch": "survival", "title": "声纹感知", "icon": "support_protocol",
		"desc": "听距 +10%/级 · Lv.5 涟漪",
		"detail": "Lv.1~4 保留脚下经典方位环并每级提升听声距离 10%；Lv.5 满级（+50%，20.25m）解锁屏内扩散声波涟漪与屏外边缘来波前锋，默认与脚下环共存（可在设置中切换）。",
		"pos": Vector2(716, 306), "prereq": &"hp"},
	{"id": &"vision_range", "branch": "survival", "title": "远距侦察", "icon": "recon",
		"desc": "视野与暗视 +10% / 级",
		"detail": "强化光学传感器倍率与暗光增强模块，每级提高主视野锥距离与近身黑暗视野半径 10%（满级 +50%，100% 缩放立即可感），不畸变视角宽度。",
		"pos": Vector2(1112, 314), "prereq": &"hearing"},
	{"id": &"vision_angle", "branch": "survival", "title": "广角视野", "icon": "support_protocol",
		"desc": "视野半角 +4.4°/级（≤82°）",
		"detail": "加装广角光学棱镜，每级拓宽清晰视野与余光半角各 4.4°（满级 +22° → 清晰 62° / 总视野 82° 半角），同时保留背后视觉盲区压迫感。",
		"pos": Vector2(1508, 314), "prereq": &"vision_range"},
	# 中枝 · 火力弹道（火力橙，主干向右延伸并在弹匣扩容处上下双分叉）
	{"id": &"gun", "branch": "firepower", "title": "枪械精度", "icon": "recoil_control",
		"desc": "基础散布 -5% / 级",
		"detail": "校准枪械瞄具与持握姿势，每级降低基础散布 5%（满级 -25%），让中远距离点射更稳定。",
		"pos": Vector2(348, 560), "prereq": &""},
	{"id": &"reload", "branch": "firepower", "title": "快速换弹", "icon": "pump_speed",
		"desc": "换弹时间 -5% / 级",
		"detail": "改进换弹流程与供弹机构，每级缩短换弹时间 5%（满级 -25%），对高射速武器收益更高。",
		"pos": Vector2(740, 560), "prereq": &"gun"},
	{"id": &"magazine", "branch": "firepower", "title": "弹匣扩容", "icon": "magazine_up",
		"desc": "弹匣容量 +10% / 级",
		"detail": "改造弹匣与供弹坡道，每级提高所有武器的弹匣容量 10%（满级 +50%，管仓武器同步增加管仓容量）。",
		"pos": Vector2(1132, 560), "prereq": &"reload"},
	{"id": &"reserve", "branch": "firepower", "title": "弹药储备", "icon": "ammo_reserve",
		"desc": "备弹上限 +20% / 级",
		"detail": "扩充弹药携行具与背包挂点，每级提高各口径备弹上限 20%（满级 +100%），显著缓解长局续航压力。",
		"pos": Vector2(1528, 494), "prereq": &"magazine"},
	{"id": &"loading", "branch": "firepower", "title": "持续装填", "icon": "ammo_carry",
		"desc": "长按 R 逐发续装（管仓）",
		"detail": "解锁管仓武器的连续装填手法：按住 R 会在一发装填完成后自动续压下一发，直到弹仓装满或备弹耗尽。仅对 M870、M1014 等管仓武器生效。",
		"pos": Vector2(1528, 636), "prereq": &"magazine"},
	# 下枝 · 战地搜刮（搜刮青，向下右展开蔓延）
	{"id": &"scavenge", "branch": "scavenge", "title": "搜刮专家", "icon": "scavenger",
		"desc": "撤离资源 +10% / 级",
		"detail": "提高战利品回收与折算效率，每级提高撤离信用点与基础材料收益 10%（满级 +50%，与被动「行动津贴」加算）。",
		"pos": Vector2(324, 818), "prereq": &""},
	{"id": &"magnet", "branch": "scavenge", "title": "磁力拾取", "icon": "magnet",
		"desc": "吸附范围 +20% / 级",
		"detail": "在拾取装置上加装磁力线圈，每级扩大掉落物自动吸附范围 20%（满级 +100%），混战中不再漏捡。",
		"pos": Vector2(716, 818), "prereq": &"scavenge"},
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
var _passive_buttons: Dictionary = {}
var _passive_title: Label
var _confirm_layer: Control
var _dragging := false
var _drag_moved := false
var _drag_start := Vector2.ZERO
var _drag_origin := Vector2.ZERO


## 自适应竖向格栅等级条：外框 + 等分水平能量格，自动适配任意上限（1~N），自下而上点亮。
class TalentLevelGauge extends Control:
	var level := 0
	var max_level := 5
	var accent := Color(0.32, 0.94, 0.56)
	var unlocked := true

	func configure(cur_lv: int, max_lv: int, col: Color, is_unlocked: bool) -> void:
		level = maxi(cur_lv, 0)
		max_level = maxi(max_lv, 1)
		accent = col
		unlocked = is_unlocked
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 8.0 or h < 10.0:
			return
		var maxed := level >= max_level
		# 深黑底框 + 清晰外描边（满级时边框发亮，前置未解锁时暗化）。
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.024, 0.032, 0.96), true)
		var border_col := accent.lightened(0.22) if maxed \
			else (Color(0.62, 0.68, 0.74, 0.86) if unlocked else Color(0.34, 0.38, 0.44, 0.55))
		draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0)), border_col, false, 1.6)

		var pad := 3.5
		var gap := 3.0 if max_level <= 6 else 2.0
		var inner_w := maxf(w - pad * 2.0, 2.0)
		var inner_h := maxf(h - pad * 2.0, 2.0)
		var total_gap := gap * float(maxi(max_level - 1, 0))
		var seg_h := maxf((inner_h - total_gap) / float(max_level), 2.0)

		# 自下而上绘制每一个等级能量块（第 0 格在最底部，满级时整柱点亮）。
		for i in max_level:
			var y := h - pad - float(i + 1) * seg_h - float(i) * gap
			var rect := Rect2(Vector2(pad, y), Vector2(inner_w, seg_h))
			if i < level:
				var fill := accent.lightened(0.06) if not maxed else accent.lightened(0.16)
				draw_rect(rect, fill, true)
				# 顶部细高光与底部微暗边，增强像素能量块的立体质感。
				var hi_h := minf(2.0, seg_h * 0.25)
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, hi_h)),
					accent.lightened(0.45), true)
				draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 1.2), Vector2(rect.size.x, 1.2)),
					accent.darkened(0.28), true)
			elif i == level and unlocked:
				# 下一级待解锁槽：微弱同色空框提示下一步升级进度。
				draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.08), true)
				draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.42), false, 1.0)
			else:
				draw_rect(rect, Color(0.07, 0.09, 0.12, 0.92), true)
				draw_rect(rect, Color(0.22, 0.26, 0.32, 0.45), false, 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	_build_confirm()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -720
	_panel.offset_right = 720
	_panel.offset_top = -422
	_panel.offset_bottom = 422
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

	_build_passives_strip(layout)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.75))
	layout.add_child(divider)

	_tree_area = Control.new()
	_tree_area.custom_minimum_size = Vector2(1280, 480)
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


func _build_passives_strip(parent: Node) -> void:
	var bar_panel := PanelContainer.new()
	var st := PixelUI.panel_style(Color(0.024, 0.036, 0.048, 0.94), 1, Color(PixelUI.CYAN, 0.42))
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	bar_panel.add_theme_stylebox_override("panel", st)
	parent.add_child(bar_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar_panel.add_child(row)
	_passive_title = PixelUI.emphasize(
		PixelUI.label(row, "角色等级被动 // PASSIVES", 17, PixelUI.CYAN), 2, 1)
	_passive_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for spec in [["body_adapt", "机体适应"], ["ops_stipend", "行动津贴"]]:
		var pid := String(spec[0])
		var btn := PixelUI.button(String(spec[1]), 30)
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size.x = 290
		btn.pressed.connect(_toggle_passive.bind(pid))
		row.add_child(btn)
		_passive_buttons[pid] = btn
	var hint := PixelUI.label(row, "Lv.2 起每级 +1% · 可随时关闭做无被动挑战/测试", 15, PixelUI.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _toggle_passive(id: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null or not p.has_method("set_passive_enabled"):
		return
	var next_state := not bool(p.passive_enabled(id))
	p.set_passive_enabled(id, next_state)
	var label := "机体适应" if id == "body_adapt" else "行动津贴"
	_feedback.text = "角色被动「%s」已%s · 开始行动后生效" % [label, "启用" if next_state else "关闭"]
	_feedback.add_theme_color_override("font_color", PixelUI.OK if next_state else PixelUI.AMBER_BRIGHT)
	_refresh()


func _refresh_passives(p: Node) -> void:
	var slv := int(p.skill_level()) if p.has_method("skill_level") else int(p.data.get("skill_level", 1))
	var max_lv := int(p.max_level()) if p.has_method("max_level") else 50
	var pct := maxi(0, slv - 1)
	if _passive_title != null:
		_passive_title.text = "角色等级被动 (Lv.%d/%d)" % [slv, max_lv]
	if _passive_buttons.has("body_adapt"):
		var on := bool(p.passive_enabled("body_adapt")) if p.has_method("passive_enabled") else true
		var btn: Button = _passive_buttons["body_adapt"]
		btn.text = "%s 机体适应  +%d%% 基础生命" % ["[■]" if on else "[□]", pct if on else 0]
		btn.add_theme_color_override("font_color", BRANCH_COLORS["survival"] if on else PixelUI.DIM)
	if _passive_buttons.has("ops_stipend"):
		var on := bool(p.passive_enabled("ops_stipend")) if p.has_method("passive_enabled") else true
		var btn: Button = _passive_buttons["ops_stipend"]
		btn.text = "%s 行动津贴  +%d%% 结算收益" % ["[■]" if on else "[□]", pct if on else 0]
		btn.add_theme_color_override("font_color", PixelUI.GOLD if on else PixelUI.DIM)


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

	_pan_hint = PixelUI.label(bar, "按住自由拖动 / 滚轮探索完整天赋树 ⇄", 19, PixelUI.AMBER_BRIGHT)
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
	var style := PixelUI.panel_style(Color(0.055, 0.075, 0.102, 0.98), 2, PixelUI.AMBER_BRIGHT)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)
	_content.add_child(card)
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 6)
	card.add_child(rows)
	var tag := PixelUI.emphasize(PixelUI.label(rows, "DOLL-01", PixelUI.FS_BODY, PixelUI.AMBER_BRIGHT), 2, 1)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := PixelUI.label(rows, "神经核心", 19, BRANCH_COLORS["scavenge"])
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := PixelUI.label(rows, "生存 · 火力 · 搜刮\n三向分支蔓延", 16, PixelUI.DIM)
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

	var style := PixelUI.panel_style(Color(0.042, 0.058, 0.078, 0.97), 1, Color(accent, 0.45))
	style.border_width_top = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	var unlocked_style := style.duplicate() as StyleBoxFlat
	unlocked_style.bg_color = Color(
		lerpf(0.048, accent.r, 0.10),
		lerpf(0.064, accent.g, 0.10),
		lerpf(0.084, accent.b, 0.10),
		0.98)
	unlocked_style.border_color = Color(accent, 0.85)
	var selected := unlocked_style.duplicate() as StyleBoxFlat
	selected.border_color = accent.lightened(0.30)
	selected.set_border_width_all(2)
	selected.border_width_top = 4
	card.add_theme_stylebox_override("panel", style)
	_content.add_child(card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 5)
	card.add_child(outer)

	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 8)
	outer.add_child(main_row)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 4)
	main_row.add_child(left_col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	left_col.add_child(top)
	var icon := TextureRect.new()
	var path := ICON_ROOT + String(def["icon"]) + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	icon.custom_minimum_size = Vector2(36, 36)
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

	var desc := PixelUI.label(left_col, String(def["desc"]), 15, PixelUI.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	desc.clip_text = true
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 右侧自适应竖向格栅等级条（参考图样式：外框 + 等分水平能量格，自动适配 1~N 级上限）。
	var gauge := TalentLevelGauge.new()
	gauge.custom_minimum_size = Vector2(30, 74)
	gauge.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_row.add_child(gauge)

	var buy := PixelUI.button("强化", 29)
	buy.custom_minimum_size.x = CARD_SIZE.x - 22.0
	buy.add_theme_font_size_override("font_size", 16)
	buy.pressed.connect(_buy.bind(id))
	outer.add_child(buy)

	_cards[id] = {
		"card": card, "level": level, "gauge": gauge, "buy": buy, "accent": accent,
		"style": style, "style_unlocked": unlocked_style, "style_selected": selected,
	}


func open() -> void:
	visible = true
	move_to_front()
	_feedback.text = ""
	_selected = &""
	_confirm_layer.hide()
	var view_h := _tree_area.size.y if (_tree_area != null and _tree_area.size.y > 10.0) else 520.0
	_set_pan(0.0, (view_h - CONTENT_SIZE.y) * 0.5)
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
	var slv := int(p.skill_level()) if p.has_method("skill_level") else int(p.data.get("skill_level", 1))
	var prog: Dictionary = p.xp_progress() if p.has_method("xp_progress") else {}
	var xp_note := "Lv.%d (MAX)" % slv if bool(prog.get("is_max", false)) else "Lv.%d · 距下级 %d/%d" % [
		slv, int(prog.get("in_level", 0)), maxi(1, int(prog.get("needed", 30)))]
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
		PixelUI.bb(xp_note, PixelUI.AMBER_BRIGHT),
		PixelUI.bb(ResourceDB.display_name(&"electronics"), BRANCH_COLORS["firepower"]),
		PixelUI.bb(str(elec), PixelUI.TEXT),
		PixelUI.bb(ResourceDB.display_name(&"energy"), BRANCH_COLORS["survival"]),
		PixelUI.bb(str(ener), PixelUI.TEXT),
		PixelUI.bb(ResourceDB.display_name(&"parts"), BRANCH_COLORS["scavenge"]),
		PixelUI.bb(str(parts), PixelUI.TEXT),
	]
	_refresh_passives(p)
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
		var gauge: TalentLevelGauge = entry["gauge"]
		var buy: Button = entry["buy"]
		var card: PanelContainer = entry["card"]
		var accent: Color = entry["accent"]
		total_levels += level

		level_label.text = "Lv.%d / %d" % [level, maximum]
		level_label.add_theme_color_override(
			"font_color", accent.lightened(0.15) if level > 0 else PixelUI.DIM)
		gauge.configure(level, maximum, accent, prereq_ok)

		buy.disabled = cost < 0 or not prereq_ok \
			or credits < cost or p.material_count(material) < material_cost
		if cost < 0:
			buy.text = "★ 已满级"
		elif not prereq_ok:
			buy.text = "需 %s Lv.1" % _title(prereq)
		else:
			buy.text = "强化 · %d 点 + %s×%d" % [
				cost, ResourceDB.display_name(material).substr(0, 2), material_cost]
		card.modulate = Color(1, 1, 1, 1) if prereq_ok else Color(0.82, 0.85, 0.90, 0.58)
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
		_detail_body.text = "从左侧 DOLL-01 神经核心沿翡翠绿（机体防线）、琥珀橙（火力弹道）、战术青（战地搜刮）三条技能方向蔓延。按住画布可自由拖拽探索，购买后下局生效，重置全额返还。"
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
			return "生命上限 +%d%%（%d，基础 100）" % [level * 15, 100 + level * 15]
		&"move":
			return "移动速度 +%d%%" % (level * 5)
		&"armor":
			return "护甲上限 +%d%%（+%d 耐久）" % [level * 20, level * 20]
		&"dodge_dist":
			var dist := Doll2D.DODGE_DISTANCE_M * (1.0 + float(level) * 0.08)
			return "闪避翻滚距离 +%d%%（%.2f m）" % [level * 8, dist]
		&"dodge_cd":
			var cd := Doll2D.DODGE_COOLDOWN * maxf(0.50, 1.0 - float(level) * 0.08)
			return "闪避翻滚冷却 -%d%%（%.2f s）" % [level * 8, cd]
		&"hearing":
			var meters := HearingIndicator2D.HEARING_METERS * (1.0 + float(level) * HearingIndicator2D.HEARING_TALENT_STEP)
			if level < HearingIndicator2D.ACOUSTIC_UNLOCK_LEVEL:
				return "脚下经典方向环 · 听声距离 +%d%%（%.2f m，Lv.5 解锁声波涟漪）" % [level * 10, meters]
			return "声波涟漪已解锁（默认与脚下环共存）· 听声距离 +%d%%（%.2f m）" % [level * 10, meters]
		&"vision_range":
			var dark_m := VisionFog2D.DARK_RADIUS_METERS * (1.0 + float(level) * VisionFog2D.VISION_RANGE_TALENT_STEP)
			return "主视野与暗视距离 +%d%%（近身暗视 %.2f m）" % [level * 10, dark_m]
		&"vision_angle":
			var clear_deg := minf(VisionFog2D.CLEAR_HALF_DEG + float(level) * VisionFog2D.VISION_ANGLE_TALENT_STEP_DEG, VisionFog2D.MAX_CLEAR_HALF_DEG)
			var total_deg := minf(VisionFog2D.TOTAL_HALF_DEG + float(level) * VisionFog2D.VISION_ANGLE_TALENT_STEP_DEG, VisionFog2D.MAX_TOTAL_HALF_DEG)
			return "清晰半角 %.1f° / 总半角 %.1f°（全角 %.0f°）" % [clear_deg, total_deg, total_deg * 2.0]
		&"gun":
			return "基础散布 -%d%%" % (level * 5)
		&"reload":
			return "换弹时间 -%d%%" % (level * 5)
		&"magazine":
			return "弹匣容量 +%d%%" % (level * 10)
		&"reserve":
			return "备弹上限 +%d%%" % (level * 20)
		&"scavenge":
			return "撤离资源 +%d%%" % (level * 10)
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


## 绘制背景神经网格、三条分支色域氛围带、核心光晕、分支标题与有机贝塞尔枝干。
func _draw_tree_canvas() -> void:
	var c := _content
	var sz := CONTENT_SIZE
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.018, 0.026, 0.97), true)

	# 三条分支柔和色域背景带，清晰区分生存绿 / 火力橙 / 搜刮青区域。
	c.draw_rect(Rect2(0.0, 0.0, sz.x, 472.0), Color(BRANCH_COLORS["survival"], 0.024), true)
	c.draw_rect(Rect2(0.0, 472.0, sz.x, 308.0), Color(BRANCH_COLORS["firepower"], 0.022), true)
	c.draw_rect(Rect2(0.0, 780.0, sz.x, sz.y - 780.0), Color(BRANCH_COLORS["scavenge"], 0.024), true)
	c.draw_line(Vector2(240.0, 472.0), Vector2(sz.x - 40.0, 472.0), Color(0.35, 0.45, 0.55, 0.14), 1.0)
	c.draw_line(Vector2(240.0, 780.0), Vector2(sz.x - 40.0, 780.0), Color(0.35, 0.45, 0.55, 0.14), 1.0)

	# 细微战术坐标网格，增强大画布空间延展感。
	var grid := Color(0.28, 0.42, 0.56, 0.075)
	var x := 48.0
	while x < sz.x:
		c.draw_line(Vector2(x, 0), Vector2(x, sz.y), grid, 1.0)
		x += 72.0
	var y := 48.0
	while y < sz.y:
		c.draw_line(Vector2(0, y), Vector2(sz.x, y), grid, 1.0)
		y += 72.0

	# 核心右侧发散光晕。
	var root_out := ROOT_POS + Vector2(ROOT_SIZE.x, ROOT_SIZE.y * 0.5)
	c.draw_circle(root_out, 74.0, Color(PixelUI.AMBER, 0.05), true, -1.0, true)
	c.draw_circle(root_out, 36.0, Color(PixelUI.AMBER, 0.12), true, -1.0, true)

	# 分支方向标题标签（左侧加短色条）。
	for branch_key in BRANCH_META:
		var meta: Dictionary = BRANCH_META[branch_key]
		var col: Color = BRANCH_COLORS[branch_key]
		var pos: Vector2 = meta["pos"]
		c.draw_rect(Rect2(pos + Vector2(-10.0, 3.0), Vector2(4.0, 16.0)), col, true)
		c.draw_string(PixelUI.FONT, pos + Vector2(0, 17), String(meta["tag"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(col, 0.90))

	# 从核心引出的三条主枝干与节点分叉（平滑三次贝塞尔曲线）。
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
	var dx := maxf((to.x - from.x) * 0.52, 56.0)
	var c1 := from + Vector2(dx, 0.0)
	var c2 := to - Vector2(dx, 0.0)
	const STEPS := 28
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
		_content.draw_polyline(pts, Color(accent, 0.24), 10.0, true)
		_content.draw_polyline(pts, accent.lightened(0.14), 3.2, true)
	elif unlocked:
		_content.draw_polyline(pts, Color(accent, 0.14), 6.5, true)
		_content.draw_polyline(pts, Color(accent, 0.68), 2.3, true)
	else:
		_content.draw_polyline(pts, Color(PixelUI.DIM, 0.30), 1.8, true)
	var dot_col := accent.lightened(0.18) if active else (Color(accent, 0.75) if unlocked else Color(PixelUI.DIM, 0.42))
	_content.draw_circle(from, 4.5, dot_col, true, -1.0, true)
	var arrow := PackedVector2Array([
		to,
		to + Vector2(-10.0, -5.0),
		to + Vector2(-10.0, 5.0),
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
			if event.shift_pressed:
				_set_pan(_content.position.x + 96.0)
			else:
				_set_pan(_content.position.x + 72.0, _content.position.y + 72.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.shift_pressed:
				_set_pan(_content.position.x - 96.0)
			else:
				_set_pan(_content.position.x - 72.0, _content.position.y - 72.0)


func _begin_drag() -> void:
	if _content == null:
		return
	_dragging = true
	_drag_moved = false
	_drag_start = get_global_mouse_position()
	_drag_origin = _content.position


func _end_drag() -> void:
	_dragging = false
	_drag_moved = false


func _set_pan(value: float, value_y := NAN) -> void:
	if _content == null or _tree_area == null:
		return
	var min_x := minf(0.0, _tree_area.size.x - _content.size.x)
	_content.position.x = clampf(value, min_x, 0.0)
	var min_y := minf(0.0, _tree_area.size.y - _content.size.y)
	if not is_nan(value_y):
		_content.position.y = clampf(value_y, min_y, 0.0)
	else:
		_content.position.y = clampf(_content.position.y, min_y, 0.0)
	_refresh_pan_hint()


func _refresh_pan_hint() -> void:
	if _pan_hint == null or _content == null or _tree_area == null:
		return
	_pan_hint.visible = _content.size.x > _tree_area.size.x + 1.0 \
		or _content.size.y > _tree_area.size.y + 1.0


func _input(event: InputEvent) -> void:
	if not visible or not _dragging:
		return
	if event is InputEventMouseMotion:
		var delta := get_global_mouse_position() - _drag_start
		if not _drag_moved and delta.length() < DRAG_THRESHOLD:
			return
		_drag_moved = true
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
