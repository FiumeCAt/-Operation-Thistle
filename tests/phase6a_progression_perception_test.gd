extends SceneTree
## Phase 6A 综合回归：
## 1) 非线性 XP 曲线与 Lv.50 上限
## 2) 可开关角色被动（机体适应 +1%/级 基础生命加算 / 行动津贴 +1%/级 结算收益且不作用于 XP）
## 3) 武器等级解锁（18 把武器门禁、旧档已配装兼容、调试临时全解锁）
## 4) 视野距离与广角解耦（远距侦察放大暗视半径、广角半角封顶 82°、无 Y 轴拉伸畸变）
## 5) 声纹感知 Lv.5 解锁声波涟漪并与脚下环共存 + 设置页三档切换持久化
## 6) 闪避基础距离提升（3.2m）+ 战术步幅/疾闪回气双天赋 + 天赋树 15 节点无重叠
## 7) FAL 步枪改用中型弹池（基础备弹 160），与 AWM 重型弹池（40）彻底隔离
## godot --headless --path . --script res://tests/phase6a_progression_perception_test.gd

const META_STORE := preload("res://scripts/core/progress/MetaProgress.gd")
const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")
const DOLL_SCENE := preload("res://scenes/actors/Doll2D.tscn")
const MAIN_SCENE := preload("res://scenes/core/Main2D.tscn")

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


func _near(a: float, b: float, eps := 0.02) -> bool:
	return absf(a - b) <= eps


func _step_physics(frames: int) -> void:
	for _i in frames:
		await physics_frame


