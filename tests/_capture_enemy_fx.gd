extends SceneTree
## 临时截图：敌人射击曳光 + 近战刀光。
## godot --path . --script res://tests/_capture_enemy_fx.gd -- --save-path user://capture_enemy_fx.json

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_enemy_fx"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 25:
		await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)
	main.camera.position_smoothing_enabled = false
	var doll = main.doll
	doll.global_position = Vector2(35, 21) * 64.0
	doll.armor = 100
	doll.hp = 100
	doll.aim_target = doll.global_position + Vector2(220, 0)

	var rifle: Enemy2D = null
	var rusher: Enemy2D = null
	for enemy in main.enemies:
		if enemy.kind == &"rifleman" and rifle == null:
			rifle = enemy
		elif enemy.kind == &"rusher" and rusher == null:
			rusher = enemy
	rifle.global_position = Vector2(42, 21) * 64.0
	rusher.global_position = doll.global_position + Vector2(-56, 0)
	for i in 6:
		await process_frame

	rifle._attack_cd = 0.0
	rifle._try_attack(rifle.global_position.distance_to(doll.global_position))
	rusher._attack_cd = 0.0
	rusher._try_attack(56.0)
	for i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/enemy_attack_fx.png")
	print("enemy fx capture done")
	quit()
