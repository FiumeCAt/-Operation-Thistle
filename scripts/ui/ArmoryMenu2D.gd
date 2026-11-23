extends Control
class_name ArmoryMenu2D
## 基地武备库：武器数据 / 护甲数据两个子页面，配置主/副两把携带武器。
## 配置写入 Progress.data["loadout_2d"]，开始行动后生效。

signal closed

const STATS_MODEL := preload("res://scripts/weapons/WeaponStatsModel.gd")
const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")
const TOOLTIP_VIEW := preload("res://scripts/ui/armory/ArmoryTooltipView.gd")
const ARMOR_VIEW := preload("res://scripts/ui/armory/ArmoryArmorView.gd")
const DETAIL_VIEW := preload("res://scripts/ui/armory/ArmoryDetailView.gd")
const PANEL_SIZE := Vector2(1240, 820)
## 武器数据行 / 效果映射 / 悬浮窗宽度统一收口至 ArmoryTooltipView，保留兼容别名。
const STAT_KEYS: Array[String] = TOOLTIP_VIEW.STAT_KEYS
const STAT_EFFECT := TOOLTIP_VIEW.STAT_EFFECT
const TIP_WIDTH := TOOLTIP_VIEW.TIP_WIDTH
## 激光/准心颜色预设。
const COLOR_PRESETS: Array[Color] = [
	Color(0.35, 1.0, 0.50), Color(1.0, 0.30, 0.22), Color(0.35, 0.80, 1.0),
	Color(1.0, 0.72, 0.25), Color(0.75, 0.45, 1.0), Color(0.92, 0.95, 1.0),
	Color(0.03, 0.03, 0.04),
]

var _selected: StringName = &"m870"
var _primary: StringName = &"m870"
var _secondary: StringName = &"g17"
var _detail_view: ArmoryDetailView = DETAIL_VIEW.new()
var _weapon_buttons: Dictionary:
	get: return _detail_view.weapon_buttons
var _weapon_list: VBoxContainer:
	get: return _detail_view.weapon_list
var _mod_items: VBoxContainer
## 武器列表滚动容器：18 把枪时用于程序化定位与截图。
var _list_scroll: ScrollContainer:
	get: return _detail_view.list_scroll
var _detail_values: Dictionary:
	get: return _detail_view.detail_values
var _detail_deltas: Dictionary:
	get: return _detail_view.detail_deltas
var _detail_base: Dictionary:
	get: return _detail_view.detail_base
var _detail_rows: Dictionary:
	get: return _detail_view.detail_rows
var _tooltip_view: ArmoryTooltipView = TOOLTIP_VIEW.new()
var _detail_tips: Dictionary:
	get: return _tooltip_view.tips
	set(v): _tooltip_view.tips = v
var _tip_panel: PanelContainer:
	get: return _tooltip_view.tip_panel
	set(v): _tooltip_view.tip_panel = v
var _tip_label: Label:
	get: return _tooltip_view.tip_label
	set(v): _tooltip_view.tip_label = v
var _detail_title: Label:
	get: return _detail_view.detail_title
var _detail_icon: TextureRect:
	get: return _detail_view.detail_icon
var _loadout_label: Label
var _feedback: Label
var _primary_button: Button:
	get: return _detail_view.primary_button
var _secondary_button: Button:
	get: return _detail_view.secondary_button
var _page := "weapon"
var _weapon_sub := "data"
var _weapon_page: Control
var _weapon_data_page: Control:
	get: return _detail_view.page
var _armor_view: ArmoryArmorView = ARMOR_VIEW.new()
var _armor_page: Control:
	get: return _armor_view.page
var _tab_weapon: Button
var _tab_armor: Button
var _sub_tab_data: Button
var _sub_tab_mods: Button
var _armor_values: Dictionary:
	get: return _armor_view.values
