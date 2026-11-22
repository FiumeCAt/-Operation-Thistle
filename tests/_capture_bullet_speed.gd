extends SceneTree
## 子弹速度视觉验收：同一位置连续抓两帧，确认弹头/曳光在飞行而不是瞬移。
## godot --path . --script res://tests/_capture_bullet_speed.gd

var main


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null:
		quit(1)
		return
	p.reset_for_test()
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	main.doll.global_position = Vector2(39.5, 60.5) * main.TILE
	main.doll.equip_weapon_id(&"m1911")
	main.doll.weapon_rig.mag = 20
	main.mouse_aim_enabled = false
	# 从枪口水平向右瞄准：该方向射界 >3000px，能完整看到弹丸飞行。
	main.doll.aim_target = main.get_safe_shot_origin() + Vector2(900, 0)
	for i in 10:
		await process_frame
	# 枪口随瞄准转动后再校准一次，保证最终弹道水平。
	main.doll.aim_target = main.get_safe_shot_origin() + Vector2(900, 0)
	for i in 6:
		await process_frame
	main.doll.weapon_rig.cooldown = 0.0
	main.doll.weapon_rig.try_fire()
	for i in 3:
		await physics_frame
	# 暂停物理，冻结弹丸，确保截图时子弹实体仍在画面内。
	paused = true
	_print_bullets("frame3")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://screenshots/_verify_bullet_speed_1.png")
	# 关闭弹道线条：子弹实体应保留，只隐藏长线。
	p.data["bullet_trail_enabled"] = false
	main._on_settings_applied()
	await process_frame
	_print_bullets("off")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://screenshots/_verify_bullet_trail_off.png")
	# 重新开启：长线恢复。
	p.data["bullet_trail_enabled"] = true
	main._on_settings_applied()
	await process_frame
	_print_bullets("on2")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		"res://screenshots/_verify_bullet_trail_on2.png")
	paused = false
	print("bullet speed capture done")
	quit()


func _print_bullets(tag: String) -> void:
	for child in main.fx_layer.get_children():
		if child is PlayerBullet2D:
			var screen: Vector2 = child.get_global_transform_with_canvas().origin
			var line_visible: bool = child.trail_line != null and child.trail_line.visible
			print(tag, " bullet world=", child.global_position,
				" screen=", screen, " speed=", child.velocity.length(),
				" trail=", line_visible)
