extends SceneTree
## 敌人寻路回归：整图 A* 网格可用，路径不穿墙，敌人能绕过墙角接近玩家。
## godot --headless --path . --script res://tests/navigation_2d_test.gd

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


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	var level = main.level
	_check(level.is_nav_walkable(level.player_spawn),
		"player spawn is on the navigation grid")
	_check(not level.is_nav_walkable(Vector2(6.5, 8.5) * 64.0),
		"outside-wall cells are solid")

	var from: Vector2 = level.player_spawn
	var to: Vector2 = level.rooms[1]["center"]
	var path: PackedVector2Array = level.find_nav_path(from, to)
	_check(path.size() >= 2, "A* returns a path across the facility (%d points)" % path.size())
	var all_walkable := true
	for point in path:
		if not level.is_nav_walkable(point):
			all_walkable = false
			break
	_check(all_walkable, "every path point stays on walkable cells")
	if path.size() >= 2:
		_check(path[path.size() - 1].distance_to(to) < 96.0,
			"path ends near the requested target")
		_check(_path_length(path) > from.distance_to(to) * 1.02,
			"path detours around walls instead of crossing them")

	# 真实移动：让步枪兵从装卸区追到仓储区，必须绕过墙角和门洞。
	var enemy := Enemy2D.new()
	enemy.setup(&"rifleman", level.rooms[0]["center"], 1)
	enemy.nav_level = level
	enemy.always_hunt = true
	main.sort_layer.add_child(enemy)
	# 目标放在仓库区门外的西主廊：敌人必须先向东穿过装卸区大门，再沿走廊北上。
	main.doll.global_position = Vector2(39.0, 22.0) * 64.0
	enemy.global_position = level.rooms[0]["center"]
	for i in 20:
		await physics_frame
	var start_dist: float = enemy.global_position.distance_to(main.doll.global_position)
	for i in 240:
		await physics_frame
	var end_dist: float = enemy.global_position.distance_to(main.doll.global_position)
	_check(end_dist < start_dist - 150.0,
		"enemy navigates around corners (%.0f -> %.0f)" % [start_dist, end_dist])
	_check(enemy.nav_level == level, "enemy receives the level navigation grid")

	enemy.queue_free()
	main.queue_free()
	await process_frame
	print("\n=== navigation 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total
