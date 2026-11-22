extends Control
class_name StashMenu2D
## 主菜单仓库：只读展示信用点与全部资源的库存。
## 数据来自 Progress，打开时刷新；不消耗任何资源。

signal closed

const PANEL_SIZE := Vector2(1080, 600)

var _credit_value: Label
var _basic_total: Label
var _advanced_total: Label
var _summary: Label
var _counts: Dictionary = {}
var _back_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
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

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "仓库 // STASH", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "ESC 关闭", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 12)
	rows.add_child(summary)
	PixelUI.icon(summary, "res_credit", 36)
	var credit_name := PixelUI.label(summary, "信用点", PixelUI.FS_BODY, PixelUI.DIM)
	credit_name.custom_minimum_size.x = 96
	_credit_value = PixelUI.label(summary, "0", PixelUI.FS_TITLE, PixelUI.AMBER)
	_credit_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = PixelUI.label(summary, "", 20, PixelUI.DIM)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	columns.add_child(_build_column("基础资源 // BASIC", ResourceDB.BASIC))

	var advanced := _build_column("进阶资源 // RARE", ResourceDB.ADVANCED)
	columns.add_child(advanced)

	var footer := PixelUI.label(rows,
		"资源在武备库与天赋树中消耗 · 成功撤离后并入仓库",
		PixelUI.FS_BODY, PixelUI.DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_back_button = PixelUI.button("返回", 46)
	_back_button.custom_minimum_size.x = 280
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(close_menu)
	rows.add_child(_back_button)


func _build_column(title: String, ids: Array[StringName]) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var label := PixelUI.label(header, title, PixelUI.FS_BODY, PixelUI.AMBER)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var total := PixelUI.label(header, "共 0 件", 20, PixelUI.DIM)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if ids == ResourceDB.BASIC:
		_basic_total = total
	else:
		_advanced_total = total

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)

	for id in ids:
		_resource_row(rows, id)
	return panel


func _resource_row(parent: Node, id: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	PixelUI.icon(row, "res_" + String(id), 56)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	PixelUI.label(info, ResourceDB.display_name(id), PixelUI.FS_BODY, PixelUI.TEXT)
	var desc := PixelUI.label(info, _desc(id), 18, PixelUI.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_OFF
	var count := PixelUI.label(row, "0", PixelUI.FS_TITLE, PixelUI.TEXT)
	count.custom_minimum_size.x = 84
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counts[String(id)] = count


func _desc(id: StringName) -> String:
	return String(ResourceDB.DATA.get(id, {}).get("desc", ""))


func open() -> void:
	visible = true
	move_to_front()
	_refresh()
	if _back_button != null:
		_back_button.grab_focus()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _refresh() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	_credit_value.text = str(p.credits())
	var basic_total := 0
	for id in ResourceDB.BASIC:
		var value: int = p.material_count(id)
		basic_total += value
		_set_count(id, value)
	var advanced_total := 0
	for id in ResourceDB.ADVANCED:
		var value: int = p.advanced_count(id)
		advanced_total += value
		_set_count(id, value)
	_basic_total.text = "共 %d 件" % basic_total
	_advanced_total.text = "共 %d 件" % advanced_total
	_summary.text = "资源合计 %d 件" % (basic_total + advanced_total)


func _set_count(id: StringName, value: int) -> void:
	var label: Label = _counts.get(String(id))
	if label == null:
		return
	label.text = str(value)
	label.add_theme_color_override("font_color", PixelUI.TEXT if value > 0 else PixelUI.DIM)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
