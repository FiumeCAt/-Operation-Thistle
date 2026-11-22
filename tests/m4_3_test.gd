extends SceneTree
## M4.3：成长上限、枪械散布、支援次数与存档往返。

var _main: Node3D
var _checks := 0
var _fails := 0
var _progress

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

func _run() -> void:
	print("=== Operation Thistle M4.3 growth test ===")
	create_timer(120.0).timeout.connect(func() -> void: quit(2))
	_progress = root.get_node_or_null("Progress")
	_check(_progress != null, "Progress autoload 存在")
	if _progress == null:
		quit(1)
		return

	# ---- 成长上限与价格
	_progress.reset_for_test()
	_progress.data["resources"] = 5000
	_check(_progress.upgrade_cost(&"hp") == 45, "生命强化首级价格 45")
	_check(_progress.upgrade_cost(&"unknown") == -1, "未知成长项不可购买")
	_check(not _progress.buy_upgrade(&"unknown"), "未知成长项购买失败")

	for i in _progress.upgrade_max(&"hp"):
		_check(_progress.buy_upgrade(&"hp"), "生命强化第 %d 级可购买" % (i + 1))
	_check(_progress.upgrade_level(&"hp") == 5 and _progress.upgrade_cost(&"hp") == -1, "生命强化封顶 5 级")
	_check(not _progress.buy_upgrade(&"hp"), "满级后不能继续购买生命强化")

	for i in _progress.upgrade_max(&"support"):
		_check(_progress.buy_upgrade(&"support"), "支援协议第 %d 级可购买" % (i + 1))
	_check(not _progress.buy_upgrade(&"support") and _progress.upgrade_level(&"support") == 2, "支援协议封顶 2 级")

	for i in _progress.upgrade_max(&"gun"):
		_check(_progress.buy_upgrade(&"gun"), "枪械精度第 %d 级可购买" % (i + 1))
	_check(not _progress.buy_upgrade(&"gun") and _progress.upgrade_level(&"gun") == 3, "枪械精度封顶 3 级")

	var before_resources := int(_progress.data["resources"])
	_check(before_resources == 3920, "购买按等级价格扣费：%d" % before_resources)
	_check(_progress.save_data(), "成长数据可保存")
	var gun_level: int = _progress.upgrade_level(&"gun")
	_progress.data["upgrades"]["gun"] = 0
	_progress.load_data()
	_check(_progress.upgrade_level(&"gun") == gun_level, "重读存档后枪械等级保持")
	var raw := FileAccess.open(_progress.save_path, FileAccess.READ)
	_check(raw != null, "存档文件可读")
	if raw:
		var parsed = JSON.parse_string(raw.get_as_text())
		raw.close()
		_check(typeof(parsed) == TYPE_DICTIONARY and parsed.get("upgrades", {}).has("gun"), "存档包含枪械等级字段")

	# ---- 场景接线：生命、散布、支援次数
	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)

	_progress.data["upgrades"] = {"hp": 2, "support": 2, "gun": 3}
	_main._apply_persistent_upgrades()
	_check(is_equal_approx(_main.doll.hp_max, 130.0), "生命强化 2 级使上限为 130")
	_check(is_equal_approx(_main.doll.weapon.accuracy_multiplier, pow(0.94, 3.0)), "枪械精度 3 级应用 0.94^3 倍率")

	var weapon: PlayerWeapon = _main.doll.weapon
	var upgraded := weapon.get_spread_half_angle()
	weapon.accuracy_multiplier = 1.0
	var baseline := weapon.get_spread_half_angle()
	weapon.accuracy_multiplier = pow(0.94, 3.0)
	_check(upgraded < baseline and absf(upgraded / baseline - pow(0.94, 3.0)) < 0.0001, "散布按成长倍率缩小")

	_check(_main.support_max_uses() == 4, "支援协议 2 级提供 4 次支援")
	_main.support_uses = 4
	_check(not _main.use_support(), "次数用尽后支援不可用")
	_main.support_uses = 0
	_main.support_cooldown = 0.0
	_check(_main.use_support() and _main.support_uses == 1, "仍有次数时支援可用")
	await _frames(2)
	_check(_main.run_hud._support.text.contains("次数 1/4"), "HUD 显示动态支援上限")

	# ---- 干净存档不应污染
	_progress.reset_for_test()
	_main._apply_persistent_upgrades()
	_check(is_equal_approx(_main.doll.weapon.accuracy_multiplier, 1.0), "重置后枪械倍率回到 1.0")
	_check(_main.support_max_uses() == 2, "重置后支援次数回到 2")

	print("=== M4.3 %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
