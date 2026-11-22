extends Node3D
class_name LevelGenerator
## 程序化关卡：主轴走廊 + 交替侧房 + 门洞 + 掩体 + 终点竖井。
##
## 尺度沿用设计方案 §6.1：走廊 6m、房间 14×10m、墙高 3.4m、段长 24m。
## 生成顺序固定：先几何 → 再烘焙导航网格 → 场景就绪后由 Main 生成 actor。
## 导航必须在几何建完之后烘焙，否则敌人会没有可走面。

const TARGET_SCRIPT := preload("res://scripts/dev/TargetDummy.gd")
const ZPIX_FONT := preload("res://assets/art/ui/Zpix.ttf")

const H := 2.4               # 墙高：剖面式 2.5D，墙只到角色头部上方，能俯看布局
const T := 0.4               # 墙厚
const CORRIDOR_HALF := 3.0   # 走廊半宽（总宽 6m）
const SEG_LEN := 24.0        # 段长
const ROOM_W := 14.0         # 房间宽（沿 X）
const ROOM_D := 10.0         # 房间深（沿 Z）
const DOOR_W := 3.0          # 门洞净宽

@export var seg_count := 5
@export var level_seed := 20261025

## 供 Main 使用
var player_spawn := Vector3(4.0, 0.02, 0.0)
var enemy_spawns: Array[Vector3] = []
var room_centers: Array[Vector3] = []
var search_containers: Array[StaticBody3D] = []
var exit_position := Vector3.ZERO
var exit_highlight: MeshInstance3D
var depth := 1
var spawns_snapped := false
var rooms: Array[Dictionary] = []
var doors: Array[StaticBody3D] = []
var occupied: Array[Rect2] = []
var cover_rects: Array[Rect2] = []
var reserved_rects: Array[Rect2] = []

func _reserve(rect: Rect2) -> void:
	reserved_rects.append(rect)
	occupied.append(rect)

var enemy_kinds: Array[StringName] = []
var explored: Dictionary = {}
var room_fog: Array[MeshInstance3D] = []
var room_fog_labels: Array[Label3D] = []
static var _border_texture: ImageTexture
const ROOM_TYPES := ["军械库", "医疗站", "储藏室", "巢穴", "控制室", "宿舍区", "机房"]
const ROOM_PROFILES := {
	"军械库": {"loot": &"ammo", "reward": 2, "weights": {"ammo": 0.75, "resource": 0.20, "repair": 0.05}, "risk": "中等遭遇 · 弹药收益"},
	"医疗站": {"loot": &"repair", "reward": 1, "weights": {"repair": 0.75, "resource": 0.20, "ammo": 0.05}, "risk": "低强度搜刮 · 恢复收益"},
	"储藏室": {"loot": &"resource", "reward": 4, "weights": {"resource": 0.80, "ammo": 0.15, "repair": 0.05}, "risk": "低掩护 · 资源收益"},
	"巢穴": {"loot": &"resource", "reward": 3, "weights": {"resource": 0.45, "ammo": 0.35, "repair": 0.20}, "risk": "高压力战斗 · 高收益"},
	"控制室": {"loot": &"resource", "reward": 3, "weights": {"resource": 0.55, "ammo": 0.30, "repair": 0.15}, "risk": "观察路线 · 远程压力"},
	"宿舍区": {"loot": &"resource", "reward": 2, "weights": {"resource": 0.60, "repair": 0.25, "ammo": 0.15}, "risk": "低强度搜刮 · 狭道掩体"},
	"机房": {"loot": &"ammo", "reward": 2, "weights": {"ammo": 0.45, "resource": 0.40, "repair": 0.15}, "risk": "设备掩体 · 狭道遭遇"},
}

func explore(point: Vector3) -> void:
	for i in rooms.size():
		if (rooms[i]["rect"] as Rect2).has_point(Vector2(point.x, point.z)) and not explored.has(i):
			explored[i] = true
			_reveal_room(i)

## 未探索房间的"未知区域"遮罩：在墙顶以下盖一层暗色顶板，顶部悬浮"未探索"。
## 顶板低于墙顶，从侧面不会形成一堵黑墙；只做视觉遮挡，不带碰撞。
func _build_room_fog(cx: float, cz: float, xa: float, xb: float, near: float, far: float) -> void:
	var depth := absf(far - near)
	var slab_h := 0.12
	var size := Vector3(maxf(1.0, xb - xa - 0.2), slab_h, maxf(1.0, depth - 0.2))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = Vector3(cx, H - 0.35, (near + far) * 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.030, 0.040, 0.055, 1.0)
	mi.material_override = mat
	mi.cast_shadow = 0
	add_child(mi)
	room_fog.append(mi)

	# 顶板四边加一圈暗琥珀描边，读作"未扫描区域"而不是普通黑块。
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.72, 0.44, 0.16)
	edge.emission_enabled = true
	edge.emission = Color(0.78, 0.44, 0.12)
	edge.emission_energy_multiplier = 0.6
	for spec in [
		[Vector3(0.0, 0.07, size.z * 0.5), Vector3(size.x, 0.02, 0.03)],
		[Vector3(0.0, 0.07, -size.z * 0.5), Vector3(size.x, 0.02, 0.03)],
		[Vector3(size.x * 0.5, 0.07, 0.0), Vector3(0.03, 0.02, size.z)],
		[Vector3(-size.x * 0.5, 0.07, 0.0), Vector3(0.03, 0.02, size.z)],
	]:
		var frame := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = spec[1]
		frame.mesh = fb
		frame.position = spec[0]
		frame.material_override = edge
		frame.cast_shadow = 0
		mi.add_child(frame)

	var tag := Label3D.new()
	tag.text = "未探索"
	tag.font = ZPIX_FONT
	tag.font_size = 40
	tag.pixel_size = 0.005
	tag.modulate = Color(0.82, 0.58, 0.26, 0.9)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(cx, H - 0.2, (near + far) * 0.5)
	add_child(tag)
	room_fog_labels.append(tag)

