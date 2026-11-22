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
var _deaths := 0

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

func _ammo() -> Dictionary:
	var weapon: PlayerWeapon = _main.doll.weapon
	weapon._save_current()
	return weapon._saved.duplicate(true)

func _restart(baseline: Dictionary, old_enemies: Array) -> void:
	var old_id := _main.get_instance_id()
	_main.run_hud._restart.pressed.emit()
	_check(_main.run_hud._at_base and paused, "结算返回无存档简易基地")
	_main.run_hud._restart.pressed.emit()
	_check(_main.get_instance_id() == old_id and not _main.in_base, "同一场景实例重新出发")
	await _frames(10)
	_check(not _main.doll.is_dead and _main.doll.hp == _main.doll.hp_max and not _main.run_hud._result.visible, "重新出发后玩家与结算 UI 重置")
	_check(_main._run_ready and not paused, "重新生成关卡并解除暂停")
	_check(_main.run_state == _main.RunState.ACTIVE and _main.resources == 0 and _main.extracted_resources == 0, "重开局状态及资源重置")
	_check(not _main.rig.orbit_dragging and is_zero_approx(_main.rig.rotation.y), "重开镜头yaw归零且无残留拖动")
	var boxes_clean: bool = _main.level.search_containers.size() >= 5
	for box in _main.level.search_containers:
		boxes_clean = boxes_clean and not box.get_meta("searched")
	_check(boxes_clean, "重开全部容器未搜索")
	var enemies := get_nodes_in_group("enemies")
	var fresh := enemies.size() == old_enemies.size()
	for enemy in enemies:
		fresh = fresh and not old_enemies.has(enemy.get_instance_id())
	_check(fresh, "重开敌人数量恢复且实例全新")
	_check(_ammo() == baseline and _main.doll.weapon.shots == 0, "重开四把武器全部弹药与计数恢复")

func _enemy_ids() -> Array:
	var ids := []
	for enemy in get_nodes_in_group("enemies"):
		ids.append(enemy.get_instance_id())
	return ids

func _pause_combat() -> void:
	var weapon: PlayerWeapon = _main.doll.weapon
	var before := _ammo()
	var shots := weapon.shots
	var hp: float = _main.doll.hp
	var duration: float = _main.elapsed_time
	var enemy_states := []
	for enemy in get_nodes_in_group("enemies"):
		enemy_states.append([enemy.global_position, enemy.hp, enemy._state_t])
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await _key(KEY_R)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(event)
	await _frames(12)
	_check(weapon.shots == shots and _ammo() == before and _main.doll.hp == hp, "结算暂停后真实开火换弹输入不能战斗")
	var unchanged := true
	var enemies := get_nodes_in_group("enemies")
	for i in enemies.size():
		unchanged = unchanged and enemy_states[i] == [enemies[i].global_position, enemies[i].hp, enemies[i]._state_t]
	_check(unchanged and _main.elapsed_time == duration, "暂停后敌人及局计时冻结")

