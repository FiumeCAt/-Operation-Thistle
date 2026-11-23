extends CharacterBody2D
class_name Enemy2D

## 俯视 2D 敌人：复用 EnemyDB 的数值，行为简化为
## 巡逻 → 警戒（听到声音）→ 调查 → 搜索 → 战斗 → 残血逃跑。
## 视觉用 assets/art/enemies/<id>.png 的立绘，水平翻转表示朝向。

signal died(enemy)

const UNITS := preload("res://scripts/core/GameUnits.gd")
const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const TILE := UNITS.TILE
const LOST_SIGHT := 7.0
const SEARCH_TIME := 12.0
## 发现玩家时的红色感叹号：8 帧贴图，带发光与 Wi-Fi 式外扩波纹。
const ALERT_ICON_SHEET: Texture2D = preload("res://assets/art/fx/enemy_alert.png")
const ALERT_FRAMES := 8
const ALERT_FPS := 12.0
const ALERT_LIFE := 1.25
const ALERT_ICON_SCALE := 0.68
const ALERT_ICON_LIFT := 38.0

var kind: StringName = &"rifleman"
var stats: Dictionary = {}
var hp := 70.0
var hp_max := 70.0
## 伤害倍率：浪潮模式随波次提升，常规关卡保持 1.0。
var damage_mul := 1.0
var state := "patrol"
var home := Vector2.ZERO
## 玩家引用保持无类型声明：这里只调用 Duck 类型上的 take_damage / global_position。
var player = null

var _sprite: Sprite2D
var _sprite_h := 0.0
var _bar_bg: Polygon2D
var _bar_fill: Polygon2D
var _state_t := 0.0
var _attack_cd := 0.0
var _lost_t := 0.0
var _hit_flash := 0.0
## 受击形变（压扁/拉伸）与子弹停止力造成的击退速度。
var _squash := 0.0
var _knock := Vector2.ZERO
var _wander := Vector2.ZERO
var _wander_wait := 0.0
var _last_known := Vector2.ZERO
var _dead := false
var _bob := 0.0

## 新单位动画与行为状态（旧立绘单位不会用到 _anim）。
var _anim: AnimatedSprite2D
var _anim_override := ""
var _anim_override_t := 0.0
var _burst_left := 0
var _burst_t := 0.0
var _charge_t := 0.0
var _charge_dir := Vector2.ZERO
var _charge_cd := 0.0
var _explode_t := -1.0
var _exploded := false
var _hit_sfx_cd := 0.0
## 哨戒炮：第一次攻击前红色激光锁定；锁定与开火期间原地不动。
var _turret_lock_t := 0.0
var _turret_locked := false
var _laser_on := false
var _laser_phase := 0.0
## 扇形视野：朝向会随移动/警戒目标转动，站岗时缓慢扫视。
var view_dir := Vector2.RIGHT
var view_half := deg_to_rad(55.0)
## 浪潮模式：无视侦测结果永久锁定玩家位置，主动向玩家移动。
var always_hunt := false
## 关卡寻路网格：由 Main2D 在生成时注入；没有时退回直线移动。
var nav_level = null
## 贴脸察觉半径：4 格内不依赖扇形角度，避免走到脸上还被无视。
const CLOSE_AWARE_RADIUS := 256.0
const VIEW_TURN_SPEED := 5.0
const VIEW_SWEEP_SPEED := 0.9
## 寻路重算间隔与路径点到达半径（像素）。
const NAV_REPATH := 0.55
const NAV_WAYPOINT_RADIUS := 26.0
const NAV_GOAL_TOLERANCE := 160.0

var _nav_path := PackedVector2Array()
var _nav_index := 0
var _nav_goal := Vector2.INF
var _nav_t := 0.0

## 头顶警觉图标与“上一帧是否看见玩家”的边沿检测。
var _alert_icon: Sprite2D
var _alert_t := 0.0
var _saw_player := false


func setup(kind_id: StringName, spawn: Vector2, depth: int,
		hp_mul := 1.0, damage_mul_value := 1.0) -> void:
	kind = kind_id
	stats = EnemyDB.stats(kind)
	home = spawn
	position = spawn
	hp_max = float(stats["hp"]) * pow(1.1, float(maxi(depth - 1, 0))) \
		* maxf(hp_mul, 0.01)
	hp = hp_max
	## 浪潮模式按波次放大输出；不改共享 stats，避免影响所有同类单位。
	damage_mul = maxf(damage_mul_value, 0.01)
	_wander = spawn
	_last_known = spawn
	view_dir = Vector2.from_angle(_rng_angle())
	view_half = deg_to_rad(_default_view_angle()) * 0.5


func _rng_angle() -> float:
	return randf() * TAU


## 扇形视野总角度：炮塔更宽，近战单位略窄，普通枪兵 110°。
func _default_view_angle() -> float:
	var behavior := String(stats.get("behavior", ""))
	if behavior == "turret":
		return 150.0
	if bool(stats.get("melee", false)):
		return 100.0
	return 110.0


func _ready() -> void:
	add_to_group("actors")
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1 | 2
	_build_visual()
	player = get_tree().get_first_node_in_group("player")
	if nav_level == null:
		nav_level = get_tree().get_first_node_in_group("nav_level")


func _body_scale() -> float:
	return float(stats.get("body_scale", 0.30))


