extends SceneTree
## 跨进程存档验证。必须在两个独立进程中分别运行：
##   godot --headless --path . --script res://tests/save_persistence_test.gd -- --phase write --save-path user://save_persist.json
##   godot --headless --path . --script res://tests/save_persistence_test.gd -- --phase verify --save-path user://save_persist.json
## write 跑两次用于验证 Windows 覆盖已有存档；verify 必须在全新进程中读取上一次写入的结果。

var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("[FAIL] " + label)

func _arg(name: String, fallback := "") -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return fallback

func _run() -> void:
	var phase := _arg("--phase", "verify")
	var progress := root.get_node_or_null("Progress")
	_check(progress != null, "Progress autoload 存在")
	if progress == null:
		quit(1)
		return
	await process_frame
	match phase:
		"write":
			_write(progress)
		"verify":
			_verify(progress)
		_:
			_check(false, "未知阶段：%s" % phase)
	print("=== SAVE %s: phase=%s path=%s (%d checks, %d failures) ===" % [
		"PASS" if _fails == 0 else "FAILED", phase, progress.save_path, _checks, _fails])
	quit(0 if _fails == 0 else 1)

func _write(progress) -> void:
	progress.data["resources"] = 42
	progress.data["xp"] = 81
	progress.data["upgrades"] = {"hp": 2, "support": 1}
	progress.data["support_charges"] = 1
	progress.data["skill_level"] = 1 + int(progress.data["xp"]) / 20
	progress.set_loadout(&"saiga12k", &"slug")
	progress.set_run_mode("waves")
	progress.set_map_id("goliath_arena")
	_check(progress.save_data(), "save_data 返回成功")
	_check(FileAccess.file_exists(progress.save_path), "存档文件已接收")
	_check(not FileAccess.file_exists(progress.save_path + ".tmp"), "临时文件已清理")

func _verify(progress) -> void:
	_check(FileAccess.file_exists(progress.save_path), "重开进程后存档文件仍在")
	_check(int(progress.data["resources"]) == 42, "资源跨进程恢复：%d" % int(progress.data["resources"]))
	_check(int(progress.data["xp"]) == 81 and int(progress.data["skill_level"]) == 5,
		"XP 与等级跨进程恢复：xp=%d lv=%d" % [int(progress.data["xp"]), int(progress.data["skill_level"])])
	var upgrades: Dictionary = progress.data["upgrades"]
	_check(int(upgrades.get("hp", -1)) == 2 and int(upgrades.get("support", -1)) == 1,
		"升级跨进程恢复：%s" % str(upgrades))
	_check(int(progress.data["support_charges"]) == 1, "支援次数跨进程恢复")
	var loadout: Dictionary = progress.data["loadout"]
	_check(String(loadout.get("weapon", "")) == "saiga12k" and String(loadout.get("ammo", "")) == "slug",
		"配装跨进程恢复：%s" % str(loadout))
	_check(progress.run_mode() == "waves" and progress.map_id() == "goliath_arena",
		"浪潮地图跨进程恢复")
