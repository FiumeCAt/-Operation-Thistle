extends Node
class_name ProgressService

const VERSION := 1
const DEFAULT_PATH := "user://save_v1.json"
## 主菜单存档管理：5 个手动槽位，退出游戏时自动写回当前槽位。
const SLOT_COUNT := 5
## 以下数值默认值会被 data/progression.json 覆盖（_ready 时加载），
## 保留默认值是为了表缺失时仍能启动。
## 切片期只开放可成长条目，并各自设上限，避免无限叠加。
var UPGRADE_MAX := {"hp": 5, "support": 2, "gun": 3, "fov": 4, "sight": 4}
## 经济倍率：所有信用点花费 ×3（+200%），获取 ×0.5。
var CREDIT_COST_MUL := 3.0
var CREDIT_GAIN_MUL := 0.5
## 2D 天赋树独立存档，避免把 3D 的支援/视野线强行套到 2D。
## 生命/枪械与 3D 线分开，2D 的天赋只影响 2D 行动。
var TALENT_2D_MAX := {
	"hp": 5, "gun": 3, "move": 4, "reload": 3, "scavenge": 3, "loading": 1,
	"armor": 3, "magazine": 3, "reserve": 3, "magnet": 3,
}
## 2D 天赋前置：进阶节点需要基础节点至少 Lv.1。
var TALENT_2D_PREREQ := {
	"move": "hp", "reload": "gun", "magazine": "reload",
	"loading": "magazine", "reserve": "magazine",
	"armor": "move", "magnet": "scavenge",
}
## 三条强化线各自消耗一种基础资源：枪械 / 人物性能 / 生存搜刮。
var TALENT_2D_MATERIAL := {
	"hp": "energy", "move": "energy",
	"gun": "electronics", "reload": "electronics", "magazine": "electronics",
	"scavenge": "parts", "loading": "parts", "armor": "parts",
	"reserve": "parts", "magnet": "electronics",
}
## ID 白名单位于代码（结构约束），数值上限位于 data/progression.json。
const AMMO_DISPLAY_MODES := ["both", "numeric", "graphic"]
const WEAPON_IDS := [
	"m870", "m1014", "saiga12k", "g17",
	"g18", "m1911", "fn57", "python",
	"mp7", "tmp", "p90", "ump45",
	"fal", "akm", "l85a2", "sr25", "vss", "awm",
]
const SPAWN_IDS := ["insertion", "abandoned"]
const EXTRACT_IDS := ["east", "south"]

var save_path := DEFAULT_PATH
var data: Dictionary = {}
## 上一次成功写入的存档文本，用于跳过无变化写入。
var _last_saved_text := ""

func _ready() -> void:
	_load_progression_tables()
	var args := OS.get_cmdline_user_args()
	var explicit := false
	for i in args.size():
		if args[i] == "--save-path" and i + 1 < args.size():
			save_path = args[i + 1]
			explicit = true
	if not explicit:
		var test_name := _test_script_name()
		if test_name != "":
			save_path = "user://test_%s.json" % test_name
			_remove_save()
	load_data()

## 从 data/progression.json 覆盖成长/天赋上限；缺表时保留脚本内默认值。
func _load_progression_tables() -> void:
	var table := GameData.table("progression")
	if table.has("upgrade_max"):
		UPGRADE_MAX = table["upgrade_max"]
	if table.has("talent_max"):
		TALENT_2D_MAX = table["talent_max"]
	if table.has("talent_prereq"):
		TALENT_2D_PREREQ = table["talent_prereq"]
	if table.has("talent_material"):
		TALENT_2D_MATERIAL = table["talent_material"]
	if table.has("credit_cost_mul"):
		CREDIT_COST_MUL = float(table["credit_cost_mul"])
	if table.has("credit_gain_mul"):
		CREDIT_GAIN_MUL = float(table["credit_gain_mul"])

## 测试/录制脚本运行时自动隔离存档，避免读写玩家真实的 save_v1.json。
## 只要脚本位于 res://tests/ 下（不限于 *_test.gd），就使用独立存档；
## 这样临时调试脚本也不会再碰正式存档。
func _test_script_name() -> String:
	for arg in OS.get_cmdline_args():
		var text := String(arg).replace("\\", "/")
		if not text.ends_with(".gd"):
			continue
		if text.begins_with("res://tests/") or text.contains("/tests/"):
			return text.get_file().get_basename()
		if text.ends_with("_test.gd"):
			return text.get_file().get_basename()
	return ""


