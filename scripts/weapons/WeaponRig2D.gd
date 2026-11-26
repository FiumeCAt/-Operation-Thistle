extends Node2D
class_name WeaponRig2D

## 2D 持枪表现协调入口：管理枪身/手臂/支撑臂/枪口焰/弹匣节点、输入与信号转发。
## 供弹/换弹/切枪/收拔枪状态机委托至 WeaponFeedState2D；
## 武器贴图度量、双臂 IK、枪管对齐、层级判定与姿态叠加委托至 WeaponPoseIK2D。

signal fired(muzzle_global: Vector2, direction: Vector2)
signal weapon_switched(id: StringName)
signal reload_finished
signal holstered_changed(stowed: bool)
signal fire_mode_changed(mode: String, supported: bool)
signal ammo_switched(ammo_id: StringName)

const UNITS := preload("res://scripts/core/GameUnits.gd")
const STATS_MODEL := preload("res://scripts/weapons/WeaponStatsModel.gd")
const FEED_STATE := preload("res://scripts/weapons/WeaponFeedState2D.gd")
const POSE_IK := preload("res://scripts/weapons/WeaponPoseIK2D.gd")

const UPPER_ARM_TEX := preload("res://assets/art/characters/doll_b/parts/arm2/upper_arm.png")
const FOREARM_TEX := preload("res://assets/art/characters/doll_b/parts/arm2/forearm.png")
const HAND_TEX := preload("res://assets/art/characters/doll_b/parts/arm2/hand.png")
const FLASH_TEX := preload("res://assets/art/weapons/fx/flash_strip.png")
const MAG_TEX := preload("res://assets/art/weapons/fx/mag_pistol.png")
const SHELL_TEX := preload("res://assets/art/weapons/fx/mag_shell.png")

## 枪械贴图视觉缩放标尺（game_units_test 校验常量，仅用于视觉缩放，与世界 64 px/m 解耦）。
const SPRITE_PX_PER_METER := POSE_IK.SPRITE_PX_PER_METER
const ARM_SCALE := POSE_IK.ARM_SCALE
const ARM_LENGTH := POSE_IK.ARM_LENGTH
const BEHIND_Z := POSE_IK.BEHIND_Z
const FRONT_Z := POSE_IK.FRONT_Z

const RECOIL_DISTANCE := 3.2
const RECOIL_RETURN := 13.0
const RECOIL_KICK := 0.05
const FLASH_TIME := 0.06
const FLASH_SCALE := 0.55
const TURN_SPEED := 22.0
const MAG_SCALE := 0.7
const SPRINT_DIP := 3.0
const ADS_ARM_LENGTH := 18.0
const ADS_LIFT := 5.0
const ADS_BLEND_SPEED := 12.0
const ELBOW_TURN_SPEED := 9.0

var feed: WeaponFeedState2D = FEED_STATE.new()

## 供弹/换弹/切枪/收拔枪状态（委托至 WeaponFeedState2D，保留既有属性接口）。
var weapon_id: StringName:
	get: return feed.weapon_id
	set(v): feed.weapon_id = v
var loadout: Array[StringName]:
	get: return feed.loadout
	set(v): feed.loadout = v
var data: WeaponData
var aim_world := Vector2.ZERO
var aim_enabled := true
## 可选回调：鼠标悬停在 HUD 交互按钮（如快慢机拨片）时拦截左键开火，避免切模式误射。
var fire_input_blocked_fn: Callable = Callable()
## 由 Doll2D 每帧写入：是否处于瞄准姿态、当前身体朝向。
var aiming := false
var body_direction := 0
var aim_angle := 0.0
var recoil := 0.0
var cooldown: float:
	get: return feed.cooldown
	set(v): feed.cooldown = v
var shots: int:
	get: return feed.shots
	set(v): feed.shots = v
## 配件汇总后的伤害、散布、后坐、视野与瞄具倍率。
var damage_mul := 1.0
var spread_mul := 1.0
var recoil_mul := 1.0
var vision_mul := 1.0
var ads_speed_mul := 1.0
var ads_time := 0.24
var muzzle_flash_mode := "partial"
var has_laser := false
var has_suppressor := false
var sight_magnification := 1.0
var sight_look_ahead_mul := 1.0
var sight_reticle := "iron"
var sight_ads_time_mul := 1.0
var has_scope_sight := false
var aim_zoom_mul := 1.0

