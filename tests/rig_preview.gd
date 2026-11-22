extends SceneTree
## 骨架预览：把 normal / chibi 两套骨架放大排成网格截图，检查分件与关节。
## 输出 screenshots/rig_preview_dirs.png 与 rig_preview_walk.png
## 运行：Godot_v4.7.2-stable_win64.exe --path . --script res://tests/rig_preview.gd

const DollRig2DRes := preload("res://scripts/actors/DollRig2D.gd")
const ZOOM := 1.55

func _initialize() -> void:
	call_deferred("_run")

func _spawn(holder: Node2D, style: String, pos: Vector2) -> Node:
	var rig := DollRig2DRes.new()
	rig.height = 128.0
	rig.style = style
	rig.position = pos
	holder.add_child(rig)
	return rig

func _run() -> void:
	RenderingServer.set_default_clear_color(Color("2a2d33"))
	var holder := Node2D.new()
	root.add_child(holder)
	var camera := Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = Vector2(512, 300)
	holder.add_child(camera)
	camera.make_current()

	# 第一张：两套风格 × 4 个朝向
	for row in 2:
		var style: String = "normal" if row == 0 else "chibi"
		for col in 4:
			var rig := _spawn(holder, style, Vector2(200 + col * 200, 200 + row * 220))
			await process_frame
			rig.set_state("idle", col, rig.global_position + Vector2(-80, 0), true, 0.016)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/rig_preview_dirs.png")
	for child in holder.get_children():
		if child is Camera2D:
			continue
		child.queue_free()
	await process_frame

	# 第二张：行走 8 个相位（上排 normal，下排 chibi）
	for row in 2:
		var style: String = "normal" if row == 0 else "chibi"
		for col in 8:
			var rig := _spawn(holder, style, Vector2(120 + col * 112, 200 + row * 220))
			await process_frame
			for i in (col + 1) * 2:
				rig.set_state("walk", 0, rig.global_position + Vector2(80, 0), true, 0.045)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/rig_preview_walk.png")
	print("saved rig preview")
	quit()
