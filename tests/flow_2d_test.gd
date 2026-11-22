extends SceneTree
## 2D 玩法闭环测试：搜刮资源 → 撤离成功 / 资源不足拒绝 / 阵亡失败。
## godot --headless --path . --script res://tests/flow_2d_test.gd

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


func _run() -> void:
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_physics_process(false)

	var level: Level2D = main.level
	var doll = main.doll
	_check(level.containers.size() == 52,
		"34 loot containers + 18 decorative searchables generated")

	# 没有资源时撤离应被拒绝
	doll.global_position = level.exit_position
	main.camera.global_position = doll.global_position
	await physics_frame
	await process_frame
	main._try_interact()
	_check(main.run_state == 0, "extraction refused without resources")

	# 搜一个强制为机械零件的箱子：容器产出 2–4 份，直接入背包
	var entry: Dictionary = level.containers[0]
	entry["loot"] = &"parts"
	doll.global_position = entry["position"]
	await physics_frame
	await process_frame
	main._try_interact()
	_check(bool(entry["searched"]), "container becomes searched")
	_check(int(main.loot["parts"]) >= 2 and int(main.loot["parts"]) <= 4,
		"container yields 2-4 parts, got %d" % int(main.loot["parts"]))
	_check(main.resources >= int(main.loot["parts"]),
		"container can also yield other resource types")
	var collected: int = main.resources
	main._try_interact()
	_check(main.resources == collected, "searched container cannot be looted twice")
	main.backpack.open()
	_check(main.backpack.visible and main.backpack.run_count_labels["parts"].text
		== str(int(main.loot["parts"])),
		"backpack shows the parts count for this run")
	main.backpack.close()

	# 医疗箱治疗
	var med: Dictionary = level.containers[1]
	med["loot"] = &"repair"
	doll.hp = 40
	doll.global_position = med["position"]
	await physics_frame
	await process_frame
	main._try_interact()
	_check(doll.hp == 70, "medical container heals 30, hp=%d" % doll.hp)

	# 带资源撤离成功
	doll.global_position = level.exit_position
	await physics_frame
	await process_frame
	main._try_interact()
	_check(main.run_state == 1, "extraction succeeds with resources")
	_check(main.result_label.visible, "success panel shown")
	_check(main.result_label.text.contains("撤离成功"), "success text shown")

	# 死亡失败：重开一局
	main.queue_free()
	await process_frame
	var main2 = load("res://scenes/core/Main2D.tscn").instantiate()
	main2.mouse_aim_enabled = false
	root.add_child(main2)
	await process_frame
	await physics_frame
	for enemy in main2.enemies:
		enemy.set_physics_process(false)
	main2.doll.take_damage(999)
	await process_frame
	_check(main2.run_state == 2, "player death fails the run")
	_check(main2.result_label.visible and main2.result_label.text.contains("阵亡"), "death panel shown")

	print("\n=== flow 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
