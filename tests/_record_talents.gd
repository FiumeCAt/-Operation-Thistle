extends SceneTree
## 临时录制：开始菜单 -> 打开天赋树 -> 购买生命强化 -> 返回 -> 开始行动。
## godot --path . --write-movie out/record/talents.avi --fixed-fps 30 \
##   --script res://tests/_record_talents.gd -- --save-path user://record_talents.json

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null:
		push_error("Progress missing")
		quit(1)
		return
	# 录制会触发购买写盘，必须落在隔离存档上，不能碰玩家真实存档。
	if not String(p.save_path).contains("record_talents"):
		push_error("refusing to write non-isolated save: " + String(p.save_path))
		quit(1)
		return
	p.data["resources"] = 120
	p.data["xp"] = 40
	p.data["skill_level"] = 3
	p.data["talents_2d"] = {"hp": 2, "gun": 1, "move": 1, "reload": 0, "scavenge": 1}
	p.save_data()

	change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")
	for i in 45:
		await process_frame

	var menu = current_scene
	for i in 20:
		await process_frame
	menu._open_talents()
	for i in 75:
		await process_frame

	# 购买生命强化 Lv.2 -> Lv.3，画面会显示扣费与反馈。
	menu.talents._buy(&"hp")
	for i in 75:
		await process_frame

	menu.talents.close_tree()
	for i in 30:
		await process_frame
	menu.start_button.pressed.emit()

	for i in 30:
		await process_frame
	Input.action_press("move_right")
	for i in 45:
		await physics_frame
	Input.action_release("move_right")
	for i in 30:
		await process_frame

	# 展示 ESC 菜单，确认新 UI 与全局按钮音在游戏内一致。
	var main = current_scene
	if main != null and main.pause_menu != null:
		main.pause_menu.open()
	for i in 45:
		await process_frame
	if main != null and main.pause_menu != null:
		main.pause_menu.close()
	for i in 30:
		await process_frame

	print("talents record done, frames=", Engine.get_frames_drawn())
	quit()
