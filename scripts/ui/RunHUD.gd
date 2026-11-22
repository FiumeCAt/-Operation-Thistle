extends CanvasLayer
## 正式行动 HUD：头像 / 目标 / 生命 / 体力 / 支援 / 交互提示，像素风切角面板。

const AVATAR_NORMAL: Texture2D = preload("res://assets/art/ui/portraits/avatar_normal.png")
const AVATAR_HURT: Texture2D = preload("res://assets/art/ui/portraits/avatar_hurt.png")
const AVATAR_CRITICAL: Texture2D = preload("res://assets/art/ui/portraits/avatar_critical.png")

var main: Node3D
var _root: Control
var _status: Label
var _meta: Label
var _meta_row: HBoxContainer
var _hint: Label
var _result: PanelContainer
var _summary: Label
var _restart: Button
var _health: SegmentBar
var _health_value: Label
var _stamina: SegmentBar
var _stamina_value: Label
var _avatar: TextureRect
var _avatar_state := ""
var _avatar_panel: PixelUI.PixelPanel
var _status_panel: PixelUI.PixelPanel
var _support: Label
var _heal_support: Label
var _top_panel: PixelUI.PixelPanel
var _map: Control
var _hint_timer := 0.0
var _hints_visible := true
var _objective_timer := 0.0
var _objective_visible := true
var _shaft: PanelContainer
var _growth_panel: PanelContainer
var _growth_title: Label
var _growth_summary: Label
var _growth_content: VBoxContainer
var _growth_is_talent := false
var _extract: Button
var _continue_button: Button
var _continue_hint: Label
var _at_base := false
var _loot: Label
var _loot_time := 0.0
var _base_panel: PanelContainer
var _base_summary: Label
var _start: Button
var _upgrade: Button
var _loadout: Button

const ICON_ROOT := "res://assets/art/ui/talents/"

func show_loot(text: String) -> void:
	_loot.text = text
	_loot_time = 3.5
	_loot.show()
	_fit_objective()

func show_shaft() -> void:
	_extract.disabled = main.resources < 1
	_continue_button.text = "继续下潜" if main.depth < main.MAX_DEPTH else "第五层完成 · 撤离"
	_continue_hint.visible = main.depth >= main.MAX_DEPTH
	_shaft.show()
	_shaft.move_to_front()

func hide_shaft() -> void:
	_shaft.hide()

func _return_or_start() -> void:
	if _at_base:
		main.start_expedition()
	else:
		main.return_to_base()
		_base_summary.text = "前沿基地 · 行动结算完成\n本次行动带出资源：%d" % main.extracted_resources
		_restart.text = "返回基地"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelUI.apply_theme(_root)
	_build_avatar_panel()
	_build_objective_panel()
	_build_status_panel()
	_build_result_panel()
	_build_base_panel()
	_build_growth_panel()
	_build_shaft_panel()

