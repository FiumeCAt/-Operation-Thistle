extends Control
## 主菜单存档管理（Phase 5B 扩容）：
## - 5 个手动槽位：存档 / 读档 / 清空（二次确认 + .bak 备份）；
## - 重置当前游戏进度（默认保留画面/音量/偏好设置，二次确认 + .bak 备份）；
## - 原生文件弹窗导出/导入 .json（导入前强制版本迁移 + 结构校验，失败绝不覆盖现存档，可选是否覆盖本地偏好）。

signal closed
signal slot_loaded(slot: int)

const SLOT_COUNT := 5
const PANEL_SIZE := Vector2(1180, 748)

var _rows: Array[Dictionary] = []
var _status: Label
var _close_button: Button
var _keep_settings := true
var _overwrite_settings := false
var _keep_settings_button: Button
var _overwrite_settings_button: Button
var _export_dialog: FileDialog
var _import_dialog: FileDialog

## 二次确认浮层
var _confirm_overlay: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_ok_button: Button
var _pending_action := ""
var _pending_slot := 0
var _pending_import_path := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	_build_file_dialogs()
	_build_confirm_overlay()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.84)
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
	rows.add_child(header)
	var title := PixelUI.label(header, "存档管理 // SAVE SLOTS", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "5 槽位 · 重置 · JSON 导入导出", 18, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)
	PixelUI.label(rows, "5 个手动槽位 · 退出游戏时自动保存到当前槽位 · 重置/清空/导入前均自动备份 .bak",
		18, PixelUI.DIM)

	for slot in range(1, SLOT_COUNT + 1):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.custom_minimum_size.y = 54
		rows.add_child(line)

		var info_box := VBoxContainer.new()
		info_box.add_theme_constant_override("separation", 1)
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(info_box)

		var top_line := HBoxContainer.new()
		top_line.add_theme_constant_override("separation", 8)
		info_box.add_child(top_line)

		var name_label := PixelUI.label(top_line, "槽位 %d" % slot, 21, PixelUI.AMBER)
		name_label.custom_minimum_size.x = 104
		var summary_top := PixelUI.label(top_line, "-", 19, PixelUI.TEXT)
		summary_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary_top.clip_text = true
		var summary_bottom := PixelUI.label(info_box, "", 16, PixelUI.DIM)
		summary_bottom.clip_text = true

		var save_button := PixelUI.button("存档", 42)
		save_button.add_theme_font_size_override("font_size", 18)
		save_button.custom_minimum_size.x = 88
		save_button.pressed.connect(_save_slot.bind(slot))
		line.add_child(save_button)

		var load_button := PixelUI.button("读档", 42)
		load_button.add_theme_font_size_override("font_size", 18)
		load_button.custom_minimum_size.x = 88
		load_button.pressed.connect(_load_slot.bind(slot))
		line.add_child(load_button)

		var clear_button := PixelUI.button("清空", 42)
		clear_button.add_theme_font_size_override("font_size", 18)
		clear_button.custom_minimum_size.x = 84
		clear_button.add_theme_color_override("font_color", PixelUI.DANGER)
		clear_button.pressed.connect(request_clear_slot.bind(slot))
		line.add_child(clear_button)

		_rows.append({
			"slot": slot,
			"name": name_label,
			"top": summary_top,
			"bottom": summary_bottom,
			"load": load_button,
			"clear": clear_button,
		})

	var tools_sep := HSeparator.new()
	tools_sep.add_theme_color_override("color", Color(PixelUI.CYAN, 0.55))
	rows.add_child(tools_sep)
	PixelUI.section_bar(rows, "存档维护与迁移", "RESET & JSON TRANSFER", PixelUI.CYAN)

	var tools_panel := PanelContainer.new()
	var tst := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.CYAN, 0.35))
	tst.content_margin_left = 12
	tst.content_margin_right = 12
	tst.content_margin_top = 8
	tst.content_margin_bottom = 8
	tools_panel.add_theme_stylebox_override("panel", tst)
	rows.add_child(tools_panel)

	var tools_rows := VBoxContainer.new()
	tools_rows.add_theme_constant_override("separation", 8)
	tools_panel.add_child(tools_rows)

	# 维护行 1：重置当前进度
	var reset_row := HBoxContainer.new()
	reset_row.add_theme_constant_override("separation", 10)
	tools_rows.add_child(reset_row)
	var reset_btn := PixelUI.button("重置当前进度", 38)
	reset_btn.add_theme_font_size_override("font_size", 17)
	reset_btn.custom_minimum_size.x = 200
	reset_btn.add_theme_color_override("font_color", PixelUI.DANGER)
	reset_btn.pressed.connect(request_reset_progress)
	reset_row.add_child(reset_btn)

	_keep_settings_button = PixelUI.button("", 38)
	_keep_settings_button.add_theme_font_size_override("font_size", 16)
	_keep_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keep_settings_button.pressed.connect(func() -> void: set_keep_settings_on_reset(not _keep_settings))
	reset_row.add_child(_keep_settings_button)

	# 维护行 2：导出 / 导入 .json
	var transfer_row := HBoxContainer.new()
	transfer_row.add_theme_constant_override("separation", 10)
	tools_rows.add_child(transfer_row)
	var export_btn := PixelUI.button("导出存档 (.json)", 38)
	export_btn.add_theme_font_size_override("font_size", 17)
	export_btn.custom_minimum_size.x = 200
	export_btn.add_theme_color_override("font_color", PixelUI.CYAN)
	export_btn.pressed.connect(_open_export_dialog)
	transfer_row.add_child(export_btn)

	var import_btn := PixelUI.button("导入存档 (.json)", 38)
	import_btn.add_theme_font_size_override("font_size", 17)
	import_btn.custom_minimum_size.x = 200
	import_btn.add_theme_color_override("font_color", PixelUI.AMBER_BRIGHT)
	import_btn.pressed.connect(_open_import_dialog)
	transfer_row.add_child(import_btn)

	_overwrite_settings_button = PixelUI.button("", 38)
	_overwrite_settings_button.add_theme_font_size_override("font_size", 16)
	_overwrite_settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overwrite_settings_button.pressed.connect(
		func() -> void: set_overwrite_settings_on_import(not _overwrite_settings))
	transfer_row.add_child(_overwrite_settings_button)

	_refresh_option_toggles()

	_status = PixelUI.label(rows, "", 19, PixelUI.DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 24

	_close_button = PixelUI.primary_button("关闭", 42)
	_close_button.add_theme_font_size_override("font_size", 19)
	_close_button.custom_minimum_size.x = 240
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(close_menu)
	rows.add_child(_close_button)


func _build_file_dialogs() -> void:
	_export_dialog = FileDialog.new()
	_export_dialog.name = "ExportSaveDialog"
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.use_native_dialog = true
	_export_dialog.title = "导出存档为 JSON"
	_export_dialog.filters = PackedStringArray(["*.json ; 蓟花行动存档 (.json)"])
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)

	_import_dialog = FileDialog.new()
	_import_dialog.name = "ImportSaveDialog"
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.use_native_dialog = true
	_import_dialog.title = "选择要导入的 JSON 存档"
	_import_dialog.filters = PackedStringArray(["*.json ; 蓟花行动存档 (.json)"])
	_import_dialog.file_selected.connect(_on_import_file_selected)
	add_child(_import_dialog)


