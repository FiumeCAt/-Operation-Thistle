extends SceneTree

class InputProbe:
	extends Node
	var presses := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.physical_keycode == KEY_E and event.pressed:
			presses += 1

var _main: Node3D
var _checks := 0
var _fails := 0
var _probe: InputProbe
var _expected_resources := 0
var _expected_remainder := 0.0

func _record_reward(base: int) -> int:
	var value := float(base) * pow(1.05, _main.depth - 1) + _expected_remainder
	var amount := floori(value + 0.000001)
	_expected_remainder = value - amount
	_expected_resources += amount
	return amount

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = InputEventKey.new()
	event.physical_keycode = code
	Input.parse_input_event(event)
	await _frames(2)

func _place(point: Vector3) -> void:
	_main.doll.global_position = point
	_main.doll.velocity = Vector3.ZERO
	await _frames()

func _near_box(index: int) -> StaticBody3D:
	var box: StaticBody3D = _main.level.search_containers[index]
	await _place(Vector3(box.global_position.x - 1.5, 0.02, box.global_position.z))
	return box

func _ammo() -> Dictionary:
	_main.doll.weapon._save_current()
	return _main.doll.weapon._saved.duplicate(true)

func _disable_enemy(node: Node) -> void:
	if node is Enemy:
		node.process_mode = Node.PROCESS_MODE_DISABLED

