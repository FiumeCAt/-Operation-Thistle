extends SceneTree
## 存档槽位回归：5 个槽位的存/读、摘要、主菜单入口、退出自动存档。
## godot --headless --path . --script res://tests/save_slots_2d_test.gd

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


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	_check(p != null, "Progress autoload exists")
	if p == null:
		quit(1)
		return
	_check(p.reset_for_test(), "isolated reset is allowed")
	_check(String(p.slot_path(1)).contains("slot1"), "slot paths use numbered files")
	_check(p.SLOT_COUNT == 5, "five slots are available")

	# 1) 存档到槽位并生成摘要。
	p.data["resources"] = 120
	p.data["xp"] = 40
	p.data["talents_2d"]["hp"] = 2
	p.data["materials_2d"]["electronics"] = 7
	_check(p.save_to_slot(1), "save to slot 1 succeeds")
	var info1: Dictionary = p.slot_info(1)
	_check(not bool(info1.get("empty", true)), "slot 1 is no longer empty")
	var summary1: Dictionary = info1.get("summary", {})
	_check(int(summary1.get("credits", 0)) == 120, "slot 1 summary keeps credits")
	_check(int(summary1.get("xp", 0)) == 40, "slot 1 summary keeps xp")
	_check(int(summary1.get("talents", 0)) == 2, "slot 1 summary counts talents")
	_check(int(summary1.get("materials", 0)) == 7, "slot 1 summary counts materials")
	_check(bool(info1.get("active", false)), "slot 1 becomes the active slot")

	# 2) 第二个槽位互不覆盖。
	p.data["resources"] = 300
	p.data["xp"] = 80
	_check(p.save_to_slot(2), "save to slot 2 succeeds")
	_check(int(p.slot_info(1).get("summary", {}).get("credits", 0)) == 120,
		"slot 1 snapshot is not modified by slot 2")
	_check(int(p.slot_info(3).get("empty", false)) == 1, "slot 3 is empty")

	# 3) 读档覆盖当前进度。
	_check(p.load_from_slot(1), "load from slot 1 succeeds")
	_check(int(p.data["resources"]) == 120 and int(p.data["xp"]) == 40,
		"loading restores credits and xp")
	_check(p.active_slot() == 1, "loaded slot becomes active")
	_check(int(p.data["talents_2d"]["hp"]) == 2, "loading restores talents")

	# 4) 主菜单存档入口与读档刷新。
	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.saves_button != null and menu.saves_button.text.contains("存档"),
		"start menu exposes the save slot entry")
	menu._open_saves()
	_check(menu.save_slots.visible, "save slot menu opens")
	_check(menu.save_slots._rows.size() == 5, "save slot menu lists five slots")
	menu.save_slots._load_slot(2)
	_check(int(p.data["resources"]) == 300, "menu load switches to slot 2")
	_check(menu._stats["credits"].text == "300", "dossier refreshes after loading")
	menu.save_slots.close_menu()
	_check(not menu.save_slots.visible, "save slot menu closes")
	menu.queue_free()
	await process_frame

	# 5) 退出游戏自动存档写回当前槽位（槽位 2）。
	p.data["resources"] = 777
	p.autosave_on_exit()
	_check(int(p.slot_info(2).get("summary", {}).get("credits", 0)) == 777,
		"exit autosave writes the active slot")
	_check(int(p.slot_info(1).get("summary", {}).get("credits", 0)) == 120,
		"exit autosave leaves other slots untouched")
	_check(int(p.data["resources"]) == 777, "exit autosave keeps memory data")

	print("\n=== save slots 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
