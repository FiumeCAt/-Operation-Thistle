extends Node
class_name ProgressService
## 全局存档与进度协调外壳（Autoload `/root/Progress`）：
## 对外保留全部既有字段、常量与公开 API 契约（含旧存档键名 100% 兼容），
## 内部职责分别委托给 SaveStore / SettingsStore / MetaProgress / LoadoutStore / TalentStore。

signal ui_theme_changed(theme_id: String, accent: Color)

const SAVE_STORE := preload("res://scripts/core/progress/SaveStore.gd")
const SETTINGS_STORE := preload("res://scripts/core/progress/SettingsStore.gd")
const META_STORE := preload("res://scripts/core/progress/MetaProgress.gd")
const LOADOUT_STORE := preload("res://scripts/core/progress/LoadoutStore.gd")
const TALENT_STORE := preload("res://scripts/core/progress/TalentStore.gd")

const VERSION := SAVE_STORE.VERSION
const DEFAULT_PATH := SAVE_STORE.DEFAULT_PATH
const SLOT_COUNT := SAVE_STORE.SLOT_COUNT
const AMMO_DISPLAY_MODES := SAVE_STORE.AMMO_DISPLAY_MODES
const WEAPON_IDS := SAVE_STORE.WEAPON_IDS
const SPAWN_IDS := SAVE_STORE.SPAWN_IDS
const EXTRACT_IDS := SAVE_STORE.EXTRACT_IDS
const DEFAULT_LASER_COLOR := SAVE_STORE.DEFAULT_LASER_COLOR
const DEFAULT_RETICLE_COLOR := SAVE_STORE.DEFAULT_RETICLE_COLOR

## 以下数值默认值会被 data/progression.json 覆盖（_ready 时加载），保留默认值以便缺表仍可启动。
var UPGRADE_MAX := {"hp": 5, "support": 2, "gun": 3, "fov": 4, "sight": 4}
var CREDIT_COST_MUL := 3.0
var CREDIT_GAIN_MUL := 0.5
var TALENT_2D_MAX := {
	"hp": 5, "gun": 5, "move": 5, "reload": 5, "scavenge": 5, "loading": 1,
	"armor": 5, "magazine": 5, "reserve": 5, "magnet": 5, "hearing": 5,
}
var TALENT_2D_PREREQ := {
	"move": "hp", "hearing": "hp", "reload": "gun", "magazine": "reload",
	"loading": "magazine", "reserve": "magazine",
	"armor": "move", "magnet": "scavenge",
}
var TALENT_2D_MATERIAL := {
	"hp": "energy", "move": "energy", "hearing": "energy",
	"gun": "electronics", "reload": "electronics", "magazine": "electronics",
	"scavenge": "parts", "loading": "parts", "armor": "parts",
	"reserve": "parts", "magnet": "electronics",
}

var save_path := DEFAULT_PATH
var data: Dictionary = {}
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


func _exit_tree() -> void:
	autosave_on_exit()


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


func is_isolated_save() -> bool:
	return save_path != DEFAULT_PATH


func _remove_save() -> void:
	SAVE_STORE.remove_save_family(save_path)


func _save_family_paths() -> Array[String]:
	return SAVE_STORE.save_family_paths(save_path)


func _defaults() -> Dictionary:
	return SAVE_STORE.defaults()


func _normalize_data() -> bool:
	return SAVE_STORE.normalize_data(data, UPGRADE_MAX, TALENT_2D_MAX)


## ---- 主存档与手动槽位（SaveStore）----

func load_data() -> bool:
	_last_saved_text = ""
	var res := SAVE_STORE.load_main(save_path, UPGRADE_MAX, TALENT_2D_MAX)
	data = res["data"]
	var loaded := bool(res["loaded"])
	var source := String(res["source"])
	if loaded and source != save_path:
		SAVE_STORE.quarantine_corrupt_main(save_path)
		_last_saved_text = ""
		if save_data():
			push_warning("存档已从备份恢复：%s -> %s" % [source, save_path])
	elif bool(res["migrated"]):
		save_data()
	_sync_ui_theme()
	return loaded


