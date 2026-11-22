extends SceneTree
## 临时截图：小地图、ADS 方向前探、滚轮 20/100/200% 缩放、撤离返回基地面板。
## godot --path . --script res://tests/_capture_features.gd -- --save-path user://capture_features.json

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_features"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.camera.position_smoothing_enabled = false
	main.doll.global_position = Vector2(60, 21) * 64.0
	for i in 30:
		await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)

	await _shot("screenshots/ui_minimap.png")

	# 背包：左侧拾取信息流 + TAB 面板（本局拾取 / 仓库）
	main.loot = {"electronics": 2, "energy": 1, "parts": 3}
	main.advanced_loot = {"electronic_core": 1}
	main.resources = 7
	p.data["resources"] = 120
	p.data["materials_2d"] = {"electronics": 5, "energy": 4, "parts": 8}
	p.data["advanced_2d"] = {
		"weapon_parts": 1, "electronic_core": 2,
		"high_energy_cell": 0, "military_alloy": 3,
	}
	main.hud.push_pickup("+3 机械零件", ResourceDB.color_of(&"parts"))
	main.hud.push_pickup("+1 电子核心", ResourceDB.color_of(&"electronic_core"))
	main.backpack.open()
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_backpack.png")
	main.backpack.close()
	for i in 5:
		await process_frame

	# ADS：视线朝右，镜头向瞄准方向前探。
	Input.warp_mouse(Vector2(1320, 450))
	Input.action_press("aim")
	for i in 45:
		await physics_frame
	await _shot("screenshots/ads_look_100.png")

	main._set_view_zoom(200.0)
	for i in 45:
		await process_frame
	await _shot("screenshots/ads_look_200.png")

	main._set_view_zoom(20.0)
	for i in 45:
		await process_frame
	await _shot("screenshots/ads_look_020.png")

	main._set_view_zoom(100.0)
	Input.warp_mouse(Vector2(800, 120))
	for i in 45:
		await physics_frame
	await _shot("screenshots/ads_look_up.png")
	Input.action_release("aim")
	for i in 30:
		await process_frame

	main.loot = {"electronics": 2, "energy": 1, "parts": 1}
	main.resources = 4
	main.level.set_power_on(true)
	main._finish_run(true, true)
	for i in 10:
		await process_frame
	await _shot("screenshots/ui_result_return.png")

	print("features capture done")
	quit()
