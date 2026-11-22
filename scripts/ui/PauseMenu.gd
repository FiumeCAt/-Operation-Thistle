extends CanvasLayer
class_name PauseMenu
## Esc 暂停菜单：音量、动态模糊、摄像机视角。打开时暂停游戏。

signal closed

var main: Node3D

var _root: Control
var _volume: HSlider
var _volume_value: Label
var _blur_button: Button
var _dark_button: Button
var _free_cam_button: Button
var _env_stats: Label
var _camera_buttons: Array[Button] = []

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func setup(m: Node3D) -> void:
	main = m

func _build() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PixelUI.apply_theme(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -340
	panel.offset_bottom = 340
	_root.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)
	PixelUI.label(rows, "暂停 // 设置", PixelUI.FS_TITLE, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	rows.add_child(volume_row)
	var volume_label := PixelUI.label(volume_row, "音量", PixelUI.FS_BODY, PixelUI.DIM)
	volume_label.custom_minimum_size.x = 120
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 100.0
	_volume.step = 5.0
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.custom_minimum_size.y = 28
	volume_row.add_child(_volume)
	_volume_value = PixelUI.label(volume_row, "80%", PixelUI.FS_BODY, PixelUI.TEXT)
	_volume_value.custom_minimum_size.x = 80
	_volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_volume.value_changed.connect(_on_volume_changed)

	var blur_row := HBoxContainer.new()
	blur_row.add_theme_constant_override("separation", 12)
	rows.add_child(blur_row)
	var blur_label := PixelUI.label(blur_row, "动态模糊", PixelUI.FS_BODY, PixelUI.DIM)
	blur_label.custom_minimum_size.x = 120
	blur_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blur_button = PixelUI.button("开", 52)
	_blur_button.custom_minimum_size.x = 180
	_blur_button.pressed.connect(_on_blur_pressed)
	blur_row.add_child(_blur_button)

	var dark_row := HBoxContainer.new()
	dark_row.add_theme_constant_override("separation", 12)
	rows.add_child(dark_row)
	var dark_label := PixelUI.label(dark_row, "场景黑暗", PixelUI.FS_BODY, PixelUI.DIM)
	dark_label.custom_minimum_size.x = 120
	dark_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dark_button = PixelUI.button("开", 52)
	_dark_button.custom_minimum_size.x = 180
	_dark_button.pressed.connect(_on_dark_pressed)
	dark_row.add_child(_dark_button)

	var free_row := HBoxContainer.new()
	free_row.add_theme_constant_override("separation", 12)
	rows.add_child(free_row)
	var free_label := PixelUI.label(free_row, "自由镜头", PixelUI.FS_BODY, PixelUI.DIM)
	free_label.custom_minimum_size.x = 120
	free_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_cam_button = PixelUI.button("关", 52)
	_free_cam_button.custom_minimum_size.x = 180
	_free_cam_button.pressed.connect(_on_free_cam_pressed)
	free_row.add_child(_free_cam_button)

	PixelUI.label(rows, "摄像机视角", PixelUI.FS_BODY, PixelUI.DIM)
	var camera_row := HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 10)
	rows.add_child(camera_row)
	var names := ["完全俯视", "标准", "折中"]
	for i in names.size():
		var button := PixelUI.button(names[i], 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _on_camera_pressed(i))
		camera_row.add_child(button)
		_camera_buttons.append(button)

	var hint := PixelUI.label(rows, "ESC 关闭菜单 · 中键拖动改镜头角 · 滚轮缩放 · ~ 切换自由镜头", PixelUI.FS_BODY, PixelUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 诊断行：直接显示当前环境参数，方便判断"画面发黑"是设置没生效还是别的原因。
	_env_stats = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)
	_env_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var close_button := PixelUI.button("继续游戏", 56)
	close_button.pressed.connect(close)
	rows.add_child(close_button)

func open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if main != null and not bool(main.get("in_base")):
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var progress := get_node_or_null("/root/Progress")
	var data: Dictionary = progress.data if progress else {}
	var volume := float(data.get("volume", 0.8))
	_volume.set_value_no_signal(volume * 100.0)
	_volume_value.text = "%d%%" % roundi(volume * 100.0)
	_blur_button.text = "开" if bool(data.get("motion_blur", true)) else "关"
	_dark_button.text = "关" if bool(data.get("bright_test", false)) else "开"
	var free_rig = main.get("rig") if main != null else null
	var free_on := free_rig != null and bool(free_rig.get("free_camera_enabled"))
	_free_cam_button.text = "开" if free_on else "关"
	var mode := int(data.get("camera_mode", 1))
	for i in _camera_buttons.size():
		_camera_buttons[i].add_theme_color_override(
			"font_color", PixelUI.AMBER_BRIGHT if i == mode else PixelUI.TEXT)
	_update_env_stats()

func _update_env_stats() -> void:
	if _env_stats == null:
		return
	var world = main.get("world_env") if main != null else null
	if world != null and world.environment:
		var e: Environment = world.environment
		_env_stats.text = "环境 ambient %.2f · 曝光 %.2f · 雾 %s" % [
			e.ambient_light_energy, e.tonemap_exposure, "开" if e.fog_enabled else "关"]
	else:
		_env_stats.text = "环境节点未找到"

func _on_volume_changed(value: float) -> void:
	_volume_value.text = "%d%%" % roundi(value)
	var progress := get_node_or_null("/root/Progress")
	if progress:
		progress.set_volume(value / 100.0)
	if main and main.has_method("apply_volume"):
		main.apply_volume(value / 100.0)

func _on_blur_pressed() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	var next := not bool(progress.data.get("motion_blur", true))
	progress.set_motion_blur(next)
	if main:
		main.motion_blur.set_enabled(next)
	_refresh()

func _on_dark_pressed() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	var next_bright := not bool(progress.data.get("bright_test", false))
	progress.set_bright_test(next_bright)
	if main and main.has_method("apply_bright_test"):
		main.apply_bright_test(next_bright)
	_refresh()

func _on_free_cam_pressed() -> void:
	if main and main.has_method("toggle_free_camera"):
		main.toggle_free_camera()
	_refresh()

func _on_camera_pressed(index: int) -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress:
		progress.set_camera_mode(index)
	if main and main.has_method("apply_camera_mode"):
		main.apply_camera_mode(index)
	_refresh()