func _reveal_room(index: int) -> void:
	if index < 0 or index >= room_fog.size():
		return
	if index < room_fog_labels.size() and is_instance_valid(room_fog_labels[index]):
		room_fog_labels[index].hide()
	if is_instance_valid(room_fog[index]):
		room_fog[index].hide()

func _on_door_opened(room_index: int) -> void:
	if room_index < 0 or room_index >= rooms.size() or explored.has(room_index):
		return
	explored[room_index] = true
	_reveal_room(room_index)

func _free_space(rect: Rect2) -> bool:
	for used in occupied:
		if used.grow(0.6).intersects(rect):
			return false
	return true

var nav_region: NavigationRegion3D

var _rng := RandomNumberGenerator.new()
var _total_len := 0.0

# 材质
var mat_wall: StandardMaterial3D
var mat_floor: StandardMaterial3D
var mat_wall_trim: StandardMaterial3D
var mat_wall_base: StandardMaterial3D
var mat_room_floor: StandardMaterial3D
var mat_hazard: StandardMaterial3D
var mat_metal: StandardMaterial3D
var mat_dark: StandardMaterial3D
var mat_amber: StandardMaterial3D
var _window_materials: Dictionary = {}

func update_wall_window(center: Vector2, logical_size: Vector2, radius: float, enabled: bool) -> void:
	for material: ShaderMaterial in _window_materials.values():
		material.set_shader_parameter("window_center", center)
		material.set_shader_parameter("logical_size", logical_size)
		material.set_shader_parameter("window_radius", radius)
		material.set_shader_parameter("window_enabled", enabled)

## 玩家透窗：只在相机到玩家的射线被墙挡住时开启，避免角色像浮在墙上。
func update_player_window(center: Vector2, logical_size: Vector2, radius: float, enabled: bool) -> void:
	for material: ShaderMaterial in _window_materials.values():
		material.set_shader_parameter("logical_size", logical_size)
		material.set_shader_parameter("player_window_center", center)
		material.set_shader_parameter("player_window_radius", radius)
		material.set_shader_parameter("player_window_enabled", enabled)

func _window_material(source: StandardMaterial3D) -> ShaderMaterial:
	if _window_materials.has(source):
		return _window_materials[source]
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/wall_window.gdshader")
	material.set_shader_parameter("albedo", source.albedo_color)
	material.set_shader_parameter("albedo_texture", source.albedo_texture)
	material.set_shader_parameter("triplanar", source.uv1_triplanar)
	material.set_shader_parameter("uv_scale", source.uv1_scale)
	material.set_shader_parameter("roughness", source.roughness)
	material.set_shader_parameter("metallic", source.metallic)
	material.set_shader_parameter("emission", source.emission * source.emission_energy_multiplier if source.emission_enabled else Color.BLACK)
	_window_materials[source] = material
	return material

func _apply_wall_window(mesh: MeshInstance3D, source: StandardMaterial3D) -> void:
	# 原材质仅投影：圆窗不会在太阳/手电阴影里挖洞。
	if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		var shadow := MeshInstance3D.new()
		shadow.name = "WallShadow"
		shadow.mesh = mesh.mesh
		shadow.material_override = source
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mesh.add_child(shadow)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = _window_material(source)

func _ready() -> void:
	_rng.seed = level_seed
	seg_count = 5 + floori(float(depth - 1) / 2.0)
	_reserve(Rect2(Vector2(player_spawn.x - 2, -2), Vector2(4, 4)))
	_total_len = float(seg_count) * SEG_LEN
	_reserve(Rect2(Vector2(-1, -0.6), Vector2(_total_len + 2, 1.2)))
	_make_materials()
	_build_corridor()
	_build_rooms()
	_build_covers()
	_build_lights()
	_build_exit()
	_build_targets()
	_build_nav()
	print("[Level] generated seg=%d len=%.0fm rooms=%d containers=%d enemy_spawns=%d" % [
		seg_count, _total_len, room_centers.size(), search_containers.size(), enemy_spawns.size()])

# ---------------------------------------------------------------- 材质

