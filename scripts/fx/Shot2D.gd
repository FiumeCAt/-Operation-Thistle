extends RefCounted
class_name Shot2D

## 2D 版开火反馈：弹道拖尾 + 命中火花 + 弹壳 + 枪声波纹。
## 全部程序化绘制，挂到 Main2D 的 FXLayer（世界坐标层），用完自动释放。

const TRACER_SPEED := 4200.0
const TRACER_MIN_TIME := 0.03
const TRACER_MAX_TIME := 0.13
## 未命中的弹丸要一直画到射程尽头，所以头部飞行更久、轨迹停留更久。
const TRACER_MISS_MAX_TIME := 0.24
const TRACER_MISS_FADE := 0.28


## 曳光：一条快速淡出的射线 + 一颗沿射线飞出的弹头。
## miss=true 时轨迹延伸到武器射程尽头，并保留更长时间的渐隐。
static func tracer(parent: Node, from: Vector2, to: Vector2,
		color := Color(1.0, 0.82, 0.45), miss := false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var distance := from.distance_to(to)
	if distance < 4.0:
		return
	var travel := clampf(distance / TRACER_SPEED, TRACER_MIN_TIME,
		TRACER_MISS_MAX_TIME if miss else TRACER_MAX_TIME)
	var line := Line2D.new()
	line.width = 2.4 if miss else 2.0
	line.default_color = Color(color.r, color.g, color.b, 0.7 if miss else 0.55)
	line.points = PackedVector2Array([Vector2.ZERO, to - from])
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.z_index = 60
	parent.add_child(line)
	line.global_position = from
	var fade := line.create_tween()
	if miss:
		fade.tween_interval(0.05)
		fade.tween_property(line, "modulate:a", 0.0, TRACER_MISS_FADE)
	else:
		fade.tween_property(line, "modulate:a", 0.0, 0.12)
	fade.tween_callback(line.queue_free)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-5.0, -1.5), Vector2(5.0, 0.0), Vector2(-5.0, 1.5),
	])
	head.color = Color(1.0, 0.96, 0.78)
	head.rotation = (to - from).angle()
	head.z_index = 61
	parent.add_child(head)
	head.global_position = from
	var fly := head.create_tween()
	fly.tween_property(head, "global_position", to, travel)
	fly.tween_callback(head.queue_free)


## 命中反馈：向四周炸开的短线火花。
static func impact(parent: Node, pos: Vector2, color := Color(1.0, 0.5, 0.35)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var burst := Node2D.new()
	burst.z_index = 62
	parent.add_child(burst)
	burst.global_position = pos
	for i in 5:
		var line := Line2D.new()
		var angle := TAU * float(i) / 5.0 + randf_range(-0.3, 0.3)
		line.points = PackedVector2Array([Vector2.ZERO, Vector2.from_angle(angle) * randf_range(6.0, 13.0)])
		line.width = 2.0
		line.default_color = color
		burst.add_child(line)
	var tw := burst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(burst, "scale", Vector2.ONE * 1.6, 0.14)
	tw.tween_property(burst, "modulate:a", 0.0, 0.14)
	tw.chain().tween_callback(burst.queue_free)


## 打在墙上：走特效库的子弹弹着（自带火花、碎屑和弹坑），方向沿弹道。
static func wall_hit(parent: Node, pos: Vector2, dir := Vector2.RIGHT) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if DisplayServer.get_name() != "headless" \
			and not CombatFxWarmup.is_ready("impacts/bullet-impact", {"height": 0}, ""):
		impact(parent, pos, Color(0.86, 0.82, 0.72))
		return
	pixel_fx(parent, "impacts/bullet-impact", pos, dir.angle(), 58, 0.7,
		PixelFx2D.Mode.BAKED, "", {"height": 0})


## Phase 4 伪 3D 子弹落地扬尘：近中距瞄准空地斜射触地时，弹出地面尘环、微碎屑与短暂弹痕。
static func ground_dust(parent: Node, pos: Vector2, dir := Vector2.RIGHT) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var root := Node2D.new()
	root.z_index = 54
	root.set_meta("ground_dust_fx", true)
	parent.add_child(root)
	root.global_position = pos

	# 地面短暂弹坑微痕
	var scuff := Polygon2D.new()
	scuff.polygon = PackedVector2Array([
		Vector2(-3.0, -1.5), Vector2(3.0, -1.5), Vector2(3.0, 1.5), Vector2(-3.0, 1.5),
	])
	scuff.color = Color(0.14, 0.12, 0.10, 0.72)
	root.add_child(scuff)

	# 椭圆扬尘扩散环（匹配 2.5D 俯视地面透视）
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(0.82, 0.78, 0.68, 0.68)
	var pts := PackedVector2Array()
	for i in 17:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * 9.0, sin(a) * 5.2))
	ring.points = pts
	ring.scale = Vector2(0.45, 0.45)
	root.add_child(ring)

	# 沿弹道前方溅起的 5 粒像素尘屑
	var fwd := dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.9, 1.9), 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.30)
	tw.tween_property(scuff, "modulate:a", 0.0, 0.48).set_delay(0.12)
	for i in 5:
		var mote := Polygon2D.new()
		var sz := randf_range(1.4, 2.6)
		mote.polygon = PackedVector2Array([
			Vector2(-sz, -sz), Vector2(sz, -sz), Vector2(sz, sz), Vector2(-sz, sz),
		])
		mote.color = Color(0.84, 0.80, 0.72, 0.82) if i % 2 == 0 else Color(0.56, 0.52, 0.46, 0.78)
		root.add_child(mote)
		var spread_a := randf_range(-0.95, 0.95)
		var kick := fwd.rotated(spread_a) * randf_range(8.0, 20.0) + Vector2(0.0, -randf_range(4.0, 12.0))
		tw.tween_property(mote, "position", kick, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mote, "modulate:a", 0.0, 0.30)
	tw.chain().tween_callback(root.queue_free)
	return root


