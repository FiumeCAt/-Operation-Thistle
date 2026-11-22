extends SceneTree
## 临时截图：金属/血肉两种命中特效（火花 vs 血珠 + 伤害数字）。
## godot --path . --script res://tests/_capture_hitfx.gd -- --save-path user://capture_hitfx.json

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null:
		quit(1)
		return
	p.reset_for_test()
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 30:
		await process_frame

	var flesh: Enemy2D = null
	var metal: Enemy2D = null
	for e in main.enemies:
		if e.kind == &"rifleman" and flesh == null:
			flesh = e
		if (e.kind == &"mobile_turret" or e.kind == &"sentry_type1") and metal == null:
			metal = e
	if flesh == null or metal == null:
		print("missing enemies")
		quit(1)
		return
	for e in main.enemies:
		e.set_physics_process(false)

	# 用北主廊做干净的直线：镜头里只有角色、敌人和地面。
	main.doll.global_position = Vector2(46.0, 36.0) * 64.0
	main.camera.global_position = main.doll.global_position
	for i in 10:
		await physics_frame

	await _shoot_at(main, flesh, metal, "screenshots/fx_hit_flesh.png")
	await _shoot_at(main, metal, flesh, "screenshots/fx_hit_metal.png")
	print("hitfx capture done")
	quit()


func _shoot_at(main, enemy: Enemy2D, other: Enemy2D, path: String) -> void:
	other.set_physics_process(false)
	other.global_position = main.doll.global_position + Vector2(-1400, 1200)
	enemy.set_physics_process(true)
	enemy.stats["speed"] = 0.0
	enemy.stats["view_range"] = 0.0
	enemy.stats["hearing"] = 0.0
	enemy._attack_cd = 999.0
	enemy.hp = 900.0
	enemy.hp_max = 900.0
	enemy.global_position = main.doll.global_position + Vector2(330, 10)
	main.doll.aim_target = enemy.global_position + Vector2(0, -52)
	for i in 14:
		await physics_frame
	main.doll.weapon_rig.try_fire()
	# 等特效从白热核心展开成喷溅（顿帧期间游戏时间很慢，多等几帧）。
	for i in 5:
		await physics_frame
	await _shot(path)
	await create_timer(0.5).timeout