func _tex_mat(path: String, roughness: float, uv: Vector3, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_scale = uv
	# 与像素角色统一：卡通硬边明暗、关闭镜面高光、最近邻采样保留像素颗粒。
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m

func _make_materials() -> void:
	# triplanar 的 uv1_scale 是「每米重复次数」，所以数值要很小（0.1 ≈ 每 10m 一次）
	mat_wall = _tex_mat("res://assets/art/env/lineart_wall_2_5.png", 1.0, Vector3(0.45, 0.45, 0.45))
	mat_wall.albedo_color = Color(0.92, 0.96, 1.02)
	# 2.5D 化：墙面与地面改为 Toon 漫反射并关闭高光，减少写实 PBR 的反光层次。
	mat_wall.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_wall.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_wall_trim = StandardMaterial3D.new()
	mat_wall_trim.albedo_color = Color(0.24, 0.31, 0.38)
	mat_wall_trim.roughness = 0.78
	mat_wall_trim.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_wall_trim.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_wall_base = StandardMaterial3D.new()
	mat_wall_base.albedo_color = Color(0.12, 0.16, 0.20)
	mat_wall_base.roughness = 0.9
	mat_wall_base.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_wall_base.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_floor = _tex_mat("res://assets/art/env/lineart_floor_2_5.png", 1.0, Vector3(0.24, 0.24, 0.24))
	mat_floor.albedo_color = Color(0.82, 0.86, 0.92)
	mat_room_floor = _tex_mat("res://assets/art/env/lineart_floor_2_5.png", 1.0, Vector3(0.30, 0.30, 0.30))
	mat_room_floor.albedo_color = Color(0.86, 0.90, 0.96)
	mat_floor.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_floor.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_room_floor.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_room_floor.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_hazard = StandardMaterial3D.new()
	mat_hazard.albedo_color = Color(0.92, 0.62, 0.18)
	mat_hazard.emission_enabled = true
	mat_hazard.emission = Color(0.85, 0.52, 0.12)
	mat_hazard.emission_energy_multiplier = 0.35
	mat_metal = StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.30, 0.34, 0.39)
	mat_metal.metallic = 0.30
	mat_metal.roughness = 0.60
	mat_metal.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_metal.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_dark = StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.10, 0.11, 0.13)
	mat_dark.roughness = 0.85
	mat_dark.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_dark.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_amber = StandardMaterial3D.new()
	mat_amber.albedo_color = Color(1.0, 0.66, 0.26)
	mat_amber.emission_enabled = true
	mat_amber.emission = Color(1.0, 0.62, 0.22)
	mat_amber.emission_energy_multiplier = 2.0

# ---------------------------------------------------------------- 图元

