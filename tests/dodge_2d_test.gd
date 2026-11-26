extends SceneTree
## Phase 5 翻滚与战术躲闪回归测试：
## 1) 输入绑定 `dodge` (Space) + DollConfig 参数 + 速度曲线积分与单调减速；
## 2) 位移距离、信号、残影/扬尘占位特效与翻滚音效；
## 3) 短无敌帧（免疫受击 + 敌方子弹直接掠过不引爆），无敌结束回归正常受击；
## 4) 严格 move_and_slide() 防穿墙 + 临时忽略敌人碰撞防围死卡角；
## 5) 翻滚中禁开火/退 ADS、冷却计时与 HUD DodgeIndicator2D 同步、Phase 7 `dodge_*` 正式动画挂口。
## godot --headless --path . --script res://tests/dodge_2d_test.gd

const DOLL_SCENE := preload("res://scenes/actors/Doll2D.tscn")
const MAIN_SCENE := preload("res://scenes/core/Main2D.tscn")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _step_physics(frames: int) -> void:
	for _i in frames:
		await physics_frame


func _count_meta(node: Node, meta_key: String) -> int:
	var n := 0
	for child in node.get_children():
		if child.has_meta(meta_key):
			n += 1
	return n


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()

	# 1. 输入映射与速度曲线数学契约
	_check(InputMap.has_action("dodge"), "project registers dodge input action")
	var has_space := false
	for ev in InputMap.action_get_events("dodge"):
		if ev is InputEventKey and ev.physical_keycode == KEY_SPACE:
			has_space = true
	_check(has_space, "dodge action binds Space key")

	var f0 := Doll2D.dodge_speed_factor(0.0)
	var f5 := Doll2D.dodge_speed_factor(0.5)
	var f1 := Doll2D.dodge_speed_factor(1.0)
	var integral := 0.0
	const SAMPLES := 100
	for i in SAMPLES:
		integral += Doll2D.dodge_speed_factor((float(i) + 0.5) / float(SAMPLES)) / float(SAMPLES)
	_check(f0 > f5 and f5 > f1 and f1 > 0.0 and absf(integral - 1.0) < 0.01,
		"dodge speed curve decelerates monotonically with unit integral (%.3f)" % integral)

	# 2. 独立舞台测试：开阔位移、信号、残影/扬尘、无敌帧、穿敌、防穿墙、Phase 7 动画挂口
	var stage := Node2D.new()
	root.add_child(stage)
	var doll: Doll2D = DOLL_SCENE.instantiate()
	doll.bounds = Rect2(0, 0, 2000, 1200)
	doll.global_position = Vector2(300, 400)
	stage.add_child(doll)
	await physics_frame

	_check(doll.config != null and "dodge_distance_m" in doll.config
		and is_equal_approx(float(doll.config.get("dodge_distance_m")), 2.6),
		"DollConfig exposes tunable dodge parameters")

	var started_dirs: Array[Vector2] = []
	var ended_count := [0]
	doll.dodge_started.connect(func(d: Vector2) -> void: started_dirs.append(d))
	doll.dodge_ended.connect(func() -> void: ended_count[0] += 1)

	var sfx := root.get_node_or_null("Sfx")
	var sfx_before := sfx.get_child_count() if sfx != null else 0
	var start_pos := doll.global_position
	_check(doll.try_dodge(Vector2.RIGHT), "try_dodge succeeds when ready")
	_check(doll.is_dodging() and doll.is_dodge_invuln() and not doll.can_dodge(),
		"dodge enters active + i-frame state and locks re-trigger")
	_check(not doll.try_dodge(Vector2.LEFT), "second dodge is blocked while dodging/on cooldown")
	_check(started_dirs.size() == 1 and started_dirs[0].is_equal_approx(Vector2.RIGHT),
		"dodge_started signal emits normalized dodge direction")
	_check((doll.collision_layer & 2) == 0 and (doll.collision_mask & 1) == 1,
		"dodge removes actor collision layer 2 while keeping wall mask layer 1")
	_check(_count_meta(stage, "dodge_dust_fx") >= 1 and _count_meta(stage, "dodge_afterimage_fx") >= 1,
		"dodge spawns launch dust and ghost afterimage placeholders")
	if sfx != null:
		_check(sfx.get_child_count() > sfx_before, "dodge plays placeholder dodge SFX")

	# 2a) 无敌帧期间免疫直接伤害，且敌方子弹直接掠过不引爆。
	var hp0 := doll.hp
	var arm0 := doll.armor
	doll.take_damage(60.0, 200.0)
	_check(doll.hp == hp0 and doll.armor == arm0, "dodge i-frames negate direct damage")
	var bullet := EnemyBullet2D.spawn(stage, doll.global_position + Vector2(20, -46),
		doll.global_position + Vector2(-20, -46), 40.0, 150.0)
	_check(bullet != null, "test enemy bullet spawned")
	await _step_physics(4)
	_check(is_instance_valid(bullet) and doll.hp == hp0 and doll.armor == arm0,
		"enemy bullet passes cleanly through dodging player during i-frames without exploding")
	if is_instance_valid(bullet):
		bullet.queue_free()

	# 2b) 推进到无敌帧结束但仍在翻滚尾部（约 0.24s / 0.30s）。
	await _step_physics(11)
	_check(doll.is_dodging() and not doll.is_dodge_invuln(),
		"i-frames end before dodge tail finishes")
	doll.take_damage(10.0, 200.0)
	_check(doll.hp < hp0 or doll.armor < arm0, "player can take damage again once i-frames expire")

	# 2c) 翻滚结束：总位移接近 2.6m (166.4px)，碰撞层/旋转复位，冷却未满前仍不可再滚。
	await _step_physics(8)
	var moved_x := doll.global_position.x - start_pos.x
	_check(not doll.is_dodging() and ended_count[0] == 1,
		"dodge ends cleanly and emits dodge_ended")
	_check(moved_x >= 140.0 and moved_x <= 195.0,
		"open-space dodge travels expected distance (~166px, actual %.1fpx)" % moved_x)
	_check((doll.collision_layer & 2) == 2 and is_equal_approx(doll.body.rotation, 0.0),
		"collision layer 2 and body rotation restore on dodge end")
	_check(not doll.can_dodge() and doll.get_dodge_cooldown_left() > 0.4,
		"dodge stays on cooldown after roll finishes")

	# 2d) 等待冷却结束，验证可再次翻滚。
	doll._dodge_cd = 0.0
	_check(doll.can_dodge() and is_equal_approx(doll.get_dodge_cooldown_ratio(), 1.0),
		"dodge becomes ready again once cooldown reaches 0")

	# 3. 严格防穿墙测试：在角色前方 42px 放置 16px 厚 Layer-1 实体墙，向右翻滚绝不穿墙。
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.global_position = Vector2(700, 400)
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 200)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	stage.add_child(wall)
	doll.global_position = Vector2(658, 400)
	await physics_frame
	_check(doll.try_dodge(Vector2.RIGHT), "dodge into wall starts")
	await _step_physics(24)
	_check(doll.global_position.x < wall.global_position.x,
		"move_and_slide prevents wall clipping during dodge (player_x=%.1f < wall_x=%.1f)" % [
			doll.global_position.x, wall.global_position.x])
	wall.queue_free()
	await physics_frame

	# 4. 临时忽略敌人碰撞防围死测试：前方 36px 放置一名活体敌人，翻滚可顺利穿过不被卡角。
	var blocker := Enemy2D.new()
	blocker.setup(&"rifleman", Vector2(360, 700), 1)
	stage.add_child(blocker)
	blocker.set_physics_process(false)
	doll._dodge_cd = 0.0
	doll.global_position = Vector2(320, 700)
	await physics_frame
	_check(doll.try_dodge(Vector2.RIGHT), "dodge through blocking enemy starts")
	await _step_physics(24)
	_check(doll.global_position.x > blocker.global_position.x + 30.0,
		"dodge passes cleanly through blocking enemy to prevent corner trapping (player_x=%.1f > enemy_x=%.1f)" % [
			doll.global_position.x, blocker.global_position.x])
	blocker.queue_free()

	# 5. Phase 7 正式动画挂口：SpriteFrames 存在 dodge_3 时自动播放且跳过占位倾斜。
	doll._dodge_cd = 0.0
	var sf := doll.body.sprite_frames
	sf.add_animation("dodge_3")
	sf.set_animation_speed("dodge_3", 8.0)
	sf.add_frame("dodge_3", sf.get_frame_texture("run_3", 0))
	doll.global_position = Vector2(300, 900)
	_check(doll.try_dodge(Vector2.RIGHT) and doll.body.animation == "dodge_3",
		"Phase 7 hook automatically plays formal dodge_<dir> animation when present")
	await _step_physics(4)
	_check(is_equal_approx(doll.body.rotation, 0.0),
		"formal dodge animation skips placeholder tilt rotation")

	stage.queue_free()
	await process_frame

	# 6. 实机 Main2D 集成：禁开火、退 ADS、HUD DodgeIndicator2D 状态同步。
	var main = MAIN_SCENE.instantiate()
	root.add_child(main)
	await _step_physics(4)
	_check(main.hud != null and main.hud.dodge_indicator != null,
		"Main2D HUD builds DodgeIndicator2D cooldown widget")
	_check(String(main.HINT_DEFAULT).contains("SPACE"),
		"Main2D default hint mentions SPACE dodge")
	var live_doll: Doll2D = main.doll
	_check(live_doll.try_dodge(Vector2.RIGHT), "Main2D player triggers dodge cleanly")
	await _step_physics(1)
	await process_frame
	await process_frame
	_check(live_doll.weapon_rig != null and live_doll.weapon_rig.dodging
		and not live_doll.weapon_rig.try_fire(),
		"WeaponRig2D blocks firing while player is dodging")
	_check(main.hud.dodge_indicator.dodging and main.hud.dodge_indicator.invuln
		and main.hud.dodge_indicator.cooldown_left > 0.5,
		"HUD DodgeIndicator2D mirrors active dodge, i-frame, and cooldown timer")

	main.queue_free()
	await process_frame

	print("\n=== dodge 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