func _build_visual() -> void:
	var frames_path := String(stats.get("frames", ""))
	if frames_path != "" and ResourceLoader.exists(frames_path):
		_build_animated_visual(load(frames_path))
	else:
		_build_still_visual()
	_build_body_nodes()
	_build_alert_icon()


func _build_still_visual() -> void:
	var tex: Texture2D = load(String(stats["texture"]))
	var s := _body_scale()
	_sprite_h = tex.get_height() * s
	_make_shadow()
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = false
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(-tex.get_width() * s * 0.5, -_sprite_h)
	add_child(_sprite)


## 新单位：16 帧像素图集（640×384 单元格，脚底 y=372）。
func _build_animated_visual(frames: SpriteFrames) -> void:
	var s := _body_scale()
	_sprite_h = 320.0 * s
	_make_shadow()
	_anim = AnimatedSprite2D.new()
	_anim.sprite_frames = frames
	_anim.animation = "move"
	_anim.centered = false
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_anim.scale = Vector2(s, s)
	_anim.position = Vector2(-320.0 * s, -372.0 * s)
	_anim.play("move")
	add_child(_anim)


func _make_shadow() -> void:
	var shadow := Sprite2D.new()
	shadow.texture = preload("res://assets/art/fx/shadow_radial.png")
	shadow.scale = Vector2(0.4, 0.15)
	shadow.modulate = Color(0.02, 0.02, 0.02, 0.45)
	add_child(shadow)


func _build_body_nodes() -> void:
	var shape := CircleShape2D.new()
	shape.radius = float(stats.get("collision_radius", 17.0))
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -8)
	add_child(collision)

	# 受击判定：立绘是竖直画在脚底的，脚底那个小圆只覆盖小腿。
	# 单独加一个 Area2D 覆盖整个身体高度，射线（collide_with_areas）才能打中看到的部分。
	var hitbox := Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 2
	hitbox.collision_mask = 0
	hitbox.monitoring = false
	hitbox.input_pickable = false
	var hit_shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = shape.radius
	capsule.height = maxf(_sprite_h * 0.78, 44.0)
	hit_shape.shape = capsule
	hit_shape.position = Vector2(0, -_sprite_h * 0.45)
	hitbox.add_child(hit_shape)
	add_child(hitbox)

	_bar_bg = Polygon2D.new()
	_bar_bg.polygon = PackedVector2Array([
		Vector2(-22, -_sprite_h - 12), Vector2(22, -_sprite_h - 12),
		Vector2(22, -_sprite_h - 6), Vector2(-22, -_sprite_h - 6),
	])
	_bar_bg.color = Color(0.08, 0.08, 0.09, 0.85)
	_bar_bg.visible = false
	add_child(_bar_bg)

	_bar_fill = Polygon2D.new()
	_bar_fill.color = Color(0.82, 0.26, 0.22)
	_bar_fill.visible = false
	add_child(_bar_fill)


## 头顶警觉图标：按帧播放，位置随敌人移动，初始隐藏。
func _build_alert_icon() -> void:
	_alert_icon = Sprite2D.new()
	_alert_icon.texture = ALERT_ICON_SHEET
	_alert_icon.hframes = ALERT_FRAMES
	_alert_icon.vframes = 1
	_alert_icon.frame = 0
	_alert_icon.centered = true
	_alert_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_alert_icon.scale = Vector2(ALERT_ICON_SCALE, ALERT_ICON_SCALE)
	_alert_icon.position = Vector2(0.0, -_sprite_h - ALERT_ICON_LIFT)
	_alert_icon.z_index = 40
	_alert_icon.visible = false
	add_child(_alert_icon)


func _show_alert_icon() -> void:
	if _alert_icon == null:
		return
	_alert_t = ALERT_LIFE
	_alert_icon.visible = true
	_alert_icon.frame = 0
	_alert_icon.modulate = Color(1, 1, 1, 1)
	_alert_icon.position = Vector2(0.0, -_sprite_h - ALERT_ICON_LIFT)


func _tick_alert_icon(delta: float) -> void:
	if _alert_t <= 0.0 or _alert_icon == null:
		return
	_alert_t = maxf(_alert_t - delta, 0.0)
	var elapsed := ALERT_LIFE - _alert_t
	_alert_icon.frame = int(elapsed * ALERT_FPS) % ALERT_FRAMES
	_alert_icon.position.y = -_sprite_h - ALERT_ICON_LIFT + sin(elapsed * 9.0) * 2.0
	# 尾段 0.28 秒淡出，避免图标突然消失。
	_alert_icon.modulate.a = clampf(_alert_t / 0.28, 0.0, 1.0)
	if _alert_t <= 0.0:
		_alert_icon.visible = false
		_alert_icon.position.y = -_sprite_h - ALERT_ICON_LIFT


