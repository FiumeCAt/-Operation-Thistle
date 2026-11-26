extends RefCounted
class_name ArmoryModCanvasView
## 武备库「配件与组件」子页视图：左侧武器/护甲列表、塔科夫式枪身锚点画布、右侧槽位详情与护甲三槽位列表。
## 从 ArmoryMenu2D 抽离，为后续在枪身贴图上叠加可视化配件图层预留独立的画布模块。

const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")
const STATS_STRIP := preload("res://scripts/ui/armory/ArmoryModStatsStrip.gd")

var page: VBoxContainer
var mod_item := "m870"
var items_scroll: ScrollContainer
var mod_items: VBoxContainer
var mod_item_buttons: Dictionary = {}
var mod_choices: Dictionary = {}
var mod_slots_box: VBoxContainer
var mod_feedback: Label

## 塔科夫式改枪画布：平直枪身贴图 + 6 部位锚点连线 + 槽位按钮
var mod_gun_view: Control
var mod_slot_buttons: Dictionary = {}
var mod_gun_tex: Texture2D
var mod_gun_rect := Rect2()
var mod_gun_anchors: Dictionary = {}
var mod_slot_targets: Dictionary = {}
var mod_selected_slot := "muzzle"

## 右侧槽位详情面板
var mod_detail: PanelContainer
var mod_detail_title: Label
var mod_detail_state: Label
var mod_detail_option: Label
var mod_detail_option_rich: RichTextLabel
var mod_detail_cost: Label
var mod_install: Button
var mod_preview_option := ""

## 下半部实时属性条 / 颜色 / 准星切换子视图
var stats_strip: ArmoryModStatsStrip = STATS_STRIP.new()

var _progress_fn: Callable = Callable()
var _loadout_fn: Callable = Callable()


func build(parent: Node, progress_fn: Callable, loadout_fn: Callable) -> void:
	_progress_fn = progress_fn
	_loadout_fn = loadout_fn

	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.visible = false
	parent.add_child(page)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	items_scroll = ScrollContainer.new()
	items_scroll.custom_minimum_size.x = 220
	items_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(items_scroll)
	mod_items = VBoxContainer.new()
	mod_items.add_theme_constant_override("separation", 8)
	mod_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_scroll.add_child(mod_items)
	for id in WeaponDB.WEAPON_ORDER:
		var button := PixelUI.button("", 58)
		button.custom_minimum_size.x = 200
		button.pressed.connect(select_item.bind(String(id)))
		mod_items.add_child(button)
		mod_item_buttons[String(id)] = button
	var armor_button := PixelUI.button("", 58)
	armor_button.custom_minimum_size.x = 200
	armor_button.pressed.connect(select_item.bind("armor"))
	mod_items.add_child(armor_button)
	mod_item_buttons["armor"] = armor_button

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)

	# 上半：枪身工位（配件框环绕枪身，连线指向真实部位）+ 右侧槽位详情。
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(top)

	mod_gun_view = Control.new()
	mod_gun_view.custom_minimum_size = Vector2(420, 280)
	mod_gun_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_gun_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mod_gun_view.draw.connect(_draw_mod_gun)
	mod_gun_view.resized.connect(_on_mod_gun_view_resized)
	top.add_child(mod_gun_view)
	for slot_def in ModDB.WEAPON_SLOTS:
		var slot := String(slot_def["id"])
		var button := PixelUI.button("", 52)
		button.size = Vector2(130, 52)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(select_slot.bind(slot))
		mod_gun_view.add_child(button)
		mod_slot_buttons[slot] = button

	_build_mod_detail(top)

	# 护甲沿用列表式三槽位。
	mod_slots_box = VBoxContainer.new()
	mod_slots_box.add_theme_constant_override("separation", 10)
	mod_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(mod_slots_box)

	# 下半：横向实时属性对比条 + 外观色块 + 准星切换。
	stats_strip.build(right, _progress_fn)
	stats_strip.reticle_style_changed.connect(refresh)
	stats_strip.feedback_emitted.connect(set_feedback)

	mod_feedback = PixelUI.label(right, "", PixelUI.FS_BODY, PixelUI.DIM)
	mod_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _progress() -> Node:
	return _progress_fn.call() if _progress_fn.is_valid() else null


func set_feedback(text: String, color: Color = PixelUI.DIM) -> void:
	if mod_feedback != null:
		mod_feedback.text = text
		mod_feedback.add_theme_color_override("font_color", color)


