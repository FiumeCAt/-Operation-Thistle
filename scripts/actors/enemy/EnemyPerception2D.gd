extends RefCounted
class_name EnemyPerception2D
## 2D 敌人感知、扇形视野、双高度视线遮挡、朝向扫视与 A* 寻路避障子系统。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
## 贴脸察觉半径：4 格内不依赖扇形角度，避免走到脸上还被无视。
const CLOSE_AWARE_RADIUS := 256.0
const VIEW_TURN_SPEED := 5.0
const VIEW_SWEEP_SPEED := 0.9
## 寻路重算间隔与路径点到达半径（像素）。
const NAV_REPATH := 0.55
const NAV_WAYPOINT_RADIUS := 26.0
const NAV_GOAL_TOLERANCE := 160.0

var view_dir := Vector2.RIGHT
var view_half := deg_to_rad(55.0)
var saw_player := false

var nav_path := PackedVector2Array()
var nav_index := 0
var nav_goal := Vector2.INF
var nav_t := 0.0


func init_view(angle: float, view_angle_deg: float) -> void:
	view_dir = Vector2.from_angle(angle)
	view_half = deg_to_rad(view_angle_deg) * 0.5


func tick(delta: float) -> void:
	nav_t = maxf(nav_t - delta, 0.0)


## 扇形视野纯几何判定（不含物理射线），便于独立单测与视觉复用。
func is_in_vision_cone(origin: Vector2, target: Vector2, def: EnemyDef) -> bool:
	if def.blind:
		return false
	var dist := origin.distance_to(target)
	if dist > def.view_range * TILE and dist > CLOSE_AWARE_RADIUS:
		return false
	if dist <= CLOSE_AWARE_RADIUS:
		return true
	var to := (target - origin).normalized()
	return absf(angle_difference(view_dir.angle(), to.angle())) <= view_half


## 扇形视野判定：距离 + 视野角 + 遮挡；贴脸时改为近身察觉。
func can_see_player(host: CharacterBody2D, def: EnemyDef, player: Node2D,
		sprite_h: float, dead: bool) -> bool:
	if dead or player == null or not is_instance_valid(player):
		return false
	if not is_in_vision_cone(host.global_position, player.global_position, def):
		return false
	return line_of_sight(host, player, sprite_h)


## 胸/膝两条射线同时检查：膝部射线抬高到掩体顶部以上，避免敌人贴着物料箱时被自己的掩体挡住视线。
func line_of_sight(host: CharacterBody2D, player: Node2D, sprite_h: float) -> bool:
	if player == null:
		return false
	var space := host.get_world_2d().direct_space_state
	return ray_clear(space, host.global_position + Vector2(0, -sprite_h * 0.55),
			player.global_position + Vector2(0, -60)) \
		and ray_clear(space, host.global_position + Vector2(0, -26),
			player.global_position + Vector2(0, -26))


func ray_clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()


## 能否看见指定位置（用于观察队友倒下）；只做距离外的射线遮挡判断。
func can_see_point(host: CharacterBody2D, point: Vector2, sprite_h: float, dead: bool) -> bool:
	if dead:
		return false
	var space := host.get_world_2d().direct_space_state
	return ray_clear(space, host.global_position + Vector2(0, -sprite_h * 0.55),
			point + Vector2(0, -20.0)) \
		and ray_clear(space, host.global_position + Vector2(0, -26),
			point + Vector2(0, -26))