## 当前存档是否位于隔离路径（测试存档或显式 --save-path）。
func is_isolated_save() -> bool:
	return save_path != DEFAULT_PATH


func _remove_save() -> void:
	for path in _save_family_paths():
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 主存档 + 临时文件 + 备份环 + 损坏快照 + 五个存档槽位。
func _save_family_paths() -> Array[String]:
	var paths: Array[String] = [
		save_path,
		save_path + ".tmp",
		save_path + ".bak",
		save_path + ".bak2",
		save_path + ".corrupt.json",
	]
	for slot in range(1, SLOT_COUNT + 1):
		var path := slot_path(slot)
		paths.append(path)
		paths.append(path + ".tmp")
	return paths

func _defaults() -> Dictionary:
	return {
		"version": VERSION,
		## 信用点：原「资源」货币改名，供基地强化/制造消费。
		"resources": 0,
		## 三种基础资源：电子元件 / 能量单元 / 机械零件。
		"materials_2d": {"electronics": 0, "energy": 0, "parts": 0},
		## 进阶资源：先入库，用途后续版本接入。
		"advanced_2d": {
			"weapon_parts": 0, "electronic_core": 0,
			"high_energy_cell": 0, "military_alloy": 0,
		},
		## 配件 / 组件：{武器 id: {槽位: 选项 id}}，护甲独立一份。
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
		## 行动模式：raid = 正常搜刮撤离；waves = 浪潮生存。
		"run_mode": "raid",
		## 浪潮地图：facility = 设施浪潮；goliath_arena = 歌利亚狂潮。
		"map_id": "facility",
		## 当前手动存档槽位（1–5）；退出游戏时自动写回这里。
		"active_slot": 1,
		"armor_max": 100,
		"armor_level": 1,
		"ammo_display": "both",
		"fire_rate_display": "interval",
		"volume": 0.8,
		"sfx_volume": 0.8,
		"music_volume": 0.8,
		"screen_shake": true,
		## 弹道线条：默认开启；关闭后仅隐藏枪口到弹丸的长曳光线，弹丸实体与飞行/命中不变。
		"bullet_trail_enabled": true,
		## 命中顿帧默认关闭；开火震动幅度以百分比保存（0–1000）。
		"hitstop_enabled": false,
		"shake_scale": 100.0,
		## 外部命中采样开关：true 用 assets/audio/sfx/impacts 的 CC0 采样，false 回到程序化三层。
		"sample_impacts": true,
		## 命中特写层级：2 完整 / 1 减弱（默认）/ 0 关闭，只影响命中粒子，不影响伤害反馈。
		"hit_fx_level": 1,
		"view_zoom": 100,
		"motion_blur": true,
		## 高倍镜镜内特效：瞄准移动时的运动模糊与镜片畸变，可分别在设置里关闭。
		"scope_motion_blur": true,
		"scope_lens_distortion": true,
		## 每个瞄具单独保存的准星样式：{sight_id: "cross"}。
		"reticle_styles": {},
		## 调试模式：全局数值倍率，仅调试开关打开时生效。
		"debug_enabled": false,
		"debug": {
			"recoil_v": 1.0, "recoil_h": 1.0, "recoil_cap": 1.0,
			"spread": 1.0, "damage": 1.0, "ads": 1.0, "move": 1.0, "vision": 1.0,
		},
		"camera_mode": 1,
		## 场景黑暗默认关闭：正常游玩与截图都用明亮照明，需要压暗时在设置里打开。
		"bright_test": true,
		"settings_rev": 2,
		"support_charges": 2,
	}

