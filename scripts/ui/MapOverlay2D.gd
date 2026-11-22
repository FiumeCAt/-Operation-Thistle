extends CanvasLayer
class_name MapOverlay2D
## M 键全屏设施地图：房间名、玩家位置/朝向、出生点、两个常开撤离点、供电与货运电梯。
## 打开时暂停游戏，M / ESC 关闭。

var run: Node2D
var _open := false
var _view: _MapView


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func setup(target: Node2D) -> void:
	run = target
	if _view != null:
		_view.run = target


func _build() -> void:
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -620
	panel.offset_right = 620
	panel.offset_top = -400
	panel.offset_bottom = 400
	root.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "K-17 // 设施地图", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "M / ESC 关闭", PixelUI.FS_BODY, PixelUI.DIM)

	_view = _MapView.new()
	_view.custom_minimum_size = Vector2(1180, 660)
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_view)

	PixelUI.label(rows, "白 玩家 · 青 撤离点 · 金 货运电梯 · 蓝 供电 · 琥珀 未搜刮补给 · 红 浪潮收尾敌人",
		PixelUI.FS_BODY, PixelUI.DIM)


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	if run != null:
		if run.get("hud") != null:
			run.hud.visible = false
		if run.get("reticle") != null:
			run.reticle.visible = false
	get_tree().paused = true
	if _view != null:
		_view.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if run != null:
		if run.get("hud") != null:
			run.hud.visible = true
		if run.get("reticle") != null:
			run.reticle.visible = true
	get_tree().paused = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_M:
		close()
		get_viewport().set_input_as_handled()


class _MapView extends Control:
	var run: Node2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(_delta: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.012, 0.018, 0.026, 0.9), true)
		if run == null or run.doll == null:
			return
		var level := run.level as Level2D
		if level == null:
			return
		var area := Rect2(Vector2(12, 12), s - Vector2(24, 24))
		var map_size: Vector2 = level.map_size()
		var scale := minf(area.size.x / map_size.x, area.size.y / map_size.y)
		var offset := area.position + (area.size - map_size * scale) * 0.5

		for rect in level.map_floor_rects():
			var r := Rect2(
				offset + Vector2(rect.position) * Level2D.TILE * scale,
				Vector2(rect.size) * Level2D.TILE * scale,
			)
			draw_rect(r, Color(0.24, 0.27, 0.30, 0.95), true)
		for room in level.rooms:
			var rect: Rect2 = room["rect"]
			var r := Rect2(offset + rect.position * scale, rect.size * scale)
			draw_rect(r, Color(PixelUI.AMBER, 0.14), true)
			draw_rect(r, Color(PixelUI.AMBER, 0.45), false, 1.0)

		for entry in level.containers:
			if not bool(entry["searched"]):
				var pos: Vector2 = entry["position"]
				draw_circle(offset + pos * scale, 3.0, Color(0.95, 0.68, 0.24, 0.9))

		for exit_data in level.exits:
			var pos: Vector2 = exit_data["position"]
			var p := offset + pos * scale
			draw_circle(p, 7.0, Color(0.16, 0.86, 0.76, 0.95))
			draw_circle(p, 3.0, Color(0.02, 0.10, 0.09, 0.95))
			var name := String(exit_data["name"])
			draw_string(PixelUI.FONT, p + Vector2(-name.length() * 7.0, 24),
				name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.96, 0.88, 0.9))

		var lift := offset + level.switch_exit_position * scale
		draw_circle(lift, 6.0,
			PixelUI.OK if level.power_on else Color(0.62, 0.52, 0.35, 0.85))
		var power := offset + level.power_position * scale
		draw_circle(power, 6.0,
			PixelUI.OK if level.power_on else Color(0.35, 0.72, 0.95, 0.9))

		# 浪潮收尾追踪：剩余敌人很少时，大地图也标红所有敌人。
		var tracking := run.has_method("waves_tracking_active") \
			and bool(run.waves_tracking_active())
		if tracking:
			for enemy in run.enemies:
				if not is_instance_valid(enemy):
					continue
				var ep: Vector2 = offset + enemy.global_position * scale
				draw_circle(ep, 6.2, Color(1.0, 0.16, 0.10, 0.26))
				draw_circle(ep, 3.4, Color(1.0, 0.20, 0.12, 1.0))
				draw_arc(ep, 6.8, 0.0, TAU, 16, Color(1.0, 0.35, 0.20, 0.7), 1.2)

		var spawn := offset + level.player_spawn * scale
		draw_arc(spawn, 9.0, 0.0, TAU, 24, Color(0.92, 0.92, 0.92, 0.8), 2.0)
		draw_string(PixelUI.FONT, spawn + Vector2(-21, -16), "部署点",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85, 0.75))

		var player: Vector2 = run.doll.global_position
		var p := offset + player * scale
		var dir: Vector2 = (run.doll.aim_target - player).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var side := Vector2(-dir.y, dir.x) * 7.0
		draw_colored_polygon(PackedVector2Array([
			p + dir * 11.0, p - dir * 5.0 + side, p - dir * 5.0 - side,
		]), Color(0.92, 1.0, 0.94, 1.0))
		draw_circle(p, 2.5, Color(0.1, 0.2, 0.15, 1.0))

		# 房间名最后画，盖住补给点等小标记，保持文字可读。
		for room in level.rooms:
			var rect: Rect2 = room["rect"]
			var label := String(room["name"])
			var text_pos := offset + rect.position * scale + Vector2(6.0, 18.0)
			draw_string_outline(PixelUI.FONT, text_pos, label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0.02, 0.02, 0.03, 0.9))
			draw_string(PixelUI.FONT, text_pos, label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.78, 0.55, 0.95))
