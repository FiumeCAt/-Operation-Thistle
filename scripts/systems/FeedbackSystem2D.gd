extends RefCounted
class_name FeedbackSystem2D
## 2D 打击反馈与特效协调子系统：屏幕震动、命中顿帧、受击红屏、枪口闪光、特效/字体预热与 2D 音效。
## 从 Main2D 抽离，对外无节点耦合，可脱离场景树独立单测核心状态机。

## pixelfx 枪口特效的原点是枪口下方的地面参考点；插件的 height 默认 26px，
## 所以节点要沿枪管下移 26px，闪光才会正好落在枪口上。
const MUZZLE_FX_GROUND := 26.0
## 滑杆 100% 对应旧版 500% 的实际震动强度，统一在这里换算。
const SHAKE_SCALE_BASE := 5.0
const HIT_FX := preload("res://scripts/fx/HitFX2D.gd")
const COMBAT_FX_WARMUP := preload("res://scripts/fx/CombatFxWarmup.gd")
const MUZZLE_FLASH := preload("res://scripts/fx/MuzzleFlash2D.gd")

## 玩家设置项
var screen_shake := true
var hitstop_enabled := false
var shake_scale := 1.0

## 镜头抖动状态
var shake := 0.0
var shake_peak := 0.0
var shake_roll_deg := 0.2
var shake_decay := 32.0
var shake_roll := 0.0

## 节点引用（由 build_hit_feedback / warm_muzzle_fx 构建）
var hitstop_timer: Timer
var hurt_flash_rect: ColorRect
var muzzle_fx: PixelFx2D
var muzzle_flash: Node2D
var _muzzle_stop_ms := 0

var _owner: Node2D
var _fx_layer: Node2D
var _doll: Doll2D
var _hud: RunHUD2D


func setup(owner_node: Node2D, fx_layer: Node2D, doll: Doll2D, hud: RunHUD2D) -> void:
	_owner = owner_node
	_fx_layer = fx_layer
	_doll = doll
	_hud = hud


## 同步 Progress 中的反馈设置（开局与设置页确认后共用）。
func apply_settings(progress: Node) -> void:
	if progress == null:
		return
	screen_shake = bool(progress.data.get("screen_shake", true))
	hitstop_enabled = bool(progress.data.get("hitstop_enabled", false))
	shake_scale = clampf(float(progress.data.get("shake_scale", 100.0)) / 100.0, 0.0, 10.0) \
		* SHAKE_SCALE_BASE


## 顿帧计时器与受击红屏只建一次，避免每次命中都新建节点。
func build_hit_feedback() -> void:
	if _owner == null:
		return
	hitstop_timer = Timer.new()
	hitstop_timer.one_shot = true
	hitstop_timer.ignore_time_scale = true
	hitstop_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	hitstop_timer.timeout.connect(end_hitstop)
	_owner.add_child(hitstop_timer)

	var layer := CanvasLayer.new()
	layer.layer = 90
	_owner.add_child(layer)
	hurt_flash_rect = ColorRect.new()
	hurt_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hurt_flash_rect.color = Color(0.72, 0.04, 0.04, 0.0)
	layer.add_child(hurt_flash_rect)
	hurt_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 添加镜头震动；更大振幅覆盖峰值/旋转/衰减档位，避免微抖打断重击。
func add_shake(amount: float, roll_deg := 0.18, decay := 32.0) -> void:
	if not screen_shake:
		return
	amount *= shake_scale
	roll_deg *= shake_scale
	if amount <= 0.001:
		return
	var stronger := amount >= shake
	shake = maxf(shake, amount)
	if stronger:
		shake_peak = maxf(shake, 0.001)
		shake_roll_deg = roll_deg
		shake_decay = decay


## 按帧衰减屏幕震动并返回本帧位置偏移与旋转角。
func step_shake(delta: float) -> Dictionary:
	var offset := Vector2.ZERO
	if shake > 0.0:
		shake = maxf(shake - delta * shake_decay, 0.0)
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
		var ratio := clampf(shake / maxf(shake_peak, 0.001), 0.0, 1.0)
		shake_roll = randf_range(-1.0, 1.0) * deg_to_rad(shake_roll_deg) * ratio
		if shake <= 0.0:
			shake_roll = 0.0
	return {"offset": offset, "roll": shake_roll}