var _mods_page: Control
var _mod_item := "m870"
var _mod_item_buttons: Dictionary = {}
var _mod_choices: Dictionary = {}
var _mod_slots_box: VBoxContainer
var _mod_feedback: Label
## 塔科夫式改枪视图：枪身贴图 + 部件锚点连线 + 槽位按钮。
var _mod_gun_view: Control
var _mod_slot_buttons: Dictionary = {}
var _mod_gun_tex: Texture2D
var _mod_gun_rect := Rect2()
var _mod_gun_anchors: Dictionary = {}
var _mod_slot_targets: Dictionary = {}
var _mod_selected_slot := "muzzle"
var _mod_detail: PanelContainer
var _mod_detail_title: Label
var _mod_detail_state: Label
var _mod_detail_option: Label
var _mod_detail_cost: Label
## 准星切换：当前选中武器已装配瞄具的样式按钮。
var _reticle_box: VBoxContainer
var _reticle_row: HBoxContainer
var _reticle_buttons: Dictionary = {}
var _mod_install: Button
var _mod_preview_option := ""
## 改枪页右侧的实时数据窗：预览配件时同步变化，方便对比。
var _mod_stats_panel: PanelContainer
var _mod_stat_values: Dictionary = {}
var _mod_stat_deltas: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	var title := PixelUI.label(header, "武备库 // ARSENAL", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "LOADOUT // 2 SLOTS", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	rows.add_child(tabs)
	_tab_weapon = PixelUI.button("▶ 武器数据 // WEAPONS", 44)
	_tab_weapon.custom_minimum_size.x = 300
	_tab_weapon.pressed.connect(func() -> void: _show_page("weapon"))
	tabs.add_child(_tab_weapon)
	_tab_armor = PixelUI.button("护甲数据 // ARMOR", 44)
	_tab_armor.custom_minimum_size.x = 300
	_tab_armor.pressed.connect(func() -> void: _show_page("armor"))
	tabs.add_child(_tab_armor)

	# 武器页：数据 / 配件两个子页
	var weapon_page := VBoxContainer.new()
	weapon_page.add_theme_constant_override("separation", 8)
	weapon_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(weapon_page)
	_weapon_page = weapon_page

	var sub_tabs := HBoxContainer.new()
	sub_tabs.add_theme_constant_override("separation", 8)
	weapon_page.add_child(sub_tabs)
	_sub_tab_data = PixelUI.button("▶ 武器数据", 36)
	_sub_tab_data.custom_minimum_size.x = 240
	_sub_tab_data.pressed.connect(func() -> void: _show_weapon_sub("data"))
	sub_tabs.add_child(_sub_tab_data)
	_sub_tab_mods = PixelUI.button("配件与组件", 36)
	_sub_tab_mods.custom_minimum_size.x = 240
	_sub_tab_mods.pressed.connect(func() -> void: _show_weapon_sub("mods"))
	sub_tabs.add_child(_sub_tab_mods)

	_detail_view.build(weapon_page)
	_detail_view.weapon_selected.connect(_select)
	_detail_view.equip_requested.connect(_equip)
	_detail_view.tip_show_requested.connect(_show_tip)
	_detail_view.tip_hide_requested.connect(_hide_tip)

	_build_armor_page(rows)
	_build_mods_page(weapon_page)

	var footer_divider := HSeparator.new()
	footer_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(footer_divider)
	_loadout_label = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.TEXT)
	_feedback = PixelUI.label(rows, "点击武器查看数据 · 装备后开始行动生效", PixelUI.FS_BODY, PixelUI.DIM)
	var close_button := PixelUI.button("返回基地", 46)
	close_button.custom_minimum_size.x = 300
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_menu)
	rows.add_child(close_button)

	_build_tooltip()


## --- 悬浮提示（委托至 ArmoryTooltipView）---------------------------------------

func _build_tooltip() -> void:
	_tooltip_view.build(self)


func _show_tip(key: String) -> void:
	_tooltip_view.show_tip(key)


func _hide_tip() -> void:
	_tooltip_view.hide_tip()


func _process(_delta: float) -> void:
	if _tooltip_view.is_visible():
		_tooltip_view.place_tip()


func _set_stat(key: String, text: String, base_text: String,
		delta: float, higher_is_better: bool, digits: int) -> void:
	_detail_view.set_stat(key, text, base_text, delta, higher_is_better, digits)


func _refresh_tooltips(installed: Dictionary, reload_talent: float, ammo) -> void:
	_tooltip_view.refresh_tooltips(_selected, installed, reload_talent, ammo,
		_detail_base, _detail_values, get_node_or_null("/root/Progress"))


## --- 护甲子页（委托至 ArmoryArmorView）----------------------------------------

func _build_armor_page(parent: Node) -> void:
	_armor_view.build(parent)


func _armor_display_mode() -> String:
	return MOD_SERVICE.armor_display_mode(get_node_or_null("/root/Progress"))


func _refresh_armor() -> void:
	_armor_view.refresh(get_node_or_null("/root/Progress"))


func _show_page(page: String) -> void:
	_page = page
	_hide_tip()
	var weapon_mode := page != "armor"
	if _weapon_page != null:
		_weapon_page.visible = weapon_mode
	if _armor_page != null:
		_armor_page.visible = not weapon_mode
	_tab_weapon.text = ("▶ " if weapon_mode else "   ") + "武器数据 // WEAPONS"
	_tab_armor.text = ("▶ " if not weapon_mode else "   ") + "护甲数据 // ARMOR"
	if weapon_mode:
		_show_weapon_sub("mods" if page == "mods" else "data")
	else:
		_feedback.text = "护甲数据 · 受击结算规则"
		_refresh_armor()


