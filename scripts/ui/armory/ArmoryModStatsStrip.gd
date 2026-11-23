extends RefCounted
class_name ArmoryModStatsStrip
## 改枪页下半部面板：实时属性对比条（4 列网格）、激光/准心颜色选择与已装配瞄具准星切换。
## 从 ArmoryMenu2D 抽离，与 WeaponStatsModel、DamageModel 与 ModInstallService 完全同源。

signal reticle_style_changed
signal feedback_emitted(text: String, color: Color)

const STATS_MODEL := preload("res://scripts/weapons/WeaponStatsModel.gd")
const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")

const COLOR_PRESETS: Array[Color] = [
	Color(0.35, 1.0, 0.50), Color(1.0, 0.30, 0.22), Color(0.35, 0.80, 1.0),
	Color(1.0, 0.72, 0.25), Color(0.75, 0.45, 1.0), Color(0.92, 0.95, 1.0),
	Color(0.03, 0.03, 0.04),
]

const STAT_DEFS: Array = [
	["mag", "弹匣"], ["rate", "射速"], ["load", "换弹"], ["range", "射程"],
	["speed", "弹速"], ["spread", "散布"], ["sound", "枪声"], ["damage", "伤害"],
	["ap", "穿甲"], ["mode", "模式"], ["slots", "槽位"], ["recoil", "后坐"],
	["vision", "视野"], ["ads", "瞄准"],
]

var stats_panel: PanelContainer
var stat_values: Dictionary = {}
var stat_deltas: Dictionary = {}
var reticle_box: VBoxContainer
var reticle_row: HBoxContainer
var reticle_buttons: Dictionary = {}
var _progress_fn: Callable = Callable()


func build(parent: Node, progress_fn: Callable) -> void:
	_progress_fn = progress_fn
	_build_mod_stats(parent)
	_build_color_picker(parent)
	_build_reticle_switch(parent)


func set_stats_visible(vis: bool) -> void:
	if stats_panel != null:
		stats_panel.visible = vis


func _progress() -> Node:
	return _progress_fn.call() if _progress_fn.is_valid() else null


