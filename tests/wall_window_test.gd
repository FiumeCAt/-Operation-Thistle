extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("[ok] ", message)

func _run() -> void:
	var main = load("res://scenes/core/Main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 10:
		await physics_frame
	main.set_process(false)
	main.set_physics_process(false)
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	main.doll.set_physics_process(false)
	main.rig.set_process(false)
	main.reticle.set_process(false)
	var level: LevelGenerator = main.level
	var reticle: AimReticle = main.reticle
	var rig: CameraRig = main.rig
	var material: ShaderMaterial = level._window_materials[level.mat_wall]
	check(level._window_materials.size() == 3, "仅墙、门框金属与建筑灯条使用窗口材质")
	check(material.get_shader_parameter("albedo_texture") == level.mat_wall.albedo_texture and material.get_shader_parameter("uv_scale") == level.mat_wall.uv1_scale, "墙贴图与三平面UV比例保留")
	check(material.get_shader_parameter("albedo") == level.mat_wall.albedo_color and is_equal_approx(material.get_shader_parameter("roughness"), level.mat_wall.roughness), "墙色与粗糙度保留")
	var wall_count := 0
	var floor_count := 0
	var prop_count := 0
	for body in level.get_children():
		if not body is StaticBody3D:
			continue
		for mesh in body.get_children():
			if not mesh is MeshInstance3D:
				continue
			if mesh.material_override is ShaderMaterial:
				wall_count += 1
				check(body.collision_layer == 1 and body.get_child(0) is CollisionShape3D, "建筑保留实体碰撞 %d" % wall_count)
				var shadow := mesh.get_node("WallShadow") as MeshInstance3D
				check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and shadow.material_override is StandardMaterial3D, "建筑原材质独立阴影 %d" % wall_count)
			elif mesh.material_override == level.mat_floor or mesh.material_override == level.mat_room_floor:
				floor_count += 1
			elif mesh.material_override == level.mat_metal:
				prop_count += 1
	check(wall_count > 20 and floor_count > 0 and prop_count > 0, "墙门框覆盖且地板箱子不挖洞")
	check(level.nav_region.navigation_mesh.get_polygon_count() > 0, "实体碰撞导航仍有可走多边形")
	rig.orbit_dragging = true
	rig._orbit_mouse = Vector2(1050, 620)
	reticle._process(0.016)
	check(material.get_shader_parameter("window_enabled") and material.get_shader_parameter("window_center") == reticle._view.center and reticle._view.center == rig._orbit_mouse, "中键锁存准心与圆窗完全同源")
	check(material.get_shader_parameter("logical_size") == root.get_visible_rect().size and is_equal_approx(material.get_shader_parameter("window_radius"), 120.0), "逻辑视口尺寸和120px半径传入shader")
	var query := PhysicsRayQueryParameters3D.create(Vector3(4, 1.1, 0), Vector3(4, 1.1, 6), 1)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and absf(hit.position.z - 3.0) < 0.01, "圆窗开启仍在原墙面阻挡弹道与视线射线")
	reticle._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not material.get_shader_parameter("window_enabled"), "失焦立即关闭圆窗")
	reticle._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	reticle._process(0.016)
	check(material.get_shader_parameter("window_enabled"), "恢复焦点重新开启")
	paused = true
	check(not material.get_shader_parameter("window_enabled"), "暂停通知立即关闭圆窗")
	paused = false
	reticle._process(0.016)
	reticle.hide()
	reticle._process(0.016)
	check(not material.get_shader_parameter("window_enabled"), "隐藏准心关闭圆窗")
	reticle.show()
	var args := OS.get_cmdline_user_args()
	if args.has("--capture") and DisplayServer.get_name() != "headless":
		var folder := args[args.find("--capture") + 1]
		main.motion_blur.set_enabled(false)
		main.hud.hide()
		var enemy: Enemy = main.spawn_enemy(&"rifleman", Vector3(4.0, 0.02, 1.6))
		enemy.set_physics_process(false)
		rig.rotation.y = 0.0
		rig.global_position = Vector3(4.0, 0, 0)
		rig.cam.position = Vector3(0, 0, 12)
		rig.orbit_dragging = true
		rig._orbit_mouse = rig.cam.unproject_position(enemy.global_position + Vector3.UP * 1.1)
		reticle._process(0.016)
		var images: Array[Image] = []
		for enabled in [false, true]:
			reticle._update_wall_window(enabled)
			for i in 4:
				await process_frame
				# 捕获夹具固定窗口状态，不依赖桌面焦点切换时序。
				reticle._update_wall_window(enabled)
				await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			images.append(image)
			check(image.save_png(folder.path_join("wall_window_%s.png" % ("on" if enabled else "off"))) == OK, "窗口渲染截图保存")
		var changed := 0
		var outside := 0
		var logical := root.get_visible_rect().size
		for y in images[0].get_height():
			for x in images[0].get_width():
				var a := images[0].get_pixel(x, y)
				var b := images[1].get_pixel(x, y)
				if Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > 0.08:
					var p := Vector2(x, y) * logical / Vector2(images[0].get_size())
					if p.distance_to(reticle._pos) < 122:
						changed += 1
					else:
						outside += 1
		check(changed > 1000, "真实渲染圆内墙体消失露出后方空间")
		check(outside < 100, "圆外建筑与阴影没有随窗口消失")
		print("[render] changed inside=", changed, " outside=", outside)
	main.finish_run(false)
	check(not material.get_shader_parameter("window_enabled"), "结算关闭圆窗")
	paused = false
	print("WALL WINDOW TEST: %d checks, %d failures" % [checks, failures])
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
