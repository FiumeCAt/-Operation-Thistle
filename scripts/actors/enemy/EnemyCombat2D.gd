extends RefCounted
class_name EnemyCombat2D
## 2D 敌人战斗策略与攻击结算子系统：
## 统一封装常规远程/近战、冲锋（哨兵一型）、双发锁定激光炮塔（移动哨戒炮）、
## 以及自爆/残血锁血引信（歌利亚通用一型）5 类战斗状态机。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
const LOST_SIGHT := 7.0

var attack_cd := 0.0
var burst_left := 0
var burst_t := 0.0
var charge_t := 0.0
var charge_dir := Vector2.ZERO
var charge_cd := 0.0
var explode_t := -1.0
var exploded := false
var turret_lock_t := 0.0
var turret_locked := false
var laser_on := false
var laser_phase := 0.0


func tick_cooldowns(host, delta: float) -> void:
	attack_cd = maxf(attack_cd - delta, 0.0)
	charge_cd = maxf(charge_cd - delta, 0.0)
	process_burst(host, delta)
	if laser_on:
		laser_phase += delta
		host.queue_redraw()
	if explode_t >= 0.0:
		host.queue_redraw()


func on_state_entered(host, new_state: String, old_state: String) -> void:
	if new_state == "combat" and old_state != "combat":
		if host.def.behavior == "turret":
			turret_locked = false
			turret_lock_t = 0.75
			laser_on = true
			laser_phase = 0.0
			host._sfx("turret_lock", -7.0)
	else:
		clear_laser(host)


func clear_laser(host) -> void:
	laser_on = false
	turret_lock_t = 0.0
	turret_locked = false
	host.queue_redraw()