var mag: int:
	get: return feed.mag
	set(v): feed.mag = v
var reserve: Dictionary:
	get: return feed.reserve
	set(v): feed.reserve = v
var reload_t: float:
	get: return feed.reload_t
	set(v): feed.reload_t = v
var reload_total: float:
	get: return feed.reload_total
	set(v): feed.reload_total = v
var reload_time_mul: float:
	get: return feed.reload_time_mul
	set(v): feed.reload_time_mul = v
var reserve_talent_mul: float:
	get: return feed.reserve_talent_mul
	set(v): feed.reserve_talent_mul = v
var hold_reload_enabled: bool:
	get: return feed.hold_reload_enabled
	set(v): feed.hold_reload_enabled = v
var switch_t: float:
	get: return feed.switch_t
	set(v): feed.switch_t = v
var sprinting := false
var dodging := false
var ads := false
var _ads_t := 0.0
var _prev_ads := false
var _cycle_sfx_t := 0.0
var _last_empty_ms := 0
var holstered: bool:
	get: return feed.holstered
	set(v): feed.holstered = v

var _pivot: Node2D
var _gun: Sprite2D
var _muzzle: Marker2D
var _flash: Sprite2D
var _upper_arm: Sprite2D
var _forearm: Sprite2D
var _hand: Sprite2D
var _support_root: Node2D
var _support_upper: Sprite2D
var _support_forearm: Sprite2D
var _support_hand: Sprite2D
var _mag_sprite: Sprite2D

var _wrist_local := Vector2.ZERO
var _barrel_angle := 0.0
var _gun_len := 20.0
var _elbow_sign := 1.0
var _kick := 0.0
var _flash_timer := 0.0
var _grip_px := Vector2.ZERO
var _muzzle_px := Vector2.ZERO
var _tex_size := Vector2.ZERO
var _gun_scale := 1.0
var _flipped := false
var _behind := false


func _ready() -> void:
	setup(weapon_id)


## 把当前武器的配件效果汇总到全新克隆的 WeaponData（绝不原地污染基础模板）。
func _apply_mods() -> void:
	damage_mul = 1.0
	spread_mul = 1.0
	recoil_mul = 1.0
	vision_mul = 1.0
	ads_speed_mul = 1.0
	ads_time = clampf(data.ads_time, 0.05, 1.50) if data != null else 0.24
	has_laser = false
	has_suppressor = false
	sight_magnification = 1.0
	sight_look_ahead_mul = 1.0
	sight_reticle = "iron"
	sight_ads_time_mul = 1.0
	has_scope_sight = false
	aim_zoom_mul = 1.0
	if data == null:
		return
	var progress := get_node_or_null("/root/Progress")
	if progress != null:
		if progress.has_method("muzzle_flash_mode"):
			muzzle_flash_mode = String(progress.muzzle_flash_mode())
		elif progress.data is Dictionary:
			muzzle_flash_mode = String(progress.data.get("muzzle_flash_mode", "partial"))
	if progress == null or not progress.has_method("weapon_mods_2d"):
		has_suppressor = weapon_id == &"vss"
		return
	var stats: Dictionary = STATS_MODEL.compute_for_progress(weapon_id, progress)
	damage_mul = float(stats["damage_mul"])
	spread_mul = float(stats["spread_mul"])
	recoil_mul = float(stats["recoil_mul"])
	vision_mul = float(stats["vision_mul"])
	ads_speed_mul = float(stats["ads_speed_mul"])
	ads_time = float(stats["ads_time"])
	sight_ads_time_mul = float(stats["sight_ads_time_mul"])
	has_laser = bool(stats["has_laser"])
	has_suppressor = bool(stats.get("has_suppressor", false))
	sight_magnification = float(stats["sight_magnification"])
	sight_look_ahead_mul = float(stats["sight_look_ahead_mul"])
	sight_reticle = String(stats["sight_reticle"])
	has_scope_sight = bool(stats["has_scope_sight"])
	aim_zoom_mul = float(stats["aim_zoom_mul"])
	data = STATS_MODEL.build_weapon_data(data, stats)