func _build_confirm_overlay() -> void:
	_confirm_overlay = Control.new()
	_confirm_overlay.name = "ConfirmOverlay"
	_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(shade)

	var box := PixelUI.panel()
	box.accent = PixelUI.DANGER
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -330
	box.offset_right = 330
	box.offset_top = -155
	box.offset_bottom = 155
	_confirm_overlay.add_child(box)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)

	_confirm_title = PixelUI.label(v, "二次确认", 26, PixelUI.DANGER)
	var div := HSeparator.new()
	div.add_theme_color_override("color", PixelUI.DANGER)
	v.add_child(div)

	_confirm_body = PixelUI.label(v, "", 18, PixelUI.TEXT)
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)

	_confirm_ok_button = PixelUI.button("确认执行", 42)
	_confirm_ok_button.add_theme_font_size_override("font_size", 18)
	_confirm_ok_button.custom_minimum_size.x = 180
	_confirm_ok_button.add_theme_color_override("font_color", PixelUI.DANGER)
	_confirm_ok_button.pressed.connect(func() -> void: confirm_pending_action())
	btns.add_child(_confirm_ok_button)

	var cancel_btn := PixelUI.primary_button("取消", 42)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.custom_minimum_size.x = 180
	cancel_btn.pressed.connect(cancel_pending_action)
	btns.add_child(cancel_btn)