func _run() -> void:
	print("=== Operation Thistle run loop test ===")
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	_probe = InputProbe.new()
	_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(_probe)
	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	var baseline := _ammo()
	var old_enemies := _enemy_ids()
	_check(_main._run_ready and _main.level.search_containers.size() >= 5, "真实场景生成多个资源箱")
	var kinds := ["ammo_box", "medical_box", "material_box", "drawer_cabinet", "safe"]
	var sizes := [Vector3(1.1, 0.65, 0.9), Vector3(1.0, 0.75, 0.9), Vector3(1.1, 0.7, 1.0), Vector3(0.85, 1.6, 0.85), Vector3(1.0, 1.35, 1.0)]
	for i in _main.level.search_containers.size():
		var container: StaticBody3D = _main.level.search_containers[i]
		var art := container.get_node("ContainerArt") as Sprite3D
		var old_hidden: bool = not container.get_meta("marker").visible
		var collision: CollisionShape3D
		for child in container.get_children():
			if child is MeshInstance3D:
				old_hidden = old_hidden and not child.visible
			elif child is CollisionShape3D:
				collision = child
		_check(old_hidden, "容器%d 旧mesh与marker隐藏" % i)
		_check(container.get_meta("container_kind") == kinds[i % kinds.size()] and collision.shape.size.is_equal_approx(sizes[i % sizes.size()]), "容器%d 类型及独立碰撞尺寸" % i)
		_check(is_equal_approx(collision.global_position.y - collision.shape.size.y * 0.5, 0.0), "容器%d 碰撞底部落地" % i)
		_check(art.billboard == BaseMaterial3D.BILLBOARD_ENABLED and is_equal_approx(art.global_position.y, 0.03) and is_equal_approx(art.offset.y, art.region_rect.size.y * 0.5), "容器%d billboard底部锚定" % i)
		_check(art.region_enabled and art.region_rect.size.x < art.texture.get_width() and art.region_rect.size.y < art.texture.get_height(), "容器%d alpha区域裁切" % i)
	_check(not _main.try_interact() and _main.resources == 0, "出生点远距搜索无效")
	await _key(KEY_E)
	_check(_main.resources == 0, "远距 E 输入搜索无效")
	await _place(_main.level.exit_position)
	await _key(KEY_E)
	_check(_main.run_state == _main.RunState.ACTIVE and paused and _main.run_hud._extract.disabled and _main.resources == 0, "零资源 E 打开竖井但不能撤离")
	_main.cancel_shaft()
	var box: StaticBody3D = _main.level.search_containers[0]
	await _place(Vector3(box.global_position.x - 1.5, 0.02, box.global_position.z))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = box.global_position + Vector3(-0.8, 0.4, 0.0)
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = Vector3(0.15, 2.0, 2.0)
	shape.shape = geometry
	wall.add_child(shape)
	_main.add_child(wall)
	await _frames()
	_check((_main.doll.global_position + Vector3.UP * 0.8).distance_to(box.global_position) < _main.INTERACT_RANGE, "隔墙测试在交互距离内")
	await _key(KEY_E)
	_check(_main.resources == 0 and not box.get_meta("searched"), "真实物理墙遮挡时 E 搜索无效")
	wall.queue_free()
	await _frames()
	var map: RID = _main.level.nav_region.get_navigation_map()
	var expected_resources := 0
	for i in _main.level.search_containers.size():
		box = _main.level.search_containers[i]
		expected_resources += int(box.get_meta("reward", 1))
		var point := Vector3(box.global_position.x - 1.5, 0.02, box.global_position.z)
		var path := NavigationServer3D.map_get_path(map, _main.level.player_spawn, point, true)
		var reach := path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
		# 小房间较窄，导航终点可能落在离箱子一格的位置；只要走进交互距离即视为可达
		_check(path.size() > 1 and reach.distance_to(box.global_position) <= _main.INTERACT_RANGE,
			"箱%d 从出生点可走到交互距离内" % i)
		await _place(point)
		var presses := _probe.presses
		await _key(KEY_E)
		_check(_probe.presses == presses + 1 and _main.resources == expected_resources and box.get_meta("searched"), "箱%d E 经实际 _input 分发按房间奖励搜索" % i)
		_check(box.get_node("ContainerArt").modulate == Color(0.3, 1.0, 0.55) and box.get_node("ContainerLabel").modulate == Color(0.3, 1.0, 0.55), "箱%d 搜索后图像与标签变绿" % i)
		_check(not box.get_meta("marker").visible, "箱%d 搜索后marker仍隐藏" % i)
		await _key(KEY_E)
		_check(_main.resources == expected_resources, "箱%d 重复搜索不增资源" % i)
	for id in WeaponDB.WEAPON_ORDER:
		_main.doll.weapon.switch_to(id)
		_main.doll.weapon.mag = 0
		_main.doll.weapon.reserve[_main.doll.weapon.ammo_type] = 0
	var victim: Enemy = get_nodes_in_group("enemies")[0]
	victim.on_hit(victim.global_position, Vector3.UP, 10000.0, 100.0)
	await _frames(4)
	await _place(_main.level.exit_position)
	var presses := _probe.presses
	await _key(KEY_E)
	_check(_main.shaft_open and paused, "E 经实际 _input 打开竖井选择")
	_main.run_hud._extract.pressed.emit()
	_check(_probe.presses == presses + 1 and _main.run_state == _main.RunState.SUCCESS and paused, "竖井按钮触发成功撤离")
	_check(_main.extracted_resources == expected_resources and _main.run_hud._result.visible, "成功带出房间奖励并显示结算")
	var summary: String = _main.run_hud._summary.text
	_main.run_hud._result.hide()
	_main.finish_run(true)
	_main.finish_run(false)
	_check(not _main.run_hud._result.visible and _main.run_hud._summary.text == summary and _main.extracted_resources == expected_resources, "成功重复请求不再次显示结算或覆盖结果")
	_main.run_hud._result.show()
	await _pause_combat()
	await _restart(baseline, old_enemies)
	old_enemies = _enemy_ids()
	box = _main.level.search_containers[0]
	await _place(Vector3(box.global_position.x - 1.5, 0.02, box.global_position.z))
	await _key(KEY_E)
	_main.doll.died.connect(func() -> void: _deaths += 1)
	_main.doll._hurt_cd = 0.0
	_main.doll.take_damage(1000.0)
	_check(_main.run_state == _main.RunState.FAILED and paused and _main.doll.is_dead and _main.extracted_resources == 0, "死亡失败且不带出已搜资源")
	summary = _main.run_hud._summary.text
	_main.run_hud._result.hide()
	_main.doll._hurt_cd = 0.0
	_main.doll.take_damage(1000.0)
	_main.finish_run(false)
	_main.finish_run(true)
	_check(_deaths == 1 and not _main.run_hud._result.visible and _main.run_hud._summary.text == summary, "死亡信号和失败结算各仅一次")
	_main.run_hud._result.show()
	await _pause_combat()
	await _restart(baseline, old_enemies)
	print("=== %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	paused = false
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