## 右侧槽位详情：标题、当前装配、预览配件与安装按钮。
func _build_mod_detail(parent: Node) -> void:
	mod_detail = PixelUI.panel(PixelUI.BG_LIGHT)
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	mod_detail.add_theme_stylebox_override("panel", style)
	mod_detail.custom_minimum_size = Vector2(250, 280)
	parent.add_child(mod_detail)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	mod_detail.add_child(rows)
	mod_detail_title = PixelUI.emphasize(PixelUI.label(rows, "", 19, PixelUI.AMBER_BRIGHT), 2, 1)
	mod_detail_state = PixelUI.label(rows, "", 18, PixelUI.CYAN)
	mod_detail_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mod_detail_option = PixelUI.label(rows, "", 18, PixelUI.TEXT)
	mod_detail_option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mod_detail_option.visible = false
	mod_detail_option_rich = PixelUI.rich_label(rows, "", 18, PixelUI.TEXT, 1)
	mod_detail_option_rich.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mod_detail_cost = PixelUI.label(rows, "", 17, PixelUI.GOLD)
	mod_detail_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	rows.add_child(buttons)
	var prev := PixelUI.button("<", 42)
	prev.custom_minimum_size.x = 40
	prev.pressed.connect(cycle_selected.bind(-1))
	buttons.add_child(prev)
	mod_install = PixelUI.button("安装", 42)
	mod_install.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_install.add_theme_font_size_override("font_size", 16)
	mod_install.pressed.connect(install_preview)
	buttons.add_child(mod_install)
	var next := PixelUI.button(">", 42)
	next.custom_minimum_size.x = 40
	next.pressed.connect(cycle_selected.bind(1))
	buttons.add_child(next)


func select_item(item: String) -> void:
	mod_item = item
	mod_choices.clear()
	mod_selected_slot = "muzzle"
	set_feedback("点击枪身连线或槽位切换 · 安装消耗信用点与进阶资源", PixelUI.DIM)
	refresh()
	if items_scroll != null and mod_item_buttons.has(mod_item):
		items_scroll.call_deferred("ensure_control_visible", mod_item_buttons[mod_item])


func select_slot(slot: String) -> void:
	mod_selected_slot = slot
	mod_choices.erase(slot)
	refresh()


func refresh() -> void:
	if mod_slots_box == null:
		return
	var p := _progress()
	var loadout: Dictionary = _loadout_fn.call() if _loadout_fn.is_valid() \
		else MOD_SERVICE.read_loadout(p)
	var primary: StringName = loadout.get("primary", &"m870")
	var secondary: StringName = loadout.get("secondary", &"g17")
	var index := 0
	for sid in MOD_SERVICE.pinned_weapon_order(primary, secondary):
		if mod_item_buttons.has(sid):
			mod_items.move_child(mod_item_buttons[sid], index)
			index += 1

	var is_armor := mod_item == "armor"
	var installed: Dictionary = {}
	if p != null:
		installed = p.armor_mods_2d() if is_armor else p.weapon_mods_2d(StringName(mod_item))

	for id in mod_item_buttons:
		var button: Button = mod_item_buttons[id]
		var count := 0
		if p != null:
			var mods: Dictionary = p.armor_mods_2d() if id == "armor" \
				else p.weapon_mods_2d(StringName(id))
			count = mods.size()
		var label := "护甲 // DOLL-01" if id == "armor" \
			else String(WeaponDB.get_weapon(StringName(id)).display_name).split(" // ")[0]
		var slot_mark := ""
		if StringName(id) == primary:
			slot_mark = " [主]"
		elif StringName(id) == secondary:
			slot_mark = " [副]"
		var total_slots: int = ModDB.ARMOR_SLOTS.size() if id == "armor" \
			else ModDB.WEAPON_SLOTS.size()
		button.text = "%s%s%s  [%d/%d]" % [
			"▶ " if id == mod_item else "   ", label, slot_mark, count, total_slots]
		button.add_theme_font_size_override("font_size", 20)

	mod_gun_view.visible = not is_armor
	stats_strip.set_stats_visible(not is_armor)
	mod_detail.visible = not is_armor
	mod_slots_box.visible = is_armor
	if is_armor:
		_refresh_armor_mod_rows(installed)
	else:
		refresh_gun_view()
		_refresh_slot_buttons(installed)
		_refresh_mod_detail(installed)
	stats_strip.refresh_reticle_switch(mod_item)