## 命中/击杀的短暂顿帧：把全局时间压到 12%，用真实时间计时恢复。
func hitstop(seconds: float) -> void:
	if seconds <= 0.0 or hitstop_timer == null or not hitstop_enabled:
		return
	# 无头测试不需要画面顿帧，避免拖慢物理步进与测试时长。
	if DisplayServer.get_name() == "headless":
		return
	Engine.time_scale = 0.12
	hitstop_timer.start(maxf(hitstop_timer.time_left, seconds))


func end_hitstop() -> void:
	Engine.time_scale = 1.0


## 结算或离场时回收顿帧计时与时间缩放，避免结算界面或下个场景继续慢放。
func reset_time_scale() -> void:
	if hitstop_timer != null and is_instance_valid(hitstop_timer):
		hitstop_timer.stop()
	Engine.time_scale = 1.0


## 纯计算：受击红屏透明度随本次扣血线性上升并夹在 [0.10, 0.34]。
static func calc_hurt_flash_alpha(hp_damage: int) -> float:
	return clampf(0.10 + float(hp_damage) / 160.0, 0.10, 0.34)


## 玩家受击：血量越掉越多，红屏越明显。
func flash_hurt(hp_damage: int) -> void:
	if hurt_flash_rect == null or not is_instance_valid(hurt_flash_rect):
		return
	var alpha := calc_hurt_flash_alpha(hp_damage)
	hurt_flash_rect.color = Color(0.72, 0.04, 0.04, alpha)
	var tw := hurt_flash_rect.create_tween()
	tw.tween_property(hurt_flash_rect, "color:a", 0.0, 0.34)


## 玩家受击完整反馈：护甲/生命分开飘字，真正掉血时红屏 + 抖屏，并刷新 HUD 护甲条。
func on_player_damaged(armor_damage: int, hp_damage: int, pos: Vector2) -> void:
	if _fx_layer != null:
		if armor_damage > 0:
			DamageNumber2D.spawn(_fx_layer, pos + Vector2(-16, -6), armor_damage,
				Color(0.45, 0.72, 1.0), "armor")
		if hp_damage > 0:
			DamageNumber2D.spawn(_fx_layer, pos + Vector2(12, 4), hp_damage,
				Color(1.0, 0.42, 0.38), "flesh", true)
	if hp_damage > 0:
		# 真正掉血才红屏 + 抖屏，纯破甲只飘蓝字，避免一直闪。
		flash_hurt(hp_damage)
		add_shake(2.2, 0.3, 24.0)
	if _hud != null and _doll != null:
		_hud.set_armor(_doll.armor, _doll.armor_max)


## 预创建常驻枪口火光与局部点亮节点（以及保留兼容的 PixelFx2D 节点），零运行时分配卡顿。
func warm_muzzle_fx() -> void:
	if _fx_layer == null:
		return
	if muzzle_flash == null or not is_instance_valid(muzzle_flash):
		muzzle_flash = MUZZLE_FLASH.new()
		muzzle_flash.name = "MuzzleFlash2D"
		_fx_layer.add_child(muzzle_flash)
	muzzle_fx = Shot2D.pixel_fx(_fx_layer, "projectiles/muzzle-pistol",
		Vector2.ZERO, 0.0, 60, 1.0, PixelFx2D.Mode.BAKED)
	if muzzle_fx == null:
		return
	muzzle_fx.free_when_done = false
	muzzle_fx.modulate.a = 0.0
	muzzle_fx.stop()


