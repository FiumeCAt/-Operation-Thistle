extends RefCounted
class_name ResourceDB
## 资源表。数据来自 data/resources.json；颜色同时用于地面掉落物、容器指示灯和 UI 文案。

static var BASIC: Array[StringName] = _load_list("basic")
static var ADVANCED: Array[StringName] = _load_list("advanced")
static var ADVANCED_WEIGHTS: Dictionary = _load_weights()
static var DATA: Dictionary = _load_data()


static func _load_list(key: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameData.table("resources").get(key, []):
		out.append(StringName(id))
	return out


static func _load_weights() -> Dictionary:
	var raw: Dictionary = GameData.table("resources").get("advanced_weights", {})
	return GameData.string_name_keys(raw)


static func _load_data() -> Dictionary:
	var raw: Dictionary = GameData.table("resources").get("data", {})
	var out := {}
	for key in raw:
		var rec: Dictionary = raw[key].duplicate()
		rec["color"] = Color.html(String(rec.get("color", "#ffffff")))
		out[StringName(key)] = rec
	return out


static func has(id: StringName) -> bool:
	return DATA.has(id)


static func is_basic(id: StringName) -> bool:
	return BASIC.has(id)


static func display_name(id: StringName) -> String:
	return String(DATA.get(id, {}).get("name", String(id)))


static func short_name(id: StringName) -> String:
	return String(DATA.get(id, {}).get("short", String(id)))


static func color_of(id: StringName) -> Color:
	return DATA.get(id, {}).get("color", Color.WHITE)
