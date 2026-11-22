extends CanvasLayer
class_name AimReticle2D

## 游戏内准心：四线间距随武器散布缩放，ADS 收紧；同时隐藏系统光标。
## 只有 ADS 时额外显示墙面弹着小点与暗角聚焦。

const COLOR_POINT := Color(0.88, 0.92, 0.88, 0.92)
const COLOR_BLOCKED := Color(0.96, 0.58, 0.48, 0.95)
const HIT_TIME := 0.14
## ADS 时屏幕四周轻微压暗，形成聚焦感，不改变中心视野。
const VIGNETTE_ALPHA := 0.26
## 准心间距：把散布锥角投影到鼠标的实际距离，再乘当前 zoom 换成屏幕像素。
## 上限放宽到 56px，全自动积满时准心能真正散开，不会提前顶到上限。
const BASE_GAP := 4.0
const MIN_GAP := 4.0
const MAX_GAP := 56.0
const TICK_LEN := 5.0
const GAP_SPEED := 14.0

var main: Node2D
var _view: RetView
var _vignette: TextureRect
var _hit_t := 0.0
var _cursor_hidden := false
var _focused := true
var _gap := BASE_GAP


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vignette = TextureRect.new()
	_vignette.name = "AdsVignette"
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture = _make_vignette_texture()
	_vignette.modulate.a = 0.0
	_vignette.visible = false
	add_child(_vignette)
	_view = RetView.new()
	_view.name = "RetView"
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)


## 中心透明、边缘渐暗的径向渐变，运行时生成，不需要额外贴图。
func _make_vignette_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 1))
	gradient.add_point(0.55, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _ads_blend() -> float:
	if main != null and main.doll != null and main.doll.weapon_rig != null:
		return clampf(main.doll.weapon_rig.get_ads_blend(), 0.0, 1.0)
	return 1.0 if main != null and main.doll != null and main.doll.ads else 0.0


func _set_vignette(target: float, delta: float) -> void:
	_vignette.modulate.a = move_toward(_vignette.modulate.a, target, delta * 1.8)
	_vignette.visible = _vignette.modulate.a > 0.002


## 游戏内隐藏系统光标；UI/暂停/结束时恢复，避免箭头挡住准心。
func _set_cursor_hidden(hidden: bool) -> void:
	if hidden and not _focused:
		hidden = false
	var mode := Input.MOUSE_MODE_HIDDEN if hidden else Input.MOUSE_MODE_VISIBLE
	if Input.get_mouse_mode() == mode:
		_cursor_hidden = hidden
		return
	_cursor_hidden = hidden
	Input.set_mouse_mode(mode)


func _notification(what: int) -> void:
	# 窗口失焦时交还系统光标，避免切出游戏后鼠标消失
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_set_cursor_hidden(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


func setup(run: Node2D) -> void:
	main = run


## 命中敌人时闪一下准心，给开火一个明确的“打中了”的反馈。
func show_hit() -> void:
	_hit_t = HIT_TIME


func _process(delta: float) -> void:
	_hit_t = maxf(_hit_t - delta, 0.0)
	if main == null or get_tree().paused:
		_view.visible = false
		_vignette.visible = false
		_vignette.modulate.a = 0.0
		_set_cursor_hidden(false)
		return
	if int(main.get("run_state")) != 0:
		_view.visible = false
		_vignette.visible = false
		_vignette.modulate.a = 0.0
		_set_cursor_hidden(false)
		return
	_view.visible = true
	_set_cursor_hidden(true)
	_set_vignette(VIGNETTE_ALPHA * _ads_blend(), delta)
	var screen := get_viewport().get_mouse_position()
	var to_world := get_viewport().get_canvas_transform().affine_inverse()
	var world_mouse: Vector2 = to_world * screen
	var block: Dictionary = main.get_aim_block()
	var blocked := bool(block.get("blocked", false))
	var impact_screen := screen
	if blocked:
		impact_screen = get_viewport().get_canvas_transform() * Vector2(block.get("point", world_mouse))
	# 散布锥角投影到鼠标的实际距离；这样弹着范围会大致落在准心四线之间。
	var spread: float = main.get_aim_spread()
	var zoom: float = main.camera.zoom.x if main.camera != null else 1.0
	var origin: Vector2 = main.get_shot_origin()
	var aim_dist := origin.distance_to(world_mouse)
	var target_gap := clampf(BASE_GAP + tan(spread * 0.5) * aim_dist * zoom, MIN_GAP, MAX_GAP)
	_gap = lerpf(_gap, target_gap, clampf(GAP_SPEED * delta, 0.0, 1.0))
	_view.center = screen
	_view.blocked = blocked
	_view.impact = impact_screen
	_view.hit = _hit_t > 0.0
	_view.ads = main.doll.ads
	_view.zoom_pct = main.view_zoom_pct
	# 调整视角时显示倍率；非 100% 档位也常驻提示当前缩放。
	var adjusting := InputMap.has_action("view_zoom") and Input.is_action_pressed("view_zoom")
	_view.show_zoom = adjusting or absf(main.view_zoom_pct - 100.0) > 0.1
	_view.gap = _gap
	_view.queue_redraw()


class RetView extends Control:
	var center := Vector2.ZERO
	var blocked := false
	var impact := Vector2.ZERO
	var hit := false
	var ads := false
	var show_zoom := false
	var gap := 4.0
	var zoom_pct := 100.0

	func _draw() -> void:
		var point := center
		var dark := Color(0.04, 0.05, 0.07, 0.62)
		# 四线准心：内端间距随散布变化，外端再延伸一小段。
		var dirs: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
		for dir in dirs:
			var a: Vector2 = point + dir * gap
			var b: Vector2 = point + dir * (gap + TICK_LEN)
			draw_line(a, b, dark, 2.0, false)
			draw_line(a, b, COLOR_POINT, 1.0, false)
		draw_circle(point, 2.0, dark, true, -1.0, true)
		draw_circle(point, 1.0, COLOR_POINT, true, -1.0, true)
		# ADS 被墙挡住时，额外在墙面弹着点标一个小点；准心仍跟着鼠标。
		if ads and blocked:
			draw_circle(impact, 2.4, dark, true, -1.0, true)
			draw_circle(impact, 1.3, COLOR_BLOCKED, true, -1.0, true)
		if show_zoom:
			var text := "%d%%" % int(round(zoom_pct))
			draw_string(PixelUI.FONT, point + Vector2(-18, 30), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.88, 0.92, 0.88, 0.62))
		if hit:
			draw_circle(center, 5.0, Color(1.0, 1.0, 1.0, 0.9), false, 1.0, true)
