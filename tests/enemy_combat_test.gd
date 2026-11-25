extends SceneTree
## EnemyCombat2D 独立单元测试：验证炮塔激光锁定状态、歌利亚按伤害比例缩引信与 200% 瞬爆、双发连射与状态复位。
## godot --headless --path . --script res://tests/enemy_combat_test.gd

const ENEMY_DEF := preload("res://scripts/actors/enemy/EnemyDef.gd")
const COMBAT := preload("res://scripts/actors/enemy/EnemyCombat2D.gd")

var _pass := 0
var _fail := 0


class StubPlayer extends Node2D:
	var damage_taken := 0.0
	var last_ap := 0.0

	func take_damage(amount: float, ap: float = 0.0) -> void:
		damage_taken += amount
		last_ap = ap


class StubEnemy extends CharacterBody2D:
	var def: EnemyDef
	var hp := 60.0
	var hp_max := 60.0
	var damage_mul := 1.0
	var state := "patrol"
	var always_hunt := false
	var player: Node2D = null
	var _dead := false
	var _state_t := 0.0
	var _lost_t := 0.0
	var _last_known := Vector2.ZERO
	var _anim = null
	var _sprite_h := 80.0
	var entered_states: Array[String] = []
	var sfx_calls: Array[String] = []
	var die_calls := 0
	var explode_fx_calls := 0
	var last_shake := 0.0

	func _enter(s: String) -> void:
		state = s
		entered_states.append(s)

	func _sfx(k: String, _v := 0.0, _p := 1.0) -> void:
		sfx_calls.append(k)

	func _shake(a: float) -> void:
		last_shake = a

	func _play_anim_override(_a: String, _t: float) -> void:
		pass

	func _attack_flash(_c: Color) -> void:
		pass

	func _melee_slash(_t: Vector2) -> void:
		pass

	func _line_of_sight() -> bool:
		return true

	func _move(_d: Vector2, _s: float, _dt: float) -> void:
		pass

	func _chase_dir(_t: Vector2) -> Vector2:
		return Vector2.RIGHT

	func _spawn_explosion_fx(_r: float) -> void:
		explode_fx_calls += 1

	func _die() -> void:
		die_calls += 1
		_dead = true

	func _finish_death_visual() -> void:
		pass

	func _update_visual(_d: float, _dt: float) -> void:
		pass

	func friendly_explosion_mul() -> float:
		return 0.8


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _run() -> void:
	var dummy_player := StubPlayer.new()
	root.add_child(dummy_player)
	dummy_player.global_position = Vector2(200, 0)

	# 1. 移动哨戒炮：进战开启 0.75s 激光锁定，读秒完成后进入开火双发队列
	var turret_host := StubEnemy.new()
	turret_host.def = ENEMY_DEF.from_dict(&"mobile_turret", EnemyDB.stats(&"mobile_turret"))
	turret_host.player = dummy_player
	root.add_child(turret_host)

	var turret_combat: EnemyCombat2D = COMBAT.new()
	turret_combat.on_state_entered(turret_host, "combat", "patrol")
	_check(turret_combat.laser_on and not turret_combat.turret_locked
		and is_equal_approx(turret_combat.turret_lock_t, 0.75)
		and turret_host.sfx_calls.has("turret_lock"),
		"turret combat entry arms 0.75s laser lock and sound")

	turret_combat.do_combat(turret_host, Vector2(200, 0), 200.0, true, 0.4)
	_check(not turret_combat.turret_locked and turret_combat.laser_on,
		"turret stays locked-in-progress before 0.75s elapses")

	turret_combat.do_combat(turret_host, Vector2(200, 0), 200.0, true, 0.4)
	_check(turret_combat.turret_locked and turret_combat.burst_left == 2 and turret_combat.laser_on,
		"turret completes lock and queues 2-round burst while keeping laser")

	turret_combat.on_state_entered(turret_host, "search", "combat")
	_check(not turret_combat.laser_on and not turret_combat.turret_locked,
		"leaving combat clears turret laser and lock state")

	# 2. 歌利亚：未坐地受致命伤（< 200% 血量上限）锁血 1 点并点引信；
	#    自爆期间每造成 1% 血量上限伤害减少 1% 总自爆时间，归零立刻引爆。
	var goliath_host := StubEnemy.new()
	goliath_host.def = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	goliath_host.player = dummy_player
	goliath_host.hp_max = 100.0
	goliath_host.hp = -20.0
	root.add_child(goliath_host)

	var goliath_combat: EnemyCombat2D = COMBAT.new()
	goliath_combat.on_self_destruct_damaged(goliath_host, 120.0)
	var base_delay: float = goliath_host.def.explode_delay
	_check(is_equal_approx(goliath_host.hp, 1.0)
		and is_equal_approx(goliath_combat.explode_t, base_delay)
		and not goliath_combat.exploded,
		"goliath fatal damage below 200 percent hp_max clamps hp to 1 and ignites fuse")

	goliath_host.hp -= 37.0
	goliath_combat.on_self_destruct_damaged(goliath_host, 37.0)
	_check(is_equal_approx(goliath_combat.explode_t, base_delay * 0.63)
		and is_equal_approx(goliath_host.hp, 1.0) and not goliath_combat.exploded,
		"37 percent hp_max damage during fuse shortens fuse time by 37 percent")

	goliath_host.hp -= 63.0
	goliath_combat.on_self_destruct_damaged(goliath_host, 63.0)
	_check(goliath_combat.exploded and goliath_host.die_calls == 1
		and goliath_host.explode_fx_calls == 1 and dummy_player.damage_taken > 0.0
		and goliath_host.hp <= 0.0,
		"cumulative 100 percent hp_max fuse damage detonates immediately")

	# 3. 歌利亚：倒计时自然归零同样触发爆炸与死亡
	var tick_host := StubEnemy.new()
	tick_host.def = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	tick_host.player = dummy_player
	tick_host.hp_max = 100.0
	tick_host.hp = -10.0
	root.add_child(tick_host)
	var tick_combat: EnemyCombat2D = COMBAT.new()
	tick_combat.on_self_destruct_damaged(tick_host, 110.0)
	var dmg_before_tick := dummy_player.damage_taken
	tick_combat.explode_t = 0.05
	tick_combat.tick_self_destruct(tick_host, 0.1)
	_check(tick_combat.exploded and tick_host.die_calls == 1
		and tick_host.explode_fx_calls == 1 and dummy_player.damage_taken > dmg_before_tick,
		"fuse expiry triggers explosion, player blast damage, FX, and death in one step")

	# 4. 歌利亚：进入坐地自爆前单次受 >= 200% 血量上限伤害直接瞬间自爆，不坐地不倒计时
	var instant_host := StubEnemy.new()
	instant_host.def = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	instant_host.player = dummy_player
	instant_host.hp_max = 100.0
	instant_host.hp = -100.0
	root.add_child(instant_host)
	var instant_combat: EnemyCombat2D = COMBAT.new()
	var dmg_before_instant := dummy_player.damage_taken
	instant_combat.on_self_destruct_damaged(instant_host, 200.0)
	_check(instant_combat.exploded and instant_host.die_calls == 1
		and instant_combat.explode_t < 0.0
		and not instant_host.sfx_calls.has("fuse_long")
		and instant_host.sfx_calls.has("boom")
		and dummy_player.damage_taken > dmg_before_instant,
		"200 percent hp_max damage before sit-down triggers instant detonation without fuse")

	# 5. 歌利亚：进入坐地前单次受 199% 血量上限伤害仍进入坐地倒计时
	var near_host := StubEnemy.new()
	near_host.def = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	near_host.player = dummy_player
	near_host.hp_max = 100.0
	near_host.hp = -99.0
	root.add_child(near_host)
	var near_combat: EnemyCombat2D = COMBAT.new()
	near_combat.on_self_destruct_damaged(near_host, 199.0)
	_check(not near_combat.exploded and is_equal_approx(near_host.hp, 1.0)
		and is_equal_approx(near_combat.explode_t, base_delay),
		"199 percent hp_max damage before sit-down still enters sit-down fuse")

	# 6. 爆炸屏幕震动距离衰减：近处适当减弱（<=4.5），中远距离逐步衰减，极远处为 0
	var r_px := 3.0 * COMBAT.TILE
	var s_close := COMBAT.calc_explosion_shake(0.5 * COMBAT.TILE, r_px)
	var s_mid := COMBAT.calc_explosion_shake(11.0 * COMBAT.TILE, r_px)
	var s_far := COMBAT.calc_explosion_shake(20.0 * COMBAT.TILE, r_px)
	var s_zero := COMBAT.calc_explosion_shake(28.0 * COMBAT.TILE, r_px)
	_check(s_close > 3.5 and s_close <= 4.5,
		"close explosion shake appropriately softened (%.2f)" % s_close)
	_check(s_mid > 0.8 and s_mid < s_close * 0.5,
		"mid-range explosion shake attenuated smoothly (%.2f)" % s_mid)
	_check(s_far > 0.0 and s_far < s_mid * 0.6 and is_zero_approx(s_zero),
		"far explosion shake tapers to zero beyond 26m (%.2f -> %.2f)" % [s_far, s_zero])
	_check(instant_host.last_shake > 0.0 and instant_host.last_shake < 4.5,
		"runtime explosion passes distance-attenuated shake (%.2f)" % instant_host.last_shake)

	turret_host.queue_free()
	goliath_host.queue_free()
	tick_host.queue_free()
	instant_host.queue_free()
	near_host.queue_free()
	dummy_player.queue_free()
	await process_frame
	print("\n=== enemy combat: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
