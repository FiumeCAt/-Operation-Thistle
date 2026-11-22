extends CharacterBody3D
class_name Doll
signal died

var is_dead := false
var flashlight_on := false
var flashlight: SpotLight3D

func set_flashlight(on: bool) -> void:
	if on and (is_dead or get_tree().paused):
		return
	flashlight_on = on
	if flashlight:
		flashlight.visible = on

func visibility_multiplier() -> float:
	return 1.4 if flashlight_on else 1.0
## 玩家骨架：相机相对移动 / 鼠标射线平面瞄准 / 8 向立绘 / 试射反馈。
## 所有玩法逻辑保持在 XZ 平面，朝向只转 Y 轴。

@export_group("Movement")
@export var walk_speed := 4.2
@export var sprint_speed := 6.5
@export var accel := 28.0
@export var decel := 40.0
@export var turn_speed := 16.0

@export_group("Stamina")
@export var stamina_max := 100.0
@export var stamina_drain := 24.0
@export var stamina_regen := 18.0

@export_group("Vision")
## 半角：主视野 80°，总视野 120°（接近人眼双目视野）。
@export var vision_clear_half := 40.0
@export var vision_total_half := 60.0
@export var vision_range := 12.0

const FX_FLASH := preload("res://assets/art/fx/muzzle_flash.png")
const HAND_LOCAL := {
	"LOW": Vector2(0.10, 0.98),      # 待机/行走：腰前
	"AIM": Vector2(0.05, 1.27),      # 据枪/开火：胸前偏右
	"RELOAD": Vector2(0.10, 1.10),   # 装填：腰线偏中
}

const HAND_REFERENCE := {
	"LOW": Vector2(0.10, 0.98),
	"AIM": Vector2(0.05, 1.27),
	"RELOAD": Vector2(0.10, 1.10),
}

const HAND_PIXEL_REPRESENTATIVE := {
	"LOW": [Vector2(61, 78), Vector2(78, 78), Vector2(86, 77), Vector2(88, 76), Vector2(64, 77), Vector2(40, 76), Vector2(42, 77), Vector2(50, 78)],
	"AIM": [Vector2(57, 56), Vector2(77, 56), Vector2(92, 54), Vector2(79, 54), Vector2(64, 59), Vector2(49, 54), Vector2(36, 54), Vector2(51, 56)],
	"RELOAD": [Vector2(53, 80), Vector2(67, 80), Vector2(87, 80), Vector2(91, 80), Vector2(64, 78), Vector2(37, 80), Vector2(41, 80), Vector2(61, 80)],
}

## 弹道飞行高度（米）。瞄准点也取这个高度的平面，两者一致才能让准心与命中对齐。
## 取 1.1 而不是 1.25：既贴近设计稿的"胸口高度"，又能让 1.2m 以上的掩体真正挡住子弹。
const AIM_HEIGHT := 1.1

var camera_rig: CameraRig
var aim_point := Vector3.ZERO
var stamina := 100.0
var hp := 100.0
var hp_max := 100.0
var _hurt_cd := 0.0
var shots := 0
var _step_timer := 0.0
var _step_alt := false

var action_state := ""
var action_timer := 0.0

# 调试 / 截图用覆盖
var debug_face_enabled := false
var debug_face_deg := 0.0
var debug_aim_enabled := false
var debug_aim_world := Vector3.ZERO
var debug_state := ""
var debug_hold_muzzle := false

# 武器层每帧把真实枪口位置回填到这里；有外部枪口时不再用锚点推算
var _external_muzzle := false

@onready var billboard: BillboardVisual = $Visual
@onready var muzzle: Marker3D = $Visual/Muzzle
@onready var flash: Sprite3D = $Visual/Muzzle/Flash
@onready var muzzle_light: OmniLight3D = $Visual/Muzzle/MuzzleLight
@onready var weapon: PlayerWeapon = $Weapon

var shadow: MeshInstance3D
var wedge: MeshInstance3D
var _flash_tween: Tween
var health_bar: HealthBar3D
var _hurt_flash := 0.0

func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	up_direction = Vector3.UP

	# 保留世界深度，让墙体与场景物件自然遮挡立绘。
	billboard.body.no_depth_test = false
	billboard.body.render_priority = 1

	flash.texture = FX_FLASH
	flash.billboard = 1
	flash.modulate = Color(1, 1, 1, 0)
	flash.cast_shadow = 0

	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.position = Vector3(0.2, AIM_HEIGHT, 0.3)
	flashlight.rotation.y = PI
	flashlight.spot_range = 14.0
	flashlight.spot_angle = 30.0
	flashlight.light_energy = 4.0
	flashlight.shadow_enabled = true
	add_child(flashlight)
	set_flashlight(false)
	_build_ground_fx()
	health_bar = HealthBar3D.new()
	health_bar.position.y = 2.05
	add_child(health_bar)
	health_bar.update_health(hp, hp_max)
	stamina = stamina_max
	aim_point = global_position + Vector3(0, 0, 3)

