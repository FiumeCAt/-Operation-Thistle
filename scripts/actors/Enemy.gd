extends CharacterBody3D
class_name Enemy
## 敌人：NavigationAgent3D 寻路 + 6 态状态机。
## 状态：PATROL → SUSPICIOUS → INVESTIGATE → COMBAT → SEARCH → FLEE
## 感知：视觉（距离 + 视锥 + 射线遮挡）、听觉（外部调用 hear_noise）。
## 立绘用 Sprite3D 固定 Y billboard，与主角同一套投影规则。

signal died(enemy: Enemy)

enum State { PATROL, SUSPICIOUS, INVESTIGATE, COMBAT, SEARCH, FLEE }

const STATE_NAMES := ["PATROL", "SUSPICIOUS", "INVESTIGATE", "COMBAT", "SEARCH", "FLEE"]
const ZPIX_FONT := preload("res://assets/art/ui/Zpix.ttf")

const CELL_H := 384.0
const FOV_DEG := 110.0          # 视锥总角度
const LOST_SIGHT_TIME := 2.5    # 跟丢多久转 SEARCH
const SEARCH_TIME := 5.0        # 搜索时长
## 标准听觉基准：16m。枪声半径按本值折算，听觉 16 的单位按原半径听。
const HEARING_BASE := 16.0

var kind: StringName = &"rifleman"
var display_name := "哨兵"
var max_hp := 70.0
var hp := 70.0
var armor := 0.0
var speed := 2.6
var damage := 7.0
var attack_range := 13.0
var view_range := 15.0
var hearing := 16.0
var attack_cd := 1.55
var melee := false
var radius := 0.36
var patrol_radius := 6.0
var flees := true
var strafes := true
## 纯听觉单位：没有视觉，只对声音与接触作出反应。
var blind := false

var player: Doll
var sprite: Sprite3D
var outline: Sprite3D
var agent: NavigationAgent3D

var state: State = State.PATROL
var last_known := Vector3.ZERO
var investigate_point := Vector3.ZERO
var _state_t := 0.0
var _arrival_t := 0.0
var _cd := 0.0
var _flash := 0.0
var _lost_t := 0.0
var _dead := false
var _spawn_pos := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _repath_t := 0.0
var _strafe_dir := 1.0
var health_bar: HealthBar3D
var shadow: MeshInstance3D

## 对外只读状态：支援等外部系统用它过滤尸体。
var is_dead: bool:
	get:
		return _dead

func setup(p: Doll, id: StringName) -> void:
	player = p
	kind = id
	var s := EnemyDB.stats(id)
	display_name = String(s["name"])
	max_hp = float(s["hp"])
	hp = max_hp
	armor = float(s["armor"])
	speed = float(s["speed"])
	damage = float(s["damage"])
	attack_range = float(s["range"])
	view_range = float(s["view_range"])
	hearing = float(s["hearing"])
	attack_cd = float(s["cooldown"])
	melee = bool(s["melee"])
	radius = float(s["radius"])
	patrol_radius = float(s["patrol_radius"])
	flees = bool(s["flees"])
	strafes = bool(s["strafe"])
	blind = bool(s.get("blind", false))
	if blind:
		view_range = 0.0
	_spawn_pos = global_position
	last_known = _spawn_pos
	_repath_t = randf() * 0.3      # 错开重算时机，避免整屏同时寻路
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	_build()

