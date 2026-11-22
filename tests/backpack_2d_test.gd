extends SceneTree
## TAB 背包回归：打开/关闭、暂停、本局物资、仓库库存与左侧拾取信息流。
## godot --headless --path . --script res://tests/backpack_2d_test.gd

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


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()
	p.data["resources"] = 64
	p.data["materials_2d"] = {"electronics": 5, "energy": 6, "parts": 7}
	p.data["advanced_2d"] = {"weapon_parts": 1, "electronic_core": 2,
		"high_energy_cell": 0, "military_alloy": 3}

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	_check(main.backpack != null and not main.backpack.visible,
		"backpack starts hidden")

	# 本局物资：三种基础 + 一个进阶
	main.loot = {"electronics": 3, "energy": 2, "parts": 4}
	main.advanced_loot = {"electronic_core": 1}
	main.resources = 10

	# 拾取信息流：消息进入左侧列表，而不是左下状态板
	var feed_before: int = main.hud._feed_items.size()
	main._on_pickup_collected("resource", &"parts", 1)
	_check(main.hud._feed_items.size() == feed_before + 1,
		"pickup pushes a line into the side feed")
	main._on_pickup_collected("ammo", &"9mm", 18)
	_check(main.hud._feed_items.size() == feed_before + 2,
		"ammo pickup also appears in the side feed")

	# TAB 打开
	main._unhandled_input(_key(KEY_TAB))
	_check(main.backpack.is_open() and main.backpack.visible, "TAB opens the backpack")
	_check(paused, "backpack pauses the run")
	_check(not main.hud.visible and not main.reticle.visible,
		"hud and reticle hide behind the backpack")
	_check(main.backpack.run_count_labels["electronics"].text == "3"
		and main.backpack.run_count_labels["energy"].text == "2"
		and main.backpack.run_count_labels["parts"].text == "5",
		"backpack shows this run's resources")
	_check(main.backpack.run_count_labels["electronic_core"].text == "1",
		"backpack shows this run's advanced resource")
	_check(main.backpack.run_total_label.text.contains("11"),
		"backpack totals run loot (%s)" % main.backpack.run_total_label.text)
	_check(main.backpack.stash_credit_label.text == "64",
		"backpack shows stash credits")
	_check(main.backpack.stash_count_labels["electronics"].text == "5"
		and main.backpack.stash_count_labels["energy"].text == "6"
		and main.backpack.stash_count_labels["parts"].text == "7",
		"backpack shows stash basic resources")
	_check(main.backpack.stash_count_labels["electronic_core"].text == "2"
		and main.backpack.stash_count_labels["military_alloy"].text == "3",
		"backpack shows stash advanced resources")

	# TAB 关闭
	main.backpack._unhandled_input(_key(KEY_TAB))
	_check(not main.backpack.visible and not paused, "TAB closes the backpack and unpauses")
	_check(main.hud.visible and main.reticle.visible, "hud and reticle return")

	# ESC 也能关闭
	main._unhandled_input(_key(KEY_TAB))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main.backpack._unhandled_input(esc)
	_check(not main.backpack.is_open(), "ESC closes the backpack")

	# 撤离入库后，仓库数量增加
	main.loot = {"electronics": 2, "energy": 1, "parts": 1}
	main.advanced_loot = {"weapon_parts": 1}
	main.resources = 4
	main._finish_run(true)
	main.backpack.open()
	_check(main.backpack.stash_count_labels["electronics"].text == "7"
		and main.backpack.stash_count_labels["energy"].text == "7"
		and main.backpack.stash_count_labels["parts"].text == "8",
		"extraction merges run resources into the stash")
	_check(main.backpack.stash_count_labels["weapon_parts"].text == "2",
		"extraction merges advanced resources into the stash")
	main.backpack.close()

	main.queue_free()
	await process_frame
	print("\n=== backpack 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
