extends SceneTree
## ContainerRuntime2D 独立单元测试：验证容器目录、稀有度、保底规则、提示切换与浪潮重置。
## godot --headless --path . --script res://tests/container_runtime_test.gd

const RUNTIME := preload("res://scripts/level/ContainerRuntime2D.gd")

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
	# 1. 目录查询与兜底
	_check(RUNTIME.display_name(&"safe_military") == "军用保险箱"
		and RUNTIME.display_name(&"unknown_box") == "补给箱",
		"display_name returns localized name and fallback")
	_check(RUNTIME.rarity_color(&"safe_military") == RUNTIME.RARITY_LEGENDARY
		and RUNTIME.rarity_color(&"weapon_crate") == RUNTIME.RARITY_EPIC
		and RUNTIME.rarity_color(&"material_box") == RUNTIME.RARITY_COMMON,
		"rarity_color maps container tiers accurately")
	_check(RUNTIME.guarantees_advanced(&"safe_military")
		and RUNTIME.guarantees_advanced(&"safe_electronic")
		and RUNTIME.guarantees_advanced(&"safe_standard")
		and not RUNTIME.guarantees_advanced(&"safe_small"),
		"guarantees_advanced covers large safes and excludes safe_small")
	_check(RUNTIME.deco_loot(&"medcrate_large") == &"repair"
		and RUNTIME.deco_loot(&"box_document") == &"electronics"
		and RUNTIME.deco_loot(&"coat_cold") == &"parts",
		"deco_loot maps medical/document/clothing props to expected loot")

	# 2. 构建标准容器 + 装饰容器，校验节点、提示切换与浪潮刷新
	var sort_layer := Node2D.new()
	root.add_child(sort_layer)
	var containers: Array[Dictionary] = [
		{"room": 0, "position": Vector2(120, 120), "loot": &"parts", "art": &"weapon_crate", "searched": false, "node": null},
	]
	var marked := [0]
	RUNTIME.spawn_deco_prop(sort_layer, containers, Vector2(240, 120), &"medcrate_large",
		func(_p: Vector2, _s: Vector2) -> void: marked[0] += 1)
	RUNTIME.build_containers(sort_layer, containers)

	_check(containers.size() == 2 and marked[0] == 1
		and containers[0]["node"] != null and containers[1]["node"] != null,
		"build_containers and spawn_deco_prop populate nodes and mark obstacle")

	RUNTIME.set_container_hint(containers, 0, false)
	_check(containers[0]["hint"].visible and containers[0]["hint"].text == "E  搜索"
		and not containers[1]["hint"].visible,
		"set_container_hint highlights only target container")
	RUNTIME.set_container_hint(containers, 0, true)
	_check(containers[0]["hint"].visible and containers[0]["hint"].text == "已搜索",
		"set_container_hint switches label for searched container")

	# 模拟开箱后浪潮刷新恢复未搜刮与关闭贴图
	var closed_tex = RUNTIME.container_art(&"weapon_crate")["closed"]
	containers[0]["searched"] = true
	containers[0]["sprite"].texture = RUNTIME.container_art(&"weapon_crate")["open"]
	containers[1]["searched"] = true
	containers[1]["node"].modulate = Color(0.5, 0.5, 0.5, 1.0)
	RUNTIME.refresh_containers(containers)
	_check(not bool(containers[0]["searched"]) and containers[0]["sprite"].texture == closed_tex
		and not bool(containers[1]["searched"]) and containers[1]["node"].modulate == Color(1, 1, 1, 1)
		and not containers[0]["hint"].visible,
		"refresh_containers restores closed texture, modulate, and hides hints")

	sort_layer.queue_free()
	await process_frame
	print("\n=== container runtime: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
