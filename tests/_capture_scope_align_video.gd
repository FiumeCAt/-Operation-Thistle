extends SceneTree
## 验收：复现“腰射瞄准箱子 → 开镜”的完整操作，检查准心下的世界点是否保持不变。
## 箱子（品红）与门（青色）相距 352 世界像素，正好等于旧版 ADS 前探距离。
## godot --path . --script res://tests/_capture_scope_align_video.gd

const FRAME_DIR := "res://screenshots/_align_frames"
const OUT_W := 960
const OUT_H := 540

var main = null
var overlay: CanvasLayer
var view: Control
var frame := 0
var box_marker: Node2D
var door_marker: Node2D
var aim_shift := -1.0
var lens_px := 0.0
var scene_text := "腰射瞄准箱子"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	for name in DirAccess.get_files_at(FRAME_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FRAME_DIR + "/" + name))
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL Progress missing")
		quit(1)
		return
	p.reset_for_test()
	p.data["run_mode"] = "raid"
	p.data["map_id"] = "facility"
	p.data["loadout_2d"] = ["m870", "g17"]
	p.data["weapon_mods_2d"]["m870"] = {"sight": "scope", "stock": "heavy"}
	p.data["view_zoom"] = 90
	p.data["screen_shake"] = false

	main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	for enemy in main.enemies.duplicate():
		enemy.queue_free()
	main.enemies.clear()
	await process_frame

	var origin: Vector2 = Vector2(39.5, 60.5) * main.TILE
	main.doll.global_position = origin
	main.doll.weapon_rig.setup(&"m870")
	await process_frame

	# 世界标记：品红箱子 = 准心目标；青色门 = 旧版前探会把镜头推到的位置。
	var box_at: Vector2 = origin + Vector2(520, 0)
	var door_at: Vector2 = box_at + Vector2(352, 0)
	box_marker = MarkRect.new()
	box_marker.set("fill", Color(1.0, 0.15, 1.0, 0.30))
	box_marker.set("line", Color(1.0, 0.15, 1.0, 0.95))
	box_marker.set("rect", Rect2(-32, -32, 64, 64))
	box_marker.position = box_at
	box_marker.z_index = 600
	main.add_child(box_marker)
	door_marker = MarkRect.new()
	door_marker.set("fill", Color(0.15, 0.9, 1.0, 0.22))
	door_marker.set("line", Color(0.2, 0.95, 1.0, 0.9))
	door_marker.set("rect", Rect2(-20, -60, 40, 120))
	door_marker.position = door_at
	door_marker.z_index = 600
	main.add_child(door_marker)

	overlay = CanvasLayer.new()
	overlay.layer = 120
	root.add_child(overlay)
	view = Control.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_debug)
	overlay.add_child(view)
	process_frame.connect(func() -> void:
		if view != null and is_instance_valid(view):
			view.queue_redraw())

	# ---- 第一阶段：腰射，把准心放到箱子上 ----
	await _hip_aim(box_at)
	scene_text = "腰射：准心在箱子上"
	await _save_frame()
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	var mouse: Vector2 = main.get_viewport().get_mouse_position()
	var world_before: Vector2 = ct.affine_inverse() * mouse
	print("hip aim: mouse=", mouse, " box_screen=", ct * box_at,
		" world_under_mouse=", world_before, " err=", world_before.distance_to(box_at))

	# ---- 第二阶段：保持鼠标不动，右键开镜 ----
	var aim_target_before: Vector2 = main.doll.aim_target
	Input.action_press("aim")
	for i in 50:
		await process_frame
		if i % 6 == 0:
			await _save_frame()
	scene_text = "开镜：应仍对准箱子"
	await _save_frame()
	ct = main.get_viewport().get_canvas_transform()
	mouse = main.get_viewport().get_mouse_position()
	var world_after: Vector2 = ct.affine_inverse() * mouse
	aim_shift = world_before.distance_to(world_after)
	lens_px = main.scope_sight._center.distance_to(mouse)
	var box_off := (ct * box_at).distance_to(mouse)
	print("ADS: mouse=", mouse, " box_screen=", ct * box_at,
		" box_off=", snappedf(box_off, 0.01),
		" world_under_mouse=", world_after,
		" aim_shift=", snappedf(aim_shift, 0.01),
		" lens_vs_mouse=", snappedf(lens_px, 0.01),
		" lens_vis=", main.scope_sight._lens_visible)
	print("aim_target shift=", snappedf(aim_target_before.distance_to(main.doll.aim_target), 0.01))
	await _shot("screenshots/_verify3_ads_box.png")

	# ---- 第三阶段：扫到屏幕边缘，确认镜窗跟随不夹取 ----
	var w: Vector2 = main.get_viewport().get_visible_rect().size
	var from := w * 0.5
	var to := w - Vector2(18, 18)
	for i in 40:
		Input.warp_mouse(from.lerp(to, float(i) / 39.0))
		await process_frame
		if i % 3 == 0:
			await _save_frame()
	await _save_frame()
	_dump_edge()

	# ---- 第四阶段：边缘开一枪 ----
	var aim_before: Vector2 = main.doll.aim_target
	main.doll.weapon_rig.cooldown = 0.0
	var fired: bool = main.doll.weapon_rig.try_fire()
	await process_frame
	print("fired=", fired, " shot_aim_err_deg=",
		rad_to_deg(main.last_shot_dir.angle_to((aim_before - main.last_shot_origin).normalized())))
	for i in 6:
		await process_frame
		await _save_frame()
	# ---- 第五阶段：视野倍率对比（铁瞄 vs 4× 镜，腰射下看视野锥宽度）----
	Input.action_release("aim")
	Input.warp_mouse(Vector2(w.x * 0.5 + 420.0, w.y * 0.5))
	for i in 40:
		await process_frame
	if p != null:
		p.data["weapon_mods_2d"]["m870"]["sight"] = "iron"
	main.doll.weapon_rig.setup(&"m870")
	for i in 30:
		await process_frame
	await _shot("screenshots/_verify_vision_iron.png")
	if p != null:
		p.data["weapon_mods_2d"]["m870"]["sight"] = "scope"
	main.doll.weapon_rig.setup(&"m870")
	for i in 40:
		await process_frame
	await _shot("screenshots/_verify_vision_scope.png")
	print("vision shots done")

	# ---- 第六阶段：声纹（背后移动的敌人）----
	var guard := Enemy2D.new()
	guard.setup(&"rusher", main.doll.global_position + Vector2(0, 260), 1)
	main.sort_layer.add_child(guard)
	guard.set_physics_process(false)
	guard.velocity = Vector2(0, 130)
	for i in 24:
		await process_frame
	await _shot("screenshots/_verify_hearing.png")
	await _save_frame()
	print("hearing shot done")

	# ---- 第七阶段：边缘视野层敌人 80% 不透明度 ----
	guard.velocity = Vector2.ZERO
	guard.global_position = main.doll.global_position \
		+ Vector2.from_angle(deg_to_rad(-60.0)) * 320.0
	for i in 26:
		await process_frame
	await _shot("screenshots/_verify_vision_edge.png")
	await _save_frame()
	print("edge enemy shot done")

	print("frames=", frame)
	quit()


