extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("[FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	print("=== Operation Thistle M4.1 test ===")
	var profiles := LevelGenerator.ROOM_PROFILES
	var seen_layouts := {}
	for depth in [1, 5, 8]:
		var level := LevelGenerator.new()
		level.level_seed = 4100 + depth
		level.depth = depth
		root.add_child(level)
		await _frames(8)
		_check(level.seg_count == 5 + floori(float(depth - 1) / 2.0), "深度%d 区段编排" % depth)
		for room in level.rooms:
			var room_type: String = room["type"]
			_check(profiles.has(room_type), "房间 %s 有用途档案" % room_type)
			_check(room["profile"] == profiles[room_type], "房间 %s 档案与类型一致" % room_type)
			if room_type in ["军械库", "医疗站", "宿舍区"]:
				if not seen_layouts.has(room_type):
					seen_layouts[room_type] = {}
				seen_layouts[room_type][room["layout"]] = true
		for box in level.search_containers:
			var room_type: String = box.get_meta("room_type")
			var profile: Dictionary = profiles[room_type]
			var effect: Dictionary = box.get_meta("loot_effect")
			_check(effect["type"] in [&"ammo", &"repair", &"resource"], "箱子效果属于有效补给类型")
			_check(box.get_meta("loot_weights") == profile["weights"], "箱子保留房间掉落权重")
			if box.get_meta("room_slot") == 0:
				_check(effect["type"] == profile["loot"], "%s 主容器体现用途" % room_type)
			_check(level.rooms[box.get_meta("room_index")]["type"] == room_type, "箱子绑定真实房间")
		level.free()
		await _frames(2)
	for room_type in ["军械库", "医疗站", "宿舍区"]:
		_check(seen_layouts.get(room_type, {}).size() >= 2, "%s 具有两种可辨识布局" % room_type)

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(12)
	var main = current_scene
	for enemy in get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	_check(main._run_ready, "真实场景第五层测试已就绪")
	main.resources = 1
	main.doll.global_position = main.level.exit_position
	await _frames()
	_check(main.open_shaft(), "第五层规则测试打开竖井")
	main.depth = main.MAX_DEPTH
	_check(not main.descend(), "第五层禁止继续下潜")
	main.extract_from_shaft()
	_check(main.run_state == main.RunState.SUCCESS and main.extracted_resources == 1, "第五层可从竖井撤离并结算")
	print("=== M4.1 %s (%d checks, %d failures) ===" % ["PASS" if failures == 0 else "FAILED", checks, failures])
	main.free()
	await process_frame
	quit(0 if failures == 0 else 1)