func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	var p := root.get_node_or_null("Progress")
	_check(p != null, "Progress autoload available")
	if p == null:
		quit(1)
		return
	p.reset_for_test()

	# ==== 1. 非线性 XP 曲线与 Lv.50 上限 ====
	_check(p.max_level() == 50, "progression max_level is 50")
	var step1 := META_STORE.xp_step_for_level(1)
	var step5 := META_STORE.xp_step_for_level(5)
	var step20 := META_STORE.xp_step_for_level(20)
	var step50 := META_STORE.xp_step_for_level(50)
	_check(step1 == 30 and step5 > step1 and step20 > step5 and step50 == 0,
		"XP step curve increases non-linearly and caps at Lv.50 (step1=%d step5=%d step20=%d)" % [
			step1, step5, step20])
	var roundtrip_ok := true
	for lv in [1, 2, 5, 10, 25, 50]:
		var req := META_STORE.xp_for_level(lv)
		if META_STORE.level_for_xp(req) != lv:
			roundtrip_ok = false
			break
	_check(roundtrip_ok, "level_for_xp(xp_for_level(lv)) == lv across 1..50")
	_check(META_STORE.level_for_xp(99999999) == 50, "huge XP clamps strictly to Lv.50")
	p.set_skill_level(99)
	_check(p.skill_level() == 50 and int(p.data["skill_level"]) == 50,
		"set_skill_level clamps to Lv.50")
	p.reset_for_test()

	# ==== 2. FAL 步枪中型弹池与备弹隔离 ====
	var fal_w := WeaponDB.get_weapon(&"fal")
	var awm_w := WeaponDB.get_weapon(&"awm")
	_check(fal_w.ammo_category == &"medium" and awm_w.ammo_category == &"heavy",
		"FAL uses medium ammo pool while AWM stays on heavy ammo pool")
	var feed := WeaponFeedState2D.new()
	feed.apply_reserve_talent(1.0)
	_check(feed.get_reserve(fal_w) == 160 and feed.get_reserve(awm_w) == 40,
		"FAL base reserve is 160 (medium) vs AWM 40 (heavy)")
	feed.on_weapon_equipped(&"fal", fal_w.mag_capacity, fal_w)
	feed.mag = 0
	feed.finish_reload(fal_w)
	_check(feed.get_reserve(fal_w) == 140 and feed.get_reserve(awm_w) == 40,
		"reloading FAL draws from medium reserve without touching AWM heavy reserve")

	# ==== 3. 武器等级解锁 + 旧档兼容 + 调试临时全解锁 ====
	_check(WeaponDB.unlock_level(&"g17") == 1 and WeaponDB.unlock_level(&"m870") == 1,
		"starter weapons G17 and M870 unlock at Lv.1")
	_check(WeaponDB.unlock_level(&"awm") >= 10 and WeaponDB.unlock_level(&"fal") >= 5,
		"high-tier weapons require higher unlock levels")
	_check(p.is_weapon_unlocked(&"g17") and not p.is_weapon_unlocked(&"awm"),
		"at Lv.1 G17 is unlocked and AWM is locked")
	var blocked := MOD_SERVICE.equip_weapon(p, &"awm", &"g17", &"m870", true)
	_check(not bool(blocked["ok"]) and String(blocked["message"]).contains("Lv."),
		"ModInstallService blocks equipping locked weapon with level message")
	# 旧档兼容：若存档已携带高等级武器，仍允许在主/副槽间切换而不损坏存档。
	p.set_loadout_2d(&"awm", &"g17")
	var legacy_swap := MOD_SERVICE.equip_weapon(p, &"awm", &"awm", &"g17", false)
	_check(bool(legacy_swap["ok"]) and p.loadout_2d() == ["g17", "awm"],
		"legacy save with pre-equipped high-tier weapon remains swappable")
	p.set_loadout_2d(&"g17", &"m870")
	# 调试模式全武器临时解锁：Lv.1 即可解锁并装备 AWM；重置调试后恢复锁定。
	p.set_debug_unlock_all_weapons(true)
	_check(p.is_weapon_unlocked(&"awm"), "debug_unlock_all_weapons unlocks AWM at Lv.1")
	var dbg_eq := MOD_SERVICE.equip_weapon(p, &"awm", &"g17", &"m870", true)
	_check(bool(dbg_eq["ok"]) and p.loadout_2d() == ["awm", "m870"],
		"AWM can be equipped while debug_unlock_all_weapons is ON")
	p.reset_debug()
	_check(not p.debug_unlock_all_weapons() and not p.is_weapon_unlocked(&"awm"),
		"reset_debug clears debug_unlock_all_weapons")
	p.reset_for_test()

	# ==== 4. 角色被动（机体适应 / 行动津贴）+ 视野/声纹/闪避天赋实装 ====
	p.set_skill_level(11)  # Lv.11 -> +10% 机体适应 & +10% 行动津贴
	p.data["talents_2d"]["hp"] = 2         # +30% 生命
	p.data["talents_2d"]["scavenge"] = 2   # +20% 搜刮
	p.data["talents_2d"]["hearing"] = 5    # Lv.5 满级解锁声波涟漪
	p.data["talents_2d"]["vision_range"] = 5  # +50% 视野与暗视距离
	p.data["talents_2d"]["vision_angle"] = 5  # +22° -> 62°/82° 半角
	p.data["talents_2d"]["dodge_dist"] = 5    # +40% 闪避距离
	p.data["talents_2d"]["dodge_cd"] = 5      # -40% 闪避冷却
	p.set_hearing_display_mode("both")
	p.save_data()

	var main = MAIN_SCENE.instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	# 4a) 机体适应与生命天赋加算：100 * (1 + 0.30 + 0.10) = 140（不是乘算 143）。
	_check(main.doll.hp_max == 140,
		"body_adapt passive (+10%% at Lv.11) stacks additively with HP talent (+30%%) -> 140 HP (got %d)" % main.doll.hp_max)
	# 4b) 行动津贴与搜刮天赋加算：1.0 + 0.20 + 0.10 = 1.30。
	_check(_near(main.talent_scavenge, 1.30),
		"ops_stipend passive (+10%) stacks additively with scavenge (+20%) -> 1.30")
	# 4c) 撤离结算验证：XP 不受行动津贴影响（仍为 10 + 4*5 = 30），信用点吃 1.30 加成。
	var xp_before := int(p.data["xp"])
	main.resources = 4
	main._finish_run(true)
	_check(int(p.data["xp"]) - xp_before == 30,
		"ops_stipend passive does NOT inflate XP reward (+30 exact)")
	_check(int(p.credits()) == 26,
		"ops_stipend + scavenge (1.30) boosts extraction credits to 26 (got %d)" % p.credits())

	# 4d) 视野距离与广角解耦 + 暗视放大 + 半角封顶 82° + 无 Y 轴拉伸畸变。
	var fog: VisionFog2D = main.vision
	_check(fog != null, "Main2D constructs VisionFog2D")
	_check(_near(fog.dark_radius_meters(), 4.5 * 1.50),
		"vision_range Lv.5 expands darkvision radius from 4.5m to 6.75m")
	_check(_near(fog.clear_half_deg(), 62.0) and _near(fog.total_half_deg(), 82.0),
		"vision_angle Lv.5 widens cone to 62° clear / 82° total half-angle")
	_check(fog._clear_light.scale.is_equal_approx(Vector2.ONE),
		"VisionFog2D light keeps uniform Vector2.ONE scale without Y-axis distortion")
	fog.level = null
	var origin := Vector2(1728, 1088)
	main.doll.global_position = origin
	fog._aim_angle = 0.0
	# 75° 在默认 60° 之外，但在广角 Lv.5（82°）之内，应处于相对暗(1)；背后 180° 远点（10m）仍为迷雾(0)。
	var side_pt: Vector2 = origin + Vector2.from_angle(deg_to_rad(75.0)) * 10.0 * float(main.TILE)
	var rear_pt: Vector2 = origin + Vector2(-10.0 * float(main.TILE), 0.0)
	_check(fog.tier_at(side_pt) == 1 and fog.tier_at(rear_pt) == 0,
		"vision_angle Lv.5 reveals 75° peripheral target while preserving rear blind spot")
	fog.set_vision_talents(5, 99)
	_check(fog.total_half_deg() <= 82.01, "total_half_deg strictly caps at <= 82° even if over-leveled")

	# 4e) 声纹 Lv.5 共存与三档模式切换。
	var hear: HearingIndicator2D = main.hearing
	_check(hear.is_acoustic_unlocked() and hear.is_acoustic_mode() and hear.is_ring_visible(),
		"hearing Lv.5 with mode='both' enables ripples coexisting with classic ring")
	hear.set_display_mode("ripple")
	_check(hear.is_acoustic_mode() and not hear.is_ring_visible(),
		"hearing mode='ripple' hides foot ring and keeps ripples")
	hear.set_display_mode("ring")
	_check(not hear.is_acoustic_mode() and hear.is_ring_visible(),
		"hearing mode='ring' falls back to classic foot ring")
	hear.set_hearing_level(4)
	hear.set_display_mode("both")
	_check(not hear.is_acoustic_unlocked() and not hear.is_acoustic_mode() and hear.is_ring_visible()
		and _near(hear.hearing_range_meters(), 13.5 * 1.40),
		"hearing Lv.4 stays in classic ring mode at +40% range")

	# 4f) 闪避双天赋应用到 Doll2D。
	_check(_near(main.doll.dodge_dist_mul, 1.40) and _near(main.doll.dodge_cd_mul, 0.60),
		"Main2D applies dodge_dist (+40%) and dodge_cd (-40%) talents to Doll2D")
	main.queue_free()
	await process_frame

	# 4g) 关闭角色被动后，机体适应与行动津贴立即失效（用于裸装测试/挑战）。
	p.set_passive_enabled("body_adapt", false)
	p.set_passive_enabled("ops_stipend", false)
	var main2 = MAIN_SCENE.instantiate()
	main2.mouse_aim_enabled = false
	root.add_child(main2)
	await process_frame
	await physics_frame
	_check(main2.doll.hp_max == 130 and _near(main2.talent_scavenge, 1.20),
		"disabling passives removes Lv.11 HP and stipend bonuses cleanly (HP=%d scavenge=%.2f)" % [
			main2.doll.hp_max, main2.talent_scavenge])
	main2.queue_free()
	await process_frame

	# ==== 5. 闪避天赋实际位移与冷却物理验证 ====
	var stage := Node2D.new()
	root.add_child(stage)
	var doll: Doll2D = DOLL_SCENE.instantiate()
	doll.bounds = Rect2(0, 0, 2400, 1200)
	doll.global_position = Vector2(300, 400)
	doll.dodge_dist_mul = 1.40
	doll.dodge_cd_mul = 0.60
	stage.add_child(doll)
	await physics_frame
	var start_x := doll.global_position.x
	_check(doll.try_dodge(Vector2.RIGHT), "talent-boosted dodge starts cleanly")
	_check(_near(doll._dodge_cd_total, 1.15 * 0.60, 0.03),
		"dodge_cd Lv.5 reduces cooldown from 1.15s to %.2fs" % doll._dodge_cd_total)
	await _step_physics(24)
	var travel_x := doll.global_position.x - start_x
	_check(travel_x >= 250.0 and travel_x <= 325.0,
		"dodge_dist Lv.5 extends 3.2m base roll to ~4.48m (~287px, actual %.1fpx)" % travel_x)
	stage.queue_free()
	await process_frame

	# ==== 6. UI 验证：TalentTree2D 15 节点无重叠 + 被动开关 + SettingsMenu2D 声纹设置 ====
	var overlap := false
	for i in TalentTree2D.NODES.size():
		var ra := Rect2(TalentTree2D.NODES[i]["pos"], TalentTree2D.CARD_SIZE)
		for j in range(i + 1, TalentTree2D.NODES.size()):
			var rb := Rect2(TalentTree2D.NODES[j]["pos"], TalentTree2D.CARD_SIZE)
			if ra.intersects(rb):
				overlap = true
	_check(TalentTree2D.NODES.size() == 15 and not overlap,
		"TalentTree2D defines 15 nodes with zero card overlap")

	var tree_ui := TalentTree2D.new()
	root.add_child(tree_ui)
	await process_frame
	tree_ui.open()
	_check(tree_ui._passive_buttons.has("body_adapt") and tree_ui._passive_buttons.has("ops_stipend"),
		"TalentTree2D exposes toggle buttons for both character passives")
	tree_ui._toggle_passive("body_adapt")
	_check(p.passive_enabled("body_adapt"), "clicking body_adapt passive toggle re-enables it")
	tree_ui.queue_free()

	var settings_ui := SettingsMenu2D.new()
	root.add_child(settings_ui)
	await process_frame
	settings_ui.open()
	_check(settings_ui._hearing_mode_buttons.size() == 3,
		"SettingsMenu2D exposes 3 hearing display mode buttons")
	settings_ui._set_hearing_display_mode("ripple")
	_check(p.hearing_display_mode() == "ripple",
		"SettingsMenu2D persists hearing_display_mode to Progress")
	settings_ui.queue_free()
	await process_frame

	print("\n=== phase 6a progression & perception: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
