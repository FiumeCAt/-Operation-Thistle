extends CharacterBody2D
class_name Enemy2D

## 俯视 2D 敌人协调入口：负责 AI 状态机（巡逻 → 警戒 → 搜索 → 战斗 → 逃跑）、受击与死亡主流程。
## 类型化配置、视觉/特效、感知/寻路与 5 类战斗策略分别委托至：
## EnemyDef / EnemyVisual2D / EnemyPerception2D / EnemyCombat2D。

signal died(enemy)

const UNITS := preload("res://scripts/core/GameUnits.gd")
const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const ENEMY_DEF := preload("res://scripts/actors/enemy/EnemyDef.gd")
const ENEMY_VISUAL := preload("res://scripts/actors/enemy/EnemyVisual2D.gd")
const ENEMY_PERCEPTION := preload("res://scripts/actors/enemy/EnemyPerception2D.gd")
const ENEMY_COMBAT := preload("res://scripts/actors/enemy/EnemyCombat2D.gd")

const TILE := UNITS.TILE
const LOST_SIGHT := ENEMY_COMBAT.LOST_SIGHT
const SEARCH_TIME := 12.0
const ALERT_ICON_SHEET: Texture2D = ENEMY_VISUAL.ALERT_ICON_SHEET
const ALERT_FRAMES := ENEMY_VISUAL.ALERT_FRAMES
const ALERT_FPS := ENEMY_VISUAL.ALERT_FPS
const ALERT_LIFE := ENEMY_VISUAL.ALERT_LIFE
const ALERT_ICON_SCALE := ENEMY_VISUAL.ALERT_ICON_SCALE
const ALERT_ICON_LIFT := ENEMY_VISUAL.ALERT_ICON_LIFT
const CLOSE_AWARE_RADIUS := ENEMY_PERCEPTION.CLOSE_AWARE_RADIUS
const VIEW_TURN_SPEED := ENEMY_PERCEPTION.VIEW_TURN_SPEED
const VIEW_SWEEP_SPEED := ENEMY_PERCEPTION.VIEW_SWEEP_SPEED
const NAV_REPATH := ENEMY_PERCEPTION.NAV_REPATH
const NAV_WAYPOINT_RADIUS := ENEMY_PERCEPTION.NAV_WAYPOINT_RADIUS
const NAV_GOAL_TOLERANCE := ENEMY_PERCEPTION.NAV_GOAL_TOLERANCE

var kind: StringName = &"rifleman"
var stats: Dictionary = {}
var def: EnemyDef = ENEMY_DEF.new()
var hp := 70.0
var hp_max := 70.0
## 伤害倍率：浪潮模式随波次提升，常规关卡保持 1.0。
var damage_mul := 1.0
var state := "patrol"
var home := Vector2.ZERO
## 玩家引用保持无类型声明：这里只调用 Duck 类型上的 take_damage / global_position。
var player = null
## 浪潮模式：无视侦测结果永久锁定玩家位置，主动向玩家移动。
var always_hunt := false
## 关卡寻路网格：由 Main2D 在生成时注入；没有时退回直线移动。
var nav_level = null

var visual: EnemyVisual2D = ENEMY_VISUAL.new()
var perception: EnemyPerception2D = ENEMY_PERCEPTION.new()
var combat: EnemyCombat2D = ENEMY_COMBAT.new()

## 视觉子系统兼容转发属性（保留旧测试与表现层字段访问）。
var _sprite: Sprite2D:
	get: return visual.sprite
	set(v): visual.sprite = v
var _sprite_h: float:
	get: return visual.sprite_h
	set(v): visual.sprite_h = v
var _anim: AnimatedSprite2D:
	get: return visual.anim
	set(v): visual.anim = v
var _alert_icon: Sprite2D:
	get: return visual.alert_icon
	set(v): visual.alert_icon = v
var _alert_t: float:
	get: return visual.alert_t
	set(v): visual.alert_t = v
var _hit_flash: float:
	get: return visual.hit_flash
	set(v): visual.hit_flash = v
var _squash: float:
	get: return visual.squash
	set(v): visual.squash = v

## 感知子系统兼容转发属性。
var view_dir: Vector2:
	get: return perception.view_dir
	set(v): perception.view_dir = v
var view_half: float:
	get: return perception.view_half
	set(v): perception.view_half = v

## 战斗子系统兼容转发属性。
var _attack_cd: float:
	get: return combat.attack_cd
	set(v): combat.attack_cd = v
var _burst_left: int:
	get: return combat.burst_left
	set(v): combat.burst_left = v
var _burst_t: float:
	get: return combat.burst_t
	set(v): combat.burst_t = v
var _charge_t: float:
	get: return combat.charge_t
	set(v): combat.charge_t = v
var _charge_dir: Vector2:
	get: return combat.charge_dir
	set(v): combat.charge_dir = v
var _charge_cd: float:
	get: return combat.charge_cd
	set(v): combat.charge_cd = v
