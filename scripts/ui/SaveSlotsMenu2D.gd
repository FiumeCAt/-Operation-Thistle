extends Control
## 主菜单存档管理：5 个槽位，可存档/读档；退出游戏时会自动写回当前槽位。

signal closed
signal slot_loaded(slot: int)

const SLOT_COUNT := 5
const PANEL_SIZE := Vector2(1120, 620)

var _rows: Array[Dictionary] = []
var _status: Label
var _close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.82)
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

	PixelUI.label(rows, "存档管理 // SAVE SLOTS", PixelUI.FS_TITLE, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)
	PixelUI.label(rows, "5 个手动槽位 · 退出游戏时自动保存到当前槽位",
		PixelUI.FS_BODY, PixelUI.DIM)

	for slot in range(1, SLOT_COUNT + 1):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.custom_minimum_size.y = 58
		rows.add_child(line)

		var info_box := VBoxContainer.new()
		info_box.add_theme_constant_override("separation", 1)
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(info_box)

		var top_line := HBoxContainer.new()
		top_line.add_theme_constant_override("separation", 8)
		info_box.add_child(top_line)

		var name_label := PixelUI.label(top_line, "槽位 %d" % slot, PixelUI.FS_BODY, PixelUI.AMBER)
		name_label.custom_minimum_size.x = 104
		var summary_top := PixelUI.label(top_line, "-", 20, PixelUI.TEXT)
		summary_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary_top.clip_text = true
		var summary_bottom := PixelUI.label(info_box, "", 18, PixelUI.DIM)
		summary_bottom.clip_text = true

		var save_button := PixelUI.button("存档", 46)
		save_button.custom_minimum_size.x = 96
		save_button.pressed.connect(_save_slot.bind(slot))
		line.add_child(save_button)

		var load_button := PixelUI.button("读档", 46)
		load_button.custom_minimum_size.x = 96
		load_button.pressed.connect(_load_slot.bind(slot))
		line.add_child(load_button)

		_rows.append({
			"slot": slot,
			"name": name_label,
			"top": summary_top,
			"bottom": summary_bottom,
			"load": load_button,
		})

	_status = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_close_button = PixelUI.button("关闭", 46)
	_close_button.custom_minimum_size.x = 260
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(close_menu)
	rows.add_child(_close_button)


func open() -> void:
	refresh()
	move_to_front()
	visible = true
	if _close_button != null:
		_close_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func refresh() -> void:
	var p := get_node_or_null("/root/Progress")
	for entry in _rows:
		var slot := int(entry["slot"])
		var name_label: Label = entry["name"]
		var top: Label = entry["top"]
		var bottom: Label = entry["bottom"]
		var load_button: Button = entry["load"]
		var info: Dictionary = p.slot_info(slot) if p != null else {"empty": true}
		var active := bool(info.get("active", false))
		name_label.text = ("● " if active else "  ") + "槽位 %d" % slot
		name_label.add_theme_color_override("font_color",
			PixelUI.OK if active else PixelUI.AMBER)
		if bool(info.get("empty", true)):
			top.text = "空存档"
			top.add_theme_color_override("font_color", PixelUI.DIM)
			bottom.text = "使用「存档」写入当前进度"
			bottom.add_theme_color_override("font_color", PixelUI.DIM)
			load_button.disabled = true
			continue
		load_button.disabled = false
		top.add_theme_color_override("font_color", PixelUI.TEXT)
		bottom.add_theme_color_override("font_color", PixelUI.DIM)
		var s: Dictionary = info.get("summary", {})
		var mode := "行动"
		if String(s.get("run_mode", "raid")) == "waves":
			mode = "歌利亚狂潮" if String(s.get("map_id", "facility")) == "goliath_arena" else "设施浪潮"
		top.text = "信用点 %d · Lv.%d · 天赋 %d" % [
			int(s.get("credits", 0)), int(s.get("skill_level", 1)),
			int(s.get("talents", 0)),
		]
		bottom.text = "材料 %d · %s · %s" % [
			int(s.get("materials", 0)), mode,
			_format_time(int(info.get("saved_at", 0))),
		]


func _format_time(unix: int) -> String:
	if unix <= 0:
		return "—"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var dt := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d-%02d %02d:%02d" % [
		int(dt.get("month", 0)), int(dt.get("day", 0)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)),
	]


func _save_slot(slot: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_status.text = "存档服务不可用"
		return
	if p.save_to_slot(slot):
		_status.text = "已保存到槽位 %d" % slot
		_status.add_theme_color_override("font_color", PixelUI.OK)
	else:
		_status.text = "保存失败：槽位 %d" % slot
		_status.add_theme_color_override("font_color", PixelUI.DANGER)
	refresh()


func _load_slot(slot: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_status.text = "存档服务不可用"
		return
	if not p.load_from_slot(slot):
		_status.text = "读取失败：槽位 %d" % slot
		_status.add_theme_color_override("font_color", PixelUI.DANGER)
		refresh()
		return
	_status.text = "已读取槽位 %d · 当前进度已切换" % slot
	_status.add_theme_color_override("font_color", PixelUI.OK)
	refresh()
	slot_loaded.emit(slot)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
