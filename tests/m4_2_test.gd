extends SceneTree

var _main: Node3D
var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	print("=== Operation Thistle M4.2 sonar hunter test ===")
	create_timer(120.0).timeout.connect(func() -> void: quit(2))

	var stats := EnemyDB.stats(&"hunter")
	_check(EnemyDB.ORDER.has(&"hunter"), "敌人表包含声呐猎手")
	_check(bool(stats.get("blind", false)), "猎手标记为盲眼")
	_check(float(stats["view_range"]) == 0.0, "猎手视觉距离为 0")
	_check(float(stats["hearing"]) > float(EnemyDB.stats(&"rifleman")["hearing"]), "猎手听觉强于普通敌人")
	_check(ResourceLoader.exists(String(stats["texture"])), "猎手贴图存在")

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var doll: Doll = _main.doll
	_check(not _main.level.enemy_kinds.has(&"hunter"), "第 1 层不投放猎手")

	var hunter := Enemy.new()
	_main.add_child(hunter)
	hunter.set_physics_process(false)
	hunter.setup(doll, &"hunter")
	await _frames(2)
	hunter.global_position = doll.global_position + Vector3(0, 0, 2)
	_check(hunter.blind and hunter.view_range == 0.0, "实例化后保留盲眼参数")
	_check(not hunter._can_see_player(), "无视觉：贴到 2 米也看不见")
	doll.set_flashlight(true)
	_check(not hunter._can_see_player(), "开手电不会被猎手发现")
	doll.set_flashlight(false)

	# 听觉：声源命中调查点，超出半径不反应
	hunter.state = Enemy.State.PATROL
	hunter._state_t = 0.0
	var noise_pos: Vector3 = hunter.global_position + Vector3(0, 0, 10)
	hunter.hear_noise(noise_pos, 30.0)
	_check(hunter.state == Enemy.State.SUSPICIOUS, "听到枪声转入 SUSPICIOUS")
	_check(hunter.investigate_point.is_equal_approx(noise_pos), "调查点等于声源位置")
	_check(hunter.last_known.is_equal_approx(noise_pos), "最后已知位置等于声源位置")

	hunter.state = Enemy.State.PATROL
	hunter._state_t = 0.0
	hunter.hear_noise(hunter.global_position + Vector3(0, 0, 100), 30.0)
	_check(hunter.state == Enemy.State.PATROL, "超出听觉半径不产生反应")

	hunter.state = Enemy.State.INVESTIGATE
	var newer: Vector3 = hunter.global_position + Vector3(8, 0, 0)
	hunter.hear_noise(newer, 30.0)
	_check(hunter.investigate_point.is_equal_approx(newer), "新声源覆盖旧调查点")

	# 受击：只记住命中位置，不读取玩家坐标
	hunter.state = Enemy.State.PATROL
	hunter.hp = 50.0
	doll.global_position = hunter.global_position + Vector3(0, 0, 9)
	var hit_pos: Vector3 = hunter.global_position + Vector3(0, 1.2, 0)
	hunter.take_damage(5.0, hit_pos, 0.0)
	_check(hunter.state == Enemy.State.SUSPICIOUS, "受击只进入 SUSPICIOUS")
	_check(hunter.last_known.is_equal_approx(hit_pos), "受击记住命中位置而非玩家位置")

	# 接触攻击
	hunter.state = Enemy.State.SEARCH
	hunter._cd = 0.0
	hunter.last_known = hunter.global_position
	doll.global_position = hunter.global_position + Vector3(0, 0, 0.8)
	_check(hunter._blind_contact(), "贴脸触发接触")
	_check(hunter.state == Enemy.State.COMBAT, "接触后转入 COMBAT")

	# 战斗中不实时追踪玩家
	var snapshot := Vector3(100, 0, 100)
	hunter.last_known = snapshot
	doll.global_position = hunter.global_position + Vector3(0, 0, 8)
	hunter._tick_blind_combat(0.016)
	_check(hunter.last_known == snapshot, "盲眼战斗不读取远处玩家坐标")
	hunter.free()
	doll.global_position = _main.level.player_spawn
	await _frames(2)

	# 枪声细线
	var before := get_nodes_in_group("combat_feedback").size()
	ImpactFX.gunshot_wave(_main, _main.level.player_spawn, 20.0)
	await _frames(1)
	_check(get_nodes_in_group("combat_feedback").size() == before + 1, "枪声冲击波已生成")

	# 层级投放规则
	for depth in [2, 3, 4]:
		var level := LevelGenerator.new()
		level.level_seed = 4200 + depth
		level.depth = depth
		root.add_child(level)
		await _frames(8)
		var has_hunter: bool = level.enemy_kinds.has(&"hunter")
		_check(has_hunter == (depth >= 3), "深度 %d 猎手投放规则" % depth)
		level.free()
		await _frames(2)

	print("=== M4.2 %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
