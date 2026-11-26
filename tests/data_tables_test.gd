extends SceneTree
## 数据表回归：data/*.json 能被加载并驱动各 DB。
## godot --headless --path . --script res://tests/data_tables_test.gd

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
	await process_frame

	# ---- 敌人表 ----
	var enemies := GameData.table("enemies")
	_check(not enemies.is_empty(), "enemies.json 已加载")
	_check(EnemyDB.ORDER.size() == 4, "当前敌人 order = 4")
	_check(EnemyDB.DATA.has(&"rifleman"), "rifleman 存在于敌人表")
	var rifle := EnemyDB.stats(&"rifleman")
	for key in ["hp", "speed", "damage", "range", "view_range", "hearing",
			"cooldown", "body_scale", "collision_radius"]:
		_check(rifle.has(key), "rifleman 字段 " + key)

	var new_ids := EnemyDB.new_units()
	_check(new_ids.size() == 4, "新单位 = 4")
	for id in new_ids:
		var stats := EnemyDB.stats(id)
		_check(EnemyDB.has(id), "新单位在表内：" + String(id))
		_check(stats.has("behavior") and stats.has("sheet"), "新单位行为/图集：" + String(id))
		_check(float(stats.get("hp", 0.0)) > 0.0, "新单位血量 > 0：" + String(id))
	_check(float(EnemyDB.stats(&"hunter_type1")["hp"]) > float(rifle["hp"]), "巡猎者血量高于哨兵")
	_check(float(EnemyDB.stats(&"sentry_type1")["charge_speed"]) > float(EnemyDB.stats(&"sentry_type1")["speed"]), "哨兵一型冲锋速度更高")
	_check(bool(EnemyDB.stats(&"goliath").get("death_explode", false)), "哥利亚死亡爆炸开关")

	# ---- 武器 / 弹药 ----
	_check(WeaponDB.WEAPON_ORDER.size() == 18, "武器 order = 18")
	var g17 := WeaponDB.get_weapon(&"g17")
	_check(g17.mag_capacity == 17, "G17 弹容 17")
	_check(is_equal_approx(g17.fire_interval, 0.11), "G17 射速间隔 0.11")
	_check(is_equal_approx(g17.sound_radius, 7.0), "G17 枪声 7m")
	var m870 := WeaponDB.get_weapon(&"m870")
	_check(m870.feed_mode == &"shell" and not m870.auto_cycle, "M870 管仓/手动循环")
	var ammo := WeaponDB.ammo_table()
	_check(ammo.size() == 30, "弹药 30 种（10 口径 × 3 档肉伤/常规/穿甲）")
	var all_calibers_have_three := true
	for wid in WeaponDB.WEAPON_ORDER:
		if WeaponDB.ammo_for_weapon(wid).size() != 3:
			all_calibers_have_three = false
	_check(all_calibers_have_three, "全部 18 把武器所属口径均有 3 种可携带切换弹药")
	var all_reserve_cost_unity := true
	var all_tiers_match_rha := true
	for aid in ammo:
		var ad: AmmoData = ammo[aid]
		if not is_equal_approx(ad.reserve_cost, 1.0):
			all_reserve_cost_unity = false
		if ad.tier != WeaponDB.tier_from_rha(ad.ap):
			all_tiers_match_rha = false
	var raw_ammo_data: Dictionary = GameData.table("ammo").get("data", {})
	_check(not WeaponDB.differential_reserve_cost_enabled() and all_reserve_cost_unity,
		"差分备弹消耗当前已停用，全部 30 种弹药统一 1.0 点/发")
	_check(float(raw_ammo_data.get("9mm_ap", {}).get("reserve_cost_diff", 1.0)) >= 1.5
		and float(raw_ammo_data.get("762nato_ap", {}).get("reserve_cost_diff", 1.0)) >= 2.0,
		"高穿弹差分倍率（reserve_cost_diff）已保留在数据表中供后续按需开启")
	_check(all_tiers_match_rha, "全部 30 种弹药的 AP 值与新 T0-T6 穿甲档位区间严格一致")
	_check(WeaponDB.get_weapon(&"m870").damage_mul > WeaponDB.get_weapon(&"saiga12k").damage_mul
		and WeaponDB.get_weapon(&"sr25").damage_mul > WeaponDB.get_weapon(&"fal").damage_mul
		and WeaponDB.get_weapon(&"g17").damage_mul > WeaponDB.get_weapon(&"g18").damage_mul,
		"武器固有属性加成拉开了同口径武器定位差异（M870>Saiga / SR25>FAL / G17>G18）")
	_check(StringName(EnemyDB.stats(&"hunter_type1").get("archetype", "")) == &"mech"
		and StringName(EnemyDB.stats(&"rifleman").get("archetype", "")) == &"human"
		and float(EnemyDB.archetype_profile(&"mutant").get("flesh_mul", 1.0)) > 1.1,
		"敌人表已接入三系生态（mech / human / mutant）与参数配置")
	var categories := WeaponDB.category_table()
	_check(categories.size() == 5, "通用弹药 5 类")
	_check(WeaponDB.get_weapon(&"g17").ammo_category == &"light"
		and WeaponDB.get_weapon(&"akm").ammo_category == &"medium"
		and WeaponDB.get_weapon(&"fal").ammo_category == &"medium"
		and WeaponDB.get_weapon(&"awm").ammo_category == &"heavy"
		and WeaponDB.get_weapon(&"m870").ammo_category == &"shotgun",
		"武器映射到通用弹药种类（FAL 走中型弹池，与 AWM 重型弹分离）")
	_check(int(categories["medium"]["reserve_max"]) == 160, "中型弹通用备弹 160")
	_check(WeaponDB.category_of(&"9mm") == &"light"
		and WeaponDB.category_of(&"45acp") == &"light"
		and WeaponDB.category_of(&"556nato") == &"medium"
		and WeaponDB.category_of(&"762nato") == &"heavy"
		and WeaponDB.category_of(&"buckshot") == &"shotgun",
		"口径映射到通用弹药种类")
	_check(int(ammo[&"buckshot"].pellets) == 8, "鹿弹 8 弹丸")
	_check(is_equal_approx(ammo[&"buckshot"].spread, 0.165), "弹药散布不再叠加全局乘数")
	_check(is_equal_approx(ammo[&"9mm"].ads_spread_mul, 0.62)
		and is_equal_approx(ammo[&"9mm"].attachment_spread_scale, 0.80),
		"9mm 开镜收紧 38% / 配件收益 80%")
	_check(is_equal_approx(ammo[&"buckshot"].ads_spread_mul, 0.80)
		and is_equal_approx(ammo[&"buckshot"].attachment_spread_scale, 0.55),
		"鹿弹开镜收紧弱 / 配件收益低")
	_check(is_equal_approx(ammo[&"556nato"].ads_spread_mul, 0.45)
		and is_equal_approx(ammo[&"556nato"].attachment_spread_scale, 1.0),
		"5.56 开镜收紧强 / 配件完整生效")
	_check(is_equal_approx(ammo[&"556nato"].muzzle_velocity_mps, 940.0)
		and is_equal_approx(ammo[&"556nato"].bullet_time_scale, 0.294)
		and is_equal_approx(ammo[&"556nato"].drag_per_m, 0.0035),
		"5.56 初速 940 m/s / 时间压缩 0.294（旧手感补偿）/ 衰减 0.0035")
	_check(is_equal_approx(ammo[&"45acp"].muzzle_velocity_mps, 260.0)
		and ammo[&"45acp"].muzzle_velocity_mps < ammo[&"9mm"].muzzle_velocity_mps
		and ammo[&"9mm"].muzzle_velocity_mps < ammo[&"762nato"].muzzle_velocity_mps,
		"弹速排序：.45 < 9mm < 7.62 NATO")
	_check(ammo[&"buckshot"].muzzle_velocity_mps < ammo[&"slug"].muzzle_velocity_mps
		and ammo[&"9x39"].muzzle_velocity_mps < ammo[&"9mm"].muzzle_velocity_mps,
		"鹿弹慢于独头 / 9×39 亚音速慢于 9mm")
	_check(is_equal_approx(WeaponDB.get_weapon(&"g17").bullet_speed_mps, 380.0)
		and is_equal_approx(WeaponDB.get_weapon(&"tmp").bullet_speed_mps, 334.0)
		and is_equal_approx(WeaponDB.get_weapon(&"sr25").bullet_speed_mps, 890.0),
		"武器子弹速度：G17 380 / TMP 334 / SR-25 890 m/s")
	var all_weapons_have_speed := true
	var all_weapons_ads_valid := true
	for wid in WeaponDB.WEAPON_ORDER:
		var wd := WeaponDB.get_weapon(wid)
		if float(wd.bullet_speed_mps) <= 0.0:
			all_weapons_have_speed = false
		var ads_t := float(wd.ads_time)
		match wd.category:
			&"pistol":
				if ads_t < 0.12 or ads_t > 0.16:
					all_weapons_ads_valid = false
			&"smg":
				if ads_t < 0.18 or ads_t > 0.22:
					all_weapons_ads_valid = false
			&"shotgun", &"rifle":
				if ads_t < 0.24 or ads_t > 0.30:
					all_weapons_ads_valid = false
			&"dmr":
				if ads_t < 0.30 or ads_t > 0.34:
					all_weapons_ads_valid = false
			&"sniper":
				if ads_t < 0.42 or ads_t > 0.48:
					all_weapons_ads_valid = false
	_check(all_weapons_have_speed, "18 把武器都配置了子弹速度")
	_check(all_weapons_ads_valid, "18 把武器均按枪类配置了合理开镜时间 ads_time")
	_check(WeaponDB.weapons_in_category(&"pistol").size() == 5
		and WeaponDB.weapons_in_category(&"smg").size() == 4
		and WeaponDB.weapons_in_category(&"shotgun").size() == 3
		and WeaponDB.weapons_in_category(&"rifle").size() == 3
		and WeaponDB.weapons_in_category(&"dmr").size() == 2
		and WeaponDB.weapons_in_category(&"sniper").size() == 1,
		"18 把武器严格划分为 6 大枪类（5手枪/4冲锋/3霰弹/3步枪/2射手/1狙击）")
	_check(WeaponDB.weapon_category(&"sr25") == &"dmr"
		and WeaponDB.weapon_category(&"vss") == &"dmr"
		and WeaponDB.weapon_category(&"awm") == &"sniper"
		and WeaponDB.weapon_category(&"fal") == &"rifle",
		"SR-25/VSS 为射手步枪、AWM 独立狙击步枪页、FAL 为步枪")
	_check(WeaponDB.get_weapon(&"fal").default_auto_fire,
		"FN FAL 默认支持全自动开火模式")
	var all_mag_styles_valid := true
	for wid in WeaponDB.WEAPON_ORDER:
		if not WeaponDB.MAG_STYLES.has(WeaponDB.get_weapon(wid).mag_style):
			all_mag_styles_valid = false
	_check(all_mag_styles_valid and WeaponDB.MAG_STYLES.has(&"box"),
		"18 把武器均有合法 mag_style 且预留 box 弹箱样式")
	_check(WeaponDB.mag_style(&"akm") == &"curved_mag"
		and WeaponDB.mag_style(&"l85a2") == &"curved_mag"
		and WeaponDB.mag_style(&"vss") == &"curved_mag"
		and WeaponDB.mag_style(&"saiga12k") == &"curved_mag"
		and WeaponDB.mag_style(&"g17") == &"stick_mag"
		and WeaponDB.mag_style(&"awm") == &"stick_mag"
		and WeaponDB.mag_style(&"m870") == &"tube"
		and WeaponDB.mag_style(&"m1014") == &"tube"
		and WeaponDB.mag_style(&"python") == &"cylinder"
		and WeaponDB.mag_style(&"p90") == &"top_mag",
		"18 把武器基础供弹容器样式映射准确（弯匣/直匣/弹管/弹巢/顶置匣）")
	_check(String(ModDB.option("magazine", "mag_drum", false, "akm").get("mag_style", "")) == "drum"
		and String(ModDB.option("magazine", "mag_drum", false, "g17").get("mag_style", "")) == "drum"
		and String(ModDB.option("magazine", "mag_drum", false, "g18").get("mag_style", "")) == "drum"
		and String(ModDB.option("magazine", "mag_drum", false, "saiga12k").get("mag_style", "")) == "drum"
		and float(ModDB.option("magazine", "mag_long", false, "g17").get("mag_scale", 1.0)) > 1.1,
		"弹鼓配件标注 drum 样式，加长弹匣标注 mag_scale 拉长比例")
	var supp := ModDB.option("muzzle", "suppressor", false, "akm")
	var supp_fx: Dictionary = supp.get("effects", {})
	_check(not supp_fx.has("damage_mul")
		and is_equal_approx(float(supp_fx.get("speed_mul", 1.0)), 1.06),
		"消音器不减伤，反而小幅提升子弹速度 (+6%)")
	_check(is_equal_approx(WeaponDB.base_spread_mul(), 1.0)
		and WeaponDB.get_weapon(&"akm").base_spread > WeaponDB.get_weapon(&"g17").base_spread,
		"每把武器使用独立基础散布")
	_check(ammo[&"slug"].color.r > 0.4 and ammo[&"slug"].color.b > 0.9, "弹药颜色解析")

	# ---- 配件 ----
	_check(ModDB.WEAPON_SLOTS.size() == 6 and ModDB.ARMOR_SLOTS.size() == 3,
		"武器 6 槽 / 护甲 3 槽")
	_check(ModDB.options("magazine", false, "saiga12k").size() == 3, "Saiga 弹匣 3 种")
	var drum := ModDB.option("magazine", "mag_drum", false, "saiga12k")
	_check(int(drum.get("effects", {}).get("capacity", 0)) == 20, "Saiga 弹鼓容量 20")
	var auto_kit := ModDB.option("core", "auto", false, "g17")
	_check(bool(auto_kit.get("effects", {}).get("full_auto", false)), "G17 全自动改件")
	_check(is_equal_approx(float(auto_kit.get("effects", {}).get("fire_interval_set", 0.0)), 0.10), "G17 改件 600 RPM")
	_check(is_equal_approx(float(auto_kit.get("effects", {}).get("sound_mul", 0.0)), 1.70), "G17 全自动噪音 +70%")
	_check(int(auto_kit.get("credits", 0)) == 360, "配件价格按经济倍率 +200%")
	var saiga_auto := ModDB.option("core", "auto", false, "saiga12k")
	_check(is_equal_approx(float(saiga_auto.get("effects", {}).get("sound_mul", 0.0)), 1.20), "霰弹枪全自动噪音 +20%")

	# ---- 资源 ----
	_check(ResourceDB.BASIC.size() == 3 and ResourceDB.ADVANCED.size() == 4, "资源 3+4")
	_check(ResourceDB.color_of(&"electronics").b > 0.8, "资源颜色解析")
	_check(int(ResourceDB.ADVANCED_WEIGHTS.get(&"weapon_parts", 0)) == 55, "枪械零件权重 55")

	# ---- 成长 / 天赋 ----
	var progress = root.get_node_or_null("Progress")
	_check(progress != null, "Progress autoload 存在")
	if progress != null:
		_check(int(progress.UPGRADE_MAX.get("hp", 0)) == 5, "强化上限来自表")
		_check(int(progress.TALENT_2D_MAX.get("magnet", 0)) == 5, "磁力天赋上限来自表（默认 5 级）")
		_check(int(progress.TALENT_2D_MAX.get("hearing", 0)) == 5, "声纹感知天赋上限来自表（5 级）")
		_check(String(progress.TALENT_2D_PREREQ.get("hearing", "")) == "hp", "声纹感知挂在生存分支生命强化下")
		_check(String(progress.TALENT_2D_PREREQ.get("loading", "")) == "magazine", "装填天赋前置来自表")
		_check(progress.WEAPON_IDS.size() == 18, "存档武器白名单来自表")
		_check(is_equal_approx(float(progress.CREDIT_COST_MUL), 3.0), "信用点花费倍率 ×3")
		_check(is_equal_approx(float(progress.CREDIT_GAIN_MUL), 0.5), "信用点获取倍率 ×0.5")
		_check(progress.credit_cost(100) == 300, "花费倍率计算")
		_check(progress.credit_gain(100) == 50, "获取倍率计算")

	print("DATA TABLES: %d checks, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
