extends SceneTree
## 护甲回归：基础 30% 减伤、护甲优先吸收、耐久衰减、AP 穿透与 HUD/飘字。
## godot --headless --path . --script res://tests/armor_2d_test.gd

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


func _has_damage_number(parent: Node) -> bool:
	for child in parent.get_children():
		if child is DamageNumber2D:
			return true
	return false


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

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	var doll = main.doll
	_check(doll.armor == 100 and doll.armor_max == 100 and doll.armor_level == 1,
		"player starts with 100 armor at defense level 1")
	_check(main.hud.armor_label.text.contains("100"), "HUD shows the armor value")

	# 30 伤害：30% 减伤 → 实际 21；护甲吃 16，生命吃 5
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0)
	await process_frame
	_check(doll.armor == 84, "armor absorbs 75%% of the mitigated hit, armor=%d" % doll.armor)
	_check(doll.hp == 95, "hp still takes chip damage, hp=%d" % doll.hp)
	_check(main.hud.armor_label.text.contains("84"), "HUD armor value follows damage")
	_check(_has_damage_number(main.fx_layer), "taking damage spawns a floating number")

	# AP 6（高级穿甲弹）抵消防御等级 → 减伤归零，护甲仍吃 75%
	doll.armor = 100
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0, 6.0)
	_check(doll.armor == 77, "AP removes mitigation but armor still absorbs, armor=%d" % doll.armor)
	_check(doll.hp == 93, "AP hit chips hp for the remainder, hp=%d" % doll.hp)

	# 低耐久时减伤衰减：armor 10/100 → 26 点，护甲打穿并溢出 16
	doll.armor = 10
	doll.armor_max = 100
	doll.armor_level = 1
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0)
	_check(doll.armor == 0, "damaged armor is consumed to zero, armor=%d" % doll.armor)
	_check(doll.hp == 84, "broken-armor overflow reaches hp, hp=%d" % doll.hp)
	doll.repair_armor(50)
	_check(doll.armor == 50, "repair kit restores armor durability")

	# 空甲：完全不打护甲
	doll.armor = 0
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(20.0)
	_check(doll.armor == 0 and doll.hp == 80, "broken armor no longer mitigates")

	# 高防御等级：40% 减伤，护甲吃 14、生命吃 4
	doll.armor = 100
	doll.armor_max = 100
	doll.armor_level = 2
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0)
	_check(doll.armor == 86 and doll.hp == 96,
		"level 2 armor mitigates 40% and protects hp")

	# 连续受击：护甲先破，生命仍有剩余
	doll.armor = 100
	doll.armor_max = 100
	doll.armor_level = 1
	doll.hp = 100
	var hits := 0
	while doll.armor > 0 and hits < 20 and doll.hp > 0:
		doll.invuln = 0.0
		doll.take_damage(30.0)
		hits += 1
	_check(doll.armor == 0 and doll.hp > 0 and doll.hp < 100,
		"armor breaks before hp (%d hits, hp=%d)" % [hits, doll.hp])

	main.queue_free()
	await process_frame
	print("\n=== armor 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
