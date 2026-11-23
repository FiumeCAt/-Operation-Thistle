extends RefCounted
class_name WaveSystem2D
## 2D 浪潮与歌利亚狂潮波次调度子系统。
## 从 Main2D 抽离，集中管理：
##   1. 波次敌人数量累计增长、线性生命/伤害倍率、掉落倍率与收尾追踪阈值；
##   2. 分批投放队列、远离玩家的刷新点排序与各波敌种抽取；
##   3. 清波结算（含歌利亚狂潮状态/弹药回满）、每 5 波撤离窗口弹窗与继续/撤离回调；
##   4. 浪潮模式 HUD 目标/提示文案生成。

signal wave_changed(wave: int, state: String)
signal finish_requested(success: bool, via_switch: bool, payout_ratio: float, note: String)

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
const WAVES_POPUP := preload("res://scripts/ui/WavesExitPopup2D.gd")

## 第 N 波在上一波基础上再增加 N 个敌人（累计增长）；
## 生命/伤害每波固定 +5%（线性，第 N 波 = 1 + 0.05 × (N-1)）。
const BASE_COUNT := 5
const STAT_STEP := 0.05
const INTERMISSION := 4.0
const SPAWN_INTERVAL := 0.12
const START_DELAY := 3.0
## 每 5 波弹一次撤离窗口，同时刷新全部补给容器。
const EXTRACT_EVERY := 5
## 结算比例：死亡 / ESC 提前撤离 30%，撤离弹窗正常撤离 100%。
const EARLY_RATIO := 0.30
const EXTRACT_RATIO := 1.0
## 每存活一波，容器与敌人掉落率、掉落数量 +2%。
const LOOT_STEP := 0.02

var waves_mode := false
var goliath_map := false
var wave_index := 0
var wave_active := false
var wave_alive := 0
var wave_loot_mul := 1.0
var spawn_queue: Array[Dictionary] = []
var spawn_t := 0.0
var spawn_batch := 1
var wave_total := 0
var intermission := 0.0
var popup: CanvasLayer = null

var _owner_node: Node
var _sort_layer: Node2D
var _level: Level2D
var _doll: Doll2D
var _hud: RunHUD2D
var _enemies: Array[Enemy2D]
var _is_active_fn: Callable = Callable()
var _on_enemy_died_fn: Callable = Callable()
var _sfx_fn: Callable = Callable()


func setup(owner_node: Node, sort_layer: Node2D, level: Level2D, doll: Doll2D,
		hud: RunHUD2D, enemies_ref: Array[Enemy2D], is_active_fn: Callable,
		on_enemy_died_fn: Callable, sfx_fn: Callable) -> void:
	_owner_node = owner_node
	_sort_layer = sort_layer
	_level = level
	_doll = doll
	_hud = hud
	_enemies = enemies_ref
	_is_active_fn = is_active_fn
	_on_enemy_died_fn = on_enemy_died_fn
	_sfx_fn = sfx_fn


func start_waves_mode() -> void:
	build_exit_popup()
	intermission = START_DELAY


func build_exit_popup() -> void:
	if popup != null or _owner_node == null:
		return
	popup = WAVES_POPUP.new()
	popup.name = "WavesExitPopup2D"
	_owner_node.add_child(popup)
	popup.extract_requested.connect(on_extract)
	popup.continue_requested.connect(on_continue)


func hide_popup_on_finish(tree: SceneTree) -> void:
	if popup != null and popup.visible:
		popup.visible = false
		if tree != null:
			tree.paused = false


func _is_run_active() -> bool:
	if _is_active_fn.is_valid():
		return bool(_is_active_fn.call())
	return true


## 累计增长：count(N) = count(N-1) + N，例如第 10 波 59 只，第 11 波就是 70 只。
static func enemy_count(index: int) -> int:
	var count := BASE_COUNT
	for step in range(2, index + 1):
		count += step
	return count


## 生命/伤害倍率：线性固定 +5%/波；第 1 波 100%，第 11 波 150%。
static func stat_scale(index: int) -> float:
	return 1.0 + STAT_STEP * float(maxi(index, 1) - 1)


## 浪潮掉落倍率：其他模式保持 1.0。
func loot_scale() -> float:
	return wave_loot_mul if waves_mode else 1.0


## 收尾追踪：剩余敌人少于 10 个，或少于本波总数的 10% 时，
## 小地图与大地图强制标出所有敌人，方便寻找最后的漏网之鱼。
func tracking_active() -> bool:
	if not waves_mode or not wave_active or wave_total <= 0:
		return false
	var remaining := wave_alive + spawn_queue.size()
	if remaining <= 0:
		return false
	return remaining < 10 or float(remaining) < float(wave_total) * 0.1


func on_enemy_died() -> void:
	if waves_mode:
		wave_alive = maxi(wave_alive - 1, 0)


## 波次推进：分批投放 → 清空后进入波间倒计时 → 下一波。
func update(delta: float) -> void:
	if not waves_mode or not _is_run_active():
		return
	if not spawn_queue.is_empty():
		spawn_t -= delta
		var spawned := 0
		while spawn_t <= 0.0 and not spawn_queue.is_empty() and spawned < spawn_batch:
			spawn_enemy(spawn_queue.pop_front())
			spawn_t += SPAWN_INTERVAL
			spawned += 1
		return
	if wave_active:
		if wave_alive <= 0:
			wave_active = false
			on_wave_cleared()
		return
	if intermission > 0.0:
		intermission = maxf(intermission - delta, 0.0)
		if intermission <= 0.0:
			begin_wave(wave_index + 1)


