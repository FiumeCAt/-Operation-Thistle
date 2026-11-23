extends RefCounted
class_name WeaponPoseIK2D
## 2D 持枪双臂 IK、枪管轴对齐、朝向层级判定、换弹/切枪/收拔枪姿态与贴图锚点变换模块。
## 纯数学与局部变换逻辑从 WeaponRig2D 抽离，同时提供 pixel_to_pivot 坐标变换供后续可视化配件挂点复用。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const FEED_STATE := preload("res://scripts/weapons/WeaponFeedState2D.gd")

const META_PATH := "res://assets/art/weapons/%s/meta.json"
const TEX_PATH := "res://assets/art/weapons/%s/side.png"

const SPRITE_PX_PER_METER := UNITS.SPRITE_PX_PER_METER
const SIZE_BOOST := 1.35
const LONG_GUN_BOOST := 1.0
const MIN_GUN_LEN := 36.0
const GUN_WORLD_SCALE := 0.6
const ARM_SCALE := 0.5
const UPPER_ARM_LEN := 12.0
const FOREARM_LEN := 12.0
const LIMB_OVERLAP := 1.5
const ARM_LENGTH := 22.8

const SHOULDER := {
	0: Vector2(6.0, -88.0),
	1: Vector2(17.0, -90.0),
	2: Vector2(0.0, -88.0),
	3: Vector2(0.0, -88.0),
}

const BEHIND_FROM := -2.356      # -135°
const BEHIND_TO := -0.785        # -45°
const BEHIND_Z := -1
const FRONT_Z := 2
const BODY_ANGLE := {0: PI * 0.5, 1: -PI * 0.5, 2: PI, 3: 0.0}

const RELOAD_DIP := 14.0
const RELOAD_TILT := 0.5
const SWITCH_TIME := FEED_STATE.SWITCH_TIME
const SWITCH_DIP := 24.0
const SWITCH_TILT := 0.45
const STOW_DIP := 22.0
const STOW_TILT := 0.5

const SUPPORT_GRIP_RATIO := 0.18
const SUPPORT_LIFT := -2.0
const SUPPORT_SHOULDER_OFFSET := Vector2(-4.0, 1.0)
const SUPPORT_MIN_SEG := 12.0
const SUPPORT_MAX_SEG := 28.0
const SUPPORT_UPPER_BASE := 13.0
const SUPPORT_FORE_BASE := 13.5


## 读取武器 side.png 与 meta.json，计算视觉缩放、枪管倾角与握把/枪口像素锚点。
static func load_weapon_metrics(id: StringName, visual_length: float) -> Dictionary:
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
	var final_barrel := barrel_angle if has_barrel else (muzzle_px - grip_px).angle()
	var tex_len := (muzzle_px - grip_px).length()
	var boost := SIZE_BOOST if visual_length < 0.5 else LONG_GUN_BOOST
	var world_len := maxf(visual_length * SPRITE_PX_PER_METER * boost, MIN_GUN_LEN) * GUN_WORLD_SCALE
	var gun_scale := world_len / maxf(tex_len, 1.0)
	return {
		"tex": tex,
		"tex_size": Vector2(tex.get_width(), tex.get_height()),
		"grip_px": grip_px,
		"muzzle_px": muzzle_px,
		"barrel_angle": final_barrel,
		"gun_scale": gun_scale,
		"gun_len": world_len,
	}


## 将武器侧视图像素坐标（枪口、瞄具轨、握把、弹匣等）映射到 Pivot 局部坐标，自动处理镜像翻转与枪管倾角。
static func pixel_to_pivot(px: Vector2, grip_px: Vector2, barrel_angle: float,
		gun_scale: float, wrist_local: Vector2, flip: bool) -> Vector2:
	var rot := barrel_angle if flip else -barrel_angle
	var delta := px - grip_px
	if flip:
		delta.y = -delta.y
	return wrist_local + delta.rotated(rot) * gun_scale


