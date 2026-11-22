extends Node2D
class_name WeaponRig2D

## 2D 持枪表现：两段手臂（大臂 + 小臂）+ 手 + 枪合成一个绕肩旋转的整体。
## 腕固定在枪管轴线上，肩→肘→腕用两段 IK 解算，距离越近肘弯得越多。
## 整组随鼠标 360°，朝上 / 背向身体时整组切到身体后面。

signal fired(muzzle_global: Vector2, direction: Vector2)
signal weapon_switched(id: StringName)
signal reload_finished
signal holstered_changed(stowed: bool)

const META_PATH := "res://assets/art/weapons/%s/meta.json"
const TEX_PATH := "res://assets/art/weapons/%s/side.png"
## 手臂分件（tools/slice_arm_parts.py 从 image2.5 母版切出）。
const UPPER_ARM_TEX := preload("res://assets/art/characters/doll_b/parts/arm2/upper_arm.png")
const FOREARM_TEX := preload("res://assets/art/characters/doll_b/parts/arm2/forearm.png")
const HAND_TEX := preload("res://assets/art/characters/doll_b/parts/arm2/hand.png")
const FLASH_TEX := preload("res://assets/art/weapons/fx/flash_strip.png")
const MAG_TEX := preload("res://assets/art/weapons/fx/mag_pistol.png")
const SHELL_TEX := preload("res://assets/art/weapons/fx/mag_shell.png")

## 角色世界身高 128px 对应约 1.7m，用它把枪的真实长度换算成像素。
const WORLD_PER_METER := 128.0 / 1.7
## 像素风里手枪需要适度夸张，否则只有 15px 看不清；长枪按真实比例即可。
const SIZE_BOOST := 1.35
const LONG_GUN_BOOST := 1.0
## 手枪最短世界长度：低于这个值握持关系看不清，会显得枪浮在手边。
const MIN_GUN_LEN := 36.0
## 像素风里武器容易显得比角色还抢眼；统一缩到 0.8 倍，贴图本身不改。
const GUN_WORLD_SCALE := 0.6
## 分件和角色图集同比例（源图 2 倍 → 世界 0.5 倍）。
const ARM_SCALE := 0.5
## 两段骨架长度（源图 24px 长 → 世界 12px）。
const UPPER_ARM_LEN := 12.0
const FOREARM_LEN := 12.0
## 小臂向肘部多压一点，盖住两段之间的直切接缝。
const LIMB_OVERLAP := 1.5
## 肩点 → 手心 的世界距离：髋射接近伸直，ADS 收回一截。
const ARM_LENGTH := 22.8
## 四向的肩点（相对脚底）。站定瞄准用的是图集 idle 帧，外套肩线
## 在 -88 左右；两段 IK 手臂变细后可以贴回肩线，不再挡住脸。
## 背向（1）的肩点外移，让朝上的枪在头侧露出来，不会整把被身体挡死。
const SHOULDER := {
	0: Vector2(6.0, -88.0),
	1: Vector2(17.0, -90.0),
	2: Vector2(0.0, -88.0),
	3: Vector2(0.0, -88.0),
}

## 瞄准角落在这一区间（屏幕上方）时，武器画在身体后面。
const BEHIND_FROM := -2.356      # -135°
const BEHIND_TO := -0.785        # -45°
const BEHIND_Z := -1
const FRONT_Z := 2
## 身体四向对应的世界角度（0=下 1=上 2=左 3=右）。
## 枪指向身体背面超过 90° 时也切到身体后面，避免从胸口/手臂穿过去。
const BODY_ANGLE := {0: PI * 0.5, 1: -PI * 0.5, 2: PI, 3: 0.0}

const RECOIL_DISTANCE := 3.2
const RECOIL_RETURN := 13.0
const RECOIL_KICK := 0.05
const FLASH_TIME := 0.06
const FLASH_SCALE := 0.55
const TURN_SPEED := 22.0
## 换弹：枪下压 + 弹匣掉落/插入的动画参数
const RELOAD_DIP := 14.0
const RELOAD_TILT := 0.5
const MAG_SCALE := 0.7
## 切枪：枪沉下去 → 换模型 → 抬起来
const SWITCH_TIME := 0.36
const SWITCH_DIP := 24.0
const SWITCH_TILT := 0.45
## 收枪 / 拔枪：枪向下沉并淡出，拔枪时反向抬起。
const HOLSTER_TIME := 0.22
const DRAW_TIME := 0.26
const STOW_DIP := 22.0
const STOW_TILT := 0.5
## 冲刺时枪口压低一点，表现“持枪冲刺”而不是举枪瞄准。
const SPRINT_DIP := 3.0
## 右键瞄准：手臂收到胸前、抬高一档，后坐与枪口抖动减弱。
const ADS_ARM_LENGTH := 18.0
const ADS_LIFT := 5.0
const ADS_BLEND_SPEED := 12.0
## 肘部换向速度：扫过正上/正下时让手臂先伸直再弯到另一侧，避免瞬间翻面。
const ELBOW_TURN_SPEED := 9.0
## 长枪支撑手：托住握把前方的护木。24px 的单臂够不到长枪护木，
## 支撑臂允许按目标距离适度拉长袖子，手掌始终贴在护木上。
const SUPPORT_GRIP_RATIO := 0.18
const SUPPORT_LIFT := -2.0
## 支撑肩从主肩略偏后侧伸出，避免背向朝上时手臂横穿头部。
const SUPPORT_SHOULDER_OFFSET := Vector2(-4.0, 1.0)
const SUPPORT_MIN_SEG := 12.0
const SUPPORT_MAX_SEG := 28.0
## 大臂 / 小臂贴图在 ARM_SCALE 下的世界长度，用于换算拉伸比例。
const SUPPORT_UPPER_BASE := 13.0
const SUPPORT_FORE_BASE := 13.5

