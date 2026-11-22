extends SceneTree
## 资源系统回归：三种基础资源、进阶资源、容器/掉落/自动拾取与撤离入库。
## godot --headless --path . --script res://tests/resources_2d_test.gd

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


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _pickups(layer: Node) -> int:
	var count := 0
	for child in layer.get_children():
		if child is LootPickup2D:
			count += 1
	return count


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()

	# ---- 资源表 ----
	_check(ResourceDB.BASIC.size() == 3, "three basic resources defined")
	_check(ResourceDB.display_name(&"electronics") == "电子元件"
		and ResourceDB.display_name(&"energy") == "能量单元"
		and ResourceDB.display_name(&"parts") == "机械零件",
		"basic resource names")
	_check(ResourceDB.ADVANCED.size() == 4
		and ResourceDB.display_name(&"weapon_parts") == "枪械零件"
		and ResourceDB.display_name(&"electronic_core") == "电子核心"
		and ResourceDB.display_name(&"high_energy_cell") == "高能电池组"
		and ResourceDB.display_name(&"military_alloy") == "军用合金",
		"advanced resource names")

	# ---- 默认存档 ----
	_check(p.credits() == 0, "credits start at 0")
	_check(p.material_count(&"electronics") == 0 and p.material_count(&"energy") == 0
		and p.material_count(&"parts") == 0, "basic stock starts empty")
	_check(p.advanced_count(&"electronic_core") == 0, "advanced stock starts empty")

	# ---- 战斗场景 ----
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)
	var doll = main.doll
	var rig: WeaponRig2D = doll.weapon_rig

	# ---- 容器直接入包，产出大于单个掉落 ----
	var entry: Dictionary = main.level.containers[0]
	entry["loot"] = &"electronics"
	doll.global_position = entry["position"]
	await physics_frame
	await process_frame
	# 测试里只等待了帧信号；手动刷新一次交互目标，避免依赖 _process 的调用顺序。
	main._update_hud(0.0)
	main._try_interact()
	_check(bool(entry["searched"]), "container searched")
	_check(int(main.loot["electronics"]) >= 2 and int(main.loot["electronics"]) <= 4,
		"container yields 2-4 electronics, got %d" % int(main.loot["electronics"]))
	var carried := 0
	for id in ResourceDB.BASIC:
		carried += int(main.loot.get(String(id), 0))
	for id in main.advanced_loot:
		carried += int(main.advanced_loot[id])
	_check(main.resources == carried,
		"container loot counts toward carried total (run=%d total=%d)" % [carried, main.resources])
	main.backpack.open()
	_check(main.backpack.run_count_labels["electronics"].text
		== str(int(main.loot["electronics"])), "backpack lists container electronics")
	main.backpack.close()

	# ---- 容器多类型：主资源 2-4，必出第二种，另有概率出进阶资源 ----
	var bundle: Array[Dictionary] = main._roll_container_bundle(&"parts", 2, 4, 1.0, 1.0)
	_check(bundle.size() == 3, "container bundle can yield 3 different item types")
	_check(StringName(bundle[0]["id"]) == &"parts"
		and int(bundle[0]["amount"]) >= 2 and int(bundle[0]["amount"]) <= 4,
		"container primary keeps the 2-4 amount")
	_check(StringName(bundle[1]["id"]) != &"parts"
		and ResourceDB.is_basic(StringName(bundle[1]["id"])),
		"container secondary is a different basic resource")
	_check(not ResourceDB.is_basic(StringName(bundle[2]["id"])),
		"container bonus can be an advanced resource")
	var single: Array[Dictionary] = main._roll_container_bundle(&"parts", 2, 4, 0.0, 0.0)
	_check(single.size() == 1 and int(single[0]["amount"]) >= 2,
		"container still guarantees the old primary drop")

	# ---- 地面掉落自动拾取 ----
	var energy_before := int(main.loot["energy"])
	main._spawn_pickup(doll.global_position + Vector2(90, 0), "resource", &"energy", 1)
	await _wait(50)
	_check(int(main.loot["energy"]) == energy_before + 1, "nearby drop is collected automatically")
	_check(_pickups(main.fx_layer) == 0, "collected pickup is removed")

	var reserve_before := rig.get_reserve()
	main._spawn_pickup(doll.global_position + Vector2(80, 0), "ammo", &"light", 18)
	await _wait(50)
	_check(rig.get_reserve() == reserve_before + 18, "ammo drop refills the shared light reserve")

	# ---- 敌人掉落 ----
	var before_drops := _pickups(main.fx_layer)
	var carried_before: int = int(main.resources)
	var victim: Enemy2D = main.enemies[0]
	victim.set_physics_process(false)
	main._spawn_enemy_drops(victim)
	await process_frame
	_check(_pickups(main.fx_layer) > before_drops or main.resources > carried_before,
		"enemy death spawns loot pickup")
	var rifle: Dictionary = EnemyDB.stats(&"rifleman")
	_check(not bool(rifle["melee"]) and float(rifle["ammo_drop"]) > 0.0,
		"ranged enemy has an ammo drop chance")
	var valid := true
	for i in 20:
		if not ResourceDB.is_basic(main._roll_basic_drop(&"rifleman")):
			valid = false
	_check(valid, "enemy basic drop table only yields basic resources")
	var consts: Dictionary = main.get_script().get_script_constant_map()
	_check(float(consts["ENEMY_SECONDARY_CHANCE"])
		< float(consts["CONTAINER_SECONDARY_CHANCE"]),
		"enemy multi-loot chance is lower than containers")
	var second_valid := true
	for i in 20:
		var second: StringName = main._roll_basic_excluding(&"parts")
		if not ResourceDB.is_basic(second) or second == &"parts":
			second_valid = false
	_check(second_valid, "enemy secondary drop is a different basic resource")

	# ---- 撤离入库：材料与进阶资源写回存档 ----
	main.loot = {"electronics": 3, "energy": 2, "parts": 4}
	main.advanced_loot = {"electronic_core": 1}
	main.resources = 10
	p.data["resources"] = 0
	p.data["materials_2d"] = {"electronics": 0, "energy": 0, "parts": 0}
	p.data["advanced_2d"] = {"weapon_parts": 0, "electronic_core": 0,
		"high_energy_cell": 0, "military_alloy": 0}
	main._finish_run(true)
	_check(p.credits() == 50, "extraction pays credits, got %d" % p.credits())
	_check(p.material_count(&"electronics") == 3 and p.material_count(&"energy") == 2
		and p.material_count(&"parts") == 4, "basic resources banked on extraction")
	_check(p.advanced_count(&"electronic_core") == 1, "advanced resource banked")
	var loot_labels: Dictionary = main.hud.debrief_loot_labels
	_check(String(loot_labels["electronics"]["count"].text) == "×3"
		and String(loot_labels["electronic_core"]["count"].text) == "×1",
		"result panel lists extracted resources")
	_check(main.hud.result_detail.text.contains("信用点 +50"),
		"result panel shows credits and xp")

	# ---- 天赋消耗：信用点 + 对应基础资源 ----
	p.data["resources"] = 100
	p.data["talents_2d"] = {"hp": 0, "gun": 0, "move": 0, "reload": 0, "scavenge": 0}
	_check(p.talent_2d_material(&"gun") == &"electronics"
		and p.talent_2d_material(&"hp") == &"energy"
		and p.talent_2d_material(&"scavenge") == &"parts",
		"upgrade lines map to their basic resource")
	_check(p.talent_2d_material_cost(&"gun") == 3, "material cost starts at 3")
	var electronics_before: int = int(p.material_count(&"electronics"))
	_check(p.buy_talent_2d(&"gun"), "gun upgrade buys with credits + electronics")
	_check(p.material_count(&"electronics") == electronics_before - 3,
		"gun upgrade spends electronics")
	_check(p.credits() == 55, "gun upgrade spends credits")

	main.queue_free()
	await process_frame
	print("\n=== resources 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
