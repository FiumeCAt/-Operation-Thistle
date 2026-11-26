extends RefCounted
class_name ProgressMetaStore
## 局外元进度存储（纯逻辑，无 I/O 副作用）：
## 管理信用点/经济倍率、基础/进阶物资入库、XP 等级、行动模式、地图与部署点。

const SAVE_STORE := preload("res://scripts/core/progress/SaveStore.gd")
const SPAWN_IDS := SAVE_STORE.SPAWN_IDS
const EXTRACT_IDS := SAVE_STORE.EXTRACT_IDS


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
	data["skill_level"] = 1 + int(data["xp"]) / 20


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
	data["skill_level"] = 1 + clean / 20


static func set_skill_level(data: Dictionary, level: int) -> void:
	var lv := maxi(1, level)
	data["xp"] = (lv - 1) * 20
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
