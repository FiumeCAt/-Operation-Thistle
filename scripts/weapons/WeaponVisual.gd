extends Node3D
class_name WeaponVisual
## L1 武器图层：3D 低模武器，挂在角色手部锚点上。
##
## 相比旧方案（单张侧视贴图 + 屏幕内旋转）：
##   - 360° 全向朝向，不再有 ±90° 翻转 / ±42° 夹角的崩溃角度
##   - 参与 3D 深度测试，会被墙体遮挡
##   - 零件是独立节点（Magazine / Pump / Muzzle），可直接做换弹与上膛动画
##   - 枪口来自模型节点，火光/弹道起点不再靠贴图像素推算

const GROUP_PITCH := {
	"LOW": -26.0,     # 低待命：枪口下压
	"AIM": 0.0,       # 据枪：水平指向瞄准点
	"RELOAD": -12.0,  # 装填：略微内倾
}

var doll: Doll
var weapon: PlayerWeapon

var model: Node3D
var muzzle_node: Node3D
var grip_node: Node3D
var enabled := true

func setup(d: Doll, w: PlayerWeapon) -> void:
	doll = d
	weapon = w
	process_priority = 100
	reload_visual()

func reload_visual() -> void:
	if model != null and is_instance_valid(model):
		model.queue_free()
		model = null
		muzzle_node = null
		grip_node = null
	if weapon == null or weapon.weapon == null:
		return
	model = WeaponModel.build(StringName(weapon.weapon.model_kind))
	add_child(model)
	muzzle_node = model.get_node_or_null("Muzzle")
	grip_node = model.get_node_or_null("Grip")
	model.visible = enabled
	sync_pose()

func set_enabled(v: bool) -> void:
	enabled = v
	if model != null and is_instance_valid(model):
		model.visible = v

func current_group() -> String:
	if doll == null or doll.billboard == null:
		return "LOW"
	match doll.billboard.current_anim:
		"reload":
			return "RELOAD"
		"aim", "fire":
			return "AIM"
		_:
			return "LOW"

func _process(_dt: float) -> void:
	sync_pose()

func sync_pose(aiming_shot: bool = false) -> void:
	if doll == null or not is_instance_valid(model) or not is_instance_valid(grip_node) or not is_instance_valid(muzzle_node):
		return
	if aiming_shot:
		doll._update_aim()
		if doll.billboard.current_anim != "fire":
			doll.billboard.play_state("aim")
	doll.billboard.sync_direction()
	model.visible = enabled and doll.billboard.current_anim != "death"
	var group := current_group()
	var hand := doll.hand_anchor_world(group)
	var target := doll.aim_point - hand
	if target.length_squared() < 0.000001:
		target = Vector3(sin(doll.rotation.y), 0.0, cos(doll.rotation.y))
	var offset := muzzle_node.position - grip_node.position
	var forward_distance := sqrt(maxf(target.length_squared() - offset.x * offset.x - offset.y * offset.y, 0.000001))
	var local_target := Vector3(offset.x, offset.y, -forward_distance)
	var up := Vector3.UP if absf(target.normalized().dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	var orientation := Basis.looking_at(target, up) * Basis.looking_at(local_target, Vector3.UP).inverse()
	var pitch := float(GROUP_PITCH.get(group, 0.0))
	orientation = orientation * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	model.global_transform = Transform3D(orientation, hand - orientation * grip_node.position)
	doll.set_muzzle_world(muzzle_node.global_position)

func get_muzzle_position() -> Vector3:
	return muzzle_node.global_position if is_instance_valid(muzzle_node) else global_position

func get_barrel_direction() -> Vector3:
	return -muzzle_node.global_basis.z.normalized() if is_instance_valid(muzzle_node) else Vector3.FORWARD

func get_grip_position() -> Vector3:
	return grip_node.global_position if is_instance_valid(grip_node) else global_position
