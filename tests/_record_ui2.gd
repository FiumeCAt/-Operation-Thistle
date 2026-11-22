extends SceneTree
## 临时录制：开始菜单 → 武器库配置 → 大图行动 → 瞄准变焦 → ESC 设置。
## godot --path . --write-movie out/record/ui_features.avi --fixed-fps 30 \
##   --script res://tests/_record_ui2.gd -- --save-path user://record_ui2.json

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("record_ui2"):
		push_error("refusing to record without an isolated save path")
		quit(1)
		return
	p.data["resources"] = 120
	p.data["xp"] = 40
	p.data["skill_level"] = 3
	p.data["loadout_2d"] = ["m870", "g17"]

	change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")
	for i in 45:
		await process_frame
	var menu = current_scene

	menu._open_armory()
	for i in 45:
		await process_frame
	menu.armory._select(&"m1014")
	for i in 20:
		await process_frame
	menu.armory._equip(false)
	for i in 30:
		await process_frame
	menu.armory.close_menu()
	for i in 15:
		await process_frame

	menu._start()
	for i in 45:
		await process_frame
	var main = current_scene
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)

	Input.warp_mouse(Vector2(1240, 450))
	Input.action_press("aim")
	for i in 35:
		await physics_frame
	Input.action_press("view_zoom")
	main._set_view_zoom(160.0)
	for i in 35:
		await process_frame
	Input.action_release("view_zoom")
	Input.action_release("aim")
	for i in 20:
		await process_frame

	main.pause_menu.open()
	for i in 25:
		await process_frame
	main.pause_menu._open_settings()
	for i in 25:
		await process_frame
	main.pause_menu._master_slider.value = 50.0
	main.pause_menu._sfx_slider.value = 65.0
	for i in 30:
		await process_frame
	main.pause_menu._close_settings()
	for i in 15:
		await process_frame
	main.pause_menu.close()
	for i in 15:
		await process_frame

	print("ui record done, frames=", Engine.get_frames_drawn())
	quit()
