extends CanvasLayer
class_name HearingIndicator2D
## 双模式战术声纹系统：
## - 默认模式（生存天赋「声纹感知」Lv.0）：保留角色脚下战术方位弧环，
##   叠加 12 向精细刻度、三层柔和霓虹辉光、威胁色渐变（冷静青 → 紧迫橙红）与外指三角标；
## - 声波模式（「声纹感知」Lv.1~5）：每级额外提升 +10% 听声距离（最高 +50%），
##   屏幕内移动敌人（含迷雾/墙后，迷雾内附带轻微定位模糊防透视）释放双层扩散声波涟漪，
##   屏幕外音源沿视口边缘推进三层弧形来波前锋。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
## 基础听声距离（米）：13.5m（864 px）；「声纹感知」天赋每级 +10%。
const HEARING_METERS := 13.5
const HEARING_TALENT_STEP := 0.10
const CLASSIC_RADIUS := 92.0
const BUCKETS := 12
const ARC_DEG := 28.0
const RING_ALPHA_IDLE := 0.11
const RING_ALPHA_ACTIVE := 0.26
const ARC_ALPHA_MIN := 0.30
const ARC_ALPHA_MAX := 0.92
const RIPPLE_LIFE := 0.80
const MAX_RIPPLES := 36
const FOG_BLUR_MIN_PX := 10.0
const FOG_BLUR_MAX_PX := 28.0
const COLOR_CALM := Color(0.46, 0.88, 1.0)
const COLOR_URGENT := Color(1.0, 0.52, 0.26)

var main: Node = null
var player: Node2D = null
var _view: Control
## 生存分支「声纹感知」天赋等级：0 = 经典优化环；>=1 = 声波扩散模式 + 每级听声距离 +10%。
var hearing_level := 0
## 12 方向声纹强度（两种模式统一维护，保留供测试与外部查询）。
var _alphas: Array[float] = []
var _urgent: Array[float] = []
var _max_signal := 0.0
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
	var progress := get_node_or_null("/root/Progress")
	if progress != null and progress.has_method("talent_2d_level"):
		set_hearing_level(int(progress.talent_2d_level(&"hearing")))


func set_hearing_level(level: int) -> void:
	hearing_level = maxi(level, 0)
	if hearing_level <= 0:
		_ripples.clear()
		_offscreen_dirs.clear()
		_emit_cd.clear()
	if _view != null:
		_view.queue_redraw()


func is_acoustic_mode() -> bool:
	return hearing_level >= 1


func hearing_range_meters() -> float:
	return HEARING_METERS * (1.0 + float(hearing_level) * HEARING_TALENT_STEP)


func hearing_range_px() -> float:
	return hearing_range_meters() * TILE


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

	var acoustic := is_acoustic_mode()
	if acoustic:
		var alive: Array[Dictionary] = []
		for rip in _ripples:
			var age := float(rip["age"]) + delta
			if age < float(rip["life"]):
				rip["age"] = age
				alive.append(rip)
		_ripples = alive

		for key in _emit_cd.keys():
			if not is_instance_valid(key):
				_emit_cd.erase(key)
				continue
			_emit_cd[key] = maxf(0.0, float(_emit_cd[key]) - delta)

	var hearing := hearing_range_px()
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
		var dist_ratio := clampf(distance / maxf(hearing, 1.0), 0.0, 1.0)
		var strength := lerpf(ARC_ALPHA_MAX, ARC_ALPHA_MIN, dist_ratio)
		strength *= clampf(speed / 155.0, 0.55, 1.0)
		var is_urgent := 1.0 if (speed > 220.0 or distance < 3.8 * TILE) else 0.0
		targets[idx] = maxf(targets[idx], strength)
		target_urgent[idx] = maxf(target_urgent[idx], is_urgent)

		if acoustic:
			var screen_pos: Vector2 = ct * enemy.global_position
			if inner_rect.has_point(screen_pos):
				if float(_emit_cd.get(enemy, 0.0)) <= 0.0:
					var cadence := clampf(lerpf(0.44, 0.22, clampf((speed - 30.0) / 260.0, 0.0, 1.0)), 0.20, 0.46)
					_emit_cd[enemy] = cadence
					var emit_pos := enemy.global_position
					# 迷雾或墙后不可见敌人加入轻微定位模糊，还原听声辨位而非精确穿墙透视。
					var obscured := (not enemy.visible) or enemy.modulate.a < 0.85
					if obscured:
						emit_pos += Vector2.from_angle(randf() * TAU) * randf_range(FOG_BLUR_MIN_PX, FOG_BLUR_MAX_PX)
					_spawn_ripple(emit_pos, strength, is_urgent > 0.5, speed)
			else:
				_offscreen_dirs.append({
					"angle": offset.angle(),
					"strength": strength,
					"urgent": is_urgent > 0.5,
				})

	var peak := 0.0
	for i in BUCKETS:
		var k := 1.0 - exp(-12.0 * delta)
		_alphas[i] = lerpf(_alphas[i], targets[i], k)
		_urgent[i] = lerpf(_urgent[i], target_urgent[i], k)
		peak = maxf(peak, _alphas[i])
	_max_signal = peak
	_view.queue_redraw()