func save_data() -> bool:
	var res := SAVE_STORE.write_main(save_path, data, _last_saved_text)
	if bool(res["ok"]):
		_last_saved_text = String(res["text"])
		return true
	return false


func reset_for_test() -> bool:
	if not is_isolated_save():
		push_error("reset_for_test 拒绝写入正式存档：%s" % save_path)
		return false
	data = SAVE_STORE.defaults()
	_last_saved_text = ""
	_sync_ui_theme()
	return save_data()


func slot_path(slot: int) -> String:
	return SAVE_STORE.slot_path(save_path, slot)


func active_slot() -> int:
	return clampi(int(data.get("active_slot", 1)), 1, SLOT_COUNT)


func slot_info(slot: int) -> Dictionary:
	return SAVE_STORE.slot_info(save_path, slot, active_slot())


func save_to_slot(slot: int) -> bool:
	var index := clampi(slot, 1, SLOT_COUNT)
	data["active_slot"] = index
	if not save_data():
		return false
	return SAVE_STORE.write_slot_payload(save_path, index, SAVE_STORE.build_slot_payload(data))


func load_from_slot(slot: int) -> bool:
	var index := clampi(slot, 1, SLOT_COUNT)
	var payload := SAVE_STORE.read_slot_payload(save_path, index)
	if payload.is_empty():
		return false
	var slot_data: Dictionary = payload["data"]
	data = SAVE_STORE.defaults()
	for key in data:
		if slot_data.has(key):
			data[key] = slot_data[key]
	SAVE_STORE.normalize_data(data, UPGRADE_MAX, TALENT_2D_MAX)
	data["active_slot"] = index
	_last_saved_text = ""
	_sync_ui_theme()
	return save_data()


func autosave_on_exit() -> void:
	if data.is_empty() or not save_data():
		return
	var index := active_slot()
	if not SAVE_STORE.write_slot_payload(save_path, index, SAVE_STORE.build_slot_payload(data)):
		push_warning("退出自动存档写入槽位失败：%d" % index)


## ---- 资源 / 元进度 / 部署（MetaProgress）----

func add_resources(amount: int) -> void:
	if META_STORE.add_resources(data, amount, CREDIT_GAIN_MUL):
		save_data()

func credit_cost(base: int) -> int:
	return META_STORE.credit_cost(base, CREDIT_COST_MUL)

func credit_gain(base: int) -> int:
	return META_STORE.credit_gain(base, CREDIT_GAIN_MUL)

func credits() -> int:
	return META_STORE.credits(data)

func material_count(id: StringName) -> int:
	return META_STORE.material_count(data, id)

func advanced_count(id: StringName) -> int:
	return META_STORE.advanced_count(data, id)

func add_materials(counts: Dictionary) -> void:
	META_STORE.add_materials(data, counts)
	save_data()

func add_xp(amount: int) -> bool:
	META_STORE.add_xp(data, amount)
	return save_data()

func set_deployment(spawn_id: StringName, extract_id: StringName) -> bool:
	return save_data() if META_STORE.set_deployment(data, spawn_id, extract_id) else false

func deployment() -> Dictionary:
	return META_STORE.deployment(data)

func set_run_mode(mode: String) -> bool:
	META_STORE.set_run_mode(data, mode)
	return save_data()

func run_mode() -> String:
	return META_STORE.run_mode(data)

func set_map_id(map_id: String) -> bool:
	META_STORE.set_map_id(data, map_id)
	return save_data()

func map_id() -> String:
	return META_STORE.map_id(data)


## ---- 携行配装与配件（LoadoutStore）----

func weapon_mods_2d(weapon_id: StringName) -> Dictionary:
	return LOADOUT_STORE.weapon_mods_2d(data, weapon_id)