## 下半：横向数据条（4 列网格），预览配件时实时变化。
func _build_mod_stats(parent: Node) -> void:
	stats_panel = PanelContainer.new()
	stats_panel.custom_minimum_size.y = 112
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	stats_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(stats_panel)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	stats_panel.add_child(grid)

	for entry in STAT_DEFS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.custom_minimum_size.x = 196
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var name_label := PixelUI.label(cell, String(entry[1]), 16, PixelUI.DIM)
		name_label.custom_minimum_size.x = 38
		var value := PixelUI.label(cell, "-", 16, PixelUI.TEXT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var delta := PixelUI.label(cell, "", 13, PixelUI.OK)
		delta.custom_minimum_size.x = 46
		delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_values[String(entry[0])] = value
		stat_deltas[String(entry[0])] = delta


## 外观颜色：激光与准心各一排色块，写入 Progress 后立即生效。
func _build_color_picker(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	row.add_child(_color_group("激光颜色", "laser"))
	row.add_child(_color_group("准心颜色", "reticle"))


func _color_group(label_text: String, kind: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var label := PixelUI.label(box, label_text, 16, PixelUI.DIM)
	label.custom_minimum_size.x = 68
	for color in COLOR_PRESETS:
		# 黑色只作为准心预设；激光保持可见的亮色，自定义调色盘仍可选任意颜色。
		if kind == "laser" and color.get_luminance() < 0.1:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(24, 24)
		button.focus_mode = Control.FOCUS_NONE
		var normal := StyleBoxFlat.new()
		normal.bg_color = color
		normal.border_color = Color(0.02, 0.02, 0.03, 0.9)
		normal.set_border_width_all(1)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.border_color = Color(1, 1, 1, 0.9)
		hover.set_border_width_all(2)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.pressed.connect(_set_sight_color.bind(kind, color))
		box.add_child(button)
	# 调色盘：预设之外允许完全自定义颜色。
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(48, 24)
	picker.focus_mode = Control.FOCUS_NONE
	picker.edit_alpha = false
	picker.tooltip_text = "自定义颜色"
	var p := _progress()
	if p != null:
		picker.color = p.laser_color() if kind == "laser" else p.reticle_color()
	picker.color_changed.connect(func(c: Color) -> void: _set_sight_color(kind, c))
	box.add_child(picker)
	return box


func _set_sight_color(kind: String, color: Color) -> void:
	var p := _progress()
	if p == null:
		return
	if kind == "laser":
		p.set_laser_color(color)
	else:
		p.set_reticle_color(color)
	feedback_emitted.emit("外观颜色已更新 · 进入行动后生效", PixelUI.OK)


## 准星切换：为当前武器已装配的瞄具切换样式（每个瞄具独立保存）。
func _build_reticle_switch(parent: Node) -> void:
	reticle_box = VBoxContainer.new()
	reticle_box.add_theme_constant_override("separation", 4)
	parent.add_child(reticle_box)
	PixelUI.label(reticle_box, "准星样式", 18, PixelUI.DIM)
	reticle_row = HBoxContainer.new()
	reticle_row.add_theme_constant_override("separation", 6)
	reticle_box.add_child(reticle_row)


func refresh_reticle_switch(mod_item: String) -> void:
	if reticle_box == null or reticle_row == null:
		return
	for child in reticle_row.get_children():
		child.queue_free()
	reticle_buttons.clear()
	var p := _progress()
	if p == null or mod_item == "armor":
		reticle_box.visible = false
		return
	var installed: Dictionary = p.weapon_mods_2d(mod_item)
	var sight_id := String(installed.get("sight", ""))
	var entry := ModDB.option("sight", sight_id, false, mod_item)
	if sight_id == "" or sight_id == "iron" or entry.is_empty():
		reticle_box.visible = false
		return
	reticle_box.visible = true
	var default_style := String(entry.get("reticle", "cross"))
	var styles := MOD_SERVICE.reticle_styles_for(entry)
	var current := String(p.reticle_style(sight_id, default_style))
	for pair in styles:
		var style := String(pair[0])
		if style == "native":
			style = default_style
		var button := PixelUI.button(("▶ " if style == current else "   ")
			+ String(pair[1]), 34)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_set_reticle_style.bind(sight_id, style))
		reticle_row.add_child(button)
		reticle_buttons[style] = button


func _set_reticle_style(sight_id: String, style: String) -> void:
	var p := _progress()
	if p != null:
		p.set_reticle_style(sight_id, style)
	reticle_style_changed.emit()


func refresh_stats(weapon_id: StringName, current_installed: Dictionary,
		preview_installed: Dictionary) -> void:
	var p := _progress()
	var cur := STATS_MODEL.compute_for_progress(weapon_id, p, current_installed)
	var pre := STATS_MODEL.compute_for_progress(weapon_id, p, preview_installed)
	var fire_mode := "interval"
	if p != null:
		fire_mode = String(p.data.get("fire_rate_display", "interval"))
	_set_stat("mag", "%d 发" % int(pre["mag"]),
		float(pre["mag"]) - float(cur["mag"]), true, 0)
	if fire_mode == "rpm":
		var rpm := 60.0 / maxf(float(pre["interval"]), 0.001)
		var cur_rpm := 60.0 / maxf(float(cur["interval"]), 0.001)
		_set_stat("rate", "%d RPM" % int(round(rpm)), rpm - cur_rpm, true, 0)
	else:
		_set_stat("rate", "%.2fs/发" % float(pre["interval"]),
			float(pre["interval"]) - float(cur["interval"]), false, 2)
	_set_stat("load", "%.2fs" % float(pre["load"]),
		float(pre["load"]) - float(cur["load"]), false, 2)
	_set_stat("range", "%.0fm" % float(pre["range"]),
		float(pre["range"]) - float(cur["range"]), true, 0)
	_set_stat("speed", "%d m/s" % int(round(float(pre["speed"]))),
		float(pre["speed"]) - float(cur["speed"]), true, 0)
	_set_stat("spread", "%.1f°" % rad_to_deg(float(pre["spread"])),
		rad_to_deg(float(pre["spread"]) - float(cur["spread"])), false, 1)
	_set_stat("ap", DAMAGE_MODEL.format_rha(float(pre["ap"]), MOD_SERVICE.armor_display_mode(p)),
		float(pre["ap"]) - float(cur["ap"]), true, 0)
	_set_stat("sound", "%.0fm" % float(pre["sound"]),
		float(pre["sound"]) - float(cur["sound"]), false, 0)
	_set_stat("damage", "%.1f" % float(pre["damage"]),
		float(pre["damage"]) - float(cur["damage"]), true, 1)
	var mode_label: Label = stat_values["mode"]
	mode_label.text = "全自动" if bool(pre["auto"]) else "单发"
	mode_label.add_theme_color_override("font_color",
		PixelUI.AMBER_BRIGHT if bool(pre["auto"]) else PixelUI.TEXT)
	var mode_delta: Label = stat_deltas["mode"]
	mode_delta.text = "" if bool(pre["auto"]) == bool(cur["auto"]) else "切换"
	var filled := 0
	for slot_def in ModDB.WEAPON_SLOTS:
		if String(current_installed.get(String(slot_def["id"]), "")) != "":
			filled += 1
	_set_stat("slots", "%d / %d" % [filled, ModDB.WEAPON_SLOTS.size()], 0.0, true, 0)
	_set_stat("recoil", "%d%%" % int(round(float(pre["recoil"]) * 100.0)),
		(float(pre["recoil"]) - float(cur["recoil"])) * 100.0, true, 0)
	_set_stat("vision", "+%d%%" % int(round(float(pre["vision"]) * 100.0)),
		(float(pre["vision"]) - float(cur["vision"])) * 100.0, true, 0)
	_set_stat("ads", "+%d%%" % int(round(float(pre["ads"]) * 100.0)),
		(float(pre["ads"]) - float(cur["ads"])) * 100.0, true, 0)


func _set_stat(key: String, text: String, delta: float,
		higher_is_better: bool, digits: int) -> void:
	var value: Label = stat_values.get(key)
	var delta_label: Label = stat_deltas.get(key)
	if value == null or delta_label == null:
		return
	value.text = text
	if absf(delta) < 0.0001:
		delta_label.text = ""
		return
	var number := ""
	if digits <= 0:
		number = "%+d" % int(round(delta))
	elif digits == 1:
		number = "%+.1f" % delta
	else:
		number = "%+.2f" % delta
	delta_label.text = number
	var gain := (delta > 0.0) == higher_is_better
	delta_label.add_theme_color_override("font_color", PixelUI.OK if gain else PixelUI.DANGER)