func _build() -> void:
	var tex_path: String = EnemyDB.stats(kind)["texture"]
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	if tex == null:
		push_warning("Enemy: 缺少贴图 " + tex_path)
		return

	collision_layer = 8          # 与靶子同层，玩家射线 1|8 可命中
	collision_mask = 1           # 只与墙体碰撞
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)

	sprite = Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = 2                 # BILLBOARD_FIXED_Y：竖直平面，只绕 Y
	sprite.alpha_cut = 1
	sprite.texture_filter = 3
	sprite.shaded = false
	sprite.cast_shadow = 0
	var projection := BillboardVisual.calculate_projection(CELL_H)
	sprite.pixel_size = projection.x
	sprite.position.y = projection.y
	sprite.modulate = Color(1.02, 1.0, 1.02)
	add_child(sprite)

	# HD-2D 外描边：与主角同一套剪影规则，但敌人贴图为单帧。
	outline = Sprite3D.new()
	outline.texture = tex
	outline.billboard = 2
	outline.alpha_cut = 1
	outline.texture_filter = 3
	outline.shaded = false
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.pixel_size = sprite.pixel_size * BillboardVisual.OUTLINE_SCALE
	outline.modulate = BillboardVisual.OUTLINE_COLOR
	outline.render_priority = -1
	add_child(outline)

	health_bar = HealthBar3D.new()
	health_bar.position.y = 2.05
	add_child(health_bar)
	health_bar.update_health(hp, max_hp)

	# 与主角共用一套投影规则：只保留贴地接触阴影。
	shadow = BillboardVisual.add_ground_shadow(self, radius * 4.0, 0.5)

	# 寻路代理
	agent = NavigationAgent3D.new()
	agent.radius = radius
	agent.height = 1.7
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 0.8
	agent.path_max_distance = 3.0
	agent.avoidance_enabled = false      # 切片期用手动分离，省性能
	add_child(agent)
	add_to_group("enemies")

	# 出生点吸附到导航网格，避免生成在墙里
	call_deferred("_snap_to_nav")

func _snap_to_nav() -> void:
	if not is_inside_tree():
		return
	var map := get_world_3d().navigation_map
	while NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		map = get_world_3d().navigation_map
	var snapped := NavigationServer3D.map_get_closest_point(map, global_position)
	if snapped.is_finite() and snapped.distance_to(Vector3.ZERO) > 0.001:
		global_position = Vector3(snapped.x, global_position.y, snapped.z)
		_spawn_pos = global_position
	_pick_patrol_target()

# ---------------------------------------------------------------- 主循环

func _process(dt: float) -> void:
	if health_bar:
		health_bar.update_health(hp, max_hp, _dead)
	if _flash > 0.0 and not _dead:
		_flash = maxf(0.0, _flash - dt)
		if sprite:
			sprite.modulate = Color(1.02, 1.0, 1.02).lerp(Color(2.4, 0.9, 0.8), _flash / 0.12)
	_update_visibility()
	_sync_outline()

