extends SceneTree
## 部署回归：出生点选择、默认撤离点、安全区不刷怪。
## godot --headless --path . --script res://tests/deployment_2d_test.gd

var _pass := 0
var _fail := 0
var _confirmed_spawn: StringName
var _confirmed_exit: StringName


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
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.deployment != null and not menu.deployment.visible, "deployment menu exists")
	menu._start()
	await process_frame
	_check(menu.deployment.visible, "start opens deployment instead of the run")
	menu.deployment.close_menu()
	menu.queue_free()
	await process_frame

	var dm := DeploymentMenu2D.new()
	root.add_child(dm)
	dm.open()
	await process_frame
	_check(dm.visible and dm._spawn_buttons.size() == 2, "two spawn points available")
	_check(dm._spawn_name.text.contains("装卸区"), "insertion selected by default")
	_check(dm._default_exit.text.contains("东侧闸门"), "insertion defaults to the east gate")
	dm._select(&"abandoned")
	_check(dm._spawn_name.text.contains("废弃仓"), "abandoned warehouse can be selected")
	_check(dm._default_exit.text.contains("南侧维修门"), "abandoned defaults to the south gate")
	_check(dm._safe_zone.text.contains("废弃仓") and dm._safe_zone.text.contains("医疗站"),
		"safe zone lists nearby rooms")
	dm.deploy_confirmed.connect(func(spawn_id: StringName, extract_id: StringName) -> void:
		_confirmed_spawn = spawn_id
		_confirmed_exit = extract_id)
	dm._confirm()
	_check(_confirmed_spawn == &"abandoned" and _confirmed_exit == &"south",
		"deployment emits the chosen spawn and default extraction")

	# 浪潮地图选择：歌利亚狂潮隐藏出生点列表，确认时使用固定部署。
	dm.set_mode("waves")
	dm.open()
	await process_frame
	_check(dm._map_row.visible, "waves mode shows the map selector")
	dm._select_map("goliath_arena")
	_check(dm.selected_map_id == "goliath_arena" and not dm._spawn_list.visible,
		"goliath arena uses fixed deployment")
	dm._confirm()
	_check(_confirmed_spawn == &"insertion" and _confirmed_exit == &"east",
		"goliath arena confirms with the fixed deployment")
	p.set_run_mode("raid")
	p.set_map_id("facility")
	dm.queue_free()
	await process_frame

	# 选择废弃仓出生后，地图应从废弃仓开局并默认南侧撤离。
	p.set_deployment(&"abandoned", &"south")
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	var level: Level2D = main.level
	_check(level.spawn_id == &"abandoned" and level.extract_id == &"south",
		"level reads the selected deployment")
	_check((level.rooms[8]["rect"] as Rect2).has_point(level.player_spawn),
		"player spawns inside the abandoned warehouse")
	_check((level.rooms[10]["rect"] as Rect2).has_point(level.exit_position),
		"default extraction is the south gate")
	_check(level.exits.size() == 2, "both extraction points stay available")

	var control_enemy := false
	var control_rect: Rect2 = level.rooms[2]["rect"]
	for pos in level.enemy_spawns:
		if control_rect.has_point(pos):
			control_enemy = true
	_check(not control_enemy, "medical station near the spawn is safe")

	var close_enemy := false
	for pos in level.enemy_spawns:
		if pos.distance_to(level.player_spawn) < 16.0 * Level2D.TILE:
			close_enemy = true
	_check(not close_enemy, "no enemies spawn within 16 tiles of the insertion point")

	main.queue_free()
	await process_frame
	print("\n=== deployment 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
