extends Node2D
class_name PlayerBullet2D
## 玩家弹丸：按“真实初速 × 弹种时间压缩”飞行，逐物理帧做线段扫掠检测。
## 速度按 v(s) = v0 * exp(-drag_per_px * s) 衰减；命中与结束通过信号通知宿主
## （enemy_hit / wall_hit / finished），不反向依赖 Main2D 的私有方法或场景结构。

signal enemy_hit(bullet: PlayerBullet2D, target: Node, point: Vector2, direction: Vector2)
signal wall_hit(bullet: PlayerBullet2D, point: Vector2, direction: Vector2)
signal ground_hit(bullet: PlayerBullet2D, point: Vector2, direction: Vector2)
signal finished(bullet: PlayerBullet2D)

const WALL_OVERLAP_LOOKAHEAD := 120.0
const WEAKSPOT_LAYER := 4
const WEAKSPOT_PENETRATE_DEPTH := 56.0

var velocity := Vector2.ZERO
var damage := 0.0
var ap := 0.0
var knockback := 0.0
var max_distance := 1000.0
var drag_per_px := 0.0
var color := Color(1.0, 0.82, 0.45)
var shot_ctx: Dictionary = {}
var player_rid := RID()
var travelled := 0.0
## Phase 4：是否命中敌人配置弱点区；由弹道优先判定后置位，保持 enemy_hit 4 参信号契约不变。
var hit_weakspot := false
## Phase 4：轻量伪 3D 子弹高度 z（1.0=枪口平射高度，0.0=地面）；vz_per_px < 0 时沿弹道自然斜降触地。
var z_height := 1.0
var vz_per_px := 0.0
## 可选墙体遮挡查询回调 (from: Vector2, to: Vector2) -> Dictionary；
## 未注入时使用弹丸自身所在 World2D 的 layer 1 射线检测。
var wall_check: Callable = Callable()
## 弹道线条：从枪口持续连到弹丸当前位置，命中后保留一小段渐隐。
## 与弹丸实体分离；设置关闭时只隐藏这条线，弹丸仍然可见并正常飞行。
var origin := Vector2.ZERO
var trail_line: Line2D = null
var trail_glow: Line2D = null
var trail_enabled := true
var _finished := false
var _sweep_query: PhysicsRayQueryParameters2D = null
var _exclude_rids: Array[RID] = []


## 无耦合构造接口：通过显式配置字典创建弹丸，由宿主订阅 enemy_hit / wall_hit / finished 信号。
static func create(parent: Node, config: Dictionary) -> PlayerBullet2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var direction: Vector2 = config.get("direction", Vector2.ZERO)
	if direction.length_squared() < 0.000001:
		return null
	var from: Vector2 = config.get("origin", Vector2.ZERO)
	var bullet := PlayerBullet2D.new()
	bullet.velocity = direction.normalized() * maxf(float(config.get("speed_px_s", 1.0)), 1.0)
	bullet.damage = float(config.get("damage", 0.0))
	bullet.ap = float(config.get("ap", 0.0))
	bullet.knockback = float(config.get("knockback", 0.0))
	bullet.max_distance = maxf(float(config.get("max_distance", 1000.0)), 1.0)
	bullet.drag_per_px = maxf(float(config.get("drag_per_px", 0.0)), 0.0)
	bullet.color = config.get("color", Color(1.0, 0.82, 0.45))
	bullet.shot_ctx = config.get("shot_ctx", {})
	bullet.origin = from
	bullet.z_height = clampf(float(config.get("z_start", 1.0)), 0.0, 2.0)
	bullet.vz_per_px = minf(float(config.get("vz_per_px", 0.0)), 0.0)
	var exclude_rid = config.get("exclude_rid", RID())
	if exclude_rid is RID:
		bullet.player_rid = exclude_rid
	bullet.trail_enabled = bool(config.get("trail_enabled", true))
	var check_cb = config.get("wall_check", Callable())
	if check_cb is Callable and (check_cb as Callable).is_valid():
		bullet.wall_check = check_cb
	var on_enemy = config.get("on_enemy_hit", Callable())
	if on_enemy is Callable and (on_enemy as Callable).is_valid():
		bullet.enemy_hit.connect(on_enemy)
	var on_wall = config.get("on_wall_hit", Callable())
	if on_wall is Callable and (on_wall as Callable).is_valid():
		bullet.wall_hit.connect(on_wall)
	var on_ground = config.get("on_ground_hit", Callable())
	if on_ground is Callable and (on_ground as Callable).is_valid():
		bullet.ground_hit.connect(on_ground)
	var on_done = config.get("on_finished", Callable())
	if on_done is Callable and (on_done as Callable).is_valid():
		bullet.finished.connect(on_done)
	bullet.rotation = bullet.velocity.angle()
	bullet.z_index = 61
	parent.add_child(bullet)
	bullet.global_position = from
	if bullet.trail_enabled:
		bullet._create_trail_line(parent, from)
	return bullet