var weapon_id: StringName = &"g17"
## 本局携带的武器（1-2 把）；数字键 1/2 与滚轮只在其中循环。
var loadout: Array[StringName] = [&"m870", &"m1014", &"saiga12k", &"g17"]
var data: WeaponData
var aim_world := Vector2.ZERO
var aim_enabled := true
## 由 Doll2D 每帧写入：是否处于瞄准姿态、当前身体朝向。
var aiming := false
var body_direction := 0
var aim_angle := 0.0
var recoil := 0.0
var cooldown := 0.0
var shots := 0
## 配件汇总后的伤害与散布倍率；由 setup 时读取 Progress 装配表写入。
var damage_mul := 1.0
var spread_mul := 1.0
## 后托/握把：后坐力倍率（连发散布增长、上限、开火震动）。
var recoil_mul := 1.0
## 瞄具：玩家视野距离倍率，由 VisionFog2D 每帧读取。
var vision_mul := 1.0
## 下挂激光：瞄准过渡速度倍率。
var ads_speed_mul := 1.0
## 是否装备可见激光。
var has_laser := false
## 瞄具：标定倍率、准心类型、是否使用镜内放大视野。
var sight_magnification := 1.0
var sight_reticle := "iron"
## 瞄具的瞄准时间倍率（>1 表示开镜更慢）。
var sight_ads_time_mul := 1.0
var has_scope_sight := false
## 瞄准时主镜头放大倍率：非高倍镜按瞄具标定倍率放大（1.0 = 不额外放大）。
var aim_zoom_mul := 1.0

## 供弹状态：每把枪各自保存弹匣数，备弹按通用弹药种类共享。
var mag := 0
## category(light/medium/heavy/shotgun/special) → 备弹数量。
var reserve: Dictionary = {}
var reload_t := 0.0
var reload_total := 0.0
## 2D 天赋「快速换弹」的比例；1.0 为原始换弹时间。
var reload_time_mul := 1.0
## 备弹天赋倍率；浪潮补满弹药时沿用，避免回满反而比开局少。
var reserve_talent_mul := 1.0
## 「持续装填」天赋：解锁后按住 R 可为管仓武器逐发续装。
var hold_reload_enabled := false
var switch_t := 0.0
## 冲刺时由 Doll2D 写入：枪保持在手，但压低一点。
var sprinting := false
## 右键瞄准（ADS）由 Doll2D 写入；0→1 平滑过渡。
var ads := false
var _ads_t := 0.0
## 收枪状态：holstered 为 true 时武器只显示在背后的挂点上。
var holstered := false
var _stow_t := 0.0
var _stow_total := 0.0
var _stow_kind := 0  # -1 收枪，1 拔枪

var _pivot: Node2D
var _gun: Sprite2D
var _muzzle: Marker2D
var _flash: Sprite2D
var _upper_arm: Sprite2D
var _forearm: Sprite2D
var _hand: Sprite2D
## 长枪的第二条手臂链（支撑手），挂在身体上而不是枪的 Pivot 上。
var _support_root: Node2D
var _support_upper: Sprite2D
var _support_forearm: Sprite2D
var _support_hand: Sprite2D
## 腕（手心）在 Pivot 局部空间的位置，由 IK 每帧解算。
var _wrist_local := Vector2.ZERO
var _mag_sprite: Sprite2D
## 贴图里枪管相对 +X 的角度（不是握把→枪口连线）。
var _barrel_angle := 0.0
var _gun_len := 20.0
## 肘部弯向：+1/-1，换向时平滑经过 0（直臂）。
var _elbow_sign := 1.0
var _kick := 0.0
var _flash_timer := 0.0
var _pending_id: StringName = &""
var _mag_by_id := {}
var _grip_px := Vector2.ZERO
var _muzzle_px := Vector2.ZERO
var _tex_size := Vector2.ZERO
var _gun_scale := 1.0
var _flipped := false
## 当前是否因为朝向原因把武器画在身体后面（远侧手需要一起隐藏）。
var _behind := false


func _ready() -> void:
	setup(weapon_id)


