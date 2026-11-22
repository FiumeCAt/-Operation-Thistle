extends Node3D
class_name HearingIndicator
## 玩家听觉指示：脚下静态细环 + 朝向 10m 内移动敌人的方向弧。
## 只做常驻显示，不会像一次性特效那样反复从脚底扩散。

const RADIUS := 2.6
const HEARING := 10.0
const BUCKETS := 12
const ARC_DEG := 26.0
const RING_ALPHA := 0.1
const ARC_ALPHA_MIN := 0.35
const ARC_ALPHA_MAX := 0.8

var player: Doll

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _arcs: Array[MeshInstance3D] = []
var _arc_mats: Array[StandardMaterial3D] = []
var _alphas: PackedFloat32Array = []

func setup(p: Doll) -> void:
	player = p
	_build()

func _build() -> void:
	_ring = _make_instance(_arc_mesh(360.0, 48))
	_ring_mat = _ring.material_override as StandardMaterial3D
	_ring_mat.albedo_color = Color(0.72, 0.88, 1.0, RING_ALPHA)
	_ring.scale = Vector3.ONE * RADIUS
	add_child(_ring)

	_alphas.resize(BUCKETS)
	for i in BUCKETS:
		var arc := _make_instance(_arc_mesh(ARC_DEG, 16))
		arc.rotation.y = -float(i) * TAU / float(BUCKETS)
		arc.scale = Vector3.ONE * RADIUS
		arc.visible = false
		add_child(arc)
		_arcs.append(arc)
		_arc_mats.append(arc.material_override as StandardMaterial3D)

func _make_instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mi.material_override = mat
	return mi

## 环形细带：内外半径只差 0.01，看起来是一条线而不是粗圈。
func _arc_mesh(arc_deg: float, segments: int) -> Mesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var t := float(i) / float(segments)
		var ang := deg_to_rad(lerpf(-arc_deg * 0.5, arc_deg * 0.5, t))
		im.surface_add_vertex(Vector3(cos(ang) * 0.995, 0.0, sin(ang) * 0.995))
		im.surface_add_vertex(Vector3(cos(ang) * 1.005, 0.0, sin(ang) * 1.005))
	im.surface_end()
	return im

func _process(dt: float) -> void:
	if player == null or not is_visible_in_tree():
		return
	global_position = player.global_position + Vector3(0, 0.03, 0)

	var targets := PackedFloat32Array()
	targets.resize(BUCKETS)
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Enemy) or node.is_dead:
			continue
		var enemy := node as Enemy
		var speed := Vector2(enemy.velocity.x, enemy.velocity.z).length()
		if speed < 0.5:
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > HEARING or distance < 0.05:
			continue
		var idx := int(round(atan2(offset.z, offset.x) / (TAU / float(BUCKETS))))
		idx = ((idx % BUCKETS) + BUCKETS) % BUCKETS
		var strength := lerpf(ARC_ALPHA_MAX, ARC_ALPHA_MIN, distance / HEARING)
		targets[idx] = maxf(targets[idx], strength)

	for i in BUCKETS:
		var target := targets[i]
		var alpha := lerpf(_alphas[i], target, 1.0 - exp(-12.0 * dt))
		_alphas[i] = alpha
		_arc_mats[i].albedo_color.a = alpha
		_arcs[i].visible = alpha > 0.02