## 换装一把枪：读取 meta.json 的握把/枪口像素锚点，重建视觉节点并恢复独立弹匣数。
func setup(id: StringName) -> void:
	weapon_id = id
	data = WeaponDB.get_weapon(id)
	_apply_mods()
	var m := POSE_IK.load_weapon_metrics(id, data.visual_length)
	var tex: Texture2D = m["tex"]
	_barrel_angle = float(m["barrel_angle"])
	_gun_scale = float(m["gun_scale"])
	_gun_len = float(m["gun_len"])
	_grip_px = m["grip_px"]
	_muzzle_px = m["muzzle_px"]
	_tex_size = m["tex_size"]
	_flipped = false

	_clear_nodes()
	_pivot = Node2D.new()
	_pivot.name = "Pivot"
	_pivot.position = _current_anchor()
	add_child(_pivot)

	_gun = Sprite2D.new()
	_gun.name = "Gun"
	_gun.texture = tex
	_gun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_gun.scale = Vector2.ONE * _gun_scale
	_pivot.add_child(_gun)
	_align_gun(false)

	_upper_arm = _make_limb(_pivot, "UpperArm", UPPER_ARM_TEX)
	_forearm = _make_limb(_pivot, "Forearm", FOREARM_TEX)
	_hand = _make_hand(_pivot, "Hand")

	_muzzle = Marker2D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector2(ARM_LENGTH + _gun_len, 0)
	_pivot.add_child(_muzzle)

	_flash = Sprite2D.new()
	_flash.name = "Flash"
	_flash.texture = FLASH_TEX
	_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flash.hframes = 3
	_flash.scale = Vector2.ONE * FLASH_SCALE
	_flash.position = Vector2(ARM_LENGTH + _gun_len + 2.0, 0)
	_apply_flash_modulate()
	_flash.visible = false
	_pivot.add_child(_flash)

	_mag_sprite = Sprite2D.new()
	_mag_sprite.name = "Magazine"
	_mag_sprite.texture = MAG_TEX if data.feed_mode == &"mag" else SHELL_TEX
	_mag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mag_sprite.scale = Vector2.ONE * MAG_SCALE
	_mag_sprite.visible = false
	add_child(_mag_sprite)

	_support_root = Node2D.new()
	_support_root.name = "SupportPivot"
	add_child(_support_root)
	_support_upper = _make_limb(_support_root, "SupportUpperArm", UPPER_ARM_TEX)
	_support_forearm = _make_limb(_support_root, "SupportForearm", FOREARM_TEX)
	_support_hand = _make_hand(_support_root, "SupportHand")
	_support_root.visible = false

	feed.on_weapon_equipped(id, data.mag_capacity, data)
	_update_layer()
	_apply_pose()


func _make_limb(parent: Node2D, node_name: String, tex: Texture2D) -> Sprite2D:
	var limb := Sprite2D.new()
	limb.name = node_name
	limb.texture = tex
	limb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	limb.scale = Vector2.ONE * ARM_SCALE
	limb.offset = Vector2(tex.get_width() * 0.5, 0.0)
	parent.add_child(limb)
	return limb


func _make_hand(parent: Node2D, node_name: String) -> Sprite2D:
	var hand := Sprite2D.new()
	hand.name = node_name
	hand.texture = HAND_TEX
	hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hand.scale = Vector2.ONE * ARM_SCALE
	parent.add_child(hand)
	return hand