func _solid(pos: Vector3, size: Vector3, mat: Material, architecture := false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = pos
	add_child(b)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	if mat == mat_wall or architecture:
		_apply_wall_window(mi, mat)
	return b

func _visual(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = 0
	add_child(mi)
	if mat == mat_amber and pos.y > 3.0:
		_apply_wall_window(mi, mat)
	return mi

## 把 [a,b] 区间按 gaps 切成若干段
func _segments(a: float, b: float, gaps: Array) -> Array:
	var out := []
	var cur := a
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	for g in sorted:
		var g0: float = g[0]
		var g1: float = g[1]
		if g0 > cur:
			out.append([cur, minf(g0, b)])
		cur = maxf(cur, g1)
	if cur < b:
		out.append([cur, b])
	return out

func _wall_x(x1: float, x2: float, z: float, gaps: Array) -> void:
	for seg in _segments(x1, x2, gaps):
		var a: float = seg[0]
		var b: float = seg[1]
		if b - a < 0.05:
			continue
		var center_x := (a + b) * 0.5
		var width := b - a
		_solid(Vector3(center_x, H * 0.5, z), Vector3(width, H, T), mat_wall)
		_visual(Vector3(center_x, 0.18, z), Vector3(width, 0.36, T + 0.04), mat_wall_base)
		_visual(Vector3(center_x, H - 0.12, z), Vector3(width, 0.24, T + 0.10), mat_wall_trim)
		var seam_x := a + 2.0
		while seam_x < b - 0.4:
			_visual(Vector3(seam_x, H * 0.57, z), Vector3(0.045, H * 0.78, T + 0.035), mat_wall_base)
			seam_x += 2.0

func _wall_z(z1: float, z2: float, x: float, gaps: Array) -> void:
	for seg in _segments(z1, z2, gaps):
		var a: float = seg[0]
		var b: float = seg[1]
		if b - a < 0.05:
			continue
		var center_z := (a + b) * 0.5
		var depth := b - a
		_solid(Vector3(x, H * 0.5, center_z), Vector3(T, H, depth), mat_wall)
		_visual(Vector3(x, 0.18, center_z), Vector3(T + 0.04, 0.36, depth), mat_wall_base)
		_visual(Vector3(x, H - 0.12, center_z), Vector3(T + 0.10, 0.24, depth), mat_wall_trim)
		var seam_z := a + 2.0
		while seam_z < b - 0.4:
			_visual(Vector3(x, H * 0.57, seam_z), Vector3(T + 0.035, H * 0.78, 0.045), mat_wall_base)
			seam_z += 2.0

# ---------------------------------------------------------------- 走廊

func _build_corridor() -> void:
	var x0 := -1.0
	var x1 := _total_len + 1.0
	# 地面
	_solid(Vector3((x0 + x1) * 0.5, -0.1, 0.0), Vector3(x1 - x0, 0.2, CORRIDOR_HALF * 2.0 + T * 2.0), mat_floor)

	# 门洞位置先算出来，供两侧墙开孔
	var north_gaps := []
	var south_gaps := []
	for i in seg_count:
		var cx := _room_center_x(i)
		if i % 2 == 0:
			north_gaps.append([cx - DOOR_W * 0.5, cx + DOOR_W * 0.5])
		else:
			south_gaps.append([cx - DOOR_W * 0.5, cx + DOOR_W * 0.5])

	_wall_x(x0, x1, -CORRIDOR_HALF - T * 0.5, north_gaps)
	_wall_x(x0, x1, CORRIDOR_HALF + T * 0.5, south_gaps)

	# 两端封口
	_solid(Vector3(x0 - T * 0.5, H * 0.5, 0), Vector3(T, H, CORRIDOR_HALF * 2.0 + T * 2.0), mat_wall)
	_solid(Vector3(x1 + T * 0.5, H * 0.5, 0), Vector3(T, H, CORRIDOR_HALF * 2.0 + T * 2.0), mat_wall)

	# 琥珀灯条 + 地面引导线
	_visual(Vector3((x0 + x1) * 0.5, 3.26, -CORRIDOR_HALF + 0.02), Vector3(x1 - x0, 0.05, 0.03), mat_amber)
	_visual(Vector3((x0 + x1) * 0.5, 3.26, CORRIDOR_HALF - 0.02), Vector3(x1 - x0, 0.05, 0.03), mat_amber)
	var x := x0 + 2.0
	while x < x1 - 2.0:
		_visual(Vector3(x, 0.014, 0.0), Vector3(1.2, 0.01, 0.055), mat_amber)
		x += 4.0

func _room_center_x(i: int) -> float:
	return SEG_LEN * 0.5 + float(i) * SEG_LEN

# ---------------------------------------------------------------- 侧房

func _build_rooms() -> void:
	var geo := []
	for i in seg_count:
		var cx := _room_center_x(i)
		var north := (i % 2 == 0)
		var dir := -1.0 if north else 1.0
		var cz := dir * (CORRIDOR_HALF + ROOM_D * 0.5)
		room_centers.append(Vector3(cx, 0.0, cz))

		# 房间地面
		_solid(Vector3(cx, -0.1, cz), Vector3(ROOM_W, 0.2, ROOM_D), mat_room_floor)
		_visual(Vector3(cx, 0.008, cz), Vector3(ROOM_W - 0.6, 0.016, ROOM_D - 0.6), mat_room_floor)

		var near := dir * CORRIDOR_HALF          # 靠走廊一侧的 z
		var far := dir * (CORRIDOR_HALF + ROOM_D) # 远端 z
		var xa := cx - ROOM_W * 0.5
		var xb := cx + ROOM_W * 0.5

		# 三面墙（靠走廊那面由走廊墙上的门洞充当）
		_wall_z(minf(near, far), maxf(near, far), xa, [])
		_wall_z(minf(near, far), maxf(near, far), xb, [])
		_wall_x(xa, xb, far, [])

		# 门框
		_build_door(cx, near, north)
		var room_door := doors.back() as AutoDoor
		room_door.opened.connect(_on_door_opened.bind(i))

		var kind := i % ROOM_TYPES.size()
		var room_type: String = ROOM_TYPES[kind]
		var alternate_layout := (level_seed + i) % 2 == 1
		var layout := "对称货架" if room_type == "军械库" and not alternate_layout else "分列货架" if room_type == "军械库" else "双床恢复位" if room_type == "医疗站" and not alternate_layout else "隔断医疗位" if room_type == "医疗站" else "双侧宿舍" if room_type == "宿舍区" and not alternate_layout else "错位宿舍" if room_type == "宿舍区" else "标准用途布局"
		rooms.append({"rect": Rect2(Vector2(xa, minf(near, far)), Vector2(ROOM_W, ROOM_D)),
			"type": room_type, "profile": ROOM_PROFILES[room_type], "layout": layout, "door": doors.back(), "center": Vector3(cx, 0, cz),
			"interaction": Vector3(cx + 2.5, 0.02, cz - dir * 0.7)})
		_reserve(Rect2(Vector2(cx - 2, minf(near, cz) - 1), Vector2(4, absf(cz - near) + 2)))
		var label := Label3D.new()
		label.text = ROOM_TYPES[kind]
		label.position = Vector3(cx, 2.7, near)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font = ZPIX_FONT
		label.font_size = 48
		label.pixel_size = 0.005
		add_child(label)
		_build_room_fog(cx, cz, xa, xb, near, far)
		_build_room_props(cx, cz, dir)
		_build_room_furniture(cx, cz, dir, xa, xb, near, far, kind, i)
		geo.append([cx, cz, dir, xa, xb, near, far, i])

	# 第二遍：小房间与掩体放在所有主容器之后，
	# 保证容器编号 0..seg-1 保持房间顺序，且掩体避开已登记占位。
	for g in geo:
		var cx2: float = g[0]
		var cz2: float = g[1]
		var dir2: float = g[2]
		var i2: int = g[7]
		_build_sub_room(cx2, cz2, dir2, g[3], g[4], g[5], g[6], i2)
		_place_extra_container(cx2, cz2, dir2, i2, rooms[i2]["type"])
		_build_room_covers(cx2, cz2, dir2)

## 每个房间的第二个可搜刮容器：在房间主区靠墙角落挑一个空位。
## 不放小房间里——窄房间烘不出稳定导航面，玩家会摸不到箱子。
func _place_extra_container(cx: float, cz: float, dir: float, index: int, room_type: String) -> void:
	var pz := cz + dir * (1.2 if index % 2 == 1 else 1.8)
	var candidates := [
		Vector3(cx + 4.4, 0.02, pz - dir * 1.6),
		Vector3(cx - 4.4, 0.02, pz - dir * 1.6),
		Vector3(cx + 4.4, 0.02, cz - dir * 2.6),
		Vector3(cx - 4.4, 0.02, cz - dir * 2.6),
	]
	for pos: Vector3 in candidates:
		var rect := Rect2(Vector2(pos.x - 0.95, pos.z - 0.95), Vector2(1.9, 1.9))
		if _free_space(rect):
			_add_container(pos, index, room_type, 1)
			return

## 后方小房间：偶数房浅、奇数房深，门洞左右交替。
## 深度需大于导航网格的半径侵蚀量，否则小房间会被烘成不可通行。
func _build_sub_room(cx: float, cz: float, dir: float, xa: float, xb: float,
		near: float, far: float, index: int) -> Rect2:
	var deep := index % 2 == 1
	var pz := cz + dir * (1.2 if deep else 1.8)
	var gap_w := 2.4
	# 门洞固定开在左半区，右侧专供容器，避免容器堵门
	var gap_center := cx - 3.4 - (0.3 if index % 2 == 0 else 0.0)
	var gap_lo := gap_center - gap_w * 0.5
	var gap_hi := gap_center + gap_w * 0.5
	_wall_x(xa, xb, pz, [[gap_lo, gap_hi]])
	_visual(Vector3(gap_center, 0.016, pz), Vector3(gap_w, 0.012, 0.1), mat_amber)
	_reserve(Rect2(Vector2(xa, pz - 0.25), Vector2(gap_lo - xa, 0.5)))
	_reserve(Rect2(Vector2(gap_hi, pz - 0.25), Vector2(xb - gap_hi, 0.5)))
	_reserve(Rect2(Vector2(gap_lo, pz - 0.5), Vector2(gap_w, 1.0)))

	var sub := Rect2(Vector2(xa, minf(pz, far)), Vector2(xb - xa, absf(far - pz)))
	_build_sub_room_props(sub, far, dir, deep)
	return sub

## 小房间里的收纳结构件：贴远端墙根摆放，不在中间形成路障
func _build_sub_room_props(sub: Rect2, far: float, dir: float, deep: bool) -> void:
	_reserve(PropKit.shelf(self, Vector3(sub.position.x + 1.6, 0, far - dir * 0.9), 1.0))
	if deep:
		_reserve(PropKit.barrel(self, Vector3(sub.position.x + 5.0, 0, far - dir * 0.8)))

## 主房间家具：按房型摆放货架、床位、发电机等，纯结构件（不可搜刮）
func _build_room_furniture(cx: float, cz: float, dir: float, xa: float, xb: float,
		near: float, far: float, kind: int, room_index: int) -> void:
	var wall_xa := xa + 1.1
	var wall_xb := xb - 1.1
	var alternate := (level_seed + room_index) % 2 == 1
	match kind:
		0:  # 军械库：对称货架 / 分列货架
			if alternate:
				_reserve(PropKit.shelf(self, Vector3(wall_xa, 0, cz - dir * 1.2), 1.0))
				_reserve(PropKit.shelf(self, Vector3(wall_xb, 0, cz + dir * 1.2), 1.0))
			else:
				_reserve(PropKit.shelf(self, Vector3(wall_xa, 0, cz), 1.0))
				_reserve(PropKit.locker(self, Vector3(wall_xb, 0, cz - dir * 1.6), dir))
		1:  # 医疗站：双床恢复位 / 隔断医疗位
			_reserve(PropKit.bunk(self, Vector3(wall_xa, 0, cz + (dir * 0.8 if alternate else -dir * 0.4)), dir))
			_reserve(PropKit.bunk(self, Vector3(wall_xb, 0, cz + (dir * 0.8 if alternate else -dir * 0.4)), dir))
			if alternate:
				_reserve(PropKit.locker(self, Vector3(cx, 0, cz - dir * 1.8), dir))
			else:
				_reserve(PropKit.locker(self, Vector3(wall_xb, 0, cz + dir * 1.2), dir))
		2:  # 储藏室
			_reserve(PropKit.shelf(self, Vector3(wall_xa, 0, cz + dir * 0.6), 1.0))
			_reserve(PropKit.crate_stack(self, Vector3(wall_xb - 0.9, 0, cz - dir * 1.2), _rng))
		3:  # 巢穴
			_reserve(PropKit.pod(self, Vector3(wall_xa + 0.3, 0, cz + dir * 0.9)))
			_reserve(PropKit.pod(self, Vector3(wall_xb - 0.6, 0, cz - dir * 1.4)))
			_reserve(PropKit.pod(self, Vector3(wall_xb - 1.6, 0, cz + dir * 1.8)))
		4:  # 控制室
			_reserve(PropKit.console(self, Vector3(wall_xa + 0.2, 0, cz + dir * 0.6), dir))
			_reserve(PropKit.generator(self, Vector3(wall_xb - 1.1, 0, cz - dir * 1.6)))
		5:  # 宿舍区：双侧宿舍 / 错位宿舍
			_reserve(PropKit.bunk(self, Vector3(wall_xa, 0, cz + (dir * 0.5 if not alternate else dir * 1.7)), dir))
			_reserve(PropKit.bunk(self, Vector3(wall_xb, 0, cz + (dir * 0.5 if not alternate else -dir * 1.0)), dir))
			_reserve(PropKit.locker(self, Vector3(wall_xa + 0.6, 0, cz - dir * (1.8 if not alternate else 0.2)), dir))
		6:  # 机房
			_reserve(PropKit.generator(self, Vector3(wall_xa + 0.4, 0, cz + dir * 0.4)))
			_reserve(PropKit.generator(self, Vector3(wall_xb - 1.4, 0, cz + dir * 0.4)))
	# 管线贴远端墙走，横穿房间会挡住视线
	PropKit.pipe_run(self, Vector3(xa + 0.6, 0, far - dir * 0.5), Vector3(xb - 0.6, 0, far - dir * 0.5), 2.6)

func _build_door(cx: float, z: float, _north: bool) -> void:
	# 两侧门柱 + 门楣（净宽 DOOR_W 可通行）
	var half := DOOR_W * 0.5
	var zz := z + signf(z) * T * 0.5
	for sx in [-1.0, 1.0]:
		_solid(Vector3(cx + sx * (half + 0.14), (H - 0.1) * 0.5, zz), Vector3(0.2, H - 0.1, T + 0.1), mat_metal, true)
	_solid(Vector3(cx, H - 0.15, zz), Vector3(DOOR_W + 0.5, 0.30, T + 0.1), mat_metal, true)
	_visual(Vector3(cx, H - 0.02, zz), Vector3(DOOR_W, 0.05, 0.08), mat_amber)
	_visual(Vector3(cx, 0.016, zz), Vector3(DOOR_W + 0.2, 0.012, 0.12), mat_amber)
	var door := preload("res://scripts/level/AutoDoor.gd").new()
	door.position = Vector3(cx, 0, zz)
	# 门扇跟着剖面墙一起压低，避免高出墙顶。
	door.scale = Vector3(1.0, (H - 0.2) / 2.8, 1.0)
	add_child(door)
	_apply_wall_window(door.leaf, mat_metal)
	doors.append(door)

func _build_room_props(cx: float, cz: float, dir: float) -> void:
	var room_index := rooms.size() - 1
	var room_type: String = rooms[room_index]["type"]
	var supply := _add_container(Vector3(cx + 2.5, 0.02, cz - dir * 2.0), room_index, room_type, 0)
	_reserve(Rect2(Vector2(cx + 1.7, cz - dir * 0.7 - 0.6), Vector2(1.6, 1.2)))
	var roster: Array = {
		"军械库": [&"rifleman", &"heavy"], "医疗站": [&"rifleman"], "储藏室": [&"rifleman", &"rusher"],
		"巢穴": [&"rusher", &"rusher", &"heavy"], "控制室": [&"rifleman", &"heavy"],
		"宿舍区": [&"rusher"], "机房": [&"rifleman", &"rusher"]
	}[room_type]
	# 声呐猎手从第 3 层开始进入巢穴，第 4 层起也会出现在机房。
	if room_type == "巢穴" and depth >= 3:
		roster.append(&"hunter")
	elif room_type == "机房" and depth >= 4:
		roster.append(&"hunter")
	for k in roster.size():
		# 敌人偏左半场，右侧留给小房间容器与通路；猎手单独站房间中部，避免和摆件重叠。
		var spawn := Vector3(cx - 4.5 + k * 3.0, 0.02, cz + dir * 3.0)
		if roster[k] == &"hunter":
			spawn = Vector3(cx + 1.0, 0.02, cz + dir * 1.2)
		enemy_spawns.append(spawn)
		enemy_kinds.append(roster[k])
		_reserve(Rect2(Vector2(spawn.x - 0.7, spawn.z - 0.7), Vector2(1.4, 1.4)))

func _build_room_covers(cx: float, cz: float, dir: float) -> void:
	# 2~4 组掩体
	var n := _rng.randi_range(2, 4)
	for k in n:
		var ox := _rng.randf_range(-ROOM_W * 0.32, ROOM_W * 0.32)
		var oz := _rng.randf_range(-ROOM_D * 0.30, ROOM_D * 0.30) * (-dir)
		var s := _rng.randf_range(0.9, 1.4)
		if absf(ox) < 1.8 or Vector2(ox - 2.5, oz + dir * 2.0).length() < 2.8:
			continue
		var rect := Rect2(Vector2(cx + ox - s / 2, cz + oz - s * 0.45), Vector2(s, s * 0.9))
		if _free_space(rect):
			occupied.append(rect)
			cover_rects.append(rect)
			_crate(cx + ox, cz + oz, Vector3(s, s * 0.95, s * 0.9))

## 新增可搜刮容器：自动编号、按序分配外观与奖励，并登记占位
func _weighted_loot(room_type: String, slot: int) -> StringName:
	var profile: Dictionary = ROOM_PROFILES.get(room_type, ROOM_PROFILES["储藏室"])
	if slot == 0:
		return profile["loot"]
	var weights: Dictionary = profile["weights"]
	var roll := _rng.randf()
	for effect in [&"ammo", &"repair", &"resource"]:
		roll -= float(weights.get(String(effect), 0.0))
		if roll <= 0.0:
			return effect
	return profile["loot"]

func _add_container(pos: Vector3, room_index := -1, room_type := "储藏室", slot := 0) -> StaticBody3D:
	var index := search_containers.size()
	var body := _crate(pos.x, pos.z, Vector3(1.1, 1.0, 1.0))
	body.name = "SupplyBox%d" % index
	body.set_meta("searched", false)
	body.set_meta("room_index", room_index)
	body.set_meta("room_type", room_type)
	body.set_meta("room_slot", slot)
	_style_container(body, index)
	var profile: Dictionary = ROOM_PROFILES.get(room_type, ROOM_PROFILES["储藏室"])
	body.set_meta("loot_weights", profile["weights"])
	var effect_type: StringName = _weighted_loot(room_type, slot)
	var reward: int = int(profile["reward"])
	if slot == 1 and room_type in ["控制室", "机房"]:
		effect_type = &"resource"
		reward = 2
	body.set_meta("reward", reward)
	body.set_meta("loot", {&"ammo": "弹药补给", &"repair": "维修组件", &"resource": "储藏物资"}.get(effect_type, "物资"))
	body.set_meta("loot_effect", {"type": effect_type, "amount": 30.0} if effect_type == &"repair" else {"type": effect_type})
	search_containers.append(body)
	_reserve(Rect2(Vector2(pos.x - 0.95, pos.z - 0.95), Vector2(1.9, 1.9)))
	return body

func _crate(x: float, z: float, size: Vector3) -> StaticBody3D:
	var body := _solid(Vector3(x, size.y * 0.5, z), size, mat_metal)
	var marker := _visual(Vector3(x, size.y + 0.012, z), Vector3(size.x * 0.86, 0.025, size.z * 0.86), mat_hazard)
	body.set_meta("marker", marker)
	return body

func _highlight_texture() -> ImageTexture:
	if _border_texture != null:
		return _border_texture
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 64:
		for t in 2:
			img.set_pixel(i, t, Color(1, 1, 1, 1))
			img.set_pixel(i, 63 - t, Color(1, 1, 1, 1))
			img.set_pixel(t, i, Color(1, 1, 1, 1))
			img.set_pixel(63 - t, i, Color(1, 1, 1, 1))
	_border_texture = ImageTexture.create_from_image(img)
	return _border_texture

func _style_container(body: StaticBody3D, index: int) -> void:
	var kinds := ["ammo_box", "medical_box", "material_box", "drawer_cabinet", "safe"]
	var labels := ["弹药箱", "医疗箱", "材料箱", "抽屉柜", "保险柜"]
	var slot := index % kinds.size()
	var texture := load("res://assets/art/containers/%s.png" % kinds[slot]) as Texture2D
	if texture == null:
		return
	var alpha := BitMap.new()
	alpha.create_from_image_alpha(texture.get_image(), 0.8)
	var minimum := alpha.get_size()
	var maximum := Vector2i(-1, -1)
	for y in alpha.get_size().y:
		for x in alpha.get_size().x:
			if alpha.get_bit(x, y):
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
	if maximum.x < minimum.x:
		return
	var bounds := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	var sizes := [Vector3(1.1, 0.65, 0.9), Vector3(1.0, 0.75, 0.9), Vector3(1.1, 0.7, 1.0), Vector3(0.85, 1.6, 0.85), Vector3(1.0, 1.35, 1.0)]
	var size: Vector3 = sizes[slot]
	body.position.y = size.y * 0.5
	var marker: MeshInstance3D = body.get_meta("marker")
	marker.hide()
	for child in body.get_children():
		if child is MeshInstance3D:
			child.visible = false
		elif child is CollisionShape3D:
			var shape := BoxShape3D.new()
			shape.size = size
			child.shape = shape
	var sprite := Sprite3D.new()
	sprite.name = "ContainerArt"
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(bounds)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.8
	var visual_width: float = [1.35, 1.25, 1.35, 1.05, 1.2][slot]
	sprite.pixel_size = visual_width / float(bounds.size.x)
	var visual_height := float(bounds.size.y) * sprite.pixel_size
	sprite.position.y = 0.03 - body.position.y
	sprite.offset.y = float(bounds.size.y) * 0.5
	sprite.shaded = false
	body.add_child(sprite)
	var label := Label3D.new()
	label.name = "ContainerLabel"
	label.text = labels[slot]
	label.font_size = 40
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = ZPIX_FONT
	label.position.y = sprite.position.y
	label.offset.y = (visual_height + 0.18) / label.pixel_size
	body.add_child(label)

	# 靠近时才显示的细白描边（QuadMesh + 透明中心边框贴图）。
	var highlight := MeshInstance3D.new()
	highlight.name = "Highlight"
	var quad := QuadMesh.new()
	quad.size = Vector2(visual_width * 1.1, visual_height * 1.1)
	highlight.mesh = quad
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	hmat.alpha_scissor_threshold = 0.5
	hmat.albedo_texture = _highlight_texture()
	hmat.albedo_color = Color(1, 1, 1, 0.9)
	hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	highlight.material_override = hmat
	highlight.cast_shadow = 0
	highlight.position = sprite.position + Vector3(0, visual_height * 0.5, 0)
	highlight.visible = false
	body.add_child(highlight)
	body.set_meta("container_kind", kinds[slot])

func search_container(container: StaticBody3D) -> bool:
	if not search_containers.has(container) or container.get_meta("searched", false):
		return false
	container.set_meta("searched", true)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.65, 0.48)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.35, 0.22)
	var marker: MeshInstance3D = container.get_meta("marker")
	marker.material_override = material
	for child in container.get_children():
		if child is MeshInstance3D:
			child.material_override = material
		elif child is Sprite3D:
			child.modulate = Color(0.3, 1.0, 0.55)
		elif child is Label3D:
			child.modulate = Color(0.3, 1.0, 0.55)
	return true

