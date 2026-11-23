extends Node2D
class_name LaserSight2D
## 下挂激光指示器：从枪口沿射击方向发射激光。
## 视觉：加法混合的多层辉光 + 沿射线渐隐的光束 + 枪口/命中点柔光斑 + 轻微呼吸闪烁。

## 激光最多延伸到这里；真正截断点由射线命中决定。
## 需要覆盖高倍镜的镜内取景上限（基础 32 米 × 瞄具视野倍率）。
const MAX_RANGE := 3200.0
const GLOW_SIZE := 64

static var _glow_tex: Texture2D

var main = null
var doll = null
var _active := false
var _has_hit := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _beam_color := Color(0.35, 1.0, 0.50)
var _time := 0.0


func setup(main_node, player) -> void:
	main = main_node
	doll = player
	# 画在曳光（z=60）之上，开火时也能看见中心线与弹道是否重合。
	z_index = 65
	# 线性过滤保证柔光晕圆润无像素锯齿。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 加法混合 + 自发光（不受迷雾 CanvasModulate 压暗）：暗处依然锐利发光，亮处不糊成色块。
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat


func _process(delta: float) -> void:
	_time += delta
	if doll == null or not is_instance_valid(doll):
		_set_active(false)
		return
	var rig = doll.weapon_rig
	if rig == null or not bool(rig.has_laser) or rig.is_holstered() or rig.is_stowing():
		_set_active(false)
		return
	if not rig.is_visible_in_tree():
		_set_active(false)
		return
	var progress := get_node_or_null("/root/Progress")
	if progress != null and progress.has_method("laser_color"):
		_beam_color = progress.laser_color()
	_from = rig.get_muzzle_position()
	if main != null and main.has_method("get_safe_shot_origin"):
		_from = main.get_safe_shot_origin(_from)
	# 与子弹共用 Main2D.aim_direction_from：同一套起点/准心/回退逻辑。
	var dir: Vector2
	if main != null and main.has_method("aim_direction_from"):
		dir = main.aim_direction_from(_from)
	else:
		var aim: Vector2 = doll.aim_target
		var offset := aim - _from
		dir = offset.normalized() if offset.length_squared() >= 64.0 \
			else rig.get_barrel_direction()
	if dir.length_squared() < 0.0001:
		_set_active(false)
		return
	var end := _from + dir * MAX_RANGE
	var query := PhysicsRayQueryParameters2D.create(_from, end, 1 | 2, [doll.get_rid()])
	query.hit_from_inside = true
	query.collide_with_areas = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	_has_hit = not hit.is_empty()
	_to = hit["position"] if _has_hit else end
	_active = true
	queue_redraw()


func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	queue_redraw()


static func _glow_texture() -> Texture2D:
	if _glow_tex == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1.0))
		gradient.set_color(1, Color(1, 1, 1, 0.0))
		gradient.add_point(0.30, Color(1, 1, 1, 0.42))
		gradient.add_point(0.62, Color(1, 1, 1, 0.10))
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.width = GLOW_SIZE
		tex.height = GLOW_SIZE
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex = tex
	return _glow_tex


func _glow(at: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(_glow_texture(),
		Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


func _draw() -> void:
	if not _active:
		return
	var from := to_local(_from)
	var to := to_local(_to)
	var c := _beam_color
	var pulse := 0.94 + 0.06 * sin(_time * 16.0)
	var length := from.distance_to(to)
	# 光束沿射线分段：保持全程高辨识度（近端 1.0 → 远端 0.72），配合三层辉光呈现真实激光束感。
	var steps := clampi(int(length / 40.0), 4, 64)
	var points := PackedVector2Array()
	var wide := PackedColorArray()
	var mid := PackedColorArray()
	var core := PackedColorArray()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var k := lerpf(1.0, 0.78, t) * pulse
		points.append(from.lerp(to, t))
		wide.append(Color(c.r, c.g, c.b, 0.22 * k))
		mid.append(Color(c.r, c.g, c.b, 0.52 * k))
		core.append(Color(c.r, c.g, c.b, 1.0 * k).lightened(0.32))
	draw_polyline_colors(points, wide, 7.2, true)
	draw_polyline_colors(points, mid, 3.0, true)
	draw_polyline_colors(points, core, 1.3, true)
	# 枪口发射器光斑：饱满的彩色散射光晕 + 亮核（参考图 2 枪口绿色光球）。
	_glow(from, 20.0 * pulse, Color(c.r, c.g, c.b, 0.78))
	_glow(from, 9.5, Color(c.r, c.g, c.b, 1.0).lightened(0.18))
	draw_circle(from, 2.2, Color(1.0, 1.0, 1.0, 0.96), true, -1.0, true)
	# 命中点光斑：仅在射线命中墙体/门/敌人时绘制强光斑与高光核，避免在空地尽头凭空悬浮。
	if _has_hit:
		_glow(to, 26.0 * pulse, Color(c.r, c.g, c.b, 0.85))
		_glow(to, 11.5, Color(c.r, c.g, c.b, 1.0).lightened(0.22))
		draw_circle(to, 2.8, Color(1.0, 1.0, 1.0, 0.98), true, -1.0, true)
