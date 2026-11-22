extends RefCounted
class_name WeaponModel
## 程序化低模武器构建器。
##
## 约定：
##   - 局部原点 = 握把（挂到角色手上）
##   - 枪口朝 -Z（Godot forward），因此用 Node3D.look_at() 即可对准瞄准方向
##   - 单位是米，尺寸即真实枪长，不再需要视觉缩放系数
##   - 零件是独立节点（Magazine / Pump / Bolt / Muzzle），供换弹与上膛动画驱动
##
## 换成手工 GLB 时，只要保持同样的节点名即可直接替换，调用方不用改。

const OUTLINE := 0.006

static var _mat_cache: Dictionary = {}
static var _mat_outline: StandardMaterial3D

# ---------------------------------------------------------------- 材质

static func mat(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), metallic]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON      # 卡通硬边明暗，和立绘赛璐璐一致
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.metallic = metallic
	m.metallic_specular = 0.35
	_mat_cache[key] = m
	return m

static func mat_outline() -> StandardMaterial3D:
	if _mat_outline != null:
		return _mat_outline
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.05, 0.055, 0.07)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = OUTLINE
	_mat_outline = m
	return m

# ---------------------------------------------------------------- 图元

static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color,
		rot := Vector3.ZERO, outline := true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = 0
	parent.add_child(mi)
	if outline:
		var ol := MeshInstance3D.new()
		ol.mesh = bm
		ol.material_override = mat_outline()
		ol.position = pos
		ol.rotation_degrees = rot
		ol.cast_shadow = 0
		parent.add_child(ol)
	return mi

static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color,
		rot := Vector3.ZERO, outline := true) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = 0
	parent.add_child(mi)
	if outline:
		var ol := MeshInstance3D.new()
		ol.mesh = cm
		ol.material_override = mat_outline()
		ol.position = pos
		ol.rotation_degrees = rot
		ol.cast_shadow = 0
		parent.add_child(ol)
	return mi

# ---------------------------------------------------------------- 配色
const C_STEEL := Color(0.30, 0.32, 0.36)
const C_POLY := Color(0.14, 0.15, 0.18)
const C_DARK := Color(0.09, 0.10, 0.12)
const C_WOOD := Color(0.30, 0.19, 0.13)
const C_ACCENT := Color(0.85, 0.45, 0.16)

# ---------------------------------------------------------------- 入口

