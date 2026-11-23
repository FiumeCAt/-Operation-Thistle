extends SceneTree
## CombatSystem2D 独立单元测试（完全不依赖 Main2D）：
## 1. 后坐力倍率随 ADS 过渡（1.0 -> RECOIL_ADS_MUL）与每帧回落。
## 2. 连发散布累积（add_burst_spread）与多弹丸命中分桶聚合（flush_shot_buckets）。
## 3. 命中反馈统计（shots_hit、damage_dealt、hit_resolved 信号、震屏/顿帧回调）。

const COMBAT := preload("res://scripts/systems/CombatSystem2D.gd")

var _ok := 0
var _fails := 0


class DummyEnemy extends Node2D:
	var hp := 100.0
	var calls := 0
	var last_amount := 0.0

	func take_damage(amount: float, _ap := 0.0, _impulse := Vector2.ZERO) -> float:
		calls += 1
		last_amount = amount
		hp = maxf(hp - amount, 0.0)
		return amount

	func hit_material() -> String:
		return "flesh"

	func hit_weight() -> float:
		return 1.0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	print("=== combat_system_test ===")

	var state := {"active": true, "ads_t": 0.0, "shakes": 0, "hitstops": 0}
	var resolved: Array = []
	var cs := COMBAT.new()
	var host := Node2D.new()
	root.add_child(host)
	await process_frame
	var enemies: Array[Enemy2D] = []
	cs.setup(host, null, null, null, enemies,
		func() -> bool: return bool(state["active"]),
		func() -> float: return float(state["ads_t"]),
		func() -> float: return 1.0,
		func() -> bool: return true,
		func() -> int: return 1,
		Callable(),
		func(_a: float, _r: float, _d: float) -> void: state["shakes"] = int(state["shakes"]) + 1,
		func(_s: float) -> void: state["hitstops"] = int(state["hitstops"]) + 1,
		Callable())
	cs.hit_resolved.connect(func(t: Node, dmg: float, killed: bool, mat: String) -> void:
		resolved.append([t, dmg, killed, mat])
	)

	# 1) 后坐力强度与回落
	_check(is_equal_approx(cs.recoil_strength(), 1.0), "hip recoil_strength == 1.0")
	state["ads_t"] = 1.0
	_check(is_equal_approx(cs.recoil_strength(), COMBAT.RECOIL_ADS_MUL),
		"ADS recoil_strength == RECOIL_ADS_MUL")
	cs.recoil_offset = Vector2(10.0, -20.0)
	cs.recoil_cam = Vector2(5.0, -10.0)
	cs.recoil_roll = 0.02
	cs.update(0.1)
	_check(cs.shot_clock > 0.09 and cs.recoil_offset.length() < Vector2(10.0, -20.0).length()
		and cs.recoil_cam.length() < Vector2(5.0, -10.0).length()
		and cs.recoil_roll < 0.02,
		"update() advances shot_clock and recovers recoil offset / cam / roll")

	# 2) 连发散布累积
	var akm: WeaponData = WeaponDB.get_weapon(&"akm")
	cs.add_burst_spread(akm)
	_check(cs.burst_spread > 0.0 and cs.burst_weapon == &"akm",
		"add_burst_spread accumulates spread and tags burst_weapon")

	# 3) 多弹丸分桶聚合：3 颗弹丸命中同一目标只调用一次 take_damage（总伤 24），且触发 1 次 hit_resolved
	var enemy := DummyEnemy.new()
	host.add_child(enemy)
	var ctx := {
		"data": akm, "ap": 10.0, "knockback": 0.0, "multi": true, "pending": 3,
		"origin": Vector2.ZERO, "buckets": {}, "fx_targets": {},
		"first_hit": false, "first_kill": false, "wall_fx": 0, "flush_scheduled": false,
	}
	var fake_bullet := {"shot_ctx": ctx, "damage": 8.0}
	cs.on_bullet_hit_enemy(fake_bullet, enemy, Vector2(50, 0), Vector2.RIGHT)
	cs.on_bullet_hit_enemy(fake_bullet, enemy, Vector2(52, 0), Vector2.RIGHT)
	cs.on_bullet_hit_enemy(fake_bullet, enemy, Vector2(54, 0), Vector2.RIGHT)
	_check(enemy.calls == 0, "multi-pellet hits wait in bucket before flush")
	cs.flush_shot_buckets(ctx)
	_check(enemy.calls == 1 and is_equal_approx(enemy.last_amount, 24.0),
		"flush_shot_buckets merges 3 pellets into one take_damage(24.0)")
	_check(cs.shots_hit == 1 and is_equal_approx(cs.damage_dealt, 24.0)
		and resolved.size() == 1 and String(resolved[0][3]) == "flesh" and not bool(resolved[0][2]),
		"hit batch updates shots_hit/damage_dealt and emits hit_resolved")
	_check(int(state["shakes"]) == 1 and int(state["hitstops"]) == 1,
		"hit batch invokes shake and hitstop feedback once per shot")

	# 4) 击杀判定触发 killed=true 与额外击杀反馈
	cs.apply_hit_batch(ctx, enemy, 80.0, Vector2(54, 0), Vector2.RIGHT)
	_check(enemy.hp <= 0.0 and resolved.size() == 2 and bool(resolved[1][2])
		and int(state["shakes"]) == 2 and int(state["hitstops"]) == 2,
		"lethal hit marks killed=true and triggers kill shake/hitstop")

	host.queue_free()
	await process_frame
	print("=== combat_system_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
