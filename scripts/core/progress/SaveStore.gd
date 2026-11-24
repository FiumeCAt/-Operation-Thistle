extends RefCounted
class_name ProgressSaveStore
## 存档持久化与版本迁移存储（纯无状态服务，不依赖场景树）：
## 负责默认结构、版本迁移框架、字段规范化与边界裁剪、主存档原子写盘 + 双备份环（.bak/.bak2）、
## 损坏快照保全与自动回退，以及 5 个手动槽位的读写与摘要生成。

const VERSION := 1
const DEFAULT_PATH := "user://save_v1.json"
const SLOT_COUNT := 5
const DEFAULT_LASER_COLOR := "#39ff88"
const DEFAULT_RETICLE_COLOR := "#ff7a3c"

const AMMO_DISPLAY_MODES := ["both", "numeric", "graphic"]
const WEAPON_IDS := [
	"m870", "m1014", "saiga12k", "g17",
	"g18", "m1911", "fn57", "python",
	"mp7", "tmp", "p90", "ump45",
	"fal", "akm", "l85a2", "sr25", "vss", "awm",
]
const SPAWN_IDS := ["insertion", "abandoned"]
const EXTRACT_IDS := ["east", "south"]


static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"resources": 0,
		"materials_2d": {"electronics": 0, "energy": 0, "parts": 0},
		"advanced_2d": {
			"weapon_parts": 0, "electronic_core": 0,
			"high_energy_cell": 0, "military_alloy": 0,
		},
		"weapon_mods_2d": {"m870": {}, "m1014": {}, "saiga12k": {}, "g17": {}},
		"armor_mods_2d": {},
		"xp": 0,
		"skill_level": 1,
		"upgrades": {"hp": 0, "support": 0, "gun": 0, "fov": 0, "sight": 0},
		"talents_2d": {
			"hp": 0, "gun": 0, "move": 0, "reload": 0, "scavenge": 0, "loading": 0,
			"armor": 0, "magazine": 0, "reserve": 0, "magnet": 0,
		},
		"loadout": {"weapon": "m870", "ammo": "buckshot"},
		"loadout_2d": ["g17", "m870"],
		"deployment": {"spawn": "insertion", "extract": "east"},
		"run_mode": "raid",
		"map_id": "facility",
		"active_slot": 1,
		"armor_max": 100,
		"armor_level": 1,
		"ammo_display": "both",
		"fire_rate_display": "interval",
		"armor_display": "value",
		"volume": 0.8,
		"sfx_volume": 0.8,
		"music_volume": 0.8,
		"screen_shake": true,
		"bullet_trail_enabled": true,
		"hitstop_enabled": false,
		"shake_scale": 100.0,
		"sample_impacts": true,
		"hit_fx_level": 1,
		"view_zoom": 100,
		"motion_blur": true,
		"scope_motion_blur": true,
		"scope_lens_distortion": true,
		"reticle_styles": {},
		"laser_color": DEFAULT_LASER_COLOR,
		"reticle_color": DEFAULT_RETICLE_COLOR,
		"debug_enabled": false,
		"debug": {
			"recoil_v": 1.0, "recoil_h": 1.0, "recoil_cap": 1.0,
			"spread": 1.0, "damage": 1.0, "ads": 1.0, "move": 1.0, "vision": 1.0,
		},
		"camera_mode": 1,
		"bright_test": true,
		"settings_rev": 2,
		"support_charges": 2,
	}


static func slot_path(save_path: String, slot: int) -> String:
	var index := clampi(slot, 1, SLOT_COUNT)
	return "%s_slot%d.json" % [save_path.get_basename(), index]


static func backup_paths(save_path: String) -> Array[String]:
	return [save_path + ".bak", save_path + ".bak2"]


static func save_family_paths(save_path: String) -> Array[String]:
	var paths: Array[String] = [
		save_path,
		save_path + ".tmp",
		save_path + ".bak",
		save_path + ".bak2",
		save_path + ".corrupt.json",
	]
	for slot in range(1, SLOT_COUNT + 1):
		var path := slot_path(save_path, slot)
		paths.append(path)
		paths.append(path + ".tmp")
	return paths