# ---------------------------------------------------------------- 走廊掩体

func _build_covers() -> void:
	for i in seg_count:
		var cx := _room_center_x(i)
		var n := _rng.randi_range(1, 2)
		for k in n:
			var x := cx + _rng.randf_range(-6.0, 6.0)
			var z := _rng.randf_range(-2.0, 2.0)
			# 出生点周围留空：否则玩家一进图就被箱子顶出去
			if Vector2(x - player_spawn.x, z - player_spawn.z).length() < 3.5:
				continue
			var s := _rng.randf_range(0.9, 1.3)
			if absf(x - cx) < 2.5:
				continue
			var rect := Rect2(Vector2(x - s / 2, z - s * 0.425), Vector2(s, s * 0.85))
			if _free_space(rect):
				occupied.append(rect)
				cover_rects.append(rect)
				_crate(x, z, Vector3(s, s, s * 0.85))

# ---------------------------------------------------------------- 灯光

func _build_lights() -> void:
	var x := 3.0
	while x < _total_len:
		var l := OmniLight3D.new()
		l.position = Vector3(x, H - 0.3, 0.0)
		l.light_color = Color(1.0, 0.80, 0.56)
		l.light_energy = 1.8
		l.omni_range = 12.0
		l.shadow_enabled = false
		add_child(l)
		x += SEG_LEN * 0.5

	for c in room_centers:
		var l2 := OmniLight3D.new()
		l2.position = Vector3(c.x, H - 0.3, c.z)
		l2.light_color = Color(0.66, 0.85, 1.0)
		l2.light_energy = 1.7
		l2.omni_range = 13.0
		l2.shadow_enabled = false
		add_child(l2)

