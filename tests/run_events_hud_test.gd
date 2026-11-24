extends SceneTree
## Step 3.2 回归：Main2D 行动事件信号总线 + 只读快照 + UI 解耦 + 死代码清理。
## godot --headless --path . --script res://tests/run_events_hud_test.gd

var _ok := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	print("=== run_events_hud_test ===")
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p == null:
		_check(false, "Progress autoload exists")
		quit(1)
		return
	p.reset_for_test()

	# 1) 死代码清理：RunHUD2D 不再保留未使用的 WEAPON_SHORT_NAME
	var hud_script: Script = preload("res://scripts/ui/RunHUD2D.gd")
	_check(not hud_script.get_script_constant_map().has("WEAPON_SHORT_NAME"),
		"RunHUD2D.WEAPON_SHORT_NAME dead code removed")

	# 2) BackpackMenu2D 脱离 Main2D 独立运行（纯快照回调 + opened/closed 信号）
	var standalone_bp := BackpackMenu2D.new()
	root.add_child(standalone_bp)
	await process_frame
	var bp_events := {"opened": 0, "closed": 0}
	standalone_bp.opened.connect(func() -> void: bp_events["opened"] = int(bp_events["opened"]) + 1)
	standalone_bp.closed.connect(func() -> void: bp_events["closed"] = int(bp_events["closed"]) + 1)
	standalone_bp.set_loot_provider(func() -> Dictionary:
		return {"basic": {"parts": 4, "electronics": 2}, "advanced": {"electronic_core": 1}}
	)
	standalone_bp.open()
	_check(standalone_bp.visible and int(bp_events["opened"]) == 1
		and standalone_bp.run_count_labels["parts"].text == "4"
		and standalone_bp.run_count_labels["electronic_core"].text == "1"
		and standalone_bp.run_total_label.text.contains("7"),
		"standalone BackpackMenu2D works from loot_provider without Main2D")
	standalone_bp.close()
	_check(not standalone_bp.visible and int(bp_events["closed"]) == 1 and not paused,
		"standalone BackpackMenu2D emits closed and unpauses cleanly")
	standalone_bp.queue_free()
	await process_frame

	# 3) Minimap2D & MapOverlay2D 脱离 Main2D 独立运行（纯快照回调 + opened/closed 信号）
	var mock_map_provider := func() -> Dictionary:
		return {
			"map_size": Vector2(1280, 960),
			"tile_size": 64.0,
			"floor_rects": [Rect2i(0, 0, 20, 15)],
			"rooms": [{"name": "测试间", "rect": Rect2(64, 64, 320, 256)}],
			"containers": [{"position": Vector2(200, 200), "searched": false}],
			"exits": [{"name": "测试出口", "position": Vector2(1100, 480)}],
			"power_position": Vector2(400, 400),
			"power_on": true,
			"switch_exit_position": Vector2(900, 400),
			"exit_position": Vector2(1100, 480),
			"player_spawn": Vector2(120, 480),
			"player_pos": Vector2(300, 480),
			"aim_dir": Vector2.RIGHT,
			"tracking": true,
			"enemy_positions": [Vector2(600, 480)],
		}
	var standalone_mini := Minimap2D.new()
	standalone_mini.set_snapshot_provider(mock_map_provider)
	root.add_child(standalone_mini)
	await process_frame
	_check(Minimap2D.bearing_text(Vector2.UP) == "000° N"
		and Minimap2D.bearing_text(Vector2.RIGHT) == "090° E"
		and Minimap2D.bearing_text(Vector2.DOWN) == "180° S"
		and Minimap2D.bearing_text(Vector2.LEFT) == "270° W"
		and Minimap2D.bearing_text(Vector2(1, -1)) == "045° NE",
		"Minimap2D computes accurate 360-degree tactical azimuth bearings")
	standalone_mini.configure("circle", 1.25, 1.8)
	_check(standalone_mini.map_shape == "circle"
		and is_equal_approx(standalone_mini.map_scale, 1.25)
		and is_equal_approx(standalone_mini.map_zoom, 1.8)
		and standalone_mini._clip_poly.polygon.size() >= 32,
		"Minimap2D switches to circular clipped radar with custom scale and zoom")
	_check(RunHUD2D._format_hint_bbcode("WASD 移动 · E 交互").contains("[color=#"),
		"RunHUD2D colorizes keybinds in tactical hint bar")
	var standalone_map := MapOverlay2D.new()
	standalone_map.set_snapshot_provider(mock_map_provider)
	root.add_child(standalone_map)
	await process_frame
	var map_events := {"opened": 0, "closed": 0}
	standalone_map.opened.connect(func() -> void: map_events["opened"] = int(map_events["opened"]) + 1)
	standalone_map.closed.connect(func() -> void: map_events["closed"] = int(map_events["closed"]) + 1)
	standalone_map.open()
	await process_frame
	_check(standalone_map.visible and int(map_events["opened"]) == 1,
		"standalone MapOverlay2D renders from snapshot_provider and emits opened")
	standalone_map.close()
	_check(not standalone_map.visible and int(map_events["closed"]) == 1 and not paused,
		"standalone MapOverlay2D emits closed and unpauses cleanly")
	standalone_mini.queue_free()
	standalone_map.queue_free()
	await process_frame

	# 4) Main2D 实机验证：快照只读隔离 + 浮层信号显隐 HUD/准心 + 5 个行动事件信号
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	_check(main.has_signal("shot_fired") and main.has_signal("hit_resolved")
		and main.has_signal("loot_gained") and main.has_signal("wave_changed")
		and main.has_signal("run_finished"),
		"Main2D exposes all 5 action event signals")

	# 只读快照防御性拷贝验证
	main._add_loot(&"parts", 3)
	var loot_snap: Dictionary = main.get_loot_snapshot()
	(loot_snap["basic"] as Dictionary)["parts"] = 999
	_check(int(main.loot.get("parts", 0)) == 3,
		"get_loot_snapshot() returns a defensive copy that does not mutate Main2D.loot")
	var map_snap: Dictionary = main.get_map_snapshot()
	_check(map_snap.has("map_size") and map_snap.has("player_pos")
		and map_snap.has("enemy_positions") and map_snap.has("rooms"),
		"get_map_snapshot() provides complete read-only map snapshot")

	# 浮层打开/关闭经信号联动隐藏/恢复 HUD 与准心
	main.map_overlay.open()
	_check(not main.hud.visible and not main.reticle.visible,
		"map_overlay.opened hides HUD and reticle via signal")
	main.map_overlay.close()
	_check(main.hud.visible and main.reticle.visible,
		"map_overlay.closed restores HUD and reticle via signal")
	main.backpack.open()
	_check(not main.hud.visible and not main.reticle.visible,
		"backpack.opened hides HUD and reticle via signal")
	main.backpack.close()
	_check(main.hud.visible and main.reticle.visible,
		"backpack.closed restores HUD and reticle via signal")

	# 监听 5 个事件信号
	var ev := {
		"shots": 0, "shot_weapon": &"", "shot_pellets": 0,
		"hits": 0, "hit_dmg": 0.0, "hit_mat": "",
		"loots": 0, "last_adv": false,
		"waves": [],
		"finished": 0, "fin_ok": false, "fin_shots": -1,
	}
	main.shot_fired.connect(func(wid: StringName, _aid: StringName, pellets: int) -> void:
		ev["shots"] = int(ev["shots"]) + 1
		ev["shot_weapon"] = wid
		ev["shot_pellets"] = pellets
	)
	main.hit_resolved.connect(func(_t: Node, dmg: float, _k: bool, mat: String) -> void:
		ev["hits"] = int(ev["hits"]) + 1
		ev["hit_dmg"] = dmg
		ev["hit_mat"] = mat
	)
	main.loot_gained.connect(func(_id: StringName, _amt: int, is_adv: bool) -> void:
		ev["loots"] = int(ev["loots"]) + 1
		ev["last_adv"] = is_adv
	)
	main.wave_changed.connect(func(w: int, state: String) -> void:
		(ev["waves"] as Array).append("%d:%s" % [w, state])
	)
	main.run_finished.connect(func(ok: bool, stats: Dictionary) -> void:
		ev["finished"] = int(ev["finished"]) + 1
		ev["fin_ok"] = ok
		ev["fin_shots"] = int(stats.get("shots", -1))
	)

	# 触发 loot_gained（基础 + 进阶）
	main._add_loot(&"electronics", 2)
	main._add_loot(&"electronic_core", 1)
	_check(int(ev["loots"]) == 2 and bool(ev["last_adv"]),
		"loot_gained emits for both basic and advanced items")

	# 触发 shot_fired & hit_resolved
	for e in main.enemies:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.global_position = Vector2(-2000, -2000)
	main.doll.global_position = Vector2(46.0, 36.0) * 64.0
	var dummy := Enemy2D.new()
	dummy.setup(&"rifleman", main.doll.global_position + Vector2(220, 0), 1)
	main.sort_layer.add_child(dummy)
	dummy.set_physics_process(false)
	dummy.hp = 200.0
	dummy.hp_max = 200.0
	main.doll.equip_weapon_id(&"g17")
	await physics_frame
	main.doll.weapon_rig.data.base_spread = 0.0
	main.current_ammo().spread = 0.0
	main.doll.aim_target = dummy.body_center()
	for i in 8:
		await physics_frame
	main.doll.weapon_rig.try_fire()
	for i in 20:
		await physics_frame
	_check(int(ev["shots"]) == 1 and ev["shot_weapon"] == &"g17" and int(ev["shot_pellets"]) == 1,
		"shot_fired emits with weapon id and pellet count")
	_check(int(ev["hits"]) == 1 and float(ev["hit_dmg"]) > 0.0 and String(ev["hit_mat"]) == "flesh",
		"hit_resolved emits with damage and hit material (dmg=%.1f)" % float(ev["hit_dmg"]))

	# 触发 wave_changed（started + cleared）
	main.waves_mode = true
	main._begin_wave(1)
	main._on_wave_cleared()
	var wave_log: Array = ev["waves"]
	_check(wave_log.has("1:started") and wave_log.has("1:cleared"),
		"wave_changed emits started and cleared states (%s)" % str(wave_log))

	# 触发 run_finished
	main.waves_mode = false
	main._finish_run(true)
	_check(int(ev["finished"]) == 1 and bool(ev["fin_ok"]) and int(ev["fin_shots"]) >= 1,
		"run_finished emits success flag and combat stats")

	main.queue_free()
	await process_frame
	p.reset_for_test()
	print("=== run_events_hud_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
