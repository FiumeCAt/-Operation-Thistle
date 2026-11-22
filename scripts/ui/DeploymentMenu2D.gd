extends Control
class_name DeploymentMenu2D
## 部署界面：选择出生点，每个出生点绑定不同的默认撤离点。
## 两个撤离点（东侧闸门 / 南侧维修门）本局都可用，部署点只决定“默认”与安全区。

signal deploy_confirmed(spawn_id: StringName, extract_id: StringName)
signal closed

const PANEL_SIZE := Vector2(1060, 640)
const MAP_NAMES := {
	"facility": "设施浪潮",
	"goliath_arena": "歌利亚狂潮",
}

var _spawn_id: StringName = &"insertion"
var _spawn_buttons: Dictionary = {}
var _spawn_list: VBoxContainer
var _map_row: HBoxContainer
var _map_buttons: Dictionary = {}
## 当前浪潮地图：facility 设施 / goliath_arena 歌利亚狂潮。
var selected_map_id := "facility"
var _spawn_name: Label
var _route: Label
var _default_exit: Label
var _safe_zone: Label
var _subtitle: Label
var _available_exits: Label
var _power_note: Label
var _confirm_button: Button
## raid = 正常搜刮撤离；waves = 浪潮生存，撤离走每 5 波弹窗。
var _mode := "raid"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(self)
	_build()
	if _map_row != null:
		_map_row.visible = _mode == "waves"
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
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)

	PixelUI.label(rows, "部署 // DEPLOYMENT", PixelUI.FS_TITLE, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)
	_subtitle = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)

	# 浪潮模式专属地图选择：设施浪潮 / 歌利亚狂潮。
	_map_row = HBoxContainer.new()
	_map_row.add_theme_constant_override("separation", 8)
	rows.add_child(_map_row)
	for map_id in MAP_NAMES:
		var map_button := PixelUI.button(MAP_NAMES[map_id], 44)
		map_button.custom_minimum_size.x = 260
		map_button.pressed.connect(func() -> void: _select_map(String(map_id)))
		_map_row.add_child(map_button)
		_map_buttons[map_id] = map_button

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(content)

	_spawn_list = VBoxContainer.new()
	_spawn_list.add_theme_constant_override("separation", 10)
	_spawn_list.custom_minimum_size.x = 500
	content.add_child(_spawn_list)
	for spawn_id in Level2D.SPAWNS:
		var def: Dictionary = Level2D.SPAWNS[spawn_id]
		var button := PixelUI.button("", 96)
		button.custom_minimum_size.x = 500
		button.pressed.connect(func() -> void: _select(spawn_id))
		_spawn_list.add_child(button)
		_spawn_buttons[spawn_id] = button

	var detail := PixelUI.panel()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(detail)
	var detail_rows := VBoxContainer.new()
	detail_rows.add_theme_constant_override("separation", 10)
	detail.add_child(detail_rows)

	_spawn_name = PixelUI.label(detail_rows, "", PixelUI.FS_TITLE, PixelUI.AMBER)
	var detail_divider := HSeparator.new()
	detail_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.6))
	detail_rows.add_child(detail_divider)
	_route = _detail_row(detail_rows, "进入路线")
	_default_exit = _detail_row(detail_rows, "默认撤离")
	_safe_zone = _detail_row(detail_rows, "安全区")
	_available_exits = _detail_row(detail_rows, "撤离方式")
	_power_note = PixelUI.label(detail_rows,
		"恢复供电后，军械库货运电梯可额外拉闸撤离。", PixelUI.FS_BODY, PixelUI.DIM)

	_confirm_button = PixelUI.button("确认部署", 54)
	_confirm_button.custom_minimum_size.x = 320
	_confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_confirm_button.pressed.connect(_confirm)
	rows.add_child(_confirm_button)

	var cancel := PixelUI.button("取消", 46)
	cancel.custom_minimum_size.x = 260
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(close_menu)
	rows.add_child(cancel)


func _detail_row(parent: Node, title: String) -> Label:
	var line := HBoxContainer.new()
	parent.add_child(line)
	var key := PixelUI.label(line, title, PixelUI.FS_BODY, PixelUI.DIM)
	key.custom_minimum_size.x = 110
	var value := PixelUI.label(line, "-", PixelUI.FS_BODY, PixelUI.TEXT)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return value


