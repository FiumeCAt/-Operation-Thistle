extends RefCounted
class_name PropKit
## 程序化 3D 道具：容器、家具、机械摆件。全部用盒子/圆柱拼装，无外部模型依赖。
## 每个 build_* 返回占地 Rect2（世界 XZ），调用方拿去做占位登记。

const WALL_TEX := "res://assets/art/env/lineart_wall_2_5.png"
const FLOOR_TEX := "res://assets/art/env/lineart_floor_2_5.png"

static var _cache: Dictionary = {}

static func mat(key: StringName) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D
	match key:
		&"metal":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.30, 0.34, 0.39)
			m.metallic = 0.7
			m.roughness = 0.42
		&"dark":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.11, 0.12, 0.14)
			m.roughness = 0.85
		&"amber":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(1.0, 0.66, 0.26)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.58, 0.2)
			m.emission_energy_multiplier = 2.2
		&"hazard":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.92, 0.62, 0.18)
			m.emission_enabled = true
			m.emission = Color(0.85, 0.52, 0.12)
			m.emission_energy_multiplier = 0.3
		&"fabric":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.52, 0.55, 0.6)
			m.roughness = 0.95
		&"screen":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.35, 0.85, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.22, 0.7, 0.95)
			m.emission_energy_multiplier = 1.6
		&"organic":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.42, 0.13, 0.18)
			m.emission_enabled = true
			m.emission = Color(0.55, 0.08, 0.12)
			m.emission_energy_multiplier = 0.9
			m.roughness = 0.55
		&"wall":
			m = StandardMaterial3D.new()
			m.albedo_texture = load(WALL_TEX)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.45, 0.45, 0.45)
			m.albedo_color = Color(0.92, 0.96, 1.02)
			m.roughness = 0.95
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_:
			m = StandardMaterial3D.new()
			m.albedo_texture = load(FLOOR_TEX)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.30, 0.30, 0.30)
			m.albedo_color = Color(0.86, 0.90, 0.96)
			m.roughness = 0.97
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_cache[key] = m
	return m

static func box(host: Node3D, pos: Vector3, size: Vector3, key: StringName, solid := true) -> Node3D:
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = pos
		host.add_child(body)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat(key)
		body.add_child(mi)
		return body
	var vis := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = size
	vis.mesh = bm2
	vis.material_override = mat(key)
	vis.position = pos
	vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(vis)
	return vis

## 1.8×2.1×0.55 金属货架：背板 + 三层隔板
static func shelf(host: Node3D, pos: Vector3, side: float) -> Rect2:
	var w := 1.8
	var d := 0.55
	var h := 2.1
	box(host, pos + Vector3(0, h * 0.5, 0), Vector3(w, 0.08, d), &"metal")
	box(host, pos + Vector3(0, h - 0.04, 0), Vector3(w, 0.08, d), &"metal")
	for sx in [-1.0, 1.0]:
		box(host, pos + Vector3(sx * (w * 0.5 - 0.04), h * 0.5, 0), Vector3(0.08, h, d), &"metal")
	box(host, pos + Vector3(0, h * 0.5, side * (d * 0.5 - 0.02)), Vector3(w, h, 0.05), &"dark")
	for i in 3:
		box(host, pos + Vector3(0, 0.55 + float(i) * 0.62, 0), Vector3(w - 0.12, 0.05, d - 0.06), &"metal")
	box(host, pos + Vector3(0, h * 0.72, -side * (d * 0.5 + 0.01)), Vector3(w * 0.7, 0.04, 0.03), &"amber", false)
	box(host, pos + Vector3(0, h - 0.03, -side * (d * 0.5 + 0.01)), Vector3(w * 0.94, 0.05, 0.03), &"amber", false)
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))

## 0.9×2.0×0.55 个人储物柜（双门）
static func locker(host: Node3D, pos: Vector3, side: float) -> Rect2:
	var w := 0.9
	var d := 0.55
	var h := 2.0
	box(host, pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d), &"metal")
	box(host, pos + Vector3(0, h * 0.5, side * (d * 0.5 + 0.005)), Vector3(0.02, h - 0.12, 0.02), &"dark", false)
	for s in [-1.0, 1.0]:
		box(host, pos + Vector3(s * 0.12, h * 0.55, side * (d * 0.5 + 0.01)), Vector3(0.05, 0.16, 0.03), &"amber", false)
	box(host, pos + Vector3(0, h + 0.02, 0), Vector3(w, 0.05, d), &"hazard", false)
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))