# ---------------------------------------------------------------- 终点

func _build_exit() -> void:
	var x := _total_len - 1.5
	exit_position = Vector3(x, 0.02, 0.0)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.35
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.position = Vector3(x, 0.06, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.92, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.28, 0.85, 1.0)
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.cast_shadow = 0
	add_child(ring)

	var lbl := Label3D.new()
	lbl.text = "EXTRACTION"
	lbl.font = ZPIX_FONT
	lbl.font_size = 64
	lbl.pixel_size = 0.006
	lbl.modulate = Color(0.45, 0.95, 1.0)
	lbl.billboard = 1
	lbl.no_depth_test = true
	lbl.position = Vector3(x, 1.4, 0.0)
	add_child(lbl)

	# 靠近竖井时的细白描边。
	exit_highlight = MeshInstance3D.new()
	exit_highlight.name = "ExitHighlight"
	var hl := TorusMesh.new()
	hl.inner_radius = 1.16
	hl.outer_radius = 1.2
	hl.rings = 32
	hl.ring_segments = 4
	exit_highlight.mesh = hl
	exit_highlight.rotation_degrees.x = 90.0
	exit_highlight.position = Vector3(x, 0.09, 0.0)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1, 1, 1, 0.95)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	exit_highlight.material_override = hm
	exit_highlight.cast_shadow = 0
	exit_highlight.visible = false
	add_child(exit_highlight)