func _physics_process(delta: float) -> void:
	if _dead:
		_tick_death_fuse(delta)
		return
	# 自爆优先于死亡：引信点燃后停止一切行动，只做倒计时与表现更新。
	if _explode_t >= 0.0 and _is_self_destruct_unit():
		_tick_self_destruct(delta)
		_tick_impact(delta)
		_tick_alert_icon(delta)
		_update_view_direction(delta)
		_update_visual(0.0, delta)
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_hit_sfx_cd = maxf(_hit_sfx_cd - delta, 0.0)
	_nav_t = maxf(_nav_t - delta, 0.0)
	_state_t += delta
	_process_burst(delta)
	if _laser_on:
		_laser_phase += delta
		queue_redraw()
	if _explode_t >= 0.0:
		queue_redraw()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	# 浪潮模式：不管是否发现玩家，都持续朝玩家当前位置推进。
	if always_hunt:
		_last_known = player.global_position
		_lost_t = 0.0
		if state != "combat" and state != "flee":
			_enter("combat")

	var to_player: Vector2 = player.global_position - global_position
	var dist: float = to_player.length()
	var can_see := can_see_player()
	# 只在“看见”的上升沿播放头顶警觉图标；持续看见不会重复刷屏。
	if can_see and not _saw_player:
		_show_alert_icon()
	_saw_player = can_see
	if not bool(stats.get("blind", false)) and can_see and state != "combat":
		_enter("combat")
	match state:
		"patrol":
			_do_patrol(delta)
		"suspicious":
			if can_see:
				_enter("combat")
			else:
				_move_toward(_last_known, 0.7, delta, true)
				if global_position.distance_to(_last_known) < 48.0:
					_enter("search")
				elif _state_t > 4.0:
					_enter("patrol")
		"search":
			if can_see:
				_enter("combat")
			elif _state_t > SEARCH_TIME:
				_enter("patrol")
			else:
				_wander_step(delta, 0.45)
		"combat":
			_do_combat(to_player, dist, can_see, delta)
		"flee":
			_move_away(player.global_position, float(stats["speed"]) * 0.85, delta)
			if _state_t > 2.5:
				_enter("combat")
	_tick_impact(delta)
	_tick_alert_icon(delta)
	_update_view_direction(delta)
	_update_visual(dist, delta)


## 扇形视野判定：距离 + 视野角 + 遮挡；贴脸时改为近身察觉。
func can_see_player() -> bool:
	if _dead or player == null or not is_instance_valid(player):
		return false
	# 声呐猎手等盲眼单位只看听觉，不参与扇形视野。
	if bool(stats.get("blind", false)):
		return false
	var dist := global_position.distance_to(player.global_position)
	if dist > float(stats["view_range"]) * TILE and dist > CLOSE_AWARE_RADIUS:
		return false
	if dist <= CLOSE_AWARE_RADIUS:
		return _line_of_sight()
	var to: Vector2 = (player.global_position - global_position).normalized()
	if absf(angle_difference(view_dir.angle(), to.angle())) > view_half:
		return false
	return _line_of_sight()


## 视野朝向：巡逻跟随移动方向，站岗缓慢扫视，警戒/战斗转向目标。
func _update_view_direction(delta: float) -> void:
	if _dead:
		return
	var aim_point := Vector2.ZERO
	var has_aim := false
	if state == "combat" and player != null and is_instance_valid(player):
		aim_point = player.global_position
		has_aim = true
	elif state == "search" or state == "suspicious":
		aim_point = _last_known
		has_aim = true
	if has_aim:
		var to := aim_point - global_position
		if to.length_squared() > 1.0:
			view_dir = _turn_view_toward(to.normalized(), delta * VIEW_TURN_SPEED)
			return
	if velocity.length_squared() > 16.0:
		view_dir = _turn_view_toward(velocity.normalized(), delta * VIEW_TURN_SPEED * 0.8)
	else:
		# 原地站岗时扇形缓慢旋转扫视，避免视野永远朝一个方向。
		view_dir = view_dir.rotated(delta * VIEW_SWEEP_SPEED)


func _turn_view_toward(target: Vector2, weight: float) -> Vector2:
	var angle := lerp_angle(view_dir.angle(), target.angle(), clampf(weight, 0.0, 1.0))
	return Vector2.from_angle(angle)


## 受击后的形变回弹与击退位移。
func _tick_impact(delta: float) -> void:
	if _squash > 0.0:
		_squash = maxf(_squash - delta * 5.5, 0.0)
		var amount := _squash * 0.16
		scale = Vector2(1.0 + amount, 1.0 - amount)
	elif scale != Vector2.ONE:
		scale = Vector2.ONE
	if _knock.length_squared() > 1.0:
		velocity = _knock
		move_and_slide()
		_knock = _knock.move_toward(Vector2.ZERO, 1900.0 * delta)


func _do_patrol(delta: float) -> void:
	_wander_step(delta, 0.35)


func _wander_step(delta: float, speed_ratio: float) -> void:
	if _wander_wait > 0.0:
		_wander_wait = maxf(_wander_wait - delta, 0.0)
		velocity = Vector2.ZERO
		return
	if global_position.distance_to(_wander) < 36.0:
		var angle := randf() * TAU
		_wander = home + Vector2.from_angle(angle) * randf_range(0.0, float(stats["patrol_radius"]) * TILE)
		_wander_wait = randf_range(0.6, 1.6)
		return
	_move_toward(_wander, speed_ratio, delta)


