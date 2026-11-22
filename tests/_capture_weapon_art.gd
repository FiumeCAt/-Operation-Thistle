extends SceneTree
## 临时截图：逐把武器近景，检查新像素贴图与手臂握持对齐。

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)
	main.camera.position_smoothing_enabled = false
	main.doll.global_position = Vector2(60, 21) * 64.0
	main.doll.aim_target = main.doll.global_position + Vector2(220, -30)
	main.view_zoom_pct = 200.0
	main._view_zoom_visual = 200.0
	for i in 10:
		await process_frame
	for id in [&"m870", &"m1014", &"saiga12k", &"g17"]:
		main.doll.equip_weapon_id(id)
		for i in 20:
			await process_frame
		await _shot("screenshots/weapon_%s.png" % id)
	print("weapon art capture done")
	quit()
