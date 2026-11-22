extends SceneTree
## 临时截图：武备库新枪列表 / 改枪页 / 局内开火。
## godot --path . --script res://tests/_capture_new_weapons_ui.gd -- --save-path user://capture_new_weapons.json

func _initialize() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + path)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("capture_new_weapons"):
		push_error("refusing to capture without an isolated save path")
		quit(1)
		return
	p.data["resources"] = 1200
	p.data["advanced_2d"] = {
		"weapon_parts": 9, "electronic_core": 6,
		"high_energy_cell": 4, "military_alloy": 6,
	}
	p.data["loadout_2d"] = ["akm", "mp7"]

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	for i in 20:
		await process_frame
	menu._open_armory()
	for i in 10:
		await process_frame
	menu.armory._select(&"akm")
	for i in 6:
		await process_frame
	menu.armory._list_scroll.scroll_vertical = 9999
	for i in 6:
		await process_frame
	await _shot("screenshots/new_weapons_armory.png")
	menu.armory._show_page("mods")
	menu.armory._select_mod_item("akm")
	for i in 10:
		await process_frame
	await _shot("screenshots/new_weapons_mods.png")
	menu.queue_free()
	await process_frame

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 12:
		await process_frame
	var arena := Vector2(60.0, 44.0) * 64.0
	main.doll.global_position = arena
	main.doll.hp_max = 99999.0
	main.doll.hp = 99999.0
	for e in main.enemies.duplicate():
		e.queue_free()
	main.enemies.clear()
	await process_frame
	main.camera.position_smoothing_enabled = false
	var target := Enemy2D.new()
	target.setup(&"sentry_type1", arena + Vector2(300, 40), 1)
	target.hp_max = 99999.0
	target.hp = 99999.0
	target.set_physics_process(false)
	main.sort_layer.add_child(target)
	main.enemies.append(target)
	main.doll.aim_target = target.global_position + Vector2(0, -40)
	var rig: WeaponRig2D = main.doll.weapon_rig
	rig.setup(&"akm")
	rig.loadout = [&"akm", &"mp7", &"awm"]
	for i in 10:
		await process_frame
	for i in 6:
		rig.cooldown = 0.0
		rig.try_fire()
		await process_frame
	if rig._flash != null:
		rig._flash.visible = true
		rig._flash.frame = 0
	await _shot("screenshots/new_weapons_ingame.png")

	rig.setup(&"awm")
	for i in 12:
		await process_frame
	main.doll.aim_target = target.global_position + Vector2(0, -40)
	rig.cooldown = 0.0
	rig.try_fire()
	for i in 2:
		await process_frame
	if rig._flash != null:
		rig._flash.visible = true
		rig._flash.frame = 0
	await _shot("screenshots/new_weapons_sniper.png")
	print("new weapons ui capture done")
	quit()