## 左上角头像框：随生命百分比切换表情
func _build_avatar_panel() -> void:
	var panel := PixelUI.panel()
	_avatar_panel = panel
	_root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24
	panel.offset_top = 20
	panel.offset_right = 200
	panel.offset_bottom = 216
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 8

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	_avatar = TextureRect.new()
	_avatar.texture = AVATAR_NORMAL
	_avatar.custom_minimum_size = Vector2(152, 152)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rows.add_child(_avatar)
	var name_label := PixelUI.label(rows, "DOLL-01", PixelUI.FS_BODY, PixelUI.AMBER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_state = "normal"

func _build_objective_panel() -> void:
	var top := PixelUI.panel()
	_top_panel = top
	_root.add_child(top)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 212
	top.offset_top = 20
	top.offset_right = 672
	top.offset_bottom = 260
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	top.add_child(rows)

	PixelUI.label(rows, "目标 // OBJECTIVE", PixelUI.FS_BODY, PixelUI.AMBER)
	_status = PixelUI.label(rows, "", PixelUI.FS_TITLE, PixelUI.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	rows.add_child(meta_row)
	_meta_row = meta_row
	PixelUI.icon(meta_row, "resources", 26)
	_meta = PixelUI.label(meta_row, "", PixelUI.FS_BODY, PixelUI.DIM)
	_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_loot = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.OK)
	_loot.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_loot.hide()

## 左下：生命值 + 体力 + 支援合并成一个状态面板
func _build_status_panel() -> void:
	var panel := PixelUI.panel()
	_status_panel = panel
	_root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 24
	panel.offset_top = -252
	panel.offset_right = 444
	panel.offset_bottom = -20
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)

	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 8)
	rows.add_child(health_row)
	PixelUI.icon(health_row, "repair", 26)
	var hp_title := PixelUI.label(health_row, "生命", PixelUI.FS_BODY, PixelUI.DIM)
	hp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_value = PixelUI.label(health_row, "-- / --", PixelUI.FS_BODY, PixelUI.TEXT)
	_health_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_health = SegmentBar.new()
	_health.segments = 20
	_health.color_low = PixelUI.HP_LOW
	_health.color_high = PixelUI.HP_HIGH
	_health.custom_minimum_size.y = 20
	rows.add_child(_health)

	var stamina_row := HBoxContainer.new()
	stamina_row.add_theme_constant_override("separation", 8)
	rows.add_child(stamina_row)
	PixelUI.icon(stamina_row, "stamina", 26)
	var stam_title := PixelUI.label(stamina_row, "体力", PixelUI.FS_BODY, PixelUI.DIM)
	stam_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamina_value = PixelUI.label(stamina_row, "-- / --", PixelUI.FS_BODY, PixelUI.TEXT)
	_stamina_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stamina = SegmentBar.new()
	_stamina.segments = 20
	_stamina.color_low = PixelUI.STAM_LOW
	_stamina.color_high = PixelUI.STAM_HIGH
	_stamina.custom_minimum_size.y = 20
	_stamina.ratio = 1.0
	rows.add_child(_stamina)

	var support_row := HBoxContainer.new()
	support_row.add_theme_constant_override("separation", 8)
	rows.add_child(support_row)
	PixelUI.icon(support_row, "support", 26)
	_support = PixelUI.label(support_row, "", PixelUI.FS_BODY, PixelUI.DIM)
	_support.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var heal_row := HBoxContainer.new()
	heal_row.add_theme_constant_override("separation", 8)
	rows.add_child(heal_row)
	PixelUI.icon(heal_row, "repair", 26)
	_heal_support = PixelUI.label(heal_row, "", PixelUI.FS_BODY, PixelUI.DIM)
	_heal_support.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

func _fit_objective() -> void:
	if _top_panel:
		_top_panel.size = Vector2(460, _top_panel.get_combined_minimum_size().y)
		_top_panel.visible = _objective_visible

func _build_result_panel() -> void:
	_result = PixelUI.panel()
	_root.add_child(_result)
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result.offset_left = -380
	_result.offset_right = 380
	_result.offset_top = -260
	_result.offset_bottom = 260
	var result_rows := VBoxContainer.new()
	result_rows.add_theme_constant_override("separation", 32)
	_result.add_child(result_rows)
	_summary = PixelUI.label(result_rows, "", PixelUI.FS_BODY, PixelUI.TEXT)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_restart = PixelUI.button("返回前沿基地", 60)
	_restart.pressed.connect(_return_or_start)
	result_rows.add_child(_restart)
	_result.hide()

func _build_base_panel() -> void:
	_base_panel = PixelUI.panel()
	_root.add_child(_base_panel)
	_base_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_base_panel.offset_left = 60
	_base_panel.offset_right = 840
	_base_panel.offset_top = -250
	_base_panel.offset_bottom = 250
	var base_rows := VBoxContainer.new()
	base_rows.add_theme_constant_override("separation", 10)
	_base_panel.add_child(base_rows)
	PixelUI.label(base_rows, "前沿基地 // STAGING", PixelUI.FS_TITLE, PixelUI.AMBER)
	_base_summary = PixelUI.label(base_rows, "", PixelUI.FS_BODY, PixelUI.TEXT)
	_base_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	base_rows.add_child(divider)
	_start = PixelUI.button("出发 · 新远征", 60)
	_start.pressed.connect(func() -> void: main.start_expedition())
	base_rows.add_child(_start)
	_upgrade = PixelUI.button("购买维修升级（10 资源起）", 56)
	_upgrade.pressed.connect(_buy_upgrade)
	base_rows.add_child(_upgrade)
	_loadout = PixelUI.button("切换配装：下一把武器 / 对应弹种", 56)
	_loadout.pressed.connect(_cycle_loadout)
	base_rows.add_child(_loadout)
	var skill_tree := PixelUI.button("技能树 // 查看成长路线", 56)
	skill_tree.pressed.connect(func() -> void: _show_growth(false))
	base_rows.add_child(skill_tree)
	var talent_tree := PixelUI.button("天赋树 // 查看战术天赋", 56)
	talent_tree.pressed.connect(func() -> void: _show_growth(true))
	base_rows.add_child(talent_tree)
	_base_panel.hide()