## 2.0×1.5×0.95 双层床
static func bunk(host: Node3D, pos: Vector3, side: float) -> Rect2:
	var w := 2.0
	var d := 0.95
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(host, pos + Vector3(sx * (w * 0.5 - 0.05), 0.78, sz * (d * 0.5 - 0.05)), Vector3(0.08, 1.56, 0.08), &"metal")
	for level in [0.45, 1.32]:
		box(host, pos + Vector3(0, level, 0), Vector3(w, 0.09, d), &"metal")
		box(host, pos + Vector3(0, level + 0.13, 0), Vector3(w - 0.18, 0.18, d - 0.12), &"fabric")
	box(host, pos + Vector3(0, 1.5, -side * (d * 0.5 - 0.02)), Vector3(w, 0.05, 0.03), &"amber", false)
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))

## 1.7×1.3×0.9 柴油发电机：机身 + 排气管 + 琥珀散热口
static func generator(host: Node3D, pos: Vector3) -> Rect2:
	var w := 1.7
	var d := 0.9
	box(host, pos + Vector3(0, 0.55, 0), Vector3(w, 0.9, d), &"dark")
	box(host, pos + Vector3(0, 1.05, 0), Vector3(w - 0.2, 0.12, d - 0.1), &"metal")
	for i in 4:
		box(host, pos + Vector3(-0.55 + float(i) * 0.36, 0.55, d * 0.5 + 0.01), Vector3(0.24, 0.42, 0.02), &"amber", false)
	var pipe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 1.1
	pipe.mesh = cyl
	pipe.material_override = mat(&"metal")
	pipe.position = pos + Vector3(w * 0.35, 1.5, -d * 0.2)
	host.add_child(pipe)
	box(host, pos + Vector3(0, 0.08, 0), Vector3(w + 0.1, 0.16, d + 0.1), &"hazard")
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))

## 1.7×1.1×0.7 控制台：桌面 + 倾斜发光屏
static func console(host: Node3D, pos: Vector3, side: float) -> Rect2:
	var w := 1.7
	var d := 0.7
	box(host, pos + Vector3(0, 0.42, 0), Vector3(w, 0.84, d), &"metal")
	box(host, pos + Vector3(0, 0.88, 0), Vector3(w, 0.08, d + 0.08), &"dark")
	var screen := box(host, pos + Vector3(0, 1.22, side * (d * 0.5 - 0.08)), Vector3(w - 0.2, 0.56, 0.05), &"screen", false)
	screen.rotation_degrees.x = -12.0 * side
	for i in 3:
		box(host, pos + Vector3(-0.45 + float(i) * 0.45, 0.94, -side * 0.04), Vector3(0.3, 0.03, 0.18), &"amber", false)
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))

## 2.2×0.95×1.1 战术桌：桌面 + 全息地图板
static func table(host: Node3D, pos: Vector3) -> Rect2:
	var w := 2.2
	var d := 1.1
	box(host, pos + Vector3(0, 0.86, 0), Vector3(w, 0.1, d), &"metal")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(host, pos + Vector3(sx * (w * 0.5 - 0.1), 0.42, sz * (d * 0.5 - 0.1)), Vector3(0.1, 0.84, 0.1), &"metal")
	box(host, pos + Vector3(0, 0.93, 0), Vector3(w * 0.7, 0.02, d * 0.62), &"screen", false)
	box(host, pos + Vector3(0, 0.1, 0), Vector3(w * 0.8, 0.02, d * 0.7), &"hazard", false)
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))