func _process(dt: float) -> void:
	health_bar.update_health(hp, hp_max, is_dead)
	_hurt_flash = maxf(0.0, _hurt_flash - dt)
	billboard.body.modulate = Color(1.12, 1.14, 1.18).lerp(Color(1.8, 0.45, 0.35), _hurt_flash / 0.16)

func _physics_process(dt: float) -> void:
	var main := get_parent() as Node
	if main != null and bool(main.get("in_base")):
		return
	if is_dead or get_tree().paused:
		return
	if Input.is_action_just_pressed("flashlight"):
		set_flashlight(not flashlight_on)
	_update_aim()
	_update_facing(dt)
	_update_movement(dt)
	_update_stamina(dt)
	_update_footsteps(dt)

	if action_timer > 0.0:
		action_timer = maxf(0.0, action_timer - dt)

	var state := "idle"
	if debug_state != "":
		state = debug_state
	elif action_timer > 0.0:
		state = action_state
	elif Input.is_action_pressed("aim"):
		state = "aim"
	elif Vector2(velocity.x, velocity.z).length() > 0.6:
		state = "walk"
	billboard.play_state(state)
	billboard.set_speed_scale(clampf(Vector2(velocity.x, velocity.z).length() / walk_speed, 0.65, 1.5))

	_update_muzzle_position()

func _update_muzzle_position() -> void:
	## 优先使用武器层回填的真实枪口；没有武器层时按手部锚点 + 枪长近似。
	if _external_muzzle:
		return
	var hand := hand_anchor_world("AIM")
	var facing := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var gun_len := 0.90
	if weapon != null and weapon.weapon != null:
		gun_len = weapon.weapon.visual_length
	muzzle.global_position = Vector3(hand.x, AIM_HEIGHT, hand.z) + facing * gun_len

func hand_anchor_world(group: String) -> Vector3:
	if not HAND_LOCAL.has(group):
		group = "LOW"
	var adjustment: Vector2 = HAND_LOCAL[group] - HAND_REFERENCE[group]
	var pixel: Vector2 = HAND_PIXEL_REPRESENTATIVE[group][billboard.current_dir]
	pixel += Vector2(adjustment.x, -adjustment.y) / billboard.body.pixel_size
	return billboard.pixel_to_world(pixel)

## 武器层回填真实枪口位置
func set_muzzle_world(p: Vector3) -> void:
	_external_muzzle = true
	muzzle.global_position = p

func _update_aim() -> void:
	if debug_aim_enabled:
		aim_point = debug_aim_world
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		aim_point = global_position + Vector3(0, AIM_HEIGHT, 3)
		return
	var mouse := camera_rig.aim_screen_position() if camera_rig else get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	# 关键：与「弹道所在平面」求交，而不是地面。
	# 子弹水平飞在 AIM_HEIGHT，若拿地面交点当瞄准点，命中点会系统性偏离准心
	# （俯角 58° 下 1.25m 高度差 ≈ 110px 屏幕偏移）。
	var hit = Plane(Vector3.UP, AIM_HEIGHT).intersects_ray(from, dir)
	if hit == null:
		aim_point = global_position + Vector3(0, AIM_HEIGHT, 3)
	else:
		aim_point = hit

func _update_facing(dt: float) -> void:
	if debug_face_enabled:
		rotation.y = deg_to_rad(debug_face_deg)
		return
	var to := aim_point - global_position
	to.y = 0.0
	if to.length_squared() < 0.04:
		return
	var target_yaw := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * dt))

func _update_movement(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_yaw := camera_rig.rotation.y if camera_rig else 0.0
	var wish := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, cam_yaw)
	if wish.length() > 1.0:
		wish = wish.normalized()

	var moving := wish.length_squared() > 0.001
	var sprinting := moving and Input.is_action_pressed("sprint") and stamina > 1.0
	var target_speed := sprint_speed if sprinting else walk_speed
	var target_vel := wish * target_speed
	var rate := accel if moving else decel

	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_vel, rate * dt)
	velocity.x = horiz.x
	velocity.z = horiz.z
	velocity.y -= 24.0 * dt
	move_and_slide()

func _update_stamina(dt: float) -> void:
	_hurt_cd = maxf(0.0, _hurt_cd - dt)
	var speed := Vector2(velocity.x, velocity.z).length()
	if Input.is_action_pressed("sprint") and speed > walk_speed * 0.6:
		stamina = maxf(0.0, stamina - stamina_drain * dt)
	else:
		stamina = minf(stamina_max, stamina + stamina_regen * dt)

func play_muzzle_flash() -> void:
	muzzle_light.light_energy = 5.5
	flash.modulate = Color(1, 1, 1, 1)
	flash.scale = Vector3.ONE * randf_range(0.85, 1.25)

	if debug_hold_muzzle:
		return

	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(muzzle_light, "light_energy", 0.0, 0.09)
	_flash_tween.tween_property(flash, "modulate:a", 0.0, 0.07)

