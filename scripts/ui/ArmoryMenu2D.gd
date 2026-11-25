extends Control
class_name ArmoryMenu2D
## 基地武备库协调外壳：承载标签导航、底部携行摘要与 5 个独立子视图/服务。
## 配置写入 Progress.data["loadout_2d"]，开始行动后生效。

signal closed

const STATS_MODEL := preload("res://scripts/weapons/WeaponStatsModel.gd")
const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")
const TOOLTIP_VIEW := preload("res://scripts/ui/armory/ArmoryTooltipView.gd")
const ARMOR_VIEW := preload("res://scripts/ui/armory/ArmoryArmorView.gd")
const DETAIL_VIEW := preload("res://scripts/ui/armory/ArmoryDetailView.gd")
const MOD_CANVAS_VIEW := preload("res://scripts/ui/armory/ArmoryModCanvasView.gd")
const MOD_STATS_STRIP := preload("res://scripts/ui/armory/ArmoryModStatsStrip.gd")

const PANEL_SIZE := Vector2(1280, 856)
## 兼容别名：统一收口至各子视图常量，保持既有测试引用不断裂。
const STAT_KEYS: Array[String] = TOOLTIP_VIEW.STAT_KEYS
const STAT_EFFECT := TOOLTIP_VIEW.STAT_EFFECT
const TIP_WIDTH := TOOLTIP_VIEW.TIP_WIDTH
const COLOR_PRESETS: Array[Color] = MOD_STATS_STRIP.COLOR_PRESETS

var _selected: StringName = &"m870"
var _primary: StringName = &"m870"
var _secondary: StringName = &"g17"
var _category: StringName = &"all"
var _page := "weapon"
var _weapon_sub := "data"

## 子视图实例
var _detail_view: ArmoryDetailView = DETAIL_VIEW.new()
var _tooltip_view: ArmoryTooltipView = TOOLTIP_VIEW.new()
var _armor_view: ArmoryArmorView = ARMOR_VIEW.new()
var _mod_view: ArmoryModCanvasView = MOD_CANVAS_VIEW.new()

## 顶部/底部壳体控件
var _weapon_page: Control
var _tab_weapon: Button
var _tab_armor: Button
var _sub_tab_data: Button
var _sub_tab_mods: Button
var _loadout_label: Label
var _feedback: Label

## 对外与既有测试兼容属性转发（单一状态源均在对应子视图内）
var _weapon_buttons: Dictionary:
	get: return _detail_view.weapon_buttons
var _category_buttons: Dictionary:
	get: return _detail_view.category_buttons
var _mod_shortcut_button: Button:
	get: return _detail_view.mod_button
var _weapon_list: VBoxContainer:
	get: return _detail_view.weapon_list
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
var _detail_title: Label:
	get: return _detail_view.detail_title
var _detail_icon: TextureRect:
	get: return _detail_view.detail_icon
var _primary_button: Button:
	get: return _detail_view.primary_button
var _secondary_button: Button:
	get: return _detail_view.secondary_button
var _weapon_data_page: Control:
	get: return _detail_view.page
var _detail_tips: Dictionary:
	get: return _tooltip_view.tips
	set(v): _tooltip_view.tips = v
var _tip_panel: PanelContainer:
	get: return _tooltip_view.tip_panel
	set(v): _tooltip_view.tip_panel = v
var _tip_label: Label:
	get: return _tooltip_view.tip_label
	set(v): _tooltip_view.tip_label = v
var _armor_page: Control:
	get: return _armor_view.page
var _armor_values: Dictionary:
	get: return _armor_view.values
var _mods_page: Control:
	get: return _mod_view.page
var _mod_item: String:
	get: return _mod_view.mod_item
	set(v): _mod_view.mod_item = v
var _mod_items: VBoxContainer:
	get: return _mod_view.mod_items
var _mod_item_buttons: Dictionary:
	get: return _mod_view.mod_item_buttons
var _mod_choices: Dictionary:
	get: return _mod_view.mod_choices
var _mod_slots_box: VBoxContainer:
	get: return _mod_view.mod_slots_box
var _mod_feedback: Label:
	get: return _mod_view.mod_feedback
var _mod_gun_view: Control:
	get: return _mod_view.mod_gun_view
var _mod_slot_buttons: Dictionary:
	get: return _mod_view.mod_slot_buttons
var _mod_gun_tex: Texture2D:
	get: return _mod_view.mod_gun_tex
var _mod_gun_rect: Rect2:
	get: return _mod_view.mod_gun_rect
var _mod_gun_anchors: Dictionary:
	get: return _mod_view.mod_gun_anchors
var _mod_slot_targets: Dictionary:
	get: return _mod_view.mod_slot_targets
