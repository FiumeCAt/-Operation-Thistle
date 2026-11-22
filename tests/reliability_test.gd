extends SceneTree

var _fails := 0
var _checks := 0
var _main: Node3D
var _doll: Doll
var _weapon: PlayerWeapon

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _run() -> void:
	print("=== Operation Thistle reliability test ===")
	create_timer(45.0).timeout.connect(func() -> void:
		push_error("Reliability test timed out")
		quit(2)
	)
	seed(20261025)
	var packed := load("res://scenes/core/Main.tscn") as PackedScene
	_check(packed != null, "真实 Main 场景加载")
	if packed == null:
		quit(1)
		return
	node_added.connect(_disable_enemy)
	_main = packed.instantiate()
	root.add_child(_main)
	current_scene = _main
	for i in 8:
		await physics_frame
		await process_frame
	_doll = _main.get_node_or_null("Doll") as Doll
	var level := _main.get_node_or_null("Level") as LevelGenerator
	var enemies := get_nodes_in_group("enemies")
	_check(_doll != null and level != null and not enemies.is_empty(), "玩家、关卡与延迟生成敌人初始化完成")
	if _doll == null or level == null or enemies.is_empty():
		_finish()
		return
	_weapon = _doll.weapon
	_check(_weapon != null, "真实 PlayerWeapon 已初始化")
	if _weapon == null:
		_finish()
		return
	for enemy in enemies:
		_check(not enemy.is_physics_processing() and not enemy.is_processing(), "敌人自动处理已禁用: " + str(enemy.get_instance_id()))
	_weapon.set_physics_process(false)
	_main.set_process(false)
	await _test_respawn(level)
	await _test_death_restart()
	enemies = get_nodes_in_group("enemies")
	_doll.set_physics_process(false)
	_doll.debug_set_aim(_doll.global_position + Vector3(-10.0, 0.0, 0.0))
	for id in [&"g17", &"saiga12k"]:
		_test_reload(id, false)
		_test_reload(id, true)
	_test_auto_cycle()
	for id in WeaponDB.WEAPON_ORDER:
		_test_fire_cooldown(id)
	_test_armor(enemies[0] as Enemy)
	await _test_ai(enemies[0] as Enemy, Enemy.State.INVESTIGATE, 3.0)
	await _test_ai(enemies[0] as Enemy, Enemy.State.SEARCH, 5.0)
	_finish()

func _disable_enemy(node: Node) -> void:
	if node is Enemy:
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.set_process(false)
		node.set_physics_process(false)
		node.ready.connect(func() -> void:
			node.set_process(false)
			node.set_physics_process(false)
		, CONNECT_ONE_SHOT)

func _test_respawn(level: LevelGenerator) -> void:
	var original := level.player_spawn
	for explicit in [true, false]:
		var label := "显式 respawn" if explicit else "Main 调试复位"
		level.player_spawn = original + Vector3(1.0 if explicit else -1.0, 0.25, 0.0)
		_doll.global_position = original + Vector3(0.0, 4.0, 1.0)
		_doll.velocity = Vector3(7.0, -30.0, 5.0)
		_doll.hp = 1.0
		_doll.stamina = 2.0
		_doll._hurt_cd = 0.0
		if explicit:
			_doll.respawn()
		else:
			_doll.debug_set_facing(90.0)
			_doll.debug_set_state("hurt")
			_main._reset_doll()
			_check(not _doll.debug_face_enabled and _doll.debug_state == "", label + "清除调试覆盖")
		_check(_doll.global_position.is_equal_approx(level.player_spawn), label + "使用修改后的 Level.player_spawn")
		_check(_doll.velocity.is_equal_approx(Vector3.ZERO), label + "立即清空三轴速度")
		_check(is_equal_approx(_doll.hp, _doll.hp_max) and is_equal_approx(_doll.stamina, _doll.stamina_max), label + "恢复生命和体力")
		var minimum_y := _doll.global_position.y
		for i in 120:
			await physics_frame
			await process_frame
			minimum_y = minf(minimum_y, _doll.global_position.y)
		var offset := _doll.global_position - level.player_spawn
		_check(minimum_y > -0.1 and _doll.is_on_floor(), label + "等待120物理帧仍站在真实地板上，最低 y=%.4f" % minimum_y)
		_check(Vector2(offset.x, offset.z).length() < 0.05 and absf(_doll.velocity.y) < 0.01, label + "无水平漂移或持续下坠")
	level.player_spawn = original
	_doll.respawn()

