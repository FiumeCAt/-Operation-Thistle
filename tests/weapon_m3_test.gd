extends SceneTree
## M3 换弹 / 切枪测试：弹匣消耗、自动换弹、换弹动画期间禁射、切枪动画、
## 每把枪独立弹匣、霰弹枪逐发装填、HUD 文本跟随当前武器。
## godot --headless --path . --script res://tests/weapon_m3_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _wait_until(cond: Callable, max_frames := 240) -> bool:
	for i in max_frames:
		await process_frame
		if cond.call():
			return true
	return false


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	main.mouse_aim_enabled = false
	main.doll.aim_enabled = true
	await _wait(12)
	var doll = main.doll
	var rig: WeaponRig2D = doll.weapon_rig
	_check(rig != null, "weapon rig created")
	if rig == null:
		_finish()
		return
	doll.aim_target = doll.global_position + Vector2(200, 0)
	await _wait(20)

	_check(rig.mag == 17 and rig.get_reserve() == 108, "g17 starts with a full magazine")

	# 打空整个弹匣
	var fired := 0
	for i in 40:
		await _wait_until(func() -> bool: return rig.cooldown <= 0.0)
		if rig.mag <= 0:
			break
		if rig.try_fire():
			fired += 1
	_check(fired == 17, "fired the whole magazine, got %d" % fired)
	_check(rig.mag == 0, "magazine is empty after the last shot")

	# 空仓扣扳机：拒绝开火并自动进入换弹
	_check(not rig.try_fire(), "empty gun refuses to fire")
	_check(rig.reload_t > 0.0, "empty trigger starts a reload")
	_check(not rig.try_fire(), "cannot fire while reloading")
	_check(rig.get_reload_progress() < 0.9, "reload progress is still low")

	await _wait_until(func() -> bool: return rig.reload_t <= 0.0)
	_check(rig.mag == 17, "reload fills the magazine, mag=%d" % rig.mag)
	_check(rig.get_reserve() == 91, "reload consumes reserve, reserve=%d" % rig.get_reserve())
	_check(rig.get_ammo_text().contains("17 / 91"), "hud text shows mag / reserve")

	# 换弹动画：枪向下压、弹匣精灵掉出来
	await _wait_until(func() -> bool: return rig.cooldown <= 0.0)
	rig.try_fire()
	await _wait_until(func() -> bool: return rig.cooldown <= 0.0)
	_check(rig.reload(), "manual reload accepted")
	await _wait_until(func() -> bool: return rig.get_reload_progress() > 0.3)
	var pivot: Node2D = rig.get_node("Pivot")
	var mag_sprite: Sprite2D = rig.get_node("Magazine")
	_check(pivot.position.y > -97.0, "gun dips down while reloading, y=%.1f" % pivot.position.y)
	_check(mag_sprite.visible, "magazine sprite drops out during reload")
	await _wait_until(func() -> bool: return rig.reload_t <= 0.0)
	_check(rig.mag == 17, "manual reload refills the magazine")
	_check(not mag_sprite.visible, "magazine sprite hides after the reload")

	# 切枪到 M870（1 号槽）
	_check(rig.switch_to(&"m870"), "switch to m870 accepted")
	_check(rig.switch_t > 0.0, "switch animation is running")
	_check(not rig.try_fire(), "cannot fire while switching")
	await _wait_until(func() -> bool: return rig.switch_t <= 0.0)
	_check(rig.weapon_id == &"m870", "weapon switched to m870")
	_check(rig.data.feed_mode == &"shell", "m870 feeds shells one by one")
	_check(rig.get_gun_length() > 40.0, "m870 is longer than the pistol, len=%.1f" % rig.get_gun_length())
	_check(rig.mag == 5, "m870 starts with 5 shells in the tube")

	# 霰弹枪一次压一发
	await _wait_until(func() -> bool: return rig.cooldown <= 0.0)
	_check(rig.try_fire(), "m870 fires a shell")
	await _wait(2)
	_check(rig.mag == 4, "shell consumed, mag=%d" % rig.mag)
	var reserve_before: int = rig.get_reserve()
	_check(rig.reload(), "shell reload accepted")
	await _wait_until(func() -> bool: return rig.reload_t <= 0.0)
	_check(rig.mag == 5, "one shell loaded back, mag=%d" % rig.mag)
	_check(rig.get_reserve() == reserve_before - 1, "one shell taken from reserve")

	# 持续装填天赋：按住 R 在上一发装完后自动续压下一发
	rig.hold_reload_enabled = true
	await _wait_until(func() -> bool: return rig.cooldown <= 0.0)
	rig.try_fire()
	await _wait_until(func() -> bool: return rig.cooldown <= 0.0)
	rig.try_fire()
	_check(rig.mag == 3, "two shells spent for hold reload, mag=%d" % rig.mag)
	rig.process_hold_reload()
	_check(rig.reload_t > 0.0, "hold reload starts loading a shell")
	await _wait_until(func() -> bool: return rig.reload_t <= 0.0)
	_check(rig.mag == 4, "hold reload loaded one shell, mag=%d" % rig.mag)
	rig.process_hold_reload()
	_check(rig.reload_t > 0.0, "hold reload chains the next shell")
	await _wait_until(func() -> bool: return rig.reload_t <= 0.0)
	_check(rig.mag == 5, "hold reload filled the tube, mag=%d" % rig.mag)
	rig.hold_reload_enabled = false

	# 换弹中切枪会取消换弹
	_check(rig.reload() == false, "full tube refuses reload")
	rig.try_fire()
	rig.reload()
	_check(rig.switch_to(&"g17"), "switching cancels the reload animation")
	_check(rig.reload_t == 0.0, "reload state cleared by the switch")
	await _wait_until(func() -> bool: return rig.switch_t <= 0.0)
	_check(rig.weapon_id == &"g17", "switched back to g17")
	_check(rig.mag == 17, "g17 keeps its own magazine state")

	# HUD 文本跟随当前武器
	await _wait(3)
	_check(main.hud._title.text.begins_with("G17"), "hud label follows the equipped weapon")

	_finish()


func _finish() -> void:
	print("\n=== weapon m3: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