func _do_combat(to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	var behavior := String(stats.get("behavior", ""))
	if behavior == "charger":
		_do_charger(to_target, dist, can_see, delta)
		return
	if behavior == "suicide":
		_do_suicide(to_target, dist, can_see, delta)
		return
	if behavior == "turret":
		_do_turret(to_target, dist, can_see, delta)
		return
	var speed_px := float(stats["speed"]) * TILE
	var range_px := float(stats["range"]) * TILE
	var dir := to_target.normalized()
	if bool(stats["melee"]):
		if dist > range_px * 0.9:
			_move(_chase_dir(player.global_position), speed_px, delta)
		else:
			velocity = Vector2.ZERO
		_try_attack(dist)
	else:
		var desired := range_px * 0.75
		# 浪潮永久追踪：看不见玩家时不保持交战距离，持续朝玩家方向压过去。
		if always_hunt and not can_see:
			desired = 0.0
		if dist > desired * 1.2:
			_move(_chase_dir(player.global_position), speed_px, delta)
		elif dist < desired * 0.65:
			_move(-dir, speed_px, delta)
		elif bool(stats.get("strafe", false)):
			_move(dir.orthogonal() * (1.0 if fmod(_state_t, 2.0) > 1.0 else -1.0), speed_px * 0.55, delta)
		else:
			velocity = Vector2.ZERO
		if can_see:
			_try_attack(dist)

	if can_see:
		_lost_t = 0.0
		_last_known = player.global_position
	else:
		_lost_t += delta
		if _lost_t > LOST_SIGHT and not always_hunt:
			_enter("search")

	if hp <= hp_max * 0.25 and bool(stats.get("flees", false)):
		_enter("flee")


## 移动哨卫炮：一次攻击分两发，按 burst_interval 间隔出膛。
func _process_burst(delta: float) -> void:
	if _burst_left <= 0:
		return
	_burst_t -= delta
	if _burst_t > 0.0:
		return
	if player == null or not is_instance_valid(player):
		_burst_left = 0
		return
	_fire_round()
	_burst_left -= 1
	_burst_t = float(stats.get("burst_interval", 0.12))


## 哨兵一型：发现后先蓄力，再直线冲撞；撞到玩家造成伤害并进入冷却。
func _do_charger(to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	var speed_px := float(stats["speed"]) * TILE
	var range_px := float(stats["range"]) * TILE
	var dir := to_target.normalized()
	if _charge_t > 0.0:
		_charge_t = maxf(_charge_t - delta, 0.0)
		velocity = _charge_dir * float(stats.get("charge_speed", 6.0)) * TILE
		move_and_slide()
		_play_anim_override("attack", 0.2)
		if dist < range_px * 1.5:
			_charge_t = 0.0
			_charge_cd = float(stats.get("charge_cooldown", 3.0))
			_attack_cd = float(stats["cooldown"])
			_attack_flash(Color(0.45, 1.0, 0.55))
			_sfx("ram", -4.0, randf_range(0.95, 1.05))
			_shake(5.0)
			if player != null and is_instance_valid(player):
				player.take_damage(float(stats["damage"]) * damage_mul, _attack_ap())
				Shot2D.hit_burst(get_parent(), player.global_position + Vector2(0, -60),
					(player.global_position - global_position).normalized(), "flesh", 0.7)
		return
	if can_see and dist > range_px * 1.8 and _charge_cd <= 0.0 and _line_of_sight():
		_charge_dir = dir
		_charge_t = 0.8
		_sfx("charge_up", -9.0, randf_range(0.95, 1.05))
		_play_anim_override("alert", 0.35)
	else:
		if dist > range_px * 0.9:
			_move(_chase_dir(player.global_position), speed_px, delta)
		else:
			velocity = Vector2.ZERO
		_try_attack(dist)
	if can_see:
		_lost_t = 0.0
		_last_known = player.global_position
	else:
		_lost_t += delta
		if _lost_t > LOST_SIGHT and not always_hunt:
			_enter("search")


## 哥利亚：贴近玩家后坐地，引信结束后自爆并同时死亡。
func _do_suicide(to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	var range_px := float(stats["range"]) * TILE
	if _explode_t >= 0.0:
		_tick_self_destruct(delta)
		return
	if dist > range_px:
		_move(_chase_dir(player.global_position), float(stats["speed"]) * TILE, delta)
	else:
		_begin_self_destruct()
		_play_anim_override("attack", 0.6)
	if can_see:
		_lost_t = 0.0
		_last_known = player.global_position
	else:
		_lost_t += delta
		if _lost_t > LOST_SIGHT and not always_hunt:
			_enter("search")


## 自爆单位：哥利亚这类单位血量不会归零，而是锁在 1 点并点燃引信。
func _is_self_destruct_unit() -> bool:
	return bool(stats.get("death_explode", false)) \
		or String(stats.get("behavior", "")) == "suicide"


## 进入自爆状态：停止移动、坐地并启动引信；重复调用只保留第一次的引信。
func _begin_self_destruct() -> void:
	if _dead or _explode_t >= 0.0:
		return
	_explode_t = maxf(float(stats.get("explode_delay", 2.0)), 0.01)
	velocity = Vector2.ZERO
	_play_anim_override("attack", 0.2)
	_sfx("fuse_long", -8.0)
	if state != "combat":
		_enter("combat")
	queue_redraw()


## 自爆引信倒计时：归零时爆炸并死亡，两个事件在同一帧结算。
func _tick_self_destruct(delta: float) -> void:
	if _explode_t < 0.0:
		return
	_explode_t -= delta
	velocity = Vector2.ZERO
	_play_anim_override("attack", 0.2)
	queue_redraw()
	if _explode_t <= 0.0:
		# 先清空引信，确保爆炸→死亡的同一帧不会再次触发死亡引信结算。
		_explode_t = -1.0
		_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_explode_damage()
	_die()


## 移动哨卫炮：发现后先用红色激光锁定，锁定和开火期间原地不动；
## 只有丢失目标才恢复搜索/巡逻。
func _do_turret(to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	velocity = Vector2.ZERO
	if not can_see:
		_laser_on = false
		_turret_lock_t = 0.0
		_turret_locked = false
		queue_redraw()
		_lost_t += delta
		if _lost_t > LOST_SIGHT and not always_hunt:
			_enter("search")
		return
	_lost_t = 0.0
	_last_known = player.global_position
	if not _turret_locked:
		_turret_lock_t = maxf(_turret_lock_t - delta, 0.0)
		_laser_on = true
		queue_redraw()
		_play_anim_override("alert", 0.2)
		if _turret_lock_t <= 0.0:
			_turret_locked = true
			_attack_cd = 0.0
			_try_attack(dist)
		return
	# 锁定完成后激光继续保留，作为持续瞄准提示。
	_laser_on = true
	queue_redraw()
	_try_attack(dist)


func _draw() -> void:
	if _explode_t >= 0.0:
		_draw_blast_ring()
	if not _laser_on or player == null or not is_instance_valid(player):
		return
	var from := Vector2(0.0, -_sprite_h * 0.62)
	var to: Vector2 = player.global_position - global_position + Vector2(0.0, -46.0)
	draw_line(from, to, Color(1.0, 0.04, 0.03, 0.06), 7.0)
	draw_line(from, to, Color(1.0, 0.10, 0.06, 0.22), 2.5)
	draw_line(from, to, Color(1.0, 0.30, 0.22, 0.55), 1.0)
	var pulse := 2.4 + 1.2 * sin(_laser_phase * 22.0)
	draw_circle(to, pulse, Color(1.0, 0.12, 0.08, 0.45))
	draw_circle(from, 2.0, Color(1.0, 0.25, 0.18, 0.55))


## 哥利亚 2 秒倒计时：半透明红圈 + 从边缘向内填充的进度。
func _draw_blast_ring() -> void:
	var total := maxf(float(stats.get("explode_delay", 2.0)), 0.01)
	var radius := float(stats.get("explode_radius", 3.2)) * TILE
	var progress := clampf(1.0 - _explode_t / total, 0.0, 1.0)
	var center := Vector2(0.0, -6.0)
	draw_circle(center, radius, Color(1.0, 0.08, 0.06, 0.10))
	draw_arc(center, radius, 0.0, TAU, 72, Color(1.0, 0.20, 0.12, 0.55), 2.0)
	var width := maxf(2.0, radius * progress)
	draw_arc(center, radius - width * 0.5, 0.0, TAU, 72,
		Color(1.0, 0.25, 0.16, 0.26), width)
	if progress > 0.98:
		draw_circle(center, radius, Color(1.0, 0.20, 0.12, 0.22))


func _sfx(kind: String, volume_db := 0.0, pitch := 1.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play_2d(kind, volume_db, pitch)


func _shake(amount: float) -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("add_shake"):
			node.add_shake(amount)
			return
		node = node.get_parent()


## 爆炸友伤比例：歌利亚狂潮内降到 50%，减少歌利亚互相引爆；
## 其他模式保持原来的 80%。
func friendly_explosion_mul() -> float:
	var progress := get_node_or_null("/root/Progress")
	if progress != null and progress.has_method("map_id") \
			and String(progress.run_mode()) == "waves" \
			and String(progress.map_id()) == "goliath_arena":
		return 0.5
	return 0.8


## 爆炸伤害对玩家和附近敌人同时生效（哥利亚的死亡爆炸也走这里）。
func _explode_damage() -> void:
	var radius_px := float(stats.get("explode_radius", 3.0)) * TILE
	var dmg := float(stats.get("explode_damage", 60.0)) * damage_mul
	_sfx("boom", -3.0, randf_range(0.94, 1.02))
	_shake(8.0)
	if player != null and is_instance_valid(player) \
			and player.global_position.distance_to(global_position) <= radius_px:
		player.take_damage(dmg, 45.0)
	var friendly_mul := friendly_explosion_mul()
	# 竞技场内友军爆炸按目标护甲等穿结算，不做余穿放大也不减伤，确保 50% 就是实打实的半伤，
	# 满血歌利亚不会因为一次连锁立刻被带走。
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Enemy2D) or other.hp <= 0.0:
			continue
		if other.global_position.distance_to(global_position) <= radius_px:
			var friendly_ap := float(other.stats["armor"]) if friendly_mul <= 0.5 else 60.0
			other.take_damage(dmg * friendly_mul, friendly_ap)
	_spawn_explosion_fx(radius_px)


func _spawn_explosion_fx(radius_px: float) -> void:
	var fx := Node2D.new()
	fx.global_position = global_position + Vector2(0, -18)
	fx.z_index = 80
	get_parent().add_child(fx)
	var points := PackedVector2Array()
	for i in 28:
		points.append(Vector2.from_angle(TAU * float(i) / 28.0) * 20.0)
	var blast := Polygon2D.new()
	blast.polygon = points
	blast.color = Color(1.0, 0.52, 0.16, 0.8)
	fx.add_child(blast)
	var core := Polygon2D.new()
	core.polygon = points
	core.color = Color(1.0, 0.92, 0.7, 0.95)
	core.scale = Vector2(0.45, 0.45)
	fx.add_child(core)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2.ONE * (radius_px / 20.0), 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(blast, "modulate:a", 0.0, 0.36)
	tw.tween_property(core, "scale", Vector2.ONE * (radius_px / 20.0) * 0.6, 0.2)
	tw.tween_property(core, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(fx.queue_free)
	for i in 8:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(10.0, radius_px * 0.8)
		Shot2D.impact(get_parent(), global_position + offset + Vector2(0, -20),
			Color(1.0, 0.55, 0.2))


func _play_anim_override(anim_name: String, time: float) -> void:
	if _anim == null:
		return
	_anim_override = anim_name
	_anim_override_t = maxf(_anim_override_t, time)


## 追击方向：优先沿 A* 路径绕过墙体，路径不可用时退回直线。
func _chase_dir(target: Vector2) -> Vector2:
	var pathed := _path_dir(target)
	if pathed.length_squared() > 0.0001:
		return pathed
	var direct := target - global_position
	if direct.length_squared() < 1.0:
		return Vector2.ZERO
	return direct.normalized()


func _path_dir(target: Vector2) -> Vector2:
	if nav_level == null or not nav_level.has_method("find_nav_path"):
		return Vector2.ZERO
	var needs_repath := _nav_t <= 0.0 or _nav_goal == Vector2.INF \
		or target.distance_to(_nav_goal) > NAV_GOAL_TOLERANCE
	if needs_repath:
		_nav_path = nav_level.find_nav_path(global_position, target)
		_nav_index = 1 if _nav_path.size() > 1 else 0
		_nav_goal = target
		_nav_t = NAV_REPATH
	while _nav_index < _nav_path.size() \
			and global_position.distance_to(_nav_path[_nav_index]) <= NAV_WAYPOINT_RADIUS:
		_nav_index += 1
	if _nav_index >= _nav_path.size():
		return Vector2.ZERO
	var to := _nav_path[_nav_index] - global_position
	if to.length_squared() < 1.0:
		return Vector2.ZERO
	return to.normalized()


## 近距避障：正前方撞墙时向两侧试探，避免贴住墙角原地抖动。
func _avoid_walls(dir: Vector2) -> Vector2:
	var probe := float(stats.get("collision_radius", 17.0)) + 26.0
	if _probe_clear(dir, probe):
		return dir
	for angle in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var probe_dir := dir.rotated(deg_to_rad(angle))
		if _probe_clear(probe_dir, probe):
			return probe_dir
	return dir


func _probe_clear(dir: Vector2, dist: float) -> bool:
	var origin := global_position + Vector2(0, -8)
	var query := PhysicsRayQueryParameters2D.create(origin, origin + dir * dist, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _move(dir: Vector2, speed_px: float, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		velocity = Vector2.ZERO
		return
	velocity = _avoid_walls(dir.normalized()) * speed_px
	move_and_slide()


func _move_toward(point: Vector2, speed_ratio: float, delta: float,
		use_nav := false) -> void:
	var delta_vec := point - global_position
	if delta_vec.length() < 8.0:
		velocity = Vector2.ZERO
		return
	var dir := _chase_dir(point) if use_nav else delta_vec.normalized()
	_move(dir, float(stats["speed"]) * TILE * speed_ratio, delta)


func _move_away(from: Vector2, speed_px: float, delta: float) -> void:
	var away := global_position - from
	if away.length() < 1.0:
		return
	_move(away.normalized(), speed_px * TILE * 0.9, delta)


func _try_attack(dist: float) -> void:
	if _attack_cd > 0.0 or not _line_of_sight():
		return
	var range_px := float(stats["range"]) * TILE
	if bool(stats["melee"]):
		if dist <= range_px * 1.1:
			_attack_cd = float(stats["cooldown"])
			_attack_flash(Color(0.92, 0.32, 0.24))
			_play_anim_override("attack", 0.35)
			if String(stats.get("behavior", "")) == "melee":
				_sfx("stab", -7.0, randf_range(0.95, 1.05))
			_melee_slash(player.global_position)
			player.take_damage(float(stats["damage"]) * damage_mul, _attack_ap())
			Shot2D.hit_burst(get_parent(), player.global_position + Vector2(0, -60),
				(player.global_position - global_position).normalized(), "flesh", 0.7)
	else:
		if dist <= range_px * 1.25:
			_attack_cd = float(stats["cooldown"])
			_attack_flash(Color(1.0, 0.78, 0.36))
			_play_anim_override("attack", 0.4)
			var burst := int(stats.get("burst", 1))
			if burst > 1:
				_burst_left = burst
				_burst_t = 0.0
			else:
				_fire_round()


## 远程攻击表现：枪口闪光后发射可见子弹，命中时在玩家身上溅火花。
func _fire_round() -> void:
	if player == null or not is_instance_valid(player):
		return
	if _anim != null:
		_sfx("turret_shot", -6.0, randf_range(0.93, 1.03))
	var muzzle := global_position + Vector2(0, -_sprite_h * 0.55)
	var target: Vector2 = player.global_position + Vector2(0, -46)
	var dir := (target - muzzle).normalized()
	var parent := get_parent()
	if parent != null:
		EnemyBullet2D.spawn(parent, muzzle + dir * 12.0, target,
			float(stats["damage"]) * damage_mul, _attack_ap())


## 近战挥击：朝玩家的弧形刀光，短暂淡出。
func _melee_slash(target: Vector2) -> void:
	var angle := (target - global_position).angle()
	var arc := Line2D.new()
	var points := PackedVector2Array()
	for i in 9:
		var a := angle - 0.65 + 1.3 * float(i) / 8.0
		points.append(Vector2.from_angle(a) * 30.0)
	arc.points = points
	arc.width = 5.0
	arc.default_color = Color(1.0, 0.42, 0.28, 0.92)
	arc.z_index = 60
	arc.position = Vector2(0, -_sprite_h * 0.45)
	add_child(arc)
	var tw := create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.18)
	tw.tween_callback(arc.queue_free)


## 敌人攻击穿甲值（0.1 mm RHA 体系）：区分普通近战/9mm 与装甲单位高穿火力。
func _attack_ap() -> float:
	match kind:
		&"rifleman":
			return 22.0
		&"sentry_type1":
			return 25.0
		&"mobile_turret":
			return 35.0
		&"hunter_type1":
			return 40.0
		&"heavy":
			return 55.0
		_:
			return 12.0


func _attack_flash(color: Color) -> void:
	var flash := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		points.append(Vector2(cos(a) * 9, sin(a) * 9))
	flash.polygon = points
	flash.color = color
	flash.position = Vector2(0, -_sprite_h * 0.55)
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.14)
	tween.tween_callback(flash.queue_free)


func _line_of_sight() -> bool:
	if player == null:
		return false
	var space := get_world_2d().direct_space_state
	# 胸/膝两条射线同时检查：膝部射线抬高到掩体顶部以上，避免敌人贴着物料箱时被自己的掩体挡住视线。
	return _ray_clear(space, global_position + Vector2(0, -_sprite_h * 0.55),
			player.global_position + Vector2(0, -60)) \
		and _ray_clear(space, global_position + Vector2(0, -26),
			player.global_position + Vector2(0, -26))


func _ray_clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()


## 能否看见指定位置（用于观察队友倒下）；只做距离外的射线遮挡判断。
func can_see_point(point: Vector2) -> bool:
	if _dead:
		return false
	var space := get_world_2d().direct_space_state
	return _ray_clear(space, global_position + Vector2(0, -_sprite_h * 0.55),
			point + Vector2(0, -20.0)) \
		and _ray_clear(space, global_position + Vector2(0, -26),
			point + Vector2(0, -26))


## 视野内队友被击杀：记住玩家的最新位置并重新进入搜索/战斗。
## 即使原本已经在搜索，也会刷新搜索计时，避免队友倒下后马上放弃。
func alert_by_ally_death(clue_pos: Vector2) -> void:
	if _dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player):
		_last_known = player.global_position
	else:
		_last_known = clue_pos
	_lost_t = 0.0
	if player != null and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) \
				< float(stats["view_range"]) * TILE \
			and _line_of_sight():
		_enter("combat")
		return
	if state == "search":
		_state_t = 0.0
		_wander = _last_known
	else:
		_enter("search")


func _enter(new_state: String) -> void:
	if state == new_state:
		return
	if new_state == "combat" and state != "combat":
		if _anim != null:
			_sfx("enemy_alert", -10.0, randf_range(0.96, 1.05))
		if String(stats.get("behavior", "")) == "turret":
			_turret_locked = false
			_turret_lock_t = 0.75
			_laser_on = true
			_laser_phase = 0.0
			_sfx("turret_lock", -7.0)
		_play_anim_override("alert", 0.4)
	else:
		_laser_on = false
		_turret_lock_t = 0.0
		_turret_locked = false
		queue_redraw()
	state = new_state
	_state_t = 0.0
	_lost_t = 0.0
	if new_state == "search":
		_wander = _last_known
	elif new_state == "patrol":
		_wander = home


func _update_visual(dist: float, delta: float) -> void:
	_anim_override_t = maxf(_anim_override_t - delta, 0.0)
	var facing_left: bool = player != null and player.global_position.x < global_position.x
	if _anim != null:
		_anim.flip_h = facing_left
		if _explode_t >= 0.0:
			# 自爆倒计时：停在坐地帧，红圈负责倒计时，不循环爆炸帧。
			_set_anim("attack")
			if _anim.is_playing():
				if _anim.frame >= 1:
					_anim.pause()
					_anim.frame = 1
			else:
				_anim.frame = 1
		else:
			var anim_name := "move"
			if _anim_override_t > 0.0 and _anim_override != "":
				anim_name = _anim_override
			elif _charge_t > 0.0:
				anim_name = "attack"
			_set_anim(anim_name)
			if anim_name != "move":
				if not _anim.is_playing():
					_anim.play(anim_name)
			elif velocity.length() > 1.0:
				if not _anim.is_playing():
					_anim.play("move")
			else:
				_anim.pause()
		if _hit_flash > 0.0:
			_anim.modulate = _flash_color()
		else:
			_anim.modulate = Color.WHITE
	elif _sprite == null:
		return
	else:
		_sprite.flip_h = facing_left
		var moving := velocity.length() > 1.0
		if moving:
			_bob += delta * 9.0
			_sprite.position.y = -_sprite_h + absf(sin(_bob)) * -2.0
		if _hit_flash > 0.0:
			_sprite.modulate = _flash_color()
		else:
			_sprite.modulate = Color.WHITE
	# 受伤后短暂显示血条（死亡后的引信阶段不再显示空血条）
	var show_bar := hp < hp_max - 0.5 and not _dead
	_bar_bg.visible = show_bar
	_bar_fill.visible = show_bar
	if show_bar:
		var ratio := clampf(hp / hp_max, 0.0, 1.0)
		var left := -22.0
		var right := left + 44.0 * ratio
		_bar_fill.polygon = PackedVector2Array([
			Vector2(left, -_sprite_h - 11), Vector2(right, -_sprite_h - 11),
			Vector2(right, -_sprite_h - 7), Vector2(left, -_sprite_h - 7),
		])


func _set_anim(anim_name: String) -> void:
	if _anim == null or _anim.animation == anim_name:
		return
	_anim.play(anim_name)


## 受击闪白：金属偏冷白，血肉偏暖白，避免所有敌人都是一个颜色。
func _flash_color() -> Color:
	if hit_material() == "flesh":
		return Color(2.2, 1.75, 1.75)
	return Color(1.85, 2.05, 2.2)


func take_damage(amount: float, ap: float = 0.0, impulse: Vector2 = Vector2.ZERO) -> float:
	if _dead:
		return 0.0
	var armor := float(stats["armor"])
	var dmg: float = DAMAGE_MODEL.resolve_enemy_damage(amount, ap, armor)
	hp -= dmg
	_hit_flash = 0.14
	# 停止力：击退 + 沿受击方向的压扁形变，重武器推得更远，大体型抗推。
	if impulse.length_squared() > 1.0:
		_knock += (impulse / maxf(hit_weight(), 0.9)).limit_length(340.0)
		_squash = 1.0
	if _hit_sfx_cd <= 0.0:
		_hit_sfx_cd = 0.06
		var sfx := get_node_or_null("/root/Sfx")
		if sfx != null:
			sfx.play_hit(hit_material(), hit_weight(), -11.0)
	_enter("combat")
	if _is_self_destruct_unit():
		# 自爆期间每受击一次，剩余引信缩短 20%（含接近后自行点燃的引信）。
		if _explode_t >= 0.0:
			_explode_t = maxf(_explode_t * 0.8, 0.0)
		if hp <= 1.0:
			# 自爆优先于死亡：致命伤害只把血量压到 1 点并点燃引信。
			hp = 1.0
			if _explode_t < 0.0:
				_begin_self_destruct()
	elif hp <= 0.0:
		_die()
	return dmg


## 身体核心点：反穿墙判定用，只打到探出墙外的受击盒不会结算伤害。
func body_center() -> Vector2:
	return global_position + Vector2(0.0, -_sprite_h * 0.45)


## 脚底物理核心点：CharacterBody2D 碰撞圆心，始终位于可行走地面，
## 用于区分“敌人贴在北墙下方（立绘投影进墙但人就在同侧）”与“敌人真在墙另一侧”。
func ground_center() -> Vector2:
	return global_position + Vector2(0.0, -8.0)


## 命中材质：决定火花还是血，来自 enemies.json 的 hit_material。
func hit_material() -> String:
	return String(stats.get("hit_material", "metal"))


## 体型权重：大血量单位吃枪时反馈更重（火花更多、低频更沉）。
func hit_weight() -> float:
	return clampf(float(stats.get("hp", 70.0)) / 100.0, 0.7, 1.8)


## 枪声：听到后去声源处查看（巡逻 / 搜索状态才会被吸引）。
func hear_noise(pos: Vector2, radius_m: float) -> void:
	if _dead or state == "combat":
		return
	if global_position.distance_to(pos) > radius_m * TILE:
		return
	_last_known = pos
	if state != "suspicious":
		_enter("suspicious")


func _die() -> void:
	if _dead:
		return
	_dead = true
	if _alert_icon != null:
		_alert_icon.visible = false
	died.emit(self)
	remove_from_group("enemies")
	remove_from_group("actors")
	collision_layer = 0
	var hitbox := get_node_or_null("Hitbox") as Area2D
	if hitbox != null:
		hitbox.collision_layer = 0
	velocity = Vector2.ZERO
	_laser_on = false
	queue_redraw()
	# 哥利亚：被击杀也要先走完引信，而不是瞬间爆炸。
	if bool(stats.get("death_explode", false)) and not _exploded:
		if _explode_t < 0.0:
			_explode_t = float(stats.get("explode_delay", 2.0))
			_sfx("fuse_long", -8.0)
		_play_anim_override("attack", 0.2)
		return
	_finish_death_visual()


## 死亡后的引信倒计时：仍然绘制红圈，读秒结束后爆炸并收尾。
func _tick_death_fuse(delta: float) -> void:
	if _explode_t < 0.0 or _exploded:
		return
	_explode_t -= delta
	queue_redraw()
	_update_visual(0.0, delta)
	if _explode_t > 0.0:
		return
	_explode_t = -1.0
	_exploded = true
	_explode_damage()
	_finish_death_visual()


## 死亡动画与节点回收；自爆单位在爆炸后播死亡帧。
func _finish_death_visual() -> void:
	if _anim != null:
		if not _exploded or not bool(stats.get("death_explode", false)):
			_sfx("enemy_death", -9.0, randf_range(0.95, 1.05))
		_anim.play("death")
		var anim_tween := create_tween()
		anim_tween.tween_interval(0.5)
		anim_tween.tween_property(_anim, "modulate:a", 0.0, 0.2)
		anim_tween.tween_callback(queue_free)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.3)
	tween.tween_property(_sprite, "scale", Vector2(_sprite.scale.x * 0.8, 0.05), 0.3)
	tween.chain().tween_callback(queue_free)
