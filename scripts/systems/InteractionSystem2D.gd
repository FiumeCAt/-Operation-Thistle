extends RefCounted
class_name InteractionSystem2D
## 2D 交互与底部提示子系统：
## 从 Main2D 抽离，集中管理补给箱、控制室供电台、拉闸撤离与常开撤离点的
## 距离感知、优先级（箱子 > 供电 > 拉闸撤离 > 常开撤离）、底部提示与 E 键触发。

signal container_search_requested(entry: Dictionary)
signal extract_requested(via_switch: bool)

const INTERACT_RADIUS := 96.0
const EXIT_RADIUS := 118.0

var near_container: Dictionary = {}
var near_exit := false
var near_exit_data: Dictionary = {}
var near_power := false
var near_switch_exit := false
var hint_override := ""
var hint_timer := 0.0

var _level: Level2D
var _doll: Doll2D
var _hud: RunHUD2D
var _is_active_fn: Callable = Callable()
var _is_waves_fn: Callable = Callable()
var _resources_fn: Callable = Callable()
var _default_hint_fn: Callable = Callable()
var _sfx_fn: Callable = Callable()


func setup(level: Level2D, doll: Doll2D, hud: RunHUD2D,
		is_active_fn: Callable, is_waves_fn: Callable, resources_fn: Callable,
		default_hint_fn: Callable, sfx_fn: Callable) -> void:
	_level = level
	_doll = doll
	_hud = hud
	_is_active_fn = is_active_fn
	_is_waves_fn = is_waves_fn
	_resources_fn = resources_fn
	_default_hint_fn = default_hint_fn
	_sfx_fn = sfx_fn


func _is_active() -> bool:
	return bool(_is_active_fn.call()) if _is_active_fn.is_valid() else true


func _is_waves() -> bool:
	return bool(_is_waves_fn.call()) if _is_waves_fn.is_valid() else false


func _resources() -> int:
	return int(_resources_fn.call()) if _resources_fn.is_valid() else 0


func _default_hint() -> String:
	return String(_default_hint_fn.call()) if _default_hint_fn.is_valid() else ""


func flash_hint(text: String) -> void:
	hint_override = text
	hint_timer = 2.2
	if _hud != null:
		_hud.set_hint(text)
		_hud.flash(text)


func update(delta: float) -> void:
	if not _is_active():
		if _level != null:
			_level.set_container_hint(-1)
		if _hud != null:
			_hud.clear_interact_target()
		return
	if _level == null or _doll == null:
		return

	# 交互：补给箱 > 供电台 > 拉闸撤离 > 常开撤离。
	near_container = {}
	var near_index := -1
	var near_searched := -1
	var player_pos: Vector2 = _doll.global_position
	for i in _level.containers.size():
		var entry: Dictionary = _level.containers[i]
		var node: Node2D = entry["node"]
		if node == null or player_pos.distance_to(node.global_position) >= INTERACT_RADIUS:
			continue
		if bool(entry["searched"]):
			near_searched = i
		elif near_index < 0:
			near_container = entry
			near_index = i
	# 可搜刮箱子优先；否则在已搜刮箱子上显示“已搜索”。
	if near_index >= 0:
		_level.set_container_hint(near_index)
		var art_id := StringName(near_container.get("art", &"material_box"))
		if _hud != null:
			_hud.set_interact_target(_level.container_display_name(art_id),
				_level.container_rarity_color(art_id))
	elif near_searched >= 0:
		_level.set_container_hint(near_searched, true)
		if _hud != null:
			_hud.clear_interact_target()
	else:
		_level.set_container_hint(-1)
		if _hud != null:
			_hud.clear_interact_target()

	near_exit = false
	near_exit_data = {}
	for exit_data in _level.exits:
		var exit_pos: Vector2 = exit_data["position"]
		if player_pos.distance_to(exit_pos) < EXIT_RADIUS:
			near_exit = true
			near_exit_data = exit_data
			break
	near_power = not _level.power_on \
		and player_pos.distance_to(_level.power_position) < INTERACT_RADIUS
	near_switch_exit = player_pos.distance_to(_level.switch_exit_position) < EXIT_RADIUS

	if _hud != null:
		_hud.set_hint(resolve_hint_text(delta))


func resolve_hint_text(delta: float) -> String:
	if hint_timer > 0.0:
		hint_timer = maxf(hint_timer - delta, 0.0)
		return hint_override
	if _is_waves() and (near_switch_exit or near_exit):
		return "浪潮模式：每 5 波可撤离 · ESC 提前撤离（30%）"
	if not near_container.is_empty():
		return "E  搜索补给箱"
	if near_power:
		return "E  恢复供电（解锁拉闸撤离 · 结算 +20%）"
	if near_switch_exit:
		if _level != null and _level.power_on:
			return "E  拉闸撤离（任务 +20% · 拉闸 +10%）"
		return "货运电梯未供电 · 先恢复控制室供电"
	if near_exit:
		var exit_name := String(near_exit_data.get("name", "撤离点"))
		return "E  %s（需要至少 1 份战利品）" % exit_name
	return _default_hint()


func try_interact() -> void:
	if not _is_active():
		return
	if _level != null and _doll != null:
		update(0.0)
	if not near_container.is_empty():
		container_search_requested.emit(near_container)
	elif near_power:
		restore_power()
	elif near_switch_exit:
		try_switch_extract()
	elif near_exit:
		try_extract()


## 控制室供电：解锁军械库货运电梯，并给本局结算 +20%。
func restore_power() -> void:
	if _level == null or _level.power_on:
		return
	_level.set_power_on(true)
	if _sfx_fn.is_valid():
		_sfx_fn.call("switch", -3.0)
	flash_hint("供电恢复 · 军械库拉闸撤离已上线（结算 +20%）")


func try_switch_extract() -> void:
	if _is_waves():
		flash_hint("浪潮模式：每 5 波可撤离 · ESC 提前撤离（30%）")
		return
	if _level == null or not _level.power_on:
		flash_hint("货运电梯未供电 · 先恢复控制室供电")
		return
	if _resources() < 1:
		flash_hint("需要至少 1 份战利品才能撤离")
		return
	extract_requested.emit(true)


func try_extract() -> void:
	if _is_waves():
		flash_hint("浪潮模式：每 5 波可撤离 · ESC 提前撤离（30%）")
		return
	if _resources() < 1:
		flash_hint("需要至少 1 份战利品才能撤离")
		return
	extract_requested.emit(false)