func _refresh_option_toggles() -> void:
	if _keep_settings_button != null:
		_keep_settings_button.text = ("%s 重置时保留画面/音量/偏好设置" %
			("[■]" if _keep_settings else "[□]"))
		_keep_settings_button.add_theme_color_override("font_color",
			PixelUI.OK if _keep_settings else PixelUI.AMBER_BRIGHT)
	if _overwrite_settings_button != null:
		_overwrite_settings_button.text = ("%s 导入时覆盖本地偏好设置" %
			("[■]" if _overwrite_settings else "[□]"))
		_overwrite_settings_button.add_theme_color_override("font_color",
			PixelUI.AMBER_BRIGHT if _overwrite_settings else PixelUI.DIM)


func set_keep_settings_on_reset(keep: bool) -> void:
	_keep_settings = keep
	_refresh_option_toggles()


func set_overwrite_settings_on_import(overwrite: bool) -> void:
	_overwrite_settings = overwrite
	_refresh_option_toggles()


func is_confirm_open() -> bool:
	return _confirm_overlay != null and _confirm_overlay.visible


func open() -> void:
	cancel_pending_action()
	refresh()
	move_to_front()
	visible = true
	if _close_button != null:
		_close_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	cancel_pending_action()
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
		var clear_button: Button = entry["clear"]
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
			clear_button.disabled = true
			continue
		load_button.disabled = false
		clear_button.disabled = false
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


func _set_status(text: String, ok: bool) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", PixelUI.OK if ok else PixelUI.DANGER)


