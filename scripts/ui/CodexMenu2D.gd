extends Control
class_name CodexMenu2D
## 基地图鉴：敌人图鉴 / 物品图鉴两个子页，逐条翻页查看配图、数值与档案描述。
## 敌人 8 条（基础 4 + 新单位 4），物品 37 条（18 武器 + 12 弹药 + 7 资源）。
## 翻页按钮固定在面板左下角与右下角，使用 assets/art/ui/icons/codex_*.png 图标。

signal closed

const PANEL_SIZE := Vector2(1240, 820)
const ICON_ROOT := "res://assets/art/ui/icons/"
const PAGE_ENEMY := "enemy"
const PAGE_ITEM := "item"
## 数值网格最多显示 14 项（2 列 × 7 行）；歌利亚的爆炸参数也在此范围内。
const MAX_STATS := 14

## 敌人档案正文：世界观与战术提示，避免图鉴只剩干巴巴的数值。
const ENEMY_NOTES := {
	"rifleman": "设施标准巡逻单位。以短点射压制开阔走廊，听到枪声后会向声源靠拢并保持中距离。护甲薄弱，优先打断其射击节奏。",
	"rusher": "高速近战单位。进入视野后会直线冲刺，几乎不做横向规避；在狭窄门口容易被集中火力撕碎。",
	"heavy": "重装压制单位。移动缓慢但护甲厚重，近身挥击伤害极高；建议使用穿甲弹或绕后处理。",
	"hunter": "盲视声呐单位。完全依赖听觉锁定目标，枪声与脚步都会暴露位置；静止或使用低噪音武器能显著降低威胁。",
	"mobile_turret": "移动哨戒炮一型。中远距离双发点射，视野极广但转向迟缓；利用掩体切入其侧后方。",
	"sentry_type1": "哨兵一型。具备短距冲锋能力的人形机械，进入冲锋距离后会突然加速。",
	"hunter_type1": "巡猎者一型。高耐久近战猎杀单位，会持续追踪已知目标；不要与其在开阔地缠斗。",
	"goliath": "歌利亚通用一型。自杀式爆破单位，接近后引爆；爆炸半径 4m、中心伤害 100、引信 1.8s。被压制到 1 点生命时会立即进入自爆，自爆期间每次受击都会加快引爆，引信结束爆炸并同时死亡，不要贴脸补枪。",
}

const BEHAVIOR_NAMES := {
	"": "常规",
	"turret": "固定炮台",
	"charger": "短距冲锋",
	"melee": "近战追击",
	"suicide": "自杀爆破",
}

const KIND_NAMES := {
	"weapon": "武器",
	"ammo": "弹药",
	"resource": "资源",
}

var _page := PAGE_ENEMY
var _enemy_index := 0
var _item_index := 0
var _enemy_entries: Array[Dictionary] = []
var _item_entries: Array[Dictionary] = []

var _portrait: TextureRect
var _portrait_caption: Label
var _detail_title: Label
var _detail_sub: Label
var _stat_rows: Array = []
var _note_panel: PanelContainer
var _note_label: Label
var _note_footer: Label
var _page_label: Label
var _prev_button: Button
var _next_button: Button
var _tab_enemy: Button
var _tab_item: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_cache_entries()
	_build()
	visible = false


