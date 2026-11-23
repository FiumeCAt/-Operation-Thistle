extends SceneTree
## WaveSystem2D 独立单元测试（完全不依赖 Main2D）：
## 1. 累计增长波次数量（第 1 波 5、第 4 波 14、第 10 波 59、第 11 波 70）。
## 2. 线性生命/伤害倍率（第 1 波 1.0、第 11 波 1.5、第 21 波 2.0）。
## 3. 收尾追踪阈值（剩余 <10 或 <10% 总数时触发，非浪潮/非活跃/0 剩余时不触发）。
## 4. 歌利亚狂潮固定敌种、掉落倍率递增（+2%/波）、wave_changed & finish_requested 信号。

const WAVE := preload("res://scripts/systems/WaveSystem2D.gd")

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
	print("=== wave_system_test ===")

	# 1) 数量与线性属性倍率公式
	_check(WAVE.enemy_count(1) == 5, "wave 1 count == 5")
	_check(WAVE.enemy_count(4) == 14, "wave 4 count == 14 (5+2+3+4)")
	_check(WAVE.enemy_count(10) == 59 and WAVE.enemy_count(11) == 70,
		"wave 10/11 counts == 59 / 70")
	_check(is_equal_approx(WAVE.stat_scale(1), 1.0), "wave 1 stat scale == 1.0")
	_check(is_equal_approx(WAVE.stat_scale(11), 1.5), "wave 11 stat scale == 1.5 (+5%/wave linear)")
	_check(is_equal_approx(WAVE.stat_scale(21), 2.0), "wave 21 stat scale == 2.0")

	# 2) 收尾追踪逻辑
	var ws := WAVE.new()
	ws.waves_mode = false
	ws.wave_active = true
	ws.wave_total = 20
	ws.wave_alive = 5
	_check(not ws.tracking_active(), "tracking inactive outside waves_mode")
	ws.waves_mode = true
	_check(ws.tracking_active(), "tracking active when remaining < 10")
	ws.wave_total = 214
	ws.wave_alive = 21
	_check(ws.tracking_active(), "tracking active when remaining < 10% of wave_total (21/214)")
	ws.wave_alive = 22
	_check(not ws.tracking_active(), "tracking inactive when remaining >= 10% and >= 10 (22/214)")

	# 3) 歌利亚狂潮固定敌种 + loot_scale + 信号闭环
	ws.goliath_map = true
	_check(ws.enemy_kind(1) == &"goliath" and ws.enemy_kind(12) == &"goliath",
		"goliath_map always rolls goliath regardless of wave")
	ws.goliath_map = false
	_check(ws.enemy_kind(1) == &"rifleman", "wave 1 always rolls rifleman in facility waves")

	var events: Array[String] = []
	var finish_args: Array = []
	ws.wave_changed.connect(func(w: int, st: String) -> void: events.append("%d:%s" % [w, st]))
	ws.finish_requested.connect(func(ok: bool, sw: bool, ratio: float, note: String) -> void:
		finish_args.append([ok, sw, ratio, note])
	)
	ws.begin_wave(1)
	_check(ws.wave_index == 1 and ws.wave_active and ws.spawn_queue.size() == 5
		and events.has("1:started"),
		"begin_wave(1) queues 5 enemies and emits started")
	ws.on_wave_cleared()
	_check(is_equal_approx(ws.loot_scale(), 1.02) and events.has("1:cleared"),
		"on_wave_cleared bumps loot_scale +2% and emits cleared")
	ws.on_retreat()
	ws.on_extract()
	_check(finish_args.size() == 2 and is_equal_approx(float(finish_args[0][2]), 0.30)
		and is_equal_approx(float(finish_args[1][2]), 1.0),
		"on_retreat (30%) and on_extract (100%) emit finish_requested with exact payout ratios")

	# 4) 文案一致性
	ws.wave_active = true
	ws.wave_index = 3
	ws.wave_alive = 4
	ws.spawn_queue.clear()
	_check(ws.objective_text() == "浪潮 3 · 剩余 4"
		and ws.default_hint().contains("浪潮 3 · 剩余 4"),
		"wave HUD objective/hint strings stay exact")

	print("=== wave_system_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