func armor_mods_2d() -> Dictionary:
	return LOADOUT_STORE.armor_mods_2d(data)

func install_weapon_mod(weapon_id: StringName, slot: StringName, option_id: StringName) -> bool:
	var res := LOADOUT_STORE.install_weapon_mod(data, weapon_id, slot, option_id)
	if not bool(res["ok"]):
		return false
	return save_data() if bool(res["changed"]) else true

func install_armor_mod(slot: StringName, option_id: StringName) -> bool:
	var res := LOADOUT_STORE.install_armor_mod(data, slot, option_id)
	if not bool(res["ok"]):
		return false
	return save_data() if bool(res["changed"]) else true

func set_loadout(weapon: StringName, ammo: StringName) -> void:
	LOADOUT_STORE.set_loadout(data, weapon, ammo)
	save_data()

func set_loadout_2d(primary: StringName, secondary: StringName) -> bool:
	return save_data() if LOADOUT_STORE.set_loadout_2d(data, primary, secondary) else false

func loadout_2d() -> Array:
	return LOADOUT_STORE.loadout_2d(data)


## ---- 强化与 2D 天赋树（TalentStore）----

func upgrade_level(id: StringName) -> int:
	return TALENT_STORE.upgrade_level(data, id)

func upgrade_max(id: StringName) -> int:
	return TALENT_STORE.upgrade_max(UPGRADE_MAX, id)

func upgrade_cost(id: StringName) -> int:
	return TALENT_STORE.upgrade_cost(data, UPGRADE_MAX, CREDIT_COST_MUL, id)

func buy_upgrade(id: StringName) -> bool:
	return save_data() if TALENT_STORE.buy_upgrade(data, UPGRADE_MAX, CREDIT_COST_MUL, id) else false

func talent_2d_level(id: StringName) -> int:
	return TALENT_STORE.talent_2d_level(data, id)

func talent_2d_max(id: StringName) -> int:
	return TALENT_STORE.talent_2d_max(TALENT_2D_MAX, id)

func talent_2d_cost(id: StringName) -> int:
	return TALENT_STORE.talent_2d_cost(data, TALENT_2D_MAX, CREDIT_COST_MUL, id)

func talent_2d_material(id: StringName) -> StringName:
	return TALENT_STORE.talent_2d_material(TALENT_2D_MATERIAL, id)

func talent_2d_material_cost(id: StringName) -> int:
	return TALENT_STORE.talent_2d_material_cost(data, TALENT_2D_MAX, TALENT_2D_MATERIAL, id)

func buy_talent_2d(id: StringName) -> bool:
	var ok := TALENT_STORE.buy_talent_2d(
		data, TALENT_2D_MAX, TALENT_2D_PREREQ, TALENT_2D_MATERIAL, CREDIT_COST_MUL, id)
	return save_data() if ok else false

func talent_2d_dependents(id: StringName) -> Array[StringName]:
	return TALENT_STORE.talent_2d_dependents(TALENT_2D_PREREQ, id)

func reset_talent_2d(id: StringName) -> Dictionary:
	var result := TALENT_STORE.reset_talent_2d(
		data, TALENT_2D_PREREQ, TALENT_2D_MATERIAL, CREDIT_COST_MUL, id)
	if not (result["nodes"] as Array).is_empty():
		save_data()
	return result

func reset_all_talents_2d() -> Dictionary:
	var result := TALENT_STORE.reset_all_talents_2d(
		data, TALENT_2D_MAX, TALENT_2D_MATERIAL, CREDIT_COST_MUL)
	if not (result["nodes"] as Array).is_empty():
		save_data()
	return result


## ---- 设置 / 瞄具外观 / 调试参数（SettingsStore）----

func laser_color() -> Color:
	return SETTINGS_STORE.laser_color(data)

func reticle_color() -> Color:
	return SETTINGS_STORE.reticle_color(data)

