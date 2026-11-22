extends Node2D
class_name DollRig2D

## 模块化骨架：头、躯干、双臂、双腿、背后武器箱各自独立，带髋/肩/颈关节。
## 所有尺寸都按「角色总身高」的比例配置，因此常规比例与 Q 版共用同一套零件图。
const PART_DIR := "res://assets/art/characters/doll_b/parts/normal/"
const STYLES := {
	"normal": {
		"label": "常规比例",
		"leg": 0.36, "torso": 0.38, "head": 0.28, "arm": 0.34, "case": 0.38,
		"leg_gap": 0.05, "shoulder_gap": 0.125, "shoulder_y": 0.96, "leg_w": 1.0, "arm_w": 1.0,
	},
	"chibi": {
		"label": "Q 版",
		"leg": 0.19, "torso": 0.30, "head": 0.54, "arm": 0.22, "case": 0.28,
		"leg_gap": 0.06, "shoulder_gap": 0.10, "shoulder_y": 0.97, "leg_w": 1.55, "arm_w": 1.35,
	},
}

var height := 128.0
var style := "normal"
var direction := 0
var aim := Vector2.ZERO
var aim_enabled := false

var _hip: Node2D
var _torso_pivot: Node2D
var _torso: Sprite2D
var _neck: Node2D
var _head_pivot: Node2D
var _head: Sprite2D
var _arm_l: Node2D
var _arm_r: Node2D
var _leg_l: Node2D
var _leg_r: Node2D
var _case: Sprite2D

var _phase := 0.0
var _bob := 0.0
var _leg_len := 46.0
var _torso_h := 48.0
var _head_h := 36.0
var _arm_len := 43.0
var _part_dir := PART_DIR
var _leg_gap := 6.4
var _shoulder_x := 16.0
var _torso_scale := Vector2.ONE

var _head_textures := {}

func _ready() -> void:
	_build()

func _build() -> void:
	for child in get_children():
		child.queue_free()
	var cfg: Dictionary = STYLES.get(style, STYLES["normal"])
	_part_dir = "res://assets/art/characters/doll_b/parts/%s/" % (style if STYLES.has(style) else "normal")
	_leg_len = height * cfg.leg
	_torso_h = height * cfg.torso
	_head_h = height * cfg.head
	_arm_len = height * cfg.arm

	_hip = Node2D.new()
	_hip.name = "Hip"
	_hip.position = Vector2(0, -_leg_len)
	add_child(_hip)

	# 腿：绕髋关节转动，零件顶端挂在关节上
	var leg_w: float = cfg.leg_w
	_leg_gap = height * float(cfg.leg_gap)
	_leg_l = _limb("LegL", "leg", _leg_len, Vector2(-_leg_gap, 0), -3, leg_w)
	_leg_r = _limb("LegR", "leg", _leg_len, Vector2(_leg_gap, 0), -3, leg_w)

	# 背后武器箱（在她背上，正面朝向时被躯干挡住，只露出右侧一角）
	_case = _part("Case", "case", height * cfg.case, -2)
	_case.position = Vector2(height * 0.12, -_torso_h * 0.66)
	_case.rotation = 0.26
	_case.modulate = Color(0.82, 0.85, 0.95)
	_hip.add_child(_case)

	# 躯干：从髋部向上
	_torso_pivot = Node2D.new()
	_torso_pivot.name = "TorsoPivot"
	_hip.add_child(_torso_pivot)
	_torso = _part("Torso", "torso", _torso_h, 0)
	_torso.position = Vector2(0, -_torso_h * 0.5)
	_torso_pivot.add_child(_torso)

	# 颈关节 + 头
	_neck = Node2D.new()
	_neck.name = "Neck"
	_neck.position = Vector2(0, -_torso_h * 0.96)
	_torso_pivot.add_child(_neck)
	_head_pivot = Node2D.new()
	_head_pivot.name = "HeadPivot"
	_neck.add_child(_head_pivot)
	_head = _part("Head", "head_front", _head_h, 3)
	# 头部略微压进衣领，摆头时脖子处不露出缝隙
	_head.position = Vector2(0, -_head_h * 0.42)
	_head_pivot.add_child(_head)

	# 双臂：绕肩关节转动，垂在躯干两侧
	var shoulder_y := -_torso_h * float(cfg.shoulder_y)
	var shoulder_x: float = height * float(cfg.shoulder_gap)
	_shoulder_x = shoulder_x
	var arm_w: float = cfg.arm_w
	_arm_l = _limb("ArmL", "arm", _arm_len, Vector2(-shoulder_x, shoulder_y), 1, arm_w)
	_arm_r = _limb("ArmR", "arm", _arm_len, Vector2(shoulder_x, shoulder_y), 1, arm_w)
	for pivot in [_arm_l, _arm_r]:
		pivot.get_parent().remove_child(pivot)
		_torso_pivot.add_child(pivot)
	_torso_scale = _torso.scale

	for part in ["head_front", "head_back", "head_left", "head_right"]:
		_head_textures[part] = load(_part_dir + part + ".png")
	_apply_direction()

