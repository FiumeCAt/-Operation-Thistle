extends SceneTree
## 临时：用 MovieWriter 录制 开始菜单 -> 游戏 -> ESC 菜单 -> 继续。
## godot --path . --write-movie out/record/menus.avi --fixed-fps 30 \
##   --script res://tests/_record_menus.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")
	for i in 45:
		await process_frame

	var menu = current_scene
	for i in 30:
		await process_frame
	if menu != null and menu.start_button != null:
		menu.start_button.pressed.emit()

	for i in 45:
		await process_frame
	var main = current_scene
	for i in 30:
		await process_frame
	if main != null and main.pause_menu != null:
		main.pause_menu.open()

	for i in 45:
		await process_frame
	if main != null and main.pause_menu != null:
		main.pause_menu.close()
	for i in 30:
		await process_frame

	print("menu record done")
	quit()