func _build_shaft_panel() -> void:
	_shaft = PixelUI.panel()
	_root.add_child(_shaft)
	_shaft.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_shaft.offset_left = -440
	_shaft.offset_right = 440
	_shaft.offset_top = -220
	_shaft.offset_bottom = 220
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	_shaft.add_child(choices)
	PixelUI.label(choices, "竖井 // SHAFT", PixelUI.FS_TITLE, PixelUI.AMBER)
	var info := PixelUI.label(choices, "决策期间暂停\n下潜：敌人 HP ×1.10 / 伤害 ×1.05\n资源 ×1.05（小数累计），不回血、不结算", PixelUI.FS_BODY, PixelUI.DIM)
	_continue_hint = PixelUI.label(choices, "", PixelUI.FS_BODY, PixelUI.AMBER)
	_continue_hint.visible = false
	for text in ["撤离（至少1份资源）", "继续下潜", "取消"]:
		var button := PixelUI.button(text, 60)
		choices.add_child(button)
		match text:
			"撤离（至少1份资源）":
				_extract = button
				button.pressed.connect(func() -> void: main.extract_from_shaft())
			"继续下潜":
				_continue_button = button
				button.pressed.connect(func() -> void:
					if main.depth < main.MAX_DEPTH:
						main.descend()
					else:
						main.extract_from_shaft()
				)
			"取消":
				button.pressed.connect(func() -> void: main.cancel_shaft())
	_shaft.hide()

func setup(run: Node3D) -> void:
	main = run
	if main.in_base:
		show_base()
	else:
		show_expedition()
	var map := preload("res://scripts/ui/RunMap.gd").new()
	map.main = main
	map.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map.offset_left = -234
	map.offset_top = 20
	map.offset_right = -24
	map.offset_bottom = 230
	_root.add_child(map)
	_map = map
	map.visible = not main.in_base
	_refresh()

## 像素字体不做自动换行（会撑坏容器高度），按字数硬折行
func _wrap(text: String, per_line := 24) -> String:
	var out := ""
	for raw in text.split("\n"):
		var line := ""
		var count := 0
		for ch in raw:
			line += ch
			count += 1
			if count >= per_line:
				out += line + "\n"
				line = ""
				count = 0
		out += line + "\n"
	return out.trim_suffix("\n")

func _build_growth_panel() -> void:
	_growth_panel = PixelUI.panel()
	_root.add_child(_growth_panel)
	_growth_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_growth_panel.offset_left = -590
	_growth_panel.offset_right = 590
	_growth_panel.offset_top = -400
	_growth_panel.offset_bottom = 400
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	_growth_panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_growth_title = PixelUI.label(header, "技能成长", PixelUI.FS_TITLE, PixelUI.AMBER)
	_growth_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_growth_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var close := PixelUI.button("返回基地", 52)
	close.custom_minimum_size.x = 160
	close.pressed.connect(_close_growth)
	header.add_child(close)
	_growth_summary = PixelUI.label(layout, "", PixelUI.FS_BODY, PixelUI.DIM)
	_growth_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	layout.add_child(divider)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_growth_content = VBoxContainer.new()
	_growth_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_growth_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_growth_content)
	_growth_panel.hide()

