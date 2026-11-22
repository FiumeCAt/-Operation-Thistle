extends SceneTree
## 浪潮模式回归：波次成长、永久追踪、每 5 波刷新补给与 100% 撤离、30% 阵亡/提前撤离回收、掉落成长。
## godot --headless --path . --script res://tests/waves_2d_test.gd

var _pass := 0
var _fail := 0
const BASE_COUNT := 5
const STAT_STEP := 0.05
const INTERMISSION := 4.0


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
	var p = root.get_node_or_null("Progress")
	_check(p != null, "Progress autoload exists")
	p.reset_for_test()
	_check(p.run_mode() == "raid", "run mode defaults to raid")
	p.set_run_mode("waves")
	_check(p.run_mode() == "waves", "run mode saves waves")
	p.set_run_mode("bogus")
	_check(p.run_mode() == "raid", "unknown run mode falls back to raid")
	p.set_run_mode("waves")

	# 1) 开局：浪潮模式不刷常规关卡敌人，ESC 菜单出现提前撤离。
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	_check(main.waves_mode, "main enters waves mode from Progress")
	_check(main.enemies.is_empty(), "waves mode skips pre-generated enemies")
	_check(main.pause_menu._retreat != null and main.pause_menu._retreat.visible,
		"pause menu shows retreat in waves mode")

	# 2) 第 1 波：从基础数量开始，属性不放大。
	var rifleman_hp := float(EnemyDB.stats(&"rifleman")["hp"])
	main._begin_wave(1)
	_check(main.wave_index == 1 and main.wave_active, "wave 1 starts")
	_check(main._wave_spawn_queue.size() == BASE_COUNT,
		"wave 1 count = base (%d)" % main._wave_spawn_queue.size())
	while not main._wave_spawn_queue.is_empty():
		main._spawn_wave_enemy(main._wave_spawn_queue.pop_front())
	_check(main.enemies.size() == BASE_COUNT, "wave 1 enemies spawned")
	_check(main.wave_alive == BASE_COUNT, "wave alive counter matches")
	_check(is_equal_approx(main.wave_loot_mul, 1.0), "waves start at 100% loot")
	var all_hunt := true
	for enemy in main.enemies:
		all_hunt = all_hunt and enemy.always_hunt
	_check(all_hunt, "wave enemies permanently hunt the player")
	_check(main.waves_tracking_active(), "waves under 10 enemies are tracked from the start")
	var wave1_hp_ok := true
	for enemy in main.enemies:
		enemy.set_physics_process(false)
		wave1_hp_ok = wave1_hp_ok and is_equal_approx(enemy.hp_max,
			float(EnemyDB.stats(enemy.kind)["hp"]))
	_check(wave1_hp_ok, "wave 1 keeps base hp")
	_check(is_equal_approx(float(EnemyDB.stats(&"rifleman")["hp"]), rifleman_hp),
		"enemy stats table is not mutated")

	# 3) 清空第 1 波 → 进入波间倒计时。
	for enemy in main.enemies.duplicate():
		enemy.set_physics_process(false)
		enemy.take_damage(999999.0)
	main._update_waves(0.016)
	_check(not main.wave_active and main.wave_alive == 0, "clearing a wave ends the assault")
	_check(is_equal_approx(main._wave_intermission, INTERMISSION),
		"cleared wave starts the intermission")
	_check(is_equal_approx(main.wave_loot_mul, 1.02),
		"surviving a wave raises loot to 102%")

	# 4) 第 4 波：在上一波基础上再 +2/+3/+4，生命/伤害线性 +5%×3。
	var wave4_count := BASE_COUNT + 2 + 3 + 4
	main._begin_wave(4)
	_check(main._wave_spawn_queue.size() == wave4_count,
		"wave 4 count grows by wave number (%d)" % main._wave_spawn_queue.size())
	var stat_mul: float = 1.0 + STAT_STEP * 3.0
	var wave4_ok := true
	var kinds_ok := true
	while not main._wave_spawn_queue.is_empty():
		main._spawn_wave_enemy(main._wave_spawn_queue.pop_front())
	for enemy in main.enemies:
		enemy.set_physics_process(false)
		wave4_ok = wave4_ok and is_equal_approx(enemy.hp_max,
			float(EnemyDB.stats(enemy.kind)["hp"]) * stat_mul)
		wave4_ok = wave4_ok and is_equal_approx(enemy.damage_mul, stat_mul)
		kinds_ok = kinds_ok and enemy.kind in [&"rifleman", &"rusher", &"heavy"]
	_check(main.enemies.size() == wave4_count, "wave 4 enemies spawned")
	_check(wave4_ok, "wave 4 hp/damage scale to %.3f" % stat_mul)
	_check(kinds_ok, "wave 4 roster stays below hunter tier")
	_check(is_equal_approx(main.wave_stat_scale(11), 1.5),
		"wave 11 stats are 150%, linear not compounding")
	_check(is_equal_approx(main.wave_stat_scale(21), 2.0),
		"wave 21 stats are 200%, linear not compounding")
	_check(not main.waves_tracking_active(), "14 remaining enemies are not tracked")
	main.wave_alive = 9
	_check(main.waves_tracking_active(), "fewer than 10 remaining enemies are tracked")
	main.wave_alive = wave4_count
	main.wave_index = 20
	main._wave_total = 214
	main.wave_alive = 21
	_check(main.waves_tracking_active(), "below 10 percent remaining is tracked")
	main.wave_alive = 22
	_check(not main.waves_tracking_active(), "above 10 percent remaining is not tracked")
	main.wave_index = 4
	main._wave_total = wave4_count
	main.wave_alive = wave4_count
	# 累计增长规则：第 11 波 = 第 10 波 + 11。
	var wave10_count: int = main._wave_enemy_count(10)
	var wave11_count: int = main._wave_enemy_count(11)
	_check(wave10_count == BASE_COUNT + 54, "wave 10 accumulates 2..10 (%d)" % wave10_count)
	_check(wave11_count - wave10_count == 11,
		"wave 11 adds its own wave number (%d -> %d)" % [wave10_count, wave11_count])
	for enemy in main.enemies.duplicate():
		enemy.take_damage(999999.0)
	main._update_waves(0.016)
	_check(is_equal_approx(main.wave_loot_mul, 1.04),
		"two survived waves raise loot to 104%")

	# 5) 每 5 波：刷新补给 + 撤离弹窗；第 4 波不触发。
	_check(main._wave_popup != null and not main._wave_popup.visible,
		"wave 4 does not open the extraction popup")
	var test_entry: Dictionary = main.level.containers[0]
	test_entry["searched"] = true
	(test_entry["node"] as Node2D).modulate = Color(0.5, 0.5, 0.5, 1.0)
	main.wave_index = 5
	main.wave_active = false
	main._on_wave_cleared()
	_check(is_equal_approx(main.wave_loot_mul, 1.06),
		"wave 5 raises loot to 106%")
	_check(main._loot_amount(100) == 106, "loot amount scales with survived waves")
	_check(is_equal_approx(main._loot_chance(0.5), 0.53),
		"loot chance scales with survived waves")
	_check(not bool(test_entry["searched"]), "wave 5 refreshes all containers")
	_check((test_entry["node"] as Node2D).modulate == Color(1, 1, 1, 1),
		"refreshed containers return to normal tint")
	_check(main._wave_popup != null and main._wave_popup.visible,
		"wave 5 opens the extraction popup")
	_check(main.get_tree().paused, "extraction popup pauses the game")
	_check(main._wave_popup._wave_label.text.contains("第 5 波")
		and main._wave_popup._wave_label.text.contains("100%"),
		"popup names wave 5 and the 100% payout")
	main._wave_popup._continue()
	_check(not main.get_tree().paused and not main._wave_popup.visible,
		"continuing closes the popup and resumes")
	_check(is_equal_approx(main._wave_intermission, main.WAVES_INTERMISSION),
		"continuing schedules the next wave")

	# 6) 正常撤离：100% 信用点与材料。
	main.resources = 10
	main.loot = {"electronics": 10, "energy": 0, "parts": 0}
	main.advanced_loot = {"weapon_parts": 4}
	var credits_before: int = p.credits()
	var electronics_before: int = p.material_count(&"electronics")
	var weapon_parts_before: int = p.advanced_count(&"weapon_parts")
	main._on_waves_extract()
	var raw_100 := int(round(10.0 * 10.0 * main.talent_scavenge * 1.0))
	_check(p.credits() - credits_before == p.credit_gain(raw_100),
		"extraction pays 100%% credits (%d)" % (p.credits() - credits_before))
	_check(p.material_count(&"electronics") - electronics_before == 10,
		"extraction pays 100%% materials")
	_check(p.advanced_count(&"weapon_parts") - weapon_parts_before == 4,
		"extraction pays 100%% advanced materials")
	_check(main.hud.result_label.text == "撤离成功"
		and main.hud.result_detail.text.contains("100%"),
		"result panel shows the 100%% extraction")
	main.queue_free()
	await process_frame

	# 7) ESC 提前撤离：30%。
	var main2 = load("res://scenes/core/Main2D.tscn").instantiate()
	main2.mouse_aim_enabled = false
	root.add_child(main2)
	await process_frame
	await physics_frame
	main2.resources = 10
	main2.loot = {"electronics": 10, "energy": 0, "parts": 0}
	main2.advanced_loot = {}
	credits_before = p.credits()
	electronics_before = p.material_count(&"electronics")
	main2._on_waves_retreat()
	var raw_30 := int(round(10.0 * 10.0 * main2.talent_scavenge * 0.3))
	_check(p.credits() - credits_before == p.credit_gain(raw_30),
		"ESC retreat pays 30%% credits (%d)" % (p.credits() - credits_before))
	_check(p.material_count(&"electronics") - electronics_before == 3,
		"ESC retreat pays 30%% materials")
	_check(main2.hud.result_label.text == "撤离成功"
		and main2.hud.result_detail.text.contains("30%"),
		"result panel shows the 30%% retreat")
	main2.queue_free()
	await process_frame

	# 8) 阵亡：同样回收 30%，并在面板展示回收物资。
	var main3 = load("res://scenes/core/Main2D.tscn").instantiate()
	main3.mouse_aim_enabled = false
	root.add_child(main3)
	await process_frame
	await physics_frame
	main3.resources = 10
	main3.loot = {"electronics": 10, "energy": 0, "parts": 0}
	main3.advanced_loot = {}
	credits_before = p.credits()
	electronics_before = p.material_count(&"electronics")
	main3._on_player_died()
	_check(p.credits() - credits_before == p.credit_gain(raw_30),
		"death pays 30%% credits (%d)" % (p.credits() - credits_before))
	_check(p.material_count(&"electronics") - electronics_before == 3,
		"death pays 30%% materials")
	_check(main3.hud.result_label.text == "阵亡"
		and main3.hud.result_detail.text.contains("30%"),
		"death panel explains the 30%% recovery")
	var row_visible := false
	var loot_entry: Dictionary = main3.hud.debrief_loot_labels.get("electronics", {})
	if not loot_entry.is_empty():
		row_visible = (loot_entry["row"] as Control).visible
	_check(row_visible, "death panel still lists recovered loot")
	main3.queue_free()
	await process_frame

	# 9) 开始菜单：浪潮按钮走部署页并记录模式。
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.waves_button != null and menu.waves_button.text.contains("浪潮"),
		"start menu exposes the waves entry")
	menu._start_waves()
	_check(menu.deployment.visible and menu._pending_mode == "waves",
		"waves entry opens deployment in waves mode")
	_check(menu.deployment._subtitle.text.contains("浪潮"),
		"deployment explains the waves rules")
	menu.deployment.close_menu()
	menu.queue_free()
	await process_frame

	print("\n=== waves 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