var _explode_t: float:
	get: return combat.explode_t
	set(v): combat.explode_t = v
var _exploded: bool:
	get: return combat.exploded
	set(v): combat.exploded = v
var _turret_lock_t: float:
	get: return combat.turret_lock_t
	set(v): combat.turret_lock_t = v
var _turret_locked: bool:
	get: return combat.turret_locked
	set(v): combat.turret_locked = v
var _laser_on: bool:
	get: return combat.laser_on
	set(v): combat.laser_on = v
var _laser_phase: float:
	get: return combat.laser_phase
	set(v): combat.laser_phase = v

var _state_t := 0.0
var _lost_t := 0.0
var _knock := Vector2.ZERO
var _wander := Vector2.ZERO
var _wander_wait := 0.0
var _last_known := Vector2.ZERO
var _dead := false
var _hit_sfx_cd := 0.0


func setup(kind_id: StringName, spawn: Vector2, depth: int,
		hp_mul := 1.0, damage_mul_value := 1.0) -> void:
	kind = kind_id
	stats = EnemyDB.stats(kind)
	def = ENEMY_DEF.from_dict(kind, stats)
	home = spawn
	position = spawn
	hp_max = def.scaled_hp(depth, hp_mul)
	hp = hp_max
	damage_mul = maxf(damage_mul_value, 0.01)
	_wander = spawn
	_last_known = spawn
	perception.init_view(randf() * TAU, def.default_view_angle())


func _ready() -> void:
	add_to_group("actors")
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 1 | 2
	visual.build(self, def)
	player = get_tree().get_first_node_in_group("player")
	if nav_level == null:
		nav_level = get_tree().get_first_node_in_group("nav_level")


func _physics_process(delta: float) -> void:
	if _dead:
		combat.tick_death_fuse(self, delta)
		return
	# 自爆优先于死亡：引信点燃后停止一切行动，只做倒计时与表现更新。
	if _explode_t >= 0.0 and def.is_self_destruct_unit():
		combat.tick_self_destruct(self, delta)
		_tick_impact(delta)
		visual.tick_alert_icon(delta)
		_update_view_direction(delta)
		_update_visual(0.0, delta)
		return
	visual.tick_flash(delta)
	_hit_sfx_cd = maxf(_hit_sfx_cd - delta, 0.0)
	perception.tick(delta)
	_state_t += delta
	combat.tick_cooldowns(self, delta)
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
	if can_see and not perception.saw_player:
		visual.show_alert_icon()
	perception.saw_player = can_see
	if not def.blind and can_see and state != "combat":
		_enter("combat")
	match state:
		"patrol":
			_wander_step(delta, 0.35)
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
			combat.do_combat(self, to_player, dist, can_see, delta)
		"flee":
			_move_away(player.global_position, def.speed * 0.85, delta)
			if _state_t > 2.5:
				_enter("combat")
	_tick_impact(delta)
	visual.tick_alert_icon(delta)
	_update_view_direction(delta)
	_update_visual(dist, delta)


func _tick_impact(delta: float) -> void:
	visual.tick_squash(self, delta)
	if _knock.length_squared() > 1.0:
		velocity = _knock
		move_and_slide()
		_knock = _knock.move_toward(Vector2.ZERO, 1900.0 * delta)


func _wander_step(delta: float, speed_ratio: float) -> void:
	if _wander_wait > 0.0:
		_wander_wait = maxf(_wander_wait - delta, 0.0)
		velocity = Vector2.ZERO
		return
	if global_position.distance_to(_wander) < 36.0:
		var angle := randf() * TAU
		_wander = home + Vector2.from_angle(angle) * randf_range(0.0, def.patrol_radius * TILE)
		_wander_wait = randf_range(0.6, 1.6)
		return
	_move_toward(_wander, speed_ratio, delta)


func _enter(new_state: String) -> void:
	if state == new_state:
		return
	var old_state := state
	if new_state == "combat" and old_state != "combat":
		if always_hunt:
			var sfx := get_node_or_null("/root/Sfx")
			if sfx != null and sfx.has_method("play_wave_spawn_cue"):
				sfx.play_wave_spawn_cue(-10.0, randf_range(0.96, 1.05))
		elif _anim != null:
			_sfx("enemy_alert", -10.0, randf_range(0.96, 1.05))
		_play_anim_override("alert", 0.4)
	combat.on_state_entered(self, new_state, old_state)
	state = new_state
	_state_t = 0.0
	_lost_t = 0.0
	if new_state == "search":
		_wander = _last_known
	elif new_state == "patrol":
		_wander = home


## 视野内队友被击杀：记住玩家的最新位置并重新进入搜索/战斗。
func alert_by_ally_death(clue_pos: Vector2) -> void:
	if _dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	_last_known = player.global_position if (player != null and is_instance_valid(player)) else clue_pos
	_lost_t = 0.0
	if player != null and is_instance_valid(player) \
			and global_position.distance_to(player.global_position) < def.view_range * TILE \
			and _line_of_sight():
		_enter("combat")
		return
	if state == "search":
		_state_t = 0.0
		_wander = _last_known
	else:
		_enter("search")


