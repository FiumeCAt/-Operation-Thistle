extends SceneTree
## 临时截图：K-17 环形设施全景、出生点、控制室供电台、军械库货运电梯。
## godot --path . --script res://tests/_capture_map.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.data["resources"] = 40
	main_shot()


func main_shot() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 30:
		await process_frame

	# 全景：暂停主循环让相机停在整图中心。
	main.set_process(false)
	main.set_physics_process(false)
	main.hud.visible = false
	main.reticle.visible = false
	var camera: Camera2D = main.camera
	# 全景需要看整张图，临时放开设施相机边界。
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(main.level.map_size().x)
	camera.limit_bottom = int(main.level.map_size().y)
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(0.12, 0.12)
	camera.global_position = main.level.map_size() * 0.5
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_overview.png")

	# 出生点
	main.hud.visible = true
	main.reticle.visible = true
	camera.zoom = Vector2(1.9, 1.9)
	camera.global_position = main.level.player_spawn + Vector2(0, -44)
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_spawn.png")

	# 控制室供电台
	main.doll.global_position = main.level.power_position + Vector2(0, -80)
	camera.global_position = main.doll.global_position + Vector2(0, -44)
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_control.png")

	# 已供电的军械库货运电梯
	main.level.set_power_on(true)
	main.doll.global_position = main.level.switch_exit_position + Vector2(0, 110)
	camera.global_position = main.doll.global_position + Vector2(0, -44)
	camera.reset_smoothing()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_lift.png")

	# 主装配大厅与中央走廊
	var hall: Rect2 = main.level.rooms[19]["rect"]
	main.doll.global_position = hall.get_center() + Vector2(0, 120)
	camera.zoom = Vector2(1.9, 1.9)
	camera.global_position = main.doll.global_position + Vector2(0, -60)
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_hall.png")

	# 更衣室挂衣道具
	main.doll.global_position = main.level.rooms[15]["center"] + Vector2(0, -320)
	camera.global_position = main.doll.global_position + Vector2(0, -30)
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_locker.png")

	# 食堂与休息区
	main.doll.global_position = main.level.rooms[18]["center"]
	camera.global_position = main.doll.global_position
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/map_k17_canteen.png")

	print("map capture done")
	quit()
