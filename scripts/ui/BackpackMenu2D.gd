extends CanvasLayer
class_name BackpackMenu2D
## TAB 背包：左栏本局拾取的物资，右栏仓库库存与信用点。
## 打开时暂停游戏，TAB / ESC 关闭；通过只读快照回调与 opened/closed 信号解耦 Main2D。

signal opened
signal closed

var run: Node2D
var loot_provider: Callable = Callable()
var run_total_label: Label
var stash_credit_label: Label
## 测试与外部读取用：资源 id → 数量标签。
var run_count_labels := {}
var stash_count_labels := {}

var _open := false
var _panel: PanelContainer


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func setup(target: Node2D) -> void:
	run = target
	if target != null and target.has_method("get_loot_snapshot"):
		loot_provider = target.get_loot_snapshot
	else:
		loot_provider = Callable()


func set_loot_provider(provider: Callable) -> void:
	loot_provider = provider


func is_open() -> bool:
	return _open


func _build() -> void:
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -520
	_panel.offset_right = 520
	_panel.offset_top = -330
	_panel.offset_bottom = 330
	root.add_child(_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	_panel.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := PixelUI.label(header, "战术背包 // BACKPACK", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	PixelUI.label(header, "TAB / ESC 关闭", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	layout.add_child(divider)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)

	columns.add_child(_build_run_column())
	columns.add_child(_build_stash_column())

	var footer := PixelUI.label(layout,
		"撤离成功后本局物资并入仓库 · 阵亡则全部丢失", PixelUI.FS_BODY, PixelUI.DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_run_column() -> Control:
	var panel := _column_panel()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	PixelUI.label(rows, "本局拾取 // THIS RUN", PixelUI.FS_BODY, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	for id in ResourceDB.BASIC:
		_build_resource_row(rows, id, run_count_labels)
	PixelUI.label(rows, "进阶 // RARE", PixelUI.FS_BODY, PixelUI.DIM)
	for id in ResourceDB.ADVANCED:
		_build_resource_row(rows, id, run_count_labels)
	run_total_label = PixelUI.label(rows, "共 0 件", PixelUI.FS_BODY, PixelUI.TEXT)
	run_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return panel


func _build_stash_column() -> Control:
	var panel := _column_panel()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	PixelUI.label(rows, "仓库 // STASH", PixelUI.FS_BODY, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	var credit_row := HBoxContainer.new()
	credit_row.add_theme_constant_override("separation", 8)
	rows.add_child(credit_row)
	PixelUI.icon(credit_row, "res_credit", 24)
	var credit_name := PixelUI.label(credit_row, "信用点", PixelUI.FS_BODY, PixelUI.DIM)
	credit_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stash_credit_label = PixelUI.label(credit_row, "0", PixelUI.FS_BODY, PixelUI.AMBER)
	for id in ResourceDB.BASIC:
		_build_resource_row(rows, id, stash_count_labels)
	PixelUI.label(rows, "进阶 // RARE", PixelUI.FS_BODY, PixelUI.DIM)
	for id in ResourceDB.ADVANCED:
		_build_resource_row(rows, id, stash_count_labels)
	return panel


func _column_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _build_resource_row(parent: Node, id: StringName, target: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	PixelUI.icon(row, "res_" + String(id), 24)
	var name_label := PixelUI.label(row, ResourceDB.display_name(id), PixelUI.FS_BODY, PixelUI.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := PixelUI.label(row, "0", PixelUI.FS_BODY, PixelUI.DIM)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	target[String(id)] = count


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	refresh()
	opened.emit()
	get_tree().paused = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()
	get_tree().paused = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func refresh() -> void:
	var snap: Dictionary = {}
	if loot_provider.is_valid():
		var data = loot_provider.call()
		if data is Dictionary:
			snap = data
	elif run != null and run.has_method("get_loot_snapshot"):
		var data = run.get_loot_snapshot()
		if data is Dictionary:
			snap = data
	else:
		return
	var loot: Dictionary = snap.get("basic", {})
	var advanced: Dictionary = snap.get("advanced", {})
	var total := 0
	for id in ResourceDB.BASIC:
		var value := int(loot.get(String(id), 0))
		total += value
		_set_count(run_count_labels, id, value)
	for id in ResourceDB.ADVANCED:
		var value := int(advanced.get(String(id), 0))
		total += value
		_set_count(run_count_labels, id, value)
	run_total_label.text = "共 %d 件" % total

	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	stash_credit_label.text = str(progress.credits())
	for id in ResourceDB.BASIC:
		_set_count(stash_count_labels, id, progress.material_count(id))
	for id in ResourceDB.ADVANCED:
		_set_count(stash_count_labels, id, progress.advanced_count(id))


func _set_count(target: Dictionary, id: StringName, value: int) -> void:
	var label: Label = target.get(String(id))
	if label == null:
		return
	label.text = str(value)
	label.add_theme_color_override("font_color", PixelUI.TEXT if value > 0 else PixelUI.DIM)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var close_requested := event.is_action_pressed("ui_cancel")
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_TAB:
		close_requested = true
	if close_requested:
		close()
		get_viewport().set_input_as_handled()