func set_action_state(state: String, duration: float) -> void:
	action_state = state
	action_timer = duration

func get_muzzle_position() -> Vector3:
	return muzzle.global_position

func _build_ground_fx() -> void:
	# 贴地软阴影：HD-2D 只保留接触阴影，去掉会拉出长影的胶囊投影体。
	shadow = BillboardVisual.add_ground_shadow(self, 1.25, 0.5)
	# HD-2D 接地：软阴影中心再压一层小尺寸硬阴影，强化脚底接触感。
	BillboardVisual.add_ground_shadow(self, 0.5, 0.55, 0.034)

	# 朝向扇形：直接用顶点生成 +Z 方向的锥形片，方向明确、无贴图 V 轴歧义
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(0.0, 0.0, 0.18)
	var c_apex := Color(1.0, 0.72, 0.42, 0.28)
	var c_edge := Color(1.0, 0.72, 0.42, 0.0)
	var seg := 14
	var half := deg_to_rad(24.0)
	var radius := 1.6
	for i in seg:
		var a0 := -half + 2.0 * half * float(i) / float(seg)
		var a1 := -half + 2.0 * half * float(i + 1) / float(seg)
		var p0 := Vector3(sin(a0), 0.0, cos(a0)) * radius
		var p1 := Vector3(sin(a1), 0.0, cos(a1)) * radius
		st.set_color(c_apex)
		st.add_vertex(apex)
		st.set_color(c_edge)
		st.add_vertex(p0)
		st.set_color(c_edge)
		st.add_vertex(p1)
	st.generate_normals()

	wedge = MeshInstance3D.new()
	wedge.name = "FacingCone"
	wedge.mesh = st.commit()
	wedge.position.y = 0.04
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.vertex_color_use_as_albedo = true
	wmat.albedo_color = Color(1, 1, 1, 1)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.render_priority = 2
	wedge.material_override = wmat
	wedge.cast_shadow = 0
	add_child(wedge)

func take_damage(amount: float) -> void:
	if is_dead or _hurt_cd > 0.0 or amount <= 0.0:
		return
	_hurt_cd = 0.12
	hp = maxf(0.0, hp - amount)
	_hurt_flash = 0.16
	billboard.body.modulate = Color(1.8, 0.45, 0.35)
	health_bar.update_health(hp, hp_max, hp <= 0.0, true)
	ImpactFX.spawn(get_parent(), global_position + Vector3.UP)
	set_action_state("hurt", 0.28)
	if camera_rig:
		camera_rig.add_shake(0.5)
	if hp <= 0.0:
		is_dead = true
		set_flashlight(false)
		velocity = Vector3.ZERO
		died.emit()

func repair(amount: float) -> float:
	if is_dead or hp <= 0.0:
		return 0.0
	var restored := minf(maxf(amount, 0.0), maxf(0.0, hp_max - hp))
	hp += restored
	return restored

func respawn() -> void:
	set_flashlight(false)
	var level := get_node_or_null("../Level") as LevelGenerator
	if level == null:
		return
	global_position = level.player_spawn
	velocity = Vector3.ZERO
	hp = hp_max
	is_dead = false
	_hurt_flash = 0.0
	billboard.body.modulate = Color(1.12, 1.14, 1.18)
	health_bar.update_health(hp, hp_max)
	stamina = stamina_max
	_hurt_cd = 0.12
	action_state = ""
	action_timer = 0.0
	_step_timer = 0.0
	if camera_rig:
		camera_rig.stop_orbit()
		camera_rig.global_position = Vector3(global_position.x, 0.0, global_position.z)

func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

# ---------------------------------------------------------------- 调试接口
func _sfx() -> Node:
	return get_tree().root.get_node_or_null("Sfx")

func _update_footsteps(dt: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 0.8:
		_step_timer -= dt
		if _step_timer <= 0.0:
			_step_timer = 0.30 if planar > walk_speed * 1.15 else 0.42
			_step_alt = not _step_alt
			var s := _sfx()
			if s:
				s.play_3d(self, "step", global_position + Vector3(0, 0.05, 0),
					-11.0, 1.04 if _step_alt else 0.90)
	else:
		_step_timer = 0.0

func debug_fire() -> void:
	if weapon:
		weapon.debug_fire_once()

func debug_set_facing(deg: float) -> void:
	debug_face_enabled = true
	debug_face_deg = deg
	rotation.y = deg_to_rad(deg)

func debug_set_aim(world: Vector3) -> void:
	debug_aim_enabled = true
	debug_aim_world = world
	aim_point = world

func debug_set_state(state: String) -> void:
	debug_state = state
	if state != "":
		billboard.play_state(state)

func debug_clear() -> void:
	debug_face_enabled = false
	debug_aim_enabled = false
	debug_state = ""
	debug_hold_muzzle = false
	debug_reset_muzzle()

func debug_reset_muzzle() -> void:
	muzzle_light.light_energy = 0.0
	flash.modulate = Color(1, 1, 1, 0)
