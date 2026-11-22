extends SceneTree
## 骨架对比录制：常规比例 → Q 版，各录「站立摆头 + 四向行走 + 冲刺」。
## 运行：
##   Godot_v4.7.2-stable_win64.exe --path . --write-movie out/rig/frame.png --fixed-fps 30 \
##     --script res://tests/record_rig.gd

const IDLE_FRAMES := 18
const SWEEP_FRAMES := 40
const WALK_FRAMES := 24
const RUN_FRAMES := 26

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await _wait(8)

	await _perform(main, "normal")
	main.doll.enable_rig("chibi")
	main.hint_label.text = "模块化骨架 · Q 版 · WASD 移动 / Shift 跑 / 鼠标看向"
	await _wait(6)
	await _perform(main, "chibi")
	quit()

func _perform(main, _style: String) -> void:
	var doll = main.doll
	# 站立 + 头部朝鼠标左右扫动
	for i in SWEEP_FRAMES:
		var a := float(i) / SWEEP_FRAMES * TAU
		doll.aim_target = doll.global_position + Vector2(cos(a) * 160.0, sin(a) * 24.0)
		await process_frame
	doll.aim_target = doll.global_position
	await _wait(IDLE_FRAMES)

	# 四向行走
	for action in ["move_right", "move_forward", "move_left", "move_back"]:
		await _hold(action, WALK_FRAMES, false)

	# 冲刺（只展示左右）
	for action in ["move_right", "move_left"]:
		await _hold(action, RUN_FRAMES, true)

	# 回到站立
	await _wait(IDLE_FRAMES)

func _hold(action: String, frames: int, sprint: bool) -> void:
	if sprint:
		Input.action_press("sprint")
	Input.action_press(action)
	await _wait(frames)
	Input.action_release(action)
	if sprint:
		Input.action_release("sprint")
	await _wait(3)

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