## 条目缓存：只在打开菜单前生成一次，翻页时不再重复构造武器数据。
func _cache_entries() -> void:
	_enemy_entries.clear()
	_item_entries.clear()
	var seen := {}
	for id in EnemyDB.ORDER:
		if seen.has(id):
			continue
		seen[id] = true
		_enemy_entries.append({"kind": "enemy", "id": id})
	for id in EnemyDB.new_units():
		if seen.has(id):
			continue
		seen[id] = true
		_enemy_entries.append({"kind": "enemy", "id": id})
	for id in WeaponDB.WEAPON_ORDER:
		_item_entries.append({"kind": "weapon", "id": id})
	for id in WeaponDB.AMMO_ORDER:
		_item_entries.append({"kind": "ammo", "id": id})
	for id in ResourceDB.BASIC:
		_item_entries.append({"kind": "resource", "id": id})
	for id in ResourceDB.ADVANCED:
		_item_entries.append({"kind": "resource", "id": id})


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	rows.add_child(header)
	var title := PixelUI.label(header, "图鉴 // CODEX", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := PixelUI.label(header, "ARCHIVE // %d ENTRIES" % (enemy_count() + item_count()),
		PixelUI.FS_BODY, PixelUI.DIM)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	rows.add_child(tabs)
	_tab_enemy = PixelUI.button("▶ 敌人图鉴 // HOSTILES", 44)
	_tab_enemy.name = "TabEnemy"
	_tab_enemy.custom_minimum_size.x = 420
	_tab_enemy.add_theme_font_size_override("font_size", 20)
	_tab_enemy.pressed.connect(func() -> void: _show_page(PAGE_ENEMY))
	tabs.add_child(_tab_enemy)
	_tab_item = PixelUI.button("   物品图鉴 // ITEMS", 44)
	_tab_item.name = "TabItem"
	_tab_item.custom_minimum_size.x = 420
	_tab_item.add_theme_font_size_override("font_size", 20)
	_tab_item.pressed.connect(func() -> void: _show_page(PAGE_ITEM))
	tabs.add_child(_tab_item)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(content)

	var portrait_panel := PixelUI.panel(PixelUI.BG_LIGHT, Color(PixelUI.AMBER, 0.55))
	portrait_panel.custom_minimum_size.x = 460
	content.add_child(portrait_panel)
	var portrait_rows := VBoxContainer.new()
	portrait_rows.add_theme_constant_override("separation", 8)
	portrait_panel.add_child(portrait_rows)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(420, 420)
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_rows.add_child(_portrait)

	_portrait_caption = PixelUI.label(portrait_rows, "", 20, PixelUI.DIM)
	_portrait_caption.name = "PortraitCaption"
	_portrait_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 6)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(detail)

	_detail_title = PixelUI.label(detail, "", 32, PixelUI.AMBER)
	_detail_title.name = "DetailTitle"
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_sub = PixelUI.label(detail, "", 20, PixelUI.DIM)
	_detail_sub.name = "DetailSub"

	var detail_divider := HSeparator.new()
	detail_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.55))
	detail.add_child(detail_divider)

	# 两列数值 + 中间竖线：避免左右两列的「数值」和「字段名」在视觉上连成一句。
	var stat_columns := HBoxContainer.new()
	stat_columns.name = "StatGrid"
	stat_columns.add_theme_constant_override("separation", 18)
	detail.add_child(stat_columns)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 4)
	left_col.custom_minimum_size.x = 320
	stat_columns.add_child(left_col)
	var column_sep := VSeparator.new()
	column_sep.custom_minimum_size.x = 1
	column_sep.add_theme_color_override("color", Color(PixelUI.AMBER, 0.28))
	stat_columns.add_child(column_sep)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 4)
	right_col.custom_minimum_size.x = 320
	stat_columns.add_child(right_col)
	for i in MAX_STATS:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.custom_minimum_size.x = 320
		(left_col if i % 2 == 0 else right_col).add_child(cell)
		var name_label := PixelUI.label(cell, "", 18, PixelUI.DIM)
		name_label.custom_minimum_size.x = 78
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var value_label := PixelUI.label(cell, "", 18, PixelUI.TEXT)
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# 长数值自动换行而不是截断，同时避免把 1240 宽的面板撑大。
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_stat_rows.append({"cell": cell, "name": name_label, "value": value_label})

	_note_panel = PixelUI.panel(PixelUI.BG_LIGHT, Color(PixelUI.AMBER, 0.45))
	_note_panel.name = "NotePanel"
	_note_panel.custom_minimum_size.y = 190
	_note_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_note_panel)
	var note_rows := VBoxContainer.new()
	note_rows.add_theme_constant_override("separation", 4)
	_note_panel.add_child(note_rows)
	PixelUI.label(note_rows, "档案记录 // ARCHIVE NOTE", 20, PixelUI.AMBER)
	var note_divider := HSeparator.new()
	note_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.35))
	note_rows.add_child(note_divider)
	_note_label = PixelUI.label(note_rows, "", 20, PixelUI.TEXT)
	_note_label.name = "NoteLabel"
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note_footer = PixelUI.label(note_rows, "更多背景资料待补充 // DATA PENDING", 18, PixelUI.DIM)
	_note_footer.name = "NoteFooter"

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	rows.add_child(footer)
	_prev_button = _paging_button("codex_prev", "◀")
	_prev_button.name = "PrevButton"
	_prev_button.pressed.connect(func() -> void: _step(-1))
	footer.add_child(_prev_button)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	footer.add_child(center)
	_page_label = PixelUI.label(center, "", 20, PixelUI.TEXT)
	_page_label.name = "PageLabel"
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := PixelUI.label(center, "← → 翻页 · ESC 返回基地", 18, PixelUI.DIM)
	hint.name = "HintLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_next_button = _paging_button("codex_next", "▶")
	_next_button.name = "NextButton"
	_next_button.pressed.connect(func() -> void: _step(1))
	footer.add_child(_next_button)

	_show_page(PAGE_ENEMY)


