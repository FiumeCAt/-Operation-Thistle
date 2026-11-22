extends SceneTree
## 临时录制：小地图、ADS 方向前探、滚轮 20/100/200% 缩放、撤离返回基地。
## godot --path . --write-movie out/record/features.avi --fixed-fps 30 \
##   --script res://tests/_record_features.gd -- --save-path user://record_features.json

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("record_features"):
		push_error("refusing to record without an isolated save path")
		quit(1)
		return

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.camera.position_smoothing_enabled = false
	main.doll.global_position = Vector2(60, 21) * 64.0
	for i in 45:
		await process_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)

	# 小地图与常规视野
	for i in 30:
		await process_frame

	# ADS 100%：镜头朝准心方向前探
	Input.warp_mouse(Vector2(1320, 450))
	Input.action_press("aim")
	for i in 45:
		await physics_frame

	# 200% 放大
	main._set_view_zoom(200.0)
	for i in 45:
		await process_frame

	# 20% 广角
	main._set_view_zoom(20.0)
	for i in 45:
		await process_frame

	# 100% 朝上瞄准，确认视野仍留在设施内
	main._set_view_zoom(100.0)
	Input.warp_mouse(Vector2(800, 150))
	for i in 45:
		await physics_frame
	Input.action_release("aim")
	for i in 30:
		await process_frame

	# 撤离结算 → 返回基地
	main.loot = {"electronics": 2, "energy": 1, "parts": 1}
	main.resources = 4
	main.level.set_power_on(true)
	main._finish_run(true, true)
	for i in 45:
		await process_frame
	main.hud.return_button.pressed.emit()
	for i in 45:
		await process_frame

	print("features record done, frames=", Engine.get_frames_drawn())
	quit()
