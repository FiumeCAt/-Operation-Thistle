extends SceneTree
## 动画展示录制：站立 → 四向行走 → 四向奔跑 → 站立。
## 配合：--write-movie <file> --fixed-fps 30 --script res://tests/record_anim.gd -- --lod=128

const IDLE_FRAMES := 24
const MOVE_FRAMES := 30

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	await _wait(10)
	await _wait(IDLE_FRAMES)

	for action in ["move_right", "move_back", "move_left", "move_forward"]:
		await _hold(action, MOVE_FRAMES, false)

	for action in ["move_right", "move_back", "move_left", "move_forward"]:
		await _hold(action, MOVE_FRAMES, true)

	await _wait(IDLE_FRAMES)
	quit()

func _hold(action: String, frames: int, sprint: bool) -> void:
	if sprint:
		Input.action_press("sprint")
	Input.action_press(action)
	await _wait(frames)
	Input.action_release(action)
	if sprint:
		Input.action_release("sprint")
	await _wait(4)

func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
