extends SceneTree
## WeaponFeedState2D 独立单元测试：验证弹匣/管仓供弹、持续装填、切枪中点换模、收拔枪与浪潮整备回满。
## godot --headless --path . --script res://tests/weapon_feed_state_test.gd

const FEED_STATE := preload("res://scripts/weapons/WeaponFeedState2D.gd")

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
	var feed: WeaponFeedState2D = FEED_STATE.new()
	var g17: WeaponData = WeaponDB.get_weapon(&"g17")
	var m870: WeaponData = WeaponDB.get_weapon(&"m870")
	feed.on_weapon_equipped(&"g17", g17.mag_capacity)

	# 1. 开火消耗与射速冷却
	_check(feed.mag == 17 and feed.try_fire(g17) == &"fired" and feed.mag == 16
		and feed.shots == 1 and feed.cooldown > 0.0,
		"firing decrements mag, increments shots, and starts cooldown")
	_check(feed.try_fire(g17) == &"blocked", "cooldown blocks immediate second shot")

	# 2. 弹匣枪整匣换弹与备弹消耗
	feed.cooldown = 0.0
	feed.mag = 0
	_check(feed.try_fire(g17) == &"need_reload", "empty mag triggers need_reload result")
	var reserve_before := feed.get_reserve(g17)
	_check(feed.reload(g17) and feed.reload_t > 0.0, "reload starts for empty mag")
	var ev := feed.tick(feed.reload_total + 0.01, g17)
	_check(bool(ev["reload_finished"]) and feed.mag == 17
		and feed.get_reserve(g17) == reserve_before - 17,
		"mag reload fills capacity and deducts shared reserve")

	# 3. 切枪中点触发换模，换弹中切枪自动取消换弹
	feed.mag = 10
	feed.reload(g17)
	_check(feed.start_switch(&"m870", g17) == &"animated" and feed.reload_t == 0.0
		and feed.switch_t > 0.0,
		"switching mid-reload cancels reload and starts switch animation")
	var mid_ev := feed.tick(FEED_STATE.SWITCH_TIME * 0.55, g17)
	_check(mid_ev["switch_swap"] == &"m870", "switch midpoint emits swap target")
	feed.on_weapon_equipped(&"m870", m870.mag_capacity)
	feed.tick(FEED_STATE.SWITCH_TIME, m870)
	_check(feed.mag == 5 and feed.weapon_id == &"m870", "m870 equips with 5 shells")

	# 4. 管仓逐发装填 + 持续装填天赋
	feed.mag = 3
	feed.hold_reload_enabled = true
	_check(feed.process_hold_reload(m870) and feed.reload_t > 0.0,
		"hold_reload starts shell reload on tube shotgun")
	feed.tick(feed.reload_total + 0.01, m870)
	_check(feed.mag == 4, "shell reload loads exactly one shell per cycle")

	# 5. 收枪/拔枪与收枪状态扣扳机自动拔枪
	_check(feed.holster() and feed.is_stowing(), "holster starts stow timer")
	var stow_ev := feed.tick(FEED_STATE.HOLSTER_TIME + 0.01, m870)
	_check(bool(stow_ev["holster_completed"]) and feed.holstered,
		"holster completion signals holstered state")
	_check(feed.try_fire(m870) == &"need_draw", "firing while holstered requests draw")
	_check(feed.start_switch(&"g17", m870) == &"instant_holstered",
		"switching while holstered is instant without draw animation")
	feed.draw()
	feed.tick(FEED_STATE.DRAW_TIME + 0.01, m870)

	# 6. 备弹天赋与浪潮回满
	feed.apply_reserve_talent(1.5)
	feed.mag = 1
	feed.set_reserve(m870, 0)
	feed.refill_all_ammo(m870)
	_check(feed.mag == m870.mag_capacity and feed.get_reserve(m870) > 0,
		"refill_all_ammo restores full mag and talent-scaled reserve")

	# 7. 开火模式切换（全自动/半自动）与切枪独立记忆
	var fal: WeaponData = WeaponDB.get_weapon(&"fal")
	_check(feed.supports_full_auto(fal) and feed.get_fire_mode(fal) == "auto" and feed.is_auto_mode(fal),
		"FN FAL supports full-auto and defaults to auto mode")
	var tog1 := feed.toggle_fire_mode(fal)
	_check(bool(tog1["changed"]) and bool(tog1["supported"]) and String(tog1["mode"]) == "semi"
		and not feed.is_auto_mode(fal),
		"toggling FAL switches from full-auto to semi-auto")
	var tog_m870 := feed.toggle_fire_mode(m870)
	_check(not bool(tog_m870["changed"]) and not bool(tog_m870["supported"])
		and feed.get_fire_mode(m870) == "semi",
		"semi-only weapon (M870) rejects full-auto toggle and stays semi")
	# 切枪往返后保持每把武器各自的快慢机档位
	feed.on_weapon_equipped(&"m870", m870.mag_capacity)
	feed.on_weapon_equipped(&"fal", fal.mag_capacity)
	_check(feed.get_fire_mode(fal) == "semi", "FAL retains semi mode after switching weapons")
	var tog2 := feed.toggle_fire_mode(fal)
	_check(bool(tog2["changed"]) and feed.is_auto_mode(fal), "toggling FAL again restores full-auto")

	# 8. Phase 3B: 局内 Q 键 3 档切弹（肉伤 / 常规 / 穿甲）+ 高穿弹备弹点数消耗与退还
	var akm: WeaponData = WeaponDB.get_weapon(&"akm")
	feed.on_weapon_equipped(&"akm", akm.mag_capacity, akm)
	feed.mag = 30
	feed.set_reserve(akm, 90)
	_check(akm.ammo_id == &"762x39", "AKM starts with standard 7.62x39 ammo")
	var sw_ap := feed.start_ammo_switch(akm, 1)
	_check(bool(sw_ap["ok"]) and sw_ap["target"] == &"762x39_ap" and feed.reload_t > 0.0,
		"Q switch starts tactical reload to 7.62x39 AP")
	var sw_ev := feed.tick(feed.reload_total + 0.01, akm)
	# 退还 30*1.0 -> 120 备弹点；装填 30 发 AP（1.5点/发 = 45点）-> 剩 75 点
	_check(sw_ev["ammo_switched"] == &"762x39_ap" and akm.ammo_id == &"762x39_ap"
		and feed.mag == 30 and feed.get_reserve(akm) == 75,
		"switching to 7.62x39 AP refunds std rounds and spends 1.5x reserve points (75 left)")
	# 再次切到肉伤弹（HP，1.0点/发）：退还 30*1.5=45 -> 120 点，装 30 发 HP -> 剩 90 点（无刷弹也无损点）
	var sw_hp := feed.start_ammo_switch(akm, 1)
	_check(bool(sw_hp["ok"]) and sw_hp["target"] == &"762x39_hp",
		"second Q switch cycles cleanly to 7.62x39 flesh ammo")
	feed.tick(feed.reload_total + 0.01, akm)
	_check(akm.ammo_id == &"762x39_hp" and feed.mag == 30 and feed.get_reserve(akm) == 90,
		"switching back to 1.0x ammo restores exact reserve points with zero dupe/loss (90)")

	print("\n=== weapon feed state: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