## 弹道线条是独立节点：弹丸命中后节点立即释放，线条仍能保留一小段渐隐。
func _create_trail_line(parent: Node, from: Vector2) -> void:
	var line_color := color.lerp(Color(1.0, 0.97, 0.86), 0.35)
	trail_line = Line2D.new()
	trail_line.width = 2.2
	trail_line.default_color = Color(line_color.r, line_color.g, line_color.b, 0.78)
	trail_line.z_index = 60
	trail_line.top_level = true
	trail_line.set_meta("bullet_trail", true)
	parent.add_child(trail_line)
	trail_line.global_position = Vector2.ZERO
	trail_line.points = PackedVector2Array([from, from])
	# 柔光层作为线条子节点：跟随 points / visible / modulate 一起变化，增强开火曳光高亮质感。
	trail_glow = Line2D.new()
	trail_glow.width = 8.0
	trail_glow.default_color = Color(line_color.r, line_color.g, line_color.b, 0.18)
	trail_glow.points = PackedVector2Array([from, from])
	trail_glow.z_index = -1
	trail_line.add_child(trail_glow)


func _ready() -> void:
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _finished:
		return
	var speed := velocity.length()
	if speed < 1.0:
		_finish(global_position)
		return
	var remaining := max_distance - travelled
	if remaining <= 0.5:
		_finish(global_position)
		return
	var dir := velocity / speed
	var step_len := minf(speed * delta, remaining)
	var will_hit_ground := false
	if vz_per_px < -0.000001:
		var dist_to_ground := maxf(z_height / absf(vz_per_px), 0.0)
		if dist_to_ground <= step_len:
			step_len = dist_to_ground
			will_hit_ground = true
	var from := global_position
	var next := from + dir * step_len

	# 关键：必须查线段而不是只查终点。单次宽扫合并层 1|2|4（墙/躯干/弱点），空飞期射线开销直接砍半 50%，并复用 Query 对象零临时分配。
	if _sweep_query == null:
		_exclude_rids.clear()
		if player_rid.is_valid():
			_exclude_rids.append(player_rid)
		_sweep_query = PhysicsRayQueryParameters2D.new()
		_sweep_query.collision_mask = 1 | 2 | WEAKSPOT_LAYER
		_sweep_query.exclude = _exclude_rids
		_sweep_query.hit_from_inside = true
		_sweep_query.collide_with_areas = true
	_sweep_query.from = from
	_sweep_query.to = next
	var space := get_world_2d().direct_space_state
	var hit := space.intersect_ray(_sweep_query)

	if not hit.is_empty():
		var col = hit.get("collider")
		if col is CollisionObject2D and (col.collision_layer & WEAKSPOT_LAYER) != 0:
			var ws_target = _extract_target(hit)
			if ws_target != null and ws_target.has_method("take_damage"):
				_resolve_enemy_hit(ws_target, hit["position"], dir, true)
				return
		_resolve_hit(hit, from, dir, _exclude_rids)
		return

	global_position = next
	travelled += step_len
	if vz_per_px < -0.000001:
		z_height = maxf(0.0, z_height + vz_per_px * step_len)
	velocity *= exp(-drag_per_px * step_len)
	_update_trail_points(global_position)
	if will_hit_ground or (vz_per_px < -0.000001 and z_height <= 0.001):
		ground_hit.emit(self, next, dir)
		_finish(next)
		return
	queue_redraw()


static func _extract_target(hit: Dictionary):
	var collider = hit.get("collider")
	if collider is Area2D:
		return collider.get_parent()
	return collider