## 把当前武器的配件效果汇总到 WeaponData；每次 setup/换枪都会重新计算。
func _apply_mods() -> void:
	damage_mul = 1.0
	spread_mul = 1.0
	recoil_mul = 1.0
	vision_mul = 1.0
	ads_speed_mul = 1.0
	has_laser = false
	sight_magnification = 1.0
	sight_reticle = "iron"
	sight_ads_time_mul = 1.0
	has_scope_sight = false
	aim_zoom_mul = 1.0
	if data == null:
		return
	var progress := get_node_or_null("/root/Progress")
	if progress == null or not progress.has_method("weapon_mods_2d"):
		return
	var installed: Dictionary = progress.weapon_mods_2d(weapon_id)
	var mods := ModDB.modifiers(installed, false, String(weapon_id))
	# 天赋「弹匣扩容」按比例增加弹匣容量。
	var talent_mag := 1.0
	if progress.has_method("talent_2d_level"):
		talent_mag = 1.0 + float(progress.talent_2d_level(&"magazine")) * 0.08
	damage_mul = float(mods["damage_mul"])
	spread_mul = float(mods["spread_mul"])
	recoil_mul = clampf(float(mods["recoil_mul"]), 0.2, 1.5)
	vision_mul = clampf(float(mods["vision_mul"]), 1.0, 2.2)
	ads_speed_mul = clampf(float(mods["ads_speed_mul"]), 1.0, 2.0)
	sight_ads_time_mul = clampf(float(mods.get("ads_time_mul", 1.0)), 1.0, 2.0)
	has_laser = bool(mods.get("laser", false))
	# 瞄具的标定倍率/准心是字符串型元数据，不参与 ModDB 的倍率叠乘。
	var sight := ModDB.option(
		"sight", String(installed.get("sight", "")), false, String(weapon_id))
	if not sight.is_empty():
		sight_magnification = clampf(float(sight.get("magnification", 1.0)), 1.0, 8.0)
		sight_reticle = String(sight.get("reticle", "iron"))
		has_scope_sight = bool(sight.get("scope", false))
		# 准星切换：玩家在改枪界面为这个瞄具选择的样式优先。
		if progress.has_method("reticle_style"):
			sight_reticle = String(progress.reticle_style(
				String(installed.get("sight", "")), sight_reticle))
	# 非高倍镜的 ADS 主镜头放大跟瞄具标定倍率一致（红点 1.1×、全息 1.5×）。
	aim_zoom_mul = sight_magnification
	data.load_time = maxf(0.05, data.load_time * float(mods["reload_mul"]))
	data.fire_interval = maxf(0.03, data.fire_interval * float(mods["fire_mul"]))
	data.range_m *= float(mods["range_mul"])
	data.sound_radius *= float(mods["sound_mul"])
	# 后坐力：连发散布增长/上限与开火镜震一起压低。
	data.spread_growth *= recoil_mul
	data.spread_max *= recoil_mul
	data.shake_amount *= recoil_mul

	# 弹匣是独立基础配件：容量取绝对值，最后再叠天赋倍率。
	var magazine := ModDB.option("magazine", String(installed.get("magazine", "")), false, String(weapon_id))
	if not magazine.is_empty():
		var mag_fx: Dictionary = magazine.get("effects", {})
		if mag_fx.has("capacity"):
			data.mag_capacity = int(mag_fx["capacity"])
	data.mag_capacity = maxi(1, int(round(float(data.mag_capacity) * talent_mag)))

	# 枪机专属改件：全自动 / 固定射速。武器自带全自动（G18/AKM 等）保留。
	data.auto_fire = data.default_auto_fire
	var core := ModDB.option("core", String(installed.get("core", "")), false, String(weapon_id))
	if not core.is_empty():
		var core_fx: Dictionary = core.get("effects", {})
		if core_fx.has("fire_interval_set"):
			data.fire_interval = maxf(0.03, float(core_fx["fire_interval_set"]))
		if bool(core_fx.get("full_auto", false)):
			data.auto_fire = true


