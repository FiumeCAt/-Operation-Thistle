extends SceneTree
## 一次性工具：抓取当前构建的完整流程截图，用于立项书 / 展示材料。
## 运行（需要窗口渲染，不能加 --headless）：
##   godot --path . --script res://tests/demo_capture_test.gd

const OUT_DIR := "D:/AI Game/temp_20261027_01/demo_shots"
const TITLE_MENU := "res://scripts/ui/TitleMenu.gd"

var _main: Node3D
var _shot_index := 0

func _initialize() -> void:
	call_deferred("_run")

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%02d_%s.png" % [OUT_DIR, _shot_index, name]
	var err := img.save_png(path)
	print("[demo_shot] %s err=%s size=%s" % [path, err, str(img.get_size())])
	_shot_index += 1

func _disable_enemies() -> void:
	for enemy in get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("=== Operation Thistle demo capture ===")

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene

	# 01 启动界面
	var menu = load(TITLE_MENU).new()
	_main.add_child(menu)
	await _frames(8)
	await _shot("menu")
	menu.free()

	# 02 战前基地
	_main.level.visible = false
	_main.doll.visible = false
	_main._build_base()
	_main.return_to_base()
	await _frames(10)
	await _shot("base")

	# 03 行动开始
	_main.start_expedition()
	await _frames(5)
	while not _main._run_ready:
		await physics_frame
	await _frames(20)
	_main.run_hud._set_hints(false)
	_disable_enemies()
	_main.rig.pitch_deg = 66.0
	_main.rig.distance = 14.0
	_main.doll.global_position = _main.level.player_spawn
	_main.doll.aim_point = _main.doll.global_position + Vector3(8, 1.0, 0)
	await _frames(20)
	await _shot("run_start")

	# 04 战斗与开火（走廊，敌人位于正前方）
	var enemies := get_nodes_in_group("enemies")
	_main.doll.global_position = Vector3(22.0, 0.02, 0.0)
	_main.doll.aim_point = Vector3(30.0, 1.0, 0.0)
	for i in mini(2, enemies.size()):
		enemies[i].global_position = Vector3(27.0 + float(i) * 1.2, 0.02, -1.6 + float(i) * 3.2)
	await _frames(20)
	_main.doll.weapon.apply_loadout(true)
	_main.doll.weapon.try_fire()
	await _frames(1)
	await _shot("combat")

	# 05 信息战：手电 + 手枪枪声细线 + 方向弧
	await _frames(40)
	_main.doll.weapon.switch_to(&"g17")
	await _frames(4)
	_main.doll.set_flashlight(true)
	var near: Enemy = enemies[0]
	_main.doll.global_position = Vector3(30.0, 0.02, 0.0)
	_main.doll.aim_point = Vector3(38.0, 1.0, 0.0)
	near.global_position = _main.doll.global_position + Vector3(6.0, 0.0, 1.0)
	near.velocity = Vector3(2.0, 0.0, 0.0)
	await _frames(16)
	_main.doll.weapon.try_fire()
	await _frames(8)
	await _shot("info_warfare")

	# 06 房间：军械库内景（相机贴近房间中心）
	var armory: Dictionary = _main.level.rooms[0]
	var acenter: Vector3 = armory["center"]
	_main.doll.global_position = acenter
	_main.doll.aim_point = acenter + Vector3(0, 1, -4)
	_main.rig.pitch_deg = 42.0
	_main.rig.distance = 15.0
	_main.rig.fov = 44.0
	_main.rig.global_position = Vector3(acenter.x, 0.0, acenter.z)
	_main.rig.rotation.y = 0.0
	await _frames(20)
	await _shot("room")

	# 07 搜刮反馈
	_main.rig.pitch_deg = 66.0
	_main.rig.distance = 14.0
	_main.rig.fov = 34.0
	var box: StaticBody3D = _main.level.search_containers[0]
	_main.doll.global_position = box.global_position + Vector3(-1.5, 0.02, 0)
	_main.doll.aim_point = box.global_position + Vector3(0, 1, 0)
	await _frames(16)
	_main.try_interact()
	await _frames(3)
	await _shot("loot")

	# 08 低血量 HUD
	_main.doll.hp = 24.0
	await _frames(6)
	await _shot("low_hp")
	_main.doll.hp = _main.doll.hp_max

	# 08 敌人阵容（含声呐猎手）
	_main.doll.global_position = Vector3(38.0, 0.02, 0.0)
	_main.doll.aim_point = Vector3(48.0, 1.0, 0.0)
	_main.rig.pitch_deg = 66.0
	_main.rig.distance = 14.0
	_main.rig.fov = 34.0
	var lineup := [[&"rifleman", -2.6], [&"rusher", 0.0], [&"heavy", 2.8], [&"hunter", -4.9]]
	for pair in lineup:
		var unit: Enemy = _main.spawn_enemy(pair[0], Vector3(44.0, 0.0, pair[1]))
		unit.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(16)
	_main.doll.set_flashlight(true)
	await _frames(10)
	await _shot("enemies")

	# 09 竖井面板
	_main.resources = 12
	_main.doll.global_position = _main.level.exit_position
	_main.rig.global_position = Vector3(_main.level.exit_position.x, 0.0, _main.level.exit_position.z)
	await _frames(14)
	_main.open_shaft()
	await _frames(6)
	await _shot("shaft")
	_main.cancel_shaft()
	await _frames(4)

	# 10 撤离结算
	_main.resources = 12
	_main.doll.global_position = _main.level.exit_position
	await _frames(8)
	_main.finish_run(true)
	await _frames(6)
	await _shot("result")

	# 11 成长面板
	_main.restart_run()
	await _frames(6)
	_main.run_hud._show_growth(false)
	await _frames(6)
	await _shot("growth")

	print("=== demo capture done ===")
	quit(0)