## 读取存档：主文件 → 备份环（.bak / .bak2）→ 默认值。
## 主文件损坏时不会直接覆盖，而是先留一份 .corrupt.json 再用备份重建。
func load_data() -> bool:
	_last_saved_text = ""
	data = _defaults()
	var parsed := _read_valid_save(save_path)
	var source := save_path
	if parsed.is_empty():
		for backup in _backup_paths():
			parsed = _read_valid_save(backup)
			if not parsed.is_empty():
				source = backup
				break
	var loaded := not parsed.is_empty()
	if loaded:
		for key in data:
			if parsed.has(key):
				data[key] = parsed[key]
	elif FileAccess.file_exists(save_path):
		# 没有可用备份时至少把坏文件留一份快照，方便之后人工恢复。
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(save_path + ".corrupt.json"))
		push_warning("存档校验失败且没有可用备份，本次加载默认数据：%s" % save_path)
	var migrated := _normalize_data()
	if loaded and source != save_path:
		_recover_from_backup(source)
	elif migrated:
		save_data()
	return loaded


## 字段补全、上限裁剪与非法值过滤；读主存档和读槽位共用。
## 返回 true 表示发生了需要立刻落盘的迁移。
func _normalize_data() -> bool:
	var migrated := false
	if typeof(data["upgrades"]) != TYPE_DICTIONARY:
		data["upgrades"] = _defaults()["upgrades"]
	else:
		# 旧存档缺少新字段时补 0，并按当前上限裁剪。
		var upgrades: Dictionary = data["upgrades"]
		data["upgrades"] = {}
		for key in UPGRADE_MAX:
			data["upgrades"][key] = clampi(int(upgrades.get(key, 0)), 0, int(UPGRADE_MAX[key]))
	var talents = data.get("talents_2d", null)
	if typeof(talents) != TYPE_DICTIONARY:
		data["talents_2d"] = _defaults()["talents_2d"]
	else:
		var clean_talents := {}
		for key in TALENT_2D_MAX:
			clean_talents[key] = clampi(int(talents.get(key, 0)), 0, int(TALENT_2D_MAX[key]))
		data["talents_2d"] = clean_talents
	# 基础资源与进阶资源：旧存档缺少时补 0，并过滤未知键。
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
	# 配件：只保留已知武器 / 槽位 / 选项，旧存档缺字段时补空。
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
	if typeof(data["loadout"]) != TYPE_DICTIONARY:
		data["loadout"] = {"weapon": "m870", "ammo": "buckshot"}
	else:
		data["loadout"] = {"weapon": String(data["loadout"].get("weapon", "m870")), "ammo": String(data["loadout"].get("ammo", "buckshot"))}
	if not AMMO_DISPLAY_MODES.has(String(data.get("ammo_display", "both"))):
		data["ammo_display"] = "both"
	if not ["interval", "rpm"].has(String(data.get("fire_rate_display", "interval"))):
		data["fire_rate_display"] = "interval"
	# 2D 携带武器：1-2 把，过滤未知 ID 与重复项。
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
	# 部署点：出生点与默认撤离点必须来自已解锁列表。
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
	data["debug_enabled"] = bool(data.get("debug_enabled", false))
	if not (data.get("debug") is Dictionary):
		data["debug"] = {}
	data["camera_mode"] = clampi(int(data.get("camera_mode", 1)), 0, 2)
	data["bright_test"] = bool(data.get("bright_test", true))
	# settings_rev 迁移：每次提升版本都把场景黑暗重置为关闭，旧存档也能立刻看到亮版画面。
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


## 备份环：.bak 为上一次成功存档，.bak2 为上上次。
func _backup_paths() -> Array[String]:
	return [save_path + ".bak", save_path + ".bak2"]


## 读文件并做结构校验；任何读取/解析/字段错误都返回空字典。
func _read_valid_save(path: String) -> Dictionary:
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
	if not _is_valid_save(dict):
		return {}
	return dict


## 结构校验：版本匹配且关键字段类型正确，截断/乱码文件会被拒绝。
func _is_valid_save(parsed: Dictionary) -> bool:
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