func play_muzzle_fx(pos: Vector2, angle: float, intensity := 1.0, suppressed := false) -> void:
	if _fx_layer == null:
		return
	if muzzle_flash == null or not is_instance_valid(muzzle_flash):
		warm_muzzle_fx()
	if muzzle_flash != null and is_instance_valid(muzzle_flash):
		muzzle_flash.trigger(pos, angle, intensity, suppressed)
	if muzzle_fx != null and is_instance_valid(muzzle_fx):
		if suppressed:
			muzzle_fx.stop()
			muzzle_fx.modulate.a = 0.0
		else:
			muzzle_fx.global_position = pos + Vector2(0.0, MUZZLE_FX_GROUND).rotated(angle)
			muzzle_fx.rotation = angle
			muzzle_fx.scale = Vector2.ONE * clampf(intensity * 0.85, 0.65, 1.25)
			muzzle_fx.play()
			muzzle_fx.modulate.a = 0.45
			_muzzle_stop_ms = Time.get_ticks_msec() + 260


## 每帧把活跃中的枪口特效贴回当前枪口位置与枪管朝向，超时自动停止。
func update_muzzle_fx() -> void:
	if _doll == null:
		return
	var barrel_angle := 0.0
	if _doll.weapon_rig != null:
		barrel_angle = _doll.weapon_rig.get_barrel_direction().angle()
	var cur_muzzle := _doll.get_muzzle_position()
	if muzzle_flash != null and is_instance_valid(muzzle_flash) and muzzle_flash.is_active():
		muzzle_flash.sync_muzzle(cur_muzzle, barrel_angle)
	if muzzle_fx == null or not is_instance_valid(muzzle_fx) or not muzzle_fx.is_playing():
		return
	muzzle_fx.global_position = cur_muzzle \
		+ Vector2(0.0, MUZZLE_FX_GROUND).rotated(barrel_angle)
	muzzle_fx.global_rotation = barrel_angle
	if Time.get_ticks_msec() >= _muzzle_stop_ms:
		muzzle_fx.stop()


## 开局预热命中/击杀特效与命中采样：把首次战斗的一次性加载成本提前分摊掉。
func warm_combat_fx() -> void:
	if DisplayServer.get_name() == "headless" or _owner == null:
		return
	var sfx := _owner.get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("warm_impact_samples"):
		sfx.warm_impact_samples()
	var warmup := COMBAT_FX_WARMUP.new()
	warmup.name = "CombatFxWarmup"
	_owner.add_child(warmup)
	var variants := HIT_FX.impact_variants()
	variants.push_front({"id": "projectiles/muzzle-pistol", "opts": {}})
	warmup.setup(variants)
	warm_damage_fonts()


## 伤害跳字使用 15/17/19/21/23 号字与 4px 描边，首次出现才光栅化会卡一下；
## 先在不可见状态下画一帧，把字形与描边预热进字体缓存。
func warm_damage_fonts() -> void:
	if DisplayServer.get_name() == "headless" or _owner == null or not _owner.is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = -8
	_owner.add_child(layer)
	var row := HBoxContainer.new()
	row.modulate.a = 0.0
	layer.add_child(row)
	for size in [15, 17, 19, 21, 23]:
		var label := Label.new()
		label.text = "-0123456789"
		label.add_theme_font_override("font", PixelUI.FONT)
		label.add_theme_font_size_override("font_size", size)
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.02, 0.95))
		label.add_theme_constant_override("outline_size", 4)
		row.add_child(label)
	await _owner.get_tree().process_frame
	if is_instance_valid(layer):
		layer.queue_free()


## 立即套用弹道线条开关：只隐藏枪口到弹丸的长线，弹丸实体与命中不受影响。
func apply_bullet_trail_setting(enabled: bool) -> void:
	if _fx_layer == null:
		return
	var bullets: Array = []
	for child in _fx_layer.get_children():
		if child is PlayerBullet2D:
			bullets.append(child)
		elif child.has_meta("bullet_trail"):
			child.visible = enabled
	# 单独处理子弹：重新开启时可能需要在子弹当前位置补建线条。
	for bullet in bullets:
		bullet.set_trail_visible(enabled)


func play_sfx(kind: String, volume_db := 0.0) -> void:
	if _owner == null:
		return
	var sfx := _owner.get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play_2d(kind, volume_db, randf_range(0.96, 1.04))
