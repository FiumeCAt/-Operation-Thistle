extends SceneTree
## EnemyCombat2D 独立单元测试：验证炮塔激光锁定状态、歌利亚受击锁血与 20% 缩引信、双发连射与状态复位。
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

	func _enter(s: String) -> void:
		state = s
		entered_states.append(s)

	func _sfx(k: String, _v := 0.0, _p := 1.0) -> void:
		sfx_calls.append(k)

	func _shake(_a: float) -> void:
		pass

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

	# 2. 歌利亚：受致命伤锁血 1 点并点引信，再次受击缩短 20% 引信，归零后爆炸并触发死亡
	var goliath_host := StubEnemy.new()
	goliath_host.def = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	goliath_host.player = dummy_player
	goliath_host.hp = -50.0
	root.add_child(goliath_host)

	var goliath_combat: EnemyCombat2D = COMBAT.new()
	goliath_combat.on_self_destruct_damaged(goliath_host)
	_check(is_equal_approx(goliath_host.hp, 1.0)
		and is_equal_approx(goliath_combat.explode_t, goliath_host.def.explode_delay)
		and not goliath_combat.exploded,
		"goliath fatal damage clamps hp to 1 and ignites fuse")

	var before_fuse := goliath_combat.explode_t
	goliath_combat.on_self_destruct_damaged(goliath_host)
	_check(is_equal_approx(goliath_combat.explode_t, before_fuse * 0.8),
		"subsequent hits shorten active fuse by 20 percent")

	goliath_combat.explode_t = 0.05
	goliath_combat.tick_self_destruct(goliath_host, 0.1)
	_check(goliath_combat.exploded and goliath_host.die_calls == 1
		and goliath_host.explode_fx_calls == 1 and dummy_player.damage_taken > 0.0,
		"fuse expiry triggers explosion, player blast damage, FX, and death in one step")

	turret_host.queue_free()
	goliath_host.queue_free()
	dummy_player.queue_free()
	await process_frame
	print("\n=== enemy combat: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