## 主存档损坏时：留档坏文件 → 删除主文件 → 用备份内容重建主存档。
func _recover_from_backup(source: String) -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(save_path + ".corrupt.json"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	_last_saved_text = ""
	if save_data():
		push_warning("存档已从备份恢复：%s -> %s" % [source, save_path])


## 保存前把当前主存档滚入备份环，保证任何时刻都有一份上一版可回退。
## 损坏的主存档不会进入备份环，避免把坏文件当成可恢复版本。
func _rotate_backups() -> void:
	if not FileAccess.file_exists(save_path):
		return
	if _read_valid_save(save_path).is_empty():
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


func save_data() -> bool:
	data["version"] = VERSION
	var text := JSON.stringify(data, "\t")
	# 内容没变且主文件仍在时跳过写入，避免设置开关反复触发备份轮换。
	if text == _last_saved_text and FileAccess.file_exists(save_path):
		return true
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档临时文件：%s" % temp_path)
		return false
	file.store_string(text)
	file.flush()
	file.close()
	# 回读校验：确认落盘内容完整后才覆盖主存档。
	if _read_valid_save(temp_path).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		push_error("存档临时文件校验失败：%s" % temp_path)
		return false
	_rotate_backups()
	var ok := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(save_path)) == OK
	if ok:
		_last_saved_text = text
	else:
		push_error("存档替换失败：%s" % save_path)
	return ok


func reset_for_test() -> bool:
	# 双保险：即使测试隔离检测失效，也不允许重置正式存档。
	if not is_isolated_save():
		push_error("reset_for_test 拒绝写入正式存档：%s" % save_path)
		return false
	data = _defaults()
	_last_saved_text = ""
	return save_data()


## ---- 主菜单手动存档槽位 ----

func slot_path(slot: int) -> String:
	var index := clampi(slot, 1, SLOT_COUNT)
	return "%s_slot%d.json" % [save_path.get_basename(), index]


func active_slot() -> int:
	return clampi(int(data.get("active_slot", 1)), 1, SLOT_COUNT)


## 槽位摘要：空槽返回 {"empty": true}，主菜单列表直接用它刷新。
func slot_info(slot: int) -> Dictionary:
	var index := clampi(slot, 1, SLOT_COUNT)
	var payload := _read_slot_payload(index)
	if payload.is_empty():
		return {"slot": index, "empty": true, "active": index == active_slot()}
	return {
		"slot": index,
		"empty": false,
		"active": index == active_slot(),
		"saved_at": int(payload.get("saved_at", 0)),
		"summary": (payload.get("summary", {}) as Dictionary).duplicate(),
	}


## 把当前进度写入指定槽位，并把它设为「当前槽位」。
func save_to_slot(slot: int) -> bool:
	var index := clampi(slot, 1, SLOT_COUNT)
	data["active_slot"] = index
	if not save_data():
		return false
	return _write_slot_payload(index, {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"summary": _slot_summary(data),
		"data": data.duplicate(true),
	})


## 读取槽位覆盖当前进度；失败时保持内存数据不变。
func load_from_slot(slot: int) -> bool:
	var index := clampi(slot, 1, SLOT_COUNT)
	var payload := _read_slot_payload(index)
	if payload.is_empty():
		return false
	var slot_data: Dictionary = payload["data"]
	data = _defaults()
	for key in data:
		if slot_data.has(key):
			data[key] = slot_data[key]
	_normalize_data()
	data["active_slot"] = index
	_last_saved_text = ""
	return save_data()


## 退出游戏自动存档：主存档 + 当前槽位。
func autosave_on_exit() -> void:
	if data.is_empty():
		return
	if not save_data():
		return
	var index := active_slot()
	if not _write_slot_payload(index, {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"summary": _slot_summary(data),
		"data": data.duplicate(true),
	}):
		push_warning("退出自动存档写入槽位失败：%d" % index)


func _slot_summary(source: Dictionary) -> Dictionary:
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


func _read_slot_payload(slot: int) -> Dictionary:
	var path := slot_path(slot)
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
	if not _is_valid_slot_payload(payload):
		return {}
	return payload


func _is_valid_slot_payload(payload: Dictionary) -> bool:
	var slot_data = payload.get("data", null)
	return typeof(slot_data) == TYPE_DICTIONARY and _is_valid_save(slot_data)


func _write_slot_payload(slot: int, payload: Dictionary) -> bool:
	if not _is_valid_slot_payload(payload):
		push_error("拒绝写入结构不完整的存档槽位：%d" % slot)
		return false
	var path := slot_path(slot)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档槽位：%s" % temp_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	# 回读临时文件，确认槽位内容完整后再覆盖旧槽位。
	var check := FileAccess.open(temp_path, FileAccess.READ)
	var json := JSON.new()
	var parsed_ok := false
	if check != null:
		parsed_ok = json.parse(check.get_as_text()) == OK \
			and typeof(json.data) == TYPE_DICTIONARY \
			and _is_valid_slot_payload(json.data)
		check.close()
	if not parsed_ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		push_error("存档槽位校验失败：%s" % temp_path)
		return false
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(path)) == OK
	if not result:
		push_error("存档槽位替换失败：%s" % path)
	return result