## 换装一把枪：读取 meta.json 的握把/枪口像素锚点，重建节点。
func setup(id: StringName) -> void:
	weapon_id = id
	data = WeaponDB.get_weapon(id)
	_apply_mods()
	var grip_px := Vector2.ZERO
	var muzzle_px := Vector2.ZERO
	var barrel_angle := 0.0
	var has_barrel := false
	var path := META_PATH % id
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			grip_px = Vector2(parsed.grip_px[0], parsed.grip_px[1])
			muzzle_px = Vector2(parsed.muzzle_px[0], parsed.muzzle_px[1])
			if parsed.has("barrel_angle_deg"):
				barrel_angle = deg_to_rad(float(parsed.barrel_angle_deg))
				has_barrel = true
	if grip_px == Vector2.ZERO:
		grip_px = Vector2(276, 552)
		muzzle_px = Vector2(1361, 99)

	var tex: Texture2D = load(TEX_PATH % id)
	# 枪管方向必须用贴图里的枪管轴，而不是握把→枪口连线：
	# 手枪的握把在枪管下方一大截，用连线会把整把枪抬翘近 20°。
	_barrel_angle = barrel_angle if has_barrel else (muzzle_px - grip_px).angle()
	var tex_len := (muzzle_px - grip_px).length()
	# 长枪不再额外放大，否则 M870 会和角色一样高
	var boost := SIZE_BOOST if data.visual_length < 0.5 else LONG_GUN_BOOST
	var world_len: float = data.visual_length * WORLD_PER_METER * boost
	# 手枪按真实比例只有 20px，在 128px 角色尺度下看不清握持关系，统一抬到可见长度
	world_len = maxf(world_len, MIN_GUN_LEN) * GUN_WORLD_SCALE
	_gun_scale = world_len / maxf(tex_len, 1.0)
	_gun_len = world_len
	_grip_px = grip_px
	_muzzle_px = muzzle_px
	_tex_size = Vector2(tex.get_width(), tex.get_height())
	_flipped = false

	_clear_nodes()
	# Pivot = 肩点；手臂、手、枪都挂在这里，整组一起旋转。
	# 子节点不再单独设 z_index：整组只保留一个层级，靠添加顺序决定
	# “枪 → 手臂/手 → 枪口焰”的叠压关系，否则切到身体后面时
	# 手臂的相对层级会等于身体层级，描边会透在外套上。
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

	_upper_arm = _make_limb("UpperArm", UPPER_ARM_TEX)
	_forearm = _make_limb("Forearm", FOREARM_TEX)
	_hand = Sprite2D.new()
	_hand.name = "Hand"
	_hand.texture = HAND_TEX
	_hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hand.scale = Vector2.ONE * ARM_SCALE
	_pivot.add_child(_hand)

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
	_flash.visible = false
	_pivot.add_child(_flash)

	_mag_sprite = Sprite2D.new()
	_mag_sprite.name = "Magazine"
	_mag_sprite.texture = MAG_TEX if data.feed_mode == &"mag" else SHELL_TEX
	_mag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mag_sprite.scale = Vector2.ONE * MAG_SCALE
	_mag_sprite.visible = false
	add_child(_mag_sprite)

	# 长枪的支撑臂：独立于枪的 Pivot，从身体肩点伸到护木。
	_support_root = Node2D.new()
	_support_root.name = "SupportPivot"
	add_child(_support_root)
	_support_upper = _make_support_limb("SupportUpperArm", UPPER_ARM_TEX)
	_support_forearm = _make_support_limb("SupportForearm", FOREARM_TEX)
	_support_hand = Sprite2D.new()
	_support_hand.name = "SupportHand"
	_support_hand.texture = HAND_TEX
	_support_hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_support_hand.scale = Vector2.ONE * ARM_SCALE
	_support_root.add_child(_support_hand)
	_support_root.visible = false

	# 每把枪保留自己的弹匣数，切回来时不会重置
	if not _mag_by_id.has(id):
		_mag_by_id[id] = data.mag_capacity
	mag = int(_mag_by_id[id])

	_update_layer()
	_apply_pose()


func _clear_nodes() -> void:
	# 先移出场景树再 queue_free：否则新旧节点同名，新节点会被改名成 Pivot2/Gun2，
	# 调试与测试里按名字取节点会直接失败。
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _process(delta: float) -> void:
	if data == null:
		return
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
	if switch_t > 0.0:
		var before := switch_t
		switch_t = maxf(switch_t - delta, 0.0)
		# 在动画最低点换模型，新旧枪交替正好被下沉遮住
		if before > SWITCH_TIME * 0.5 and switch_t <= SWITCH_TIME * 0.5 and _pending_id != &"":
			var next_id := _pending_id
			_pending_id = &""
			setup(next_id)
			weapon_switched.emit(next_id)
	if reload_t > 0.0:
		reload_t = maxf(reload_t - delta, 0.0)
		if reload_t <= 0.0:
			_finish_reload()
	if _stow_t > 0.0:
		var was_stowing := _stow_t
		_stow_t = maxf(_stow_t - delta, 0.0)
		# 收枪动作结束时才把枪挂到背后，避免手和背后同时出现两把枪
		if was_stowing > 0.0 and _stow_t <= 0.0 and _stow_kind < 0:
			holstered_changed.emit(true)
	# aim_world 在 Doll2D 的物理帧里写入；首帧还是零向量时不要拿它算角度，
	# 否则开局第一枪会朝左上角偏一大截。
	if aim_enabled and aim_world != Vector2.ZERO and not holstered:
		var target := (aim_world - global_position).angle()
		aim_angle = wrapf(
			lerp_angle(aim_angle, target, clampf(TURN_SPEED * delta, 0.0, 1.0)),
			-PI, PI)
	# 肘部弯向平滑换向：扫过正上/正下时手臂先伸直再弯到另一侧
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
	_ads_t = move_toward(_ads_t, 1.0 if ads and not holstered else 0.0,
		ADS_BLEND_SPEED * ads_speed_mul / maxf(sight_ads_time_mul, 0.2) * delta)
	_apply_pose()
	if InputMap.has_action("holster") and Input.is_action_just_pressed("holster"):
		toggle_holster()
	if InputMap.has_action("reload"):
		if Input.is_action_just_pressed("reload"):
			reload()
		elif Input.is_action_pressed("reload"):
			process_hold_reload()
	if InputMap.has_action("fire"):
		if data.auto_fire:
			# 全自动改件：按住左键，由 cooldown 控制射速。
			if Input.is_action_pressed("fire"):
				try_fire()
		elif Input.is_action_just_pressed("fire"):
			try_fire()


