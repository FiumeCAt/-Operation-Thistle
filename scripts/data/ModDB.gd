extends RefCounted
class_name ModDB
## 配件 / 组件表：武器三个槽位、护甲三个槽位。数据来自 data/mods.json。
## 安装消耗信用点 + 进阶资源；效果在开局装配或武器 setup 时汇总应用。

static var WEAPON_SLOTS: Array[Dictionary] = _load_slots("weapon_slots")
static var ARMOR_SLOTS: Array[Dictionary] = _load_slots("armor_slots")
## 武器配件：所有枪械通用，效果按倍率叠乘。
static var WEAPON_OPTIONS: Dictionary = _scaled_section("weapon_options")
## 弹匣独立成基础配件：容量是绝对值，替换后直接改写武器弹容。
static var WEAPON_MAGAZINES: Dictionary = GameData.string_name_keys(_scaled_section("weapon_magazines"))
## 武器专属改件：目前是两把枪的全自动枪机。
static var WEAPON_EXTRA: Dictionary = GameData.string_name_keys(_scaled_section("weapon_extra"))
## 护甲组件：改变耐久上限、防御等级、吸收比例与移速。
static var ARMOR_OPTIONS: Dictionary = _scaled_section("armor_options")


static func _mods_table() -> Dictionary:
	return GameData.table("mods")


static func _section(key: String) -> Dictionary:
	return _mods_table().get(key, {})


static func _credit_mul() -> float:
	return float(GameData.table("progression").get("credit_cost_mul", 1.0))


## 配件价格统一走经济倍率，UI 与扣费读同一份数据。
static func _scaled_section(key: String) -> Dictionary:
	return _scale_costs_dict(_section(key))


static func _scale_costs_dict(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source:
		var value = source[key]
		if String(key) == "credits":
			out[key] = int(round(float(value) * _credit_mul()))
		elif value is Dictionary:
			out[key] = _scale_costs_dict(value)
		elif value is Array:
			out[key] = _scale_costs_array(value)
		else:
			out[key] = value
	return out


static func _scale_costs_array(source: Array) -> Array:
	var out := []
	for item in source:
		if item is Dictionary:
			out.append(_scale_costs_dict(item))
		elif item is Array:
			out.append(_scale_costs_array(item))
		else:
			out.append(item)
	return out


static func _load_slots(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _mods_table().get(key, []):
		out.append(entry)
	return out


static func slots(is_armor: bool) -> Array[Dictionary]:
	return ARMOR_SLOTS if is_armor else WEAPON_SLOTS


## weapon_id 为空时返回通用配件；弹匣与专属改件需要武器 id 才能取到。
static func options(slot: String, is_armor: bool, weapon_id := "") -> Array:
	if is_armor:
		return ARMOR_OPTIONS.get(slot, [])
	if slot == "magazine":
		return WEAPON_MAGAZINES.get(StringName(weapon_id), [])
	var table: Array = WEAPON_OPTIONS.get(slot, [])
	var merged: Array = table.duplicate()
	if weapon_id != "":
		var extra: Dictionary = WEAPON_EXTRA.get(StringName(weapon_id), {})
		if extra.has(slot):
			merged.append_array(extra[slot])
	return merged


static func option(slot: String, option_id: String, is_armor: bool, weapon_id := "") -> Dictionary:
	for entry in options(slot, is_armor, weapon_id):
		if String(entry["id"]) == option_id:
			return entry
	return {}


static func default_modifiers() -> Dictionary:
	return {
		"damage_mul": 1.0, "spread_mul": 1.0, "range_mul": 1.0,
		"speed_mul": 1.0,
		"mag_mul": 1.0, "reload_mul": 1.0, "fire_mul": 1.0,
		"sound_mul": 1.0,
		## 后坐力（连发散布增长/上限/开火震动）、瞄具视野、瞄准过渡速度。
		"recoil_mul": 1.0, "vision_mul": 1.0, "ads_speed_mul": 1.0,
		## 瞄具的“瞄准时间加成”：大于 1 表示开镜更慢。
		"ads_time_mul": 1.0,
		## 下挂激光开关：有任意配件点亮即为 true。
		"laser": false,
		"armor_max_add": 0, "armor_level_add": 0,
		"absorb_add": 0.0, "move_mul": 1.0,
	}


## installed: {slot_id: option_id}；返回汇总后的倍率/加值。
## capacity / full_auto / fire_interval_set 是绝对值或开关，由武器单独读取，不参与叠乘。
static func modifiers(installed: Dictionary, is_armor: bool, weapon_id := "") -> Dictionary:
	var total := default_modifiers()
	for slot_def in slots(is_armor):
		var slot := String(slot_def["id"])
		var chosen := String(installed.get(slot, ""))
		if chosen == "":
			continue
		var entry := option(slot, chosen, is_armor, weapon_id)
		if entry.is_empty():
			continue
		var effects: Dictionary = entry.get("effects", {})
		for key in effects:
			if key in ["capacity", "full_auto", "fire_interval_set"]:
				continue
			if key == "laser":
				total["laser"] = bool(total.get("laser", false)) or bool(effects[key])
				continue
			if key.ends_with("_add"):
				total[key] = total.get(key, 0.0) + float(effects[key])
			else:
				total[key] = float(total.get(key, 1.0)) * float(effects[key])
	return total