func _clear_nodes() -> void:
	# 先移出场景树再 queue_free：避免同名新节点被改名成 Pivot2/Gun2。
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _process(delta: float) -> void:
	if data == null:
		return
	var ev := feed.tick(delta, data)
	var swap_id: StringName = ev["switch_swap"]
	if swap_id != &"":
		setup(swap_id)
		weapon_switched.emit(swap_id)
	if bool(ev["reload_finished"]):
		reload_finished.emit()
	var switched_ammo: StringName = ev.get("ammo_switched", &"")
	if switched_ammo != &"":
		ammo_switched.emit(switched_ammo)
	if bool(ev["holster_completed"]):
		holstered_changed.emit(true)

	if aim_enabled and aim_world != Vector2.ZERO and not holstered:
		var target := (aim_world - global_position).angle()
		aim_angle = wrapf(
			lerp_angle(aim_angle, target, clampf(TURN_SPEED * delta, 0.0, 1.0)),
			-PI, PI)
	var elbow_target := 1.0 if Vector2.from_angle(aim_angle + PI * 0.5).dot(Vector2.DOWN) >= 0.0 else -1.0
	_elbow_sign = move_toward(_elbow_sign, elbow_target, ELBOW_TURN_SPEED * delta)
	if recoil > 0.0:
		recoil = maxf(recoil - RECOIL_RETURN * delta, 0.0)
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		_flash.frame = 0 if _flash_timer > FLASH_TIME * 0.5 else 1
		if _flash_timer <= 0.0:
			_flash.visible = false
	_update_layer()
	var ads_rate := get_ads_rate()
	var dbg_progress := get_node_or_null("/root/Progress")
	if dbg_progress != null and dbg_progress.has_method("debug_mul"):
		ads_rate *= float(dbg_progress.debug_mul("ads"))
	var want_ads := ads and not holstered
	if want_ads != _prev_ads:
		_prev_ads = want_ads
		_play_weapon_action_sfx("ads_in" if want_ads else "ads_out", -14.5)
	if _cycle_sfx_t > 0.0:
		_cycle_sfx_t -= delta
		if _cycle_sfx_t <= 0.0:
			_play_weapon_action_sfx("cycle", -8.5)
	_ads_t = move_toward(_ads_t, 1.0 if want_ads else 0.0, ads_rate * delta)
	_apply_pose()

	if InputMap.has_action("holster") and Input.is_action_just_pressed("holster"):
		toggle_holster()
	if InputMap.has_action("fire_mode") and Input.is_action_just_pressed("fire_mode"):
		toggle_fire_mode()
	if InputMap.has_action("ammo_switch") and Input.is_action_just_pressed("ammo_switch"):
		switch_ammo()
	if InputMap.has_action("reload"):
		if Input.is_action_just_pressed("reload"):
			reload()
		elif Input.is_action_pressed("reload"):
			process_hold_reload()
	var fire_blocked := fire_input_blocked_fn.is_valid() and bool(fire_input_blocked_fn.call())
	if InputMap.has_action("fire") and not fire_blocked:
		if is_auto_mode():
			if Input.is_action_pressed("fire"):
				try_fire()
		elif Input.is_action_just_pressed("fire"):
			try_fire()


func _unhandled_input(event: InputEvent) -> void:
	if data == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var index := int(event.physical_keycode) - int(KEY_1)
		if index >= 0 and index < loadout.size():
			if switch_to(loadout[index]):
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if InputMap.has_action("view_zoom") and Input.is_action_pressed("view_zoom"):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(-1)


## --- 姿态、IK 与挂点坐标（委托至 WeaponPoseIK2D）-----------------------------

func _align_gun(flip: bool) -> void:
	_flipped = flip
	POSE_IK.align_gun(_gun, _muzzle, _wrist_local, _grip_px, _muzzle_px,
		_tex_size, _barrel_angle, _gun_scale, flip)


## 将侧视图上的任意像素坐标（如瞄具导轨/枪口/下挂槽位）转为当前 Pivot 局部坐标。
func get_mount_local(px: Vector2) -> Vector2:
	return POSE_IK.pixel_to_pivot(px, _grip_px, _barrel_angle, _gun_scale, _wrist_local, _flipped)


func get_stance_id() -> StringName:
	if data == null:
		return &"rifle"
	return POSE_IK.resolve_stance_id(data.category, data.visual_length)


func get_stance() -> Dictionary:
	return POSE_IK.get_stance(get_stance_id())


func _arm_length() -> float:
	var st := get_stance()
	return lerpf(float(st.get("hip_arm_len", ARM_LENGTH)),
		float(st.get("ads_arm_len", ADS_ARM_LENGTH)), _ads_t)


func get_ads_blend() -> float:
	return _ads_t


## 统一的开镜过渡速率（1 / 最终开镜秒数），供举枪姿态与 Main2D 镜头/散布共用。
func get_ads_rate() -> float:
	return 1.0 / maxf(ads_time, 0.05)


func set_muzzle_flash_mode(mode: String) -> void:
	muzzle_flash_mode = mode if ["full", "partial", "off"].has(mode) else "partial"
	_apply_flash_modulate()
	if muzzle_flash_mode == "off":
		_flash_timer = 0.0
		if _flash != null:
			_flash.visible = false


