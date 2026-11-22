extends SceneTree
## 头部跟随演示录制：站立左右摆头 → 四向行走（走的是和真鼠标完全相同的 aim_target 逻辑）。
## godot --path . --write-movie <file> --fixed-fps 30 --script res://tests/record_head.gd

const SWEEP := 46
const WALK := 22

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.mouse_aim_enabled = false
	for i in 10:
		await process_frame

	var doll = main.get_node("World2D/SortLayer/Doll2D")
	var center: Vector2 = doll.global_position
	for step in SWEEP:
		var t := float(step) / float(SWEEP - 1)
		doll.aim_target = center + Vector2(cos(t * TAU) * 200.0, 0)
		await process_frame

	for action in ["move_right", "move_forward", "move_left", "move_back"]:
		Input.action_press(action)
		for i in WALK:
			# 走动时瞄准点继续左右扫，确认头能独立摆
			var t := float(i) / float(WALK)
			doll.aim_target = doll.global_position + Vector2(cos(t * TAU) * 200.0, 0)
			await process_frame
		Input.action_release(action)
		for i in 3:
			await process_frame

	for i in 20:
		await process_frame
	quit()