## 沿躯干命中点向前探测目标自身弱点：受层 1 墙体截断（防穿墙打弱点），遇到其他敌人的弱点重叠时排除重试（防敌群吞弱点）。
func _find_target_weakspot_along(from_pos: Vector2, to_pos: Vector2, target, exclude: Array[RID]) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var local_ex: Array[RID] = exclude.duplicate()
	var ws_q := PhysicsRayQueryParameters2D.new()
	ws_q.from = from_pos
	ws_q.to = to_pos
	ws_q.collision_mask = 1 | WEAKSPOT_LAYER
	ws_q.hit_from_inside = true
	ws_q.collide_with_areas = true
	for _attempt in 3:
		ws_q.exclude = local_ex
		var ws_hit := space.intersect_ray(ws_q)
		if ws_hit.is_empty():
			return {}
		var col = ws_hit.get("collider")
		if col is CollisionObject2D and (col.collision_layer & 1) != 0 and (col.collision_layer & WEAKSPOT_LAYER) == 0:
			return {}
		if _extract_target(ws_hit) == target:
			return ws_hit
		var hit_rid = ws_hit.get("rid", RID())
		if hit_rid is RID and (hit_rid as RID).is_valid() and not local_ex.has(hit_rid):
			local_ex.append(hit_rid)
		else:
			return {}
	return {}


func _query_wall_between(from_pos: Vector2, to_pos: Vector2) -> Dictionary:
	if wall_check.is_valid():
		return wall_check.call(from_pos, to_pos)
	if from_pos.distance_squared_to(to_pos) < 1.0:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos, 1)
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query)


func _resolve_enemy_hit(target, point: Vector2, dir: Vector2, is_weakspot: bool) -> void:
	# 敌人贴墙只露出受击盒时，从开火点回看身体核心；被墙挡住就不结算伤害。
	# 但 2.5D 立绘向上延伸，敌人贴在北墙下方或门框拐角旁时，body_center() 可能投影进墙内，
	# 而脚底物理核心 ground_center() 仍在同侧开阔地面；仅当身体核心与脚底核心（及命中点到脚底）
	# 均被墙体隔开时，才判定为隔墙穿射并拒绝结算伤害。
	if target.has_method("body_center"):
		var shot_origin: Vector2 = shot_ctx.get("origin", origin)
		var blocked: Dictionary = _query_wall_between(shot_origin, target.body_center())
		if not blocked.is_empty():
			var clear_via_ground := false
			if target.has_method("ground_center"):
				var ground: Vector2 = target.ground_center()
				if _query_wall_between(shot_origin, ground).is_empty():
					clear_via_ground = true
				elif _query_wall_between(point, ground).is_empty():
					clear_via_ground = true
			if not clear_via_ground:
				wall_hit.emit(self, blocked["position"], dir)
				_finish(blocked["position"])
				return
	hit_weakspot = is_weakspot
	enemy_hit.emit(self, target, point, dir)
	_finish(point)


func _resolve_hit(hit: Dictionary, from_pos: Vector2, dir: Vector2, exclude: Array[RID]) -> void:
	var point: Vector2 = hit["position"]
	var target = _extract_target(hit)

	if target != null and target.has_method("take_damage"):
		# 射线优先弱点结算：仅从躯干命中点向前探测 WEAKSPOT_PENETRATE_DEPTH（不重扫已扫过的空飞段）。
		var probe_end := point + dir * WEAKSPOT_PENETRATE_DEPTH
		var ws_hit := _find_target_weakspot_along(point, probe_end, target, exclude)
		if not ws_hit.is_empty():
			_resolve_enemy_hit(target, ws_hit["position"], dir, true)
			return
		_resolve_enemy_hit(target, point, dir, false)
		return

	# 2.5D 遮挡修正：敌人站在北墙/掩体南侧时，其立绘与上半身 Hitbox 会向上投影盖在墙前；
	# 瞄准胸口/头部可能先擦到敌人身后的墙体碰撞盒。仅当敌人脚底严格位于墙面南侧且开火点到脚底无墙阻挡时，
	# 才将该次擦墙还原为命中敌人，同时保持 0 隔墙穿射漏洞。
	var overlap_hit := _find_wall_front_enemy_hit(point, dir)
	if not overlap_hit.is_empty():
		var ov_target = overlap_hit["target"]
		var ov_point: Vector2 = overlap_hit["point"]
		var ov_ws := bool(overlap_hit.get("weakspot", false))
		hit_weakspot = ov_ws
		enemy_hit.emit(self, ov_target, ov_point, dir)
		_finish(ov_point)
		return

	wall_hit.emit(self, point, dir)
	_finish(point)