func open() -> void:
	_spawn_id = &"insertion"
	selected_map_id = "facility"
	var p := get_node_or_null("/root/Progress")
	if p != null:
		var dep: Dictionary = p.deployment()
		var id := StringName(dep.get("spawn", "insertion"))
		if Level2D.SPAWNS.has(id):
			_spawn_id = id
		if _mode == "waves" and p.has_method("map_id") \
				and String(p.map_id()) == "goliath_arena":
			selected_map_id = "goliath_arena"
	_refresh_mode()
	_refresh()
	move_to_front()
	visible = true
	if _confirm_button != null:
		_confirm_button.grab_focus()


## 由开始菜单在打开部署页前调用，切换本次行动模式。
func set_mode(mode: String) -> void:
	_mode = "waves" if mode == "waves" else "raid"
	if _mode != "waves":
		selected_map_id = "facility"
	_refresh_mode()


func _select_map(map_id: String) -> void:
	if not MAP_NAMES.has(map_id):
		return
	selected_map_id = map_id
	_refresh_mode()
	_refresh()


func _refresh_map_buttons() -> void:
	for id in _map_buttons:
		var button: Button = _map_buttons[id]
		var marker := "▶ " if id == selected_map_id else "   "
		button.text = marker + String(MAP_NAMES[id])


func _refresh_mode() -> void:
	if _subtitle == null:
		return
	if _map_row != null:
		_map_row.visible = _mode == "waves"
	if _mode == "waves":
		if selected_map_id == "goliath_arena":
			_subtitle.text = "歌利亚狂潮：开阔平地，只刷新歌利亚；每波结束回满状态与弹药"
		else:
			_subtitle.text = "设施浪潮：在设施内迎接一波波更强的进攻，每 5 波可撤离"
		if _available_exits != null:
			_available_exits.text = "每 5 波撤离弹窗（100%）/ ESC 提前撤离（30%）"
		_refresh_map_buttons()
	else:
		_subtitle.text = "选择进入点 · 出生点决定默认撤离点与安全区"
		if _available_exits != null:
			_available_exits.text = "东侧闸门 / 南侧维修门（本局都可用）"


func close_menu() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _select(id: StringName) -> void:
	if not Level2D.SPAWNS.has(id):
		return
	_spawn_id = id
	_refresh()


func _refresh() -> void:
	if _mode == "waves" and selected_map_id == "goliath_arena":
		_spawn_list.visible = false
		_spawn_id = &"insertion"
		_spawn_name.text = "歌利亚狂潮"
		_route.text = "固定部署 · 竞技场中央"
		_default_exit.text = "每 5 波撤离弹窗"
		_safe_zone.text = "全图开阔平地 · 无掩体"
		_available_exits.text = "每 5 波撤离 100% / ESC 提前撤离 30%"
		_confirm_button.text = "进入歌利亚狂潮"
		if _power_note != null:
			_power_note.visible = false
		return

	_spawn_list.visible = true
	_confirm_button.text = "确认部署"
	if _power_note != null:
		_power_note.visible = true
	for id in _spawn_buttons:
		var def: Dictionary = Level2D.SPAWNS[id]
		var marker := "▶ " if id == _spawn_id else "   "
		var exit_def: Dictionary = Level2D.EXTRACTS[def["default_exit"]]
		var button: Button = _spawn_buttons[id]
		button.text = "%s%s\n默认撤离：%s" % [marker, String(def["name"]), String(exit_def["name"])]

	var def: Dictionary = Level2D.SPAWNS[_spawn_id]
	var exit_def: Dictionary = Level2D.EXTRACTS[def["default_exit"]]
	_spawn_name.text = String(def["name"])
	_route.text = String(def["route"])
	_default_exit.text = String(exit_def["name"])
	var safe_names: Array[String] = []
	for index in def["safe_rooms"]:
		safe_names.append(String(Level2D.ROOM_DEFS[int(index)]["name"]))
	_safe_zone.text = "、".join(safe_names) + "（不会刷怪）"


func _confirm() -> void:
	var def: Dictionary = Level2D.SPAWNS[_spawn_id]
	visible = false
	deploy_confirmed.emit(_spawn_id, def["default_exit"])
