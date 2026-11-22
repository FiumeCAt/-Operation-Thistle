extends RefCounted
class_name WeaponStatsModel

## 武器属性单一计算模型（纯计算，无全局状态）：
## 统一 WeaponDB + ModDB + 2D 天赋的属性计算，供 WeaponRig2D、ArmoryMenu2D 与测试共用。
## 每次计算都读取全新的 WeaponData 实例，绝不修改或污染共享缓存。

const MAG_TALENT_PER_LEVEL := 0.08
const RELOAD_TALENT_BASE := 0.94
const GUN_ACCURACY_BASE := 0.94


static func mag_talent_mul(level: int) -> float:
	return 1.0 + float(maxi(level, 0)) * MAG_TALENT_PER_LEVEL


static func reload_talent_mul(level: int) -> float:
	return pow(RELOAD_TALENT_BASE, float(maxi(level, 0)))


static func gun_accuracy_mul(level: int) -> float:
	return pow(GUN_ACCURACY_BASE, float(maxi(level, 0)))


## 从 Progress Autoload 提取与武器属性相关的 2D 天赋等级；缺失时全回退 0。
static func talents_from_progress(progress: Node) -> Dictionary:
	if progress == null or not progress.has_method("talent_2d_level"):
		return {"magazine": 0, "reload": 0, "gun": 0}
	return {
		"magazine": int(progress.talent_2d_level(&"magazine")),
		"reload": int(progress.talent_2d_level(&"reload")),
		"gun": int(progress.talent_2d_level(&"gun")),
	}


