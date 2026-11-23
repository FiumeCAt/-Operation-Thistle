extends SceneTree
## InteractionSystem2D 独立单元测试（完全不依赖 Main2D）：
## 1. 交互优先级：补给箱 > 供电台 > 拉闸撤离 > 常开撤离。
## 2. 撤离守卫：浪潮模式禁止常规撤离、战利品 <1 禁止撤离、拉闸撤离需先供电。
## 3. 底部提示覆盖计时器（flash_hint）与状态提示优先级。

const INTERACT := preload("res://scripts/systems/InteractionSystem2D.gd")

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
	print("=== interaction_system_test ===")

	var state := {"active": true, "waves": false, "resources": 0}
	var searched: Array = []
	var extracts: Array = []
	var sys := INTERACT.new()
	sys.setup(null, null, null,
		func() -> bool: return bool(state["active"]),
		func() -> bool: return bool(state["waves"]),
		func() -> int: return int(state["resources"]),
		func() -> String: return "DEFAULT_HINT",
		Callable())
	sys.container_search_requested.connect(func(entry: Dictionary) -> void: searched.append(entry))
	sys.extract_requested.connect(func(via_switch: bool) -> void: extracts.append(via_switch))

	# 1) 优先级：补给箱 > 撤离点
	sys.near_container = {"art": &"material_box", "searched": false}
	sys.near_exit = true
	sys.near_exit_data = {"name": "南侧撤离点"}
	_check(sys.resolve_hint_text(0.016).contains("搜索补给箱"),
		"container hint takes priority over exit")
	sys.try_interact()
	_check(searched.size() == 1 and extracts.is_empty(),
		"try_interact prioritizes container search over extraction")

	# 2) 常开撤离守卫：无战利品被拦截 + flash_hint，有战利品发射 extract_requested(false)
	sys.near_container = {}
	sys.try_interact()
	_check(extracts.is_empty() and sys.hint_override.contains("至少 1 份战利品"),
		"extraction blocked with 0 resources and sets hint override")
	_check(sys.resolve_hint_text(0.1).contains("至少 1 份战利品"),
		"flash_hint override stays active while timer > 0")
	# 计时耗尽后恢复常开撤离提示
	sys.resolve_hint_text(3.0)
	_check(sys.resolve_hint_text(0.016).contains("南侧撤离点"),
		"expired hint override falls back to proximity exit prompt")

	state["resources"] = 2
	sys.try_interact()
	_check(extracts.size() == 1 and not bool(extracts[0]),
		"normal exit emits extract_requested(false) with >=1 resource")

	# 3) 浪潮模式禁止走常规撤离点
	state["waves"] = true
	sys.try_interact()
	_check(extracts.size() == 1 and sys.hint_override.contains("每 5 波可撤离"),
		"waves mode blocks physical exit interaction")
	sys.hint_timer = 0.0
	_check(sys.resolve_hint_text(0.016).contains("浪潮模式"),
		"waves mode shows waves exit hint near exit")

	# 4) 非活跃状态不响应交互，无目标回退默认提示
	state["waves"] = false
	sys.near_exit = false
	_check(sys.resolve_hint_text(0.016) == "DEFAULT_HINT",
		"falls back to default hint when nothing is nearby")
	state["active"] = false
	sys.near_container = {"art": &"safe"}
	sys.try_interact()
	_check(searched.size() == 1, "inactive run ignores try_interact")

	print("=== interaction_system_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