## 数字键 1-4 与滚轮切枪（输入由武器层自己处理，Doll2D 不需要知道）。
func _unhandled_input(event: InputEvent) -> void:
	if data == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var index := int(event.physical_keycode) - int(KEY_1)
		if index >= 0 and index < loadout.size():
			if switch_to(loadout[index]):
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# Alt+滚轮用于整体视角缩放，不切枪。
		if InputMap.has_action("view_zoom") and Input.is_action_pressed("view_zoom"):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(-1)


## 枪贴图默认朝右（枪口 +X）。朝左瞄准时不旋转 180°（那样枪托、机匣会倒过来），
## 而是把贴图上下翻转，并按镜像后的枪管方向重新对齐握把。
func _align_gun(flip: bool) -> void:
	_flipped = flip
	if _gun == null:
		return
	_gun.flip_v = flip
	var rot := _barrel_angle if flip else -_barrel_angle
	var grip := _grip_px - _tex_size * 0.5
	var muzzle := _muzzle_px - _tex_size * 0.5
	if flip:
		grip.y = -grip.y
		muzzle.y = -muzzle.y
	_gun.rotation = rot
	# 握把对到手腕，枪口相对握把使用同一贴图锚点变换。
	_gun.position = _wrist_local - grip.rotated(rot) * _gun_scale
	if _muzzle != null:
		_muzzle.position = _wrist_local + (muzzle - grip).rotated(rot) * _gun_scale


## 大臂 / 小臂共用：枢轴放在贴图左端中心（肩 / 肘），朝 +X 延伸。
func _make_limb(node_name: String, tex: Texture2D) -> Sprite2D:
	var limb := Sprite2D.new()
	limb.name = node_name
	limb.texture = tex
	limb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	limb.scale = Vector2.ONE * ARM_SCALE
	limb.offset = Vector2(tex.get_width() * 0.5, 0.0)
	_pivot.add_child(limb)
	return limb


## 支撑臂分件挂在 SupportPivot 下，不随枪管轴线整体旋转。
func _make_support_limb(node_name: String, tex: Texture2D) -> Sprite2D:
	var limb := Sprite2D.new()
	limb.name = node_name
	limb.texture = tex
	limb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	limb.scale = Vector2.ONE * ARM_SCALE
	limb.offset = Vector2(tex.get_width() * 0.5, 0.0)
	_support_root.add_child(limb)
	return limb


## 两段 IK：肩 → 肘 → 腕。腕固定在枪管轴线上，肘朝屏幕下方弯，
## 手腕距离越近弯得越多；超过两段总长时完全伸直。
func _solve_arm(d: float) -> void:
	var reach := UPPER_ARM_LEN + FOREARM_LEN
	var wrist_x := minf(d, reach)
	_wrist_local = Vector2(wrist_x, 0.0)
	if wrist_x >= reach - 0.01:
		_upper_arm.rotation = 0.0
		_forearm.position = Vector2(UPPER_ARM_LEN - LIMB_OVERLAP, 0.0)
		_forearm.rotation = 0.0
		return
	var cos_shoulder := clampf(
		(UPPER_ARM_LEN * UPPER_ARM_LEN + wrist_x * wrist_x - FOREARM_LEN * FOREARM_LEN)
		/ (2.0 * UPPER_ARM_LEN * wrist_x), -1.0, 1.0)
	# 肘朝屏幕下方弯；_elbow_sign 平滑换向，扫过正上/正下时手臂先伸直，
	# 不会在一帧里突然翻到另一侧。
	var shoulder_angle := acos(cos_shoulder) * _elbow_sign
	var elbow := Vector2.from_angle(shoulder_angle) * UPPER_ARM_LEN
	_upper_arm.rotation = shoulder_angle
	_forearm.rotation = (Vector2(wrist_x, 0.0) - elbow).angle()
	_forearm.position = elbow - Vector2.from_angle(_forearm.rotation) * LIMB_OVERLAP


## 右键瞄准时手臂收回一截，枪贴近身体。
func _arm_length() -> float:
	return lerpf(ARM_LENGTH, ADS_ARM_LENGTH, _ads_t)


## 瞄准过渡进度 0~1，供 HUD / 精度计算用。
func get_ads_blend() -> float:
	return _ads_t


func _apply_pose() -> void:
	if _pivot == null:
		return
	# 朝左时贴图上下镜像，避免整把枪倒置；每帧重解手臂 IK 以跟随 ADS
	var flip := absf(aim_angle) > PI * 0.5
	_solve_arm(_arm_length())
	_align_gun(flip)
	if _hand != null:
		_hand.position = _wrist_local
		_hand.rotation = 0.0
		_hand.flip_v = _flipped
	if _flash != null:
		_flash.position = _muzzle.position + Vector2(2.0, 0.0)
	var anchor := _current_anchor() - Vector2(0.0, ADS_LIFT * _ads_t)
	# 枪身贴图按枪管轴对齐，枢轴只需对齐瞄准角
	_pivot.rotation = aim_angle + _kick * recoil * lerpf(1.0, 0.45, _ads_t)
	# 朝镜头方向（屏幕下方）瞄准时把枪沿枪管压短，假装透视缩短
	var toward_camera := clampf(Vector2.DOWN.dot(Vector2.from_angle(aim_angle)), 0.0, 1.0)
	var foreshorten := lerpf(1.0, 0.45, toward_camera)
	_pivot.scale = Vector2(foreshorten, 1.0)
	var back := Vector2.from_angle(aim_angle) * RECOIL_DISTANCE * recoil * lerpf(1.0, 0.6, _ads_t)
	_pivot.position = anchor - back
	if _flash != null:
		# 抵消枢轴在 X 方向的压缩，枪口焰形状不被压扁
		_flash.scale = Vector2(FLASH_SCALE / maxf(foreshorten, 0.01), FLASH_SCALE)
	_apply_reload_pose()
	_apply_switch_pose()
	_apply_stow_pose()
	# 冲刺持枪：枪不收起，只压低一点点，和举枪瞄准区分开。
	if sprinting and not aiming and not holstered and _stow_t <= 0.0:
		_pivot.position.y += SPRINT_DIP
	# 支撑手最后解算：目标跟随枪的最终变换（含收枪/换弹/切枪的下沉）。
	_solve_support_arm()


