extends SceneTree
## 临时：用 Godot MovieWriter 录制动态准心（腰射/ADS、光标隐藏）。
## godot --path . --write-movie out/record/crosshair.avi --fixed-fps 30 \
##   --script res://tests/_record_crosshair.gd

var main
var doll
var rig


func _initialize() -> void:
	call_deferred("_run")


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _mouse(offset: Vector2) -> void:
	Input.warp_mouse(root.size * 0.5 + offset)


func _run() -> void:
	main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	await _wait(4)
	doll = main.doll
	rig = doll.weapon_rig
	rig.switch_to(&"m870")
	for i in 300:
		await process_frame
		if not rig.is_busy():
			break

	# 腰射：准心跟随鼠标，间距保持霰弹的宽间距
	_mouse(Vector2(120, -30))
	await _wait(15)
	_mouse(Vector2(240, 60))
	await _wait(15)

	# ADS：间距收紧、暗角出现
	Input.action_press("aim")
	await _wait(25)
	rig.try_fire()
	await _wait(15)
	_mouse(Vector2(-180, -80))
	await _wait(20)

	# 松开右键：间距恢复
	Input.action_release("aim")
	await _wait(25)
	_mouse(Vector2(60, 160))
	await _wait(15)
	rig.try_fire()
	await _wait(20)
	await _wait(20)

	print("crosshair record done")
	quit()