func _exit_tree() -> void:
	# 退出游戏（菜单退出或关窗口）时自动保存主存档与当前槽位。
	autosave_on_exit()


func add_resources(amount: int) -> void:
	if amount <= 0:
		return
	data["resources"] = maxi(0, int(data.get("resources", 0)) + credit_gain(amount))
	save_data()


## 信用点花费 / 获取倍率；表在 data/progression.json。
func credit_cost(base: int) -> int:
	return int(round(float(base) * CREDIT_COST_MUL))


func credit_gain(base: int) -> int:
	return int(round(float(base) * CREDIT_GAIN_MUL))


## 信用点余额（内部沿用 resources 键，避免旧存档与 3D 成长线断档）。
func credits() -> int:
	return int(data.get("resources", 0))


func material_count(id: StringName) -> int:
	return int(data.get("materials_2d", {}).get(String(id), 0))


func advanced_count(id: StringName) -> int:
	return int(data.get("advanced_2d", {}).get(String(id), 0))


## 撤离结算：把本局带出的基础/进阶资源并入库存。
func add_materials(counts: Dictionary) -> void:
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
	save_data()


## ---- 配件 / 组件 ----

func weapon_mods_2d(weapon_id: StringName) -> Dictionary:
	var all_mods: Dictionary = data.get("weapon_mods_2d", {})
	return (all_mods.get(String(weapon_id), {}) as Dictionary).duplicate()


func armor_mods_2d() -> Dictionary:
	return (data.get("armor_mods_2d", {}) as Dictionary).duplicate()


## ---- 外观颜色（激光 / 准心） ----
const DEFAULT_LASER_COLOR := "#39ff88"
const DEFAULT_RETICLE_COLOR := "#ff7a3c"

func laser_color() -> Color:
	return _sight_color("laser_color", DEFAULT_LASER_COLOR)

func reticle_color() -> Color:
	return _sight_color("reticle_color", DEFAULT_RETICLE_COLOR)

func _sight_color(key: String, fallback: String) -> Color:
	var raw := String(data.get(key, fallback))
	return Color.html(raw) if Color.html_is_valid(raw) else Color.html(fallback)

func set_laser_color(color: Color) -> void:
	data["laser_color"] = "#" + color.to_html(false)
	save_data()

func set_reticle_color(color: Color) -> void:
	data["reticle_color"] = "#" + color.to_html(false)
	save_data()


## 安装武器配件：同槽位换装会重新收费；重复安装当前选项不收费。
func install_weapon_mod(weapon_id: StringName, slot: StringName, option_id: StringName) -> bool:
	var weapon := String(weapon_id)
	if not WEAPON_IDS.has(weapon):
		return false
	var entry := ModDB.option(String(slot), String(option_id), false, weapon)
	if entry.is_empty():
		return false
	var all_mods: Dictionary = data.get("weapon_mods_2d", {})
	var installed: Dictionary = all_mods.get(weapon, {})
	if String(installed.get(String(slot), "")) == String(option_id):
		return true
	if not _can_pay_mod(entry):
		return false
	_pay_mod(entry)
	installed[String(slot)] = String(option_id)
	all_mods[weapon] = installed
	data["weapon_mods_2d"] = all_mods
	return save_data()


## 安装护甲组件。
func install_armor_mod(slot: StringName, option_id: StringName) -> bool:
	var entry := ModDB.option(String(slot), String(option_id), true)
	if entry.is_empty():
		return false
	var installed: Dictionary = data.get("armor_mods_2d", {})
	if String(installed.get(String(slot), "")) == String(option_id):
		return true
	if not _can_pay_mod(entry):
		return false
	_pay_mod(entry)
	installed[String(slot)] = String(option_id)
	data["armor_mods_2d"] = installed
	return save_data()