## 翻页按钮：图标优先，资源缺失时退回文字箭头，保证任何环境下都可点击。
func _paging_button(icon_name: String, fallback: String) -> Button:
	var button := PixelUI.button("", 56)
	button.custom_minimum_size = Vector2(96, 56)
	button.add_theme_font_size_override("font_size", 28)
	var path := ICON_ROOT + icon_name + ".png"
	if ResourceLoader.exists(path):
		var icon := TextureRect.new()
		icon.texture = load(path)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 26
		icon.offset_right = -26
		icon.offset_top = 10
		icon.offset_bottom = -10
	else:
		button.text = fallback
	return button


func enemy_count() -> int:
	return _enemy_entries.size()


func item_count() -> int:
	return _item_entries.size()


func _show_page(page: String) -> void:
	_page = page if page == PAGE_ITEM else PAGE_ENEMY
	_tab_enemy.text = ("▶ " if _page == PAGE_ENEMY else "   ") + "敌人图鉴 // HOSTILES"
	_tab_item.text = ("▶ " if _page == PAGE_ITEM else "   ") + "物品图鉴 // ITEMS"
	_refresh_entry()


func _step(delta: int) -> void:
	if _page == PAGE_ENEMY:
		_enemy_index = clampi(_enemy_index + delta, 0, maxi(enemy_count() - 1, 0))
	else:
		_item_index = clampi(_item_index + delta, 0, maxi(item_count() - 1, 0))
	_refresh_entry()


func _refresh_entry() -> void:
	if _page == PAGE_ENEMY:
		_enemy_index = clampi(_enemy_index, 0, maxi(enemy_count() - 1, 0))
		if not _enemy_entries.is_empty():
			_refresh_enemy(_enemy_entries[_enemy_index]["id"])
	else:
		_item_index = clampi(_item_index, 0, maxi(item_count() - 1, 0))
		if not _item_entries.is_empty():
			var entry: Dictionary = _item_entries[_item_index]
			match String(entry["kind"]):
				"weapon":
					_refresh_weapon(entry["id"])
				"ammo":
					_refresh_ammo(entry["id"])
				"resource":
					_refresh_resource(entry["id"])
	_update_pager()


func _refresh_enemy(id: StringName) -> void:
	var st := EnemyDB.stats(id)
	_portrait.texture = _enemy_texture(id)
	_portrait.modulate = Color.WHITE
	_portrait_caption.text = "HOSTILE // 敌方单位"
	_detail_title.text = String(st.get("name", String(id)))
	_detail_sub.text = "HOSTILE // ENEMY UNIT · %s" % String(id)
	_set_stats(_enemy_fields(id))
	_note_label.text = String(ENEMY_NOTES.get(String(id), "档案缺失，等待后续情报补录。"))


