extends Control
class_name Minimap2D
## 右上角 K-17 小地图：房间轮廓、目标点、玩家朝向与近距离敌情。
## 每 0.1 秒重绘一次，避免每帧重建绘制指令。

const SIZE := Vector2(320, 224)
const MAP_MARGIN := 10.0
const HEADER := 30.0
## 只显示玩家附近的敌人，保留探索紧张感。
const ENEMY_RADIUS := 760.0

var run: Node2D

var _tick := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	set_process(true)


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 0.1:
		_tick = 0.0
		queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.010, 0.016, 0.024, 0.92), true)
	draw_rect(Rect2(Vector2.ZERO, s), Color(PixelUI.AMBER, 0.85), false, 2.0)
	for p in [Vector2.ZERO, Vector2(s.x - 16, 0), Vector2(0, s.y - 4), Vector2(s.x - 16, s.y - 4)]:
		draw_rect(Rect2(p, Vector2(16, 4)), PixelUI.AMBER, true)
	for p in [Vector2.ZERO, Vector2(s.x - 4, 0), Vector2(0, s.y - 16), Vector2(s.x - 4, s.y - 16)]:
		draw_rect(Rect2(p, Vector2(4, 16)), PixelUI.AMBER, true)
	draw_string(PixelUI.FONT, Vector2(12, 24), "K-17 // MAP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PixelUI.AMBER)
	draw_line(Vector2(12, 34), Vector2(s.x - 12, 34), Color(PixelUI.AMBER, 0.3), 1.0)

	if run == null or run.doll == null:
		return
	var level := run.level as Level2D
	if level == null:
		return

	var area := Rect2(Vector2(MAP_MARGIN, HEADER + 6),
		s - Vector2(MAP_MARGIN * 2.0, HEADER + 16.0))
	var map_size: Vector2 = level.map_size()
	var scale := minf(area.size.x / map_size.x, area.size.y / map_size.y)
	var offset := area.position + (area.size - map_size * scale) * 0.5

	for rect in level.map_floor_rects():
		var r := Rect2(
			offset + Vector2(rect.position) * Level2D.TILE * scale,
			Vector2(rect.size) * Level2D.TILE * scale,
		)
		draw_rect(r, Color(0.26, 0.29, 0.32, 0.95), true)
	for room in level.rooms:
		var rect: Rect2 = room["rect"]
		draw_rect(Rect2(offset + rect.position * scale, rect.size * scale),
			Color(PixelUI.AMBER, 0.22), true)
		draw_rect(Rect2(offset + rect.position * scale, rect.size * scale),
			Color(PixelUI.AMBER, 0.55), false, 1.0)

	for entry in level.containers:
		if not bool(entry["searched"]):
			var container_pos: Vector2 = entry["position"]
			draw_circle(offset + container_pos * scale, 1.4,
				Color(0.95, 0.68, 0.24, 0.75))

	draw_circle(offset + level.power_position * scale, 3.2,
		PixelUI.OK if level.power_on else Color(0.35, 0.72, 0.95, 0.95))
	draw_circle(offset + level.switch_exit_position * scale, 3.2,
		PixelUI.OK if level.power_on else Color(0.55, 0.50, 0.40, 0.8))
	draw_circle(offset + level.exit_position * scale, 3.8, Color(0.22, 0.88, 0.78, 0.95))

	var player: Vector2 = run.doll.global_position
	# 浪潮收尾：剩余敌人很少时取消距离裁剪，所有敌人标红，方便追踪。
	var tracking := run.has_method("waves_tracking_active") \
		and bool(run.waves_tracking_active())
	for enemy in run.enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := player.distance_to(enemy.global_position)
		if not tracking and dist >= ENEMY_RADIUS:
			continue
		var p: Vector2 = offset + enemy.global_position * scale
		if tracking:
			draw_circle(p, 2.6, Color(1.0, 0.20, 0.12, 1.0))
			draw_arc(p, 4.6, 0.0, TAU, 12, Color(1.0, 0.30, 0.18, 0.75), 1.0)
		else:
			draw_circle(p, 1.8, Color(0.95, 0.32, 0.26, 0.9))

	var p := offset + player * scale
	var dir: Vector2 = (run.doll.aim_target - player).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	draw_circle(p, 3.6, Color(0.90, 0.96, 1.0, 1.0))
	draw_line(p, p + dir * 10.0, Color(0.90, 0.96, 1.0, 0.95), 2.0)
	draw_string(PixelUI.FONT, Vector2(s.x - 26, HEADER + 16), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelUI.DIM)