func _can_pay_mod(entry: Dictionary) -> bool:
	var credits := int(entry.get("credits", 0))
	if credits < 0 or int(data.get("resources", 0)) < credits:
		return false
	var cost: Dictionary = entry.get("cost", {})
	var advanced: Dictionary = data.get("advanced_2d", {})
	for id in cost:
		if int(advanced.get(String(id), 0)) < int(cost[id]):
			return false
	return true


func _pay_mod(entry: Dictionary) -> void:
	data["resources"] = maxi(0, int(data.get("resources", 0)) - int(entry.get("credits", 0)))
	var advanced: Dictionary = data.get("advanced_2d", {})
	var cost: Dictionary = entry.get("cost", {})
	for id in cost:
		var key := String(id)
		advanced[key] = maxi(0, int(advanced.get(key, 0)) - int(cost[id]))
	data["advanced_2d"] = advanced

func upgrade_level(id: StringName) -> int:
	return int(data.get("upgrades", {}).get(String(id), 0))

func upgrade_max(id: StringName) -> int:
	return int(UPGRADE_MAX.get(String(id), 0))

## 返回下一级价格；未知项或已满级返回 -1。
func upgrade_cost(id: StringName) -> int:
	var key := String(id)
	if not UPGRADE_MAX.has(key):
		return -1
	var level := upgrade_level(id)
	if level >= int(UPGRADE_MAX[key]):
		return -1
	return credit_cost(15 + level * 15)

func buy_upgrade(id: StringName) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or int(data["resources"]) < cost:
		return false
	data["resources"] = int(data["resources"]) - cost
	data["upgrades"][String(id)] = upgrade_level(id) + 1
	data["xp"] = int(data["xp"]) + 5
	data["skill_level"] = 1 + int(data["xp"]) / 20
	return save_data()

func add_xp(amount: int) -> bool:
	data["xp"] = maxi(0, int(data.get("xp", 0)) + amount)
	data["skill_level"] = 1 + int(data["xp"]) / 20
	return save_data()

## ---- 2D 天赋树：与 3D 成长线共用资源/XP，但等级独立存档。 ----

func talent_2d_level(id: StringName) -> int:
	return int(data.get("talents_2d", {}).get(String(id), 0))

func talent_2d_max(id: StringName) -> int:
	return int(TALENT_2D_MAX.get(String(id), 0))

## 返回下一级价格；未知项或已满级返回 -1。
func talent_2d_cost(id: StringName) -> int:
	var key := String(id)
	if not TALENT_2D_MAX.has(key):
		return -1
	var level := talent_2d_level(id)
	if level >= int(TALENT_2D_MAX[key]):
		return -1
	return credit_cost(15 + level * 15)

## 该节点消耗哪种基础资源；未知节点返回空。
func talent_2d_material(id: StringName) -> StringName:
	return StringName(TALENT_2D_MATERIAL.get(String(id), ""))

## 材料消耗：3 → 6 → 9 … 与信用点一起扣。
func talent_2d_material_cost(id: StringName) -> int:
	var level := talent_2d_level(id)
	if talent_2d_material(id) == &"" or level >= talent_2d_max(id):
		return -1
	return 3 + level * 3

func buy_talent_2d(id: StringName) -> bool:
	var cost := talent_2d_cost(id)
	var material := talent_2d_material(id)
	var material_cost := talent_2d_material_cost(id)
	if cost < 0 or material_cost < 0:
		return false
	if int(data["resources"]) < cost or material_count(material) < material_cost:
		return false
	var prereq := String(TALENT_2D_PREREQ.get(String(id), ""))
	if prereq != "" and talent_2d_level(StringName(prereq)) < 1:
		return false
	data["resources"] = int(data["resources"]) - cost
	var materials: Dictionary = data["materials_2d"]
	materials[String(material)] = maxi(0, int(materials.get(String(material), 0)) - material_cost)
	data["talents_2d"][String(id)] = talent_2d_level(id) + 1
	data["xp"] = int(data["xp"]) + 5
	data["skill_level"] = 1 + int(data["xp"]) / 20
	return save_data()


## ---- 天赋重置：返还已投入的信用点与基础资源 ----

