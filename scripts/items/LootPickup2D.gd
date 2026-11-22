extends Node2D
class_name LootPickup2D
## 地面掉落物：靠近吸附、贴身自动拾取。
## 只做表现与距离判定，入包逻辑通过 setup 时传入的回调交给 Main2D。

const PICKUP_RADIUS := 58.0
## 吸附范围与初速都调高：贴地战斗中掉落物不再被角色甩开。
const MAGNET_RADIUS := 220.0
const MAGNET_SPEED := 640.0
## 越近吸得越快，远距离也保留一个较快的起始速度。
const MAGNET_BASE_PULL := 0.55

var kind := "resource"
var id: StringName = &"parts"
var amount := 1

var _collect: Callable
var _player: Node2D
var _phase := 0.0
var _collected := false
## 实际吸附范围：默认值再叠加「磁力拾取」天赋。
var _magnet_radius := MAGNET_RADIUS


func setup(item_kind: String, item_id: StringName, count: int, callback: Callable) -> void:
	kind = item_kind
	id = item_id
	amount = maxi(1, count)
	_collect = callback


func _ready() -> void:
	_phase = randf() * TAU
	_player = get_tree().get_first_node_in_group("player")
	var progress := get_node_or_null("/root/Progress")
	if progress != null and progress.has_method("talent_2d_level"):
		_magnet_radius = MAGNET_RADIUS * (1.0 + float(progress.talent_2d_level(&"magnet")) * 0.2)
	queue_redraw()


## 当前吸附半径（含天赋加成），用于测试与调试。
func get_magnet_radius() -> float:
	return _magnet_radius


func _process(delta: float) -> void:
	if _collected:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var target: Vector2 = _player.global_position + Vector2(0, -20)
	var to_target := target - global_position
	var dist := to_target.length()
	if dist <= PICKUP_RADIUS:
		_pick_up()
		return
	if dist < _magnet_radius and dist > 0.001:
		var pull := 1.0 - dist / _magnet_radius
		global_position += to_target / dist * MAGNET_SPEED * (MAGNET_BASE_PULL + pull * (1.0 - MAGNET_BASE_PULL)) * delta
	queue_redraw()


func _pick_up() -> void:
	if _collected:
		return
	_collected = true
	if _collect.is_valid():
		_collect.call(kind, id, amount)
	queue_free()


func _draw() -> void:
	var bob := sin(Time.get_ticks_msec() * 0.004 + _phase) * 2.0
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.005 + _phase)
	var color := _pickup_color()
	# 地面阴影
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, 8.0, Color(0.02, 0.02, 0.02, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 外圈光晕
	draw_circle(Vector2(0, bob), 11.0 * pulse, Color(color, 0.16))
	draw_circle(Vector2(0, bob), 7.5 * pulse, Color(color, 0.22))
	if kind == "ammo":
		_draw_ammo(Vector2(0, bob), color)
	else:
		_draw_crystal(Vector2(0, bob), color)


func _draw_crystal(center: Vector2, color: Color) -> void:
	var r := 7.0
	var diamond := PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r * 0.7, 0),
		center + Vector2(0, r), center + Vector2(-r * 0.7, 0),
	])
	draw_colored_polygon(diamond, color)
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	draw_polyline(outline, Color(1, 1, 1, 0.55), 1.0, true)
	draw_rect(Rect2(center + Vector2(-1.5, -3.0), Vector2(3, 6)),
		Color(1, 1, 1, 0.75), true)


func _draw_ammo(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center + Vector2(-6, -4), Vector2(12, 8)),
		Color(0.12, 0.12, 0.14, 0.95), true)
	draw_rect(Rect2(center + Vector2(-5, -3), Vector2(10, 6)), color, true)
	for i in 3:
		draw_rect(Rect2(center + Vector2(-4 + i * 4, -5), Vector2(2, 10)),
			Color(1.0, 0.92, 0.62, 0.9), true)


func _pickup_color() -> Color:
	if kind == "ammo":
		var info: Dictionary = WeaponDB.category_table().get(String(id), {})
		if not info.is_empty():
			return Color.html(String(info.get("color", "#ffd18a")))
		return Color(0.92, 0.42, 0.30)
	return ResourceDB.color_of(id)
