extends SceneTree
## 视野系统：120° 总视野、80° 主视野、敌人视野外隐藏、开门揭示房间、玩家主动开门 / 敌人自动开门。

var _main: Node3D
var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	print("=== Operation Thistle vision test ===")
	create_timer(90.0).timeout.connect(func() -> void: quit(2))

	_check(is_equal_approx(VisionCone.alpha_for_angle(0.0), 0.0), "正前方完全清晰")
	_check(is_equal_approx(VisionCone.alpha_for_angle(40.0), 0.0), "80° 主视野边缘仍然清晰")
	_check(is_equal_approx(VisionCone.alpha_for_angle(60.0), VisionCone.MAX_ALPHA), "120° 边缘完全压暗")
	var mid := VisionCone.alpha_for_angle(50.0)
	_check(mid > 0.0 and mid < VisionCone.MAX_ALPHA, "40°–60° 之间为渐变")
	_check(is_equal_approx(VisionCone.alpha_for_angle(180.0), VisionCone.MAX_ALPHA), "背后完全压暗")

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var doll: Doll = _main.doll
	_check(_main.vision_cone != null and _main.vision_cone.visible, "行动中启用视野遮罩")
	_check(doll.billboard.body.billboard == 2, "玩家立绘使用固定 Y")
	_check(not doll.billboard.body.no_depth_test, "玩家立绘遵守场景深度遮挡")
	var original_fog: bool = _main.get_node("WorldEnvironment").environment.fog_enabled
	_main.debug_visual_mode = true
	_main._apply_debug_visual_mode()
	_check(not _main.vision_cone.visible, "调试视觉模式关闭视野黑暗遮罩")
	_check(not _main.screen_vignette.visible and not _main.health_vignette.visible, "调试视觉模式关闭屏幕暗角")
	_check(not _main.get_node("PixelGrade").visible, "调试视觉模式关闭像素后处理")
	_check(not _main.get_node("WorldEnvironment").environment.fog_enabled, "调试视觉模式关闭场景雾")
	_main.debug_visual_mode = false
	_main._apply_debug_visual_mode()
	_check(_main.vision_cone.visible and _main.get_node("WorldEnvironment").environment.fog_enabled == original_fog, "退出调试模式恢复常规视觉")

	var enemy := Enemy.new()
	_main.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.setup(doll, &"rusher")
	await _frames(2)

	doll.global_position = Vector3(0, 0.02, 0)
	doll.debug_set_facing(0.0)
	enemy.global_position = Vector3(0, 0, 6)
	enemy._update_visibility()
	_check(enemy.visible and is_equal_approx(enemy.sprite.modulate.a, 1.0), "正前方敌人可见")

	enemy.global_position = Vector3(0, 0, -6)
	enemy._update_visibility()
	_check(not enemy.visible, "背后敌人完全隐藏")

	var side := Vector3(sin(deg_to_rad(50.0)), 0.0, cos(deg_to_rad(50.0))) * 6.0
	enemy.global_position = side
	enemy._update_visibility()
	var side_alpha := enemy.sprite.modulate.a
	_check(enemy.visible and side_alpha > 0.0 and side_alpha < 1.0, "50° 附近敌人随渐变淡出：%.2f" % side_alpha)

	enemy.global_position = Vector3(0, 0, 13.0)
	enemy._update_visibility()
	_check(not enemy.visible, "视距 12m 外敌人隐藏")

	enemy.global_position = Vector3(0, 0, -6)
	enemy.velocity = Vector3(2.0, 0.0, 0.0)
	await _frames(20)
	var lit := 0
	for arc in _main.hearing_indicator._arcs:
		if arc.visible:
			lit += 1
	_check(lit > 0, "视野外敌人仍显示声纹")
	enemy.free()

	# ---- 开门揭示未知房间
	var level := LevelGenerator.new()
	level.level_seed = 6161
	level.depth = 1
	root.add_child(level)
	await _frames(8)
	_check(not level.explored.has(0), "房间初始未知")
	var door := level.doors[0] as AutoDoor
	door.set_open(true)
	_check(level.explored.has(0), "开门即记录探索")
	_check(not level.room_fog[0].visible, "开门后房间遮罩消失")
	_check(level.room_fog[1].visible, "未开门房间仍保持未知")

	# ---- 玩家透窗：参数应写入墙体材质，并只在遮挡时开启
	level.update_player_window(Vector2(100, 100), Vector2(1024, 576), 92.0, true)
	var window_mat: ShaderMaterial = level._window_materials.values()[0]
	_check(bool(window_mat.get_shader_parameter("player_window_enabled")), "玩家透窗开启参数写入墙体材质")
	level.update_player_window(Vector2.ZERO, Vector2(1024, 576), 92.0, false)
	_check(not bool(window_mat.get_shader_parameter("player_window_enabled")), "玩家透窗可关闭")

	# ---- 玩家必须主动开门，敌人靠近自动开门
	var tactics_door := level.doors[1] as AutoDoor
	_check(not tactics_door.is_open, "第二扇门初始关闭")

	var player_body := _dummy_actor(2)
	level.add_child(player_body)
	player_body.global_position = tactics_door.global_position + Vector3(0, 0, 1.8)
	await _frames(4)
	_check(not tactics_door.is_open, "玩家靠近不会自动开门")

	var enemy_body := _dummy_actor(8)
	level.add_child(enemy_body)
	enemy_body.global_position = tactics_door.global_position + Vector3(0, 0, -1.8)
	await _frames(4)
	_check(tactics_door.is_open, "敌人靠近自动开门")

	enemy_body.free()
	player_body.free()
	await _frames(6)
	_check(not tactics_door.is_open, "无人时门自动关闭")

	level.free()
	await _frames(2)

	# ---- 视野升级接线
	var progress := root.get_node_or_null("/root/Progress") as ProgressService
	progress.data["upgrades"]["fov"] = 4
	progress.data["upgrades"]["sight"] = 4
	_main._apply_persistent_upgrades()
	_check(is_equal_approx(doll.vision_total_half, 65.0), "视野角度 4 级 → 总角 130°")
	_check(is_equal_approx(doll.vision_range, 14.0), "视野范围 4 级 → 视距 14m")
	_check(is_equal_approx(_main.vision_cone.total_half, 65.0) and is_equal_approx(_main.vision_cone.range_m, 14.0), "升级后遮罩同步重建")
	_check(is_equal_approx(_main.vision_cone.clear_half, 40.0 + 10.0 / 3.0), "清晰区随总角同比例扩张")

	# ---- 玩家按 E 开门（取第一扇仍然关闭的门）
	var main_door: AutoDoor
	for node in _main.level.doors:
		if node is AutoDoor and not node.is_open:
			main_door = node
			break
	_check(main_door != null, "行动关卡存在关闭的门")
	if main_door != null:
		doll.global_position = main_door.global_position + Vector3(0, 0.02, 1.2)
		_check(_main._get_interaction_hint().begins_with("E 开门"), "靠近关闭的门提示 E 开门")
		_check(_main.try_interact() and main_door.is_open, "按 E 主动开门")

	print("=== VISION %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)

## 用于开门判定的占位角色：只有碰撞层，没有逻辑。
func _dummy_actor(layer: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	shape.position.y = 0.9
	body.add_child(shape)
	return body