## 长枪支撑手：肩点固定在身体，手掌目标跟随枪的护木；两段 IK 的手掌始终
## 贴在护木上。袖子沿长度方向拉伸，弥补 24px 手臂够不到长枪护木的问题。
func _solve_support_arm() -> void:
	if _support_root == null or _support_upper == null or _gun == null:
		return
	var long_gun := data != null and data.visual_length >= 0.5
	# 收/拔枪动画期间也显示，让支撑手跟着枪一起淡出/淡入。
	var show := long_gun and (not holstered or _stow_t > 0.0)
	_support_root.visible = show
	if not show:
		return
	_support_root.position = _current_anchor() + SUPPORT_SHOULDER_OFFSET
	var support_local := _wrist_local + Vector2(_gun_len * SUPPORT_GRIP_RATIO, SUPPORT_LIFT)
	var target := _support_root.to_local(_pivot.to_global(support_local))
	var dist := target.length()
	if dist < 0.5:
		return
	var dir := target / dist
	var seg := clampf(dist * 0.5 + 0.5, SUPPORT_MIN_SEG, SUPPORT_MAX_SEG)
	var a := dist * 0.5
	var h := sqrt(maxf(seg * seg - a * a, 0.0))
	var perp := Vector2(-dir.y, dir.x) * _elbow_sign
	var elbow := dir * a + perp * h
	_support_upper.position = Vector2.ZERO
	_support_upper.rotation = elbow.angle()
	_support_upper.scale = Vector2(ARM_SCALE * (seg + LIMB_OVERLAP) / SUPPORT_UPPER_BASE, ARM_SCALE)
	var wrist_dir := target - elbow
	wrist_dir = wrist_dir.normalized() if wrist_dir.length() > 0.01 else dir
	_support_forearm.position = elbow - wrist_dir * LIMB_OVERLAP
	_support_forearm.rotation = wrist_dir.angle()
	_support_forearm.scale = Vector2(ARM_SCALE * (seg + LIMB_OVERLAP) / SUPPORT_FORE_BASE, ARM_SCALE)
	_support_hand.position = target
	_support_hand.rotation = _pivot.global_rotation - _support_root.global_rotation
	_support_hand.flip_v = not _flipped


## 收枪 / 拔枪动画：整组手臂与枪一起下沉淡出，拔枪时反向抬起淡入。
func _apply_stow_pose() -> void:
	if _gun == null:
		return
	var alpha := 1.0
	if _stow_t <= 0.0:
		_gun.visible = not holstered
		_gun.modulate.a = 1.0
		_set_limbs_visible(not holstered)
		if _support_root != null:
			_support_root.modulate.a = 1.0
		return
	var p := clampf(1.0 - _stow_t / maxf(_stow_total, 0.001), 0.0, 1.0)
	if _stow_kind < 0:
		_pivot.position += Vector2(0.0, STOW_DIP * p)
		_pivot.rotation += STOW_TILT * p
		alpha = 1.0 - p
	else:
		var lift := 1.0 - p
		_pivot.position += Vector2(0.0, STOW_DIP * lift)
		_pivot.rotation += STOW_TILT * lift
		alpha = p
	_gun.visible = true
	_gun.modulate.a = alpha
	_set_limbs_visible(true)
	for limb in [_upper_arm, _forearm, _hand]:
		if limb != null:
			limb.modulate.a = alpha
	if _support_root != null:
		_support_root.modulate.a = alpha
	if _flash != null:
		_flash.visible = false


func _set_limbs_visible(shown: bool) -> void:
	for limb in [_upper_arm, _forearm, _hand]:
		if limb != null:
			limb.visible = shown
			limb.modulate.a = 1.0