## 武器页内部子页：数据 / 配件。
func _show_weapon_sub(sub: String) -> void:
	_weapon_sub = sub
	if _weapon_data_page != null:
		_weapon_data_page.visible = sub == "data"
	if _mods_page != null:
		_mods_page.visible = sub == "mods"
	_sub_tab_data.text = ("▶ " if sub == "data" else "   ") + "武器数据"
	_sub_tab_mods.text = ("▶ " if sub == "mods" else "   ") + "配件与组件"
	if sub == "mods":
		_feedback.text = "配件与组件 · 安装后开始行动生效"
		if _mod_feedback != null:
			_mod_feedback.text = "点击选项切换预览 · 安装消耗信用点与进阶资源"
			_mod_feedback.add_theme_color_override("font_color", PixelUI.DIM)
		_refresh_mods()
	else:
		_feedback.text = "点击武器查看数据 · 装备后开始行动生效"
		# 从配件页返回时重新读取实际数据，避免显示安装前的旧数值。
		_refresh()


## 配件子页：左侧选择枪械/护甲，右侧塔科夫式改枪视图 + 槽位详情。
func _build_mods_page(parent: Node) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.visible = false
	parent.add_child(page)
	_mods_page = page

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	var items_scroll := ScrollContainer.new()
	items_scroll.custom_minimum_size.x = 220
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(items_scroll)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 8)
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.add_child(items)
	_mod_items = items
	for id in WeaponDB.WEAPON_ORDER:
		var button := PixelUI.button("", 58)
		button.custom_minimum_size.x = 200
		button.pressed.connect(_select_mod_item.bind(String(id)))
		items.add_child(button)
		_mod_item_buttons[String(id)] = button
	var armor_button := PixelUI.button("", 58)
	armor_button.custom_minimum_size.x = 200
	armor_button.pressed.connect(_select_mod_item.bind("armor"))
	items.add_child(armor_button)
	_mod_item_buttons["armor"] = armor_button

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)

	# 上半：枪身工位（配件框环绕枪身，连线指向真实部位）+ 右侧槽位详情。
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(top)

	_mod_gun_view = Control.new()
	_mod_gun_view.custom_minimum_size = Vector2(420, 280)
	_mod_gun_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mod_gun_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mod_gun_view.draw.connect(_draw_mod_gun)
	_mod_gun_view.resized.connect(_on_mod_gun_view_resized)
	top.add_child(_mod_gun_view)
	for slot_def in ModDB.WEAPON_SLOTS:
		var slot := String(slot_def["id"])
		var button := PixelUI.button("", 52)
		button.size = Vector2(130, 52)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_select_mod_slot.bind(slot))
		_mod_gun_view.add_child(button)
		_mod_slot_buttons[slot] = button

	_build_mod_detail(top)

	# 护甲沿用列表式三槽位。
	_mod_slots_box = VBoxContainer.new()
	_mod_slots_box.add_theme_constant_override("separation", 10)
	_mod_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_mod_slots_box)

	# 下半：横向数据条，预览配件时实时变化。
	_build_mod_stats(right)
	_build_color_picker(right)
	_build_reticle_switch(right)

	_mod_feedback = PixelUI.label(right, "", PixelUI.FS_BODY, PixelUI.DIM)
	_mod_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## 外观颜色：激光与准心各一排色块，写入 Progress 后立即生效。
