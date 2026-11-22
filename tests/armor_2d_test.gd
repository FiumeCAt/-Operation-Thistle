extends SceneTree
## RHA 护甲系统回归：未击穿主扣甲+钝伤、击穿直入血+少量甲损、耐久衰减、破甲溢出、最低减伤与 HUD/飘字。
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
	_check(doll.armor == 100 and doll.armor_max == 100 and doll.armor_level == 1
		and is_equal_approx(doll.armor_rha(), 30.0),
		"player starts with 100 armor at Lv1 (30 / 3.0mm RHA)")
	_check(main.hud.armor_label.text.contains("100"), "HUD shows the armor value")

	# 未击穿（30 伤 / 0 AP vs 30 RHA）：主扣护甲 20，少量钝伤 4
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0, 0.0)
	await process_frame
	_check(doll.armor == 80, "unpenetrated hit drains armor mainly, armor=%d" % doll.armor)
	_check(doll.hp == 96, "unpenetrated hit leaves only light blunt damage, hp=%d" % doll.hp)
	_check(main.hud.armor_label.text.contains("80"), "HUD armor value follows damage")
	_check(_has_damage_number(main.fx_layer), "taking damage spawns a floating number")

	# 击穿（30 伤 / 50 AP vs 30 RHA）：直扣血 32（余穿 +2），护甲仅少量穿孔损耗 8
	doll.armor = 100
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0, 50.0)
	_check(doll.armor == 92, "penetrated hit causes only light hole wear, armor=%d" % doll.armor)
	_check(doll.hp == 68, "penetrated hit punches straight into hp with overpen, hp=%d" % doll.hp)

	# 低耐久破甲溢出（armor 10/100 挡 30 伤 0 AP -> 甲归零、溢出 + 钝伤共 14 HP）
	doll.armor = 10
	doll.armor_max = 100
	doll.armor_level = 1
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0, 0.0)
	_check(doll.armor == 0, "damaged armor is consumed to zero, armor=%d" % doll.armor)
	_check(doll.hp == 86, "broken-armor overflow reaches hp, hp=%d" % doll.hp)
	doll.repair_armor(50)
	_check(doll.armor == 50, "repair kit restores armor durability")

	# 空甲：失去护甲基础减伤（20 伤 0 AP -> 掉 20 HP）；若提供最低减伤 20% 则掉 16 HP
	doll.armor = 0
	doll.hp = 100
	doll.min_damage_reduction = 0.0
	doll.invuln = 0.0
	doll.take_damage(20.0, 0.0)
	_check(doll.armor == 0 and doll.hp == 80, "broken armor no longer mitigates")
	doll.hp = 100
	doll.min_damage_reduction = 0.20
	doll.invuln = 0.0
	doll.take_damage(20.0, 0.0)
	_check(doll.armor == 0 and doll.hp == 84, "min_damage_reduction floor still applies when broken")
	doll.min_damage_reduction = 0.0

	# 高 RHA 等级（Lv2 = 50 RHA）可挡下 35 AP 火力，Lv1 (30 RHA) 会被击穿
	doll.armor = 100
	doll.armor_max = 100
	doll.armor_level = 2
	doll.hp = 100
	doll.invuln = 0.0
	doll.take_damage(30.0, 35.0)
	_check(doll.armor < 90 and doll.hp > 85,
		"Lv2 (50 RHA) blocks 35 AP and protects hp (arm=%d hp=%d)" % [doll.armor, doll.hp])

	# 连续未击穿受击：护甲先破，生命仍有剩余
	doll.armor = 100
	doll.armor_max = 100
	doll.armor_level = 1
	doll.hp = 100
	var hits := 0
	while doll.armor > 0 and hits < 20 and doll.hp > 0:
		doll.invuln = 0.0
		doll.take_damage(30.0, 0.0)
		hits += 1
	_check(doll.armor == 0 and doll.hp > 0 and doll.hp < 100,
		"armor breaks before hp (%d hits, hp=%d)" % [hits, doll.hp])

	main.queue_free()
	await process_frame
	print("\n=== armor 2d: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