func set_laser_color(color: Color) -> void:
	SETTINGS_STORE.set_laser_color(data, color)
	save_data()

func set_reticle_color(color: Color) -> void:
	SETTINGS_STORE.set_reticle_color(data, color)
	save_data()

func ui_theme() -> String:
	return SETTINGS_STORE.ui_theme(data)

func ui_theme_color() -> Color:
	return SETTINGS_STORE.ui_theme_color(data)

func set_ui_theme(theme_id: String) -> bool:
	if not SETTINGS_STORE.set_ui_theme(data, theme_id):
		return false
	_sync_ui_theme()
	ui_theme_changed.emit(ui_theme(), PixelUI.theme_accent())
	return save_data()

func set_ui_theme_color(color: Color) -> bool:
	SETTINGS_STORE.set_ui_theme_color(data, color)
	SETTINGS_STORE.set_ui_theme(data, "custom")
	_sync_ui_theme()
	ui_theme_changed.emit(ui_theme(), PixelUI.theme_accent())
	return save_data()

func _sync_ui_theme() -> void:
	PixelUI.set_theme_palette(ui_theme(), ui_theme_color())
	PixelUI.set_typewriter_config(typewriter_enabled(), typewriter_speed())

func ammo_display() -> String:
	return SETTINGS_STORE.ammo_display(data)


func set_ammo_display(mode: String) -> bool:
	return save_data() if SETTINGS_STORE.set_ammo_display(data, mode) else false

func set_fire_rate_display(mode: String) -> bool:
	return save_data() if SETTINGS_STORE.set_fire_rate_display(data, mode) else false

func armor_display() -> String:
	return SETTINGS_STORE.armor_display(data)

func set_armor_display(mode: String) -> bool:
	return save_data() if SETTINGS_STORE.set_armor_display(data, mode) else false

func set_volume(value: float) -> bool:
	SETTINGS_STORE.set_volume(data, value)
	return save_data()

func set_sfx_volume(value: float) -> bool:
	SETTINGS_STORE.set_sfx_volume(data, value)
	return save_data()

func set_music_volume(value: float) -> bool:
	SETTINGS_STORE.set_music_volume(data, value)
	return save_data()

func set_screen_shake(enabled: bool) -> bool:
	SETTINGS_STORE.set_screen_shake(data, enabled)
	return save_data()

func set_bullet_trail_enabled(enabled: bool) -> bool:
	SETTINGS_STORE.set_bullet_trail_enabled(data, enabled)
	return save_data()

func set_hitstop_enabled(enabled: bool) -> bool:
	SETTINGS_STORE.set_hitstop_enabled(data, enabled)
	return save_data()

func set_shake_scale(value: float) -> bool:
	SETTINGS_STORE.set_shake_scale(data, value)
	return save_data()

func set_sample_impacts(enabled: bool) -> bool:
	SETTINGS_STORE.set_sample_impacts(data, enabled)
	return save_data()

func set_hit_fx_level(level: int) -> bool:
	SETTINGS_STORE.set_hit_fx_level(data, level)
	return save_data()

func muzzle_flash_mode() -> String:
	return SETTINGS_STORE.muzzle_flash_mode(data)

func set_muzzle_flash_mode(mode: String) -> bool:
	return save_data() if SETTINGS_STORE.set_muzzle_flash_mode(data, mode) else false

func set_view_zoom(value: float) -> bool:
	SETTINGS_STORE.set_view_zoom(data, value)
	return save_data()

func minimap_shape() -> String:
	return SETTINGS_STORE.minimap_shape(data)

func set_minimap_shape(shape: String) -> bool:
	return save_data() if SETTINGS_STORE.set_minimap_shape(data, shape) else false

func minimap_scale() -> float:
	return SETTINGS_STORE.minimap_scale(data)

func set_minimap_scale(value: float) -> bool:
	SETTINGS_STORE.set_minimap_scale(data, value)
	return save_data()

