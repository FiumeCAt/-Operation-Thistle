extends CanvasLayer
class_name RunHUD2D

## 2D 行动 HUD：左下角一块紧凑状态板（生命 / 资源 / 目标），
## 操作提示贴左上，右下武器面板，居中结算。
## 头像已移除；面板底图由 image2.5 生成，替代原先的大面积纯色黑框。

const PLATE_TEX: Texture2D = preload("res://assets/art/ui/hud/status_plate.png")
const WEAPON_PLATE_TEX: Texture2D = preload("res://assets/art/ui/hud/weapon_plate.png")
## 状态板贴左下角：生命条在屏幕左下，避开主要视野。
const PLATE_POS := Vector2(20, -148)
const PLATE_SIZE := Vector2(560, 132)
const WEAPON_PLATE_SIZE := Vector2(360, 150)

## 右上角小地图：只显示玩家附近敌情，目标点常显。
signal return_requested
signal restart_requested

## 拾取信息在屏幕左侧滚动显示，不占左下状态板。
const FEED_LIFE := 3.4
const FEED_MAX := 6

var main: Node2D

var hp_label: Label
var objective_label: Label
var hint_label: Label
## 左上交互目标：靠近可搜刮容器时显示名称，并用容器稀有度着色。
var interact_label: Label
var result_label: Label
var result_detail: Label
var ammo_label: Label
var return_button: Button
var restart_button: Button
var armor_label: Label
## 结算界面的带出物资数量标签（资源 id → Label）与战斗统计（键 → Label）。
var debrief_loot_labels := {}
var debrief_stat_labels := {}

var _root: Control
var _minimap: Minimap2D
var _health: SegmentBar
var _armor_bar: SegmentBar
var _title: Label
var _ammo_name: Label
var _reserve: Label
var _count: Label
var _state: Label
var _progress: ProgressBar
var _strip: ShellStrip2D
var _result_panel: PanelContainer
var _debrief_empty: Label
var _feed: VBoxContainer
var _feed_items: Array[Dictionary] = []
var _flash_t := 0.0
var _hp_critical := false
var _armor_broken := false


func setup(run: Node2D) -> void:
	main = run
	if _minimap != null:
		_minimap.setup(run)


func _ready() -> void:
	layer = 40
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelUI.apply_theme(_root)
	_build_status_plate()
	_build_hint()
	_build_pickup_feed()
	_build_weapon_panel()
	_build_minimap()
	_build_result_panel()


func _build_minimap() -> void:
	_minimap = Minimap2D.new()
	_root.add_child(_minimap)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -344
	_minimap.offset_right = -24
	_minimap.offset_top = 20
	_minimap.offset_bottom = 244


## 左下：生成式金属板 + 两行信息（生命/资源、目标），不再放头像。
func _build_status_plate() -> void:
	var plate := TextureRect.new()
	plate.texture = PLATE_TEX
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(plate)
	plate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	plate.offset_left = PLATE_POS.x
	plate.offset_top = PLATE_POS.y
	plate.offset_right = PLATE_POS.x + PLATE_SIZE.x
	plate.offset_bottom = PLATE_POS.y + PLATE_SIZE.y

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	plate.add_child(margin)

	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	rows.add_child(top_row)
	_health = SegmentBar.new()
	_health.segments = 18
	_health.color_low = PixelUI.HP_LOW
	_health.color_high = PixelUI.HP_HIGH
	_health.custom_minimum_size.y = 20
	_health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_health)
	hp_label = PixelUI.label(top_row, "-- / --", PixelUI.FS_BODY, PixelUI.TEXT)
	hp_label.custom_minimum_size.x = 96
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var armor_row := HBoxContainer.new()
	armor_row.add_theme_constant_override("separation", 10)
	rows.add_child(armor_row)
	_armor_bar = SegmentBar.new()
	_armor_bar.segments = 18
	_armor_bar.color_low = Color(0.32, 0.52, 0.82)
	_armor_bar.color_high = Color(0.48, 0.82, 1.0)
	_armor_bar.custom_minimum_size.y = 12
	_armor_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armor_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	armor_row.add_child(_armor_bar)
	armor_label = PixelUI.label(armor_row, "护甲 --", PixelUI.FS_BODY, PixelUI.DIM)
	armor_label.custom_minimum_size.x = 96
	armor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	armor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	objective_label = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.TEXT)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	objective_label.clip_text = true