## 视野朝向：巡逻跟随移动方向，站岗缓慢扫视，警戒/战斗转向目标。
func update_view_direction(host: CharacterBody2D, state: String, player: Node2D,
		last_known: Vector2, dead: bool, delta: float) -> void:
	if dead:
		return
	var aim_point := Vector2.ZERO
	var has_aim := false
	if state == "combat" and player != null and is_instance_valid(player):
		aim_point = player.global_position
		has_aim = true
	elif state == "search" or state == "suspicious":
		aim_point = last_known
		has_aim = true
	if has_aim:
		var to := aim_point - host.global_position
		if to.length_squared() > 1.0:
			view_dir = _turn_view_toward(to.normalized(), delta * VIEW_TURN_SPEED)
			return
	if host.velocity.length_squared() > 16.0:
		view_dir = _turn_view_toward(host.velocity.normalized(), delta * VIEW_TURN_SPEED * 0.8)
	else:
		# 原地站岗时扇形缓慢旋转扫视，避免视野永远朝一个方向。
		view_dir = view_dir.rotated(delta * VIEW_SWEEP_SPEED)


func _turn_view_toward(target: Vector2, weight: float) -> Vector2:
	var angle := lerp_angle(view_dir.angle(), target.angle(), clampf(weight, 0.0, 1.0))
	return Vector2.from_angle(angle)


## 追击方向：优先沿 A* 路径绕过墙体，路径不可用时退回直线。
func chase_dir(host: CharacterBody2D, nav_level, target: Vector2) -> Vector2:
	var pathed := path_dir(host, nav_level, target)
	if pathed.length_squared() > 0.0001:
		return pathed
	var direct := target - host.global_position
	if direct.length_squared() < 1.0:
		return Vector2.ZERO
	return direct.normalized()


func path_dir(host: CharacterBody2D, nav_level, target: Vector2) -> Vector2:
	if nav_level == null or not nav_level.has_method("find_nav_path"):
		return Vector2.ZERO
	var needs_repath := nav_t <= 0.0 or nav_goal == Vector2.INF \
		or target.distance_to(nav_goal) > NAV_GOAL_TOLERANCE
	if needs_repath:
		nav_path = nav_level.find_nav_path(host.global_position, target)
		nav_index = 1 if nav_path.size() > 1 else 0
		nav_goal = target
		nav_t = NAV_REPATH
	while nav_index < nav_path.size() \
			and host.global_position.distance_to(nav_path[nav_index]) <= NAV_WAYPOINT_RADIUS:
		nav_index += 1
	if nav_index >= nav_path.size():
		return Vector2.ZERO
	var to := nav_path[nav_index] - host.global_position
	if to.length_squared() < 1.0:
		return Vector2.ZERO
	return to.normalized()


## 近距避障：正前方撞墙时向两侧试探，避免贴住墙角原地抖动。
func avoid_walls(host: CharacterBody2D, def: EnemyDef, dir: Vector2) -> Vector2:
	var probe := def.collision_radius + 26.0
	if _probe_clear(host, dir, probe):
		return dir
	for angle in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var probe_dir := dir.rotated(deg_to_rad(angle))
		if _probe_clear(host, probe_dir, probe):
			return probe_dir
	return dir


func _probe_clear(host: CharacterBody2D, dir: Vector2, dist: float) -> bool:
	var origin := host.global_position + Vector2(0, -8)
	var query := PhysicsRayQueryParameters2D.create(origin, origin + dir * dist, 1)
	return host.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func move_dir(host: CharacterBody2D, def: EnemyDef, dir: Vector2, speed_px: float) -> void:
	if dir.length_squared() < 0.0001:
		host.velocity = Vector2.ZERO
		return
	host.velocity = avoid_walls(host, def, dir.normalized()) * speed_px
	host.move_and_slide()


func move_toward(host: CharacterBody2D, def: EnemyDef, nav_level,
		point: Vector2, speed_ratio: float, use_nav := false) -> void:
	var delta_vec := point - host.global_position
	if delta_vec.length() < 8.0:
		host.velocity = Vector2.ZERO
		return
	var dir := chase_dir(host, nav_level, point) if use_nav else delta_vec.normalized()
	move_dir(host, def, dir, def.speed * TILE * speed_ratio)


func move_away(host: CharacterBody2D, def: EnemyDef, from: Vector2, speed_px: float) -> void:
	var away := host.global_position - from
	if away.length() < 1.0:
		return
	move_dir(host, def, away.normalized(), speed_px * TILE * 0.9)