static func build(kind: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "WeaponModel"
	var mz := Node3D.new()
	mz.name = "Muzzle"
	root.add_child(mz)
	var grip := Marker3D.new()
	grip.name = "Grip"
	root.add_child(grip)
	match kind:
		&"g17":
			_pistol(root, mz)
			grip.position = Vector3(0, -0.045, 0.030)
			root.set_meta("length", 0.20)
		&"saiga12k":
			_saiga(root, mz)
			grip.position = Vector3(0, -0.060, 0.055)
			root.set_meta("length", 0.82)
		&"m1014":
			_m1014(root, mz)
			grip.position = Vector3(0, -0.065, 0.045)
			root.set_meta("length", 0.89)
		_:
			_m870(root, mz)
			grip.position = Vector3(0, -0.055, 0.055)
			root.set_meta("length", 0.98)
	return root

# ---------------------------------------------------------------- 各型号
## 泵动霰弹：机匣 + 长枪管 + 管仓 + 可动护木 + 固定枪托
static func _m870(root: Node3D, mz: Node3D) -> void:
	box(root, Vector3(0.048, 0.085, 0.22), Vector3(0, 0.015, -0.02), C_STEEL)      # 机匣
	cyl(root, 0.019, 0.50, Vector3(0, 0.038, -0.36), C_STEEL, Vector3(90, 0, 0))    # 枪管
	cyl(root, 0.017, 0.42, Vector3(0, -0.008, -0.34), C_DARK, Vector3(90, 0, 0))    # 管仓
	box(root, Vector3(0.030, 0.022, 0.03), Vector3(0, 0.056, -0.575), C_ACCENT, Vector3.ZERO, false)  # 准星
	# 护木（可动零件）
	var pump := Node3D.new()
	pump.name = "Pump"
	pump.position = Vector3(0, -0.006, -0.30)
	root.add_child(pump)
	box(pump, Vector3(0.056, 0.052, 0.15), Vector3.ZERO, C_POLY)
	for i in 4:
		box(pump, Vector3(0.060, 0.010, 0.012), Vector3(0, 0.014, -0.045 + i * 0.030), C_DARK, Vector3.ZERO, false)
	# 握把与枪托
	box(root, Vector3(0.040, 0.10, 0.055), Vector3(0, -0.075, 0.055), C_POLY, Vector3(-12, 0, 0))
	box(root, Vector3(0.044, 0.075, 0.30), Vector3(0, -0.020, 0.20), C_POLY, Vector3(4, 0, 0))
	box(root, Vector3(0.050, 0.090, 0.045), Vector3(0, -0.030, 0.345), C_DARK)
	mz.position = Vector3(0, 0.038, -0.62)

## 半自动战斗霰弹：短枪管 + 散热罩 + 手枪握把 + 伸缩托
static func _m1014(root: Node3D, mz: Node3D) -> void:
	box(root, Vector3(0.050, 0.090, 0.24), Vector3(0, 0.012, -0.02), C_STEEL)
	cyl(root, 0.020, 0.40, Vector3(0, 0.036, -0.30), C_STEEL, Vector3(90, 0, 0))
	# 散热罩
	cyl(root, 0.028, 0.22, Vector3(0, 0.036, -0.26), C_DARK, Vector3(90, 0, 0), false)
	for i in 5:
		box(root, Vector3(0.056, 0.008, 0.008), Vector3(0, 0.036, -0.34 + i * 0.038), C_POLY, Vector3.ZERO, false)
	cyl(root, 0.016, 0.26, Vector3(0, -0.006, -0.30), C_DARK, Vector3(90, 0, 0))
	box(root, Vector3(0.030, 0.020, 0.028), Vector3(0, 0.054, -0.47), C_ACCENT, Vector3.ZERO, false)
	# 手枪握把
	box(root, Vector3(0.040, 0.115, 0.052), Vector3(0, -0.085, 0.045), C_POLY, Vector3(-14, 0, 0))
	# 伸缩托
	box(root, Vector3(0.034, 0.030, 0.16), Vector3(0, 0.005, 0.20), C_DARK)
	box(root, Vector3(0.048, 0.085, 0.045), Vector3(0, -0.015, 0.29), C_POLY)
	mz.position = Vector3(0, 0.036, -0.50)

## 弹匣霰弹：AK 式机匣 + 前挂弹匣 + 骨架托
static func _saiga(root: Node3D, mz: Node3D) -> void:
	box(root, Vector3(0.050, 0.088, 0.26), Vector3(0, 0.010, -0.02), C_STEEL)
	cyl(root, 0.019, 0.34, Vector3(0, 0.036, -0.31), C_STEEL, Vector3(90, 0, 0))
	box(root, Vector3(0.044, 0.044, 0.18), Vector3(0, 0.006, -0.24), C_POLY)      # 木质/聚合物护木
	box(root, Vector3(0.030, 0.020, 0.028), Vector3(0, 0.054, -0.43), C_ACCENT, Vector3.ZERO, false)
	# 弹匣（可拆零件，换弹时下移）
	var mag := Node3D.new()
	mag.name = "Magazine"
	mag.position = Vector3(0, -0.075, -0.10)
	root.add_child(mag)
	box(mag, Vector3(0.036, 0.16, 0.075), Vector3.ZERO, C_DARK, Vector3(10, 0, 0))
	box(mag, Vector3(0.040, 0.012, 0.080), Vector3(0, -0.082, 0.008), C_POLY, Vector3(10, 0, 0), false)
	box(root, Vector3(0.038, 0.105, 0.052), Vector3(0, -0.080, 0.055), C_POLY, Vector3(-12, 0, 0))
	# 骨架托
	box(root, Vector3(0.026, 0.016, 0.22), Vector3(0, 0.030, 0.20), C_DARK)
	box(root, Vector3(0.026, 0.016, 0.22), Vector3(0, -0.020, 0.20), C_DARK)
	box(root, Vector3(0.034, 0.080, 0.030), Vector3(0, 0.005, 0.31), C_POLY)
	mz.position = Vector3(0, 0.036, -0.48)

## 手枪：套筒 + 聚合物握把（握把朝下，长度短）
static func _pistol(root: Node3D, mz: Node3D) -> void:
	box(root, Vector3(0.030, 0.042, 0.185), Vector3(0, 0.030, -0.045), C_STEEL)    # 套筒
	cyl(root, 0.009, 0.030, Vector3(0, 0.030, -0.150), C_DARK, Vector3(90, 0, 0))  # 枪口
	box(root, Vector3(0.028, 0.014, 0.130), Vector3(0, 0.004, -0.030), C_POLY)     # 套筒座
	box(root, Vector3(0.028, 0.105, 0.048), Vector3(0, -0.062, 0.030), C_POLY, Vector3(-16, 0, 0))  # 握把
	box(root, Vector3(0.020, 0.014, 0.030), Vector3(0, 0.056, 0.030), C_DARK, Vector3.ZERO, false)  # 击锤/照门
	box(root, Vector3(0.012, 0.012, 0.014), Vector3(0, 0.006, -0.020), C_ACCENT, Vector3.ZERO, false)
	mz.position = Vector3(0, 0.030, -0.175)