func _apply_flash_modulate() -> void:
	if _flash == null:
		return
	var alpha := 0.0 if muzzle_flash_mode == "off" \
		else (0.16 if has_suppressor else (0.72 if muzzle_flash_mode == "full" else 0.46))
	_flash.modulate = Color(1.0, 0.90, 0.72, alpha)


func _current_anchor() -> Vector2:
	return POSE_IK.shoulder_anchor(body_direction)


func _update_layer() -> void:
	_behind = POSE_IK.is_behind_body(aim_angle, body_direction)
	var target_z := BEHIND_Z if _behind else FRONT_Z
	if z_index != target_z:
		z_index = target_z


func _apply_pose() -> void:
	if _pivot == null:
		return
	var flip := absf(aim_angle) > PI * 0.5
	_wrist_local = POSE_IK.solve_primary_arm(_upper_arm, _forearm, _arm_length(), _elbow_sign)
	_align_gun(flip)
	if _hand != null:
		_hand.position = _wrist_local
		_hand.rotation = 0.0
		_hand.flip_v = _flipped
	if _flash != null:
		_flash.position = _muzzle.position + Vector2(2.0, 0.0)
	var st := get_stance()
	var ads_lift := float(st.get("ads_lift", ADS_LIFT))
	var shoulder_off: Vector2 = st.get("shoulder_offset", Vector2.ZERO)
	var kick_mul := float(st.get("recoil_kick_mul", 1.0))
	var anchor := _current_anchor() + shoulder_off - Vector2(0.0, ads_lift * _ads_t)
	_pivot.rotation = aim_angle + _kick * kick_mul * recoil * lerpf(1.0, 0.45, _ads_t)
	var toward_camera := clampf(Vector2.DOWN.dot(Vector2.from_angle(aim_angle)), 0.0, 1.0)
	var foreshorten := lerpf(1.0, 0.45, toward_camera)
	_pivot.scale = Vector2(foreshorten, 1.0)
	var back := Vector2.from_angle(aim_angle) * RECOIL_DISTANCE * recoil * lerpf(1.0, 0.6, _ads_t)
	_pivot.position = anchor - back
	if _flash != null:
		_flash.scale = Vector2(FLASH_SCALE / maxf(foreshorten, 0.01), FLASH_SCALE)

	var limbs := [_upper_arm, _forearm, _hand]
	POSE_IK.apply_reload_pose(_pivot, _mag_sprite, _current_anchor(), reload_t, reload_total)
	POSE_IK.apply_switch_pose(_pivot, _gun, limbs, _support_root, switch_t)
	POSE_IK.apply_stow_pose(_pivot, _gun, limbs, _support_root, _flash,
		holstered, feed.stow_t, feed.stow_total, feed.stow_kind)
	var sprint_dip := float(st.get("sprint_dip", SPRINT_DIP))
	if dodging and not holstered and feed.stow_t <= 0.0:
		_pivot.position.y += sprint_dip * 1.35
	elif sprinting and not aiming and not holstered and feed.stow_t <= 0.0:
		_pivot.position.y += sprint_dip
	var show_support := data != null and bool(st.get("support_arm", data.visual_length >= 0.5)) \
		and data.visual_length >= 0.5 \
		and (not holstered or feed.stow_t > 0.0)
	POSE_IK.solve_support_arm(_support_root, _support_upper, _support_forearm, _support_hand,
		_pivot, _current_anchor(), _wrist_local, _gun_len, _elbow_sign, _flipped, show_support,
		float(st.get("support_ratio", POSE_IK.SUPPORT_GRIP_RATIO)),
		float(st.get("support_lift", POSE_IK.SUPPORT_LIFT)))


## --- 供弹/动作接口（委托至 WeaponFeedState2D）--------------------------------

func try_fire() -> bool:
	if dodging:
		return false
	match feed.try_fire(data):
		&"need_draw":
			draw()
			return false
		&"need_reload":
			if not reload():
				var now := Time.get_ticks_msec()
				if now - _last_empty_ms >= 220:
					_last_empty_ms = now
					_play_weapon_action_sfx("empty", -7.5)
			return false
		&"fired":
			recoil = recoil_mul
			_kick = -RECOIL_KICK + randf_range(-0.015, 0.015)
			if not has_suppressor and muzzle_flash_mode != "off":
				_flash_timer = FLASH_TIME
				_flash.visible = true
				_flash.frame = 0
			if data != null and (data.category == &"sniper" or (data.feed_mode == &"shell" and not data.auto_cycle)):
				_cycle_sfx_t = 0.16 if data.category == &"sniper" else 0.12
			fired.emit(get_muzzle_position(), Vector2.from_angle(aim_angle))
			return true
		_:
			return false

