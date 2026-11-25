extends RefCounted
class_name ArmoryDetailView
## 武备库「武器数据」子页视图：顶部 7 分类标签栏 + 左侧分类定置武器滚动列表 + 右侧 18 项属性详情面板与主/副装配及「去改枪」按钮。
## 统一复用 WeaponStatsModel、DamageModel 与 ModInstallService，不重复实现数值公式。

signal weapon_selected(weapon_id: StringName)
signal category_selected(category: StringName)
signal equip_requested(primary_slot: bool)
signal mod_requested(weapon_id: StringName)
signal tip_show_requested(key: String)
signal tip_hide_requested

const STATS_MODEL := preload("res://scripts/weapons/WeaponStatsModel.gd")
const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")
const TOOLTIP_VIEW := preload("res://scripts/ui/armory/ArmoryTooltipView.gd")

var page: VBoxContainer
var category_bar: HBoxContainer
var category_buttons: Dictionary = {}
var category_note: Label
var list_scroll: ScrollContainer
var weapon_list: VBoxContainer
var weapon_buttons: Dictionary = {}
var detail_icon: TextureRect
var detail_title: Label
var detail_subtitle: Label
var detail_values: Dictionary = {}
var detail_deltas: Dictionary = {}
var detail_base: Dictionary = {}
var detail_rows: Dictionary = {}
var primary_button: Button
var secondary_button: Button
var mod_button: Button
var _current_selected: StringName = &"m870"


func build(parent: Node) -> void:
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(page)

	# 顶部 7 分类标签栏：全部 / 手枪 / 冲锋枪 / 霰弹枪 / 步枪 / 射手步枪 / 狙击步枪。
	category_bar = HBoxContainer.new()
	category_bar.add_theme_constant_override("separation", 6)
	page.add_child(category_bar)
	for cat in WeaponDB.WEAPON_CATEGORIES:
		var count := WeaponDB.weapons_in_category(cat).size()
		var btn := PixelUI.button("%s (%d)" % [WeaponDB.weapon_category_name(cat), count], 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func() -> void: category_selected.emit(cat))
		category_bar.add_child(btn)
		category_buttons[cat] = btn

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size.x = 580
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	split.add_child(left_col)

	category_note = PixelUI.label(left_col, "", 16, PixelUI.DIM)
	category_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	list_scroll = ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 580
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(list_scroll)
	weapon_list = VBoxContainer.new()
	weapon_list.add_theme_constant_override("separation", 8)
	weapon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(weapon_list)
	for id in WeaponDB.WEAPON_ORDER:
		var button := PixelUI.button("", 68)
		button.custom_minimum_size.x = 540
		button.add_theme_font_size_override("font_size", 19)
		button.pressed.connect(func() -> void: weapon_selected.emit(id))
		weapon_list.add_child(button)
		weapon_buttons[id] = button

	var detail := PixelUI.panel()
	detail.custom_minimum_size.x = 480
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail)
	var detail_rows_box := VBoxContainer.new()
	detail_rows_box.add_theme_constant_override("separation", 1)
	detail.add_child(detail_rows_box)

	var detail_header := HBoxContainer.new()
	detail_header.add_theme_constant_override("separation", 10)
	detail_rows_box.add_child(detail_header)
	detail_icon = TextureRect.new()
	detail_icon.name = "WeaponIcon"
	detail_icon.custom_minimum_size = Vector2(68, 68)
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	detail_header.add_child(detail_icon)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_box.add_theme_constant_override("separation", 2)
	detail_header.add_child(title_box)
	detail_title = PixelUI.label(title_box, "", 24, PixelUI.AMBER)
	detail_subtitle = PixelUI.label(title_box, "悬浮数据行查看加成来源", 16, PixelUI.DIM)
	var detail_divider := HSeparator.new()
	detail_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.6))
	detail_rows_box.add_child(detail_divider)
	for key in TOOLTIP_VIEW.STAT_KEYS:
		_build_stat_row(detail_rows_box, key)

	var equip_row := HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 8)
	detail_rows_box.add_child(equip_row)
	primary_button = PixelUI.button("设为主武器", 34)
	primary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_button.add_theme_font_size_override("font_size", 18)
	primary_button.pressed.connect(func() -> void: equip_requested.emit(true))
	equip_row.add_child(primary_button)

	secondary_button = PixelUI.button("设为副武器", 34)
	secondary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secondary_button.add_theme_font_size_override("font_size", 18)
	secondary_button.pressed.connect(func() -> void: equip_requested.emit(false))
	equip_row.add_child(secondary_button)

	mod_button = PixelUI.button("⚙ 去改枪 // 改装此武器", 34)
	mod_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_button.add_theme_font_size_override("font_size", 18)
	mod_button.add_theme_color_override("font_color", PixelUI.AMBER_BRIGHT)
	mod_button.pressed.connect(func() -> void: mod_requested.emit(_current_selected))
	detail_rows_box.add_child(mod_button)