func minimap_zoom_min() -> float:
	return SETTINGS_STORE.minimap_zoom_min(data)

func set_minimap_zoom_min(value: float) -> bool:
	SETTINGS_STORE.set_minimap_zoom_min(data, value)
	return save_data()

func minimap_zoom_max() -> float:
	return SETTINGS_STORE.minimap_zoom_max(data)

func set_minimap_zoom_max(value: float) -> bool:
	SETTINGS_STORE.set_minimap_zoom_max(data, value)
	return save_data()

func minimap_zoom() -> float:
	return SETTINGS_STORE.minimap_zoom(data)

func set_minimap_zoom(value: float) -> bool:
	SETTINGS_STORE.set_minimap_zoom(data, value)
	return save_data()

func typewriter_enabled() -> bool:
	return SETTINGS_STORE.typewriter_enabled(data)

func set_typewriter_enabled(enabled: bool) -> bool:
	SETTINGS_STORE.set_typewriter_enabled(data, enabled)
	PixelUI.set_typewriter_config(typewriter_enabled(), typewriter_speed())
	return save_data()

func typewriter_speed() -> float:
	return SETTINGS_STORE.typewriter_speed(data)

func set_typewriter_speed(speed: float) -> bool:
	SETTINGS_STORE.set_typewriter_speed(data, speed)
	PixelUI.set_typewriter_config(typewriter_enabled(), typewriter_speed())
	return save_data()

func ammo_exact_rounds() -> bool:
	return SETTINGS_STORE.ammo_exact_rounds(data)

func set_ammo_exact_rounds(enabled: bool) -> bool:
	SETTINGS_STORE.set_ammo_exact_rounds(data, enabled)
	return save_data()

func pickup_merge_window() -> float:
	return SETTINGS_STORE.pickup_merge_window(data)

func set_pickup_merge_window(seconds: float) -> bool:
	SETTINGS_STORE.set_pickup_merge_window(data, seconds)
	return save_data()

func set_motion_blur(enabled: bool) -> bool:
	SETTINGS_STORE.set_motion_blur(data, enabled)
	return save_data()

func scope_motion_blur() -> bool:
	return SETTINGS_STORE.scope_motion_blur(data)

func set_scope_motion_blur(enabled: bool) -> bool:
	SETTINGS_STORE.set_scope_motion_blur(data, enabled)
	return save_data()

func scope_lens_distortion() -> bool:
	return SETTINGS_STORE.scope_lens_distortion(data)

func set_scope_lens_distortion(enabled: bool) -> bool:
	SETTINGS_STORE.set_scope_lens_distortion(data, enabled)
	return save_data()

func reticle_style(sight_id: String, fallback: String) -> String:
	return SETTINGS_STORE.reticle_style(data, sight_id, fallback)

func set_reticle_style(sight_id: String, style: String) -> bool:
	SETTINGS_STORE.set_reticle_style(data, sight_id, style)
	return save_data()

func debug_enabled() -> bool:
	return SETTINGS_STORE.debug_enabled(data)

func set_debug_enabled(enabled: bool) -> bool:
	SETTINGS_STORE.set_debug_enabled(data, enabled)
	return save_data()

func debug_value(key: String) -> float:
	return SETTINGS_STORE.debug_value(data, key)

func debug_mul(key: String) -> float:
	return SETTINGS_STORE.debug_mul(data, key)

func set_debug_value(key: String, value: float) -> void:
	SETTINGS_STORE.set_debug_value(data, key, value)

func reset_debug() -> void:
	SETTINGS_STORE.reset_debug(data)

func set_camera_mode(mode: int) -> bool:
	SETTINGS_STORE.set_camera_mode(data, mode)
	return save_data()

func set_bright_test(enabled: bool) -> bool:
	SETTINGS_STORE.set_bright_test(data, enabled)
	return save_data()