func _test_death_restart() -> void:
	var old_id := _main.get_instance_id()
	var old_doll_id := _doll.get_instance_id()
	var old_level_id: int = _main.level.get_instance_id()
	var position := _doll.global_position
	_doll._hurt_cd = 0.0
	_doll.take_damage(1000.0)
	_check(_doll.is_dead and _doll.hp == 0.0 and _main.run_state == _main.RunState.FAILED, "死亡进入失败而非自动复位")
	_check(paused and _doll.global_position == position and _main.run_hud._result.visible, "死亡原地暂停并显示结算")
	_main.run_hud._restart.pressed.emit()
	_check(_main.run_hud._at_base and paused and _main.get_instance_id() == old_id, "返回基地保留结果，不提前重开")
	_main.run_hud._restart.pressed.emit()
	for i in 10:
		await physics_frame
		await process_frame
	_check(_main.get_instance_id() == old_id, "按钮 pressed 信号复用同一个 Main 实例")
	_check(_main.doll.get_instance_id() == old_doll_id and _main.doll == _doll, "重开保留同一个 Doll 实例")
	_check(not is_instance_id_valid(old_level_id) and _main.level.get_instance_id() != old_level_id, "重开销毁旧关卡并生成新关卡")
	_check(not paused and _main._run_ready, "重开解除暂停并重新就绪")
	_check(not _doll.is_dead and _doll.hp == _doll.hp_max and _main.resources == 0, "新局恢复生命并清空资源")
	_weapon.set_physics_process(false)
	_main.set_process(false)

func _prepare_weapon(id: StringName) -> void:
	_weapon.switch_to(id)
	_weapon._physics_process(10.0)
	_weapon.mag = _weapon.weapon.mag_capacity
	_weapon.chamber = "LOADED" if _weapon.weapon.chamber_size > 0 else "EMPTY"
	_weapon.reserve[_weapon.ammo_type] = 40

func _snapshot() -> Dictionary:
	return {
		"fire_cd": _weapon.fire_cd,
		"cycle_t": _weapon.cycle_t,
		"load_t": _weapon.load_t,
		"busy_max": _weapon.busy_max,
		"pending_cycle": _weapon._pending_cycle,
		"pending_load": _weapon._pending_load,
		"mag": _weapon.mag,
		"chamber": _weapon.chamber,
		"reserve": _weapon.reserve.duplicate(true),
		"ammo_type": _weapon.ammo_type,
	}

func _round_trip(label: String) -> void:
	var id := _weapon.weapon_id
	var before := _snapshot()
	var progress := _weapon.get_progress()
	_weapon.switch_to(&"g17" if id == &"m870" else &"m870")
	_weapon._physics_process(8.0)
	_weapon.switch_to(id)
	var after := _snapshot()
	for key in before:
		_check(after[key] == before[key], "%s 收起8秒再切回保留 %s" % [label, key])
	_check(is_equal_approx(_weapon.get_progress(), progress), label + "忙碌进度保持不变")

func _total_ammo() -> int:
	return _weapon.get_loaded_total() + _weapon.get_reserve() + _weapon._pending_load

func _test_reload(id: StringName, scarce: bool) -> void:
	_prepare_weapon(id)
	_weapon.mag = 2
	_weapon.reserve[_weapon.ammo_type] = 3 if scarce else 40
	var label := "%s %s换弹" % [id, "备弹不足" if scarce else "常规"]
	var total := _total_ammo()
	var expected := mini(_weapon.weapon.mag_capacity - 2, _weapon.get_reserve())
	_weapon.reload_magazine()
	_check(_weapon._pending_load == expected and _weapon.load_t > 0.0, label + "启动真实待装填")
	_check(_total_ammo() == total and _weapon.mag == 2, label + "预扣备弹但未提前入匣")
	_weapon._physics_process(_weapon.load_t * 0.4)
	_round_trip(label)
	var during := _snapshot()
	_weapon.reload_magazine()
	_check(_snapshot() == during, label + "重复按换弹不会重复预扣")
	_weapon._physics_process(_weapon.load_t * 0.5)
	_check(_weapon.mag == 2 and _weapon._pending_load == expected, label + "剩余时间未到不装填")
	_weapon._physics_process(_weapon.load_t + 0.001)
	_check(_weapon.mag == 2 + expected and _weapon._pending_load == 0 and is_zero_approx(_weapon.load_t), label + "到时准确完成一次装填")
	_check(_total_ammo() == total, label + "最终弹药守恒")
	var completed_mag := _weapon.mag
	var completed_reserve := _weapon.get_reserve()
	_round_trip(label + "完成后")
	_weapon._physics_process(10.0)
	_weapon._resolve_load()
	_check(_weapon.mag == completed_mag and _weapon.get_reserve() == completed_reserve and _total_ammo() == total, label + "再切换、再推进、重复结算均不增弹")

func _test_auto_cycle() -> void:
	_prepare_weapon(&"m1014")
	var total := _total_ammo()
	var mag := _weapon.mag
	var shots := _weapon.shots
	_weapon.try_fire()
	_check(_weapon.shots == shots + 1 and _weapon.chamber == "FIRED" and _weapon._pending_cycle and _weapon.cycle_t > 0.0, "M1014 射击启动真实自动上膛")
	_weapon._physics_process(_weapon.cycle_t * 0.25)
	_round_trip("M1014 自动上膛")
	_weapon.try_fire()
	_check(_weapon.shots == shots + 1, "M1014 上膛中不能射击")
	_weapon._physics_process(_weapon.cycle_t * 0.5)
	_check(_weapon.chamber == "FIRED" and _weapon.mag == mag, "M1014 未到时不提前上膛")
	_weapon._physics_process(_weapon.cycle_t + 0.001)
	_check(_weapon.chamber == "LOADED" and _weapon.mag == mag - 1 and not _weapon._pending_cycle, "M1014 切回后继续完成上膛")
	_check(_total_ammo() == total - 1, "M1014 只消耗已射出的一发")
	_round_trip("M1014 上膛完成后")
	_weapon._physics_process(1.0)
	_weapon._resolve_cycle()
	_check(_weapon.mag == mag - 1 and _total_ammo() == total - 1, "M1014 不重复上膛扣弹")
	_weapon.try_fire()
	_check(_weapon.shots == shots + 2, "M1014 恢复后能再次射击")