func _show_growth(talents: bool) -> void:
	if not _at_base:
		return
	_growth_is_talent = talents
	_base_panel.hide()
	_result.hide()
	_growth_panel.show()
	_growth_panel.move_to_front()
	var progress := get_node_or_null("/root/Progress")
	var data: Dictionary = progress.data if progress else {}
	var xp := int(data.get("xp", 0))
	var level := int(data.get("skill_level", 1))
	var upgrades: Dictionary = data.get("upgrades", {})
	var resources := int(data.get("resources", 0))
	_growth_title.text = "战术天赋" if talents else "技能成长路线"
	_growth_summary.text = "XP %d    技能等级 Lv.%d    距下一等级 %d / 20 XP    可用信用点 %d" % [xp, level, xp % 20, resources]
	for child in _growth_content.get_children():
		_growth_content.remove_child(child)
		child.queue_free()
	if talents:
		_add_growth_row("hp_boost", "生命强化", "生命上限 +15 / 级，最高 5 级。", "Lv.%d / %d" % [int(upgrades.get("hp", 0)), 5], &"")
		_add_growth_row("support_protocol", "支援协议", "狙击支援次数 = 2 + 等级，最高 2 级。", "Lv.%d / %d" % [int(upgrades.get("support", 0)), 2], &"")
		_add_growth_row("recoil_control", "枪械精度", "基础散布每级 -6%，最高 3 级。", "Lv.%d / %d" % [int(upgrades.get("gun", 0)), 3], &"")
		_add_growth_row("recon", "视野角度", "视野总角每级 +2.5°，最高 4 级。", "Lv.%d / %d" % [int(upgrades.get("fov", 0)), 4], &"")
		_add_growth_row("scavenger", "视野范围", "视距每级 +0.5m，最高 4 级。", "Lv.%d / %d" % [int(upgrades.get("sight", 0)), 4], &"")
		_add_growth_row("ammo_carry", "扩容携行", "提升携弹能力。", "规划中 · 效果未实现", &"")
		_add_growth_row("armor_pierce", "穿甲弹道", "强化穿透作战能力。", "规划中 · 效果未实现", &"")
		_add_growth_row("pump_speed", "快速泵动", "缩短泵动与装填时间。", "规划中 · 效果未实现", &"")
	else:
		_add_growth_row("hp_boost", "生命强化", "生命上限 +15 / 级，最高 5 级；购买消耗资源并获得 5 XP。", "Lv.%d / %d" % [int(upgrades.get("hp", 0)), 5], &"hp")
		_add_growth_row("support_protocol", "支援协议", "每级 +1 次狙击支援，最高 2 级；伤害 80 与 8 秒冷却不变。", "Lv.%d / %d" % [int(upgrades.get("support", 0)), 2], &"support")
		_add_growth_row("recoil_control", "枪械精度", "每级基础散布 -6%，最高 3 级；不改变伤害与射速。", "Lv.%d / %d" % [int(upgrades.get("gun", 0)), 3], &"gun")
		_add_growth_row("recon", "视野角度", "每级视野总角 +2.5°（清晰区按比例同步扩张），最高 4 级。", "Lv.%d / %d" % [int(upgrades.get("fov", 0)), 4], &"fov")
		_add_growth_row("scavenger", "视野范围", "每级视距 +0.5m，最高 4 级；只扩大可见距离。", "Lv.%d / %d" % [int(upgrades.get("sight", 0)), 4], &"sight")
		_add_growth_row("ammo_carry", "扩容携行", "未开放。", "锁定 · 效果未实现", &"")
		_add_growth_row("armor_pierce", "穿甲弹道", "未开放。", "锁定 · 效果未实现", &"")
		_add_growth_row("pump_speed", "快速泵动", "未开放。", "锁定 · 效果未实现", &"")

