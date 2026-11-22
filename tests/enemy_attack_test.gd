extends SceneTree
## 敌人攻击回归：墙体阻挡、射击曳光、近战刀光。
## godot --headless --path . --script res://tests/enemy_attack_test.gd

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


func _has_child_type(parent: Node, type) -> bool:
	for child in parent.get_children():
		if is_instance_of(child, type):
			return true
	return false


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	for enemy in main.enemies:
		enemy.set_process(false)
		enemy.set_physics_process(false)

	var doll = main.doll
	doll.armor = 0
	doll.hp = 100
	doll.invuln = 0.0

	var rifle: Enemy2D = null
	var rusher: Enemy2D = null
	for enemy in main.enemies:
		if enemy.kind == &"rifleman" and rifle == null:
			rifle = enemy
		elif enemy.kind == &"rusher" and rusher == null:
			rusher = enemy
	_check(rifle != null and rusher != null, "test enemies available")
	if rifle == null or rusher == null:
		quit(1)
		return

	# 玩家在仓库区，步枪手在西主廊：射线必须被墙挡住。
	doll.global_position = Vector2(30, 20) * 64.0
	rifle.global_position = Vector2(39, 20) * 64.0
	await physics_frame
	_check(not rifle._line_of_sight(), "wall blocks enemy line of sight")
	rifle._attack_cd = 0.0
	rifle._try_attack(rifle.global_position.distance_to(doll.global_position))
	_check(doll.hp == 100, "enemy cannot damage the player through a wall")

	# 同一段西主廊内：射击应能命中，并生成敌方曳光。
	doll.global_position = Vector2(38, 30) * 64.0
	rifle.global_position = Vector2(39, 37) * 64.0
	await physics_frame
	_check(rifle._line_of_sight(), "clear line of sight inside the same corridor")
	rifle._attack_cd = 0.0
	rifle._try_attack(rifle.global_position.distance_to(doll.global_position))
	_check(_has_child_type(main.sort_layer, EnemyBullet2D),
		"enemy ranged attack spawns a physical bullet")
	var damaged := false
	for i in 120:
		await physics_frame
		if doll.hp < 100:
			damaged = true
			break
	_check(damaged, "rifleman damages the player with a clear shot")

	# 近战：贴脸攻击应产生刀光并造成伤害。
	doll.hp = 100
	doll.invuln = 0.0
	rusher.global_position = doll.global_position + Vector2(56, 0)
	await physics_frame
	_check(rusher._line_of_sight(), "melee enemy has line of sight at close range")
	rusher._attack_cd = 0.0
	rusher._try_attack(56.0)
	_check(doll.hp < 100, "melee attack damages the player")
	_check(_has_child_type(rusher, Line2D), "melee attack spawns a slash arc")

	main.queue_free()
	await process_frame
	print("\n=== enemy attack: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