# ---------------------------------------------------------------- 训练靶（供截图与弹道工具使用）

func _build_targets() -> void:
	# 第一段走廊放 3 个靶，位置固定，方便自动化验收
	for p in [Vector3(10.0, 0.0, 1.8), Vector3(14.0, 0.0, -1.8), Vector3(18.0, 0.0, 0.0)]:
		var t := StaticBody3D.new()
		t.set_script(TARGET_SCRIPT)
		t.position = p + Vector3(0, 0.02, 0)
		add_child(t)

# ---------------------------------------------------------------- 导航

func _build_nav() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)

	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.35
	nm.agent_max_slope = 45.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.filter_baking_aabb = AABB(
		Vector3(-4.0, -1.5, -CORRIDOR_HALF - ROOM_D - 2.0),
		Vector3(_total_len + 8.0, 3.6, (CORRIDOR_HALF + ROOM_D + 2.0) * 2.0)
	)
	nav_region.navigation_mesh = nm

	# 显式以本节点为根解析（--script / 无编辑器场景时默认根节点取不到）
	var source := NavigationMeshSourceGeometryData3D.new()
	# 门通道始终可规划；靠近时实际门扇开门，而非声称 avoidance 能封导航。
	for door in doors:
		door.collision_layer = 0
	NavigationServer3D.parse_source_geometry_data(nm, source, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	for door in doors:
		door.collision_layer = 1

	var polys := nm.get_polygon_count()
	if polys == 0:
		push_error("[Level] 导航网格烘焙失败：0 个多边形，敌人将无法寻路")
	else:
		print("[Level] navmesh baked, polygons=%d" % polys)
	_snap_spawns_deferred()

## 烘焙完成不代表导航地图已同步；等一次同步后再吸附，否则查询会被拒绝
func _snap_spawns_deferred() -> void:
	var map := nav_region.get_navigation_map()
	for i in 120:
		await get_tree().physics_frame
		if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
			break
	_snap_spawns_to_nav()
	spawns_snapped = true

## 把敌人出生点吸附到导航面上，避免窄房/摆件把点挤出网格导致敌人原地卡死
func _snap_spawns_to_nav() -> void:
	var map := nav_region.get_navigation_map()
	for i in enemy_spawns.size():
		var point: Vector3 = enemy_spawns[i]
		var snapped := NavigationServer3D.map_get_closest_point(map, point)
		if snapped != Vector3.ZERO and point.distance_to(snapped) > 0.4:
			enemy_spawns[i] = Vector3(snapped.x, 0.02, snapped.z)
