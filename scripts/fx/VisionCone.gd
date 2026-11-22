extends Node3D
class_name VisionCone
## 玩家视野遮罩：默认 120° 总视野，其中 80° 清晰，外侧渐变到暗，背后压暗。
## 只压暗场景，不隐藏场景本身；敌人由 Enemy 自己按视野淡出。

const BASE_CLEAR_HALF := 40.0   # 80° 主视野的一半
const BASE_TOTAL_HALF := 60.0   # 120° 总视野的一半
const BASE_RANGE := 12.0
const MAX_ALPHA := 0.86
const INNER_RADIUS := 0.6
const HEIGHT := 3.3

var player: Doll

var clear_half := BASE_CLEAR_HALF
var total_half := BASE_TOTAL_HALF
var range_m := BASE_RANGE

var _mesh_instance: MeshInstance3D
var _yaw := 0.0

static func alpha_for_angle(deg: float, clear_half_deg := BASE_CLEAR_HALF, total_half_deg := BASE_TOTAL_HALF) -> float:
	var a := absf(wrapf(deg, -180.0, 180.0))
	if a <= clear_half_deg:
		return 0.0
	if a >= total_half_deg:
		return MAX_ALPHA
	return (a - clear_half_deg) / (total_half_deg - clear_half_deg) * MAX_ALPHA

func setup(p: Doll) -> void:
	player = p
	_yaw = p.global_rotation.y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0, 0, 0, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 遮罩悬在墙顶下方，但需要稳定覆盖地面与物件，因此不做深度测试。
	mat.no_depth_test = true
	mat.render_priority = 3
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.material_override = mat
	_mesh_instance.cast_shadow = 0
	add_child(_mesh_instance)
	apply(p.vision_clear_half, p.vision_total_half, p.vision_range)

## 视野升级后重建遮罩几何。
func apply(new_clear_half: float, new_total_half: float, new_range: float) -> void:
	clear_half = new_clear_half
	total_half = new_total_half
	range_m = new_range
	if _mesh_instance == null:
		return
	_mesh_instance.mesh = _build_mesh()

func _build_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segments := 64
	var start := clear_half
	var span := 360.0 - clear_half * 2.0
	for i in segments + 1:
		var deg := start + span * float(i) / float(segments)
		var a := deg_to_rad(deg)
		var alpha := alpha_for_angle(deg, clear_half, total_half)
		var dir := Vector3(sin(a), 0.0, cos(a))
		st.set_color(Color(1, 1, 1, alpha))
		st.add_vertex(dir * INNER_RADIUS)
		st.set_color(Color(1, 1, 1, alpha))
		st.add_vertex(dir * range_m)
	return st.commit()

func _process(dt: float) -> void:
	if player == null or not is_visible_in_tree():
		return
	global_position = player.global_position + Vector3(0, HEIGHT, 0)
	_yaw = lerp_angle(_yaw, player.global_rotation.y, 1.0 - exp(-14.0 * dt))
	rotation.y = _yaw
