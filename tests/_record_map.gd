extends SceneTree
## 临时录制：K-17 装卸区出生 → 控制室恢复供电 → 军械库拉闸撤离。
## godot --path . --write-movie out/record/map_k17.avi --fixed-fps 30 \
##   --script res://tests/_record_map.gd -- --save-path user://record_map.json

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("record_map"):
		push_error("refusing to record without an isolated save path")
		quit(1)
		return

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 45:
		await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)

	# 出生点向右走过装卸区闸门。
	Input.action_press("move_right")
	for i in 120:
		await physics_frame
	Input.action_release("move_right")
	for i in 24:
		await process_frame

	# 控制室：恢复供电。
	main.doll.global_position = main.level.power_position + Vector2(0, -80)
	for i in 36:
		await process_frame
	main._try_interact()
	for i in 48:
		await process_frame

	# 军械库：带资源拉闸撤离，展示任务与拉闸加成。
	main.resources = 4
	main.doll.global_position = main.level.switch_exit_position
	for i in 36:
		await process_frame
	main._try_interact()
	for i in 60:
		await process_frame

	print("map record done, frames=", Engine.get_frames_drawn())
	quit()
