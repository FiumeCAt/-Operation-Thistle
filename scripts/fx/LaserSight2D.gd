extends Node2D
class_name LaserSight2D
## 下挂激光指示器：从枪口沿射击方向发射激光。
## 命中墙体或敌人时，在命中点显示带辉光的光斑（参考图效果）。

## 激光最多延伸到这里；真正截断点由射线命中决定。
## 需要覆盖高倍镜的镜内取景上限（基础 32 米 × 瞄具视野倍率）。
const MAX_RANGE := 3200.0

var main = null
var doll = null
var _active := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _beam_color := Color(0.35, 1.0, 0.50)


func setup(main_node, player) -> void:
	main = main_node
	doll = player
	# 画在曳光（z=60）之上，开火时也能看见中心线与弹道是否重合。
	z_index = 65


func _process(_delta: float) -> void:
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
	_to = hit["position"] if not hit.is_empty() else end
	_active = true
	queue_redraw()


func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var from := to_local(_from)
	var to := to_local(_to)
	var c := _beam_color
	var glow := Color(c.r, c.g, c.b, 0.10)
	var soft := Color(c.r, c.g, c.b, 0.34)
	var core := Color(c.r, c.g, c.b, 1.0).lightened(0.35)
	draw_line(from, to, glow, 7.0)
	draw_line(from, to, soft, 2.4)
	draw_line(from, to, core, 1.0)
	draw_circle(to, 9.0, Color(c.r, c.g, c.b, 0.20))
	draw_circle(to, 3.6, Color(c.r, c.g, c.b, 0.95).lightened(0.25))
	draw_circle(from, 2.0, soft)