## 护甲：保留原来的三行槽位列表。
func _refresh_armor_mod_rows(installed: Dictionary) -> void:
	for child in mod_slots_box.get_children():
		mod_slots_box.remove_child(child)
		child.queue_free()

	var p := _progress()
	for slot_def in ModDB.slots(true):
		var slot := String(slot_def["id"])
		var options := ModDB.options(slot, true, mod_item)
		if options.is_empty():
			continue
		var current := String(installed.get(slot, ""))
		var choice := int(mod_choices.get(slot, -1))
		if choice < 0:
			choice = 0
			for i in options.size():
				if String(options[i]["id"]) == current:
					choice = i
					break
		choice = clampi(choice, 0, options.size() - 1)
		mod_choices[slot] = choice
		var entry: Dictionary = options[choice]
		var option_id := String(entry["id"])

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		mod_slots_box.add_child(row)

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
		option_button.pressed.connect(cycle_slot.bind(slot))
		row.add_child(option_button)

		var install_button := PixelUI.button("", 84)
		install_button.custom_minimum_size.x = 300
		install_button.add_theme_font_size_override("font_size", 18)
		if option_id == current:
			install_button.text = "已装配\n无需安装"
			install_button.disabled = true
		else:
			install_button.text = "安装\n%s\n%s" % [
				MOD_SERVICE.cost_line(entry), MOD_SERVICE.material_line(entry)]
			install_button.disabled = not MOD_SERVICE.can_pay_mod(p, entry)
		install_button.pressed.connect(install_mod.bind(slot, option_id))
		row.add_child(install_button)


## 枪身展示：读取 meta.json 的握把/枪口/部件像素锚点，计算 6 槽位在画布中的坐标。
func refresh_gun_view() -> void:
	if mod_gun_view == null or mod_slot_buttons.is_empty():
		return
	var path := "res://assets/art/weapons/%s/side.png" % mod_item
	mod_gun_tex = load(path) if ResourceLoader.exists(path) else null
	if mod_gun_tex == null:
		mod_gun_view.queue_redraw()
		return
	var width := mod_gun_view.size.x
	if width < 1.0:
		width = 580.0
	var height := mod_gun_view.size.y
	if height < 1.0:
		height = 280.0

	# 枪身放在上下配件框之间。
	var area := Rect2(14.0, 66.0, width - 28.0, height - 132.0)
	var tex_size := mod_gun_tex.get_size()
	var fit := minf(area.size.x / tex_size.x, area.size.y / tex_size.y)
	var draw_size := tex_size * fit
	mod_gun_rect = Rect2(area.position + (area.size - draw_size) * 0.5, draw_size)

	var grip := Vector2(276, 552)
	var muzzle := Vector2(1361, 99)
	var bolt_px := Vector2.ZERO
	var mag_px := Vector2.ZERO
	var muzzle_mod_px := Vector2.ZERO
	var meta_path := "res://assets/art/weapons/%s/meta.json" % mod_item
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
		return mod_gun_rect.position + Vector2(
			px.x / tex_size.x, px.y / tex_size.y) * mod_gun_rect.size
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
	mod_gun_anchors = {
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
		var button: Button = mod_slot_buttons[slot]
		button.position = boxes[slot]
		button.size = box_size
		var center_x: float = boxes[slot].x + box_size.x * 0.5
		var top_row: bool = boxes[slot].y < height * 0.5
		mod_slot_targets[slot] = Vector2(center_x,
			boxes[slot].y + box_size.y if top_row else boxes[slot].y)
	mod_gun_view.queue_redraw()


func _draw_mod_gun() -> void:
	if mod_gun_view == null or mod_gun_tex == null:
		return
	mod_gun_view.draw_texture_rect(mod_gun_tex, mod_gun_rect, false)
	for slot in mod_gun_anchors:
		var anchor: Vector2 = mod_gun_anchors[slot]
		var target: Vector2 = mod_slot_targets.get(slot, Vector2.ZERO)
		if target == Vector2.ZERO:
			continue
		var active: bool = String(slot) == mod_selected_slot
		var color := PixelUI.AMBER_BRIGHT if active else Color(PixelUI.AMBER, 0.55)
		mod_gun_view.draw_line(anchor, target, color, 3.0 if active else 1.5)
		mod_gun_view.draw_circle(anchor, 4.5 if active else 3.0, color)


func _on_mod_gun_view_resized() -> void:
	if mod_gun_view != null and mod_gun_view.visible:
		refresh_gun_view()


func _refresh_slot_buttons(installed: Dictionary) -> void:
	for slot_def in ModDB.WEAPON_SLOTS:
		var slot := String(slot_def["id"])
		var button: Button = mod_slot_buttons[slot]
		var current := String(installed.get(slot, ""))
		var entry := ModDB.option(slot, current, false, mod_item)
		var state := "未装配" if entry.is_empty() else String(entry["name"])
		button.text = "%s%s\n%s" % [
			"▶ " if slot == mod_selected_slot else "",
			String(slot_def["name"]), state]
		button.add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if slot == mod_selected_slot else PixelUI.TEXT)


