extends CanvasLayer
class_name HearingIndicator2D
## 声波式战术声纹系统：
## 1) 屏幕内（含视野迷雾/墙后）移动的敌人会在音源位置扩散出双层声波涟漪（带正弦微颤波形与衰减回波）；
## 2) 屏幕外或远端音源会在对应来波方向绘制向内推进的弧形声波前锋；
## 3) 静默时画面完全干净，不再在角色脚下常驻死板圆环；基础听声距离提升至 13.5 米。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
## 基础听声距离（米）：由 10m 提升至 13.5m，更契合 64 px/m 广角视野节奏。
const HEARING_METERS := 13.5
const BUCKETS := 12
const ARC_DEG := 28.0
const ARC_ALPHA_MIN := 0.28
const ARC_ALPHA_MAX := 0.90
const RIPPLE_LIFE := 0.78
const MAX_RIPPLES := 36
const COLOR_CALM := Color(0.42, 0.88, 1.0)
const COLOR_URGENT := Color(1.0, 0.54, 0.26)

var main: Node = null
var player: Node2D = null
var _view: Control
## 12 方向声纹强度（保留供测试与外部查询）。
var _alphas: Array[float] = []
var _urgent: Array[float] = []
var _offscreen_dirs: Array[Dictionary] = []
## 世界坐标扩散声波涟漪：{world_pos, age, life, max_radius, strength, urgent, phase}
var _ripples: Array[Dictionary] = []
var _emit_cd: Dictionary = {}
var _time := 0.0


func setup(main_node, player_node) -> void:
	main = main_node
	player = player_node
	layer = 6
	_view = Control.new()
	_view.name = "HearingView"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_alphas.resize(BUCKETS)
	_urgent.resize(BUCKETS)
	for i in BUCKETS:
		_alphas[i] = 0.0
		_urgent[i] = 0.0


func _process(delta: float) -> void:
	_time += delta
	if player == null or not is_instance_valid(player) or _view == null:
		return
	var targets: Array[float] = []
	var target_urgent: Array[float] = []
	targets.resize(BUCKETS)
	target_urgent.resize(BUCKETS)
	for i in BUCKETS:
		targets[i] = 0.0
		target_urgent[i] = 0.0
	_offscreen_dirs.clear()

	# 推进既有声波涟漪生命周期。
	var alive: Array[Dictionary] = []
	for rip in _ripples:
		var age := float(rip["age"]) + delta
		if age < float(rip["life"]):
			rip["age"] = age
			alive.append(rip)
	_ripples = alive

	# 衰减每个敌人的声波发射冷却，并清理失效键。
	for key in _emit_cd.keys():
		if not is_instance_valid(key):
			_emit_cd.erase(key)
			continue
		_emit_cd[key] = maxf(0.0, float(_emit_cd[key]) - delta)

	var hearing := HEARING_METERS * TILE
	var ct: Transform2D = _view.get_viewport().get_canvas_transform()
	var vp_rect := Rect2(Vector2.ZERO, _view.get_viewport().get_visible_rect().size)
	var inner_rect := vp_rect.grow(-28.0)

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var hp_value = enemy.get("hp")
		if hp_value != null and float(hp_value) <= 0.0:
			continue
		if bool(enemy.get("_dead")):
			continue
		var body := enemy as CharacterBody2D
		var speed := body.velocity.length() if body != null else 0.0
		if speed < 30.0:
			continue
		var offset: Vector2 = enemy.global_position - player.global_position
		var distance: float = offset.length()
		if distance > hearing or distance < 1.0:
			continue
		var idx := int(round(offset.angle() / (TAU / float(BUCKETS))))
		idx = ((idx % BUCKETS) + BUCKETS) % BUCKETS
		var dist_ratio := clampf(distance / hearing, 0.0, 1.0)
		var strength := lerpf(ARC_ALPHA_MAX, ARC_ALPHA_MIN, dist_ratio)
		strength *= clampf(speed / 155.0, 0.55, 1.0)
		var is_urgent := 1.0 if (speed > 220.0 or distance < 3.8 * TILE) else 0.0
		targets[idx] = maxf(targets[idx], strength)
		target_urgent[idx] = maxf(target_urgent[idx], is_urgent)

		var screen_pos: Vector2 = ct * enemy.global_position
		if inner_rect.has_point(screen_pos):
			# 屏幕内（即使躲在迷雾或墙后）：周期性在音源处放出扩散声波。
			if float(_emit_cd.get(enemy, 0.0)) <= 0.0:
				var cadence := clampf(lerpf(0.44, 0.22, clampf((speed - 30.0) / 260.0, 0.0, 1.0)), 0.20, 0.46)
				_emit_cd[enemy] = cadence
				_spawn_ripple(enemy.global_position, strength, is_urgent > 0.5, speed)
		else:
			_offscreen_dirs.append({
				"angle": offset.angle(),
				"strength": strength,
				"urgent": is_urgent > 0.5,
			})

	for i in BUCKETS:
		var k := 1.0 - exp(-12.0 * delta)
		_alphas[i] = lerpf(_alphas[i], targets[i], k)
		_urgent[i] = lerpf(_urgent[i], target_urgent[i], k)
	_view.queue_redraw()


