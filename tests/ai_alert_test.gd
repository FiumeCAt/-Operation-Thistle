extends SceneTree
## AI 警觉回归：丢失目标后追踪更久；视野内队友倒下会触发搜索玩家。
## godot --headless --path . --script res://tests/ai_alert_test.gd

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

	_check(Enemy2D.LOST_SIGHT >= 7.0, "lost-sight pursuit lasts longer (%.1f s)" % Enemy2D.LOST_SIGHT)
	_check(Enemy2D.SEARCH_TIME >= 12.0, "search state lasts longer (%.1f s)" % Enemy2D.SEARCH_TIME)

	# 清掉关卡自带敌人，只在同一片大厅里布置观察者。
	for enemy in main.enemies:
		enemy.set_physics_process(false)
		enemy.queue_free()
	main.enemies.clear()
	await process_frame

	var hall: Dictionary = {}
	for room in main.level.rooms:
		if StringName(room["type"]) == &"hall":
			hall = room
			break
	_check(not hall.is_empty(), "hall room is available for the test")
	if hall.is_empty():
		quit(1)
		return
	var rect: Rect2 = hall["rect"]
	var spot: Vector2 = rect.position + Vector2(4.0, 5.0) * main.TILE

	var victim := _spawn(main, &"rifleman", spot)
	var witness := _spawn(main, &"rifleman", spot + Vector2(2.5, 0.0) * main.TILE)
	var far_guard := _spawn(main, &"rifleman", spot + Vector2(22.0, 0.0) * main.TILE)
	await process_frame
	await physics_frame

	_check(witness.can_see_point(victim.global_position), "witness sees the victim")
	_check(not witness.can_see_point(main.doll.global_position),
		"witness cannot see the player from here")
	_check(witness.state == "patrol" and far_guard.state == "patrol",
		"observers start on patrol")

	witness._state_t = 5.0
	victim.take_damage(999999.0)
	_check(witness.state == "search", "ally death in view triggers search")
	_check(witness._state_t <= 0.01, "new search restarts its timer")
	_check(is_equal_approx(witness._lost_t, 0.0), "lost-sight timer resets for the search")
	_check(witness._last_known.distance_to(main.doll.global_position) < 2.0,
		"search targets the player's last known position")
	_check(far_guard.state == "patrol", "enemies outside view are not alerted")

	# 已在搜索中的单位被队友death提醒时，也会刷新搜索计时。
	witness._state_t = 9.0
	witness.alert_by_ally_death(spot)
	_check(witness._state_t <= 0.01 and witness.state == "search",
		"an ongoing search refreshes instead of ending")

	main.queue_free()
	await process_frame
	print("\n=== ai alert: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


func _spawn(main, kind: StringName, pos: Vector2) -> Enemy2D:
	var enemy := Enemy2D.new()
	enemy.setup(kind, pos, 1)
	main.sort_layer.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.died.connect(main._on_enemy_died)
	main.enemies.append(enemy)
	return enemy