func _refresh_weapon(id: StringName) -> void:
	var w := WeaponDB.get_weapon(id)
	_portrait.texture = _item_texture("weapon", id)
	_portrait.modulate = Color.WHITE
	_portrait_caption.text = "WEAPON // 武器"
	_detail_title.text = w.display_name
	_detail_sub.text = "ITEM ARCHIVE // WEAPON · %s" % String(id)
	_set_stats(_weapon_fields(w))
	_note_label.text = _note_for_weapon(w)


func _refresh_ammo(id: StringName) -> void:
	var ammo = WeaponDB.ammo_table().get(id)
	if ammo == null:
		return
	_portrait.texture = _item_texture("ammo", id)
	_portrait.modulate = ammo.color
	_portrait_caption.text = "AMMUNITION // 弹药"
	_detail_title.text = ammo.display_name
	_detail_sub.text = "ITEM ARCHIVE // AMMO · %s" % String(id)
	_set_stats(_ammo_fields(ammo))
	_note_label.text = _note_for_ammo(ammo)


func _refresh_resource(id: StringName) -> void:
	var rec: Dictionary = ResourceDB.DATA.get(id, {})
	_portrait.texture = _item_texture("resource", id)
	_portrait.modulate = Color.WHITE
	_portrait_caption.text = "MATERIAL // 资源"
	_detail_title.text = String(rec.get("name", String(id)))
	_detail_sub.text = "ITEM ARCHIVE // MATERIAL · %s" % String(id)
	_set_stats(_resource_fields(id, rec))
	_note_label.text = _note_for_resource(id, rec)


func _set_stats(fields: Array) -> void:
	for i in _stat_rows.size():
		var row: Dictionary = _stat_rows[i]
		var cell: Control = row["cell"]
		if i < fields.size():
			cell.visible = true
			var name_label: Label = row["name"]
			var value_label: Label = row["value"]
			name_label.text = String(fields[i][0])
			value_label.text = String(fields[i][1])
		else:
			cell.visible = false


func _enemy_fields(id: StringName) -> Array:
	var st := EnemyDB.stats(id)
	var fields: Array = []
	fields.append(["生命值", "%d" % int(round(float(st.get("hp", 0.0))))])
	fields.append(["护甲", "%d" % int(round(float(st.get("armor", 0.0))))])
	fields.append(["移动速度", "%.1f m/s" % float(st.get("speed", 0.0))])
	var damage := float(st.get("damage", 0.0))
	fields.append(["攻击伤害", "0（仅爆炸）" if damage <= 0.0 else "%d" % int(round(damage))])
	fields.append(["攻击距离", "%.1f m" % float(st.get("range", 0.0))])
	if bool(st.get("blind", false)):
		fields.append(["视野范围", "盲视"])
	else:
		fields.append(["视野范围", "%.0f m" % float(st.get("view_range", 0.0))])
	fields.append(["听觉范围", "%.0f m" % float(st.get("hearing", 0.0))])
	var cooldown := float(st.get("cooldown", 0.0))
	fields.append(["攻击间隔", "—" if cooldown >= 100.0 else "%.2f s" % cooldown])
	fields.append(["行为模式", String(BEHAVIOR_NAMES.get(String(st.get("behavior", "")), "常规"))])
	fields.append(["进阶掉落", "%.1f%%" % (float(st.get("advanced_drop", 0.0)) * 100.0)])
	if bool(st.get("death_explode", false)):
		fields.append(["爆炸半径", "%.0f m" % float(st.get("explode_radius", 0.0))])
		fields.append(["爆炸伤害", "%d" % int(round(float(st.get("explode_damage", 0.0))))])
		fields.append(["引爆延迟", "%.1f s" % float(st.get("explode_delay", 0.0))])
	return fields