func _sync_outline() -> void:
	if outline == null or sprite == null:
		return
	outline.visible = sprite.modulate.a > 0.45
	if not outline.visible:
		return
	var lift := sprite.pixel_size * float(CELL_H) * 0.5 * (BillboardVisual.OUTLINE_SCALE - 1.0)
	var back_dir := Vector3(0.0, 0.0, -1.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		back_dir = -cam.global_transform.basis.z.normalized()
	var back_len := 0.03 - lift * back_dir.y
	outline.global_position = sprite.global_position + back_dir * back_len + Vector3.UP * lift

## 只显示在玩家视野内的敌人：主视野外开始淡出，总视野或视距外完全隐藏。
## 听觉声纹由 HearingIndicator 独立绘制，不受这里影响。
func _update_visibility() -> void:
	if _dead or player == null or sprite == null:
		return
	var to := global_position - player.global_position
	to.y = 0.0
	var distance := to.length()
	var angle := 0.0
	if distance > 0.1:
		var facing := Vector3(sin(player.global_rotation.y), 0.0, cos(player.global_rotation.y))
		angle = rad_to_deg(facing.angle_to(to.normalized()))
	var clear_half: float = player.vision_clear_half
	var total_half: float = player.vision_total_half
	var range_m: float = player.vision_range
	var alpha := clampf((total_half - angle) / maxf(total_half - clear_half, 0.01), 0.0, 1.0)
	alpha *= clampf((range_m - distance) / 1.5, 0.0, 1.0)
	# 相机与敌人之间若被墙完全挡住，整体隐藏，避免立绘被墙裁成半身。
	if alpha > 0.01 and _camera_blocked():
		alpha = 0.0
	var base := sprite.modulate
	sprite.modulate = Color(base.r, base.g, base.b, alpha)
	if health_bar:
		health_bar.visible = alpha > 0.45
	visible = alpha > 0.01

## 相机到胸口/头部采样：任一位置可见就保留；两条射线都撞墙才判定为完全遮挡。
func _camera_blocked() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var from := cam.global_position
	for height in [1.15, 1.55]:
		var to := global_position + Vector3(0, height, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return false
	return true

func _physics_process(dt: float) -> void:
	if _dead or player == null:
		return
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0:
		return
	_cd = maxf(0.0, _cd - dt)
	_state_t += dt
	_repath_t -= dt
	var sees := _can_see_player()
	if sees:
		last_known = player.global_position
		_lost_t = 0.0
	else:
		_lost_t += dt

	match state:
		State.PATROL:
			_tick_patrol(dt, sees)
		State.SUSPICIOUS:
			_tick_suspicious(dt, sees)
		State.INVESTIGATE:
			_tick_investigate(dt, sees)
		State.COMBAT:
			_tick_combat(dt, sees)
		State.SEARCH:
			_tick_search(dt, sees)
		State.FLEE:
			_tick_flee(dt, sees)

	_apply_gravity(dt)
	move_and_slide()

func _apply_gravity(dt: float) -> void:
	if not is_on_floor():
		velocity.y -= 24.0 * dt
	else:
		velocity.y = 0.0

# ---------------------------------------------------------------- 各状态

func _tick_patrol(dt: float, sees: bool) -> void:
	if sees:
		_enter(State.COMBAT)
		return
	if blind and _blind_contact():
		return
	if _arrived(_patrol_target):
		_pick_patrol_target()
	_stroll(dt, speed * 0.55)

func _tick_suspicious(dt: float, sees: bool) -> void:
	_halt(dt)
	_face(investigate_point)
	if sees:
		_enter(State.COMBAT)
		return
	if blind and _blind_contact():
		return
	if _state_t > 1.0:
		_enter(State.INVESTIGATE)

func _tick_investigate(dt: float, sees: bool) -> void:
	if sees:
		_enter(State.COMBAT)
		return
	if blind and _blind_contact():
		return
	if _arrived(investigate_point):
		_arrival_t += dt
		_halt(dt)
		_face(investigate_point)
		if _arrival_t >= 3.0:
			_enter(State.SEARCH)
		return
	_arrival_t = 0.0
	if _state_t > 12.0:
		_enter(State.SEARCH)
		return
	_navigate_to(dt, investigate_point, speed * 0.85)

func _tick_combat(dt: float, sees: bool) -> void:
	if blind:
		_tick_blind_combat(dt)
		return
	if not sees and _lost_t > LOST_SIGHT_TIME:
		_enter(State.SEARCH)
		return
	if flees and hp < max_hp * 0.25:
		_enter(State.FLEE)
		return

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	_face(player.global_position)

	# 远程：保持距离 + 横向 strafe；近战：贴脸
	if melee:
		if dist > attack_range * 0.85:
			_navigate_to(dt, player.global_position, speed)
		else:
			_halt(dt)
			if _cd <= 0.0:
				_attack()
		return

	if dist > attack_range:
		_navigate_to(dt, player.global_position, speed)
	elif strafes:
		var right := Vector3(-to_player.z, 0.0, to_player.x).normalized()
		velocity.x = right.x * speed * 0.6 * _strafe_dir
		velocity.z = right.z * speed * 0.6 * _strafe_dir
		if fmod(_state_t, 1.8) < dt:      # 每隔约 1.8s 换方向
			_strafe_dir = -_strafe_dir
	else:
		_halt(dt)
	if _cd <= 0.0 and sees:
		_attack()

func _tick_search(dt: float, sees: bool) -> void:
	if sees:
		_enter(State.COMBAT)
		return
	if _arrived(last_known):
		_arrival_t += dt
		_halt(dt)
		# 原地环视
		rotation.y += dt * 1.4
		if _arrival_t >= SEARCH_TIME:
			_enter(State.PATROL)
		return
	_arrival_t = 0.0
	if _state_t > 12.0:
		_enter(State.PATROL)
		return
	_navigate_to(dt, last_known, speed * 0.8)

func _tick_flee(dt: float, sees: bool) -> void:
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	away = away.normalized()
	var flee_point := global_position + away * 6.0
	_navigate_to(dt, flee_point, speed * 1.15)
	if _state_t > 4.0 and not sees:
		hp = maxf(hp, max_hp * 0.3)
		_enter(State.SEARCH)

## 盲眼单位的近身接触：只有玩家贴到攻击距离内才会转入战斗。
## 转入战斗时只记录一次玩家位置快照，之后不再实时追踪。
func _blind_contact() -> bool:
	if player == null:
		return false
	var d := global_position.distance_to(player.global_position)
	if d > attack_range * 0.9:
		return false
	last_known = player.global_position
	_enter(State.COMBAT)
	return true

## 盲眼战斗：追到最后一次接触点，原地挥击；不会隔着墙读取玩家位置。
func _tick_blind_combat(dt: float) -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() <= attack_range * 0.9:
		last_known = player.global_position
		_halt(dt)
		_face(player.global_position)
		if _cd <= 0.0:
			_attack()
		return
	if _arrived(last_known):
		_arrival_t += dt
		_halt(dt)
		rotation.y += dt * 1.8
		if _arrival_t >= 2.0:
			_enter(State.SEARCH)
		return
	_arrival_t = 0.0
	_navigate_to(dt, last_known, speed * 1.1)

func _enter(next: State) -> void:
	state = next
	_state_t = 0.0
	_arrival_t = 0.0
	_repath_t = 0.0
	match next:
		State.INVESTIGATE:
			investigate_point = last_known
		State.PATROL:
			_pick_patrol_target()

# ---------------------------------------------------------------- 移动

func _stroll(dt: float, spd: float) -> void:
	if _patrol_target == Vector3.ZERO:
		_pick_patrol_target()
		return
	_navigate_to(dt, _patrol_target, spd)

func _navigate_to(dt: float, target: Vector3, spd: float) -> void:
	if agent == null:
		return
	if _repath_t <= 0.0:
		_repath_t = 0.35
		agent.target_position = target
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0004:
		velocity.x = move_toward(velocity.x, 0.0, spd * 8.0 * dt)
		velocity.z = move_toward(velocity.z, 0.0, spd * 8.0 * dt)
		return
	dir = dir.normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	# 平滑转向，避免瞬间打转
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-10.0 * dt))

