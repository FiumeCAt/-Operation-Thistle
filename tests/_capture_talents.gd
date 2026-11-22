extends SceneTree
## 临时截图：开始菜单 + 天赋树，输出到 screenshots/。
## godot --path . --script res://tests/_capture_talents.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p != null:
		# 只改内存数据，不写盘，避免污染玩家存档。
		p.data["resources"] = 120
		p.data["xp"] = 40
		p.data["skill_level"] = 3
		p.data["talents_2d"] = {"hp": 2, "gun": 1, "move": 1, "reload": 0, "scavenge": 1}
	change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/ui_start.png")

	var menu = current_scene
	menu._open_talents()
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/ui_talents.png")

	print("talents capture done")
	quit()