## 操作提示：贴屏幕左上，只留一行，带描边保证在亮地面也可读。
func _build_hint() -> void:
	hint_label = PixelUI.label(_root, "", 20, PixelUI.DIM)
	hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint_label.offset_left = 28
	hint_label.offset_right = 1240
	hint_label.offset_top = 18
	hint_label.offset_bottom = 50
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.clip_text = true
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.88))

	interact_label = PixelUI.label(_root, "", 22, PixelUI.TEXT)
	interact_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	interact_label.offset_left = 28
	interact_label.offset_right = 1240
	interact_label.offset_top = 52
	interact_label.offset_bottom = 86
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	interact_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interact_label.clip_text = true
	interact_label.add_theme_constant_override("outline_size", 6)
	interact_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.88))
	interact_label.hide()


## 左侧拾取信息流：底部对齐，新消息从下方出现，旧消息上移并淡出。
func _build_pickup_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 2)
	_feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_feed.offset_left = 28
	_feed.offset_right = 560
	_feed.offset_top = -560
	_feed.offset_bottom = -166
	_root.add_child(_feed)


## 拾取反馈：不打断底部操作提示，只往左侧信息流追加一行。
func push_pickup(text: String, color: Color) -> void:
	if _feed == null:
		return
	var line := PixelUI.label(_feed, text, PixelUI.FS_BODY, color)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.add_theme_constant_override("outline_size", 6)
	line.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.03, 0.9))
	_feed_items.append({"label": line, "t": FEED_LIFE})
	while _feed_items.size() > FEED_MAX:
		var old: Dictionary = _feed_items.pop_front()
		var old_label = old["label"]
		if is_instance_valid(old_label):
			old_label.queue_free()


## 右下：枪名 / 弹匣 / 备弹 / 状态 / 换弹进度，共用生成式金属底板。
func _build_weapon_panel() -> void:
	var plate := TextureRect.new()
	plate.texture = WEAPON_PLATE_TEX
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(plate)
	plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	plate.offset_left = -24 - WEAPON_PLATE_SIZE.x
	plate.offset_top = -24 - WEAPON_PLATE_SIZE.y
	plate.offset_right = -24
	plate.offset_bottom = -24

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	plate.add_child(margin)

	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 4)
	margin.add_child(rows)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	rows.add_child(title_row)
	_title = PixelUI.label(title_row, "G17 // 9MM", PixelUI.FS_BODY, PixelUI.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state = PixelUI.label(title_row, "就绪", PixelUI.FS_BODY, PixelUI.AMBER)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 10)
	rows.add_child(count_row)
	_count = PixelUI.label(count_row, "-- / --", PixelUI.FS_TITLE, PixelUI.TEXT)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ammo_label = _count
	_reserve = PixelUI.label(count_row, "备弹 --", PixelUI.FS_BODY, PixelUI.DIM)
	_reserve.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 10)
	rows.add_child(strip_row)
	_strip = ShellStrip2D.new()
	_strip.custom_minimum_size = Vector2(150, 16)
	_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(_strip)
	_ammo_name = PixelUI.label(strip_row, "9mm", PixelUI.FS_BODY, PixelUI.AMBER)
	_ammo_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ammo_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_progress = PixelUI.bar(6)
	_progress.max_value = 100
	_progress.value = 0
	rows.add_child(_progress)