func _find_wall_front_enemy_hit(wall_pt: Vector2, dir: Vector2) -> Dictionary:
	var dist_to_wall := global_position.distance_to(wall_pt)
	var lookahead := minf(maxf(max_distance - travelled - dist_to_wall, 0.0), WALL_OVERLAP_LOOKAHEAD)
	if lookahead < 1.0:
		return {}
	var exclude: Array[RID] = []
	if player_rid.is_valid():
		exclude.append(player_rid)
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		wall_pt, wall_pt + dir * lookahead, 2 | WEAKSPOT_LAYER, exclude)
	query.hit_from_inside = true
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	var target = _extract_target(hit)
	if target == null or not target.has_method("take_damage") or not target.has_method("ground_center"):
		return {}
	var ground: Vector2 = target.ground_center()
	if wall_pt.y >= ground.y:
		return {}
	var shot_origin: Vector2 = shot_ctx.get("origin", origin)
	if not _query_wall_between(shot_origin, ground).is_empty():
		return {}
	var hit_pt: Vector2 = hit["position"]
	var collider = hit.get("collider")
	var is_ws: bool = collider is Area2D and bool(collider.get_meta("is_weakspot", false))
	if not is_ws:
		var ws_probe := _find_target_weakspot_along(wall_pt, hit_pt + dir * WEAKSPOT_PENETRATE_DEPTH, target, exclude)
		if not ws_probe.is_empty():
			is_ws = true
			hit_pt = ws_probe["position"]
	return {"target": target, "point": hit_pt, "weakspot": is_ws}


func _finish(endpoint: Vector2) -> void:
	if _finished:
		return
	_finished = true
	_end_trail_line(endpoint)
	finished.emit(self)
	queue_free()


func _update_trail_points(endpoint: Vector2) -> void:
	if not trail_enabled:
		return
	if trail_line == null or not is_instance_valid(trail_line):
		return
	var points := PackedVector2Array([origin, endpoint])
	trail_line.points = points
	if trail_glow != null and is_instance_valid(trail_glow):
		trail_glow.points = points


## 命中/超程后把线固定在最终点并渐隐；关闭设置时直接释放线条。
func _end_trail_line(endpoint: Vector2) -> void:
	if trail_line == null or not is_instance_valid(trail_line):
		trail_line = null
		trail_glow = null
		return
	var line := trail_line
	trail_line = null
	trail_glow = null
	var points := PackedVector2Array([origin, endpoint])
	line.points = points
	if line.get_child_count() > 0 and line.get_child(0) is Line2D:
		(line.get_child(0) as Line2D).points = points
	if not trail_enabled:
		line.queue_free()
		return
	line.visible = true
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.16)
	tw.tween_callback(line.queue_free)


## 设置页切换时只控制弹道线条，不影响弹丸实体。
## 若子弹在关闭状态下出膛，重新开启时按当前位置补一条线。
func set_trail_visible(enabled: bool) -> void:
	trail_enabled = enabled
	if enabled and not _finished and trail_line == null and is_inside_tree():
		_create_trail_line(get_parent(), origin)
		_update_trail_points(global_position)
	if trail_line != null and is_instance_valid(trail_line):
		trail_line.visible = enabled


func _draw() -> void:
	var speed := velocity.length()
	# 伪 3D 斜向落点：在子弹下方绘制随高度收敛的地面投影点，增强落地空间感。
	if vz_per_px < -0.000001 and z_height > 0.02:
		var shadow_local := Vector2(0.0, z_height * 16.0).rotated(-rotation)
		var shadow_alpha := lerpf(0.36, 0.14, clampf(z_height, 0.0, 1.0))
		draw_circle(shadow_local, 2.2, Color(0.04, 0.04, 0.05, shadow_alpha))
	# 弹丸实体保持短小：长距离弹道由独立线条负责，关闭线条后仍能看到这颗子弹。
	var trail := clampf(speed * 0.006, 12.0, 42.0)
	var glow := Color(color.r, color.g, color.b, 0.20)
	var body := Color(color.r, color.g, color.b, 0.62)
	draw_line(Vector2(-trail, 0.0), Vector2.ZERO, glow, 4.5)
	draw_line(Vector2(-trail * 0.8, 0.0), Vector2.ZERO, body, 2.2)
	draw_line(Vector2(-trail * 0.35, 0.0), Vector2.ZERO, Color(1.0, 0.96, 0.78, 0.95), 1.4)
	draw_circle(Vector2.ZERO, 2.4, Color(1.0, 0.96, 0.8, 0.95))
