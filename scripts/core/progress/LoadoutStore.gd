extends RefCounted
class_name ProgressLoadoutStore
## 携行配装与配件/护甲组件安装存储（纯逻辑，无 I/O 副作用）。

const SAVE_STORE := preload("res://scripts/core/progress/SaveStore.gd")
const WEAPON_IDS := SAVE_STORE.WEAPON_IDS


static func set_loadout(data: Dictionary, weapon: StringName, ammo: StringName) -> void:
	data["loadout"] = {"weapon": String(weapon), "ammo": String(ammo)}


static func set_loadout_2d(data: Dictionary, primary: StringName,
		secondary: StringName) -> bool:
	var first := String(primary)
	var second := String(secondary)
	if not WEAPON_IDS.has(first):
		return false
	if not WEAPON_IDS.has(second):
		second = "g17" if first != "g17" else "m870"
	if first == second:
		return false
	data["loadout_2d"] = [first, second]
	return true


static func loadout_2d(data: Dictionary) -> Array:
	return (data.get("loadout_2d", ["g17", "m870"]) as Array).duplicate()


static func weapon_mods_2d(data: Dictionary, weapon_id: StringName) -> Dictionary:
	var all_mods: Dictionary = data.get("weapon_mods_2d", {})
	return (all_mods.get(String(weapon_id), {}) as Dictionary).duplicate()


static func weapon_ammo_2d(data: Dictionary, weapon_id: StringName) -> StringName:
	var all_ammo: Dictionary = data.get("weapon_ammo_2d", {})
	var raw := String(all_ammo.get(String(weapon_id), ""))
	if raw != "":
		var aid := StringName(raw)
		var tbl := WeaponDB.ammo_table()
		if tbl.has(aid) and tbl[aid].caliber == WeaponDB.get_weapon(weapon_id).caliber:
			return aid
	return WeaponDB.get_weapon(weapon_id).ammo_id


static func set_weapon_ammo_2d(data: Dictionary, weapon_id: StringName, ammo_id: StringName) -> bool:
	var wid := String(weapon_id)
	if not WEAPON_IDS.has(wid):
		return false
	var tbl := WeaponDB.ammo_table()
	if not tbl.has(ammo_id):
		return false
	if tbl[ammo_id].caliber != WeaponDB.get_weapon(weapon_id).caliber:
		return false
	var all_ammo: Dictionary = data.get("weapon_ammo_2d", {})
	all_ammo[wid] = String(ammo_id)
	data["weapon_ammo_2d"] = all_ammo
	return true


static func armor_mods_2d(data: Dictionary) -> Dictionary:
	return (data.get("armor_mods_2d", {}) as Dictionary).duplicate()


static func can_pay_mod(data: Dictionary, entry: Dictionary) -> bool:
	var credits := int(entry.get("credits", 0))
	if credits < 0 or int(data.get("resources", 0)) < credits:
		return false
	var cost: Dictionary = entry.get("cost", {})
	var advanced: Dictionary = data.get("advanced_2d", {})
	for id in cost:
		if int(advanced.get(String(id), 0)) < int(cost[id]):
			return false
	return true


static func pay_mod(data: Dictionary, entry: Dictionary) -> void:
	data["resources"] = maxi(0, int(data.get("resources", 0)) - int(entry.get("credits", 0)))
	var advanced: Dictionary = data.get("advanced_2d", {})
	var cost: Dictionary = entry.get("cost", {})
	for id in cost:
		var key := String(id)
		advanced[key] = maxi(0, int(advanced.get(key, 0)) - int(cost[id]))
	data["advanced_2d"] = advanced


## 安装武器配件：返回 {"ok": bool, "changed": bool}；重复安装当前选项不扣费且 changed=false。
static func install_weapon_mod(data: Dictionary, weapon_id: StringName,
		slot: StringName, option_id: StringName) -> Dictionary:
	var weapon := String(weapon_id)
	if not WEAPON_IDS.has(weapon):
		return {"ok": false, "changed": false}
	var entry := ModDB.option(String(slot), String(option_id), false, weapon)
	if entry.is_empty():
		return {"ok": false, "changed": false}
	var all_mods: Dictionary = data.get("weapon_mods_2d", {})
	var installed: Dictionary = all_mods.get(weapon, {})
	if String(installed.get(String(slot), "")) == String(option_id):
		return {"ok": true, "changed": false}
	if not can_pay_mod(data, entry):
		return {"ok": false, "changed": false}
	pay_mod(data, entry)
	installed[String(slot)] = String(option_id)
	all_mods[weapon] = installed
	data["weapon_mods_2d"] = all_mods
	return {"ok": true, "changed": true}


## 安装护甲组件：返回 {"ok": bool, "changed": bool}。
static func install_armor_mod(data: Dictionary, slot: StringName,
		option_id: StringName) -> Dictionary:
	var entry := ModDB.option(String(slot), String(option_id), true)
	if entry.is_empty():
		return {"ok": false, "changed": false}
	var installed: Dictionary = data.get("armor_mods_2d", {})
	if String(installed.get(String(slot), "")) == String(option_id):
		return {"ok": true, "changed": false}
	if not can_pay_mod(data, entry):
		return {"ok": false, "changed": false}
	pay_mod(data, entry)
	installed[String(slot)] = String(option_id)
	data["armor_mods_2d"] = installed
	return {"ok": true, "changed": true}