## 枪贴图默认朝右（枪口 +X）；朝左瞄准时上下镜像并按枪管轴重新对齐握把与枪口。
static func align_gun(gun: Sprite2D, muzzle: Marker2D, wrist_local: Vector2,
		grip_px: Vector2, muzzle_px: Vector2, tex_size: Vector2,
		barrel_angle: float, gun_scale: float, flip: bool) -> void:
	if gun == null:
		return
	gun.flip_v = flip
	var rot := barrel_angle if flip else -barrel_angle
	gun.rotation = rot
	gun.position = pixel_to_pivot(tex_size * 0.5, grip_px, barrel_angle, gun_scale, wrist_local, flip)
	if muzzle != null:
		muzzle.position = pixel_to_pivot(muzzle_px, grip_px, barrel_angle, gun_scale, wrist_local, flip)


## 两段 IK：肩 → 肘 → 腕；返回 Pivot 局部空间的手腕位置。
static func solve_primary_arm(upper_arm: Sprite2D, forearm: Sprite2D,
		d: float, elbow_sign: float) -> Vector2:
	var reach := UPPER_ARM_LEN + FOREARM_LEN
	var wrist_x := minf(d, reach)
	var wrist_local := Vector2(wrist_x, 0.0)
	if upper_arm == null or forearm == null:
		return wrist_local
	if wrist_x >= reach - 0.01:
		upper_arm.rotation = 0.0
		forearm.position = Vector2(UPPER_ARM_LEN - LIMB_OVERLAP, 0.0)
		forearm.rotation = 0.0
		return wrist_local
	var cos_shoulder := clampf(
		(UPPER_ARM_LEN * UPPER_ARM_LEN + wrist_x * wrist_x - FOREARM_LEN * FOREARM_LEN)
		/ (2.0 * UPPER_ARM_LEN * wrist_x), -1.0, 1.0)
	var shoulder_angle := acos(cos_shoulder) * elbow_sign
	var elbow := Vector2.from_angle(shoulder_angle) * UPPER_ARM_LEN
	upper_arm.rotation = shoulder_angle
	forearm.rotation = (Vector2(wrist_x, 0.0) - elbow).angle()
	forearm.position = elbow - Vector2.from_angle(forearm.rotation) * LIMB_OVERLAP
	return wrist_local


## 长枪支撑手两段 IK：肩点固定在身体，手掌目标跟随枪的护木位置。
static func solve_support_arm(support_root: Node2D, support_upper: Sprite2D,
		support_forearm: Sprite2D, support_hand: Sprite2D, pivot: Node2D,
		anchor: Vector2, wrist_local: Vector2, gun_len: float,
		elbow_sign: float, flipped: bool, show: bool) -> void:
	if support_root == null or support_upper == null or pivot == null:
		return
	support_root.visible = show
	if not show:
		return
	support_root.position = anchor + SUPPORT_SHOULDER_OFFSET
	var support_local := wrist_local + Vector2(gun_len * SUPPORT_GRIP_RATIO, SUPPORT_LIFT)
	var target := support_root.to_local(pivot.to_global(support_local))
	var dist := target.length()
	if dist < 0.5:
		return
	var dir := target / dist
	var seg := clampf(dist * 0.5 + 0.5, SUPPORT_MIN_SEG, SUPPORT_MAX_SEG)
	var a := dist * 0.5
	var h := sqrt(maxf(seg * seg - a * a, 0.0))
	var perp := Vector2(-dir.y, dir.x) * elbow_sign
	var elbow := dir * a + perp * h
	support_upper.position = Vector2.ZERO
	support_upper.rotation = elbow.angle()
	support_upper.scale = Vector2(ARM_SCALE * (seg + LIMB_OVERLAP) / SUPPORT_UPPER_BASE, ARM_SCALE)
	var wrist_dir := target - elbow
	wrist_dir = wrist_dir.normalized() if wrist_dir.length() > 0.01 else dir
	support_forearm.position = elbow - wrist_dir * LIMB_OVERLAP
	support_forearm.rotation = wrist_dir.angle()
	support_forearm.scale = Vector2(ARM_SCALE * (seg + LIMB_OVERLAP) / SUPPORT_FORE_BASE, ARM_SCALE)
	support_hand.position = target
	support_hand.rotation = pivot.global_rotation - support_root.global_rotation
	support_hand.flip_v = not flipped


## 肩点是手、枪、手臂共同的枢轴；四向只差肩点位置。
static func shoulder_anchor(body_direction: int) -> Vector2:
	return SHOULDER.get(body_direction, SHOULDER[0])