## 战斗主分发：按 EnemyDef.behavior 路由到对应策略。
func do_combat(host, to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	match host.def.behavior:
		"charger":
			_do_charger(host, to_target, dist, can_see, delta)
		"suicide":
			_do_suicide(host, to_target, dist, can_see, delta)
		"turret":
			_do_turret(host, to_target, dist, can_see, delta)
		_:
			_do_standard(host, to_target, dist, can_see, delta)


func _do_standard(host, to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	var def: EnemyDef = host.def
	var speed_px := def.speed * TILE
	var range_px := def.attack_range * TILE
	var dir := to_target.normalized()
	if def.melee:
		if dist > range_px * 0.9:
			host._move(host._chase_dir(host.player.global_position), speed_px, delta)
		else:
			host.velocity = Vector2.ZERO
		try_attack(host, dist)
	else:
		var desired := range_px * 0.75
		# 浪潮永久追踪：看不见玩家时不保持交战距离，持续朝玩家方向压过去。
		if host.always_hunt and not can_see:
			desired = 0.0
		if dist > desired * 1.2:
			host._move(host._chase_dir(host.player.global_position), speed_px, delta)
		elif dist < desired * 0.65:
			host._move(-dir, speed_px, delta)
		elif def.strafe:
			host._move(dir.orthogonal() * (1.0 if fmod(host._state_t, 2.0) > 1.0 else -1.0), speed_px * 0.55, delta)
		else:
			host.velocity = Vector2.ZERO
		if can_see:
			try_attack(host, dist)

	_update_sight_memory(host, can_see, delta)
	if host.hp <= host.hp_max * 0.25 and def.flees:
		host._enter("flee")


## 移动哨卫炮：一次攻击分两发，按 burst_interval 间隔出膛。
func process_burst(host, delta: float) -> void:
	if burst_left <= 0:
		return
	burst_t -= delta
	if burst_t > 0.0:
		return
	if host.player == null or not is_instance_valid(host.player):
		burst_left = 0
		return
	fire_round(host)
	burst_left -= 1
	burst_t = host.def.burst_interval


## 哨兵一型：发现后先蓄力，再直线冲撞；撞到玩家造成伤害并进入冷却。
func _do_charger(host, to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	var def: EnemyDef = host.def
	var speed_px := def.speed * TILE
	var range_px := def.attack_range * TILE
	var dir := to_target.normalized()
	if charge_t > 0.0:
		charge_t = maxf(charge_t - delta, 0.0)
		host.velocity = charge_dir * def.charge_speed * TILE
		host.move_and_slide()
		host._play_anim_override("attack", 0.2)
		if dist < range_px * 1.5:
			charge_t = 0.0
			charge_cd = def.charge_cooldown
			attack_cd = def.cooldown
			host._attack_flash(Color(0.45, 1.0, 0.55))
			host._sfx("ram", -4.0, randf_range(0.95, 1.05))
			host._shake(5.0)
			if host.player != null and is_instance_valid(host.player):
				host.player.take_damage(def.damage * host.damage_mul, def.attack_ap())
				Shot2D.hit_burst(host.get_parent(), host.player.global_position + Vector2(0, -60),
					(host.player.global_position - host.global_position).normalized(), "flesh", 0.7)
		return
	if can_see and dist > range_px * 1.8 and charge_cd <= 0.0 and host._line_of_sight():
		charge_dir = dir
		charge_t = 0.8
		host._sfx("charge_up", -9.0, randf_range(0.95, 1.05))
		host._play_anim_override("alert", 0.35)
	else:
		if dist > range_px * 0.9:
			host._move(host._chase_dir(host.player.global_position), speed_px, delta)
		else:
			host.velocity = Vector2.ZERO
		try_attack(host, dist)
	_update_sight_memory(host, can_see, delta)


## 哥利亚：贴近玩家后坐地，引信结束后自爆并同时死亡。
func _do_suicide(host, _to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	var def: EnemyDef = host.def
	var range_px := def.attack_range * TILE
	if explode_t >= 0.0:
		tick_self_destruct(host, delta)
		return
	if dist > range_px:
		host._move(host._chase_dir(host.player.global_position), def.speed * TILE, delta)
	else:
		begin_self_destruct(host)
		host._play_anim_override("attack", 0.6)
	_update_sight_memory(host, can_see, delta)


## 移动哨卫炮：发现后先用红色激光锁定，锁定和开火期间原地不动；只有丢失目标才恢复搜索/巡逻。
func _do_turret(host, _to_target: Vector2, dist: float, can_see: bool, delta: float) -> void:
	host.velocity = Vector2.ZERO
	if not can_see:
		clear_laser(host)
		host._lost_t += delta
		if host._lost_t > LOST_SIGHT and not host.always_hunt:
			host._enter("search")
		return
	host._lost_t = 0.0
	host._last_known = host.player.global_position
	if not turret_locked:
		turret_lock_t = maxf(turret_lock_t - delta, 0.0)
		laser_on = true
		host.queue_redraw()
		host._play_anim_override("alert", 0.2)
		if turret_lock_t <= 0.0:
			turret_locked = true
			attack_cd = 0.0
			try_attack(host, dist)
		return
	# 锁定完成后激光继续保留，作为持续瞄准提示。
	laser_on = true
	host.queue_redraw()
	try_attack(host, dist)


func _update_sight_memory(host, can_see: bool, delta: float) -> void:
	if can_see:
		host._lost_t = 0.0
		host._last_known = host.player.global_position
	else:
		host._lost_t += delta
		if host._lost_t > LOST_SIGHT and not host.always_hunt:
			host._enter("search")


func try_attack(host, dist: float) -> void:
	if attack_cd > 0.0 or not host._line_of_sight():
		return
	var def: EnemyDef = host.def
	var range_px := def.attack_range * TILE
	if def.melee:
		if dist <= range_px * 1.1:
			attack_cd = def.cooldown
			host._attack_flash(Color(0.92, 0.32, 0.24))
			host._play_anim_override("attack", 0.35)
			if def.behavior == "melee":
				host._sfx("stab", -7.0, randf_range(0.95, 1.05))
			host._melee_slash(host.player.global_position)
			host.player.take_damage(def.damage * host.damage_mul, def.attack_ap())
			Shot2D.hit_burst(host.get_parent(), host.player.global_position + Vector2(0, -60),
				(host.player.global_position - host.global_position).normalized(), "flesh", 0.7)
	else:
		if dist <= range_px * 1.25:
			attack_cd = def.cooldown
			host._attack_flash(Color(1.0, 0.78, 0.36))
			host._play_anim_override("attack", 0.4)
			var burst := def.burst
			if burst > 1:
				burst_left = burst
				burst_t = 0.0
			else:
				fire_round(host)


## 远程攻击表现：枪口闪光后发射可见子弹，命中时在玩家身上溅火花。
func fire_round(host) -> void:
	if host.player == null or not is_instance_valid(host.player):
		return
	if host._anim != null:
		host._sfx("turret_shot", -6.0, randf_range(0.93, 1.03))
	var muzzle: Vector2 = host.global_position + Vector2(0, -host._sprite_h * 0.55)
	var target: Vector2 = host.player.global_position + Vector2(0, -46)
	var dir := (target - muzzle).normalized()
	var parent: Node = host.get_parent()
	if parent != null:
		EnemyBullet2D.spawn(parent, muzzle + dir * 12.0, target,
			host.def.damage * host.damage_mul, host.def.attack_ap())


## 进入自爆状态：停止移动、坐地并启动引信；重复调用只保留第一次的引信。
func begin_self_destruct(host) -> void:
	if host._dead or explode_t >= 0.0:
		return
	explode_t = maxf(host.def.explode_delay, 0.01)
	host.velocity = Vector2.ZERO
	host._play_anim_override("attack", 0.2)
	host._sfx("fuse_long", -8.0)
	if host.state != "combat":
		host._enter("combat")
	host.queue_redraw()


const INSTANT_EXPLODE_HP_RATIO := 2.0


## 自爆单位受击逻辑：
##   - 进入坐地自爆前，若单次有效伤害 >= 200% 自身血量上限，跳过坐地与倒计时直接瞬间自爆；
##   - 否则血量跌至 <= 1 时锁血 1 点并进入坐地自爆倒计时；
##   - 进入自爆状态后，每造成 1% 血量上限的伤害就减少 1% 总自爆时间，归零时立即引爆。
func on_self_destruct_damaged(host, dmg: float = 0.0) -> void:
	if host._dead or exploded:
		return
	var max_hp := maxf(float(host.hp_max), 1.0)
	var hit_dmg := maxf(dmg, 0.0)
	if explode_t >= 0.0:
		var base_delay := maxf(float(host.def.explode_delay), 0.01)
		explode_t = maxf(explode_t - base_delay * (hit_dmg / max_hp), 0.0)
		if explode_t <= 0.0:
			explode_t = -1.0
			host.hp = minf(float(host.hp), 0.0)
			explode(host)
			return
		if host.hp <= 1.0:
			host.hp = 1.0
		return
	if hit_dmg >= max_hp * INSTANT_EXPLODE_HP_RATIO:
		explode_t = -1.0
		explode(host)
		return
	if host.hp <= 1.0:
		host.hp = 1.0
		begin_self_destruct(host)


## 自爆引信倒计时：归零时爆炸并死亡，两个事件在同一帧结算。
func tick_self_destruct(host, delta: float) -> void:
	if explode_t < 0.0:
		return
	explode_t -= delta
	host.velocity = Vector2.ZERO
	host._play_anim_override("attack", 0.2)
	host.queue_redraw()
	if explode_t <= 0.0:
		# 先清空引信，确保爆炸→死亡的同一帧不会再次触发死亡引信结算。
		explode_t = -1.0
		explode(host)


## 死亡入口检查：哥利亚被直接击杀也要先走完引信，返回 true 表示推迟死亡表现。
func start_death_fuse_if_needed(host) -> bool:
	if host.def.death_explode and not exploded:
		if explode_t < 0.0:
			explode_t = host.def.explode_delay
			host._sfx("fuse_long", -8.0)
		host._play_anim_override("attack", 0.2)
		return true
	return false


## 死亡后的引信倒计时：仍然绘制红圈，读秒结束后爆炸并收尾。
func tick_death_fuse(host, delta: float) -> void:
	if explode_t < 0.0 or exploded:
		return
	explode_t -= delta
	host.queue_redraw()
	host._update_visual(0.0, delta)
	if explode_t > 0.0:
		return
	explode_t = -1.0
	exploded = true
	explode_damage(host)
	host._finish_death_visual()


func explode(host) -> void:
	if exploded:
		return
	exploded = true
	explode_damage(host)
	host._die()


const EXPLOSION_SHAKE_CLOSE := 4.4
const EXPLOSION_SHAKE_EDGE := 3.8
const EXPLOSION_SHAKE_MID := 1.35
const EXPLOSION_SHAKE_MID_DIST := 11.0 * TILE
const EXPLOSION_SHAKE_MAX_DIST := 26.0 * TILE


## 按爆炸点与玩家距离计算衰减后的震屏幅度：
## 近处（爆心~爆圈）适当减弱至 4.4→3.8（旧版恒定 8.0），中远距离平滑衰减，26m 外不再产生无谓抖动。
static func calc_explosion_shake(dist_px: float, radius_px: float) -> float:
	var d := maxf(dist_px, 0.0)
	var r := maxf(radius_px, TILE)
	if d <= r:
		return lerpf(EXPLOSION_SHAKE_CLOSE, EXPLOSION_SHAKE_EDGE, d / r)
	if d <= EXPLOSION_SHAKE_MID_DIST:
		var t := clampf((d - r) / maxf(EXPLOSION_SHAKE_MID_DIST - r, 1.0), 0.0, 1.0)
		return lerpf(EXPLOSION_SHAKE_EDGE, EXPLOSION_SHAKE_MID, pow(t, 0.85))
	if d < EXPLOSION_SHAKE_MAX_DIST:
		var t := clampf((d - EXPLOSION_SHAKE_MID_DIST)
			/ maxf(EXPLOSION_SHAKE_MAX_DIST - EXPLOSION_SHAKE_MID_DIST, 1.0), 0.0, 1.0)
		return lerpf(EXPLOSION_SHAKE_MID, 0.0, pow(t, 1.15))
	return 0.0


## 爆炸伤害对玩家和附近敌人同时生效（哥利亚的死亡爆炸也走这里）。
func explode_damage(host) -> void:
	var def: EnemyDef = host.def
	var radius_px := def.explode_radius * TILE
	var dmg: float = def.explode_damage * float(host.damage_mul)
	host._sfx("boom", -3.0, randf_range(0.94, 1.02))
	var dist_to_player := 0.0
	if host.player != null and is_instance_valid(host.player):
		dist_to_player = host.player.global_position.distance_to(host.global_position)
	var shake_amt := calc_explosion_shake(dist_to_player, radius_px)
	if shake_amt > 0.01:
		host._shake(shake_amt)
	if host.player != null and is_instance_valid(host.player) \
			and host.player.global_position.distance_to(host.global_position) <= radius_px:
		host.player.take_damage(dmg, 45.0)
	var friendly_mul: float = host.friendly_explosion_mul()
	# 竞技场内友军爆炸按目标护甲等穿结算，不做余穿放大也不减伤，确保 50% 就是实打实的半伤，
	# 满血歌利亚不会因为一次连锁立刻被带走。
	for other in host.get_tree().get_nodes_in_group("enemies"):
		if other == host or not other.has_method("take_damage") or other.get("def") == null:
			continue
		if float(other.hp) <= 0.0:
			continue
		if other.global_position.distance_to(host.global_position) <= radius_px:
			var other_armor: float = other.def.armor
			var friendly_ap: float = other_armor if friendly_mul <= 0.5 else 60.0
			other.take_damage(dmg * friendly_mul, friendly_ap)
	host._spawn_explosion_fx(radius_px)