func _refresh_mod_detail(installed: Dictionary) -> void:
	var slot := mod_selected_slot
	var options := ModDB.options(slot, false, mod_item)
	if options.is_empty():
		return
	var current := String(installed.get(slot, ""))
	var choice := int(mod_choices.get(slot, -1))
	if choice < 0:
		choice = 0
		for i in options.size():
			if String(options[i]["id"]) == current:
				choice = i
				break
	choice = clampi(choice, 0, options.size() - 1)
	mod_choices[slot] = choice
	var entry: Dictionary = options[choice]
	mod_preview_option = String(entry["id"])
	var slot_name := ""
	for slot_def in ModDB.WEAPON_SLOTS:
		if String(slot_def["id"]) == slot:
			slot_name = String(slot_def["name"])
			break
	var installed_entry := ModDB.option(slot, current, false, mod_item)
	var installed_name := "未装配" if installed_entry.is_empty() \
		else String(installed_entry["name"])
	mod_detail_title.text = "%s // %s" % [slot_name, MOD_SERVICE.slot_english_name(slot)]
	mod_detail_state.text = "当前：%s" % installed_name
	mod_detail_cost.text = "消耗：%s\n%s" % [
		MOD_SERVICE.cost_line(entry), MOD_SERVICE.material_line(entry)]
	# 已装配同款配件时不再重复打印配件名（上方 mod_detail_state 已显示“当前：xxx”）；
	# 瞄具由 desc（定位说明）+ sight_stats_line（唯一数值摘要）组成，避免两段完全相同的数值重复出现。
	var lines: Array[String] = []
	if mod_preview_option != current:
		lines.append("预览：%s" % String(entry["name"]))
	var desc := String(entry.get("desc", "")).strip_edges()
	if desc != "":
		lines.append(desc)
	if slot == "sight":
		var sight_line := MOD_SERVICE.sight_stats_line(entry)
		if sight_line != "" and sight_line != desc:
			lines.append(sight_line)
	mod_detail_option.text = "\n".join(PackedStringArray(lines))
	if mod_detail_option_rich != null:
		mod_detail_option_rich.text = _format_mod_option_bb(lines)
	mod_install.text = "已装配" if mod_preview_option == current else "安装"
	mod_install.disabled = mod_preview_option == current or not MOD_SERVICE.can_pay_mod(_progress(), entry)
	# 实时数据窗：把当前预览当作已装配，计算与当前配置的差值。
	var preview := installed.duplicate()
	preview[slot] = mod_preview_option
	stats_strip.refresh_stats(StringName(mod_item), installed, preview)


func _format_mod_option_bb(lines: Array[String]) -> String:
	var out: Array[String] = []
	for line in lines:
		if line.begins_with("预览："):
			out.append(PixelUI.bb(line, PixelUI.AMBER_BRIGHT))
			continue
		if line.contains(" · ") and (line.contains("%") or line.contains("倍率")):
			var segs := line.split(" · ")
			var colored: Array[String] = []
			for seg in segs:
				var s := seg.strip_edges()
				if s.begins_with("倍率"):
					colored.append(PixelUI.bb(s, PixelUI.GOLD))
				elif s.contains("瞄准时间 +") or s.contains("散布 +") or s.contains("噪音 +") \
						or s.contains("换弹 +") or s.contains("伤害 -") or s.contains("射速 -"):
					colored.append(PixelUI.bb(s, PixelUI.DANGER))
				elif s.contains("+") or s.contains("-"):
					colored.append(PixelUI.bb(s, PixelUI.OK))
				else:
					colored.append(PixelUI.bb(s, PixelUI.CYAN))
			out.append(" · ".join(PackedStringArray(colored)))
		else:
			out.append(line)
	return "\n".join(PackedStringArray(out))


func cycle_selected(step: int) -> void:
	var options := ModDB.options(mod_selected_slot, false, mod_item)
	if options.is_empty():
		return
	var choice := int(mod_choices.get(mod_selected_slot, 0))
	mod_choices[mod_selected_slot] = (choice + step + options.size()) % options.size()
	var p := _progress()
	var installed: Dictionary = {}
	if p != null:
		installed = p.weapon_mods_2d(StringName(mod_item))
	_refresh_mod_detail(installed)


func install_preview() -> void:
	if mod_preview_option == "":
		return
	install_mod(mod_selected_slot, mod_preview_option)


func cycle_slot(slot: String) -> void:
	var is_armor := mod_item == "armor"
	var options := ModDB.options(slot, is_armor, mod_item)
	if options.is_empty():
		return
	var choice := int(mod_choices.get(slot, 0))
	mod_choices[slot] = (choice + 1) % options.size()
	refresh()


func install_mod(slot: String, option_id: String) -> void:
	var p := _progress()
	if p == null:
		return
	var res := MOD_SERVICE.install_mod(p, mod_item, slot, option_id)
	if bool(res["ok"]):
		var sfx := p.get_node_or_null("/root/Sfx")
		if sfx != null:
			sfx.play_2d("mod_install", -6.5)
		set_feedback(String(res["message"]), PixelUI.OK)
		mod_choices.erase(slot)
	else:
		set_feedback(String(res["message"]), PixelUI.DANGER)
	refresh()