## 腰射状态下把鼠标放到世界点的屏幕位置；开镜前相机只跟玩家，因此很快稳定。
func _hip_aim(world: Vector2) -> void:
	for i in 5:
		var ct: Transform2D = main.get_viewport().get_canvas_transform()
		Input.warp_mouse(ct * world)
		for f in 6:
			await process_frame


func _dump_edge() -> void:
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	var mouse: Vector2 = main.get_viewport().get_mouse_position()
	print("edge: mouse=", mouse, " lens_center=", main.scope_sight._center,
		" err=", snappedf(main.scope_sight._center.distance_to(mouse), 0.01),
		" lens_vis=", main.scope_sight._lens_visible)


func _save_frame() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img == null:
		return
	img.resize(OUT_W, OUT_H, Image.INTERPOLATE_BILINEAR)
	img.save_jpg("%s/f_%03d.jpg" % [FRAME_DIR, frame], 0.9)
	frame += 1


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _draw_debug() -> void:
	if main == null or not is_instance_valid(main):
		return
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	var mouse: Vector2 = main.get_viewport().get_mouse_position()
	var box_screen: Vector2 = ct * box_marker.position
	view.draw_arc(mouse, 30.0, 0.0, TAU, 48, Color(0.15, 1.0, 0.25, 0.95), 2.5)
	view.draw_line(mouse + Vector2(-42, 0), mouse + Vector2(42, 0), Color(0.15, 1.0, 0.25, 0.75), 1.0)
	view.draw_line(mouse + Vector2(0, -42), mouse + Vector2(0, 42), Color(0.15, 1.0, 0.25, 0.75), 1.0)
	# 品红小框：箱子在屏幕上的位置。开镜后它必须仍在鼠标/镜心。
	view.draw_rect(Rect2(box_screen - Vector2(36, 36), Vector2(72, 72)),
		Color(1.0, 0.15, 1.0, 0.8), false, 2.0)
	var font: Font = PixelUI.FONT
	view.draw_string(font, Vector2(24, 56), scene_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.95, 0.9))
	view.draw_string(font, Vector2(24, 84),
		"箱子与准心偏差: %.2f px" % box_screen.distance_to(mouse),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.4, 1.0, 0.5) if box_screen.distance_to(mouse) < 3.0 else Color(1.0, 0.4, 0.3))
	if aim_shift >= 0.0:
		view.draw_string(font, Vector2(24, 112),
			"开镜前后准心下的世界点偏差: %.2f 世界像素" % aim_shift,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.4, 1.0, 0.5) if aim_shift < 2.0 else Color(1.0, 0.4, 0.3))
		view.draw_string(font, Vector2(24, 140),
			"镜心与鼠标误差: %.2f px" % lens_px,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(0.4, 1.0, 0.5) if lens_px < 2.0 else Color(1.0, 0.4, 0.3))


class MarkRect extends Node2D:
	var fill := Color(1, 1, 1, 0.25)
	var line := Color(1, 1, 1, 0.9)
	var rect := Rect2(-32, -32, 64, 64)

	func _draw() -> void:
		draw_rect(rect, fill)
		draw_rect(rect, line, false, 3.0)
