extends RefCounted
class_name ProgressTalentStore
## 强化与 2D 战术天赋树存储（纯逻辑，无 I/O 副作用）：
## 管理 3D 升级线与 2D 天赋树的等级查询、价格/材料计算、前置校验、购买及级联重置返还。

const META := preload("res://scripts/core/progress/MetaProgress.gd")


static func upgrade_level(data: Dictionary, id: StringName) -> int:
	return int(data.get("upgrades", {}).get(String(id), 0))


static func upgrade_max(upgrade_max_table: Dictionary, id: StringName) -> int:
	return int(upgrade_max_table.get(String(id), 0))


static func upgrade_cost(data: Dictionary, upgrade_max_table: Dictionary,
		cost_mul: float, id: StringName) -> int:
	var key := String(id)
	if not upgrade_max_table.has(key):
		return -1
	var level := upgrade_level(data, id)
	if level >= int(upgrade_max_table[key]):
		return -1
	return META.credit_cost(15 + level * 15, cost_mul)


static func buy_upgrade(data: Dictionary, upgrade_max_table: Dictionary,
		cost_mul: float, id: StringName) -> bool:
	var cost := upgrade_cost(data, upgrade_max_table, cost_mul, id)
	if cost < 0 or int(data["resources"]) < cost:
		return false
	data["resources"] = int(data["resources"]) - cost
	data["upgrades"][String(id)] = upgrade_level(data, id) + 1
	data["xp"] = int(data["xp"]) + 5
	data["skill_level"] = META.level_for_xp(int(data["xp"]))
	return true


## ---- 2D 天赋树 ----

static func talent_2d_level(data: Dictionary, id: StringName) -> int:
	return int(data.get("talents_2d", {}).get(String(id), 0))


static func talent_2d_max(talent_max_table: Dictionary, id: StringName) -> int:
	return int(talent_max_table.get(String(id), 0))


static func talent_2d_cost(data: Dictionary, talent_max_table: Dictionary,
		cost_mul: float, id: StringName) -> int:
	var key := String(id)
	if not talent_max_table.has(key):
		return -1
	var level := talent_2d_level(data, id)
	if level >= int(talent_max_table[key]):
		return -1
	return META.credit_cost(15 + level * 15, cost_mul)


static func talent_2d_material(talent_material_table: Dictionary,
		id: StringName) -> StringName:
	return StringName(talent_material_table.get(String(id), ""))


static func talent_2d_material_cost(data: Dictionary, talent_max_table: Dictionary,
		talent_material_table: Dictionary, id: StringName) -> int:
	var level := talent_2d_level(data, id)
	if talent_2d_material(talent_material_table, id) == &"" or level >= talent_2d_max(talent_max_table, id):
		return -1
	return 3 + level * 3


static func buy_talent_2d(data: Dictionary, talent_max_table: Dictionary,
		talent_prereq_table: Dictionary, talent_material_table: Dictionary,
		cost_mul: float, id: StringName) -> bool:
	var cost := talent_2d_cost(data, talent_max_table, cost_mul, id)
	var material := talent_2d_material(talent_material_table, id)
	var material_cost := talent_2d_material_cost(
		data, talent_max_table, talent_material_table, id)
	if cost < 0 or material_cost < 0:
		return false
	if int(data["resources"]) < cost or META.material_count(data, material) < material_cost:
		return false
	var prereq := String(talent_prereq_table.get(String(id), ""))
	if prereq != "" and talent_2d_level(data, StringName(prereq)) < 1:
		return false
	data["resources"] = int(data["resources"]) - cost
	var materials: Dictionary = data["materials_2d"]
	materials[String(material)] = maxi(0, int(materials.get(String(material), 0)) - material_cost)
	data["talents_2d"][String(id)] = talent_2d_level(data, id) + 1
	data["xp"] = int(data["xp"]) + 5
	data["skill_level"] = META.level_for_xp(int(data["xp"]))
	return true


## 返回节点及其所有（传递）依赖节点。重置前置节点时依赖节点必须一起清空。
static func talent_2d_dependents(talent_prereq_table: Dictionary,
		id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = [id]
	var changed := true
	while changed:
		changed = false
		for key in talent_prereq_table:
			var prereq := StringName(talent_prereq_table[key])
			if ids.has(prereq) and not ids.has(StringName(key)):
				ids.append(StringName(key))
				changed = true
	return ids


static func reset_talent_2d(data: Dictionary, talent_prereq_table: Dictionary,
		talent_material_table: Dictionary, cost_mul: float, id: StringName) -> Dictionary:
	var result := {"nodes": [], "credits": 0, "materials": {}}
	if talent_2d_level(data, id) <= 0:
		return result
	for node_id in talent_2d_dependents(talent_prereq_table, id):
		_refund_talent(data, talent_material_table, cost_mul, node_id, result)
	return result


static func reset_all_talents_2d(data: Dictionary, talent_max_table: Dictionary,
		talent_material_table: Dictionary, cost_mul: float) -> Dictionary:
	var result := {"nodes": [], "credits": 0, "materials": {}}
	for key in talent_max_table:
		_refund_talent(data, talent_material_table, cost_mul, StringName(key), result)
	return result


static func _refund_talent(data: Dictionary, talent_material_table: Dictionary,
		cost_mul: float, id: StringName, result: Dictionary) -> void:
	var level := talent_2d_level(data, id)
	if level <= 0:
		return
	var credits_back := META.credit_cost(15 * level * (level + 1) / 2, cost_mul)
	var material := talent_2d_material(talent_material_table, id)
	var materials_back := 3 * level * (level + 1) / 2
	data["resources"] = int(data["resources"]) + credits_back
	if material != &"":
		var materials: Dictionary = data["materials_2d"]
		materials[String(material)] = int(materials.get(String(material), 0)) + materials_back
		var refunded: Dictionary = result["materials"]
		refunded[String(material)] = int(refunded.get(String(material), 0)) + materials_back
	data["talents_2d"][String(id)] = 0
	result["credits"] = int(result["credits"]) + credits_back
	(result["nodes"] as Array).append(id)