func _weapon_fields(w: WeaponData) -> Array:
	var fields: Array = []
	fields.append(["口径", w.caliber_label])
	fields.append(["弹匣容量", "%d 发" % w.mag_capacity])
	if w.feed_mode == &"mag":
		fields.append(["供弹方式", "弹匣 · 自动"])
	else:
		fields.append(["供弹方式", "管式 · 泵动 %.2fs" % w.pump_time])
	var load_suffix := " / 发" if w.feed_mode == &"shell" else ""
	fields.append(["换弹时间", "%.2fs%s" % [w.load_time, load_suffix]])
	var rpm := int(round(60.0 / maxf(w.fire_interval, 0.001)))
	fields.append(["射速", "%.2f s/发 · ≈%d RPM" % [w.fire_interval, rpm]])
	fields.append(["射程", "%.0f m" % w.range_m])
	fields.append(["连发散布", "基础 %.1f° / 上限 %.1f°" % [
		rad_to_deg(w.base_spread), rad_to_deg(w.spread_max)]])
	fields.append(["枪声范围", "%.0f m" % w.sound_radius])
	var ammo = WeaponDB.ammo_table().get(w.ammo_id)
	if ammo == null:
		fields.append(["弹药", "—"])
		fields.append(["单发总伤害", "—"])
	else:
		if ammo.pellets > 1:
			fields.append(["弹药", "%s ×%d" % [ammo.display_name, ammo.pellets]])
			fields.append(["单发总伤害", "%d × %.1f = %.1f" % [
				ammo.pellets, ammo.damage, float(ammo.damage) * float(ammo.pellets)]])
		else:
			fields.append(["弹药", ammo.display_name])
			fields.append(["单发总伤害", "%.1f" % ammo.damage])
	return fields


func _ammo_fields(ammo: AmmoData) -> Array:
	var fields: Array = []
	var cat: Dictionary = WeaponDB.category_table().get(String(ammo.category), {})
	fields.append(["通用类别", String(cat.get("display_name", String(ammo.category)))])
	fields.append(["弹丸数", "%d" % ammo.pellets])
	fields.append(["单发伤害", "%.1f" % ammo.damage])
	fields.append(["单发总伤害", "%.1f" % (ammo.damage * float(ammo.pellets))])
	fields.append(["散布", "%.1f°" % rad_to_deg(ammo.spread)])
	fields.append(["穿甲", "%d" % int(round(ammo.ap))])
	fields.append(["备弹上限", "%d 发" % ammo.reserve_max])
	fields.append(["供给武器", _weapon_names_for_ammo(ammo.id)])
	return fields


func _weapon_names_for_ammo(ammo_id: StringName) -> String:
	var names: Array[String] = []
	for wid in WeaponDB.WEAPON_ORDER:
		var w := WeaponDB.get_weapon(wid)
		if w.ammo_id == ammo_id:
			names.append(w.display_name.split(" // ")[0])
	if names.is_empty():
		return "—"
	if names.size() <= 4:
		return "、".join(PackedStringArray(names))
	return "%s 等 %d 把" % ["、".join(PackedStringArray(names.slice(0, 4))), names.size()]


func _resource_fields(id: StringName, rec: Dictionary) -> Array:
	var fields: Array = []
	var basic := ResourceDB.is_basic(id)
	fields.append(["类别", "基础资源" if basic else "进阶资源"])
	fields.append(["阶位", String(rec.get("tier", "-")).to_upper()])
	if basic:
		fields.append(["掉落权重", "常见"])
	else:
		fields.append(["掉落权重", "%d%%" % int(ResourceDB.ADVANCED_WEIGHTS.get(id, 0))])
	fields.append(["主要用途", String(rec.get("desc", "-"))])
	fields.append(["获取方式", "容器 / 敌人 / 结算"])
	return fields