## 按给定武器 ID、配件字典与天赋等级，计算完整的武器最终属性快照。
## reticle_resolver 可选：Callable(sight_id: String, default_reticle: String) -> String。
static func compute(weapon_id: StringName, installed: Dictionary,
		talents: Dictionary = {}, reticle_resolver: Callable = Callable()) -> Dictionary:
	var base := WeaponDB.get_weapon(weapon_id)
	var wid := String(weapon_id)
	var mods := ModDB.modifiers(installed, false, wid)

	var mag_level := int(talents.get("magazine", 0))
	var reload_level := int(talents.get("reload", 0))
	var gun_level := int(talents.get("gun", 0))
	var talent_mag := mag_talent_mul(mag_level)
	var reload_talent := reload_talent_mul(reload_level)
	var accuracy := gun_accuracy_mul(gun_level)

	var damage_mul := float(mods["damage_mul"])
	var spread_mul := float(mods["spread_mul"])
	var recoil_mul := clampf(float(mods["recoil_mul"]), 0.2, 1.5)
	var vision_mul := clampf(float(mods["vision_mul"]), 1.0, 2.2)
	var ads_speed_mul := clampf(float(mods["ads_speed_mul"]), 1.0, 2.0)
	var sight_ads_time_mul := clampf(float(mods.get("ads_time_mul", 1.0)), 1.0, 2.0)
	var has_laser := bool(mods.get("laser", false))

	# 瞄具元数据（标定倍率/准星样式/是否高倍镜窗）不参与 ModDB 倍率叠乘。
	var sight_id := String(installed.get("sight", ""))
	var sight := ModDB.option("sight", sight_id, false, wid)
	var sight_magnification := 1.0
	var sight_reticle := "iron"
	var has_scope_sight := false
	if not sight.is_empty():
		sight_magnification = clampf(float(sight.get("magnification", 1.0)), 1.0, 8.0)
		sight_reticle = String(sight.get("reticle", "iron"))
		has_scope_sight = bool(sight.get("scope", false))
		if reticle_resolver.is_valid():
			sight_reticle = String(reticle_resolver.call(sight_id, sight_reticle))

	# 弹匣配件提供绝对容量，最后再叠「弹匣扩容」天赋。
	var raw_capacity: int = base.mag_capacity
	var magazine := ModDB.option("magazine", String(installed.get("magazine", "")), false, wid)
	if not magazine.is_empty():
		var mag_fx: Dictionary = magazine.get("effects", {})
		if mag_fx.has("capacity"):
			raw_capacity = int(mag_fx["capacity"])
	var mag := maxi(1, int(round(float(raw_capacity) * talent_mag)))

	# 射速与全自动：先乘 fire_mul，再应用枪机专属改件；武器自带全自动（AKM/G18 等）不被非全自动枪机清掉。
	var interval := maxf(0.03, base.fire_interval * float(mods["fire_mul"]))
	var auto_fire := base.default_auto_fire
	var core := ModDB.option("core", String(installed.get("core", "")), false, wid)
	if not core.is_empty():
		var core_fx: Dictionary = core.get("effects", {})
		if core_fx.has("fire_interval_set"):
			interval = maxf(0.03, float(core_fx["fire_interval_set"]))
		if bool(core_fx.get("full_auto", false)):
			auto_fire = true

	# 换弹时间：load_modded 不含换弹天赋（供 WeaponRig2D.data.load_time，在 reload() 中另乘 reload_time_mul）；
	# load 包含换弹天赋（供武备库详情/改枪面板直接展示最终换弹时长）。
	var load_modded := maxf(0.05, base.load_time * float(mods["reload_mul"]))
	var load_effective := maxf(0.05, base.load_time * float(mods["reload_mul"]) * reload_talent)

	var range_m := base.range_m * float(mods["range_mul"])
	var sound := base.sound_radius * float(mods["sound_mul"])
	var speed := float(base.bullet_speed_mps)

	# 弹药派生：单丸伤害、总伤害、穿甲与腰射基础/最终散布。
	var ammo = WeaponDB.ammo_table().get(base.ammo_id)
	var pellets := 0
	var ap := 0.0
	var base_pellet_damage := 0.0
	var pellet_damage := 0.0
	var total_damage := 0.0
	var base_spread := 0.0
	var spread := 0.0
	if ammo != null:
		pellets = int(ammo.pellets)
		ap = float(ammo.ap)
		base_pellet_damage = float(ammo.damage)
		pellet_damage = base_pellet_damage * damage_mul
		total_damage = pellet_damage * float(pellets)
		base_spread = float(ammo.spread) + float(base.base_spread)
		var attach_scale := clampf(float(ammo.attachment_spread_scale), 0.0, 1.0)
		spread = base_spread * lerpf(1.0, spread_mul, attach_scale) * accuracy

	return {
		"base": base,
		"mods": mods,
		"ammo": ammo,
		"mag": mag,
		"interval": interval,
		"load_modded": load_modded,
		"load": load_effective,
		"range": range_m,
		"speed": speed,
		"sound": sound,
		"auto": auto_fire,
		"damage_mul": damage_mul,
		"spread_mul": spread_mul,
		"recoil_mul": recoil_mul,
		"vision_mul": vision_mul,
		"ads_speed_mul": ads_speed_mul,
		"sight_ads_time_mul": sight_ads_time_mul,
		"has_laser": has_laser,
		"sight_magnification": sight_magnification,
		"sight_reticle": sight_reticle,
		"has_scope_sight": has_scope_sight,
		"aim_zoom_mul": sight_magnification,
		"spread_growth": base.spread_growth * recoil_mul,
		"spread_max": base.spread_max * recoil_mul,
		"shake_amount": base.shake_amount * recoil_mul,
		"base_pellet_damage": base_pellet_damage,
		"pellet_damage": pellet_damage,
		"damage": total_damage,
		"pellets": pellets,
		"ap": ap,
		"base_spread": base_spread,
		"spread": spread,
		"recoil": 1.0 - recoil_mul,
		"vision": vision_mul - 1.0,
		"ads": ads_speed_mul - 1.0,
	}


## 便捷入口：从 Progress 读取指定武器的已装配件、天赋与准星样式；
## 传入 installed_override（如改枪预览表）时覆盖已装配件字典。
static func compute_for_progress(weapon_id: StringName, progress: Node,
		installed_override = null) -> Dictionary:
	var installed: Dictionary = {}
	if installed_override is Dictionary:
		installed = installed_override
	elif progress != null and progress.has_method("weapon_mods_2d"):
		installed = progress.weapon_mods_2d(weapon_id)
	var talents := talents_from_progress(progress)
	var resolver := Callable()
	if progress != null and progress.has_method("reticle_style"):
		resolver = func(sight_id: String, default_reticle: String) -> String:
			return String(progress.reticle_style(sight_id, default_reticle))
	return compute(weapon_id, installed, talents, resolver)


## 将 compute() 产出的改装字段写入运行期 WeaponData 实例（供 WeaponRig2D._apply_mods 使用）。
static func apply_to_weapon_data(data: WeaponData, stats: Dictionary) -> void:
	if data == null:
		return
	data.load_time = float(stats["load_modded"])
	data.fire_interval = float(stats["interval"])
	data.range_m = float(stats["range"])
	data.sound_radius = float(stats["sound"])
	data.spread_growth = float(stats["spread_growth"])
	data.spread_max = float(stats["spread_max"])
	data.shake_amount = float(stats["shake_amount"])
	data.mag_capacity = int(stats["mag"])
	data.auto_fire = bool(stats["auto"])