func _spawn_ripple(world_pos: Vector2, strength: float, urgent: bool, speed: float) -> void:
	if _ripples.size() >= MAX_RIPPLES:
		_ripples.pop_front()
	var max_r := lerpf(48.0, 74.0, clampf(speed / 300.0, 0.0, 1.0))
	_ripples.append({
		"world_pos": world_pos,
		"age": 0.0,
		"life": RIPPLE_LIFE,
		"max_radius": max_r,
		"strength": strength,
		"urgent": urgent,
		"phase": _time * 4.5 + world_pos.x * 0.01,
	})


func _draw_view() -> void:
	if player == null or not is_instance_valid(player):
		return
	var ct: Transform2D = _view.get_viewport().get_canvas_transform()
	var vp_size := _view.get_viewport().get_visible_rect().size
	var zoom_scale := maxf(ct.get_scale().x, 0.4)

	# 1. 绘制音源处扩散的声波涟漪（主声波弧前锋 + 柔和回波圈 + 瞬时脉冲心）。
	for rip in _ripples:
		var t := clampf(float(rip["age"]) / maxf(float(rip["life"]), 0.01), 0.0, 1.0)
		var pos: Vector2 = ct * (rip["world_pos"] as Vector2)
		var base_col := COLOR_URGENT if bool(rip["urgent"]) else COLOR_CALM
		var strength := float(rip["strength"])
		var max_r := float(rip["max_radius"]) * zoom_scale
		var fade := (1.0 - t) * (1.0 - t) * strength
		var r1 := lerpf(10.0, max_r, 1.0 - pow(1.0 - t, 1.8))
		var phase := float(rip["phase"]) + t * 1.4
		_draw_acoustic_wave(pos, r1, phase,
			Color(base_col.r, base_col.g, base_col.b, fade * 0.88), lerpf(2.2, 1.2, t))
		if t > 0.16:
			var t2 := clampf((t - 0.16) / 0.84, 0.0, 1.0)
			var r2 := lerpf(8.0, max_r * 0.72, 1.0 - pow(1.0 - t2, 1.6))
			var fade2 := (1.0 - t2) * (1.0 - t2) * strength * 0.52
			_draw_acoustic_wave(pos, r2, phase + 0.78,
				Color(base_col.r, base_col.g, base_col.b, fade2), lerpf(1.6, 0.9, t2))
		if t < 0.28:
			var core_a := (1.0 - t / 0.28) * strength * 0.70
			_view.draw_circle(pos, lerpf(3.2, 1.2, t / 0.28),
				Color(base_col.r, base_col.g, base_col.b, core_a), true, -1.0, true)

	# 2. 绘制屏幕外音源的来波弧形前锋（3 层错峰向内行进的声波弧，沿视口边缘方向提示）。
	if not _offscreen_dirs.is_empty():
		var center := vp_size * 0.5
		var half_box := vp_size * 0.5 - Vector2(62.0, 62.0)
		for entry in _offscreen_dirs:
			var ang := float(entry["angle"])
			var dir := Vector2.from_angle(ang)
			var tx := absf(half_box.x / dir.x) if absf(dir.x) > 0.001 else 1e9
			var ty := absf(half_box.y / dir.y) if absf(dir.y) > 0.001 else 1e9
			var edge_pt := center + dir * minf(tx, ty)
			var col := COLOR_URGENT if bool(entry["urgent"]) else COLOR_CALM
			var str_val := float(entry["strength"])
			_draw_incoming_wave(edge_pt, ang + PI, col, str_val)


## 绘制同心分段声波纹（连续淡底环 + 4 道对称脉冲弧峰，呈现清晰的战术声呐波纹感）。
func _draw_acoustic_wave(center: Vector2, radius: float, phase: float,
		col: Color, width: float) -> void:
	if col.a <= 0.01 or radius < 3.0:
		return
	# 底层柔和连续声波环。
	_view.draw_arc(center, radius, 0.0, TAU, 36,
		Color(col.r, col.g, col.b, col.a * 0.30), maxf(1.0, width * 0.65), true)
	# 4 道对称的高亮声波波峰弧（模拟扩散中的声压脉冲）。
	const ARCS := 4
	var span := TAU / float(ARCS) * 0.56
	for k in ARCS:
		var a0 := phase + float(k) * (TAU / float(ARCS))
		_view.draw_arc(center, radius, a0, a0 + span, 12, col, width, true)


## 绘制 3 道向内行进的弧形声波前锋（面向玩家方向推进，模拟远端传来的声波）。
func _draw_incoming_wave(origin: Vector2, inward_angle: float,
		col: Color, strength: float) -> void:
	var spread := deg_to_rad(ARC_DEG)
	for k in 3:
		var p := fmod(_time * 1.9 + float(k) / 3.0, 1.0)
		var r := lerpf(16.0, 62.0, p)
		var alpha := sin(p * PI) * strength * 0.85
		if alpha <= 0.02:
			continue
		var w := lerpf(2.8, 1.2, p)
		_view.draw_arc(origin, r, inward_angle - spread * 0.5, inward_angle + spread * 0.5,
			16, Color(col.r, col.g, col.b, alpha), w, true)
