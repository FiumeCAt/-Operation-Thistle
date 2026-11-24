extends SceneTree
## 俯视 2D 像素场景测试：格子地图、四向角色、碰撞、相机。
## 运行：Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/stage1_2d_test.gd

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
	print("=== top-down pixel 2D test ===")

	_check(
		ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/StartMenu2D.tscn",
		"project boots into StartMenu2D.tscn"
	)
	_check(not ResourceLoader.exists("res://scenes/core/Main.tscn"), "legacy 3D Main.tscn removed")

	var packed: PackedScene = load("res://scenes/core/Main2D.tscn")
	_check(packed != null, "Main2D.tscn loads")
	if packed == null:
		quit(1)
		return

	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await physics_frame
	await process_frame

	_check(main is Node2D, "root is Node2D, got %s" % main.get_class())
	_check(not _has_node3d(main), "scene contains no Node3D")

	var world: Node2D = main.get_node_or_null("World2D")
	_check(world != null and world.y_sort_enabled, "World2D enables y-sort")
	var sort_layer: Node2D = main.get_node_or_null("World2D/SortLayer")
	_check(sort_layer != null and sort_layer.y_sort_enabled, "SortLayer enables y-sort")
	var floor_layer: Node2D = main.get_node_or_null("World2D/FloorLayer")
	_check(floor_layer != null and floor_layer.z_index < -50, "FloorLayer draws behind actors")

	var level: Level2D = main.get_node_or_null("Level2D")
	_check(level != null, "Level2D exists")
	if level == null:
		quit(1)
		return
	_check(level.rooms.size() == 20, "level generates 20 rooms")
	_check(is_equal_approx(level.map_size().x, 11264.0), "map width matches the 176-tile layout")
	_check(level.doors.size() == 25 and level.containers.size() == 52,
		"twenty main doors + five side doors and 52 searchables")
	_check(level.enemy_spawns.size() >= 8, "enemy spawns generated, got %d" % level.enemy_spawns.size())
	_check(main.enemies.size() == level.enemy_spawns.size(), "enemies spawned for every spawn point")
	_check(main.run_state == 0 and main.resources == 0, "run starts in the active state")

	var walls := 0
	for child in sort_layer.get_children():
		if child is StaticBody2D:
			walls += 1
	_check(walls >= 30, "walls and props built, got %d" % walls)

	var doll: Doll2D = main.get_node_or_null("World2D/SortLayer/Doll2D")
	_check(doll != null, "Doll2D exists")
	if doll == null:
		quit(1)
		return
	_check(doll is CharacterBody2D, "player is CharacterBody2D")
	_check(doll.collision_layer == 2 and doll.collision_mask == 1, "player collision layer/mask")
	_check(doll.get_node("Body").offset == Vector2(0, -doll.frame_size.y * 0.45), "sprite anchored at feet")
	var body: AnimatedSprite2D = doll.get_node("Body")
	var frames: SpriteFrames = body.sprite_frames
	_check(frames != null, "walk frames built")
	if frames != null:
		var directions_ok := true
		for row in 4:
			var name := "walk_%d" % row
			if not frames.has_animation(name) or frames.get_frame_count(name) != 4:
				directions_ok = false
		_check(directions_ok, "4 direction walk animations with 4 frames each")
		_check(not frames.has_animation("walk_4"), "no extra directions beyond 4")
		var idle_run_ok := true
		for row in 4:
			for prefix in ["idle", "run"]:
				var anim := "%s_%d" % [prefix, row]
				if not frames.has_animation(anim) or frames.get_frame_count(anim) != 4:
					idle_run_ok = false
		_check(idle_run_ok, "idle and run animations exist for all 4 directions")

	# ---- 模块化：无头身体 + 独立头部层 + 背后武器挂点
	var head_pivot: Node2D = doll.get_node_or_null("Body/HeadPivot")
	var head: Sprite2D = doll.get_node_or_null("Body/HeadPivot/Head")
	_check(head_pivot != null and head != null, "head is a separate modular layer")
	_check(head != null and head.texture != null, "head layer has a texture from the current frame")
	var body_atlas: AtlasTexture = body.sprite_frames.get_frame_texture("idle_0", 0)
	_check(
		body_atlas != null and body_atlas.atlas.resource_path.ends_with("doll_lod_256_body.png"),
		"body sprite uses the headless sheet"
	)
	var head_atlas: AtlasTexture = head.texture
	_check(
		head_atlas != null and head_atlas.atlas.resource_path.ends_with("doll_lod_256_head.png"),
		"head layer uses the separate head sheet"
	)
	_check(doll.rig == null, "atlas rendering is the default, rig only via --rig=")

	# 跑步正面：四帧里踩地的那只脚必须左右交替，不能一直用同一只脚
	# 直接读磁盘上的无头图集，避免 headless 下 GPU 纹理取不到像素。
	var run_img := Image.load_from_file(
		ProjectSettings.globalize_path("res://assets/art/characters/doll_b/lod/doll_lod_256_body.png"))
	var fsize: Vector2i = doll.frame_size
	var sides := {}
	if not run_img.is_empty():
		for col in 4:
			var contact_x := 0.0
			var contact_n := 0
			for y in range(fsize.y - 18, fsize.y):
				for x in range(fsize.x):
					if run_img.get_pixel(col * fsize.x + x, 8 * fsize.y + y).a > 0.1:
						contact_x += x
						contact_n += 1
			if contact_n > 0:
				sides[contact_x / contact_n < fsize.x * 0.5] = true
	_check(sides.size() == 2, "run cycle alternates the planted foot")
	var mount: Node2D = doll.get_node_or_null("WeaponMount")
	_check(mount != null, "weapon mount node exists")
	var mount_before := mount.position if mount != null else Vector2.ZERO

	doll.aim_enabled = true
	main.mouse_aim_enabled = false
	doll.aim_target = doll.global_position + Vector2(200, 0)
	for i in 20:
		await physics_frame
	var tilt_right := head_pivot.rotation if head_pivot != null else 0.0
	if Doll2D.HEAD_MOTION_ENABLED:
		_check(tilt_right > 0.01, "head tilts toward right aim, rot=%.3f" % tilt_right)
	else:
		_check(is_zero_approx(tilt_right), "head stays locked on right aim while HEAD_MOTION_ENABLED=false, rot=%.3f" % tilt_right)
	doll.aim_target = doll.global_position + Vector2(-200, 0)
	for i in 20:
		await physics_frame
	var tilt_left := head_pivot.rotation if head_pivot != null else 0.0
	if Doll2D.HEAD_MOTION_ENABLED:
		_check(tilt_left < -0.01, "head tilts toward left aim, rot=%.3f" % tilt_left)
	else:
		_check(is_zero_approx(tilt_left), "head stays locked on left aim while HEAD_MOTION_ENABLED=false, rot=%.3f" % tilt_left)

	var dummy := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	doll.equip_weapon(dummy)
	_check(mount != null and mount.get_node_or_null("Weapon") != null, "weapon can be equipped on the back mount")
	# 站定瞄准时身体会朝瞄准方向；先朝右站定，再往左走，移动过程中挂点应转向左侧
	doll.aim_target = doll.global_position + Vector2(200, 0)
	for i in 10:
		await physics_frame
	mount_before = mount.position if mount != null else Vector2.ZERO
	Input.action_press("move_left")
	for i in 10:
		await physics_frame
	var mount_walking := mount.position if mount != null else Vector2.ZERO
	Input.action_release("move_left")
	await physics_frame
	_check(mount_walking.distance_to(mount_before) > 1.0, "mount anchor follows facing direction")
	doll.unequip_weapon()
	doll.aim_enabled = false

	var camera: Camera2D = main.get_node_or_null("Camera2D")
	_check(camera != null, "Camera2D exists")
	_check(camera != null and camera.position_smoothing_enabled, "camera uses smoothing")
	_check(
		camera != null and is_equal_approx(camera.zoom.x, main.ZOOM),
		"camera zoom matches Main2D.ZOOM (%.2f), got %.2f" % [main.ZOOM, camera.zoom.x if camera != null else 0.0]
	)
	_check(camera != null and camera.limit_right == 10816 and camera.limit_bottom == 7104, "camera limited to the level")

	# ---- 移动与朝向
	var start_x: float = doll.global_position.x
	Input.action_press("move_right")
	for i in 12:
		await physics_frame
	Input.action_release("move_right")
	await physics_frame
	_check(doll.global_position.x > start_x + 10.0, "player moves right, dx=%.1f" % (doll.global_position.x - start_x))
	_check(doll.direction == 3, "right movement selects east frames, got %d" % doll.direction)

	Input.action_press("move_forward")
	for i in 6:
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	_check(doll.direction == 1, "upward movement selects north frames, got %d" % doll.direction)

	# ---- 走廊北墙阻挡：从走廊向上走，应被房间隔墙挡住
	doll.global_position = Vector2(300, 864)
	Input.action_press("move_forward")
	for i in 40:
		await physics_frame
	Input.action_release("move_forward")
	await physics_frame
	_check(doll.global_position.y > 690.0, "corridor wall blocks movement, y=%.1f" % doll.global_position.y)

	# ---- 边界限制
	doll.global_position = Vector2(90, 864)
	Input.action_press("move_left")
	for i in 24:
		await physics_frame
	Input.action_release("move_left")
	await physics_frame
	_check(doll.global_position.x >= 39.0, "player stays inside the level bounds, x=%.1f" % doll.global_position.x)

	# ---- 调试照明
	var overlay: CanvasLayer = main.get_node_or_null("DebugOverlay2D")
	var modulate: CanvasModulate = main.get_node_or_null("World2D/CanvasModulate")
	_check(overlay != null and not overlay.visible, "debug overlay hidden by default")
	main.debug_visual_mode = true
	main._apply_debug_visual_mode()
	await process_frame
	_check(overlay.visible, "debug overlay toggles on")
	_check(modulate.color.r >= 1.0, "debug mode lifts tint")
	main.debug_visual_mode = false
	main._apply_debug_visual_mode()

	print("=== top-down result: %s (%d ok / %d fail) ===" % ["PASS" if _fails == 0 else "%d FAIL" % _fails, _ok, _fails])
	quit(0 if _fails == 0 else 1)

func _has_node3d(node: Node) -> bool:
	if node is Node3D:
		return true
	for child in node.get_children():
		if _has_node3d(child):
			return true
	return false