func _halt(dt: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 26.0 * dt)
	velocity.z = move_toward(velocity.z, 0.0, 26.0 * dt)

func _face(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 0.25)

func _arrived(target: Vector3) -> bool:
	var d := target - global_position
	d.y = 0.0
	return d.length() < 0.9

func _pick_patrol_target() -> void:
	var a := randf() * TAU
	var r := patrol_radius * sqrt(randf())
	_patrol_target = _spawn_pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if agent:
		agent.target_position = _patrol_target
		_repath_t = 0.35

# ---------------------------------------------------------------- 感知

## 视觉：距离 + 视锥 + 射线遮挡
func _can_see_player() -> bool:
	if blind or player == null:
		return false
	var to_p := player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > view_range * player.visibility_multiplier():
		return false
	if dist > 0.9:
		var facing := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
		var ang := rad_to_deg(facing.angle_to(to_p.normalized()))
		if ang > FOV_DEG * 0.5:
			return false
	var from := global_position + Vector3(0, 1.2, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()

## 听觉：由外部（枪声）调用。radius 为声音的传播范围（米），
## 以 16m 听觉为基准按单位听觉缩放；例如听觉 22 的猎手能多听 37.5%。
func hear_noise(pos: Vector3, radius := HEARING_BASE) -> void:
	if _dead:
		return
	if state == State.COMBAT:
		return
	var d := global_position.distance_to(pos)
	var audible := maxf(0.0, radius) * (hearing / HEARING_BASE)
	if d > audible:
		return
	if not investigate_point.is_equal_approx(pos):
		_arrival_t = 0.0
		_state_t = 0.0
		_repath_t = 0.0
	last_known = pos
	investigate_point = pos
	# 新的声源会打断旧调查点，避免敌人一直走向已经过时的位置。
	if state == State.PATROL or state == State.SEARCH or state == State.INVESTIGATE:
		_enter(State.SUSPICIOUS)
	elif state == State.SUSPICIOUS:
		_state_t = 0.0

# ---------------------------------------------------------------- 攻击

func _attack() -> void:
	_cd = attack_cd
	if melee:
		if global_position.distance_to(player.global_position) <= attack_range + 0.5:
			player.take_damage(damage)
			var s := _sfx()
			if s:
				s.play_3d(_audio_host(), "hit", global_position, -8.0, 0.8)
		return

	var from := global_position + Vector3(0, 1.25, 0)
	var dir := player.global_position + Vector3(0, 1.0, 0) - from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var end := from + dir * (attack_range + 8.0)
	var q := PhysicsRayQueryParameters3D.create(from, end, 1 | 2)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	ImpactFX.tracer(_audio_host(), from, hit.get("position", end))
	var s2 := _sfx()
	if s2:
		s2.play_3d(_audio_host(), "shotgun", from, -14.0, 1.35)
	if hit.is_empty():
		return
	if hit.get("collider") == player:
		player.take_damage(damage)
	else:
		ImpactFX.spawn(_audio_host(), hit["position"])

func _sfx() -> Node:
	return get_tree().root.get_node_or_null("Sfx")

## 3D 音效挂到玩家所在层，避免把 AudioStreamPlayer3D 塞进敌人容器
func _audio_host() -> Node:
	return player.get_parent() if player != null else get_parent()

# ---------------------------------------------------------------- 受伤

func on_hit(pos: Vector3, _normal: Vector3, dmg := 0.0, ap: float = 0.0) -> void:
	take_damage(dmg, pos, ap)

func take_damage(dmg: float, pos: Vector3, ap: float = 0.0) -> void:
	if _dead or dmg <= 0.0:
		return
	_flash = 0.12
	# 护甲：穿甲不足则直接扣减
	var real := dmg * (1.0 + (ap - armor) * 0.1) if ap > armor else maxf(1.0, dmg - armor)
	real = roundf(real)
	hp -= real
	if health_bar:
		health_bar.update_health(hp, max_hp, hp <= 0.0, true)
	if sprite:
		sprite.modulate = Color(2.4, 0.9, 0.8)
	ImpactFX.spawn(_audio_host(), pos)
	_spawn_damage(pos, real)
	# 被打到一定进入战斗，并把最后位置设为受击方向。
	# 盲眼单位只记住被击中的位置，不会借受击瞬间获知玩家坐标。
	if blind:
		if state != State.COMBAT:
			last_known = pos
			investigate_point = pos
			_enter(State.SUSPICIOUS)
	elif state != State.COMBAT:
		last_known = player.global_position if player else pos
		_enter(State.COMBAT)
	var s := _sfx()
	if s:
		s.play_3d(_audio_host(), "hit", pos, -7.0, randf_range(0.9, 1.1))
	if hp <= 0.0:
		_die()

func _spawn_damage(pos: Vector3, dmg: float) -> void:
	if dmg <= 0.0:
		return
	var l := Label3D.new()
	l.text = str(int(round(dmg)))
	l.font = ZPIX_FONT
	l.font_size = 48
	l.pixel_size = 0.0042
	l.modulate = Color(1.0, 0.72, 0.42)
	l.billboard = 1
	l.no_depth_test = true
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = to_local(pos) + Vector3(randf_range(-0.15, 0.15), 0.35, 0)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.7, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.finished.connect(l.queue_free)

func _die() -> void:
	_dead = true
	if health_bar:
		health_bar.hide()
	state = State.PATROL
	collision_layer = 0
	agent = null
	set_physics_process(false)
	var s := _sfx()
	if s:
		s.play_3d(_audio_host(), "break", global_position + Vector3(0, 0.9, 0), -6.0, 1.2)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(1.05, 0.55, 1.05), 0.35)
	if sprite:
		tw.tween_property(sprite, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void:
		died.emit(self)
		queue_free()
	)

# ---------------------------------------------------------------- 调试

func state_name() -> String:
	return STATE_NAMES[int(state)]