func _test_fire_cooldown(id: StringName) -> void:
	_prepare_weapon(id)
	_weapon.try_fire()
	if id == &"m870":
		_weapon.pump_action()
	var shots := _weapon.shots
	var cooldown := _weapon.fire_cd
	_check(cooldown > 0.0, str(id) + "真实开火产生冷却")
	_round_trip(str(id) + "射击冷却")
	_weapon.try_fire()
	_check(_weapon.shots == shots, str(id) + "切回不能绕过冷却射击")
	_weapon._physics_process(cooldown * 0.5)
	_check(is_equal_approx(_weapon.fire_cd, cooldown * 0.5), str(id) + "冷却仅在持有时推进")
	_weapon.try_fire()
	_check(_weapon.shots == shots, str(id) + "半程冷却仍阻止射击")
	_weapon._physics_process(maxf(_weapon.fire_cd, _weapon.cycle_t) + 0.001)
	_weapon.try_fire()
	_check(_weapon.shots == shots + 1, str(id) + "冷却与上膛完成后可射击")

func _test_armor(enemy: Enemy) -> void:
	enemy.armor = 4.0
	for sample in [[20.0, 2.0, 16.0], [20.0, 4.0, 16.0], [20.0, 6.0, 24.0], [2.0, 0.0, 1.0], [13.0, 5.0, 14.0]]:
		enemy.hp = 1000.0
		enemy.on_hit(enemy.global_position + Vector3.UP, Vector3.UP, sample[0], sample[1])
		var actual := 1000.0 - enemy.hp
		_check(is_equal_approx(actual, sample[2]), "伤害 %.1f / AP %.1f / 护甲4：预期 %.1f，实际 %.1f" % [sample[0], sample[1], sample[2], actual])

func _ai_tick(enemy: Enemy, state: Enemy.State, dt: float) -> void:
	enemy._state_t += dt
	enemy._repath_t -= dt
	if state == Enemy.State.INVESTIGATE:
		enemy._tick_investigate(dt, false)
	else:
		enemy._tick_search(dt, false)

func _test_ai(enemy: Enemy, state: Enemy.State, wait_seconds: float) -> void:
	var label := "调查" if state == Enemy.State.INVESTIGATE else "搜索"
	var origin := _doll.global_position
	enemy.global_position = origin
	enemy.velocity = Vector3.ZERO
	enemy.agent.target_position = origin
	for i in 3:
		await physics_frame
		enemy.agent.get_next_path_position()
	_check(enemy.agent.is_navigation_finished() and enemy.agent.is_target_reached(), label + "前置条件：真实 agent 旧目标已到达")
	var target := origin + Vector3(4.0, 0.0, 0.0)
	enemy.last_known = target
	enemy._enter(state)
	_check(not enemy._arrived(target), label + "不把旧 agent 的到达标记用于新目标")
	_ai_tick(enemy, state, 0.1)
	_check(enemy.state == state and is_zero_approx(enemy._arrival_t), label + "未到新目标不开始等待或跳状态")
	_check(enemy.agent.target_position.is_equal_approx(target), label + "真实导航代理收到新目标")
	for i in 8:
		_ai_tick(enemy, state, 0.5)
	_check(enemy.state == state and is_zero_approx(enemy._arrival_t), label + "路途耗时不计入到达等待")
	enemy.global_position = target
	_ai_tick(enemy, state, 0.5)
	_check(is_equal_approx(enemy._arrival_t, 0.5), label + "真正到达才累计等待")
	enemy.global_position = origin
	_ai_tick(enemy, state, 0.1)
	_check(is_zero_approx(enemy._arrival_t), label + "离开目标重置连续等待")
	enemy.global_position = target
	for i in int((wait_seconds - 0.5) / 0.5):
		_ai_tick(enemy, state, 0.5)
	_check(enemy.state == state and is_equal_approx(enemy._arrival_t, wait_seconds - 0.5), label + "等待 %.1f 秒尚不退出" % (wait_seconds - 0.5))
	_ai_tick(enemy, state, 0.5)
	var expected := Enemy.State.SEARCH if state == Enemy.State.INVESTIGATE else Enemy.State.PATROL
	_check(enemy.state == expected and is_zero_approx(enemy._arrival_t), label + "到达后恰满 %.1f 秒才转换状态" % wait_seconds)

func _finish() -> void:
	print("=== %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	await create_timer(2.0).timeout
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	await create_timer(0.1).timeout
	if is_instance_valid(_main):
		_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
