extends SceneTree
## LootSystem2D 独立单元测试（完全不依赖 Main2D）：
## 1. 掉落倍率缩放（scale_amount / scale_chance）边界。
## 2. 基础/进阶抽取与第二基础资源不重复保证。
## 3. 容器产物组合（必出主资源、二次/进阶概率控制与浪潮倍率放大）。
## 4. 撤离入库（基础吃搜刮天赋、进阶原样）与浪潮 30%/100% 回收拆表。

const LOOT := preload("res://scripts/systems/LootSystem2D.gd")

var _ok := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	print("=== loot_system_test ===")

	# 1) 倍率缩放边界
	_check(LOOT.scale_amount(1, 0.2) == 1, "scale_amount floors at 1")
	_check(LOOT.scale_amount(10, 1.2) == 12, "scale_amount applies wave multiplier (10*1.2=12)")
	_check(is_equal_approx(LOOT.scale_chance(0.8, 2.0), 1.0), "scale_chance clamps upper bound to 1.0")
	_check(is_equal_approx(LOOT.scale_chance(0.5, -1.0), 0.0), "scale_chance clamps lower bound to 0.0")

	# 2) 基础 / 排除 / 进阶抽取
	var all_basic_ok := true
	for i in 30:
		if not ResourceDB.is_basic(LOOT.roll_basic_drop(&"rifleman")):
			all_basic_ok = false
			break
		if not ResourceDB.is_basic(LOOT.roll_basic_drop(&"unknown_enemy")):
			all_basic_ok = false
			break
	_check(all_basic_ok, "roll_basic_drop always returns a valid basic resource")

	var excl_ok := true
	for i in 30:
		var pick: StringName = LOOT.roll_basic_excluding(&"parts")
		if pick == &"parts" or not ResourceDB.is_basic(pick):
			excl_ok = false
			break
	_check(excl_ok, "roll_basic_excluding never repeats primary resource")

	var adv_ok := true
	for i in 30:
		if not ResourceDB.ADVANCED.has(LOOT.roll_advanced()):
			adv_ok = false
			break
	_check(adv_ok, "roll_advanced always returns a valid advanced material")

	# 3) 容器产物组合
	var bundle_full: Array[Dictionary] = LOOT.roll_container_bundle(&"parts", 2, 4, 1.0, 1.0, 1.0)
	_check(bundle_full.size() == 3 and bundle_full[0]["id"] == &"parts"
		and bundle_full[1]["id"] != &"parts" and ResourceDB.ADVANCED.has(bundle_full[2]["id"]),
		"roll_container_bundle emits primary + distinct secondary + advanced at 100% chance")
	var bundle_min: Array[Dictionary] = LOOT.roll_container_bundle(&"energy", 2, 4, 0.0, 0.0, 1.0)
	_check(bundle_min.size() == 1 and bundle_min[0]["id"] == &"energy"
		and int(bundle_min[0]["amount"]) >= 2 and int(bundle_min[0]["amount"]) <= 4,
		"roll_container_bundle emits only primary within [min, max] at 0% bonus chances")
	var bundle_scaled: Array[Dictionary] = LOOT.roll_container_bundle(&"electronics", 2, 2, 0.0, 0.0, 1.5)
	_check(int(bundle_scaled[0]["amount"]) == 3,
		"roll_container_bundle applies wave loot_scale to quantity (2*1.5=3)")

	# 4) 撤离入库与浪潮回收拆表
	var banked: Dictionary = LOOT.compute_banked_materials(
		{"parts": 5, "electronics": 0, "energy": 2},
		{"electronic_core": 2, "weapon_parts": 0},
		1.4
	)
	_check(int(banked.get("parts", 0)) == 7 and int(banked.get("energy", 0)) == 3
		and not banked.has("electronics")
		and int(banked.get("electronic_core", 0)) == 2 and not banked.has("weapon_parts"),
		"compute_banked_materials scales basic by scavenge_mul and preserves advanced exact counts")

	var scaled_30: Dictionary = LOOT.compute_scaled_materials(
		{"parts": 10, "energy": 1},
		{"military_alloy": 2},
		1.0, 0.30
	)
	var basic_30: Dictionary = scaled_30["basic"]
	var adv_30: Dictionary = scaled_30["advanced"]
	var merged_30: Dictionary = scaled_30["materials"]
	_check(int(basic_30.get("parts", 0)) == 3 and int(basic_30.get("energy", 0)) == 1
		and int(adv_30.get("military_alloy", 0)) == 1
		and merged_30.size() == 3,
		"compute_scaled_materials at 30% preserves >=1 floor and splits basic/advanced cleanly")

	# 5) 独立收集回调（无 Main2D 宿主）
	var sys := LOOT.new()
	var added: Array = []
	var sfx_calls: Array = []
	sys.setup(null, null, null, null, func() -> float: return 1.0,
		func(kind: String, _v: float) -> void: sfx_calls.append(kind),
		func(id: StringName, amt: int) -> void: added.append([id, amt]))
	sys.on_pickup_collected("resource", &"parts", 3)
	_check(added.size() == 1 and added[0][0] == &"parts" and int(added[0][1]) == 3
		and sfx_calls == ["pickup"],
		"standalone on_pickup_collected invokes add_loot_fn and sfx_fn cleanly")

	print("=== loot_system_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
