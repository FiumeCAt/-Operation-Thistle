extends SceneTree
## 截图脚本：保存 2D 主场景的静立、行走与全景各一张到 screenshots/。
## 运行：Godot_v4.7.2-stable_win64.exe --path . --script res://tests/capture_2d.gd -- --rig=normal
## 不同骨架风格会带后缀，避免互相覆盖：2d_rig_normal_walk.png

var _suffix := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rig="):
			var v := arg.get_slice("=", 1)
			if v != "off":
				_suffix = "_rig_" + v
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/core/Main2D.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame

	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/2d%s_scene.png" % _suffix)

	# 行走帧：向右走 20 个物理帧后截图，检查迈步与踩地。
	Input.action_press("move_right")
	for i in 20:
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/2d%s_walk.png" % _suffix)
	Input.action_release("move_right")
	await physics_frame

	var camera: Camera2D = main.get_node("Camera2D")
	camera.zoom = Vector2(0.7, 0.7)
	camera.global_position = Vector2(768, 576)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/2d%s_overview.png" % _suffix)

	print("saved three", _suffix)
	quit()
