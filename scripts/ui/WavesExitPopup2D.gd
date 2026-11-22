extends CanvasLayer
## 浪潮模式每 5 波弹出的撤离窗口：继续挑战，或现在撤离并按 100% 结算。
## 弹窗期间暂停游戏，但自身保持 PROCESS_MODE_ALWAYS，按钮仍可操作。

signal extract_requested
signal continue_requested

var _wave_label: Label
var _continue_button: Button


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -190
	panel.offset_bottom = 190
	root.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)

	PixelUI.label(rows, "浪潮撤离 // EXTRACT", PixelUI.FS_TITLE, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	_wave_label = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.TEXT)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var extract := PixelUI.primary_button("撤离结算（信用点/材料 100%）", 56)
	extract.custom_minimum_size.x = 440
	extract.pressed.connect(_extract)
	rows.add_child(extract)

	_continue_button = PixelUI.button("继续下一波", 52)
	_continue_button.custom_minimum_size.x = 440
	_continue_button.pressed.connect(_continue)
	rows.add_child(_continue_button)

	var hint := PixelUI.label(rows, "ESC 继续", PixelUI.FS_BODY, PixelUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func open(wave: int) -> void:
	if visible:
		return
	_wave_label.text = "第 %d 波已清除。\n现在撤离可按 100%% 回收信用点与材料，或继续挑战更强的下一波。" % wave
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _continue_button != null:
		_continue_button.grab_focus()


func _continue() -> void:
	visible = false
	get_tree().paused = false
	continue_requested.emit()


func _extract() -> void:
	visible = false
	get_tree().paused = false
	extract_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_continue()
		get_viewport().set_input_as_handled()