static func remove_save_family(save_path: String) -> void:
	for path in save_family_paths(save_path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 版本迁移框架：按主版本号依次执行迁移，后续升级 VERSION = 2 只需在此追加单步转换。
## 返回 {"data": Dictionary, "migrated": bool}；不支持的高版本或损坏结构返回空 data。
static func migrate_save_version(parsed: Dictionary) -> Dictionary:
	var ver := int(parsed.get("version", -1))
	if ver < 0 or ver > VERSION:
		return {"data": {}, "migrated": false}
	var current := parsed.duplicate(true)
	var migrated := false
	# 预留 v0 -> v1 兼容升级钩子（若旧档缺失版本号 0，补齐基础容器再升到 v1）。
	if ver == 0:
		for dict_key in ["materials_2d", "advanced_2d", "upgrades", "talents_2d",
				"loadout", "deployment"]:
			if typeof(current.get(dict_key, null)) != TYPE_DICTIONARY:
				current[dict_key] = defaults()[dict_key]
		if typeof(current.get("loadout_2d", null)) != TYPE_ARRAY:
			current["loadout_2d"] = defaults()["loadout_2d"]
		current["version"] = 1
		ver = 1
		migrated = true
	if ver != VERSION:
		return {"data": {}, "migrated": false}
	return {"data": current, "migrated": migrated}


## 结构校验：版本匹配且关键字段类型正确，截断/乱码文件会被拒绝。
static func is_valid_save(parsed: Dictionary) -> bool:
	if int(parsed.get("version", -1)) != VERSION:
		return false
	for key in ["materials_2d", "advanced_2d", "upgrades", "talents_2d",
			"loadout", "deployment"]:
		if typeof(parsed.get(key, null)) != TYPE_DICTIONARY:
			return false
	if typeof(parsed.get("loadout_2d", null)) != TYPE_ARRAY:
		return false
	var resources = parsed.get("resources", 0)
	if typeof(resources) != TYPE_INT and typeof(resources) != TYPE_FLOAT:
		return false
	return true


## 读文件并做结构校验；支持低版本存档经版本迁移框架升级后再校验，任何损坏/乱码返回空字典。
static func read_valid_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var dict: Dictionary = parsed
	if is_valid_save(dict):
		return dict
	var ver := int(dict.get("version", -1))
	if ver >= 0 and ver < VERSION:
		var migrated := migrate_save_version(dict)
		var upgraded: Dictionary = migrated["data"]
		if not upgraded.is_empty() and is_valid_save(upgraded):
			return dict
	return {}


## 字段补全、上限裁剪与非法值过滤；读主存档和读槽位共用。
## 返回 true 表示发生了需要立刻落盘的迁移。
static func normalize_data(data: Dictionary, upgrade_max: Dictionary,
		talent_2d_max: Dictionary) -> bool:
	var migrated := false
	var def := defaults()
	if typeof(data.get("upgrades", null)) != TYPE_DICTIONARY:
		data["upgrades"] = def["upgrades"]
	else:
		var upgrades: Dictionary = data["upgrades"]
		data["upgrades"] = {}
		for key in upgrade_max:
			data["upgrades"][key] = clampi(int(upgrades.get(key, 0)), 0, int(upgrade_max[key]))
	var talents = data.get("talents_2d", null)
	if typeof(talents) != TYPE_DICTIONARY:
		data["talents_2d"] = def["talents_2d"]
	else:
		var clean_talents := {}
		for key in talent_2d_max:
			clean_talents[key] = clampi(int(talents.get(key, 0)), 0, int(talent_2d_max[key]))
		data["talents_2d"] = clean_talents
	var materials = data.get("materials_2d", null)
	if typeof(materials) != TYPE_DICTIONARY:
		materials = {}
	var clean_materials := {}
	for id in ResourceDB.BASIC:
		clean_materials[String(id)] = maxi(0, int(materials.get(String(id), 0)))
	data["materials_2d"] = clean_materials
	var advanced = data.get("advanced_2d", null)
	if typeof(advanced) != TYPE_DICTIONARY:
		advanced = {}
	var clean_advanced := {}
	for id in ResourceDB.ADVANCED:
		clean_advanced[String(id)] = maxi(0, int(advanced.get(String(id), 0)))
	data["advanced_2d"] = clean_advanced
	var weapon_mods = data.get("weapon_mods_2d", null)
	if typeof(weapon_mods) != TYPE_DICTIONARY:
		weapon_mods = {}
	var clean_weapon_mods := {}
	for weapon_id in WEAPON_IDS:
		var installed = weapon_mods.get(weapon_id, {})
		var clean_slots := {}
		if typeof(installed) == TYPE_DICTIONARY:
			for slot_def in ModDB.WEAPON_SLOTS:
				var slot := String(slot_def["id"])
				var option_id := String(installed.get(slot, ""))
				if ModDB.option(slot, option_id, false, String(weapon_id)).is_empty():
					continue
				clean_slots[slot] = option_id
		clean_weapon_mods[weapon_id] = clean_slots
	data["weapon_mods_2d"] = clean_weapon_mods
	var armor_mods = data.get("armor_mods_2d", null)
	if typeof(armor_mods) != TYPE_DICTIONARY:
		armor_mods = {}
	var clean_armor_mods := {}
	for slot_def in ModDB.ARMOR_SLOTS:
		var slot := String(slot_def["id"])
		var option_id := String(armor_mods.get(slot, ""))
		if not ModDB.option(slot, option_id, true).is_empty():
			clean_armor_mods[slot] = option_id
	data["armor_mods_2d"] = clean_armor_mods
	if typeof(data.get("loadout", null)) != TYPE_DICTIONARY:
		data["loadout"] = {"weapon": "m870", "ammo": "buckshot"}
	else:
		data["loadout"] = {
			"weapon": String(data["loadout"].get("weapon", "m870")),
			"ammo": String(data["loadout"].get("ammo", "buckshot")),
		}
	if not AMMO_DISPLAY_MODES.has(String(data.get("ammo_display", "both"))):
		data["ammo_display"] = "both"
	if not ["interval", "rpm"].has(String(data.get("fire_rate_display", "interval"))):
		data["fire_rate_display"] = "interval"
	if not ["value", "rha_mm"].has(String(data.get("armor_display", "value"))):
		data["armor_display"] = "value"
	var loadout_2d = data.get("loadout_2d", null)
	var clean_loadout: Array = []
	if typeof(loadout_2d) == TYPE_ARRAY:
		for id in loadout_2d:
			var key := String(id)
			if WEAPON_IDS.has(key) and not clean_loadout.has(key):
				clean_loadout.append(key)
	if clean_loadout.is_empty():
		clean_loadout = ["g17", "m870"]
	if clean_loadout.size() > 2:
		clean_loadout.resize(2)
	data["loadout_2d"] = clean_loadout
	var deployment = data.get("deployment", null)
	var spawn_id := "insertion"
	var extract_id := "east"
	if typeof(deployment) == TYPE_DICTIONARY:
		spawn_id = String(deployment.get("spawn", "insertion"))
		extract_id = String(deployment.get("extract", "east"))
	if not SPAWN_IDS.has(spawn_id):
		spawn_id = "insertion"
	if not EXTRACT_IDS.has(extract_id):
		extract_id = "east"
	data["deployment"] = {"spawn": spawn_id, "extract": extract_id}
	if not ["raid", "waves"].has(String(data.get("run_mode", "raid"))):
		data["run_mode"] = "raid"
	if not ["facility", "goliath_arena"].has(String(data.get("map_id", "facility"))):
		data["map_id"] = "facility"
	if String(data.get("run_mode", "raid")) != "waves":
		data["map_id"] = "facility"
	data["armor_max"] = clampi(int(data.get("armor_max", 100)), 50, 200)
	data["armor_level"] = clampi(int(data.get("armor_level", 1)), 1, 4)
	data["volume"] = clampf(float(data.get("volume", 0.8)), 0.0, 1.0)
	data["sfx_volume"] = clampf(float(data.get("sfx_volume", 0.8)), 0.0, 1.0)
	data["music_volume"] = clampf(float(data.get("music_volume", 0.8)), 0.0, 1.0)
	data["screen_shake"] = bool(data.get("screen_shake", true))
	data["bullet_trail_enabled"] = bool(data.get("bullet_trail_enabled", true))
	data["hitstop_enabled"] = bool(data.get("hitstop_enabled", false))
	data["shake_scale"] = clampf(float(data.get("shake_scale", 100.0)), 0.0, 1000.0)
	data["sample_impacts"] = bool(data.get("sample_impacts", true))
	data["hit_fx_level"] = clampi(int(data.get("hit_fx_level", 1)), 0, 2)
	data["view_zoom"] = clampf(
		roundf(float(data.get("view_zoom", 100)) / 10.0) * 10.0, 20.0, 200.0)
	data["motion_blur"] = bool(data.get("motion_blur", true))
	data["scope_motion_blur"] = bool(data.get("scope_motion_blur", true))
	data["scope_lens_distortion"] = bool(data.get("scope_lens_distortion", true))
	if not (data.get("reticle_styles") is Dictionary):
		data["reticle_styles"] = {}
	var raw_laser := String(data.get("laser_color", DEFAULT_LASER_COLOR))
	data["laser_color"] = raw_laser if Color.html_is_valid(raw_laser) else DEFAULT_LASER_COLOR
	var raw_reticle := String(data.get("reticle_color", DEFAULT_RETICLE_COLOR))
	data["reticle_color"] = raw_reticle if Color.html_is_valid(raw_reticle) else DEFAULT_RETICLE_COLOR
	data["debug_enabled"] = bool(data.get("debug_enabled", false))
	if not (data.get("debug") is Dictionary):
		data["debug"] = {}
	data["camera_mode"] = clampi(int(data.get("camera_mode", 1)), 0, 2)
	data["bright_test"] = bool(data.get("bright_test", true))
	if int(data.get("settings_rev", 0)) < 2:
		data["settings_rev"] = 2
		data["bright_test"] = true
		migrated = true
	data["resources"] = maxi(0, int(data.get("resources", 0)))
	data["xp"] = maxi(0, int(data.get("xp", 0)))
	data["skill_level"] = 1 + int(data["xp"]) / 20
	data["support_charges"] = maxi(0, int(data.get("support_charges", 2)))
	data["active_slot"] = clampi(int(data.get("active_slot", 1)), 1, SLOT_COUNT)
	data["version"] = VERSION
	return migrated


## 读取主存档（主文件 → 备份环 .bak/.bak2 → 默认值），返回 {loaded, data, source, migrated}。
static func load_main(save_path: String, upgrade_max: Dictionary,
		talent_2d_max: Dictionary) -> Dictionary:
	var data := defaults()
	var parsed := read_valid_save(save_path)
	var source := save_path
	if parsed.is_empty():
		for backup in backup_paths(save_path):
			parsed = read_valid_save(backup)
			if not parsed.is_empty():
				source = backup
				break
	var loaded := not parsed.is_empty()
	var migrated := false
	if loaded:
		var ver_res := migrate_save_version(parsed)
		var migrated_dict: Dictionary = ver_res["data"]
		if bool(ver_res["migrated"]):
			migrated = true
		if not migrated_dict.is_empty():
			parsed = migrated_dict
		for key in data:
			if parsed.has(key):
				data[key] = parsed[key]
	elif FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(save_path + ".corrupt.json"))
		push_warning("存档校验失败且没有可用备份，本次加载默认数据：%s" % save_path)
	if normalize_data(data, upgrade_max, talent_2d_max):
		migrated = true
	return {
		"loaded": loaded,
		"data": data,
		"source": source,
		"migrated": migrated,
	}


