extends SceneTree
## K-17 环形地图回归：房间布局、容器/敌人分布、供电目标、拉闸撤离与结算加成。
## godot --headless --path . --script res://tests/map_2d_test.gd

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


func _near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	var level: Level2D = main.level
	var names: Array[String] = []
	for room in level.rooms:
		names.append(String(room["name"]))
	_check(names == ["装卸区", "仓库区", "医疗站", "军械库", "数据仓", "控制室", "巢穴", "维修间", "废弃仓",
		"撤离区", "南侧撤离区", "精炼车间", "铸造车间", "变电站", "质检室", "更衣室", "通风机房",
		"休息区", "食堂", "主装配大厅"],
		"twenty sector rooms in fixed order")
	_check(level.doors.size() == 25, "twenty main doors plus five side doors")
	_check(level.containers.size() == 52,
		"34 loot containers plus 18 decorative searchables")
	_check(level.exits.size() == 2, "two unlocked extraction points")
	_check(level.exits[0]["id"] == &"east" and level.exits[1]["id"] == &"south",
		"east and south extractions are active")
	_check(level.enemy_spawns.size() >= 25, "25+ enemy spawns, got %d" % level.enemy_spawns.size())

	var heavies := 0
	for kind in level.enemy_kinds:
		if kind == &"heavy":
			heavies += 1
	_check(heavies == 4, "four heavy elites")

	var overlap := false
	for i in level.rooms.size():
		for j in range(i + 1, level.rooms.size()):
			if (level.rooms[i]["rect"] as Rect2).intersects(level.rooms[j]["rect"]):
				overlap = true
	_check(not overlap, "room rects do not overlap")
	_check((level.rooms[0]["rect"] as Rect2).has_point(level.player_spawn),
		"player spawns inside the loading bay")
	_check((level.rooms[9]["rect"] as Rect2).has_point(level.exit_position),
		"direct extraction sits in the east room")
	_check((level.rooms[10]["rect"] as Rect2).has_point(
		Vector2(Level2D.EXTRACTS[&"south"]["pos"]) * Level2D.TILE),
		"south extraction room is connected")
	_check((level.rooms[3]["rect"] as Rect2).has_point(level.switch_exit_position),
		"cargo lift sits in the armory")
	_check((level.rooms[5]["rect"] as Rect2).has_point(level.power_position),
		"power console sits in the control room")
	_check(_near(level.doors[0]["node"].rotation, PI * 0.5), "loading bay door is vertical")
	_check(_near(level.doors[9]["node"].rotation, PI * 0.5), "extraction door is vertical")
	_check(_near(level.doors[10]["node"].rotation, 0.0), "south extraction door is horizontal")

	# 出生点安全区：默认装卸区出生，储藏室不刷怪。
	var storage_enemy := false
	var storage_rect: Rect2 = level.rooms[1]["rect"]
	for pos in level.enemy_spawns:
		if storage_rect.has_point(pos):
			storage_enemy = true
	_check(not storage_enemy, "safe room near insertion spawn has no enemies")

	main.doll.global_position = level.rooms[0]["door"]
	await physics_frame
	await process_frame
	await process_frame
	_check(level.doors[0]["node"].open, "loading bay door opens for the player")
	await create_timer(0.4).timeout
	_check(level.doors[0]["node"]._slide > 0.9, "door panels slide fully open")

	_check(not level.power_on and _near(level.bonus_mul, 1.0), "power starts offline")
	_check(main.map_overlay != null and not main.map_overlay.visible,
		"big map overlay exists and is hidden")
	main.map_overlay.toggle()
	_check(main.map_overlay.visible and paused, "M map pauses and shows the facility")
	main.map_overlay.toggle()
	_check(not main.map_overlay.visible and not paused, "closing the big map resumes")
	_check(main.hud._minimap != null and main.hud._minimap.run == main,
		"minimap is wired to the run")
	_check(main.hud._minimap.size.x >= 240.0, "minimap is large enough to read")
	_check(main._objective_text().contains("可选：供电"), "objective hints at the power option")

	# 未供电时拉闸撤离应被拒绝
	main.doll.global_position = level.switch_exit_position
	await physics_frame
	await process_frame
	main._try_interact()
	_check(main.run_state == 0, "cargo lift refuses extraction before power")
	_check(level._switch_label.text.contains("未供电"), "lift label shows unpowered")

	# 控制室恢复供电
	main.doll.global_position = level.power_position + Vector2(0, -80)
	await physics_frame
	await process_frame
	main._try_interact()
	_check(level.power_on, "interacting with the console restores power")
	_check(_near(level.bonus_mul, 1.2), "power grants a 20% run bonus")
	_check(level._switch_label.text.contains("已供电"), "lift label flips to powered")
	_check(main._objective_text().contains("拉闸"), "objective updates after power")

	# 无资源仍不能撤离
	main.doll.global_position = level.switch_exit_position
	await physics_frame
	await process_frame
	main._try_interact()
	_check(main.run_state == 0, "cargo lift still needs one resource")

	# 带资源拉闸撤离：5 资源 × 10 × 1.2 × 1.1 = 66，结算面板显示 66 × 0.5 = 33
	main.resources = 5
	main._try_interact()
	_check(main.run_state == 1, "powered cargo lift extracts successfully")
	_check(int(p.data["resources"]) == 33, "switch extraction pays 33, got %d" % int(p.data["resources"]))
	_check(int(p.data["xp"]) == 45, "switch extraction pays 45 xp, got %d" % int(p.data["xp"]))
	_check(main.hud.result_detail.text.contains("+33") and main.hud.result_detail.text.contains("拉闸撤离 +10%"),
		"result panel shows the objective and lift bonuses")
	_check(main.hud.return_button.visible and main.hud.return_button.text.contains("返回基地"),
		"result panel offers return to base")

	# 直接撤离：不要求供电，也没有任务加成
	main.queue_free()
	await process_frame
	var banked := int(p.data["resources"])
	var main2 = load("res://scenes/core/Main2D.tscn").instantiate()
	main2.mouse_aim_enabled = false
	root.add_child(main2)
	await process_frame
	await physics_frame
	for enemy in main2.enemies:
		enemy.set_physics_process(false)
	main2.resources = 3
	main2.doll.global_position = main2.level.exit_position
	await physics_frame
	await process_frame
	main2._try_interact()
	_check(main2.run_state == 1, "direct extraction works without power")
	_check(int(p.data["resources"]) == banked + 15, "direct extraction pays 15")
	_check(not main2.result_label.text.contains("任务加成"), "direct extraction has no objective bonus")

	main2.queue_free()
	await process_frame

	# 撤离后点击“返回基地”应真的回到开始菜单。
	var main3 = load("res://scenes/core/Main2D.tscn").instantiate()
	main3.mouse_aim_enabled = false
	root.add_child(main3)
	await process_frame
	await physics_frame
	main3.resources = 1
	main3._finish_run(true)
	await process_frame
	main3.hud.return_button.pressed.emit()
	for i in 4:
		await process_frame
	_check(current_scene != null and current_scene.name == "StartMenu2D",
		"return button goes back to the base menu")

	print("\n=== map 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
