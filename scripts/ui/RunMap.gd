extends Control
## 右上角方形小地图：切角框 + 琥珀色已探索房间，不横跨画面。

var main: Node3D

const SIZE := 210.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.014, 0.020, 0.028, 0.94), true)
	draw_rect(Rect2(Vector2.ZERO, s), PixelUI.AMBER, false, 2.0)
	for p in [Vector2.ZERO, Vector2(s.x - 18, 0.0), Vector2(0.0, s.y - 4), Vector2(s.x - 18, s.y - 4)]:
		draw_rect(Rect2(p, Vector2(18, 4)), PixelUI.AMBER, true)
	for p in [Vector2.ZERO, Vector2(s.x - 4, 0.0), Vector2(0.0, s.y - 18), Vector2(s.x - 4, s.y - 18)]:
		draw_rect(Rect2(p, Vector2(4, 18)), PixelUI.AMBER, true)
	draw_string(PixelUI.FONT, Vector2(14, 34), "区域", HORIZONTAL_ALIGNMENT_LEFT, -1, PixelUI.FS_BODY, PixelUI.AMBER)
	draw_line(Vector2(14, 46), Vector2(s.x - 14, 46), Color(PixelUI.AMBER, 0.35), 1.0)

	if main == null or not is_instance_valid(main.level) or main.doll == null:
		return
	var level: LevelGenerator = main.level
	var origin := Vector2(s.x * 0.5, s.y * 0.58)
	var scale_map := minf((s.x - 36.0) / (level.seg_count * 24.0 + 4.0), 2.4)
	draw_rect(Rect2(origin + Vector2(-1, -3) * scale_map, Vector2(level.seg_count * 24.0 + 2, 6) * scale_map),
		Color(0.30, 0.35, 0.40), false)
	for i in level.rooms.size():
		if not level.explored.has(i):
			continue
		var rect: Rect2 = level.rooms[i]["rect"]
		draw_rect(Rect2(origin + rect.position * scale_map, rect.size * scale_map), PixelUI.AMBER, false, 2.0)
		var door: StaticBody3D = level.rooms[i]["door"]
		var point := origin + Vector2(door.position.x, door.position.z) * scale_map
		draw_line(point - Vector2(4, 0), point + Vector2(4, 0), PixelUI.OK if door.is_open else PixelUI.DANGER, 3)
	draw_circle(origin + Vector2(level.exit_position.x, level.exit_position.z) * scale_map, 4, Color.CYAN)
	draw_circle(origin + Vector2(main.doll.position.x, main.doll.position.z) * scale_map, 4, Color.WHITE)
