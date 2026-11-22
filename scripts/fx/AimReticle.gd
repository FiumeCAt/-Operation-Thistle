extends CanvasLayer
class_name AimReticle
## 屏幕空间动态准心（纯程序绘制，不用贴图）。
## 位置：跟随鼠标光标（鼠标即瞄准点，与角色 aim_point 一致）。
## 半径：按当前弹种的真实散布锥在瞄准距离处换算成屏幕像素，所以环有多大就代表打得有多散。
## 形态：腰射 = 宽虚线圆环 + 四刻度；瞄准 = 精确十字 + 细环 + 枪口指向线。

const COLOR_HIP := Color(1.0, 0.72, 0.28)
const COLOR_AIM := Color(0.42, 0.92, 1.0)
const COLOR_BLOCKED := Color(0.96, 0.34, 0.28)

@export_range(100.0, 140.0) var wall_window_radius := 120.0
var doll: Doll
var wall_level: LevelGenerator
var _window_focused := true

func _update_wall_window(enabled: bool) -> void:
	if is_instance_valid(wall_level):
		wall_level.update_wall_window(_pos, get_viewport().get_visible_rect().size, wall_window_radius, enabled)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		_update_wall_window(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_update_wall_window(false)

var _view: RetView
var _pos := Vector2.ZERO
var _aim_mix := 0.0              # 0=腰射 1=瞄准
var _blocked := false
var _muzzle_screen := Vector2.ZERO
var _aim_world := Vector3.ZERO

func _ready() -> void:
	layer = 5
	_view = RetView.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)

func setup(d: Doll) -> void:
	doll = d

func _process(dt: float) -> void:
	if not is_instance_valid(doll) or doll.is_dead or get_tree().paused or not visible or not _window_focused:
		_update_wall_window(false)
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_update_wall_window(false)
		return

	# ---- 位置：1:1 跟鼠标，不做插值（准心任何拖尾都会让手感变糊）
	_pos = doll.camera_rig.aim_screen_position() if doll.camera_rig else get_viewport().get_mouse_position()
	_update_wall_window(true)

	# ---- 瞄准状态
	var aiming := Input.is_action_pressed("aim") or doll.debug_state == "aim"
	_aim_mix = move_toward(_aim_mix, 1.0 if aiming else 0.0, dt * 8.0)

	var wpn: PlayerWeapon = doll.weapon
	if wpn == null or wpn.weapon == null:
		return
	var aim := wpn.query_aim()
	if aim.is_empty():
		return
	_aim_world = aim["end"]
	var muzzle: Vector3 = aim["origin"]
	_muzzle_screen = cam.unproject_position(muzzle)
	_blocked = aim["blocked"]
	var axis: Vector3 = aim["direction"]
	var depth: float = aim["aim_distance"]
	if _blocked:
		depth = minf(depth, muzzle.distance_to(_aim_world))
	var outline := PackedVector2Array()
	if not aim["muzzle_blocked"]:
		for i in 65:
			var edge := wpn.get_cone_direction(axis, 1.0, TAU * float(i) / 64.0)
			var point := muzzle + edge * depth / maxf(edge.dot(axis), 0.001)
			if cam.is_position_behind(point):
				outline.clear()
				break
			outline.append(cam.unproject_position(point))

	_view.center = _pos
	_view.muzzle = _muzzle_screen
	_view.aim_mix = _aim_mix
	_view.blocked = _blocked
	_view.outline = outline
	_view.impact = cam.unproject_position(_aim_world)
	_view.show_impact = (_blocked or aim["behind_muzzle"]) and not cam.is_position_behind(_aim_world)
	_view.queue_redraw()


class RetView extends Control:
	var center := Vector2.ZERO
	var muzzle := Vector2.ZERO
	var aim_mix := 0.0
	var blocked := false
	var outline := PackedVector2Array()
	var impact := Vector2.ZERO
	var show_impact := false

	func _draw() -> void:
		if center == Vector2.ZERO:
			return
		var col := COLOR_HIP.lerp(COLOR_AIM, aim_mix)
		if blocked:
			col = col.lerp(COLOR_BLOCKED, 0.6)

		if aim_mix > 0.1:
			draw_line(muzzle, impact if show_impact else center, Color(col.r, col.g, col.b, 0.16 * aim_mix), 1.0)
		for i in maxi(0, outline.size() - 1):
			if aim_mix > 0.5 or i % 4 < 2:
				draw_line(outline[i], outline[i + 1], Color(col.r, col.g, col.b, 0.42), 1.0)
		for i in 4:
			var angle := TAU * float(i) / 4.0
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(center + direction * 5.0, center + direction * 16.0, Color.BLACK, 5.0, true)
			draw_line(center + direction * 6.0, center + direction * 15.0, Color.WHITE, 2.5, true)
		draw_circle(center, 3.3, Color.BLACK, true, -1.0, true)
		draw_circle(center, 1.8, Color.WHITE, true, -1.0, true)
		if show_impact:
			draw_arc(impact, 7.0, 0.0, TAU, 32, Color.BLACK, 5.0, true)
			draw_arc(impact, 7.0, 0.0, TAU, 32, COLOR_BLOCKED, 2.5, true)
			for diagonal in [Vector2(4, 4), Vector2(4, -4)]:
				draw_line(impact - diagonal, impact + diagonal, Color.BLACK, 5.0, true)
				draw_line(impact - diagonal, impact + diagonal, COLOR_BLOCKED, 2.5, true)