var _mod_selected_slot: String:
	get: return _mod_view.mod_selected_slot
	set(v): _mod_view.mod_selected_slot = v
var _mod_detail: PanelContainer:
	get: return _mod_view.mod_detail
var _mod_detail_title: Label:
	get: return _mod_view.mod_detail_title
var _mod_detail_state: Label:
	get: return _mod_view.mod_detail_state
var _mod_detail_option: Label:
	get: return _mod_view.mod_detail_option
var _mod_detail_cost: Label:
	get: return _mod_view.mod_detail_cost
var _mod_install: Button:
	get: return _mod_view.mod_install
var _mod_preview_option: String:
	get: return _mod_view.mod_preview_option
var _mod_stats_panel: PanelContainer:
	get: return _mod_view.stats_strip.stats_panel
var _mod_stat_values: Dictionary:
	get: return _mod_view.stats_strip.stat_values
var _mod_stat_deltas: Dictionary:
	get: return _mod_view.stats_strip.stat_deltas
var _reticle_box: VBoxContainer:
	get: return _mod_view.stats_strip.reticle_box
var _reticle_row: HBoxContainer:
	get: return _mod_view.stats_strip.reticle_row
var _reticle_buttons: Dictionary:
	get: return _mod_view.stats_strip.reticle_buttons


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
	rows.add_theme_constant_override("separation", 8)
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
	_tab_weapon = PixelUI.button("▶ 武器数据 // WEAPONS", 40)
	_tab_weapon.custom_minimum_size.x = 300
	_tab_weapon.pressed.connect(func() -> void: _show_page("weapon"))
	tabs.add_child(_tab_weapon)
	_tab_armor = PixelUI.button("护甲数据 // ARMOR", 40)
	_tab_armor.custom_minimum_size.x = 300
	_tab_armor.pressed.connect(func() -> void: _show_page("armor"))
	tabs.add_child(_tab_armor)

	# 武器页：数据 / 配件两个子页
	var weapon_page := VBoxContainer.new()
	weapon_page.add_theme_constant_override("separation", 6)
	weapon_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(weapon_page)
	_weapon_page = weapon_page

	var sub_tabs := HBoxContainer.new()
	sub_tabs.add_theme_constant_override("separation", 8)
	weapon_page.add_child(sub_tabs)
	_sub_tab_data = PixelUI.button("▶ 武器数据", 34)
	_sub_tab_data.custom_minimum_size.x = 240
	_sub_tab_data.pressed.connect(func() -> void: _show_weapon_sub("data"))
	sub_tabs.add_child(_sub_tab_data)
	_sub_tab_mods = PixelUI.button("配件与组件", 34)
	_sub_tab_mods.custom_minimum_size.x = 240
	_sub_tab_mods.pressed.connect(func() -> void: _show_weapon_sub("mods"))
	sub_tabs.add_child(_sub_tab_mods)

	_detail_view.build(weapon_page)
	_detail_view.weapon_selected.connect(_select)
	_detail_view.category_selected.connect(_select_category)
	_detail_view.ammo_selected.connect(_select_ammo)
	_detail_view.equip_requested.connect(_equip)
	_detail_view.mod_requested.connect(_open_mods_for_weapon)
	_detail_view.tip_show_requested.connect(_show_tip)
	_detail_view.tip_hide_requested.connect(_hide_tip)

	_armor_view.build(rows)
	_mod_view.build(weapon_page, _progress_node, _current_loadout)

	var footer_divider := HSeparator.new()
	footer_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(footer_divider)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 16)
	rows.add_child(footer_row)
	var footer_info := VBoxContainer.new()
	footer_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_info.add_theme_constant_override("separation", 2)
	footer_row.add_child(footer_info)
	_loadout_label = PixelUI.label(footer_info, "", 18, PixelUI.TEXT)
	_feedback = PixelUI.label(footer_info, "点击武器查看数据 · 装备后开始行动生效", 16, PixelUI.DIM)
	var close_button := PixelUI.button("返回基地", 44)
	close_button.custom_minimum_size.x = 240
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_menu)
	footer_row.add_child(close_button)

	_tooltip_view.build(self)


func _progress_node() -> Node:
	return get_node_or_null("/root/Progress")


func _current_loadout() -> Dictionary:
	_read_loadout()
	return {"primary": _primary, "secondary": _secondary}


func _process(_delta: float) -> void:
	if _tooltip_view.is_visible():
		_tooltip_view.place_tip()


func open() -> void:
	_read_loadout()
	_category = &"all"
	_selected = _primary
	_feedback.text = "点击武器查看数据 · 装备后开始行动生效"
	_show_page("weapon")
	_refresh()
	if _list_scroll != null:
		_list_scroll.scroll_vertical = 0
	move_to_front()
	visible = true


