extends SceneTree
## 存档系统回归：测试隔离、备份轮换、损坏回退、无备份保护、无变化跳过写入。
## godot --headless --path . --script res://tests/save_system_test.gd

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


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _read_int(path: String, key: String) -> int:
	var json := JSON.new()
	if json.parse(_read_text(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return -99999
	return int(json.data.get(key, -99999))


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	_check(p != null, "Progress autoload exists")
	if p == null:
		quit(1)
		return
	var main_path: String = String(p.save_path)
	var bak_path := main_path + ".bak"
	var bak2_path := main_path + ".bak2"
	var corrupt_path := main_path + ".corrupt.json"

	# 1) 测试脚本必须自动隔离到独立存档。
	_check(p.is_isolated_save(), "test run uses an isolated save path")
	_check(main_path.contains("save_system"), "save path is named after the test")
	var isolated_path: String = p.save_path
	p.save_path = p.DEFAULT_PATH
	_check(not p.is_isolated_save(), "production path is treated as non-isolated")
	p.save_path = isolated_path
	_check(p.reset_for_test(), "isolated reset is allowed")
	_check(not FileAccess.file_exists(main_path + ".tmp"), "no temp file left behind")

	# 2) 连续保存形成 .bak / .bak2 备份环。
	p.data["resources"] = 100
	_check(p.save_data(), "first save succeeds")
	p.data["resources"] = 200
	_check(p.save_data(), "second save succeeds")
	_check(FileAccess.file_exists(bak_path), "first save rolls into .bak")
	_check(_read_int(bak_path, "resources") == 100, ".bak keeps the previous save")
	p.data["resources"] = 300
	_check(p.save_data(), "third save succeeds")
	_check(_read_int(bak_path, "resources") == 200, ".bak keeps the latest previous save")
	_check(_read_int(bak2_path, "resources") == 100, ".bak2 keeps the older save")

	# 3) 主存档损坏 → 自动从最新备份恢复，并保留损坏快照。
	_write_text(main_path, "{ this is not valid json")
	_check(p.load_data(), "corrupt main falls back to a backup")
	_check(int(p.data["resources"]) == 200, "recovery uses the newest valid backup (200)")
	_check(_read_int(main_path, "resources") == 200, "main save is rebuilt after recovery")
	_check(FileAccess.file_exists(corrupt_path), "corrupt snapshot is preserved")
	_check(_read_text(corrupt_path).contains("not valid json"), "snapshot keeps the broken file")

	# 4) 没有可用备份时加载默认数据，且不覆盖原文件。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bak2_path))
	_write_text(main_path, "broken again")
	_check(not p.load_data(), "load reports failure when no backup exists")
	_check(int(p.data["resources"]) == 0, "defaults are used without a backup")
	_check(_read_text(main_path) == "broken again", "broken main is left untouched")

	# 5) 数据没变时不重复写入，也不推动备份轮换。
	_check(p.reset_for_test(), "reset after corruption is allowed")
	p.data["resources"] = 1
	_check(p.save_data(), "save before rotation test")
	p.data["resources"] = 2
	_check(p.save_data(), "save creates a rotation candidate")
	var bak_before := _read_text(bak_path)
	_check(p.save_data(), "unchanged save still reports success")
	_check(_read_text(bak_path) == bak_before, "unchanged save does not rotate backups")
	p.data["resources"] = 3
	_check(p.save_data(), "changed save writes again")
	_check(_read_int(main_path, "resources") == 3, "main save reflects the new value")
	_check(_read_int(bak_path, "resources") == 2, "backup tracks the last written value")

	print("\n=== save system: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