## 换弹：枪先下压侧摆，旧弹匣掉落、新弹匣从下方插入，最后抬回瞄准位置。
func _apply_reload_pose() -> void:
	if _mag_sprite == null:
		return
	if reload_t <= 0.0:
		_mag_sprite.visible = false
		return
	var p := 1.0 - reload_t / maxf(reload_total, 0.001)
	var dip := sin(clampf(p, 0.0, 1.0) * PI)
	_pivot.position += Vector2(0.0, RELOAD_DIP * dip)
	_pivot.rotation += -RELOAD_TILT * dip
	var anchor := _current_anchor()
	if p >= 0.24 and p <= 0.5:
		# 旧弹匣掉下去
		var k := (p - 0.24) / 0.26
		_mag_sprite.visible = true
		_mag_sprite.position = anchor + Vector2(0.0, 2.0 + 24.0 * k * k)
		_mag_sprite.rotation = 1.1 * k
		_mag_sprite.modulate.a = 1.0 - k
	elif p > 0.5 and p <= 0.82:
		# 新弹匣从下方插回去
		var k2 := (p - 0.5) / 0.32
		_mag_sprite.visible = true
		_mag_sprite.position = anchor + Vector2(0.0, 20.0 * (1.0 - k2))
		_mag_sprite.rotation = 0.0
		_mag_sprite.modulate.a = clampf(k2 * 2.0, 0.0, 1.0)
	else:
		_mag_sprite.visible = false


## 切枪：整组沉下去、倾斜、淡出，中点换模型后再抬回来。
func _apply_switch_pose() -> void:
	if switch_t <= 0.0:
		return
	var p := 1.0 - switch_t / SWITCH_TIME
	var dip := sin(clampf(p, 0.0, 1.0) * PI)
	_pivot.position += Vector2(0.0, SWITCH_DIP * dip)
	_pivot.rotation += SWITCH_TILT * dip
	if _gun != null:
		_gun.modulate.a = 1.0 - 0.92 * dip
	for limb in [_upper_arm, _forearm, _hand]:
		if limb != null:
			limb.modulate.a = _gun.modulate.a
	if _support_root != null:
		_support_root.modulate.a = _gun.modulate.a


## 肩点是手、枪、手臂共同的枢轴；四向只差肩点位置。
func _current_anchor() -> Vector2:
	return SHOULDER.get(body_direction, SHOULDER[0])


## 朝上瞄准、或枪口指向身体背面时，把武器画到身体后面，
## 避免枪身从胸口/远侧手臂中间穿过去。
func _update_layer() -> void:
	var behind_up := aim_angle > BEHIND_FROM and aim_angle < BEHIND_TO
	# 背向时持枪手在屏幕右侧：朝上 / 右上举枪走前景，手臂才看得见；
	# 只有朝左上会横穿头部，仍然压到身体后面。
	if body_direction == 1:
		behind_up = aim_angle > BEHIND_FROM and aim_angle < -1.75
	var body_angle: float = BODY_ANGLE.get(body_direction, 0.0)
	var far_side := absf(angle_difference(aim_angle, body_angle)) > PI * 0.5
	_behind = behind_up or far_side
	var target_z := BEHIND_Z if _behind else FRONT_Z
	if z_index != target_z:
		z_index = target_z


func try_fire() -> bool:
	if data == null or cooldown > 0.0 or reload_t > 0.0 or switch_t > 0.0:
		return false
	if holstered:
		# 收枪状态扣扳机 = 自动拔枪，不直接开火
		draw()
		return false
	if _stow_t > 0.0:
		return false
	if mag <= 0:
		# 空仓扣扳机：直接开始换弹，省得玩家再按一次 R
		reload()
		return false
	mag -= 1
	_mag_by_id[weapon_id] = mag
	cooldown = data.fire_interval
	recoil = recoil_mul
	_kick = -RECOIL_KICK + randf_range(-0.015, 0.015)
	_flash_timer = FLASH_TIME
	_flash.visible = true
	_flash.frame = 0
	shots += 1
	fired.emit(get_muzzle_position(), Vector2.from_angle(aim_angle))
	return true


## R 换弹：弹匣枪整匣更换，霰弹枪一次压一发。
func reload() -> bool:
	if data == null or reload_t > 0.0 or switch_t > 0.0 or holstered or _stow_t > 0.0:
		return false
	if mag >= data.mag_capacity or get_reserve() <= 0:
		return false
	reload_total = maxf(data.load_time * reload_time_mul, 0.15)
	reload_t = reload_total
	return true


## 「持续装填」：按住 R 时，上一发装完后自动续压下一发。
## 只对管仓 / 逐发装填的武器（M870、M1014、后续栓动步枪）生效。
func process_hold_reload() -> void:
	if not hold_reload_enabled or data == null or data.feed_mode != &"shell":
		return
	if holstered or _stow_t > 0.0 or switch_t > 0.0:
		return
	if reload_t > 0.0:
		return
	reload()


func _finish_reload() -> void:
	if data == null:
		return
	if data.feed_mode == &"mag":
		var take := mini(data.mag_capacity - mag, get_reserve())
		_set_reserve(get_reserve() - take)
		mag += take
	elif get_reserve() > 0:
		_set_reserve(get_reserve() - 1)
		mag += 1
	_mag_by_id[weapon_id] = mag
	reload_finished.emit()


## 切枪：中途换模型，前后各有一段收/举枪动画。
func switch_to(id: StringName) -> bool:
	if data == null or switch_t > 0.0 or _stow_t > 0.0 or id == weapon_id:
		return false
	if not loadout.has(id):
		return false
	# 换弹中切枪直接取消，避免两套动画打架
	if reload_t > 0.0:
		reload_t = 0.0
		reload_total = 0.0
		if _mag_sprite != null:
			_mag_sprite.visible = false
	# 收枪状态直接换背后的模型，不播举枪动画
	if holstered:
		setup(id)
		weapon_switched.emit(id)
		return true
	_pending_id = id
	switch_t = SWITCH_TIME
	return true