## 枪声：听到后去声源处查看（巡逻 / 搜索状态才会被吸引）。
func hear_noise(pos: Vector2, radius_m: float) -> void:
	if _dead or state == "combat":
		return
	if global_position.distance_to(pos) > radius_m * TILE:
		return
	_last_known = pos
	if state != "suspicious":
		_enter("suspicious")


func take_damage(amount: float, ap: float = 0.0, impulse: Vector2 = Vector2.ZERO,
		is_flesh_ammo: bool = false) -> float:
	if _dead:
		return 0.0
	var f_mul := def.flesh_mul if is_flesh_ammo else 1.0
	var dmg: float = DAMAGE_MODEL.resolve_enemy_damage(amount, ap, def.armor, def.blunt_floor, f_mul)
	hp -= dmg
	_hit_flash = 0.14
	if impulse.length_squared() > 1.0:
		_knock += (impulse / maxf(hit_weight(), 0.9)).limit_length(340.0)
		_squash = 1.0
	if _hit_sfx_cd <= 0.0:
		_hit_sfx_cd = 0.06
		var sfx := get_node_or_null("/root/Sfx")
		if sfx != null:
			sfx.play_hit(hit_material(), hit_weight(), -11.0)
	_enter("combat")
	if def.is_self_destruct_unit():
		combat.on_self_destruct_damaged(self, dmg)
	elif hp <= 0.0:
		_die()
	return dmg


func _die() -> void:
	if _dead:
		return
	_dead = true
	visual.hide_alert_icon()
	died.emit(self)
	remove_from_group("enemies")
	remove_from_group("actors")
	collision_layer = 0
	var hitbox := get_node_or_null("Hitbox") as Area2D
	if hitbox != null:
		hitbox.collision_layer = 0
	velocity = Vector2.ZERO
	combat.clear_laser(self)
	if combat.start_death_fuse_if_needed(self):
		return
	_finish_death_visual()


## 身体核心点：反穿墙判定用，只打到探出墙外的受击盒不会结算伤害。
func body_center() -> Vector2:
	return global_position + Vector2(0.0, -_sprite_h * 0.45)


## 脚底物理核心点：CharacterBody2D 碰撞圆心，始终位于可行走地面。
func ground_center() -> Vector2:
	return global_position + Vector2(0.0, -8.0)


func hit_material() -> String:
	return def.hit_material


func hit_weight() -> float:
	return def.hit_weight()


func friendly_explosion_mul() -> float:
	return ENEMY_DEF.friendly_explosion_mul(get_node_or_null("/root/Progress"))


## --- 子系统薄转发接口 --------------------------------------------------------

func _draw() -> void:
	visual.draw_overlays(self, def, player, _explode_t, _laser_on, _laser_phase)


func _update_visual(_dist: float, delta: float) -> void:
	visual.update_visual(self, def, player, hp, hp_max, _dead, _explode_t, _charge_t, delta)


func _play_anim_override(anim_name: String, time: float) -> void:
	visual.play_anim_override(anim_name, time)


func _melee_slash(target: Vector2) -> void:
	visual.spawn_melee_slash(self, target)


func _attack_flash(color: Color) -> void:
	visual.spawn_attack_flash(self, color)


func _spawn_explosion_fx(radius_px: float) -> void:
	visual.spawn_explosion_fx(self, radius_px)


func _finish_death_visual() -> void:
	visual.finish_death_visual(self, def, _exploded, Callable(self, "_sfx"))


func can_see_player() -> bool:
	return perception.can_see_player(self, def, player, _sprite_h, _dead)


func can_see_point(point: Vector2) -> bool:
	return perception.can_see_point(self, point, _sprite_h, _dead)


func _line_of_sight() -> bool:
	return perception.line_of_sight(self, player, _sprite_h)


func _update_view_direction(delta: float) -> void:
	perception.update_view_direction(self, state, player, _last_known, _dead, delta)


func _chase_dir(target: Vector2) -> Vector2:
	return perception.chase_dir(self, nav_level, target)


func _move(dir: Vector2, speed_px: float, _delta: float) -> void:
	perception.move_dir(self, def, dir, speed_px)


func _move_toward(point: Vector2, speed_ratio: float, _delta: float, use_nav := false) -> void:
	perception.move_toward(self, def, nav_level, point, speed_ratio, use_nav)


func _move_away(from: Vector2, speed_px: float, _delta: float) -> void:
	perception.move_away(self, def, from, speed_px)


func _try_attack(dist: float) -> void:
	combat.try_attack(self, dist)


func _explode_damage() -> void:
	combat.explode_damage(self)


func _sfx(sfx_kind: String, volume_db := 0.0, pitch := 1.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play_2d(sfx_kind, volume_db, pitch)


func _shake(amount: float) -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("add_shake"):
			node.add_shake(amount)
			return
		node = node.get_parent()