func _build_stat_row(parent: Node, key: String) -> void:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(line)
	var name_label := PixelUI.label(line, key, 17, PixelUI.DIM)
	name_label.custom_minimum_size.x = 124
	var value := PixelUI.label(line, "-", 17, PixelUI.TEXT)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_values[key] = value
	# 增减标注单独一列右对齐，避免绿/红数字把基础数值挤得跳动。
	var delta := PixelUI.label(line, "", 17, PixelUI.OK)
	delta.custom_minimum_size.x = 104
	delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_deltas[key] = delta
	detail_rows[key] = line
	line.mouse_entered.connect(func() -> void: tip_show_requested.emit(key))
	line.mouse_exited.connect(func() -> void: tip_hide_requested.emit())


## 写入实际数值与增减标注。delta 为相对基础值的差值；
## higher_is_better 为 true 时增加标绿、减少标红，false 时相反。
func set_stat(key: String, text: String, base_text: String,
		delta: float, higher_is_better: bool, digits: int) -> void:
	detail_values[key].text = text
	detail_base[key] = base_text
	var delta_label: Label = detail_deltas[key]
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
	delta_label.text = "(%s)" % number
	var gain := (delta > 0.0) == higher_is_better
	delta_label.add_theme_color_override("font_color", PixelUI.OK if gain else PixelUI.DANGER)


