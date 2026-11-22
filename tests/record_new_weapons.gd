extends SceneTree
## 新枪实机演示录像：左轮 → MP7 → AKM → SR-25 → AWM。
## godot --path . --write-movie screenshots/new_weapons_demo.avi --fixed-fps 30 \
##   --script res://tests/record_new_weapons.gd -- --save-path user://record_new_weapons.json

const FPS := 30.0
const SEGMENTS := [
	["python", 2.5],
	["mp7", 3.5],
	["akm", 3.5],
	["sr25", 3.0],
	["awm", 3.5],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var p = root.get_node_or_null("Progress")
	if p == null or not String(p.save_path).contains("record_new_weapons"):
		push_error("refusing to record without an isolated save path")
		quit(1)
		return
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 8:
		await process_frame
	var arena := Vector2(60.0, 44.0) * 64.0
	main.doll.global_position = arena
	main.doll.hp_max = 99999.0
	main.doll.hp = 99999.0
	main.doll.aim_enabled = true
	for e in main.enemies.duplicate():
		e.queue_free()
	main.enemies.clear()
	await process_frame
	main.camera.position_smoothing_enabled = false

	var targets: Array[Enemy2D] = []
	for offset in [Vector2(300, -50), Vector2(430, 90), Vector2(250, 150)]:
		var dummy := Enemy2D.new()
		dummy.setup(&"sentry_type1", arena + offset, 1)
		dummy.hp_max = 99999.0
		dummy.hp = 99999.0
		dummy.set_physics_process(false)
		main.sort_layer.add_child(dummy)
		main.enemies.append(dummy)
		targets.append(dummy)
	var rig: WeaponRig2D = main.doll.weapon_rig
	rig.loadout = [&"python", &"mp7", &"akm", &"sr25", &"awm"]

	var frame := 0
	for segment in SEGMENTS:
		rig.setup(StringName(segment[0]))
		var frames := int(round(float(segment[1]) * FPS))
		for i in frames:
			var target: Enemy2D = targets[int(frame / 40) % targets.size()]
			main.doll.aim_target = target.global_position + Vector2(0, -40)
			rig.try_fire()
			main.doll.hp = main.doll.hp_max
			frame += 1
			await process_frame
	print("new weapons record done (%d frames)" % frame)
	quit()