## Phase 5 翻滚扬尘：起步蹬地与落地时在脚下扬起贴地像素尘雾与微椭圆尘环。
static func dodge_dust(parent: Node, pos: Vector2, dir := Vector2.RIGHT,
		landing := false) -> Node2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var root := Node2D.new()
	root.z_index = 54
	root.set_meta("dodge_dust_fx", true)
	parent.add_child(root)
	root.global_position = pos

	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	root.material = mat
	var ring := Line2D.new()
	ring.width = 2.0 if landing else 2.6
	ring.default_color = Color(0.84, 0.92, 0.98, 0.52 if landing else 0.78)
	ring.use_parent_material = true
	var pts := PackedVector2Array()
	for i in 17:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * 12.0, sin(a) * 6.5))
	ring.points = pts
	ring.scale = Vector2(0.45, 0.45)
	root.add_child(ring)

	var back := -(dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.6 if landing else 2.2, 1.6 if landing else 2.2), 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.28)

	var count := 4 if landing else 7
	for i in count:
		var puff := Polygon2D.new()
		var sz := randf_range(1.8, 3.4) if not landing else randf_range(1.4, 2.4)
		puff.polygon = PackedVector2Array([
			Vector2(-sz, -sz), Vector2(sz, -sz), Vector2(sz, sz), Vector2(-sz, sz),
		])
		puff.color = Color(0.90, 0.94, 0.98, 0.86) if i % 2 == 0 else Color(0.68, 0.76, 0.84, 0.78)
		puff.use_parent_material = true
		root.add_child(puff)
		var spread := randf_range(-1.1, 1.1)
		var dist := randf_range(8.0, 20.0) if landing else randf_range(14.0, 34.0)
		var kick := back.rotated(spread) * dist + Vector2(0.0, -randf_range(2.0, 10.0))
		tw.tween_property(puff, "position", kick, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(puff, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(root.queue_free)
	return root


## Phase 5 翻滚占位残影：复制角色当前帧贴图生成青白战术残影，0.24s 内渐隐释放。
static func dodge_afterimage(parent: Node, world_pos: Vector2, body_tex: Texture2D,
		head_tex: Texture2D, body_offset: Vector2, body_scale: Vector2,
		body_rot: float, invuln_phase := true) -> Node2D:
	if parent == null or not parent.is_inside_tree() or body_tex == null:
		return null
	var ghost := Node2D.new()
	ghost.z_index = -1
	ghost.set_meta("dodge_afterimage_fx", true)
	parent.add_child(ghost)
	ghost.global_position = world_pos

	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	var tint := Color(0.42, 0.94, 1.0, 0.62) if invuln_phase else Color(0.80, 0.90, 1.0, 0.42)
	var b_sp := Sprite2D.new()
	b_sp.texture = body_tex
	b_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b_sp.material = mat
	b_sp.offset = body_offset
	b_sp.scale = body_scale
	b_sp.rotation = body_rot
	b_sp.modulate = tint
	ghost.add_child(b_sp)

	if head_tex != null:
		var h_sp := Sprite2D.new()
		h_sp.texture = head_tex
		h_sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		h_sp.material = mat
		h_sp.offset = body_offset
		h_sp.scale = body_scale
		h_sp.rotation = body_rot
		h_sp.modulate = tint
		ghost.add_child(h_sp)

	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ghost.queue_free)
	return ghost


## 通用命中爆点：敌人打中玩家等场合，同样走特效库。
static func hit_burst(parent: Node, pos: Vector2, dir: Vector2,
		material := "flesh", scale_mul := 0.7) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if material == "metal":
		pixel_fx(parent, "impacts/hit-spark", pos, dir.angle(), 62, scale_mul,
			PixelFx2D.Mode.BAKED, "gold", {"height": 0, "aim": 0.0})
	else:
		pixel_fx(parent, "impacts/blunt-hit", pos, dir.angle(), 62, scale_mul,
			PixelFx2D.Mode.BAKED, "blood", {
				"height": 0,
				"warm": "#d42a30",
				"dust": "#6a101c",
				"clod": "#a01824",
			})


## 抛壳：一小段黄铜，向侧后方弹出后淡出。
static func shell(parent: Node, pos: Vector2, dir: Vector2) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var brass := Polygon2D.new()
	brass.polygon = PackedVector2Array([
		Vector2(-1.5, -3.0), Vector2(1.5, -3.0), Vector2(1.5, 3.0), Vector2(-1.5, 3.0),
	])
	brass.color = Color(0.78, 0.58, 0.24)
	brass.rotation = randf() * TAU
	brass.z_index = 59
	parent.add_child(brass)
	brass.global_position = pos
	var side := Vector2(-dir.y, dir.x) * (1.0 if randf() < 0.5 else -1.0)
	var away := -dir.normalized() * randf_range(10.0, 20.0) + side * randf_range(6.0, 14.0) + Vector2(0, -12.0)
	var tw := brass.create_tween()
	tw.set_parallel(true)
	tw.tween_property(brass, "global_position", pos + away, 0.34)
	tw.tween_property(brass, "rotation", brass.rotation + randf_range(-7.0, 7.0), 0.34)
	tw.tween_property(brass, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(brass.queue_free)


## 枪声波纹：一圈快速扩张的细环，只提示声音传播范围。
static func noise_ring(parent: Node, pos: Vector2, radius_px: float,
		color := Color(0.82, 0.88, 0.96)) -> void:
	if parent == null or not parent.is_inside_tree() or radius_px < 8.0:
		return
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(color.r, color.g, color.b, 0.42)
	var points := PackedVector2Array()
	for i in 41:
		points.append(Vector2.from_angle(TAU * float(i) / 40.0) * radius_px)
	ring.points = points
	ring.z_index = 57
	parent.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector2.ONE * 0.10
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2.ONE, 0.55).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(ring.queue_free)


## pixelfx 插件特效：节点位置即特效原点，1x 像素与角色比例一致。
## 用节点旋转而不是 fx_angle：后者会进入烘焙缓存键，连续角度会反复重烘焙。
static func pixel_fx(parent: Node, id: String, pos: Vector2, angle: float,
		z := 60, scale_mul := 1.0, mode: PixelFx2D.Mode = PixelFx2D.Mode.LIVE,
		palette_preset := "", options := {}, speed_mul := 1.0) -> PixelFx2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := PixelFx2D.new()
	fx.effect = id
	fx.mode = mode
	fx.rotation = angle
	fx.scale = Vector2.ONE * scale_mul
	fx.speed_scale = speed_mul
	fx.z_index = z
	fx.free_when_done = true
	if palette_preset != "":
		fx.palette_preset = palette_preset
	if not options.is_empty():
		fx.options = options
	parent.add_child(fx)
	fx.global_position = pos
	return fx