## 朝上瞄准、或枪口指向身体背面超过 90° 时，将武器压到身体后方层级。
static func is_behind_body(aim_angle: float, body_direction: int) -> bool:
	var behind_up := aim_angle > BEHIND_FROM and aim_angle < BEHIND_TO
	if body_direction == 1:
		behind_up = aim_angle > BEHIND_FROM and aim_angle < -1.75
	var body_angle: float = BODY_ANGLE.get(body_direction, 0.0)
	var far_side := absf(angle_difference(aim_angle, body_angle)) > PI * 0.5
	return behind_up or far_side


static func set_limbs_visible(limbs: Array, shown: bool) -> void:
	for limb in limbs:
		if limb != null:
			limb.visible = shown
			limb.modulate.a = 1.0


## 换弹：枪先下压侧摆，旧弹匣掉落、新弹匣从下方插入，最后抬回瞄准位置。
static func apply_reload_pose(pivot: Node2D, mag_sprite: Sprite2D, anchor: Vector2,
		reload_t: float, reload_total: float) -> void:
	if mag_sprite == null:
		return
	if reload_t <= 0.0:
		mag_sprite.visible = false
		return
	var p := 1.0 - reload_t / maxf(reload_total, 0.001)
	var dip := sin(clampf(p, 0.0, 1.0) * PI)
	pivot.position += Vector2(0.0, RELOAD_DIP * dip)
	pivot.rotation += -RELOAD_TILT * dip
	if p >= 0.24 and p <= 0.5:
		var k := (p - 0.24) / 0.26
		mag_sprite.visible = true
		mag_sprite.position = anchor + Vector2(0.0, 2.0 + 24.0 * k * k)
		mag_sprite.rotation = 1.1 * k
		mag_sprite.modulate.a = 1.0 - k
	elif p > 0.5 and p <= 0.82:
		var k2 := (p - 0.5) / 0.32
		mag_sprite.visible = true
		mag_sprite.position = anchor + Vector2(0.0, 20.0 * (1.0 - k2))
		mag_sprite.rotation = 0.0
		mag_sprite.modulate.a = clampf(k2 * 2.0, 0.0, 1.0)
	else:
		mag_sprite.visible = false


## 切枪：整组沉下去、倾斜、淡出，中点换模型后再抬回来。
static func apply_switch_pose(pivot: Node2D, gun: Sprite2D, limbs: Array,
		support_root: Node2D, switch_t: float) -> void:
	if switch_t <= 0.0:
		return
	var p := 1.0 - switch_t / SWITCH_TIME
	var dip := sin(clampf(p, 0.0, 1.0) * PI)
	pivot.position += Vector2(0.0, SWITCH_DIP * dip)
	pivot.rotation += SWITCH_TILT * dip
	var alpha := 1.0 - 0.92 * dip
	if gun != null:
		gun.modulate.a = alpha
	for limb in limbs:
		if limb != null:
			limb.modulate.a = alpha
	if support_root != null:
		support_root.modulate.a = alpha


## 收枪 / 拔枪动画：整组手臂与枪一起下沉淡出，拔枪时反向抬起淡入。
static func apply_stow_pose(pivot: Node2D, gun: Sprite2D, limbs: Array,
		support_root: Node2D, flash: Sprite2D, holstered: bool,
		stow_t: float, stow_total: float, stow_kind: int) -> void:
	if gun == null:
		return
	if stow_t <= 0.0:
		gun.visible = not holstered
		gun.modulate.a = 1.0
		set_limbs_visible(limbs, not holstered)
		if support_root != null:
			support_root.modulate.a = 1.0
		return
	var p := clampf(1.0 - stow_t / maxf(stow_total, 0.001), 0.0, 1.0)
	var alpha := 1.0
	if stow_kind < 0:
		pivot.position += Vector2(0.0, STOW_DIP * p)
		pivot.rotation += STOW_TILT * p
		alpha = 1.0 - p
	else:
		var lift := 1.0 - p
		pivot.position += Vector2(0.0, STOW_DIP * lift)
		pivot.rotation += STOW_TILT * lift
		alpha = p
	gun.visible = true
	gun.modulate.a = alpha
	set_limbs_visible(limbs, true)
	for limb in limbs:
		if limb != null:
			limb.modulate.a = alpha
	if support_root != null:
		support_root.modulate.a = alpha
	if flash != null:
		flash.visible = false