func _add_growth_row(icon_name: String, title: String, detail: String, state: String, purchase_id: StringName = &"") -> void:
	var row := PanelContainer.new()
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.45))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)
	_growth_content.add_child(row)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	row.add_child(content)
	var icon := TextureRect.new()
	var path := ICON_ROOT + icon_name + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content.add_child(icon)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(labels)
	var title_label := PixelUI.label(labels, title, PixelUI.FS_BODY, PixelUI.AMBER)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var detail_label := PixelUI.label(labels, _wrap(detail, 22), PixelUI.FS_BODY, PixelUI.DIM)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var state_label := PixelUI.label(content, state, PixelUI.FS_BODY, PixelUI.TEXT)
	state_label.custom_minimum_size.x = 300
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if purchase_id != &"":
		var progress := get_node_or_null("/root/Progress")
		var cost: int = progress.upgrade_cost(purchase_id) if progress else -1
		var buy := PixelUI.button("已满级" if cost < 0 else "强化 · %d" % cost, 52)
		buy.custom_minimum_size.x = 180
		buy.disabled = progress == null or cost < 0 or int(progress.data.get("resources", 0)) < cost
		buy.pressed.connect(func() -> void: _buy_growth(purchase_id))
		content.add_child(buy)

func _close_growth() -> void:
	_growth_panel.hide()
	if _at_base:
		_base_panel.show()
		_base_panel.move_to_front()

func _process(dt: float) -> void:
	_loot_time = maxf(0.0, _loot_time - dt)
	var was_loot := _loot.visible
	_loot.visible = _loot_time > 0.0
	if was_loot != _loot.visible:
		_fit_objective()
	if main != null:
		_refresh()
		if not _at_base and _hints_visible and _hint_timer > 0.0:
			_hint_timer -= dt
			if _hint_timer <= 0.0:
				_set_hints(false)
		if not _at_base and _objective_visible and _objective_timer > 0.0:
			_objective_timer -= dt
			if _objective_timer <= 0.0:
				_set_objective(false)

## F1 精简底部操作提示；TAB 收起/展开左上目标
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			_set_hints(not _hints_visible)
		KEY_TAB:
			if not _at_base:
				_set_objective(not _objective_visible)

func _set_hints(on: bool) -> void:
	_hints_visible = on
	_hint_timer = 0.0
	if main != null and main.hud != null:
		main.hud.set_hint_visible(on)

func _set_objective(on: bool) -> void:
	_objective_visible = on
	_objective_timer = 0.0
	if _top_panel:
		_top_panel.visible = on

func show_base() -> void:
	_at_base = true
	_result.hide()
	_shaft.hide()
	_growth_panel.hide()
	_status_panel.hide()
	_objective_visible = true
	_objective_timer = 0.0
	if _meta_row:
		_meta_row.hide()
	_base_panel.show()
	_status.text = "前沿基地 // 行动整备"
	_hint.text = "配置装备、查看成长路线，然后出发"
	_health_value.visible = false
	_fit_objective()
	if _map:
		_map.hide()
	var progress := get_node_or_null("/root/Progress")
	if progress:
		var upgrades: Dictionary = progress.data.get("upgrades", {})
		_base_summary.text = "资源 %d    XP %d    技能等级 Lv.%d\n生命 Lv.%d/%d    枪械 Lv.%d/%d    支援 Lv.%d/%d\n视野角度 Lv.%d/%d    视野范围 Lv.%d/%d\n当前配装：%s / %s" % [
			progress.data["resources"], progress.data["xp"], progress.data["skill_level"],
			int(upgrades.get("hp", 0)), progress.upgrade_max(&"hp"),
			int(upgrades.get("gun", 0)), progress.upgrade_max(&"gun"),
			int(upgrades.get("support", 0)), progress.upgrade_max(&"support"),
			int(upgrades.get("fov", 0)), progress.upgrade_max(&"fov"),
			int(upgrades.get("sight", 0)), progress.upgrade_max(&"sight"),
			progress.data["loadout"]["weapon"], progress.data["loadout"]["ammo"]]
		_refresh_base_upgrade_button()
	_base_panel.move_to_front()

## 基地快捷按钮只负责生命强化，文案与可购买状态跟随等级和资源变化。
func _refresh_base_upgrade_button() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null or _upgrade == null:
		return
	var cost: int = progress.upgrade_cost(&"hp")
	if cost < 0:
		_upgrade.text = "生命强化已满级"
		_upgrade.disabled = true
		return
	_upgrade.text = "购买生命强化（%d 资源）" % cost
	_upgrade.disabled = int(progress.data.get("resources", 0)) < cost

