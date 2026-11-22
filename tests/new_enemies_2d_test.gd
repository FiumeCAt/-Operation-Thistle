extends SceneTree
## 四台新敌人的实装回归：动画节点、行为参数、双发、冲锋、自爆伤敌。
## godot --headless --path . --script res://tests/new_enemies_2d_test.gd

var _pass := 0
var _fail := 0
var _main = null


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
	# 保证测试固定使用设施/普通行动，避免上一个测试留下的浪潮地图状态影响行为。
	var p := root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.data["run_mode"] = "raid"
		p.data["map_id"] = "facility"
	_main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	var arena := Vector2(60.0, 44.0) * 64.0
	_main.doll.global_position = arena
	_main.doll.hp_max = 99999.0
	_main.doll.hp = 99999.0
	_main.mouse_aim_enabled = false
	for e in _main.enemies.duplicate():
		e.queue_free()
	_main.enemies.clear()
	await process_frame

	# 图集 / 动画
	for kind in [&"mobile_turret", &"sentry_type1", &"hunter_type1", &"goliath"]:
		var probe := Enemy2D.new()
		probe.setup(kind, arena + Vector2(0, 600), 1)
		_main.sort_layer.add_child(probe)
		_check(probe._anim != null, String(kind) + " 使用 AnimatedSprite2D")
		if probe._anim != null and probe._anim.sprite_frames != null:
			var sf: SpriteFrames = probe._anim.sprite_frames
			_check(sf.get_frame_count("move") == 4, String(kind) + " move 4 帧")
			_check(sf.get_frame_count("death") == 4, String(kind) + " death 4 帧")
			_check(sf.get_frame_count("attack") == 4, String(kind) + " attack 4 帧")
			_check(sf.get_frame_count("alert") == 4, String(kind) + " alert 4 帧")
			_check(not sf.get_animation_loop("death"), String(kind) + " death 不循环")
		probe.queue_free()
	# 关卡刷新池
	var in_roster := {}
	for profile in Level2D.ROOM_DEFS:
		for kind in profile.get("roster", []):
			in_roster[kind] = true
	for patrol in Level2D.RING_PATROLS:
		in_roster[patrol.get("kind", &"")] = true
	for kind in [&"mobile_turret", &"sentry_type1", &"hunter_type1", &"goliath"]:
		_check(in_roster.has(kind), String(kind) + " 已加入关卡刷新池")
	_check(String(EnemyDB.stats(&"mobile_turret")["name"]) == "移动哨戒炮一型", "哨戒炮名称修正")
	_check(String(EnemyDB.stats(&"goliath")["name"]) == "歌利亚通用一型", "歌利亚名称修正")
	_check(float(EnemyDB.stats(&"goliath")["explode_delay"]) > 0.0, "歌利亚引信时间已配置")

	# 双发炮塔 + 激光锁定
	var turret := Enemy2D.new()
	turret.setup(&"mobile_turret", arena + Vector2(220, 0), 1)
	_main.sort_layer.add_child(turret)
	_main.enemies.append(turret)
	var saw_laser := false
	for i in 90:
		await physics_frame
		if turret._laser_on:
			saw_laser = true
			break
	_check(saw_laser, "移动哨戒炮开火前显示红色激光锁定")
	var lock_pos: Vector2 = turret.global_position
	var saw_burst := false
	for i in 300:
		await physics_frame
		if turret._burst_left > 0:
			saw_burst = true
			break
	_check(saw_burst, "移动哨戒炮一次攻击进入双发队列")
	_check(turret._turret_locked, "锁定结束后进入开火状态")
	_check(turret._laser_on, "开火时红色激光保留")
	_check(turret.global_position.distance_to(lock_pos) < 0.5, "锁定与开火期间哨戒炮原地不动")
	await physics_frame
	var bullets := 0
	for child in _main.sort_layer.get_children():
		if child is EnemyBullet2D:
			bullets += 1
	_check(bullets > 0, "哨戒炮发射可见实体子弹")
	_check(is_equal_approx(EnemyBullet2D.BASE_SPEED * EnemyBullet2D.SPEED_SCALE, 450.0),
		"哨戒炮子弹速度为原来的一半")
	_check(is_equal_approx(EnemyBullet2D.BASE_RADIUS * EnemyBullet2D.RADIUS_SCALE, 6.0),
		"哨戒炮子弹大小为原来的 1.5 倍")

	# 冲锋哨兵
	var sentry := Enemy2D.new()
	sentry.setup(&"sentry_type1", arena + Vector2(-420, 0), 1)
	_main.sort_layer.add_child(sentry)
	_main.enemies.append(sentry)
	sentry.view_dir = (_main.doll.global_position - sentry.global_position).normalized()
	var saw_charge := false
	for i in 360:
		await physics_frame
		if sentry._charge_t > 0.0:
			saw_charge = true
			break
	_check(saw_charge, "哨兵一型发现玩家后进入冲锋")

	# 自爆伤害敌人（直接触发，避免时序抖动）
	var victim := Enemy2D.new()
	victim.setup(&"sentry_type1", arena + Vector2(0, 900), 1)
	_main.sort_layer.add_child(victim)
	var bomber := Enemy2D.new()
	bomber.setup(&"goliath", arena + Vector2(40, 900), 1)
	_main.sort_layer.add_child(bomber)
	await process_frame
	var before := victim.hp
	bomber._explode_damage()
	_check(victim.hp < before, "哥利亚爆炸对附近敌人造成伤害")
	victim.queue_free()
	bomber.queue_free()

	# 自爆优先于死亡：致命伤害只把血量压到 1 点并点燃引信，单位仍然存活。
	var bystander := Enemy2D.new()
	bystander.setup(&"sentry_type1", arena + Vector2(0, 1200), 1)
	_main.sort_layer.add_child(bystander)
	var killed := Enemy2D.new()
	killed.setup(&"goliath", arena + Vector2(40, 1200), 1)
	_main.sort_layer.add_child(killed)
	await process_frame
	var bystander_hp := bystander.hp
	killed.take_damage(99999.0)
	_check(not killed._dead and killed.hp == 1.0 and not killed._exploded,
		"哥利亚被打到 1 血时不死亡")
	_check(killed._explode_t > 0.0, "哥利亚被打到 1 血时进入自爆状态")
	await physics_frame
	await physics_frame
	_check(bystander.hp == bystander_hp, "引信期间不会瞬间爆炸")
	# 自爆期间受击：剩余引信缩短 20%。
	var fuse_before: float = killed._explode_t
	killed.take_damage(10.0)
	_check(is_equal_approx(killed._explode_t, fuse_before * 0.8),
		"自爆期间每受击一次缩短 20% 剩余引信")
	killed._explode_t = 0.02
	for i in 8:
		await physics_frame
	_check(killed._exploded and killed._dead, "自爆时同时死亡")
	_check(bystander.hp < bystander_hp, "自爆造成范围伤害")
	bystander.queue_free()
	killed.queue_free()

	# 音效资源
	var sfx = root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload 存在")
	if sfx != null:
		for kind in ["turret_lock", "turret_shot", "charge_up", "ram", "stab",
				"fuse", "fuse_long", "boom", "metal_hit", "enemy_death", "enemy_alert"]:
			_check(sfx.streams.has(kind), "新敌人音效 " + kind)

	print("NEW ENEMIES: %d checks, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