func _cycle_weapon(step: int) -> void:
	if loadout.is_empty():
		return
	var index := loadout.find(weapon_id)
	if index < 0:
		index = 0
		switch_to(loadout[0])
		return
	switch_to(loadout[(index + step + loadout.size()) % loadout.size()])


func get_reserve() -> int:
	if data == null:
		return 0
	var category := data.ammo_category
	if reserve.has(category):
		return int(reserve[category])
	var info: Dictionary = WeaponDB.category_table().get(String(category), {})
	return int(info.get("reserve_max", 0))


func _set_reserve(value: int) -> void:
	if data == null:
		return
	reserve[data.ammo_category] = maxi(value, 0)


## 备弹天赋：所有通用弹药种类按倍率给足初始备弹。
func apply_reserve_talent(mul: float) -> void:
	reserve_talent_mul = mul
	var table := WeaponDB.category_table()
	for category in table:
		var info: Dictionary = table[category]
		reserve[category] = int(round(float(info.get("reserve_max", 0)) * mul))


## 浪潮模式波次间整备：弹匣、所有武器弹匣与通用备弹全部回满。
func refill_all_ammo() -> void:
	var table := WeaponDB.category_table()
	for category in table:
		var info: Dictionary = table[category]
		reserve[category] = int(round(
			float(info.get("reserve_max", 0)) * reserve_talent_mul))
	for id in _mag_by_id:
		var wd: WeaponData = WeaponDB.get_weapon(StringName(id))
		if wd != null:
			_mag_by_id[id] = wd.mag_capacity
	if data != null:
		_mag_by_id[data.id] = data.mag_capacity
		mag = data.mag_capacity
		reload_t = 0.0
		reload_total = 0.0


## 换弹进度 0~1，供 HUD 画进度用。
func get_reload_progress() -> float:
	if reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - reload_t / reload_total, 0.0, 1.0)


## 收枪 / 拔枪进度 0~1，供 HUD 画进度用。
func get_stow_progress() -> float:
	if _stow_total <= 0.0:
		return 1.0
	return clampf(1.0 - _stow_t / _stow_total, 0.0, 1.0)


## 收枪：枪沉下去，背后挂点由 Doll2D 显示武器。
func holster() -> bool:
	if holstered or _stow_t > 0.0 or reload_t > 0.0 or switch_t > 0.0:
		return false
	holstered = true
	_stow_kind = -1
	_stow_total = HOLSTER_TIME
	_stow_t = HOLSTER_TIME
	if _flash != null:
		_flash.visible = false
	_play_stow_sfx()
	return true


## 拔枪：从下方抬起并淡入；扣扳机也会自动触发。
func draw() -> bool:
	if not holstered or _stow_t > 0.0:
		return false
	holstered = false
	_stow_kind = 1
	_stow_total = DRAW_TIME
	_stow_t = DRAW_TIME
	_play_stow_sfx()
	holstered_changed.emit(false)
	return true


func toggle_holster() -> bool:
	return draw() if holstered else holster()


func is_holstered() -> bool:
	return holstered


func is_stowing() -> bool:
	return _stow_t > 0.0 and _stow_kind < 0


func is_drawing() -> bool:
	return _stow_t > 0.0 and _stow_kind > 0


## 背后挂点用：当前枪的侧视贴图与同一世界比例。
func get_side_texture() -> Texture2D:
	return _gun.texture if _gun != null else null


func get_stow_scale() -> float:
	return _gun_scale


func _play_stow_sfx() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.play_2d("switch", -10.0, randf_range(0.95, 1.05))


func is_busy() -> bool:
	return reload_t > 0.0 or switch_t > 0.0 or _stow_t > 0.0


## HUD 文本：枪名 + 弹匣/备弹，空仓或换弹时附提示。
func get_ammo_text() -> String:
	if data == null:
		return ""
	var extra := ""
	if reload_t > 0.0:
		extra = "装填中"
	elif switch_t > 0.0:
		extra = "切枪中"
	elif mag <= 0:
		extra = "空仓 · R 换弹" if get_reserve() > 0 else "弹药耗尽"
	var line := "%s   %d / %d" % [data.display_name, mag, get_reserve()]
	return line + ("   " + extra if extra != "" else "")


func get_muzzle_position() -> Vector2:
	return _muzzle.global_position if _muzzle != null else global_position


func get_barrel_direction() -> Vector2:
	return Vector2.from_angle(aim_angle)


## 贴图里的枪管倾角（弧度）：枪身按它反向旋转后，枪管才和瞄准轴一致。
func get_barrel_angle() -> float:
	return _barrel_angle


## 握把（手心）在世界里的位置：直接读 IK 解出的腕点。
func get_grip_position() -> Vector2:
	if _pivot != null:
		return _pivot.to_global(_wrist_local)
	return to_global(_current_anchor())


## 枪在世界里的长度（握把到枪口，像素）。
func get_gun_length() -> float:
	return _gun_len
