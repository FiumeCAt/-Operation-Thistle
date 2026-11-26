extends SceneTree
## Phase 5B + FPS 帧率显示回归测试：
## 1) 设置开关 `show_fps` + 全局 `FpsOverlay2D` 显隐/刷新/持久化；
## 2) `DebugMenu2D` 三页分页（战斗与视野 / 生存与恢复 / 资源与等级）、生存上限缩放/钳制、
##    绝对值点每秒自动恢复、一键满血满甲、资源与等级直写存档；
## 3) `SaveStore` / `Progress` / `SaveSlotsMenu2D` 进度重置（保留/不保留偏好 + .bak 备份）、
##    清空槽位（二次确认 + .bak 备份）、JSON 导出与导入（v0 迁移 / 损坏与高版本拒绝 / 偏好覆盖开关）。
## godot --headless --path . --script res://tests/phase5b_debug_save_fps_test.gd

const SAVE_STORE := preload("res://scripts/core/progress/SaveStore.gd")
const SAVE_SLOTS_MENU := preload("res://scripts/ui/SaveSlotsMenu2D.gd")
const DOLL_SCENE := preload("res://scenes/actors/Doll2D.tscn")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {}
	return j.data


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	_check(p != null and p.is_isolated_save(), "Progress autoload exists with isolated save")
	if p == null:
		quit(1)
		return
	_check(p.reset_for_test(), "isolated reset succeeds")

	# ==== 1. FPS 帧率显示设置与全局 FpsOverlay2D ====
	_check(p.fps_overlay != null and not p.show_fps() and not p.fps_overlay.visible,
		"FPS overlay defaults to off and hidden")
	var sm := SettingsMenu2D.new()
	root.add_child(sm)
	await process_frame
	sm.open()
	_check(sm._fps_buttons.size() == 2 and sm._fps_buttons[false].text.contains("▶"),
		"SettingsMenu2D exposes FPS toggle defaulting to off")
	sm._set_show_fps(true)
	await process_frame
	_check(p.show_fps() and p.fps_overlay.visible and p.fps_overlay.current_text().begins_with("FPS "),
		"enabling FPS toggle immediately displays FpsOverlay2D with formatted FPS text")
	sm.queue_free()
	await process_frame
	p.load_data()
	_check(p.show_fps() and p.fps_overlay.visible, "FPS toggle persists across reload")
	p.set_show_fps(false)
	_check(not p.show_fps() and not p.fps_overlay.visible, "disabling FPS toggle hides FpsOverlay2D")

	# ==== 2. DebugMenu2D 三页分页 + 生存倍率/恢复 + 资源/等级直写 ====
	var dm := DebugMenu2D.new()
	root.add_child(dm)
	await process_frame
	dm.open()
	_check(dm._sliders.size() == 8 and dm._survival_sliders.size() == 4
		and dm._tab_pages.size() == 3 and dm.current_tab() == "combat",
		"DebugMenu2D has 3 tabs, keeps 8 combat sliders, and adds 4 survival controls")

	dm.switch_tab("survival")
	_check(dm.current_tab() == "survival" and dm._tab_pages["survival"].visible
		and not dm._tab_pages["combat"].visible,
		"DebugMenu2D switches to survival tab cleanly")

	# 挂载一个真实 Doll2D 测试生存上限倍率、比例缩放、绝对值恢复与一键满状态。
	var doll: Doll2D = DOLL_SCENE.instantiate()
	root.add_child(doll)
	await process_frame
	doll.set_base_vitals(100, 100, true)
	_check(doll.hp_max == 100 and doll.hp == 100 and doll.armor_max == 100 and doll.armor == 100,
		"Doll2D base vitals initialize to 100/100")

	dm._survival_sliders["hp_max_mul"].value = 2.0
	dm._survival_sliders["armor_max_mul"].value = 1.5
	_check(p.debug_enabled() and _near(p.debug_mul("hp_max_mul"), 2.0)
		and _near(p.debug_mul("armor_max_mul"), 1.5),
		"survival max multiplier sliders enable debug and persist values")
	_check(doll.hp_max == 200 and doll.hp == 200 and doll.armor_max == 150 and doll.armor == 150,
		"live Doll2D immediately scales max and current HP/armor when multipliers increase")

	# 受伤后降倍率：等比缩放/钳制且绝不误杀存活角色。
	doll.hp = 100
	doll.armor = 75
	dm._survival_sliders["hp_max_mul"].value = 0.5
	_check(doll.hp_max == 50 and doll.hp == 25,
		"lowering hp_max_mul scales and clamps current HP proportionally without killing player")
	dm._survival_sliders["hp_max_mul"].value = 1.0
	dm._survival_sliders["armor_max_mul"].value = 1.0
	_check(doll.hp_max == 100 and doll.hp == 50 and doll.armor_max == 100 and doll.armor == 50,
		"restoring 1.0x multipliers restores base limits while preserving ratio")

	# 绝对值自动恢复（点/秒）带小数累加，阵亡后不自动复活。
	dm._survival_sliders["hp_regen"].value = 10.0
	dm._survival_sliders["armor_regen"].value = 20.0
	_check(_near(p.debug_flat("hp_regen"), 10.0) and _near(p.debug_flat("armor_regen"), 20.0),
		"debug_flat returns absolute points/sec when debug enabled")
	for _i in 4:
		doll.step_debug_vitals(0.25, p)
	_check(doll.hp == 60 and doll.armor == 70,
		"fractional regen accumulator heals exact +10 HP and +20 armor over 1.0s")

	# 关闭调试后恢复与倍率全部回归默认（1.0x / 0 点/秒）。
	dm._set_enabled(false)
	_check(_near(p.debug_flat("hp_regen"), 0.0) and _near(p.debug_mul("hp_max_mul"), 1.0),
		"disabling debug returns flat regen to 0 and multipliers to 1.0")
	var hp_before_off := doll.hp
	doll.step_debug_vitals(1.0, p)
	_check(doll.hp == hp_before_off, "disabled debug does not regenerate HP")

	# 阵亡角色不被自动恢复复活；一键满血满甲对存活角色有效。
	dm._set_enabled(true)
	doll.hp = 0
	doll.step_debug_vitals(1.0, p)
	_check(doll.hp == 0, "dead player does not auto-revive from debug regen")
	doll.hp = 12
	doll.armor = 5
	_check(dm.full_restore_player() and doll.hp == doll.hp_max and doll.armor == doll.armor_max,
		"one-click full restore fills both HP and armor to current max")

	doll.queue_free()
	await process_frame

	# 第 3 页：资源与等级直写当前存档（不乘经济倍率）。
	dm.switch_tab("resources")
	_check(dm.current_tab() == "resources" and dm._tab_pages["resources"].visible,
		"DebugMenu2D switches to resources tab")
	dm._adjust_credits(1000)
	dm._adjust_level(4)  # Lv.1 -> Lv.5
	dm._adjust_material(&"electronics", 25)
	dm._adjust_material(&"military_alloy", 7)
	_check(p.credits() == 1000 and int(p.data["skill_level"]) == 5
		and int(p.data["xp"]) == p.xp_for_level(5)
		and p.material_count(&"electronics") == 25 and p.advanced_count(&"military_alloy") == 7,
		"resources tab directly mutates credits (raw), level/XP, basic and advanced materials")
	dm._grant_all_materials(10)
	_check(p.material_count(&"electronics") == 35 and p.material_count(&"parts") == 10
		and p.advanced_count(&"weapon_parts") == 10 and p.advanced_count(&"military_alloy") == 17,
		"grant_all_materials increments all 3 basic and 4 advanced materials")
	dm._reset_values()
	_check(p.credits() == 1000 and int(p.data["skill_level"]) == 5
		and _near(p.debug_value("hp_regen"), 0.0) and _near(p.debug_value("hp_max_mul"), 1.0),
		"resetting debug multipliers/regen preserves player save resources and level")
	dm.queue_free()
	await process_frame

	# ==== 3. 存档重置、清空槽位（二次确认 + .bak）与 JSON 导入导出 ====
	var export_path := "user://test_phase5b_export.json"
	var bad_json_path := "user://test_phase5b_bad.json"
	var future_ver_path := "user://test_phase5b_future.json"
	var v0_path := "user://test_phase5b_v0.json"
	_remove_if_exists(export_path)
	_remove_if_exists(bad_json_path)
	_remove_if_exists(future_ver_path)
	_remove_if_exists(v0_path)

	p.set_credits(999)
	p.set_xp(120)
	p.data["talents_2d"]["hp"] = 3
	p.set_volume(0.35)
	p.set_ui_theme("cyan")
	p.set_show_fps(true)
	p.save_data()
	_check(p.save_to_slot(3), "save to slot 3 succeeds")

	var slots_ui = SAVE_SLOTS_MENU.new()
	root.add_child(slots_ui)
	await process_frame
	slots_ui.open()

	# 3a) 导出 JSON 存档并校验格式与版本标记。
	_check(slots_ui.export_to_path(export_path) and FileAccess.file_exists(export_path),
		"SaveSlotsMenu2D exports save to JSON file")
	var exported := _read_json_dict(export_path)
	_check(String(exported.get("format", "")) == SAVE_STORE.EXPORT_FORMAT
		and int(exported.get("export_version", 0)) == SAVE_STORE.EXPORT_VERSION
		and int(exported.get("version", 0)) == SAVE_STORE.VERSION
		and int((exported.get("data", {}) as Dictionary).get("resources", 0)) == 999,
		"exported JSON includes format tag, export_version, save version, and full data")

	# 3b) 清空指定槽位：需二次确认，取消保留，确认后清空并生成 .bak。
	slots_ui.request_clear_slot(3)
	_check(slots_ui.is_confirm_open(), "clear slot opens two-step confirmation")
	slots_ui.cancel_pending_action()
	_check(not slots_ui.is_confirm_open() and not bool(p.slot_info(3).get("empty", true)),
		"canceling clear confirmation keeps slot 3 intact")
	slots_ui.request_clear_slot(3)
	_check(slots_ui.confirm_pending_action() and bool(p.slot_info(3).get("empty", false)),
		"confirming clear removes slot 3")
	_check(FileAccess.file_exists(p.slot_path(3) + ".bak"),
		"clearing slot 3 creates a .bak backup first")

	# 3c) 重置当前进度（默认保留本地偏好设置），且旧主存档先滚入 .bak。
	slots_ui.set_keep_settings_on_reset(true)
	slots_ui.request_reset_progress()
	_check(slots_ui.is_confirm_open(), "reset progress opens two-step confirmation")
	_check(slots_ui.confirm_pending_action(), "confirming reset progress succeeds")
	var bak_after_reset := _read_json_dict(String(p.save_path) + ".bak")
	_check(int(bak_after_reset.get("resources", -1)) == 999,
		"reset rolls previous main save (999 credits) into .bak")
	_check(p.credits() == 0 and int(p.data["xp"]) == 0 and int(p.data["skill_level"]) == 1
		and int(p.data["talents_2d"]["hp"]) == 0,
		"reset clears credits, XP, level, and talents")
	_check(_near(float(p.data["volume"]), 0.35) and p.ui_theme() == "cyan" and p.show_fps(),
		"reset with keep_settings=true preserves volume, UI theme, and show_fps")

	# 3d) 重置当前进度（不保留设置）：连同偏好设置一并恢复默认。
	p.set_credits(250)
	slots_ui.set_keep_settings_on_reset(false)
	slots_ui.request_reset_progress()
	_check(slots_ui.confirm_pending_action() and p.credits() == 0
		and _near(float(p.data["volume"]), 0.8) and p.ui_theme() == "amber" and not p.show_fps(),
		"reset with keep_settings=false restores default volume, theme, and show_fps")

	# 3e) 非法/损坏/未来高版本 JSON 导入：强制拒绝，绝不覆盖现存档。
	p.set_credits(77)
	p.set_volume(0.60)
	p.set_ui_theme("terminal")
	_write_text(bad_json_path, "{ broken json !!!")
	_write_text(future_ver_path, JSON.stringify({"version": 99, "resources": 88888}))
	_check(not slots_ui.request_import_from_path(bad_json_path) and not slots_ui.is_confirm_open()
		and p.credits() == 77,
		"corrupt JSON import is rejected without touching current save")
	_check(not slots_ui.request_import_from_path(future_ver_path) and not slots_ui.is_confirm_open()
		and p.credits() == 77,
		"unsupported future version import is rejected without touching current save")

	# 3f) 有效导出文件导入（不覆盖本地偏好设置）：恢复进度但保留本地 terminal 主题与 0.60 音量，且旧档入 .bak。
	slots_ui.set_overwrite_settings_on_import(false)
	_check(slots_ui.request_import_from_path(export_path) and slots_ui.is_confirm_open(),
		"valid JSON import passes preflight validation and opens confirmation")
	_check(slots_ui.confirm_pending_action(), "confirming JSON import succeeds")
	_check(p.credits() == 999 and int(p.data["xp"]) == 120 and int(p.data["talents_2d"]["hp"]) == 3,
		"import restores exported progress (credits, XP, talents)")
	_check(_near(float(p.data["volume"]), 0.60) and p.ui_theme() == "terminal" and not p.show_fps(),
		"import with overwrite_settings=false preserves local volume, theme, and show_fps")
	var bak_after_import := _read_json_dict(String(p.save_path) + ".bak")
	_check(int(bak_after_import.get("resources", -1)) == 77,
		"import backs up pre-import save (77 credits) into .bak")

	# 3g) 有效导出文件导入（覆盖本地偏好设置）：同步套用导出档中的 cyan 主题 / 0.35 音量 / show_fps=true。
	slots_ui.set_overwrite_settings_on_import(true)
	_check(slots_ui.request_import_from_path(export_path) and slots_ui.confirm_pending_action(),
		"import with overwrite_settings=true succeeds")
	_check(_near(float(p.data["volume"]), 0.35) and p.ui_theme() == "cyan" and p.show_fps(),
		"import with overwrite_settings=true adopts exported preferences")

	# 3h) v0 旧版本 JSON 导入：自动经 migrate_save_version -> is_valid_save -> normalize_data 升级导入。
	_write_text(v0_path, JSON.stringify({"version": 0, "resources": 512, "xp": 60}))
	slots_ui.set_overwrite_settings_on_import(false)
	_check(slots_ui.request_import_from_path(v0_path) and slots_ui.confirm_pending_action(),
		"legacy v0 save imports cleanly via version migration pipeline")
	_check(p.credits() == 512 and int(p.data["skill_level"]) == p.level_for_xp(60)
		and int(p.data["version"]) == SAVE_STORE.VERSION,
		"migrated v0 import normalizes level and current save version")

	slots_ui.queue_free()
	await process_frame

	# 清理临时导出/测试文件与测试偏好。
	p.set_show_fps(false)
	_remove_if_exists(export_path)
	_remove_if_exists(bad_json_path)
	_remove_if_exists(future_ver_path)
	_remove_if_exists(v0_path)

	print("\n=== phase5b debug save fps: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
