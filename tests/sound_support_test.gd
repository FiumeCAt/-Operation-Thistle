extends SceneTree
## 声音传播（米）、枪声/脚步声纹、三类支援资源模型。

var _main: Node3D
var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _count_shadow_casters(host: Node) -> int:
	var count := 0
	for child in host.get_children():
		if child is MeshInstance3D and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			count += 1
	return count

func _run() -> void:
	print("=== Operation Thistle sound & support test ===")
	create_timer(120.0).timeout.connect(func() -> void: quit(2))

	# ---- 枪声传播范围（米）
	var expected := {&"m870": 20.0, &"m1014": 20.0, &"saiga12k": 20.0, &"g17": 7.0}
	for id in expected:
		var radius: float = WeaponDB.get_weapon(id).sound_radius
		_check(is_equal_approx(radius, expected[id]), "%s 枪声范围 %.0fm" % [id, radius])
		_check(radius > 0.0 and radius < 32.0, "%s 传播范围已调小" % id)

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var doll: Doll = _main.doll
	_check(doll.shadow != null, "主角有贴地软阴影")
	_check(_count_shadow_casters(doll) > 0, "主角有只投影的阴影体")
	var first_enemy: Enemy = get_nodes_in_group("enemies")[0]
	_check(first_enemy.shadow != null and _count_shadow_casters(first_enemy) > 0, "敌人共用同一套投影")

	# ---- 听觉按米折算：16 听觉 = 1.0 倍
	var sentry := Enemy.new()
	_main.add_child(sentry)
	sentry.set_physics_process(false)
	sentry.setup(doll, &"rifleman")
	await _frames(2)
	sentry.global_position = Vector3(0, 0, 0)
	sentry.state = Enemy.State.PATROL
	sentry.hear_noise(Vector3(0, 0, 11.0), 10.0)
	_check(sentry.state == Enemy.State.PATROL, "标准听觉 10m 外听不到")
	sentry.state = Enemy.State.PATROL
	sentry.hear_noise(Vector3(0, 0, 9.0), 10.0)
	_check(sentry.state == Enemy.State.SUSPICIOUS, "标准听觉 10m 内听得到")

	# ---- 猎手听觉更远：22/16 倍率
	var hunter := Enemy.new()
	_main.add_child(hunter)
	hunter.set_physics_process(false)
	hunter.setup(doll, &"hunter")
	await _frames(2)
	hunter.global_position = Vector3(0, 0, 0)
	hunter.state = Enemy.State.PATROL
	hunter.hear_noise(Vector3(0, 0, 13.0), 10.0)
	_check(hunter.state == Enemy.State.SUSPICIOUS, "猎手在 10m 基础范围外仍能听到")
	hunter.state = Enemy.State.PATROL
	hunter.hear_noise(Vector3(0, 0, 14.5), 10.0)
	_check(hunter.state == Enemy.State.PATROL, "猎手仍受自身听觉上限约束")

	# ---- 常驻听觉指示：脚下细环 + 方向弧，不再重复生成扩散特效
	doll.global_position = Vector3(0, 0.02, 0)
	var indicator: HearingIndicator = _main.hearing_indicator
	_check(indicator != null and indicator.visible, "行动中显示听觉指示")
	var nodes_before := get_nodes_in_group("combat_feedback").size()
	hunter.global_position = doll.global_position + Vector3(0, 0, 6.0)
	hunter.velocity = Vector3(2.0, 0.0, 0.0)
	await _frames(20)
	_check(get_nodes_in_group("combat_feedback").size() == nodes_before, "脚步不再生成扩散特效")
	var lit := 0
	for arc in indicator._arcs:
		if arc.visible:
			lit += 1
	_check(lit > 0, "10m 内移动的敌人点亮方向弧")
	var facing_arc: MeshInstance3D = indicator._arcs[3]
	_check(facing_arc.visible, "方向弧指向敌人所在方位")
	hunter.global_position = doll.global_position + Vector3(0, 0, 11.0)
	await _frames(40)
	lit = 0
	for arc in indicator._arcs:
		if arc.visible:
			lit += 1
	_check(lit == 0, "超出 10m 后方向弧熄灭")
	hunter.free()
	sentry.free()
	await _frames(2)

	# ---- 枪声半透明细线
	var gun_before := get_nodes_in_group("combat_feedback").size()
	ImpactFX.gunshot_wave(_main, doll.global_position, 20.0)
	await _frames(1)
	var gun_waves := get_nodes_in_group("combat_feedback")
	_check(gun_waves.size() == gun_before + 1, "枪声冲击波已生成")
	if gun_waves.size() > gun_before:
		var gun_mat: StandardMaterial3D = gun_waves.back().material_override
		_check(gun_mat.albedo_color.a > 0.2 and gun_mat.albedo_color.a < 0.6, "枪声波为半透明")
		_check(not gun_mat.no_depth_test, "枪声波不穿墙")

	# ---- 支援分类
	_check(SupportDB.Scope.size() == 3, "支援分为三种资源模型")
	_check(int(SupportDB.protocol(&"self_heal")["scope"]) == SupportDB.Scope.RECHARGE, "自主恢复可重复使用")
	_check(int(SupportDB.protocol(&"sniper")["scope"]) == SupportDB.Scope.PER_LEVEL, "狙击支援每层限用")

	doll.hp = 50.0
	_main.heal_cooldown = 0.0
	_check(_main.use_heal_support() and is_equal_approx(doll.hp, 75.0), "自主恢复一次 +25 HP")
	_check(_main.heal_cooldown > 0.0, "使用后进入冷却")
	_check(not _main.use_heal_support(), "冷却期间不能重复恢复")
	doll.hp = doll.hp_max
	_main.heal_cooldown = 0.0
	_check(not _main.use_heal_support() and _main.heal_cooldown == 0.0, "满血不消耗恢复冷却")

	_main.support_uses = 0
	_main.support_cooldown = 0.0
	_check(_main.support_remaining(SupportDB.Scope.PER_LEVEL) == _main.support_max_uses(), "狙击剩余次数等于上限")
	_check(_main.use_support(), "狙击支援可用")
	_check(_main.support_uses == 1 and _main.support_cooldown > 0.0, "使用后计数与冷却生效")
	_check(_main.support_remaining(SupportDB.Scope.PER_LEVEL) == _main.support_max_uses() - 1, "剩余次数递减")

	# ---- 下潜重置每层限用
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	_main.resources = 1
	doll.global_position = _main.level.exit_position
	await _frames()
	_check(_main.open_shaft(), "打开竖井")
	_main.descend()
	while _main.transitioning:
		await physics_frame
	_check(_main.support_uses == 0, "下潜后狙击次数重置")
	_check(_main.support_run_uses == 0, "每局计数保留在下潜流程中")
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)

	print("=== SOUND/SUPPORT %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	paused = false
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