func show_expedition() -> void:
	_at_base = false
	_base_panel.hide()
	_growth_panel.hide()
	_result.hide()
	_status_panel.show()
	_objective_visible = true
	_objective_timer = 9.0
	if _meta_row:
		_meta_row.show()
	_hint.show()
	if _map:
		_map.show()
	_restart.text = "返回前沿基地"
	_set_hints(true)
	_hint_timer = 10.0
	_fit_objective()

func _cycle_loadout() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	var current := StringName(progress.data["loadout"].get("weapon", "m870"))
	var idx := WeaponDB.WEAPON_ORDER.find(current)
	var next: StringName = WeaponDB.WEAPON_ORDER[(idx + 1) % WeaponDB.WEAPON_ORDER.size()]
	var ammo: StringName = &"9mm" if next == &"g17" else &"buckshot"
	progress.set_loadout(next, ammo)
	show_base()

func _buy_upgrade() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress and progress.buy_upgrade(&"hp"):
		main._apply_persistent_upgrades()
		show_base()

func _buy_growth(id: StringName) -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null or not progress.buy_upgrade(id):
		return
	main._apply_persistent_upgrades()
	_refresh_base_upgrade_button()
	_show_growth(_growth_is_talent)

func _refresh() -> void:
	if main.in_base:
		return
	var hp_ratio := clampf(main.doll.hp / maxf(1.0, main.doll.hp_max), 0.0, 1.0)
	_health.set_ratio(hp_ratio)
	_health.visible = not main.doll.is_dead
	_health_value.visible = _health.visible
	_health_value.text = "%d / %d" % [roundi(main.doll.hp), roundi(main.doll.hp_max)]
	_update_avatar(hp_ratio)

	var stam_max := maxf(1.0, main.doll.stamina_max)
	var stam_ratio := clampf(main.doll.stamina / stam_max, 0.0, 1.0)
	_stamina.set_ratio(stam_ratio)
	# 体力只显示具体数值；回满时不再附带状态文字
	var sprinting: bool = Input.is_action_pressed("sprint") and main.doll.get_speed() > main.doll.walk_speed * 0.6
	var stam_text := "%d / %d" % [roundi(main.doll.stamina), roundi(stam_max)]
	if sprinting:
		stam_text += " · 冲刺"
	elif stam_ratio < 0.999:
		stam_text += " · 恢复"
	_stamina_value.text = stam_text

	_status.text = "搜索物资并抵达撤离井"
	_meta.text = "深度 %02d · 区段 %02d · 资源 %03d" % [main.depth, main.level.seg_count, main.resources]
	var hint_text := _wrap(main.interaction_hint, 17) + "\nT 手电：" + ("开 · 更易被发现" if main.doll.flashlight_on else "关")
	if hint_text != _hint.text:
		_hint.text = hint_text
		_fit_objective()
	var sniper_state := ("冷却 %.1fs" % main.support_cooldown) if main.support_cooldown > 0.0 else ("可用" if main.support_uses < main.support_max_uses() else "耗尽")
	_support.text = "X 狙击 // %s    次数 %d/%d" % [sniper_state, main.support_uses, main.support_max_uses()]
	var heal_state := ("冷却 %.1fs" % main.heal_cooldown) if main.heal_cooldown > 0.0 else ("就绪" if main.doll.hp < main.doll.hp_max else "满血")
	_heal_support.text = "H 恢复 // %s · 可重复" % heal_state

## 按生命百分比切换头像表情：>60% 正常，30%~60% 受伤，<30% 濒危
func _update_avatar(hp_ratio: float) -> void:
	var state := "critical" if hp_ratio < 0.3 else ("hurt" if hp_ratio < 0.6 else "normal")
	if state == _avatar_state:
		return
	_avatar_state = state
	match state:
		"critical":
			_avatar.texture = AVATAR_CRITICAL
		"hurt":
			_avatar.texture = AVATAR_HURT
		_:
			_avatar.texture = AVATAR_NORMAL

func show_result(success: bool, collected: int, extracted: int, duration: float) -> void:
	_summary.text = "%s\n\n搜集：%d    带出：%d\n耗时：%.1f秒" % ["撤离成功" if success else "行动失败", collected, extracted, duration]
	_result.show()
	_restart.grab_focus()
	_refresh()
