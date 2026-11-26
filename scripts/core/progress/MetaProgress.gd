extends RefCounted
class_name ProgressMetaStore
## 局外元进度存储（纯逻辑，无 I/O 副作用）：
## 管理信用点/经济倍率、基础/进阶物资入库、非线性 XP 等级曲线（Lv.1~50）、
## 可开关角色被动（机体适应 / 行动津贴）、行动模式、地图与部署点。

const SPAWN_IDS := ["insertion", "abandoned"]
const EXTRACT_IDS := ["east", "south"]
const PASSIVE_IDS := ["body_adapt", "ops_stipend"]
const DEFAULT_MAX_LEVEL := 50
const DEFAULT_XP_BASE := 30
const DEFAULT_XP_LINEAR := 15
const DEFAULT_XP_QUAD := 2
const DEFAULT_PASSIVE_STEP := 0.01


static func max_level() -> int:
	var tbl := GameData.table("progression")
	return maxi(1, int(tbl.get("max_level", DEFAULT_MAX_LEVEL)))


static func _xp_curve_params() -> Dictionary:
	var tbl := GameData.table("progression")
	var raw = tbl.get("xp_curve", {})
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
	return {
		"base": maxi(1, int((raw as Dictionary).get("base", DEFAULT_XP_BASE))),
		"linear": maxi(0, int((raw as Dictionary).get("linear", DEFAULT_XP_LINEAR))),
		"quad": maxi(0, int((raw as Dictionary).get("quad", DEFAULT_XP_QUAD))),
	}


## 从 level 升到 level + 1 所需经验（非线性递增）；已满级返回 0。
static func xp_step_for_level(level: int) -> int:
	var cap := max_level()
	var lv := maxi(1, level)
	if lv >= cap:
		return 0
	var p := _xp_curve_params()
	var idx := lv - 1
	return maxi(1, int(p["base"]) + int(p["linear"]) * idx + int(p["quad"]) * idx * idx)


## 到达指定等级（Lv.1 = 0 XP）所需的累计总经验。
static func xp_for_level(level: int) -> int:
	var lv := clampi(level, 1, max_level())
	var total := 0
	for cur in range(1, lv):
		total += xp_step_for_level(cur)
	return total


## 根据累计 XP 反算当前等级（钳制在 1..max_level）。
static func level_for_xp(xp: int) -> int:
	var clean := maxi(0, xp)
	var cap := max_level()
	var lv := 1
	var acc := 0
	while lv < cap:
		var step := xp_step_for_level(lv)
		if clean < acc + step:
			break
		acc += step
		lv += 1
	return lv


## 返回当前等级进度详情，供主菜单档案/天赋/调试界面统一展示。
static func xp_progress(xp: int) -> Dictionary:
	var clean := maxi(0, xp)
	var cap := max_level()
	var lv := level_for_xp(clean)
	var start_xp := xp_for_level(lv)
	var is_max := lv >= cap
	var needed := 0 if is_max else xp_step_for_level(lv)
	var in_level := 0 if is_max else maxi(0, clean - start_xp)
	return {
		"level": lv,
		"max_level": cap,
		"is_max": is_max,
		"xp": clean,
		"level_start_xp": start_xp,
		"next_level_xp": start_xp + needed,
		"in_level": in_level,
		"needed": needed,
		"ratio": 1.0 if is_max else clampf(float(in_level) / float(maxi(1, needed)), 0.0, 1.0),
	}


static func default_passives_enabled() -> Dictionary:
	return {"body_adapt": true, "ops_stipend": true}


static func passive_enabled(data: Dictionary, id: String) -> bool:
	if not PASSIVE_IDS.has(id):
		return false
	var map = data.get("passives_enabled", null)
	if typeof(map) != TYPE_DICTIONARY:
		return true
	return bool((map as Dictionary).get(id, true))


static func set_passive_enabled(data: Dictionary, id: String, enabled: bool) -> bool:
	if not PASSIVE_IDS.has(id):
		return false
	var map = data.get("passives_enabled", null)
	var clean := default_passives_enabled()
	if typeof(map) == TYPE_DICTIONARY:
		for k in PASSIVE_IDS:
			clean[k] = bool((map as Dictionary).get(k, true))
	clean[id] = enabled
	data["passives_enabled"] = clean
	return true


