extends SceneTree
## FeedbackSystem2D 单元测试：锁死震屏缩放/优先级/衰减、受击红屏阈值、
## 顿帧无头安全边界、以及纯护甲 vs 掉血时的玩家受击反馈分支。
## godot --headless --path . --script res://tests/feedback_system_test.gd

const FEEDBACK_SYSTEM := preload("res://scripts/systems/FeedbackSystem2D.gd")

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


func _near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	var fb: FeedbackSystem2D = FEEDBACK_SYSTEM.new()

	# 1. 屏幕震动开关与幅度缩放
	fb.screen_shake = false
	fb.shake_scale = 5.0
	fb.add_shake(4.0)
	_check(is_zero_approx(fb.shake), "screen_shake=false blocks shake accumulation")

	fb.screen_shake = true
	fb.shake_scale = 0.0
	fb.add_shake(10.0)
	_check(is_zero_approx(fb.shake), "shake_scale=0 blocks shake accumulation")

	# 2. 强震覆盖档位，弱震不覆盖强震的峰值/衰减速度
	fb.shake_scale = 2.0
	fb.add_shake(3.0, 0.4, 20.0)
	_check(_near(fb.shake, 6.0) and _near(fb.shake_peak, 6.0)
		and _near(fb.shake_roll_deg, 0.8) and _near(fb.shake_decay, 20.0),
		"stronger shake applies scale to amplitude and roll")

	fb.add_shake(1.0, 0.1, 60.0)
	_check(_near(fb.shake, 6.0) and _near(fb.shake_decay, 20.0),
		"weaker shake does not override stronger shake decay")

	# 3. 震动逐帧衰减直至清零
	var step1 := fb.step_shake(0.1)
	_check(_near(fb.shake, 4.0) and step1.has("offset") and step1.has("roll"),
		"step_shake decays shake linearly by delta * decay")
	var step2 := fb.step_shake(0.5)
	_check(is_zero_approx(fb.shake) and is_zero_approx(float(step2["roll"])),
		"step_shake zeroes shake and roll once decayed")
	var step3 := fb.step_shake(0.1)
	_check(step3["offset"] == Vector2.ZERO and is_zero_approx(float(step3["roll"])),
		"idle step_shake returns zero offset and zero roll")

	# 4. 受击红屏透明度夹紧区间 [0.10, 0.34]
	_check(_near(FEEDBACK_SYSTEM.calc_hurt_flash_alpha(0), 0.10),
		"hurt flash alpha floors at 0.10")
	_check(_near(FEEDBACK_SYSTEM.calc_hurt_flash_alpha(16), 0.20),
		"hurt flash alpha scales linearly with hp damage")
	_check(_near(FEEDBACK_SYSTEM.calc_hurt_flash_alpha(999), 0.34),
		"hurt flash alpha caps at 0.34")

	# 5. 无头环境下顿帧安全：不修改 Engine.time_scale，reset_time_scale 兜底恢复 1.0
	var owner := Node2D.new()
	var fx := Node2D.new()
	owner.add_child(fx)
	root.add_child(owner)
	fb.setup(owner, fx, null, null)
	fb.build_hit_feedback()
	_check(fb.hitstop_timer != null and fb.hurt_flash_rect != null,
		"build_hit_feedback creates timer and hurt flash overlay")
	fb.hitstop_enabled = true
	fb.hitstop(0.05)
	_check(_near(Engine.time_scale, 1.0), "hitstop keeps time_scale=1 in headless mode")
	Engine.time_scale = 0.12
	fb.reset_time_scale()
	_check(_near(Engine.time_scale, 1.0), "reset_time_scale restores Engine.time_scale to 1.0")

	# 6. 玩家受击反馈分支：纯护甲损伤不红屏不抖屏；真实掉血触发红屏+抖屏+双飘字
	fb.shake_scale = 1.0
	fb.on_player_damaged(18, 0, Vector2(100, 100))
	_check(is_zero_approx(fb.shake) and is_zero_approx(fb.hurt_flash_rect.color.a)
		and fx.get_child_count() == 1,
		"armor-only hit spawns armor number without hurt flash or shake")

	fb.on_player_damaged(12, 24, Vector2(100, 100))
	_check(fb.shake > 2.0 and fb.hurt_flash_rect.color.a > 0.20
		and fx.get_child_count() == 3,
		"hp hit triggers hurt flash, camera shake, and separate armor+hp numbers")

	# 7. apply_settings 与 Progress 同步
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		p.data["screen_shake"] = false
		p.data["hitstop_enabled"] = true
		p.data["shake_scale"] = 200.0
		fb.apply_settings(p)
		_check(not fb.screen_shake and fb.hitstop_enabled
			and _near(fb.shake_scale, 2.0 * FEEDBACK_SYSTEM.SHAKE_SCALE_BASE),
			"apply_settings syncs shake toggle, hitstop, and scaled shake factor")
		p.reset_for_test()

	# 8. 枪口火光与局部点亮表现：开火点亮动态点光源、叠加局部光晕与火星；消音器明显抑制亮度
	fb.warm_muzzle_fx()
	_check(fb.muzzle_flash != null and not fb.muzzle_flash.is_active(),
		"warm_muzzle_fx creates idle MuzzleFlash2D node")
	fb.play_muzzle_fx(Vector2(200, 150), 0.0, 1.2, false)
	var bright_energy: float = fb.muzzle_flash.current_light_energy()
	var bright_bloom: float = fb.muzzle_flash.current_bloom_alpha()
	_check(fb.muzzle_flash.is_active() and bright_energy > 0.55 and bright_energy < 1.20
		and bright_bloom > 0.08 and bright_bloom < 0.22 and fb.muzzle_flash.spark_count() >= 6,
		"unsuppressed shot triggers balanced muzzle light (%.2f), local bloom (%.2f), and sparks" % [bright_energy, bright_bloom])
	fb.play_muzzle_fx(Vector2(200, 150), 0.0, 1.2, true)
	var supp_energy: float = fb.muzzle_flash.current_light_energy()
	var supp_bloom: float = fb.muzzle_flash.current_bloom_alpha()
	_check(supp_energy < bright_energy * 0.45 and supp_bloom < bright_bloom * 0.45,
		"suppressor strongly dampens muzzle flash light and bloom")

	owner.queue_free()
	await process_frame
	print("\n=== feedback system: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