func close_menu() -> void:
	if not visible:
		return
	_hide_tip()
	visible = false
	closed.emit()


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


func _show_weapon_sub(sub: String, target_weapon: StringName = &"") -> void:
	_weapon_sub = sub
	if _weapon_data_page != null:
		_weapon_data_page.visible = sub == "data"
	if _mods_page != null:
		_mods_page.visible = sub == "mods"
	_sub_tab_data.text = ("▶ " if sub == "data" else "   ") + "武器数据"
	_sub_tab_mods.text = ("▶ " if sub == "mods" else "   ") + "配件与组件"
	if sub == "mods":
		_read_loadout()
		# 直接切到改枪子页时强制选中当前主武器；通过武器详情「去改枪」进入则直达该选中武器。
		var item_id := String(target_weapon) if target_weapon != &"" else String(_primary)
		_feedback.text = "配件与组件 · 安装后开始行动生效"
		_mod_view.select_item(item_id)
		_mod_view.set_feedback("点击选项切换预览 · 安装消耗信用点与进阶资源", PixelUI.DIM)
	else:
		_feedback.text = "点击武器查看数据 · 装备后开始行动生效"
		# 从配件页返回时重新读取实际数据，避免显示安装前的旧数值。
		_refresh()


func _select_category(category: StringName) -> void:
	_category = category
	_read_loadout()
	var visible_ids := MOD_SERVICE.pinned_weapon_order(_primary, _secondary, _category)
	if not visible_ids.is_empty() and not visible_ids.has(String(_selected)):
		_selected = StringName(visible_ids[0])
	if _list_scroll != null:
		_list_scroll.scroll_vertical = 0
	_refresh()


func _select_ammo(ammo_id: StringName) -> void:
	var p := _progress_node()
	if p != null and p.has_method("set_weapon_ammo_2d"):
		if p.set_weapon_ammo_2d(_selected, ammo_id):
			var a := WeaponDB.get_ammo(ammo_id)
			if a != null:
				_feedback.text = "默认出战弹种已切换为 [%s %s] %s · 局内可按 Q 热切" % [
					WeaponDB.tier_label(a.tier), WeaponDB.role_label(a.role), a.display_name]
	_refresh()


func _open_mods_for_weapon(weapon_id: StringName) -> void:
	if weapon_id == &"":
		weapon_id = _selected
	_page = "mods"
	_hide_tip()
	if _weapon_page != null:
		_weapon_page.visible = true
	if _armor_page != null:
		_armor_page.visible = false
	_tab_weapon.text = "▶ 武器数据 // WEAPONS"
	_tab_armor.text = "   护甲数据 // ARMOR"
	_show_weapon_sub("mods", weapon_id)


func _select(id: StringName) -> void:
	_selected = id
	_feedback.text = "点击武器查看数据 · 装备后开始行动生效"
	_refresh()


func _equip(primary_slot: bool) -> void:
	var p := _progress_node()
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


func _read_loadout() -> void:
	var slots := MOD_SERVICE.read_loadout(_progress_node(), _primary, _secondary)
	_primary = slots["primary"]
	_secondary = slots["secondary"]


func _refresh() -> void:
	_read_loadout()
	_hide_tip()
	_detail_view.refresh(_selected, _primary, _secondary, _progress_node(), _tooltip_view, _category)
	_loadout_label.text = "当前携带：主武器 %s · 副武器 %s" % [
		WeaponDB.get_weapon(_primary).display_name,
		WeaponDB.get_weapon(_secondary).display_name,
	]
	_refresh_armor()


## --- 子视图薄委托接口（保留既有方法签名供测试/抓图脚本调用）--------------------

func _show_tip(key: String) -> void:
	_tooltip_view.show_tip(key)


func _hide_tip() -> void:
	_tooltip_view.hide_tip()


func _refresh_armor() -> void:
	_armor_view.refresh(_progress_node())


func _select_mod_item(item: String) -> void:
	_mod_view.select_item(item)


func _select_mod_slot(slot: String) -> void:
	_mod_view.select_slot(slot)


func _refresh_mods() -> void:
	_mod_view.refresh()


func _cycle_mod_selected(step: int) -> void:
	_mod_view.cycle_selected(step)


func _install_preview() -> void:
	_mod_view.install_preview()


func _install_mod(slot: String, option_id: String) -> void:
	_mod_view.install_mod(slot, option_id)


func _mod_weapon_stats(weapon_id: StringName, installed: Dictionary) -> Dictionary:
	return STATS_MODEL.compute_for_progress(weapon_id, _progress_node(), installed)