## 2.2×1.7×1.8 箱堆：两到三个叠放
static func crate_stack(host: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> Rect2:
	var w := 1.1
	var h := 0.85
	var size := Vector3(w, h, w)
	box(host, pos + Vector3(-0.5, h * 0.5, 0), size, &"metal")
	box(host, pos + Vector3(-0.5, h + 0.02, 0), Vector3(w * 0.86, 0.04, w * 0.86), &"hazard", false)
	box(host, pos + Vector3(0.55, h * 0.5, 0.15), size, &"metal")
	box(host, pos + Vector3(0.55, h + 0.02, 0.15), Vector3(w * 0.86, 0.04, w * 0.86), &"hazard", false)
	if rng.randf() > 0.35:
		box(host, pos + Vector3(0.6, h + h * 0.5 + 0.04, 0.1), Vector3(w * 0.8, h * 0.8, w * 0.8), &"metal")
	return Rect2(Vector2(pos.x - 1.15, pos.z - 0.75), Vector2(2.3, 1.5))

## 油桶（圆柱 + 箍）
static func barrel(host: Node3D, pos: Vector3) -> Rect2:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.36
	cyl.bottom_radius = 0.36
	cyl.height = 0.95
	body.mesh = cyl
	body.material_override = mat(&"metal")
	body.position = pos + Vector3(0, 0.48, 0)
	host.add_child(body)
	var cs := StaticBody3D.new()
	cs.collision_layer = 1
	cs.collision_mask = 0
	cs.position = pos + Vector3(0, 0.48, 0)
	host.add_child(cs)
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 0.36
	cyl_shape.height = 0.95
	shape.shape = cyl_shape
	cs.add_child(shape)
	box(host, pos + Vector3(0, 0.66, 0), Vector3(0.76, 0.06, 0.76), &"hazard", false)
	return Rect2(Vector2(pos.x - 0.4, pos.z - 0.4), Vector2(0.8, 0.8))

## 巢穴卵荚：压扁球体 + 深色底座 + 琥珀脉络
static func pod(host: Node3D, pos: Vector3) -> Rect2:
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.25
	body.mesh = sphere
	body.material_override = mat(&"organic")
	body.position = pos + Vector3(0, 0.55, 0)
	host.add_child(body)
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.66
	cyl.height = 0.14
	base.mesh = cyl
	base.material_override = mat(&"dark")
	base.position = pos + Vector3(0, 0.07, 0)
	host.add_child(base)
	var cs := StaticBody3D.new()
	cs.collision_layer = 1
	cs.collision_mask = 0
	cs.position = pos + Vector3(0, 0.55, 0)
	host.add_child(cs)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.9, 1.1, 0.9)
	shape.shape = box_shape
	cs.add_child(shape)
	for i in 3:
		var angle := float(i) * 2.1
		box(host, pos + Vector3(cos(angle) * 0.4, 0.45 + float(i) * 0.18, sin(angle) * 0.4),
			Vector3(0.06, 0.34, 0.06), &"amber", false)
	return Rect2(Vector2(pos.x - 0.6, pos.z - 0.6), Vector2(1.2, 1.2))

## 沿墙管线（纯装饰，无碰撞）
static func pipe_run(host: Node3D, from: Vector3, to: Vector3, y: float) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var pipe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = length
	pipe.mesh = cyl
	pipe.material_override = mat(&"metal")
	var mid := (from + to) * 0.5
	mid.y = y
	pipe.position = mid
	pipe.rotation_degrees.z = 90.0
	pipe.rotation_degrees.y = rad_to_deg(atan2(to.z - from.z, to.x - from.x))
	host.add_child(pipe)
	for t in [0.25, 0.75]:
		var clamp_box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.2, 0.14)
		clamp_box.mesh = bm
		clamp_box.material_override = mat(&"dark")
		clamp_box.position = mid + Vector3((to.x - from.x) * (t - 0.5), 0.14, (to.z - from.z) * (t - 0.5))
		host.add_child(clamp_box)

## 站姿装甲架：底座 + 躯干 + 头盔（基地用）
static func armor_stand(host: Node3D, pos: Vector3) -> Rect2:
	box(host, pos + Vector3(0, 0.05, 0), Vector3(0.9, 0.1, 0.9), &"dark")
	box(host, pos + Vector3(0, 0.22, 0), Vector3(0.35, 0.35, 0.35), &"metal")
	box(host, pos + Vector3(0, 1.0, 0), Vector3(0.62, 0.95, 0.42), &"metal")
	box(host, pos + Vector3(0, 1.62, 0), Vector3(0.3, 0.3, 0.3), &"metal")
	box(host, pos + Vector3(0, 1.2, 0.22), Vector3(0.3, 0.5, 0.02), &"amber", false)
	return Rect2(Vector2(pos.x - 0.45, pos.z - 0.45), Vector2(0.9, 0.9))

## 武器架：三联挂架（基地用）
static func weapon_rack(host: Node3D, pos: Vector3, side: float) -> Rect2:
	var w := 2.4
	var d := 0.45
	box(host, pos + Vector3(0, 1.15, 0), Vector3(w, 2.3, d), &"dark")
	for i in 3:
		var x := -0.7 + float(i) * 0.7
		box(host, pos + Vector3(x, 1.15, side * (d * 0.5 + 0.02)), Vector3(0.42, 0.9, 0.06), &"metal", false)
		box(host, pos + Vector3(x, 1.72, side * (d * 0.5 + 0.03)), Vector3(0.2, 0.05, 0.04), &"amber", false)
	box(host, pos + Vector3(0, 2.32, 0), Vector3(w, 0.05, d + 0.1), &"hazard", false)
	return Rect2(Vector2(pos.x - w * 0.5, pos.z - d * 0.5), Vector2(w, d))