## 保存前把当前主存档滚入备份环（.bak / .bak2）；损坏文件不入备份环。
static func rotate_backups(save_path: String) -> void:
	if not FileAccess.file_exists(save_path):
		return
	if read_valid_save(save_path).is_empty():
		return
	var bak := save_path + ".bak"
	var bak2 := save_path + ".bak2"
	if FileAccess.file_exists(bak2):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak2))
	if FileAccess.file_exists(bak):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(bak),
			ProjectSettings.globalize_path(bak2))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),
		ProjectSettings.globalize_path(bak))


## 原子写入主存档（写 .tmp → 回读校验 → 备份轮换 → rename），返回 {ok, text}。
static func write_main(save_path: String, data: Dictionary,
		last_saved_text: String) -> Dictionary:
	data["version"] = VERSION
	var text := JSON.stringify(data, "\t")
	if text == last_saved_text and FileAccess.file_exists(save_path):
		return {"ok": true, "text": last_saved_text}
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档临时文件：%s" % temp_path)
		return {"ok": false, "text": last_saved_text}
	file.store_string(text)
	file.flush()
	file.close()
	if read_valid_save(temp_path).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		push_error("存档临时文件校验失败：%s" % temp_path)
		return {"ok": false, "text": last_saved_text}
	rotate_backups(save_path)
	var ok := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(save_path)) == OK
	if not ok:
		push_error("存档替换失败：%s" % save_path)
		return {"ok": false, "text": last_saved_text}
	return {"ok": true, "text": text}


