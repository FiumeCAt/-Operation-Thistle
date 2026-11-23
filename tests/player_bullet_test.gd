extends SceneTree
## PlayerBullet2D 独立解耦测试（完全不依赖 Main2D）：
## 1. 无 Main2D 宿主即可通过 PlayerBullet2D.create() 生成，零 main 反向引用。
## 2. 命中可受伤目标发射 enemy_hit + finished 信号，不触发 wall_hit。
## 3. 命中墙体发射 wall_hit + finished 信号，不触发 enemy_hit。
## 4. 注入自定义 wall_check 回调可拦截“墙后探出受击盒”，路由到 wall_hit；
##    不注入回调时也能用自身 World2D 默认 layer-1 射线拦截墙后目标。
## 5. 超程耗尽射程触发 finished 且按 exp(-drag * s) 减速；弹道线条可动态显隐。

const BULLET_SCRIPT := preload("res://scripts/fx/PlayerBullet2D.gd")

var _ok := 0
var _fails := 0


class DummyTarget extends Node2D:
	var center_offset := Vector2.ZERO
	var hits := 0

	func take_damage(_amount: float, _ap := 0.0, _impulse := Vector2.ZERO) -> float:
		hits += 1
		return _amount

	func body_center() -> Vector2:
		return global_position + center_offset


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _make_wall(parent: Node, pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	parent.add_child(wall)
	wall.global_position = pos
	return wall


func _make_target(parent: Node, pos: Vector2, hitbox_offset := Vector2.ZERO,
		hitbox_size := Vector2(36, 36)) -> DummyTarget:
	var target := DummyTarget.new()
	parent.add_child(target)
	target.global_position = pos
	var area := Area2D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hitbox_size
	shape.shape = rect
	area.add_child(shape)
	target.add_child(area)
	area.position = hitbox_offset
	return target


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(2))
	print("=== player_bullet_test ===")

	var arena := Node2D.new()
	root.add_child(arena)
	await physics_frame

	# 1) 无 Main2D 依赖：检查源码与实例不含反向引用字段
	var probe := PlayerBullet2D.new()
	_check(not ("main" in probe), "PlayerBullet2D has no main back-reference property")
	_check(probe.has_signal("enemy_hit") and probe.has_signal("wall_hit")
		and probe.has_signal("finished"),
		"PlayerBullet2D exposes enemy_hit / wall_hit / finished signals")
	probe.free()
	var invalid_null := BULLET_SCRIPT.create(arena, {"origin": Vector2.ZERO, "direction": Vector2.ZERO})
	_check(invalid_null == null, "zero-direction create() returns null safely")

	# 2) 独立命中目标：发射 enemy_hit 与 finished（通过 config 回调与信号同时验证）
	var target := _make_target(arena, Vector2(200, 0))
	await physics_frame
	await physics_frame
	var events := {"enemy": 0, "wall": 0, "done": 0, "hit_target": null, "dmg": 0.0}
	var b_enemy := BULLET_SCRIPT.create(arena, {
		"origin": Vector2(0, 0),
		"direction": Vector2.RIGHT,
		"speed_px_s": 2400.0,
		"damage": 25.0,
		"ap": 40.0,
		"max_distance": 600.0,
		"shot_ctx": {"origin": Vector2(0, 0)},
		"on_enemy_hit": func(bullet: PlayerBullet2D, hit_node: Node, _pt: Vector2, _d: Vector2) -> void:
			events["enemy"] = int(events["enemy"]) + 1
			events["hit_target"] = hit_node
			events["dmg"] = bullet.damage,
		"on_wall_hit": func(_b: PlayerBullet2D, _pt: Vector2, _d: Vector2) -> void:
			events["wall"] = int(events["wall"]) + 1,
		"on_finished": func(_b: PlayerBullet2D) -> void:
			events["done"] = int(events["done"]) + 1,
	})
	_check(b_enemy != null and b_enemy.trail_line != null, "create() spawns bullet with trail by default")
	for i in 12:
		await physics_frame
	_check(int(events["enemy"]) == 1 and int(events["wall"]) == 0 and int(events["done"]) == 1,
		"standalone target hit emits enemy_hit once + finished once (e=%d w=%d f=%d)" % [
			int(events["enemy"]), int(events["wall"]), int(events["done"])])
	_check(events["hit_target"] == target and is_equal_approx(float(events["dmg"]), 25.0),
		"enemy_hit delivers exact target and damage payload")

	# 3) 注入自定义 wall_check：模拟墙体挡住身体核心，应转为 wall_hit 而非 enemy_hit
	var injected := {"checked": 0, "enemy": 0, "wall": 0, "wall_pt": Vector2.ZERO, "done": 0}
	var b_blocked := BULLET_SCRIPT.create(arena, {
		"origin": Vector2(0, 0),
		"direction": Vector2.RIGHT,
		"speed_px_s": 2400.0,
		"damage": 25.0,
		"max_distance": 600.0,
		"shot_ctx": {"origin": Vector2(0, 0)},
		"wall_check": func(_from: Vector2, _to: Vector2) -> Dictionary:
			injected["checked"] = int(injected["checked"]) + 1
			return {"position": Vector2(120, 0)},
		"on_enemy_hit": func(_b: PlayerBullet2D, _t: Node, _p: Vector2, _d: Vector2) -> void:
			injected["enemy"] = int(injected["enemy"]) + 1,
		"on_wall_hit": func(_b: PlayerBullet2D, pt: Vector2, _d: Vector2) -> void:
			injected["wall"] = int(injected["wall"]) + 1
			injected["wall_pt"] = pt,
		"on_finished": func(_b: PlayerBullet2D) -> void:
			injected["done"] = int(injected["done"]) + 1,
	})
	_check(b_blocked != null, "bullet with injected wall_check spawned")
	for i in 12:
		await physics_frame
	_check(int(injected["checked"]) == 1 and int(injected["enemy"]) == 0
		and int(injected["wall"]) == 1 and int(injected["done"]) == 1
		and (injected["wall_pt"] as Vector2).is_equal_approx(Vector2(120, 0)),
		"injected wall_check redirects occluded hit to wall_hit at wall point")
	target.queue_free()
	await physics_frame

	# 4) 默认内置层 1 遮挡检查（不注入 wall_check，纯 World2D）：
	#    真实墙在 (100, 0)，目标核心在 (200, 0)，但受击盒探出到 (200, -60) 绕开墙
	var cover := _make_wall(arena, Vector2(100, 0), Vector2(24, 60))
	var peek_target := _make_target(arena, Vector2(200, 0), Vector2(0, -60), Vector2(36, 36))
	await physics_frame
	await physics_frame
	var built_in := {"enemy": 0, "wall": 0, "done": 0}
	var b_default := BULLET_SCRIPT.create(arena, {
		"origin": Vector2(0, -60),
		"direction": Vector2.RIGHT,
		"speed_px_s": 2400.0,
		"damage": 20.0,
		"max_distance": 600.0,
		"shot_ctx": {"origin": Vector2(0, 0)},
		"on_enemy_hit": func(_b: PlayerBullet2D, _t: Node, _p: Vector2, _d: Vector2) -> void:
			built_in["enemy"] = int(built_in["enemy"]) + 1,
		"on_wall_hit": func(_b: PlayerBullet2D, _p: Vector2, _d: Vector2) -> void:
			built_in["wall"] = int(built_in["wall"]) + 1,
		"on_finished": func(_b: PlayerBullet2D) -> void:
			built_in["done"] = int(built_in["done"]) + 1,
	})
	_check(b_default != null, "bullet using default World2D wall check spawned")
	for i in 12:
		await physics_frame
	_check(int(built_in["enemy"]) == 0 and int(built_in["wall"]) == 1 and int(built_in["done"]) == 1,
		"default layer-1 raycast blocks protruding hitbox behind wall without Main2D")
	cover.queue_free()
	peek_target.queue_free()
	await physics_frame

	# 5) 墙体直击：触发 wall_hit + finished
	var wall := _make_wall(arena, Vector2(150, 200), Vector2(24, 120))
	await physics_frame
	await physics_frame
	var wall_ev := {"enemy": 0, "wall": 0, "done": 0}
	var b_wall := BULLET_SCRIPT.create(arena, {
		"origin": Vector2(0, 200),
		"direction": Vector2.RIGHT,
		"speed_px_s": 2000.0,
		"max_distance": 500.0,
		"on_enemy_hit": func(_b: PlayerBullet2D, _t: Node, _p: Vector2, _d: Vector2) -> void:
			wall_ev["enemy"] = int(wall_ev["enemy"]) + 1,
		"on_wall_hit": func(_b: PlayerBullet2D, _p: Vector2, _d: Vector2) -> void:
			wall_ev["wall"] = int(wall_ev["wall"]) + 1,
		"on_finished": func(_b: PlayerBullet2D) -> void:
			wall_ev["done"] = int(wall_ev["done"]) + 1,
	})
	_check(b_wall != null, "wall-impact test bullet spawned")
	for i in 12:
		await physics_frame
	_check(int(wall_ev["enemy"]) == 0 and int(wall_ev["wall"]) == 1 and int(wall_ev["done"]) == 1,
		"direct wall impact emits wall_hit + finished")
	wall.queue_free()
	await physics_frame

	# 6) 阻力衰减、关闭/重开弹道线条、超程自动结束
	var range_ev := {"enemy": 0, "wall": 0, "done": 0}
	var b_range := BULLET_SCRIPT.create(arena, {
		"origin": Vector2(0, 500),
		"direction": Vector2.RIGHT,
		"speed_px_s": 600.0,
		"drag_per_px": 0.002,
		"max_distance": 180.0,
		"trail_enabled": false,
		"on_enemy_hit": func(_b: PlayerBullet2D, _t: Node, _p: Vector2, _d: Vector2) -> void:
			range_ev["enemy"] = int(range_ev["enemy"]) + 1,
		"on_wall_hit": func(_b: PlayerBullet2D, _p: Vector2, _d: Vector2) -> void:
			range_ev["wall"] = int(range_ev["wall"]) + 1,
		"on_finished": func(_b: PlayerBullet2D) -> void:
			range_ev["done"] = int(range_ev["done"]) + 1,
	})
	_check(b_range != null and b_range.trail_line == null and b_range.visible,
		"trail_enabled=false keeps bullet visible without creating trail_line")
	await physics_frame
	await physics_frame
	_check(b_range.velocity.length() < 600.0 and b_range.travelled > 0.0,
		"drag_per_px decelerates bullet velocity in flight (v=%.1f)" % b_range.velocity.length())
	b_range.set_trail_visible(true)
	_check(b_range.trail_line != null and b_range.trail_line.visible,
		"set_trail_visible(true) dynamically attaches trail_line mid-flight")
	for i in 30:
		await physics_frame
	_check(int(range_ev["enemy"]) == 0 and int(range_ev["wall"]) == 0 and int(range_ev["done"]) == 1,
		"max_distance expiry emits finished only without hit signals")

	arena.queue_free()
	await process_frame
	print("=== player_bullet_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