## 返回节点及其所有（传递）依赖节点。重置前置节点时依赖节点必须一起清空。
func talent_2d_dependents(id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = [id]
	var changed := true
	while changed:
		changed = false
		for key in TALENT_2D_PREREQ:
			var prereq := StringName(TALENT_2D_PREREQ[key])
			if ids.has(prereq) and not ids.has(StringName(key)):
				ids.append(StringName(key))
				changed = true
	return ids


## 单个天赋重置：等级归零并返还投入，返回 {nodes, credits, materials}。
func reset_talent_2d(id: StringName) -> Dictionary:
	var result := {"nodes": [], "credits": 0, "materials": {}}
	if talent_2d_level(id) <= 0:
		return result
	var nodes := talent_2d_dependents(id)
	for node_id in nodes:
		_refund_talent(node_id, result)
	save_data()
	return result


## 全部天赋重置：所有等级归零并按各自投入返还。
func reset_all_talents_2d() -> Dictionary:
	var result := {"nodes": [], "credits": 0, "materials": {}}
	for key in TALENT_2D_MAX:
		_refund_talent(StringName(key), result)
	if not (result["nodes"] as Array).is_empty():
		save_data()
	return result


func _refund_talent(id: StringName, result: Dictionary) -> void:
	var level := talent_2d_level(id)
	if level <= 0:
		return
	# 每级价格 15+15L、材料 3+3L；等差数列求和即总投入。
	var credits_back := credit_cost(15 * level * (level + 1) / 2)
	var material := talent_2d_material(id)
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

func set_loadout(weapon: StringName, ammo: StringName) -> void:
	data["loadout"] = {"weapon": String(weapon), "ammo": String(ammo)}
	save_data()

## 弹药显示偏好：both 图形+数值 / numeric 仅数值 / graphic 仅图形。
func set_ammo_display(mode: String) -> bool:
	if not AMMO_DISPLAY_MODES.has(mode):
		return false
	data["ammo_display"] = mode
	return save_data()


## 射速显示：interval = 秒/发，rpm = 每分钟发数。
func set_fire_rate_display(mode: String) -> bool:
	if not ["interval", "rpm"].has(mode):
		return false
	data["fire_rate_display"] = mode
	return save_data()

## 设置项：音量 0–1、动态模糊开关、摄像机模式 0–2。
func set_volume(value: float) -> bool:
	data["volume"] = clampf(value, 0.0, 1.0)
	return save_data()


func set_sfx_volume(value: float) -> bool:
	data["sfx_volume"] = clampf(value, 0.0, 1.0)
	return save_data()


## 背景音乐 / 环境氛围音量。
func set_music_volume(value: float) -> bool:
	data["music_volume"] = clampf(value, 0.0, 1.0)
	return save_data()


## 屏幕震动：关闭后命中与受击不再抖屏。
func set_screen_shake(enabled: bool) -> bool:
	data["screen_shake"] = enabled
	return save_data()


## 弹道线条：关闭后仅隐藏枪口到弹丸的长曳光线，弹丸实体与飞行/命中判定不变。
func set_bullet_trail_enabled(enabled: bool) -> bool:
	data["bullet_trail_enabled"] = enabled
	return save_data()


## 命中顿帧：默认关闭，由玩家在设置里主动开启。
func set_hitstop_enabled(enabled: bool) -> bool:
	data["hitstop_enabled"] = enabled
	return save_data()


## 开火震动幅度：0%–1000%，100% 为默认手感。
func set_shake_scale(value: float) -> bool:
	data["shake_scale"] = clampf(value, 0.0, 1000.0)
	return save_data()


## 外部命中采样开关：关闭即整套退回程序化命中音效。
func set_sample_impacts(enabled: bool) -> bool:
	data["sample_impacts"] = enabled
	return save_data()


## 命中特写层级：2 完整 / 1 减弱 / 0 关闭。
func set_hit_fx_level(level: int) -> bool:
	data["hit_fx_level"] = clampi(level, 0, 2)
	return save_data()


## 整体视角缩放：20%–200%，按 10% 取整保存，下次行动沿用同一档。
func set_view_zoom(value: float) -> bool:
	data["view_zoom"] = clampf(roundf(value / 10.0) * 10.0, 20.0, 200.0)
	return save_data()


## 2D 携带武器：主 / 副两把；传入同一把枪时自动交换。
func set_loadout_2d(primary: StringName, secondary: StringName) -> bool:
	var first := String(primary)
	var second := String(secondary)
	if not WEAPON_IDS.has(first):
		return false
	if not WEAPON_IDS.has(second):
		second = "g17" if first != "g17" else "m870"
	if first == second:
		return false
	data["loadout_2d"] = [first, second]
	return save_data()


func loadout_2d() -> Array:
	return (data.get("loadout_2d", ["g17", "m870"]) as Array).duplicate()


## 部署：出生点 + 该出生点的默认撤离点。
func set_deployment(spawn_id: StringName, extract_id: StringName) -> bool:
	var spawn_key := String(spawn_id)
	var extract_key := String(extract_id)
	if not SPAWN_IDS.has(spawn_key) or not EXTRACT_IDS.has(extract_key):
		return false
	data["deployment"] = {"spawn": spawn_key, "extract": extract_key}
	return save_data()


func deployment() -> Dictionary:
	return (data.get("deployment", {"spawn": "insertion", "extract": "east"}) as Dictionary).duplicate()


## 行动模式：raid（默认）或 waves（浪潮生存）。
func set_run_mode(mode: String) -> bool:
	data["run_mode"] = mode if ["raid", "waves"].has(mode) else "raid"
	return save_data()


func run_mode() -> String:
	return String(data.get("run_mode", "raid"))


## 浪潮地图：facility（默认设施）或 goliath_arena（歌利亚狂潮）。
func set_map_id(map_id: String) -> bool:
	data["map_id"] = map_id if ["facility", "goliath_arena"].has(map_id) else "facility"
	return save_data()


func map_id() -> String:
	return String(data.get("map_id", "facility"))

func set_motion_blur(enabled: bool) -> bool:
	data["motion_blur"] = enabled
	return save_data()

## 高倍镜镜内运动模糊：移动镜子时镜内画面带拖影。
func scope_motion_blur() -> bool:
	return bool(data.get("scope_motion_blur", true))

func set_scope_motion_blur(enabled: bool) -> bool:
	data["scope_motion_blur"] = enabled
	return save_data()

## 高倍镜镜片畸变：边缘桶形拉伸与轻微色散。
func scope_lens_distortion() -> bool:
	return bool(data.get("scope_lens_distortion", true))

func set_scope_lens_distortion(enabled: bool) -> bool:
	data["scope_lens_distortion"] = enabled
	return save_data()

## 玩家为某个瞄具选择的准星样式；未选择时回退到瞄具默认准星。
func reticle_style(sight_id: String, fallback: String) -> String:
	var styles: Dictionary = data.get("reticle_styles", {})
	return String(styles.get(sight_id, fallback))

func set_reticle_style(sight_id: String, style: String) -> bool:
	var styles: Dictionary = data.get("reticle_styles", {})
	styles[sight_id] = style
	data["reticle_styles"] = styles
	return save_data()

## 调试模式：打开后 debug_mul 才返回倍率，否则一律 1.0。
func debug_enabled() -> bool:
	return bool(data.get("debug_enabled", false))

func set_debug_enabled(enabled: bool) -> bool:
	data["debug_enabled"] = enabled
	return save_data()

func debug_value(key: String) -> float:
	var dbg: Dictionary = data.get("debug", {})
	return clampf(float(dbg.get(key, 1.0)), 0.0, 100.0)

func debug_mul(key: String) -> float:
	if not debug_enabled():
		return 1.0
	return debug_value(key)

func set_debug_value(key: String, value: float) -> void:
	var dbg: Dictionary = data.get("debug", {})
	dbg[key] = clampf(value, 0.0, 100.0)
	data["debug"] = dbg

func reset_debug() -> void:
	data["debug"] = {
		"recoil_v": 1.0, "recoil_h": 1.0, "recoil_cap": 1.0,
		"spread": 1.0, "damage": 1.0, "ads": 1.0, "move": 1.0, "vision": 1.0,
	}

func set_camera_mode(mode: int) -> bool:
	data["camera_mode"] = clampi(mode, 0, 2)
	return save_data()

## 测试用：关闭场景黑暗、迷雾与视野遮罩，方便截图与调色。
func set_bright_test(enabled: bool) -> bool:
	data["bright_test"] = enabled
	return save_data()
