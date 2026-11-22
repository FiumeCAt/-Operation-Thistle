extends SceneTree
## 临时：用 Godot MovieWriter 录制 6 秒霰弹枪测试视频。
## godot --path . --write-movie out/record/shotgun.avi --fixed-fps 30 \
##   --script res://tests/_record_shotgun.gd

var main
var doll
var rig


func _initialize() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _aim(dir: Vector2) -> void:
	doll.aim_target = doll.global_position + dir.normalized() * 260.0


func _run() -> void:
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await _wait(4)
	doll = main.doll
	doll.aim_enabled = true
	_aim(Vector2.RIGHT)
	await _wait(10)
	rig = doll.weapon_rig
	rig.switch_to(&"m870")
	for i in 120:
		await process_frame
		if not rig.is_busy():
			break
	_aim(Vector2.RIGHT)
	await _wait(12)

	# 1) 腰射：开火后立刻转向，验证枪口特效跟随枪口
	rig.try_fire()
	await _wait(5)
	_aim(Vector2(0.45, -0.9))
	await _wait(20)

	# 2) 右键 ADS 开火
	Input.action_press("aim")
	_aim(Vector2.RIGHT)
	await _wait(20)
	rig.try_fire()
	await _wait(18)
	Input.action_release("aim")

	# 3) 移动中朝左开火
	Input.action_press("move_right")
	_aim(Vector2.LEFT)
	await _wait(24)
	rig.try_fire()
	await _wait(20)
	_aim(Vector2(0.8, 0.6))
	await _wait(24)
	Input.action_release("move_right")

	# 4) 朝下开火收尾
	_aim(Vector2.DOWN)
	await _wait(18)
	rig.try_fire()
	await _wait(30)

	print("record frames done")
	quit()
