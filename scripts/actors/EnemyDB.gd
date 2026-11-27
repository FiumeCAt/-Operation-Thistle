extends RefCounted
class_name EnemyDB
## 敌人类型表。数值来自 data/enemies.json，贴图在 assets/art/enemies/<id>.png。
## 新单位（mobile_turret / sentry_type1 / hunter_type1 / goliath）已在表内，
## 但还未加入 order，避免旧的生成流程直接刷出来。

static var ORDER: Array[StringName] = _load_order()
static var DATA: Dictionary = _load_data()


static func _load_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameData.table("enemies").get("order", []):
		out.append(StringName(id))
	if out.is_empty():
		out = [&"rifleman", &"rusher", &"heavy", &"hunter"]
	return out


static func _load_data() -> Dictionary:
	var raw: Dictionary = GameData.table("enemies").get("data", {})
	var out := GameData.string_name_keys(raw)
	if not out.has(&"rifleman"):
		out[&"rifleman"] = {
			"name": "哨兵",
			"texture": "res://assets/art/enemies/rifleman.png",
			"hp": 70.0, "armor": 1.0, "speed": 2.6, "damage": 7.0,
			"range": 13.0, "view_range": 15.0, "hearing": 16.0,
			"cooldown": 1.55, "melee": false, "radius": 0.36,
			"patrol_radius": 6.0, "flees": true, "strafe": true,
		}
	return out


## 已就绪但尚未接入生成流程的新单位。
static func new_units() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameData.table("enemies").get("new_units", []):
		out.append(StringName(id))
	return out


static func has(id: StringName) -> bool:
	return DATA.has(id)


static func stats(id: StringName) -> Dictionary:
	return DATA.get(id, DATA[&"rifleman"])


## 敌人三系生态默认参数（mech / human / mutant，含 Phase 4 默认弱点部位配置）；缺省回退内置表。
static func archetype_profile(archetype: StringName) -> Dictionary:
	var table: Dictionary = GameData.table("enemies").get("archetypes", {})
	var key := String(archetype)
	if table.has(key) and table[key] is Dictionary:
		return table[key]
	match archetype:
		&"mech":
			return {
				"name": "机械", "blunt_floor": 0.08, "flesh_mul": 1.00,
				"weakspot": {
					"part": "optical_core", "label": "光学核心",
					"offset_x": 0.0, "offset_y_ratio": 0.62, "flip_x": false,
					"radius": 12.0, "tolerance": 1.18,
					"armor_mul": 0.50, "damage_mul": 1.50,
				},
			}
		&"mutant":
			return {
				"name": "变异", "blunt_floor": 0.22, "flesh_mul": 1.20,
				"weakspot": {
					"part": "exposed_core", "label": "暴露瘤核",
					"offset_x": 0.0, "offset_y_ratio": 0.56, "flip_x": false,
					"radius": 13.0, "tolerance": 1.18,
					"armor_mul": 0.50, "damage_mul": 2.00,
				},
			}
		_:
			return {
				"name": "人类", "blunt_floor": 0.14, "flesh_mul": 1.05,
				"weakspot": {
					"part": "head", "label": "头部",
					"offset_x": 0.0, "offset_y_ratio": 0.80, "flip_x": false,
					"radius": 11.0, "tolerance": 1.18,
					"armor_mul": 0.50, "damage_mul": 2.00,
				},
			}