func _note_for_weapon(w: WeaponData) -> String:
	var role := "自卫手枪"
	match w.sfx_kind:
		"shotgun":
			role = "近距离压制武器"
		"sniper":
			role = "远距离精确射击武器"
		"rifle":
			role = "中远距离主力步枪"
		"smg":
			role = "高射速近战压制武器"
	var feed := "弹匣供弹" if w.feed_mode == &"mag" else "管式供弹"
	return "DOLL-01 军械库登记武器，发射 %s 弹药。\n%s，%s；有效射程约 %.0f m，枪声半径 %.0f m。\n在设施内行动时注意弹药储备与换弹窗口。" % [
		w.caliber_label, role, feed, w.range_m, w.sound_radius]


func _note_for_ammo(ammo: AmmoData) -> String:
	var cat: Dictionary = WeaponDB.category_table().get(String(ammo.category), {})
	return "%s，通用类别「%s」。\n%s\n每发 %d 颗弹丸，单发伤害 %.1f，穿甲 %d，通用备弹上限 %d 发。" % [
		ammo.display_name, String(cat.get("display_name", String(ammo.category))),
		String(cat.get("note", "设施标准配发弹药。")),
		ammo.pellets, ammo.damage, int(round(ammo.ap)), ammo.reserve_max]


func _note_for_resource(id: StringName, rec: Dictionary) -> String:
	var tier := String(rec.get("tier", "")).to_upper()
	return "编号 %s · %s 阶物资。\n%s。\n由设施内的容器、敌人残骸与行动结算回收，是 DOLL-01 改装与升级的基础物资。" % [
		String(id), tier, String(rec.get("desc", "用途待补充"))]


func _update_pager() -> void:
	var count := enemy_count() if _page == PAGE_ENEMY else item_count()
	var index := _enemy_index if _page == PAGE_ENEMY else _item_index
	if count <= 0 or index < 0 or index >= count:
		_page_label.text = "暂无档案"
		_prev_button.disabled = true
		_next_button.disabled = true
		return
	var group := "敌人"
	if _page == PAGE_ITEM:
		var kind := String(_item_entries[index]["kind"])
		group = "物品 · %s" % String(KIND_NAMES.get(kind, "档案"))
	_page_label.text = "%s %02d / %02d" % [group, index + 1, count]
	_prev_button.disabled = index <= 0
	_next_button.disabled = index >= count - 1


## 敌人配图：新单位取 SpriteFrames 首帧，静态单位退回 texture。
func _enemy_texture(id: StringName) -> Texture2D:
	var st := EnemyDB.stats(id)
	var frames_path := String(st.get("frames", ""))
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var frames := load(frames_path) as SpriteFrames
		if frames != null:
			for anim in ["move", "alert", "idle", "walk"]:
				var key := StringName(anim)
				if frames.has_animation(key) and frames.get_frame_count(key) > 0:
					return frames.get_frame_texture(key, 0)
			var names := frames.get_animation_names()
			if names.size() > 0 and frames.get_frame_count(names[0]) > 0:
				return frames.get_frame_texture(names[0], 0)
	var tex_path := String(st.get("texture", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		return load(tex_path) as Texture2D
	return null


func _item_texture(kind: String, id: StringName) -> Texture2D:
	var path := ""
	match kind:
		"weapon":
			path = "res://assets/art/weapons/%s/icon.png" % String(id)
		"ammo":
			path = ICON_ROOT + "ammo.png"
		"resource":
			path = ICON_ROOT + "res_%s.png" % String(id)
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func open() -> void:
	move_to_front()
	visible = true
	_show_page(_page)
	_prev_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## 用 _input 而不是 _unhandled_input：翻页按钮持有焦点时，方向键会先被 GUI 吃掉。
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			close_menu()
			get_viewport().set_input_as_handled()
		KEY_LEFT:
			_step(-1)
			get_viewport().set_input_as_handled()
		KEY_RIGHT:
			_step(1)
			get_viewport().set_input_as_handled()
