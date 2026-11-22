extends SceneTree
## 录制用脚本：让角色按 右→下→左→上 走一圈，便于对比四档素材。
## 配合：--write-movie <file> --fixed-fps 30 --script res://tests/record_lod.gd -- --lod=1024

const SEQ := [
	["move_right", 36],
	["move_back", 30],
	["move_left", 36],
	["move_forward", 30],
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame

	for step in SEQ:
		Input.action_press(step[0])
		for i in step[1]:
			await process_frame
		Input.action_release(step[0])

	for i in 6:
		await process_frame
	quit()