## 结算界面：结构与 TAB 背包一致（左右分栏），但只展示本局带出的物资与战斗统计。
func _build_result_panel() -> void:
	_result_panel = PixelUI.panel()
	_root.add_child(_result_panel)
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.offset_left = -550
	_result_panel.offset_right = 550
	_result_panel.offset_top = -322
	_result_panel.offset_bottom = 322
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_result_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "行动结算 // DEBRIEF", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "SESSION K-17", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	result_label = PixelUI.label(rows, "", PixelUI.FS_TITLE, PixelUI.TEXT)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	columns.add_child(_build_debrief_loot())
	columns.add_child(_build_debrief_stats())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(buttons)
	return_button = PixelUI.button("返回基地", 46)
	return_button.custom_minimum_size.x = 260
	return_button.pressed.connect(func() -> void: return_requested.emit())
	buttons.add_child(return_button)
	restart_button = PixelUI.button("重新开始", 46)
	restart_button.custom_minimum_size.x = 260
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	buttons.add_child(restart_button)

	var tip := PixelUI.label(rows, "按 R 重新开始 · ESC 返回基地", PixelUI.FS_BODY, PixelUI.DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.hide()
	result_label.hide()
	result_detail.hide()
	return_button.hide()
	restart_button.hide()


## 左栏：带出物资，逐行显示图标 + 全名 + 数量；数量为 0 的行隐藏。
func _build_debrief_loot() -> Control:
	var panel := _debrief_column()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	PixelUI.label(rows, "带出物资 // EXTRACTED", PixelUI.FS_BODY, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	for id in ResourceDB.BASIC:
		_debrief_loot_row(rows, id)
	PixelUI.label(rows, "进阶 // RARE", 20, PixelUI.DIM)
	for id in ResourceDB.ADVANCED:
		_debrief_loot_row(rows, id)
	_debrief_empty = PixelUI.label(rows, "空手而归", PixelUI.FS_BODY, PixelUI.DIM)
	_debrief_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _debrief_loot_row(parent: Node, id: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	PixelUI.icon(row, "res_" + String(id), 26)
	var name_label := PixelUI.label(row, ResourceDB.display_name(id), 20, PixelUI.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := PixelUI.label(row, "×0", 20, PixelUI.DIM)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debrief_loot_labels[String(id)] = {"row": row, "count": count}


## 右栏：战斗统计。
func _build_debrief_stats() -> Control:
	var panel := _debrief_column()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	PixelUI.label(rows, "战斗统计 // COMBAT", PixelUI.FS_BODY, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	var stats := [
		["kills", "击杀敌人"], ["damage", "造成伤害"],
		["accuracy", "命中率"], ["shots", "射击次数"], ["time", "行动用时"],
	]
	for entry in stats:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var name_label := PixelUI.label(row, String(entry[1]), 20, PixelUI.DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := PixelUI.label(row, "-", 20, PixelUI.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		debrief_stat_labels[String(entry[0])] = value
	return panel


func _debrief_column() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func set_hp(current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / maxf(1.0, float(maximum)), 0.0, 1.0)
	_health.set_ratio(ratio)
	hp_label.text = "%d / %d" % [current, maximum]
	var critical := ratio < 0.3
	if critical != _hp_critical:
		_hp_critical = critical
		hp_label.add_theme_color_override(
			"font_color", PixelUI.DANGER if critical else PixelUI.TEXT)


func set_armor(current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / maxf(1.0, float(maximum)), 0.0, 1.0)
	_armor_bar.set_ratio(ratio)
	armor_label.text = "护甲 %d" % current
	var broken := current <= 0
	if broken != _armor_broken:
		_armor_broken = broken
		armor_label.add_theme_color_override(
			"font_color", PixelUI.DANGER if broken else PixelUI.TEXT)


func set_objective(text: String) -> void:
	objective_label.text = text


func set_hint(text: String) -> void:
	hint_label.text = text


## 左上角交互目标：显示可搜刮容器名字，并按稀有度着色。
func set_interact_target(text: String, color: Color) -> void:
	if interact_label == null:
		return
	interact_label.text = text
	interact_label.add_theme_color_override("font_color", color)
	interact_label.show()


func clear_interact_target() -> void:
	if interact_label != null:
		interact_label.hide()


## 拾取/交互提示：底部提示临时变成绿色，2.2 秒后恢复。
func flash(text: String) -> void:
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", PixelUI.OK)
	_flash_t = 2.2


func update_weapon(rig) -> void:
	if rig == null or rig.data == null:
		_title.text = "未装备武器"
		_ammo_name.text = ""
		_reserve.text = ""
		_count.text = "--"
		_state.text = ""
		_strip.mag = 0
		_strip.cap = 0
		_strip.queue_redraw()
		_progress.value = 0.0
		return
	var data = rig.data
	var ammo: AmmoData = WeaponDB.ammo_table().get(data.ammo_id)
	var short_name: String = String(data.display_name).split(" // ")[0]
	_title.text = "%s // %s" % [short_name, data.caliber_label]
	if ammo != null:
		_ammo_name.text = ammo.short_name
		_ammo_name.add_theme_color_override("font_color", ammo.color)
	_reserve.text = "备弹 %d" % rig.get_reserve()
	_count.text = "%d / %d" % [rig.mag, data.mag_capacity]
	_strip.cap = data.mag_capacity
	_strip.mag = rig.mag
	_strip.queue_redraw()
	var reloading: bool = rig.reload_t > 0.0
	var switching: bool = rig.switch_t > 0.0
	var state_color := PixelUI.AMBER
	if rig.is_drawing():
		_state.text = "拔枪中"
	elif rig.is_stowing():
		_state.text = "收枪中"
	elif rig.is_holstered():
		_state.text = "已收枪"
		state_color = PixelUI.DIM
	elif reloading:
		_state.text = "装填中"
		state_color = PixelUI.DANGER
	elif switching:
		_state.text = "切枪中"
		state_color = PixelUI.DANGER
	elif rig.mag <= 0:
		_state.text = "空仓"
		state_color = PixelUI.DANGER
	else:
		_state.text = "就绪"
	_state.add_theme_color_override("font_color", state_color)
	# 换弹显示换弹进度，收/拔枪显示收拔枪进度，其余保持空槽
	var progress := 0.0
	if reloading:
		progress = rig.get_reload_progress()
	elif rig.is_drawing() or rig.is_stowing():
		progress = rig.get_stow_progress()
	_progress.value = progress * 100.0


func show_result(success: bool, loot: Dictionary, advanced := {}, meta_reward := 0,
		xp_gain := 0, bonus_note := "", stats := {}) -> void:
	_result_panel.show()
	result_label.show()
	result_detail.show()
	return_button.show()
	restart_button.show()
	# 直接展示调用方传入的入仓物资；失败时 Main2D 传空表，浪潮阵亡则传入按比例回收的部分。
	_update_debrief_loot(loot, advanced)
	_update_debrief_stats(stats)
	if success:
		result_label.text = "撤离成功"
		result_label.add_theme_color_override("font_color", Color(0.82, 0.96, 0.82))
		var parts: Array[String] = []
		if meta_reward > 0 or xp_gain > 0:
			parts.append("信用点 +%d · +%d XP" % [meta_reward, xp_gain])
		if bonus_note != "":
			parts.append(bonus_note)
		result_detail.text = "    ".join(PackedStringArray(parts))
	else:
		result_label.text = "阵亡"
		result_label.add_theme_color_override("font_color", Color(0.96, 0.62, 0.58))
		var fail_parts: Array[String] = []
		if meta_reward > 0:
			fail_parts.append("回收信用点 +%d" % meta_reward)
		if bonus_note != "":
			fail_parts.append(bonus_note)
		if fail_parts.is_empty():
			result_detail.text = "本局物资全部丢失 · 仓库与装备保留"
		else:
			result_detail.text = "    ".join(PackedStringArray(fail_parts))


## 带出物资：只显示有产出的行，全部为 0 时给出空手提示。
func _update_debrief_loot(loot: Dictionary, advanced: Dictionary) -> void:
	var total := 0
	for id in ResourceDB.BASIC:
		var count := int(loot.get(String(id), 0))
		total += count
		_set_loot_row(String(id), count)
	for id in ResourceDB.ADVANCED:
		var count := int(advanced.get(String(id), 0))
		total += count
		_set_loot_row(String(id), count)
	if _debrief_empty != null:
		_debrief_empty.visible = total == 0


func _set_loot_row(id: String, count: int) -> void:
	var entry: Dictionary = debrief_loot_labels.get(id, {})
	if entry.is_empty():
		return
	var row: Control = entry["row"]
	var label: Label = entry["count"]
	row.visible = count > 0
	label.text = "×%d" % count


func _update_debrief_stats(stats: Dictionary) -> void:
	var shots := int(stats.get("shots", 0))
	var hits := int(stats.get("hits", 0))
	var accuracy := "—" if shots <= 0 else "%d%%" % int(round(float(hits) / float(shots) * 100.0))
	_set_stat_label("kills", "%d" % int(stats.get("kills", 0)))
	_set_stat_label("damage", "%d" % int(stats.get("damage", 0)))
	_set_stat_label("accuracy", accuracy)
	_set_stat_label("shots", "%d 发" % shots)
	_set_stat_label("time", _format_time(float(stats.get("time", 0.0))))


func _set_stat_label(key: String, text: String) -> void:
	var label: Label = debrief_stat_labels.get(key)
	if label != null:
		label.text = text


## 结算用时：MM:SS，超过一小时也只保留分钟。
func _format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var minutes := int(total / 60.0)
	return "%02d:%02d" % [minutes, total % 60]


func hide_result() -> void:
	_result_panel.hide()
	result_label.hide()
	result_detail.hide()
	return_button.hide()
	restart_button.hide()


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		if _flash_t <= 0.0:
			hint_label.add_theme_color_override("font_color", PixelUI.DIM)
	var expired: Array[Dictionary] = []
	for item in _feed_items:
		item["t"] = float(item["t"]) - delta
		var line = item["label"]
		if not is_instance_valid(line):
			expired.append(item)
			continue
		line.modulate.a = clampf(float(item["t"]) / 0.7, 0.0, 1.0)
		if float(item["t"]) <= 0.0:
			line.queue_free()
			expired.append(item)
	for item in expired:
		_feed_items.erase(item)


## 弹匣条：每发一根竖条，一排放得下；比矩阵格更矮，适合紧凑武器面板。
class ShellStrip2D extends Control:
	var mag := 0
	var cap := 0

	func _draw() -> void:
		if cap <= 0:
			return
		var amber := PixelUI.AMBER
		var slot := 7.0
		var bar_w := 5.0
		var bar_h := minf(size.y - 4.0, 12.0)
		var width := cap * slot - 2.0
		var origin := Vector2((size.x - width) * 0.5, (size.y - bar_h) * 0.5)
		draw_rect(Rect2(origin - Vector2(4, 3), Vector2(width + 8, bar_h + 6)),
			Color(0.85, 0.89, 0.92, 0.22), false, 1.0)
		for i in cap:
			var pos := origin + Vector2(i * slot, 0.0)
			var loaded := i < mag
			draw_rect(Rect2(pos, Vector2(bar_w, bar_h)),
				amber if loaded else Color(0.11, 0.14, 0.17, 0.95), true)
			draw_rect(Rect2(pos, Vector2(bar_w, bar_h)),
				Color(0.55, 0.60, 0.64, 0.45), false, 1.0)