func _build_color_picker(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	row.add_child(_color_group("激光颜色", "laser"))
	row.add_child(_color_group("准心颜色", "reticle"))


## 准星切换：为当前武器已装配的瞄具切换样式（每个瞄具独立保存）。
func _build_reticle_switch(parent: Node) -> void:
	_reticle_box = VBoxContainer.new()
	_reticle_box.add_theme_constant_override("separation", 4)
	parent.add_child(_reticle_box)
	PixelUI.label(_reticle_box, "准星样式", 18, PixelUI.DIM)
	_reticle_row = HBoxContainer.new()
	_reticle_row.add_theme_constant_override("separation", 6)
	_reticle_box.add_child(_reticle_row)


func _refresh_reticle_switch() -> void:
	if _reticle_box == null or _reticle_row == null:
		return
	for child in _reticle_row.get_children():
		child.queue_free()
	_reticle_buttons.clear()
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_reticle_box.visible = false
		return
	var installed: Dictionary = p.weapon_mods_2d(_mod_item)
	var sight_id := String(installed.get("sight", ""))
	var entry := ModDB.option("sight", sight_id, false, _mod_item)
	if sight_id == "" or sight_id == "iron" or entry.is_empty():
		_reticle_box.visible = false
		return
	_reticle_box.visible = true
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
		_reticle_row.add_child(button)
		_reticle_buttons[style] = button


func _set_reticle_style(sight_id: String, style: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_reticle_style(sight_id, style)
	_refresh_reticle_switch()
	_refresh_mods()


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
	var p := get_node_or_null("/root/Progress")
	if p != null:
		picker.color = p.laser_color() if kind == "laser" else p.reticle_color()
	picker.color_changed.connect(func(c: Color) -> void:
		_set_sight_color(kind, c))
	box.add_child(picker)
	return box


func _set_sight_color(kind: String, color: Color) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	if kind == "laser":
		p.set_laser_color(color)
	else:
		p.set_reticle_color(color)
	if _mod_feedback != null:
		_mod_feedback.text = "外观颜色已更新 · 进入行动后生效"
		_mod_feedback.add_theme_color_override("font_color", PixelUI.OK)


## 下半：横向数据条（4 列 × 2 行），预览配件时实时变化。
func _build_mod_stats(parent: Node) -> void:
	_mod_stats_panel = PanelContainer.new()
	_mod_stats_panel.custom_minimum_size.y = 112
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_mod_stats_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(_mod_stats_panel)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	_mod_stats_panel.add_child(grid)

	var defs := [
		["mag", "弹匣"], ["rate", "射速"], ["load", "换弹"], ["range", "射程"],
		["speed", "弹速"], ["spread", "散布"], ["sound", "枪声"], ["damage", "伤害"],
		["ap", "穿甲"], ["mode", "模式"], ["slots", "槽位"], ["recoil", "后坐"],
		["vision", "视野"], ["ads", "瞄准"],
	]
	for entry in defs:
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
		_mod_stat_values[String(entry[0])] = value
		_mod_stat_deltas[String(entry[0])] = delta


## 右侧槽位详情：标题、当前装配、预览配件与安装按钮。
func _build_mod_detail(parent: Node) -> void:
	_mod_detail = PixelUI.panel(PixelUI.BG_LIGHT)
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_mod_detail.add_theme_stylebox_override("panel", style)
	_mod_detail.custom_minimum_size = Vector2(250, 280)
	parent.add_child(_mod_detail)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_mod_detail.add_child(rows)
	_mod_detail_title = PixelUI.label(rows, "", 18, PixelUI.AMBER)
	_mod_detail_state = PixelUI.label(rows, "", 18, PixelUI.DIM)
	_mod_detail_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mod_detail_option = PixelUI.label(rows, "", 18, PixelUI.TEXT)
	_mod_detail_option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mod_detail_option.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mod_detail_cost = PixelUI.label(rows, "", 17, PixelUI.DIM)
	_mod_detail_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	rows.add_child(buttons)
	var prev := PixelUI.button("<", 42)
	prev.custom_minimum_size.x = 40
	prev.pressed.connect(_cycle_mod_selected.bind(-1))
	buttons.add_child(prev)
	_mod_install = PixelUI.button("安装", 42)
	_mod_install.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mod_install.add_theme_font_size_override("font_size", 16)
	_mod_install.pressed.connect(_install_preview)
	buttons.add_child(_mod_install)
	var next := PixelUI.button(">", 42)
	next.custom_minimum_size.x = 40
	next.pressed.connect(_cycle_mod_selected.bind(1))
	buttons.add_child(next)


func _select_mod_item(item: String) -> void:
	_mod_item = item
	_mod_choices.clear()
	_mod_selected_slot = "muzzle"
	if _mod_feedback != null:
		_mod_feedback.text = "点击枪身连线或槽位切换 · 安装消耗信用点与进阶资源"
		_mod_feedback.add_theme_color_override("font_color", PixelUI.DIM)
	_refresh_mods()


func _select_mod_slot(slot: String) -> void:
	_mod_selected_slot = slot
	_mod_choices.erase(slot)
	_refresh_mods()


func _refresh_mods() -> void:
	if _mod_slots_box == null:
		return
	_read_loadout()
	_apply_pinned_order(_mod_items, _mod_item_buttons, true)
	var is_armor := _mod_item == "armor"
	var p := get_node_or_null("/root/Progress")
	var installed: Dictionary = {}
	if p != null:
		installed = p.armor_mods_2d() if is_armor \
			else p.weapon_mods_2d(StringName(_mod_item))

	for id in _mod_item_buttons:
		var button: Button = _mod_item_buttons[id]
		var count := 0
		if p != null:
			var mods: Dictionary = p.armor_mods_2d() if id == "armor" \
				else p.weapon_mods_2d(StringName(id))
			count = mods.size()
		var label := "护甲 // DOLL-01" if id == "armor" \
			else String(WeaponDB.get_weapon(StringName(id)).display_name).split(" // ")[0]
		var slot_mark := ""
		if StringName(id) == _primary:
			slot_mark = " [主]"
		elif StringName(id) == _secondary:
			slot_mark = " [副]"
		var total_slots: int = ModDB.ARMOR_SLOTS.size() if id == "armor" \
			else ModDB.WEAPON_SLOTS.size()
		button.text = "%s%s%s  [%d/%d]" % [
			"▶ " if id == _mod_item else "   ", label, slot_mark, count, total_slots]
		button.add_theme_font_size_override("font_size", 20)

	_mod_gun_view.visible = not is_armor
	_mod_stats_panel.visible = not is_armor
	_mod_detail.visible = not is_armor
	_mod_slots_box.visible = is_armor
	if is_armor:
		_refresh_armor_mod_rows(installed)
	else:
		_refresh_mod_gun_view()
		_refresh_mod_slot_buttons(installed)
		_refresh_mod_detail(installed)
	_refresh_reticle_switch()


## 护甲：保留原来的三行槽位列表。
func _refresh_armor_mod_rows(installed: Dictionary) -> void:
	for child in _mod_slots_box.get_children():
		_mod_slots_box.remove_child(child)
		child.queue_free()

	for slot_def in ModDB.slots(true):
		var slot := String(slot_def["id"])
		var options := ModDB.options(slot, true, _mod_item)
		if options.is_empty():
			continue
		var current := String(installed.get(slot, ""))
		var choice := int(_mod_choices.get(slot, -1))
		if choice < 0:
			choice = 0
			for i in options.size():
				if String(options[i]["id"]) == current:
					choice = i
					break
		choice = clampi(choice, 0, options.size() - 1)
		_mod_choices[slot] = choice
		var entry: Dictionary = options[choice]
		var option_id := String(entry["id"])

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_mod_slots_box.add_child(row)

		var slot_label := PixelUI.label(row, String(slot_def["name"]), PixelUI.FS_BODY, PixelUI.DIM)
		slot_label.custom_minimum_size.x = 84
		slot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var option_button := PixelUI.button("", 84)
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_button.add_theme_font_size_override("font_size", 18)
		option_button.text = "%s%s\n%s" % [
			String(entry["name"]),
			"  【已装配】" if option_id == current else "  【预览】",
			String(entry["desc"]),
		]
		option_button.pressed.connect(_cycle_mod.bind(slot))
		row.add_child(option_button)

		var install_button := PixelUI.button("", 84)
		install_button.custom_minimum_size.x = 300
		install_button.add_theme_font_size_override("font_size", 18)
		if option_id == current:
			install_button.text = "已装配\n无需安装"
			install_button.disabled = true
		else:
			install_button.text = "安装\n%s\n%s" % [
				_cost_line(entry), _material_line(entry)]
			install_button.disabled = not _can_pay_mod(entry)
		install_button.pressed.connect(_install_mod.bind(slot, option_id))
		row.add_child(install_button)


## 枪身展示：读取 meta.json 的握把/枪口锚点，计算枪口、枪机、弹匣三个连接点。
func _refresh_mod_gun_view() -> void:
	if _mod_gun_view == null or _mod_slot_buttons.is_empty():
		return
	var path := "res://assets/art/weapons/%s/side.png" % _mod_item
	_mod_gun_tex = load(path) if ResourceLoader.exists(path) else null
	if _mod_gun_tex == null:
		_mod_gun_view.queue_redraw()
		return
	var width := _mod_gun_view.size.x
	if width < 1.0:
		width = 580.0
	var height := _mod_gun_view.size.y
	if height < 1.0:
		height = 280.0

	# 枪身放在上下配件框之间。
	var area := Rect2(14.0, 66.0, width - 28.0, height - 132.0)
	var tex_size := _mod_gun_tex.get_size()
	var fit := minf(area.size.x / tex_size.x, area.size.y / tex_size.y)
	var draw_size := tex_size * fit
	_mod_gun_rect = Rect2(area.position + (area.size - draw_size) * 0.5, draw_size)

	var grip := Vector2(276, 552)
	var muzzle := Vector2(1361, 99)
	var bolt_px := Vector2.ZERO
	var mag_px := Vector2.ZERO
	var muzzle_mod_px := Vector2.ZERO
	var meta_path := "res://assets/art/weapons/%s/meta.json" % _mod_item
	if FileAccess.file_exists(meta_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if parsed is Dictionary and parsed.has("grip_px") and parsed.has("muzzle_px"):
			grip = Vector2(parsed.grip_px[0], parsed.grip_px[1])
			muzzle = Vector2(parsed.muzzle_px[0], parsed.muzzle_px[1])
			if parsed.has("bolt_px"):
				bolt_px = Vector2(parsed.bolt_px[0], parsed.bolt_px[1])
			if parsed.has("magazine_px"):
				mag_px = Vector2(parsed.magazine_px[0], parsed.magazine_px[1])
			if parsed.has("muzzle_mod_px"):
				muzzle_mod_px = Vector2(parsed.muzzle_mod_px[0], parsed.muzzle_mod_px[1])
	var to_view := func(px: Vector2) -> Vector2:
		return _mod_gun_rect.position + Vector2(
			px.x / tex_size.x, px.y / tex_size.y) * _mod_gun_rect.size
	var g: Vector2 = to_view.call(grip)
	var m: Vector2 = to_view.call(muzzle)
	var dir := (m - g).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	if perp.y < 0.0:
		perp = -perp
	var length := g.distance_to(m)
	# 优先使用 meta 中标注的真实部位像素坐标，缺失时退回按枪身比例估算。
	# 新增槽位没有 meta 锚点：瞄具在机匣上方，后托在握把后方，握把/下挂在护木下方。
	_mod_gun_anchors = {
		"muzzle": to_view.call(muzzle_mod_px) if muzzle_mod_px != Vector2.ZERO else m,
		"core": to_view.call(bolt_px) if bolt_px != Vector2.ZERO \
			else g + dir * length * 0.16 - perp * length * 0.10,
		"magazine": to_view.call(mag_px) if mag_px != Vector2.ZERO \
			else g + dir * length * 0.10 + perp * length * 0.20,
		"sight": g + dir * length * 0.42 - perp * length * 0.10,
		"stock": g - dir * length * 0.22,
		"grip": g + dir * length * 0.34 + perp * length * 0.12,
	}

	# 两排三列：上排 枪机/瞄具/枪口，下排 后托/弹匣/握把下挂。
	var box_size := Vector2(130, 52)
	var pad := 10.0
	var gap := 12.0
	var total_w := box_size.x * 3.0 + gap * 2.0
	var start_x := maxf(pad, (width - total_w) * 0.5)
	var top_y := 6.0
	var bottom_y := height - box_size.y - 6.0
	var boxes := {
		"core": Vector2(start_x, top_y),
		"sight": Vector2(start_x + box_size.x + gap, top_y),
		"muzzle": Vector2(start_x + (box_size.x + gap) * 2.0, top_y),
		"stock": Vector2(start_x, bottom_y),
		"magazine": Vector2(start_x + box_size.x + gap, bottom_y),
		"grip": Vector2(start_x + (box_size.x + gap) * 2.0, bottom_y),
	}
	for slot in boxes:
		var button: Button = _mod_slot_buttons[slot]
		button.position = boxes[slot]
		button.size = box_size
		var center_x: float = boxes[slot].x + box_size.x * 0.5
		var top_row: bool = boxes[slot].y < height * 0.5
		_mod_slot_targets[slot] = Vector2(center_x,
			boxes[slot].y + box_size.y if top_row else boxes[slot].y)
	_mod_gun_view.queue_redraw()


func _draw_mod_gun() -> void:
	if _mod_gun_view == null or _mod_gun_tex == null:
		return
	_mod_gun_view.draw_texture_rect(_mod_gun_tex, _mod_gun_rect, false)
	for slot in _mod_gun_anchors:
		var anchor: Vector2 = _mod_gun_anchors[slot]
		var target: Vector2 = _mod_slot_targets.get(slot, Vector2.ZERO)
		if target == Vector2.ZERO:
			continue
		var active: bool = String(slot) == _mod_selected_slot
		var color := PixelUI.AMBER_BRIGHT if active else Color(PixelUI.AMBER, 0.55)
		_mod_gun_view.draw_line(anchor, target, color, 3.0 if active else 1.5)
		_mod_gun_view.draw_circle(anchor, 4.5 if active else 3.0, color)


func _on_mod_gun_view_resized() -> void:
	if _mod_gun_view != null and _mod_gun_view.visible:
		_refresh_mod_gun_view()


func _refresh_mod_slot_buttons(installed: Dictionary) -> void:
	for slot_def in ModDB.WEAPON_SLOTS:
		var slot := String(slot_def["id"])
		var button: Button = _mod_slot_buttons[slot]
		var current := String(installed.get(slot, ""))
		var entry := ModDB.option(slot, current, false, _mod_item)
		var state := "未装配" if entry.is_empty() else String(entry["name"])
		button.text = "%s%s\n%s" % [
			"▶ " if slot == _mod_selected_slot else "",
			String(slot_def["name"]), state]
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if slot == _mod_selected_slot else PixelUI.TEXT)


func _refresh_mod_detail(installed: Dictionary) -> void:
	var slot := _mod_selected_slot
	var options := ModDB.options(slot, false, _mod_item)
	if options.is_empty():
		return
	var current := String(installed.get(slot, ""))
	var choice := int(_mod_choices.get(slot, -1))
	if choice < 0:
		choice = 0
		for i in options.size():
			if String(options[i]["id"]) == current:
				choice = i
				break
	choice = clampi(choice, 0, options.size() - 1)
	_mod_choices[slot] = choice
	var entry: Dictionary = options[choice]
	_mod_preview_option = String(entry["id"])
	var slot_name := ""
	for slot_def in ModDB.WEAPON_SLOTS:
		if String(slot_def["id"]) == slot:
			slot_name = String(slot_def["name"])
			break
	var installed_entry := ModDB.option(slot, current, false, _mod_item)
	var installed_name := "未装配" if installed_entry.is_empty() \
		else String(installed_entry["name"])
	_mod_detail_title.text = "%s // %s" % [slot_name, MOD_SERVICE.slot_english_name(slot)]
	_mod_detail_state.text = "当前：%s" % installed_name
	_mod_detail_cost.text = "消耗：%s\n%s" % [_cost_line(entry), _material_line(entry)]
	var option_text := "%s%s\n%s" % [
		"预览：" if _mod_preview_option != current else "",
		String(entry["name"]), String(entry["desc"])]
	if slot == "sight":
		option_text += "\n" + _sight_stats_line(entry)
	_mod_detail_option.text = option_text
	_mod_install.text = "已装配" if _mod_preview_option == current else "安装"
	_mod_install.disabled = _mod_preview_option == current or not _can_pay_mod(entry)
	# 实时数据窗：把当前预览当作已装配，计算与当前配置的差值。
	var preview := installed.duplicate()
	preview[slot] = _mod_preview_option
	_refresh_mod_stats(installed, preview)


## 瞄具固定属性摘要：倍率 / 视野 / 射程 / 瞄准时间。
func _sight_stats_line(entry: Dictionary) -> String:
	return MOD_SERVICE.sight_stats_line(entry)


## 按给定装配表计算武器实际数据（统一委托 WeaponStatsModel，与 WeaponRig2D 完全同源）。
func _mod_weapon_stats(weapon_id: StringName, installed: Dictionary) -> Dictionary:
	var p := get_node_or_null("/root/Progress")
	return STATS_MODEL.compute_for_progress(weapon_id, p, installed)


func _refresh_mod_stats(current_installed: Dictionary, preview_installed: Dictionary) -> void:
	var cur := _mod_weapon_stats(StringName(_mod_item), current_installed)
	var pre := _mod_weapon_stats(StringName(_mod_item), preview_installed)
	var p := get_node_or_null("/root/Progress")
	var fire_mode := "interval"
	if p != null:
		fire_mode = String(p.data.get("fire_rate_display", "interval"))
	_set_mod_stat("mag", "%d 发" % int(pre["mag"]),
		float(pre["mag"]) - float(cur["mag"]), true, 0)
	if fire_mode == "rpm":
		var rpm := 60.0 / maxf(float(pre["interval"]), 0.001)
		var cur_rpm := 60.0 / maxf(float(cur["interval"]), 0.001)
		_set_mod_stat("rate", "%d RPM" % int(round(rpm)), rpm - cur_rpm, true, 0)
	else:
		_set_mod_stat("rate", "%.2fs/发" % float(pre["interval"]),
			float(pre["interval"]) - float(cur["interval"]), false, 2)
	_set_mod_stat("load", "%.2fs" % float(pre["load"]),
		float(pre["load"]) - float(cur["load"]), false, 2)
	_set_mod_stat("range", "%.0fm" % float(pre["range"]),
		float(pre["range"]) - float(cur["range"]), true, 0)
	_set_mod_stat("speed", "%d m/s" % int(round(float(pre["speed"]))),
		float(pre["speed"]) - float(cur["speed"]), true, 0)
	_set_mod_stat("spread", "%.1f°" % rad_to_deg(float(pre["spread"])),
		rad_to_deg(float(pre["spread"]) - float(cur["spread"])), false, 1)
	_set_mod_stat("ap", DAMAGE_MODEL.format_rha(float(pre["ap"]), _armor_display_mode()),
		float(pre["ap"]) - float(cur["ap"]), true, 0)
	_set_mod_stat("sound", "%.0fm" % float(pre["sound"]),
		float(pre["sound"]) - float(cur["sound"]), false, 0)
	_set_mod_stat("damage", "%.1f" % float(pre["damage"]),
		float(pre["damage"]) - float(cur["damage"]), true, 1)
	var mode_label: Label = _mod_stat_values["mode"]
	mode_label.text = "全自动" if bool(pre["auto"]) else "单发"
	mode_label.add_theme_color_override("font_color",
		PixelUI.AMBER_BRIGHT if bool(pre["auto"]) else PixelUI.TEXT)
	var mode_delta: Label = _mod_stat_deltas["mode"]
	mode_delta.text = "" if bool(pre["auto"]) == bool(cur["auto"]) else "切换"
	var filled := 0
	for slot_def in ModDB.WEAPON_SLOTS:
		if String(current_installed.get(String(slot_def["id"]), "")) != "":
			filled += 1
	_set_mod_stat("slots", "%d / %d" % [filled, ModDB.WEAPON_SLOTS.size()], 0.0, true, 0)
	_set_mod_stat("recoil", "%d%%" % int(round(float(pre["recoil"]) * 100.0)),
		(float(pre["recoil"]) - float(cur["recoil"])) * 100.0, true, 0)
	_set_mod_stat("vision", "+%d%%" % int(round(float(pre["vision"]) * 100.0)),
		(float(pre["vision"]) - float(cur["vision"])) * 100.0, true, 0)
	_set_mod_stat("ads", "+%d%%" % int(round(float(pre["ads"]) * 100.0)),
		(float(pre["ads"]) - float(cur["ads"])) * 100.0, true, 0)


func _set_mod_stat(key: String, text: String, delta: float,
		higher_is_better: bool, digits: int) -> void:
	var value: Label = _mod_stat_values.get(key)
	var delta_label: Label = _mod_stat_deltas.get(key)
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


func _cycle_mod_selected(step: int) -> void:
	var options := ModDB.options(_mod_selected_slot, false, _mod_item)
	if options.is_empty():
		return
	var choice := int(_mod_choices.get(_mod_selected_slot, 0))
	_mod_choices[_mod_selected_slot] = (choice + step + options.size()) % options.size()
	var p := get_node_or_null("/root/Progress")
	var installed: Dictionary = {}
	if p != null:
		installed = p.weapon_mods_2d(StringName(_mod_item))
	_refresh_mod_detail(installed)


func _install_preview() -> void:
	if _mod_preview_option == "":
		return
	_install_mod(_mod_selected_slot, _mod_preview_option)


func _cycle_mod(slot: String) -> void:
	var is_armor := _mod_item == "armor"
	var options := ModDB.options(slot, is_armor, _mod_item)
	if options.is_empty():
		return
	var choice := int(_mod_choices.get(slot, 0))
	_mod_choices[slot] = (choice + 1) % options.size()
	_refresh_mods()


func _install_mod(slot: String, option_id: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	var res := MOD_SERVICE.install_mod(p, _mod_item, slot, option_id)
	if bool(res["ok"]):
		_mod_feedback.text = String(res["message"])
		_mod_feedback.add_theme_color_override("font_color", PixelUI.OK)
		# 安装后预览跟随新配件
		_mod_choices.erase(slot)
	else:
		_mod_feedback.text = String(res["message"])
		_mod_feedback.add_theme_color_override("font_color", PixelUI.DANGER)
	_refresh_mods()


func _cost_line(entry: Dictionary) -> String:
	return MOD_SERVICE.cost_line(entry)


func _material_line(entry: Dictionary) -> String:
	return MOD_SERVICE.material_line(entry)


func _can_pay_mod(entry: Dictionary) -> bool:
	return MOD_SERVICE.can_pay_mod(get_node_or_null("/root/Progress"), entry)


func open() -> void:
	_read_loadout()
	_selected = _primary
	_feedback.text = "点击武器查看数据 · 装备后开始行动生效"
	_show_page("weapon")
	_refresh()
	move_to_front()
	visible = true


func close_menu() -> void:
	if not visible:
		return
	_hide_tip()
	visible = false
	closed.emit()


func _select(id: StringName) -> void:
	_selected = id
	_feedback.text = "点击武器查看数据 · 装备后开始行动生效"
	_refresh()


## 当前装备的主/副武器固定到列表最上方，其余保持原顺序。
func _pinned_weapon_order() -> Array[String]:
	return MOD_SERVICE.pinned_weapon_order(_primary, _secondary)


func _apply_pinned_order(list: VBoxContainer, buttons: Dictionary, string_keys: bool) -> void:
	if list == null:
		return
	var index := 0
	for sid in _pinned_weapon_order():
		var key = sid if string_keys else StringName(sid)
		if buttons.has(key):
			list.move_child(buttons[key], index)
			index += 1


func _read_loadout() -> void:
	var slots := MOD_SERVICE.read_loadout(get_node_or_null("/root/Progress"), _primary, _secondary)
	_primary = slots["primary"]
	_secondary = slots["secondary"]


## 数据页读取「基础值 × 配件加成」的实际值，统一委托 ArmoryDetailView。
func _refresh() -> void:
	_read_loadout()
	_hide_tip()
	_detail_view.refresh(_selected, _primary, _secondary,
		get_node_or_null("/root/Progress"), _tooltip_view)
	_loadout_label.text = "当前携带：主武器 %s · 副武器 %s" % [
		WeaponDB.get_weapon(_primary).display_name,
		WeaponDB.get_weapon(_secondary).display_name,
	]
	_refresh_armor()


func _equip(primary_slot: bool) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	var res := MOD_SERVICE.equip_weapon(p, _selected, _primary, _secondary, primary_slot)
	_feedback.text = String(res["message"])
	if not bool(res["ok"]):
		return
	_primary = res["primary"]
	_secondary = res["secondary"]
	_refresh()
	_refresh_mods()