func _save_slot(slot: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_set_status("存档服务不可用", false)
		return
	if p.save_to_slot(slot):
		_set_status("已保存到槽位 %d" % slot, true)
	else:
		_set_status("保存失败：槽位 %d" % slot, false)
	refresh()


func _load_slot(slot: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_set_status("存档服务不可用", false)
		return
	if not p.load_from_slot(slot):
		_set_status("读取失败：槽位 %d" % slot, false)
		refresh()
		return
	_set_status("已读取槽位 %d · 当前进度已切换" % slot, true)
	refresh()
	slot_loaded.emit(slot)


## ---- 二次确认入口：清空槽位 / 重置当前进度 / 导入存档 ----

func request_clear_slot(slot: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_set_status("存档服务不可用", false)
		return
	var info: Dictionary = p.slot_info(slot)
	if bool(info.get("empty", true)):
		_set_status("槽位 %d 已经是空的" % slot, false)
		return
	_open_confirm("clear_slot", "确认清空槽位 %d" % slot,
		"即将清空手动槽位 %d 的存档快照。\n清空前原槽位文件会自动备份为 .bak，当前正在使用的主进度不受影响。\n\n确认清空？" % slot,
		slot, "")


func request_reset_progress() -> void:
	var pref_note := "保留当前画面、音量、主题与显示设置" if _keep_settings \
		else "连同画面、音量、主题等全部本地设置一并恢复默认"
	_open_confirm("reset_progress", "确认重置当前游戏进度",
		"即将把当前进度的信用点、材料、等级、天赋与携行配装全部重置为初始状态（%s）。\n重置前当前主存档会自动滚入 .bak 备份环，确认继续？" % pref_note,
		0, "")


func _open_export_dialog() -> void:
	if _export_dialog == null:
		return
	var dt := Time.get_datetime_dict_from_system()
	_export_dialog.current_file = "operation_thistle_save_%04d%02d%02d.json" % [
		int(dt.get("year", 2026)), int(dt.get("month", 1)), int(dt.get("day", 1))]
	_export_dialog.popup_centered_ratio(0.6)


func _open_import_dialog() -> void:
	if _import_dialog == null:
		return
	_import_dialog.popup_centered_ratio(0.6)


func _on_export_file_selected(path: String) -> void:
	export_to_path(path)


func _on_import_file_selected(path: String) -> void:
	request_import_from_path(path)


func export_to_path(path: String) -> bool:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_set_status("存档服务不可用", false)
		return false
	var res: Dictionary = p.export_save_to_file(path)
	if bool(res.get("ok", false)):
		_set_status("已导出存档至：%s" % path.get_file(), true)
		return true
	_set_status("导出失败：%s" % String(res.get("error", "未知错误")), false)
	return false


func request_import_from_path(path: String) -> bool:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_set_status("存档服务不可用", false)
		return false
	var check: Dictionary = p.preview_import_file(path)
	if not bool(check.get("ok", false)):
		_set_status("导入校验失败（原存档未改动）：%s" % String(check.get("error", "无效文件")), false)
		return false
	var s: Dictionary = check.get("summary", {})
	var pref_note := "一并覆盖本地偏好设置" if _overwrite_settings else "保留当前本地画面/音量/主题设置"
	var mig_note := "\n（检测到旧版本存档，已自动完成版本兼容升级）" if bool(check.get("migrated", false)) else ""
	_open_confirm("import_save", "确认导入存档",
		"文件校验通过：%s%s\n信用点 %d · Lv.%d · 天赋 %d · 材料 %d\n导入策略：%s。\n\n导入前当前主存档会自动备份至 .bak，确认覆盖当前进度？" % [
			path.get_file(), mig_note,
			int(s.get("credits", 0)), int(s.get("skill_level", 1)),
			int(s.get("talents", 0)), int(s.get("materials", 0)),
			pref_note,
		],
		0, path)
	return true


func _open_confirm(action: String, title: String, body: String,
		slot: int, import_path: String) -> void:
	_pending_action = action
	_pending_slot = slot
	_pending_import_path = import_path
	if _confirm_title != null:
		_confirm_title.text = title
	if _confirm_body != null:
		_confirm_body.text = body
	if _confirm_overlay != null:
		_confirm_overlay.visible = true
		_confirm_overlay.move_to_front()


func cancel_pending_action() -> void:
	_pending_action = ""
	_pending_slot = 0
	_pending_import_path = ""
	if _confirm_overlay != null:
		_confirm_overlay.visible = false


func confirm_pending_action() -> bool:
	var action := _pending_action
	var slot := _pending_slot
	var import_path := _pending_import_path
	cancel_pending_action()
	var p := get_node_or_null("/root/Progress")
	if p == null:
		_set_status("存档服务不可用", false)
		return false
	match action:
		"clear_slot":
			if p.clear_slot(slot):
				_set_status("已清空槽位 %d（原槽位已备份为 .bak）" % slot, true)
				refresh()
				return true
			_set_status("清空失败：槽位 %d 不存在或已被移除" % slot, false)
			refresh()
			return false
		"reset_progress":
			if p.reset_current_progress(_keep_settings):
				var note := "保留设置" if _keep_settings else "含设置全部重置"
				_set_status("已重置当前进度（%s，旧存档已备份至 .bak）" % note, true)
				refresh()
				slot_loaded.emit(0)
				return true
			_set_status("重置当前进度失败，原存档已保留", false)
			return false
		"import_save":
			var res: Dictionary = p.import_save_from_file(import_path, _overwrite_settings)
			if bool(res.get("ok", false)):
				var note := "已覆盖偏好设置" if _overwrite_settings else "保留本地偏好设置"
				_set_status("导入成功（%s，旧存档已备份至 .bak）" % note, true)
				refresh()
				slot_loaded.emit(0)
				return true
			_set_status("导入失败（原存档未改动）：%s" % String(res.get("error", "未知错误")), false)
			return false
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if is_confirm_open():
			cancel_pending_action()
		else:
			close_menu()
		get_viewport().set_input_as_handled()