## 第 N 波：在上一波基础上再增加 N 个敌人；生命与伤害按线性固定 +5% 叠加。
func begin_wave(index: int) -> void:
	wave_index = index
	wave_active = true
	intermission = 0.0
	var stat_mul := stat_scale(wave_index)
	var count := enemy_count(wave_index)
	wave_total = count
	# 波数越高敌人越多，按批次投放，避免几十只同时生成造成卡顿。
	spawn_batch = clampi(int(ceil(float(count) / 25.0)), 1, 4)
	var points := spawn_points()
	spawn_queue.clear()
	for i in count:
		spawn_queue.append({
			"kind": enemy_kind(wave_index),
			"pos": points[i % points.size()] + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			"stat_mul": stat_mul,
		})
	spawn_t = 0.0
	if _hud != null:
		_hud.flash("第 %d 波来袭 · %d 个目标" % [wave_index, count])
	if _sfx_fn.is_valid():
		_sfx_fn.call("ui", -6.0)
	wave_changed.emit(wave_index, "started")


func on_wave_cleared() -> void:
	intermission = INTERMISSION
	wave_loot_mul += LOOT_STEP
	var clear_text := "第 %d 波清除 · 掉落 +2%%" % wave_index
	if goliath_map and _doll != null:
		# 歌利亚狂潮：每波结束自动补满生命、护甲、弹匣与备弹。
		_doll.hp = _doll.hp_max
		_doll.armor = _doll.armor_max
		if _doll.weapon_rig != null:
			_doll.weapon_rig.refill_all_ammo()
		clear_text += " · 状态/弹药回满"
	if _hud != null:
		_hud.flash(clear_text)
	if _sfx_fn.is_valid():
		_sfx_fn.call("ui", -6.0)
	if wave_index % EXTRACT_EVERY == 0 and popup != null:
		intermission = 0.0
		# 设施浪潮每 5 波刷新补给；竞技场没有容器，只弹撤离窗口。
		if goliath_map:
			if _hud != null:
				_hud.flash("第 %d 波清除 · 可撤离 100%%" % wave_index)
		else:
			if _level != null:
				_level.refresh_containers()
			if _hud != null:
				_hud.flash("第 %d 波清除 · 补给已刷新 · 可撤离 100%%" % wave_index)
		popup.open(wave_index)
		wave_changed.emit(wave_index, "extract_window")
	else:
		wave_changed.emit(wave_index, "cleared")


## 出生点优先取离玩家 9 格以外的位置，避免整波贴脸刷新。
func spawn_points() -> Array[Vector2]:
	var far: Array[Vector2] = []
	var near: Array[Vector2] = []
	var player_pos := _doll.global_position if _doll != null else Vector2.ZERO
	if _level != null:
		for pos in _level.enemy_spawns:
			if pos.distance_to(player_pos) >= 9.0 * TILE:
				far.append(pos)
			else:
				near.append(pos)
	far.shuffle()
	near.shuffle()
	var out: Array[Vector2] = []
	out.append_array(far)
	out.append_array(near)
	if out.is_empty():
		out.append(player_pos + Vector2(12.0, 0.0) * TILE)
	return out


## 精英单位随波数逐步加入，后期猎人/重装占比提高。
func enemy_kind(index: int) -> StringName:
	if goliath_map:
		return &"goliath"
	var roll := randf()
	if index >= 6 and roll < 0.15:
		return &"hunter"
	if index >= 4 and roll < 0.35:
		return &"heavy"
	if index >= 2 and roll < 0.65:
		return &"rusher"
	return &"rifleman"


func spawn_enemy(entry: Dictionary) -> Enemy2D:
	if _sort_layer == null:
		return null
	var pos: Vector2 = entry["pos"]
	var stat_mul := float(entry["stat_mul"])
	var enemy := Enemy2D.new()
	enemy.setup(StringName(entry["kind"]), pos, 1, stat_mul, stat_mul)
	enemy.always_hunt = true
	enemy.nav_level = _level
	_sort_layer.add_child(enemy)
	if _on_enemy_died_fn.is_valid():
		enemy.died.connect(_on_enemy_died_fn)
	_enemies.append(enemy)
	wave_alive += 1
	return enemy


## ESC 菜单提前撤离：按 30% 结算。
func on_retreat() -> void:
	if not waves_mode or not _is_run_active():
		return
	finish_requested.emit(true, false, EARLY_RATIO, "提前撤离 · 信用点/材料按 30% 回收")


## 每 5 波撤离弹窗：正常撤离按 100% 结算。
func on_extract() -> void:
	if not _is_run_active():
		return
	finish_requested.emit(true, false, EXTRACT_RATIO, "浪潮撤离 · 信用点/材料按 100% 回收")


func on_continue() -> void:
	intermission = INTERMISSION
	if _hud != null:
		_hud.flash("继续挑战 · 第 %d 波准备" % (wave_index + 1))


func objective_text() -> String:
	var wave_name := "歌利亚狂潮" if goliath_map else "浪潮"
	if wave_active:
		return "%s %d · 剩余 %d" % [
			wave_name, wave_index, wave_alive + spawn_queue.size()]
	if wave_index == 0:
		return "%s · 准备中" % wave_name
	return "%s %d 已清除 · 下一波准备中" % [wave_name, wave_index]


func default_hint() -> String:
	if wave_active:
		return "浪潮 %d · 剩余 %d（ESC 可提前撤离）" % [
			wave_index, wave_alive + spawn_queue.size()]
	if wave_index == 0:
		return "浪潮模式：守住每一波 · 每 5 波可撤离"
	return "第 %d 波已清除 · 下一波准备中（ESC 可提前撤离）" % wave_index
