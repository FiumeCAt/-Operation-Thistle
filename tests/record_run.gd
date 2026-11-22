extends SceneTree
## 跑动展示录制：四向冲刺各 1.2 秒，用来检查左右脚落地与贴图。
## godot --path . --write-movie out/run/frame.png --fixed-fps 30 --script res://tests/record_run.gd

const RUN_FRAMES := 36

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	for i in 10:
		await process_frame
	var doll = main.doll
	for action in ["move_back", "move_forward", "move_left", "move_right"]:
		Input.action_press("sprint")
		Input.action_press(action)
		for i in RUN_FRAMES:
			doll.aim_target = doll.global_position + Vector2(0, 200)
			await process_frame
		Input.action_release(action)
		Input.action_release("sprint")
		for i in 4:
			await process_frame
	quit()
