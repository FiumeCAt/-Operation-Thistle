extends SceneTree
## 临时截图：验证新容器贴图在游戏内的比例、落地位置与开箱切换。
## godot --path . --script res://tests/_capture_containers.gd

const NEW_ARTS: Array[StringName] = [
	&"ammo_can", &"medbag_pro", &"pc_military",
	&"drawer_steel", &"supplycrate_large", &"case_trolley_green",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 30:
		await process_frame

	main.set_process(false)
	main.set_physics_process(false)

	var by_art := {}
	for entry in main.level.containers:
		by_art[StringName(entry.get("art", &"weapon_crate"))] = entry

	for art in NEW_ARTS:
		await _shot(main, by_art[art], "cont2_%s" % art)
	for art in NEW_ARTS:
		main._search_container(by_art[art])
		await _shot(main, by_art[art], "cont2_%s_open" % art)

	print("container capture done")
	quit()


func _shot(main, entry: Dictionary, name: String) -> void:
	var pos: Vector2 = entry["position"]
	main.doll.global_position = pos + Vector2(-78, 26)
	var camera: Camera2D = main.camera
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(2.2, 2.2)
	camera.global_position = pos + Vector2(0, -30)
	camera.reset_smoothing()
	await process_frame
	# 主循环被暂停，手动刷新一次交互提示的显隐。
	main._update_hud(0.0)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/%s.png" % name)