func _part(name: String, file: String, draw_h: float, z: int, width_scale := 1.0) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = name
	sprite.texture = load(_part_dir + file + ".png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = z
	var tex_h := float(sprite.texture.get_height())
	var s := draw_h / tex_h
	sprite.scale = Vector2(s * width_scale, s)
	return sprite

func _limb(name: String, file: String, draw_len: float, offset: Vector2, z: int, width_scale := 1.0) -> Node2D:
	var pivot := Node2D.new()
	pivot.name = name
	pivot.position = offset
	_hip.add_child(pivot)
	var sprite := _part(name + "Sprite", file, draw_len, z, width_scale)
	# 零件顶端贴在关节上，向下延伸
	sprite.position = Vector2(0, draw_len * 0.5)
	pivot.add_child(sprite)
	return pivot

func set_state(mode: String, facing: int, aim_point: Vector2, aim_on: bool, delta: float) -> void:
	direction = facing
	aim = aim_point
	aim_enabled = aim_on
	if mode != "idle":
		var rate := 11.0 if mode == "run" else 7.0
		_phase = fmod(_phase + delta * rate, TAU)
	_apply_direction()
	_pose(mode, delta)

func _apply_direction() -> void:
	var key := "head_front"
	match direction:
		1: key = "head_back"
		2: key = "head_left"
		3: key = "head_right"
	_head.texture = _head_textures.get(key, _head.texture)
	# 背面朝向时武器箱在背上，需要盖住躯干；正面朝向时被身体挡住
	_case.z_index = 2 if direction == 1 else -2
	var side := direction == 2 or direction == 3
	var facing := -1.0 if direction == 2 else (1.0 if direction == 3 else 0.0)
	# 侧面：躯干压窄、站姿收拢，避免看起来和正面一样宽
	_torso.scale = Vector2(_torso_scale.x * (0.82 if side else 1.0), _torso_scale.y)
	_leg_l.position.x = -_leg_gap * (0.8 if side else 1.0) + facing * 1.5
	_leg_r.position.x = _leg_gap * (0.8 if side else 1.0) + facing * 1.5
	# 手臂：背面朝向时藏到躯干后面；侧面只留靠近镜头的一只手在前
	_arm_l.position.x = -_shoulder_x + facing * 2.0
	_arm_r.position.x = _shoulder_x + facing * 2.0
	var l_z := 1
	var r_z := 1
	match direction:
		1:
			l_z = -1
			r_z = -1
		2:
			r_z = -1
		3:
			l_z = -1
	for pair in [[_arm_l, l_z], [_arm_r, r_z]]:
		for child in pair[0].get_children():
			child.z_index = pair[1]

func _pose(mode: String, delta: float) -> void:
	var amp := 0.0
	if mode == "walk":
		amp = 0.45
	elif mode == "run":
		amp = 0.62
	var swing := sin(_phase) * amp
	_leg_l.rotation = swing
	_leg_r.rotation = -swing
	_arm_l.rotation = -swing * 0.75
	_arm_r.rotation = swing * 0.75

	var target_bob := 0.0
	if mode != "idle":
		# 腿绕髋关节摆动会把脚抬离地面；髋部下沉同样幅度，保证支撑脚踩实。
		target_bob = _leg_len * (1.0 - cos(swing)) * 0.85
	else:
		target_bob = sin(Time.get_ticks_msec() * 0.002) * 0.6
	_bob = lerpf(_bob, target_bob, clampf(delta * 14.0, 0.0, 1.0))
	_hip.position.y = -_leg_len + _bob

	var lean := 0.0
	if mode == "run":
		lean = 0.13
	elif mode == "walk":
		lean = 0.05
	_torso_pivot.rotation = lerpf(_torso_pivot.rotation, lean, clampf(delta * 10.0, 0.0, 1.0))

	var tilt := 0.0
	if aim_enabled:
		var offset := aim - global_position
		if offset.length() > 2.0:
			tilt = clampf(offset.x / 120.0, -1.0, 1.0) * 0.26
	_head_pivot.rotation = lerp_angle(_head_pivot.rotation, tilt, clampf(delta * 12.0, 0.0, 1.0))

## 供外部取用的关节节点（后续接武器/命中判定用）
func get_joint(joint_name: String) -> Node2D:
	return find_child(joint_name, true, false) as Node2D
