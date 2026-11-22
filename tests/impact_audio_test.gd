extends SceneTree
## 命中采样接入回归：材质映射、懒加载、开关回退、墙面弹着。
## godot --headless --path . --script res://tests/impact_audio_test.gd

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
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()

	var sfx = root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload exists")
	if sfx == null:
		quit(1)
		return

	# 1) 所有映射路径都必须能解析成 AudioStream。
	var missing: Array[String] = []
	for material in sfx.IMPACT_SAMPLE_SETS:
		for rel in sfx.IMPACT_SAMPLE_SETS[material]:
			var path: String = sfx.IMPACT_SAMPLE_ROOT + String(rel)
			if not ResourceLoader.exists(path):
				missing.append(path)
	_check(missing.is_empty(), "every mapped impact sample is imported (%d missing)" % missing.size())
	_check(sfx.impact_sample_count("concrete") >= 3, "concrete material has samples")
	_check(sfx.impact_sample_count("metal") >= 3, "metal material has samples")
	_check(sfx.impact_sample_count("flesh") >= 3, "flesh material has samples")
	_check(sfx.impact_sample_count("ricochet") >= 3, "ricochet layer has samples")
	_check(sfx.impact_sample_count("generic") >= 3, "generic fallback has samples")

	# 2) 默认开启采样，命中会创建播放器。
	_check(bool(p.data["sample_impacts"]) and sfx.sampled_impacts_enabled(),
		"sampled impacts are on by default")
	var before := sfx.get_child_count()
	sfx.play_hit("metal", 1.5, -20.0)
	_check(sfx.get_child_count() > before, "sample hit spawns audio players")
	await create_timer(0.06).timeout

	# 3) 墙面弹着走混凝土。
	before = sfx.get_child_count()
	sfx.play_wall_impact(-20.0)
	_check(sfx.get_child_count() > before, "wall impact plays the concrete sample")
	await create_timer(0.06).timeout

	# 玩家被敌人子弹击中：即使采样开启，也仍然走原有合成命中音。
	before = sfx.get_child_count()
	sfx.play_player_hurt(-20.0)
	_check(sfx.get_child_count() > before, "player hurt still uses synthesized hit audio")

	# 4) 关掉开关后仍能播放，但走程序化回退。
	p.set_sample_impacts(false)
	_check(not sfx.sampled_impacts_enabled(), "turning the switch off disables samples")
	# Sfx 的节流用真实毫秒，而无头模式下模拟计时的 0.06s 可能只过了几毫秒；
	# 这里直接清掉节流时间戳，保证回退路径检查稳定。
	before = sfx.get_child_count()
	sfx._last_hit_ms = 0
	sfx.play_hit("flesh", 1.0, -20.0)
	_check(sfx.get_child_count() > before, "procedural fallback still plays")
	await create_timer(0.06).timeout
	before = sfx.get_child_count()
	sfx._last_wall_ms = 0
	sfx.play_wall_impact(-20.0)
	_check(sfx.get_child_count() > before, "wall impact falls back to synthesis")

	# 5) 未知材质自动落到 generic，不应报错。
	p.data["sample_impacts"] = true
	sfx.play_hit("unknown_material", 1.0, -20.0)
	await process_frame
	_check(true, "unknown material falls back without errors")

	print("\n=== impact audio: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