static func passive_step(id: String) -> float:
	var tbl := GameData.table("progression")
	var raw = tbl.get("passives", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return DEFAULT_PASSIVE_STEP
	var key := "body_adapt_per_level" if id == "body_adapt" else "ops_stipend_per_level"
	return clampf(float((raw as Dictionary).get(key, DEFAULT_PASSIVE_STEP)), 0.0, 0.25)


## 机体适应：Lv.2 起每级 +(level - 1) * 1% 基础生命上限（与血量天赋加算，可关闭）。
static func body_adapt_hp_bonus(data: Dictionary) -> float:
	if not passive_enabled(data, "body_adapt"):
		return 0.0
	var lv := level_for_xp(int(data.get("xp", 0)))
	return float(maxi(0, lv - 1)) * passive_step("body_adapt")


## 行动津贴：Lv.2 起每级 +(level - 1) * 1% 局内撤离/浪潮信用点与基础物资收益（不作用于 XP，可关闭）。
static func ops_stipend_bonus(data: Dictionary) -> float:
	if not passive_enabled(data, "ops_stipend"):
		return 0.0
	var lv := level_for_xp(int(data.get("xp", 0)))
	return float(maxi(0, lv - 1)) * passive_step("ops_stipend")


static func credit_cost(base: int, cost_mul: float) -> int:
	return int(round(float(base) * cost_mul))


static func credit_gain(base: int, gain_mul: float) -> int:
	return int(round(float(base) * gain_mul))


static func credits(data: Dictionary) -> int:
	return int(data.get("resources", 0))


static func add_resources(data: Dictionary, amount: int, gain_mul: float) -> bool:
	if amount <= 0:
		return false
	data["resources"] = maxi(0, int(data.get("resources", 0)) + credit_gain(amount, gain_mul))
	return true


static func material_count(data: Dictionary, id: StringName) -> int:
	return int(data.get("materials_2d", {}).get(String(id), 0))


static func advanced_count(data: Dictionary, id: StringName) -> int:
	return int(data.get("advanced_2d", {}).get(String(id), 0))


static func add_materials(data: Dictionary, counts: Dictionary) -> void:
	var materials: Dictionary = data.get("materials_2d", {})
	var advanced: Dictionary = data.get("advanced_2d", {})
	for key in counts:
		var id := String(key)
		var amount := int(counts[key])
		if amount <= 0:
			continue
		if ResourceDB.BASIC.has(StringName(id)):
			materials[id] = maxi(0, int(materials.get(id, 0)) + amount)
		elif ResourceDB.ADVANCED.has(StringName(id)):
			advanced[id] = maxi(0, int(advanced.get(id, 0)) + amount)
	data["materials_2d"] = materials
	data["advanced_2d"] = advanced


static func add_xp(data: Dictionary, amount: int) -> void:
	data["xp"] = maxi(0, int(data.get("xp", 0)) + amount)
	data["skill_level"] = level_for_xp(int(data["xp"]))


## ---- 调试快捷设值 / 原始增减（Phase 5B，直接写入存档字典，不乘经济倍率）----

static func set_credits(data: Dictionary, value: int) -> void:
	data["resources"] = maxi(0, value)


static func adjust_credits_raw(data: Dictionary, delta: int) -> void:
	data["resources"] = maxi(0, int(data.get("resources", 0)) + delta)


static func set_material_count(data: Dictionary, id: StringName, value: int) -> bool:
	var clean := maxi(0, value)
	if ResourceDB.BASIC.has(id):
		var materials: Dictionary = data.get("materials_2d", {})
		materials[String(id)] = clean
		data["materials_2d"] = materials
		return true
	if ResourceDB.ADVANCED.has(id):
		var advanced: Dictionary = data.get("advanced_2d", {})
		advanced[String(id)] = clean
		data["advanced_2d"] = advanced
		return true
	return false


static func adjust_material_count(data: Dictionary, id: StringName, delta: int) -> bool:
	if ResourceDB.BASIC.has(id):
		return set_material_count(data, id, material_count(data, id) + delta)
	if ResourceDB.ADVANCED.has(id):
		return set_material_count(data, id, advanced_count(data, id) + delta)
	return false


static func set_xp(data: Dictionary, value: int) -> void:
	var clean := maxi(0, value)
	data["xp"] = clean
	data["skill_level"] = level_for_xp(clean)


static func set_skill_level(data: Dictionary, level: int) -> void:
	var lv := clampi(level, 1, max_level())
	data["xp"] = xp_for_level(lv)
	data["skill_level"] = lv


static func set_deployment(data: Dictionary, spawn_id: StringName,
		extract_id: StringName) -> bool:
	var spawn_key := String(spawn_id)
	var extract_key := String(extract_id)
	if not SPAWN_IDS.has(spawn_key) or not EXTRACT_IDS.has(extract_key):
		return false
	data["deployment"] = {"spawn": spawn_key, "extract": extract_key}
	return true


static func deployment(data: Dictionary) -> Dictionary:
	return (data.get("deployment", {"spawn": "insertion", "extract": "east"}) as Dictionary).duplicate()


static func set_run_mode(data: Dictionary, mode: String) -> void:
	data["run_mode"] = mode if ["raid", "waves"].has(mode) else "raid"


static func run_mode(data: Dictionary) -> String:
	return String(data.get("run_mode", "raid"))


static func set_map_id(data: Dictionary, map_id: String) -> void:
	data["map_id"] = map_id if ["facility", "goliath_arena"].has(map_id) else "facility"


static func map_id(data: Dictionary) -> String:
	return String(data.get("map_id", "facility"))
