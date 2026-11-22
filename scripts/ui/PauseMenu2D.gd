extends CanvasLayer
class_name PauseMenu2D
## 2D 游戏内 ESC 菜单：暂停/继续、设置、重新开始、返回主菜单、退出。
## 设置页与开始菜单共用同一个 SettingsMenu2D，读写同一份 Progress 存档，
## 所以两边永远看到同一套选项和同一组数值。

signal closed
## 设置页关闭时发出，供本局重新应用画面设置（缩放 / 抖动）。
signal settings_applied
## 浪潮模式专属：从 ESC 菜单提前撤离（按 30% 结算）。
signal retreat_requested

var _resume: Button
var _settings_button: Button
var _retreat: Button
var settings_menu: SettingsMenu2D


func _ready() -> void:
	layer = 100
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
	dim.color = Color(0.0, 0.0, 0.0, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -300
	panel.offset_bottom = 300
	root.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)

	PixelUI.label(rows, "已暂停 // PAUSED", PixelUI.FS_TITLE, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	_resume = PixelUI.button("继续行动", 56)
	_resume.custom_minimum_size.x = 360
	_resume.pressed.connect(close)
	rows.add_child(_resume)

	_settings_button = PixelUI.button("设置 // SETTINGS", 56)
	_settings_button.custom_minimum_size.x = 360
	_settings_button.pressed.connect(_open_settings)
	rows.add_child(_settings_button)

	# 仅浪潮模式显示：提前撤离并按 30% 结算。
	_retreat = PixelUI.button("提前撤离（30% 结算）", 52)
	_retreat.custom_minimum_size.x = 360
	_retreat.visible = false
	_retreat.pressed.connect(_retreat_action)
	rows.add_child(_retreat)

	var restart := PixelUI.button("重新开始", 56)
	restart.custom_minimum_size.x = 360
	restart.pressed.connect(_restart)
	rows.add_child(restart)

	var menu_btn := PixelUI.button("返回主菜单", 56)
	menu_btn.custom_minimum_size.x = 360
	menu_btn.pressed.connect(_main_menu)
	rows.add_child(menu_btn)

	var quit := PixelUI.button("退出游戏", 56)
	quit.custom_minimum_size.x = 360
	quit.pressed.connect(_quit_game)
	rows.add_child(quit)

	var hint := PixelUI.label(rows, "ESC 返回 / 继续", PixelUI.FS_BODY, PixelUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 与开始菜单完全相同的设置面板，避免两边选项漂移。
	settings_menu = SettingsMenu2D.new()
	settings_menu.name = "SettingsMenu2D"
	settings_menu.closed.connect(_close_settings)
	root.add_child(settings_menu)


func _open_settings() -> void:
	settings_menu.open()


func _close_settings() -> void:
	if _settings_button != null:
		_settings_button.grab_focus()
	settings_applied.emit()


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _resume != null:
		_resume.grab_focus()


func close() -> void:
	if not visible:
		return
	if settings_menu != null and settings_menu.visible:
		settings_menu.close_menu()
	visible = false
	get_tree().paused = false
	closed.emit()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


## 浪潮模式：先恢复时间，再交给 Main2D 走 30% 结算。
func _retreat_action() -> void:
	close()
	retreat_requested.emit()


## 由 Main2D 在浪潮模式开局时调用，显示提前撤离入口。
func set_waves_mode(enabled: bool) -> void:
	if _retreat != null:
		_retreat.visible = enabled


func _main_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")


## 退出前先写盘：主存档 + 当前槽位，避免从 ESC 菜单退出时丢进度。
func _quit_game() -> void:
	get_tree().paused = false
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.autosave_on_exit()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if settings_menu != null and settings_menu.visible:
			settings_menu.close_menu()
		else:
			close()
		get_viewport().set_input_as_handled()