## 刷新左侧武器列表（含分类筛选与主/副定置排序）与右侧 18 项属性及悬浮来源。
func refresh(selected: StringName, primary: StringName, secondary: StringName,
		progress: Node, tooltip_view: ArmoryTooltipView,
		category: StringName = &"all") -> void:
	_current_selected = selected
	for cat in WeaponDB.WEAPON_CATEGORIES:
		var btn: Button = category_buttons.get(cat)
		if btn == null:
			continue
		var count := WeaponDB.weapons_in_category(cat).size()
		var active := cat == category
		btn.text = "%s%s (%d)" % ["▶ " if active else "", WeaponDB.weapon_category_name(cat), count]
		btn.add_theme_color_override("font_color", PixelUI.AMBER_BRIGHT if active else PixelUI.TEXT)
	if category_note != null:
		category_note.text = WeaponDB.weapon_category_desc(category)

	var visible_order := MOD_SERVICE.pinned_weapon_order(primary, secondary, category)
	var visible_set := {}
	var index := 0
	for sid in visible_order:
		var key := StringName(sid)
		visible_set[key] = true
		if weapon_buttons.has(key):
			var btn: Button = weapon_buttons[key]
			btn.visible = true
			weapon_list.move_child(btn, index)
			index += 1
	for id in WeaponDB.WEAPON_ORDER:
		if not visible_set.has(id) and weapon_buttons.has(id):
			var hidden_btn: Button = weapon_buttons[id]
			hidden_btn.visible = false
			weapon_list.move_child(hidden_btn, index)
			index += 1

	var installed: Dictionary = {}
	var fire_mode := "interval"
	var reload_talent := 1.0
	if progress != null:
		installed = progress.weapon_mods_2d(selected)
		fire_mode = String(progress.data.get("fire_rate_display", "interval"))
		reload_talent = STATS_MODEL.reload_talent_mul(int(progress.talent_2d_level(&"reload")))

	var stats: Dictionary = STATS_MODEL.compute_for_progress(selected, progress, installed)
	var base: WeaponData = stats["base"]
	var ammo = stats["ammo"]

	detail_title.text = base.display_name
	if detail_subtitle != null:
		var cat_label := WeaponDB.weapon_category_name(base.category)
		var mode_label := "全自动 / 半自动" if bool(stats["auto"]) else "仅半自动"
		detail_subtitle.text = "%s · %s · 悬浮数据行查看加成来源" % [cat_label, mode_label]
	var icon_path := "res://assets/art/weapons/%s/icon.png" % selected
	detail_icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null

	var mag: int = int(stats["mag"])
	var load_time: float = float(stats["load"])
	var interval: float = float(stats["interval"])
	var range_m: float = float(stats["range"])
	var sound: float = float(stats["sound"])
	var base_damage: float = float(stats["base_pellet_damage"])
	var damage: float = float(stats["pellet_damage"])
	var spread_base: float = float(stats["base_spread"])
	var spread_actual: float = float(stats["spread"])

	detail_values["口径"].text = base.caliber_label
	detail_base["口径"] = ""
	var feed := "弹匣" if base.feed_mode == &"mag" else "管式"
	var cycle := "自动" if base.feed_mode == &"mag" else "泵动 %.2fs" % base.pump_time
	detail_values["供弹方式"].text = "%s · %s" % [feed, cycle]
	detail_base["供弹方式"] = ""

	set_stat("弹匣容量", "%d 发" % mag, "%d 发" % base.mag_capacity,
		float(mag - base.mag_capacity), true, 0)
	var load_suffix := " / 发" if base.feed_mode == &"shell" else ""
	set_stat("换弹时间", "%.2fs%s" % [load_time, load_suffix],
		"%.2fs%s" % [base.load_time, load_suffix],
		load_time - base.load_time, false, 2)
	if fire_mode == "rpm":
		var rpm := 60.0 / interval
		var base_rpm := 60.0 / maxf(base.fire_interval, 0.001)
		set_stat("射速", "%d RPM" % int(round(rpm)), "%d RPM" % int(round(base_rpm)),
			rpm - base_rpm, true, 0)
	else:
		set_stat("射速", "%.2fs / 发" % interval, "%.2fs / 发" % base.fire_interval,
			interval - base.fire_interval, false, 2)
	set_stat("射程", "%.0fm" % range_m, "%.0fm" % base.range_m,
		range_m - base.range_m, true, 0)
	var base_speed := float(base.bullet_speed_mps)
	var actual_speed := float(stats["speed"])
	set_stat("子弹速度", "%d m/s" % int(round(actual_speed)),
		"%d m/s" % int(round(base_speed)),
		actual_speed - base_speed, true, 0)
	set_stat("散布", "%.1f°" % rad_to_deg(spread_actual),
		"%.1f°" % rad_to_deg(spread_base),
		rad_to_deg(spread_actual - spread_base), false, 1)
	_set_plain_stat("后坐抑制", "%d%%" % int(round(float(stats["recoil"]) * 100.0)))
	_set_plain_stat("垂直后坐", "基 %.0f / 限 %.0f" % [
		base.recoil_vertical, base.recoil_max_vertical])
	_set_plain_stat("水平后坐", "基 %.0f / 限 %.0f" % [
		base.recoil_horizontal, base.recoil_max_horizontal])
	_set_plain_stat("视野倍率", "+%d%%" % int(round(float(stats["vision"]) * 100.0)))
	var base_ads_time: float = float(stats["base_ads_time"])
	var ads_time: float = float(stats["ads_time"])
	set_stat("瞄准速度", "%.2fs" % ads_time, "%.2fs" % base_ads_time,
		ads_time - base_ads_time, false, 2)
	set_stat("枪声范围", "%.0fm" % sound, "%.0fm" % base.sound_radius,
		sound - base.sound_radius, false, 0)
	if ammo == null:
		_set_plain_stat("弹药", "-")
		_set_plain_stat("弹丸数", "-")
		_set_plain_stat("穿甲", "-")
		_set_plain_stat("伤害", "-")
		_set_plain_stat("爆发 DPS", "-")
	else:
		var ammo_text: String = ammo.display_name
		if ammo.pellets > 1:
			ammo_text += " ×%d" % ammo.pellets
		_set_plain_stat("弹药", ammo_text)
		_set_plain_stat("弹丸数", "%d" % ammo.pellets)
		_set_plain_stat("穿甲",
			DAMAGE_MODEL.format_rha(ammo.ap, MOD_SERVICE.armor_display_mode(progress)))
		var pellets := float(ammo.pellets)
		set_stat("伤害",
			"%d × %.1f = %.1f" % [ammo.pellets, damage, float(stats["damage"])],
			"%d × %.1f = %.1f" % [ammo.pellets, base_damage, base_damage * pellets],
			(damage - base_damage) * pellets, true, 1)
		var base_burst_dps: float = float(stats["base_burst_dps"])
		var burst_dps: float = float(stats["burst_dps"])
		set_stat("爆发 DPS", "%.0f /s" % burst_dps, "%.0f /s" % base_burst_dps,
			burst_dps - base_burst_dps, true, 0)

	for id in WeaponDB.WEAPON_ORDER:
		var button: Button = weapon_buttons[id]
		var wstats: Dictionary = STATS_MODEL.compute_for_progress(id, progress)
		var weapon: WeaponData = wstats["base"]
		var w_mag: int = int(wstats["mag"])
		var w_range: float = float(wstats["range"])
		var w_interval: float = float(wstats["interval"])
		var w_fire := ("%d RPM" % int(round(60.0 / w_interval))) \
			if fire_mode == "rpm" else ("%.2fs/发" % w_interval)
		var w_speed := int(round(float(wstats["speed"])))
		var marker := "▶ " if id == selected else "   "
		var slot := ""
		if id == primary:
			slot = " [主]"
		elif id == secondary:
			slot = " [副]"
		button.text = "%s%s%s\n弹匣容量 %d · 射程 %.0fm · 弹速 %d m/s · %s" % [
			marker, weapon.display_name, slot, w_mag, w_range, w_speed, w_fire,
		]

	if tooltip_view != null:
		tooltip_view.refresh_tooltips(selected, installed, reload_talent, ammo,
			detail_base, detail_values, progress, stats)


func _set_plain_stat(key: String, text: String) -> void:
	detail_values[key].text = text
	detail_base[key] = ""
	detail_deltas[key].text = ""
