extends SceneTree
## 临时录制：部署界面 → 废弃仓出生 → M 大地图 → 护甲受击/命中飘字。
## godot --path . --write-movie out/record/new_systems.avi --fixed-fps 30 \
##   --script res://tests/_record_new2.gd -- --save-path user://record_new2.json

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("record_new2"):
		push_error("refusing to record without an isolated save path")
		quit(1)
		return
	p.reset_for_test()

	change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")
	for i in 45:
		await process_frame
	var menu = current_scene
	menu._start()
	for i in 40:
		await process_frame
	menu.deployment._select(&"abandoned")
	for i in 30:
		await process_frame
	menu.deployment._confirm()

	for i in 60:
		await process_frame
	var main = current_scene
	main.mouse_aim_enabled = false
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)
	for i in 30:
		await process_frame

	# M 键大地图：看到玩家在废弃仓、默认南侧撤离。
	main.map_overlay.open()
	for i in 45:
		await process_frame
	main.map_overlay.close()
	for i in 20:
		await process_frame

	# 受击：护甲吸收 + 红色飘字。
	main.doll.invuln = 0.0
	main.doll.take_damage(30.0)
	for i in 20:
		await process_frame

	# 命中：把一名敌人放到面前开火，显示琥珀色飘字。
	var enemy = main.enemies[0]
	enemy.global_position = main.doll.global_position + Vector2(220, 0)
	enemy.hp = 100.0
	enemy.hp_max = 100.0
	main.doll.aim_target = enemy.global_position
	for i in 4:
		await physics_frame
	main.doll.weapon_rig.try_fire()
	for i in 25:
		await process_frame

	print("new systems record done, frames=", Engine.get_frames_drawn())
	quit()