func reload() -> bool:
	var ok := feed.reload(data)
	if ok:
		_play_weapon_action_sfx("reload", -8.5)
	return ok

func process_hold_reload() -> void:
	if feed.process_hold_reload(data):
		_play_weapon_action_sfx("reload", -9.0)

func get_pending_ammo_id() -> StringName: return feed.pending_ammo_id


func switch_ammo(step := 1) -> Dictionary:
	var res := feed.start_ammo_switch(data, step)
	if bool(res.get("ok", false)):
		_play_weapon_action_sfx("ammo_switch", -8.0, 1.06 if not bool(res.get("cancelled", false)) else 0.86)
	return res

func switch_to(id: StringName) -> bool:
	var result := feed.start_switch(id, data)
	if result == &"rejected":
		return false
	_cycle_sfx_t = 0.0
	if _mag_sprite != null:
		_mag_sprite.visible = false
	_play_stow_sfx()
	if result == &"instant_holstered":
		setup(id)
		weapon_switched.emit(id)
	return true

func _cycle_weapon(step: int) -> void:
	var next_id := feed.cycle_target(step)
	if next_id != &"":
		switch_to(next_id)

func get_reserve() -> int: return feed.get_reserve(data)
func apply_reserve_talent(mul: float) -> void: feed.apply_reserve_talent(mul)
func refill_all_ammo() -> void: feed.refill_all_ammo(data)
func get_reload_progress() -> float: return feed.get_reload_progress()
func get_stow_progress() -> float: return feed.get_stow_progress()

func holster() -> bool:
	if not feed.holster():
		return false
	if _flash != null:
		_flash.visible = false
	_play_stow_sfx()
	return true

func draw() -> bool:
	if not feed.draw():
		return false
	_play_stow_sfx()
	holstered_changed.emit(false)
	return true

func toggle_holster() -> bool: return draw() if holstered else holster()
func is_holstered() -> bool: return feed.holstered
func is_stowing() -> bool: return feed.is_stowing()
func is_drawing() -> bool: return feed.is_drawing()
func is_busy() -> bool: return feed.is_busy()
func supports_full_auto() -> bool: return feed.supports_full_auto(data)
func get_fire_mode() -> String: return feed.get_fire_mode(data)
func is_auto_mode() -> bool: return feed.is_auto_mode(data)


func set_fire_mode(mode: String) -> bool:
	var ok := feed.set_fire_mode(data, mode)
	if ok:
		fire_mode_changed.emit(get_fire_mode(), supports_full_auto())
	return ok


func toggle_fire_mode() -> Dictionary:
	var res := feed.toggle_fire_mode(data)
	var changed := bool(res.get("changed", false))
	var supported := bool(res.get("supported", false))
	_play_fire_select_sfx(1.0 if changed else 0.78)
	fire_mode_changed.emit(String(res.get("mode", "semi")), supported)
	return res


func _play_fire_select_sfx(pitch := 1.0) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.play_2d("fire_select", -8.0, pitch * randf_range(0.96, 1.04))
func get_ammo_text() -> String: return feed.get_ammo_text(data)
func get_side_texture() -> Texture2D: return _gun.texture if _gun != null else null
func get_stow_scale() -> float: return _gun_scale
func get_muzzle_position() -> Vector2: return _muzzle.global_position if _muzzle != null else global_position
func get_barrel_direction() -> Vector2: return Vector2.from_angle(aim_angle)
func get_barrel_angle() -> float: return _barrel_angle
func get_gun_length() -> float: return _gun_len

func get_grip_position() -> Vector2:
	return _pivot.to_global(_wrist_local) if _pivot != null else to_global(_current_anchor())

func _play_stow_sfx() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.play_2d("switch", -10.0, randf_range(0.95, 1.05))


func _play_weapon_action_sfx(action: String, volume_db := -8.5, pitch := 1.0) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("play_weapon_action"):
		sfx.play_weapon_action(action, data, volume_db, pitch)