func _run() -> void:
	print("=== Operation Thistle looting test ===")
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	node_added.connect(_disable_enemy)
	_probe = InputProbe.new()
	_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_probe)
	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	var doll: Doll = _main.doll
	var weapon: PlayerWeapon = doll.weapon
	_check(_main._run_ready, "真实场景已就绪")
	for i in _main.level.search_containers.size():
		var box: StaticBody3D = _main.level.search_containers[i]
		var room_type: String = box.get_meta("room_type")
		var profile: Dictionary = LevelGenerator.ROOM_PROFILES[room_type]
		var effect: Dictionary = box.get_meta("loot_effect")
		_check(effect["type"] in [&"ammo", &"repair", &"resource"], "箱%d 结构化效果属于房间补给类型" % i)
		_check(box.get_meta("loot_weights") == profile["weights"], "箱%d 保留房间掉落权重" % i)
		if box.get_meta("room_slot") == 0:
			_check(effect["type"] == profile["loot"], "箱%d 主容器按房间用途配置" % i)
		var expected_reward := int(profile["reward"])
		if box.get_meta("room_slot") == 1 and room_type in ["控制室", "机房"]:
			expected_reward = 2
		_check(box.get_meta("reward") == expected_reward, "箱%d 按房间用途给资源奖励" % i)
	weapon.set_physics_process(false)
	for id in WeaponDB.WEAPON_ORDER:
		weapon.switch_to(id)
		for ammo_type in weapon._ammo_order(id):
			weapon.ammo_type = ammo_type
			weapon.reserve[ammo_type] = 0
			var before := _ammo()
			var maximum := weapon.current_ammo().reserve_max
			var added := weapon.supply_reserve()
			_check(added == ceili(maximum * 0.5) and weapon.get_reserve() == added, "%s/%s 补当前弹种上限一半" % [id, ammo_type])
			var expected := before.duplicate(true)
			expected[id]["reserve"][ammo_type] = added
			_check(_ammo() == expected, "%s/%s 其他武器、弹种、膛仓和计时不变" % [id, ammo_type])
			weapon.reserve[ammo_type] = maximum - 1
			_check(weapon.supply_reserve() == 1 and weapon.get_reserve() == maximum, "%s/%s 限制备弹上限" % [id, ammo_type])
			_check(weapon.supply_reserve() == 0 and weapon.get_reserve() == maximum, "%s/%s 满备弹返回0" % [id, ammo_type])
	weapon.switch_to(&"m870")
	weapon.ammo_type = &"buckshot"
	var ammo := weapon.current_ammo()
	var old_max := ammo.reserve_max
	ammo.reserve_max = 25
	weapon.reserve[weapon.ammo_type] = 0
	_check(weapon.supply_reserve() == 13, "奇数上限补给向上取整")
	ammo.reserve_max = old_max
	weapon.reserve[weapon.ammo_type] = 2
	weapon.set_physics_process(true)
	var box := await _near_box(0)
	var expected_gain := _record_reward(int(box.get_meta("reward")))
	box.set_meta("loot", "测试展示名")
	box.set_meta("container_kind", "safe")
	# 期望值按当前数据表推算，避免弹药上限调整后测试与实现脱节
	var supply_gain := mini(ceili(ammo.reserve_max * 0.5), ammo.reserve_max - 2)
	_check(_main.interaction_hint.contains(ammo.display_name) and _main.interaction_hint.contains("最多 +%d" % ceili(ammo.reserve_max * 0.5)), "搜索前提示当前弹种与备弹增量上限")
	var before := _ammo()
	var presses := _probe.presses
	await _key(KEY_E)
	_check(_probe.presses == presses + 1 and box.get_meta("searched"), "真实 E 输入触发搜刮")
	_check(weapon.get_reserve() == 2 + supply_gain and _main.resources == _expected_resources, "结构化效果不依赖中文名称或外观类型，同时给资源")
	_check(_main.run_hud._loot.text.contains(ammo.display_name) and _main.run_hud._loot.text.contains("备弹 +%d" % supply_gain) and _main.run_hud._loot.visible, "HUD 显示实际弹种与补给")
	var popup_found := false
	for child in _main.level.get_children():
		if child is Label3D and child.text == _main.run_hud._loot.text:
			popup_found = true
	_check(popup_found, "世界popup与HUD实际收益一致")
	var after := _ammo()
	await _key(KEY_E)
	_check(_ammo() == after and _main.resources == _expected_resources, "重复 E 不再补弹或给资源")
	await _key(KEY_4)
	_check(weapon.weapon_id == &"g17" and _ammo()[&"g17"] == before[&"g17"], "真实切枪保持其他武器状态")
	await _key(KEY_1)
	_check(weapon.weapon_id == &"m870" and weapon.get_reserve() == 2 + supply_gain, "切回原武器不丢失或复制补给")
	doll.hp = 40.0
	await _near_box(1)
	_check(_main.interaction_hint.contains("最多 +30 HP"), "医疗箱搜索前提示即时30HP维修")
	await _key(KEY_E)
	_record_reward(int(_main.level.search_containers[1].get_meta("reward")))
	_check(doll.hp == 70.0 and _main.resources == _expected_resources, "真实E即时维修30HP并保留资源")
	_check(_main.run_hud._loot.text.contains("维修 +30") and _main.run_hud._loot.text.contains("资源 +1"), "医疗反馈包含实际恢复与资源")
	await _key(KEY_E)
	_check(doll.hp == 70.0 and _main.resources == _expected_resources, "重复医疗搜索无收益")
	doll.hp = 95.5
	_check(doll.repair(30.0) == 4.5 and doll.hp == doll.hp_max, "维修实际返回小数差值且不超血上限")
	_check(doll.repair(30.0) == 0.0, "满血恢复返回0")
	_check(doll.repair(-30.0) == 0.0 and doll.hp == doll.hp_max, "负维修不扣血")
	doll.is_dead = true
	doll.hp = 0.0
	_check(doll.repair(30.0) == 0.0 and doll.hp == 0.0 and doll.is_dead, "死亡角色无法复活")
	doll.is_dead = false
	_check(doll.repair(30.0) == 0.0 and doll.hp == 0.0, "零HP角色不能恢复")
	doll.hp = 70.0
	for index in [2, 3]:
		var box3: StaticBody3D = await _near_box(index)
		after = _ammo()
		await _key(KEY_E)
		_record_reward(int(box3.get_meta("reward")))
		_check(_ammo() == after and doll.hp == 70.0 and _main.resources == _expected_resources, "箱%d 仅保留原有资源效果" % index)
	# 找一个尚未搜索的弹药容器验证满备弹仍给资源；房型随机时要按实际配置挑选
	weapon.reserve[weapon.ammo_type] = ammo.reserve_max
	var ammo_index := -1
	for i in range(_main.level.search_containers.size()):
		var candidate: StaticBody3D = _main.level.search_containers[i]
		if candidate.get_meta("searched", false):
			continue
		var effect_candidate: Dictionary = candidate.get_meta("loot_effect", {})
		if effect_candidate.get("type", &"resource") == &"ammo":
			ammo_index = i
			break
	if ammo_index < 0:
		# 房型与额外容器权重都是随机的；没有剩余弹药箱时，把一个未搜索容器指定为弹药效果。
		for i in range(_main.level.search_containers.size()):
			var spare: StaticBody3D = _main.level.search_containers[i]
			if not spare.get_meta("searched", false):
				spare.set_meta("loot_effect", {"type": &"ammo"})
				spare.set_meta("loot", "弹药补给")
				ammo_index = i
				break
	_check(ammo_index >= 0, "存在可用于验证满备弹的容器")
	if ammo_index >= 0:
		var ammo_box: StaticBody3D = await _near_box(ammo_index)
		await _key(KEY_E)
		_record_reward(int(ammo_box.get_meta("reward")))
		_check(weapon.get_reserve() == ammo.reserve_max and _main.resources == _expected_resources, "满备弹弹药箱仍给资源")
		_check(_main.run_hud._loot.text.contains("备弹 +0（已满）"), "满备弹明确显示0与已满")
	weapon.switch_to(&"g17")
	weapon.mag = 1
	weapon.reserve[weapon.ammo_type] = 40
	weapon.reload_magazine()
	weapon.set_physics_process(false)
	before = _ammo()
	var pending := weapon._pending_load
	var total := weapon.get_reserve() + weapon.get_loaded_total() + pending
	var added := weapon.supply_reserve()
	var expected := before.duplicate(true)
	expected[&"g17"]["reserve"][weapon.ammo_type] += added
	_check(pending > 0 and _ammo() == expected, "装填中补给只改备弹，不改pending/load_t/busy_max或膛仓")
	_check(weapon.get_reserve() + weapon.get_loaded_total() + weapon._pending_load == total + added, "装填中含暂存弹药总量守恒")
	weapon.switch_to(&"m870")
	weapon.switch_to(&"g17")
	_check(_ammo() == expected, "装填中补给切枪来回不丢弹不复制")
	await _place(_main.level.exit_position)
	await _key(KEY_E)
	_check(_main.shaft_open and paused, "真实 E 打开竖井")
	var resource_before: int = _main.resources
	await _main.descend()
	await _frames()
	_check(_main.depth == 2 and _ammo() == expected and doll.hp == 70.0 and _main.resources == resource_before, "下潜完整保存装填中补给、其他武器、生命与资源")
	weapon._resolve_load()
	_check(weapon._pending_load == 0 and weapon.get_reserve() + weapon.get_loaded_total() == total + added, "跨层后完成装填仍守恒")
	weapon.load_t = 0.0
	weapon.set_physics_process(true)
	doll.hp = doll.hp_max
	await _near_box(1)
	await _key(KEY_E)
	_check(doll.hp == doll.hp_max and _main.resources == resource_before + 1, "满血医疗箱仍给深度资源奖励")
	_check(_main.run_hud._loot.text.contains("维修 +0 HP（已满）"), "满血明确显示维修0与已满")
	_check(is_equal_approx(_main.reward_remainder, 0.05), "深度奖励小数累计保持")
	await _place(_main.level.exit_position)
	await _key(KEY_E)
	await _main.descend()
	await _frames()
	doll.hp = 97.0
	await _near_box(1)
	await _key(KEY_E)
	_check(doll.hp == doll.hp_max and _main.run_hud._loot.text.contains("维修 +3 HP"), "真实E医疗按剩余3HP封顶并显示实际收益")
	doll._hurt_cd = 0.0
	doll.take_damage(1000.0)
	_check(doll.repair(30.0) == 0.0 and doll.is_dead and doll.hp == 0.0, "实际死亡流程之后维修不能复活")
	print("=== %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	paused = false
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