func _spawn_ripple(world_pos: Vector2, strength: float, urgent: bool, speed: float) -> void:
	if _ripples.size() >= MAX_RIPPLES:
		_ripples.pop_front()
	var max_r := lerpf(50.0, 78.0, clampf(speed / 300.0, 0.0, 1.0))
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
	if is_acoustic_mode():
		_draw_acoustic_mode(ct, vp_size, zoom_scale)
	else:
		_draw_classic_ring(ct, zoom_scale)


## 默认模式（Lv.0）：视觉升级后的角色脚下方向声纹环。
func _draw_classic_ring(ct: Transform2D, zoom_scale: float) -> void:
	var center: Vector2 = ct * (player.global_position + Vector2(0.0, -14.0))
	var ring_r := CLASSIC_RADIUS * clampf(zoom_scale, 0.65, 1.35)
	var base_alpha := lerpf(RING_ALPHA_IDLE, RING_ALPHA_ACTIVE, clampf(_max_signal, 0.0, 1.0))

	# 底层战术细环 + 12 向微小罗盘刻度线。
	_view.draw_arc(center, ring_r, 0.0, TAU, 72,
		Color(COLOR_CALM.r, COLOR_CALM.g, COLOR_CALM.b, base_alpha), 1.4, true)
	_view.draw_arc(center, ring_r - 4.0, 0.0, TAU, 48,
		Color(COLOR_CALM.r, COLOR_CALM.g, COLOR_CALM.b, base_alpha * 0.45), 1.0, true)
	for i in BUCKETS:
		var ang := float(i) * TAU / float(BUCKETS)
		var dir := Vector2.from_angle(ang)
		var tick_a := base_alpha * (1.35 if (i % 3 == 0) else 0.75)
		var tick_len := 5.5 if (i % 3 == 0) else 3.2
		_view.draw_line(center + dir * (ring_r - tick_len), center + dir * ring_r,
			Color(COLOR_CALM.r, COLOR_CALM.g, COLOR_CALM.b, tick_a), 1.2, true)

	# 活跃方向声纹弧：柔和外晕 + 清晰主体弧 + 亮芯 + 外指小三角标。
	var half := deg_to_rad(ARC_DEG) * 0.5
	for i in BUCKETS:
		var alpha: float = _alphas[i]
		if alpha <= 0.02:
			continue
		var mid := float(i) * TAU / float(BUCKETS)
		var col := COLOR_CALM.lerp(COLOR_URGENT, clampf(_urgent[i], 0.0, 1.0))
		var pulse := 1.0 + 0.06 * sin(_time * 10.0 + float(i))
		var arc_r := ring_r + lerpf(5.0, 12.0, clampf(alpha, 0.0, 1.0))
		# 1. 柔光外晕
		_view.draw_arc(center, arc_r, mid - half * 1.08, mid + half * 1.08, 16,
			Color(col.r, col.g, col.b, alpha * 0.22 * pulse), 9.0, true)
		# 2. 主体高亮弧
		_view.draw_arc(center, arc_r, mid - half, mid + half, 16,
			Color(col.r, col.g, col.b, alpha * 0.94), 3.4, true)
		# 3. 内芯高光
		var core := col.lightened(0.38)
		_view.draw_arc(center, arc_r, mid - half * 0.68, mid + half * 0.68, 12,
			Color(core.r, core.g, core.b, alpha * 0.82), 1.4, true)
		# 4. 外指方位小箭头
		var dir := Vector2.from_angle(mid)
		var perp := Vector2(-dir.y, dir.x)
		var tip := center + dir * (arc_r + 9.0)
		var base := center + dir * (arc_r + 3.0)
		var arrow := PackedVector2Array([tip, base + perp * 3.8, base - perp * 3.8])
		_view.draw_colored_polygon(arrow, Color(core.r, core.g, core.b, alpha * 0.90))


## 声波模式（Lv.1+）：世界坐标扩散声波涟漪 + 屏幕边缘来波前锋。
func _draw_acoustic_mode(ct: Transform2D, vp_size: Vector2, zoom_scale: float) -> void:
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
			Color(base_col.r, base_col.g, base_col.b, fade * 0.90), lerpf(2.4, 1.2, t))
		if t > 0.16:
			var t2 := clampf((t - 0.16) / 0.84, 0.0, 1.0)
			var r2 := lerpf(8.0, max_r * 0.72, 1.0 - pow(1.0 - t2, 1.6))
			var fade2 := (1.0 - t2) * (1.0 - t2) * strength * 0.54
			_draw_acoustic_wave(pos, r2, phase + 0.78,
				Color(base_col.r, base_col.g, base_col.b, fade2), lerpf(1.6, 0.9, t2))
		if t < 0.28:
			var core_a := (1.0 - t / 0.28) * strength * 0.72
			_view.draw_circle(pos, lerpf(3.4, 1.2, t / 0.28),
				Color(base_col.r, base_col.g, base_col.b, core_a), true, -1.0, true)

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
	_view.draw_arc(center, radius, 0.0, TAU, 36,
		Color(col.r, col.g, col.b, col.a * 0.30), maxf(1.0, width * 0.65), true)
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