## 损坏主存档留档后移除，为重建腾出路径。
static func quarantine_corrupt_main(save_path: String) -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(save_path + ".corrupt.json"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## ---- 手动 5 槽位存取与摘要 ----

static func slot_summary(source: Dictionary) -> Dictionary:
	var talents := 0
	var talent_map: Dictionary = source.get("talents_2d", {})
	for key in talent_map:
		talents += int(talent_map[key])
	var materials := 0
	for id in ResourceDB.BASIC:
		materials += int((source.get("materials_2d", {}) as Dictionary).get(String(id), 0))
	for id in ResourceDB.ADVANCED:
		materials += int((source.get("advanced_2d", {}) as Dictionary).get(String(id), 0))
	return {
		"credits": int(source.get("resources", 0)),
		"xp": int(source.get("xp", 0)),
		"skill_level": int(source.get("skill_level", 1)),
		"talents": talents,
		"materials": materials,
		"run_mode": String(source.get("run_mode", "raid")),
		"map_id": String(source.get("map_id", "facility")),
	}


static func is_valid_slot_payload(payload: Dictionary) -> bool:
	var slot_data = payload.get("data", null)
	return typeof(slot_data) == TYPE_DICTIONARY and is_valid_save(slot_data)


static func read_slot_payload(save_path: String, slot: int) -> Dictionary:
	var path := slot_path(save_path, slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = json.data
	if not is_valid_slot_payload(payload):
		return {}
	return payload


static func write_slot_payload(save_path: String, slot: int,
		payload: Dictionary) -> bool:
	if not is_valid_slot_payload(payload):
		push_error("拒绝写入结构不完整的存档槽位：%d" % slot)
		return false
	var path := slot_path(save_path, slot)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档槽位：%s" % temp_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	var check := FileAccess.open(temp_path, FileAccess.READ)
	var json := JSON.new()
	var parsed_ok := false
	if check != null:
		parsed_ok = json.parse(check.get_as_text()) == OK \
			and typeof(json.data) == TYPE_DICTIONARY \
			and is_valid_slot_payload(json.data)
		check.close()
	if not parsed_ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		push_error("存档槽位校验失败：%s" % temp_path)
		return false
	var result := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)) == OK
	if not result:
		push_error("存档槽位替换失败：%s" % path)
	return result


static func build_slot_payload(data: Dictionary) -> Dictionary:
	return {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"summary": slot_summary(data),
		"data": data.duplicate(true),
	}


static func slot_info(save_path: String, slot: int, active_index: int) -> Dictionary:
	var index := clampi(slot, 1, SLOT_COUNT)
	var payload := read_slot_payload(save_path, index)
	if payload.is_empty():
		return {"slot": index, "empty": true, "active": index == active_index}
	return {
		"slot": index,
		"empty": false,
		"active": index == active_index,
		"saved_at": int(payload.get("saved_at", 0)),
		"summary": (payload.get("summary", {}) as Dictionary).duplicate(),
	}
