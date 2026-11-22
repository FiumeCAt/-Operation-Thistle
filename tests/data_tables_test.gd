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
	_check(ammo.size() == 12, "弹药 12 种")
	var categories := WeaponDB.category_table()
	_check(categories.size() == 5, "通用弹药 5 类")
	_check(WeaponDB.get_weapon(&"g17").ammo_category == &"light"
		and WeaponDB.get_weapon(&"akm").ammo_category == &"medium"
		and WeaponDB.get_weapon(&"awm").ammo_category == &"heavy"
		and WeaponDB.get_weapon(&"m870").ammo_category == &"shotgun",
		"武器映射到通用弹药种类")
	_check(int(categories["medium"]["reserve_max"]) == 120, "中型弹通用备弹 120")
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
		and is_equal_approx(ammo[&"556nato"].bullet_time_scale, 0.25)
		and is_equal_approx(ammo[&"556nato"].drag_per_m, 0.0035),
		"5.56 初速 940 m/s / 时间压缩 0.25 / 衰减 0.0035")
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
	for wid in WeaponDB.WEAPON_ORDER:
		if float(WeaponDB.get_weapon(wid).bullet_speed_mps) <= 0.0:
			all_weapons_have_speed = false
	_check(all_weapons_have_speed, "18 把武器都配置了子弹速度")
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
		_check(int(progress.TALENT_2D_MAX.get("magnet", 0)) == 3, "磁力天赋上限来自表")
		_check(String(progress.TALENT_2D_PREREQ.get("loading", "")) == "magazine", "装填天赋前置来自表")
		_check(progress.WEAPON_IDS.size() == 18, "存档武器白名单来自表")
		_check(is_equal_approx(float(progress.CREDIT_COST_MUL), 3.0), "信用点花费倍率 ×3")
		_check(is_equal_approx(float(progress.CREDIT_GAIN_MUL), 0.5), "信用点获取倍率 ×0.5")
		_check(progress.credit_cost(100) == 300, "花费倍率计算")
		_check(progress.credit_gain(100) == 50, "获取倍率计算")

	print("DATA TABLES: %d checks, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
