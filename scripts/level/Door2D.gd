extends Node2D
class_name Door2D

## 走廊与房间之间的双开滑门（对应 3D 版的 AutoDoor）：
## 玩家或敌人靠近时向两侧滑开并关掉碰撞，离开后自动合上。

const OPEN_TIME := 0.18
const TRIGGER_PAD := 26.0

var width := 192.0
var wall_thickness := 64.0
var open := false

var _barrier: StaticBody2D
var _left: Polygon2D
var _right: Polygon2D
var _slide := 0.0


func _ready() -> void:
	add_to_group("doors")
	_barrier = StaticBody2D.new()
	_barrier.collision_layer = 1
	_barrier.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, wall_thickness)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_barrier.add_child(collision)
	add_child(_barrier)

	_left = _panel(Vector2(-width * 0.5, -wall_thickness * 0.5))
	_right = _panel(Vector2(0.0, -wall_thickness * 0.5))
	set_process(true)


func _panel(origin: Vector2) -> Polygon2D:
	var panel := Polygon2D.new()
	var half := width * 0.5
	var h := wall_thickness * 0.78
	panel.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(half, 0), Vector2(half, h), Vector2(0, h),
	])
	panel.color = Color(0.30, 0.32, 0.34)
	panel.position = origin + Vector2(0, wall_thickness * 0.11)
	add_child(panel)

	# 门板挂 LightOccluder2D，随门板同步滑动：关门阻挡视野光线，开门时透光自然张开。
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = panel.polygon
	occ.occluder = poly
	panel.add_child(occ)

	# 门板上的黄黑警示条，俯视下也能看出这是门
	for i in 3:
		var stripe := Line2D.new()
		var x := half * (0.2 + 0.3 * i)
		stripe.points = PackedVector2Array([Vector2(x, 4), Vector2(x, h - 4)])
		stripe.width = 5.0
		stripe.default_color = Color(0.78, 0.59, 0.18, 0.8)
		panel.add_child(stripe)
	return panel


## 门处于关闭状态且门板已合拢过半时阻断视线（避免隔着紧闭铁门透视房间里的敌人）。
func blocks_segment(a: Vector2, b: Vector2) -> bool:
	if open or _slide >= 0.45:
		return false
	var p0 := to_global(Vector2(-width * 0.5, 0.0))
	var p1 := to_global(Vector2(width * 0.5, 0.0))
	return Geometry2D.segment_intersects_segment(a, b, p0, p1) != null


func _process(delta: float) -> void:
	var near := false
	for actor in get_tree().get_nodes_in_group("actors"):
		if is_instance_valid(actor) and (actor as Node2D).global_position.distance_to(global_position) < width * 0.5 + TRIGGER_PAD:
			near = true
			break
	if near != open:
		set_open(near)
	var target := 1.0 if open else 0.0
	_slide = move_toward(_slide, target, delta / OPEN_TIME)
	_left.position.x = -width * 0.5 - _slide * width * 0.42
	_right.position.x = _slide * width * 0.42


func set_open(value: bool) -> void:
	open = value
	_barrier.collision_layer = 0 if open else 1
