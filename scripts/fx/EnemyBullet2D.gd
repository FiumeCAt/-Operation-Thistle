extends Node2D
class_name EnemyBullet2D

## 敌方实体子弹：体积比原来的曳光弹头更大、速度减半，让玩家能看清弹道并侧移闪避。
## 挂到 FXLayer，命中玩家/墙体或超出寿命后自动释放。

## 原速度 900px/s 的 50%。
const BASE_SPEED := 900.0
const SPEED_SCALE := 0.5
## 原弹丸半径 4px 的 1.5 倍。
const BASE_RADIUS := 4.0
const RADIUS_SCALE := 1.5
const LIFETIME := 5.0
## 玩家身体的判定半径（脚底坐标向上 46px 为躯干中心）。
const PLAYER_CENTER := Vector2(0, -46)
const PLAYER_HIT_RADIUS := 22.0

var velocity := Vector2.ZERO
var damage := 7.0
var ap := 0.0
var radius := BASE_RADIUS * RADIUS_SCALE
var age := 0.0
var player = null


static func spawn(parent: Node, from: Vector2, target: Vector2,
		dmg: float, penetration := 0.0) -> EnemyBullet2D:
	if parent == null or not parent.is_inside_tree():
		return null
	var dir := target - from
	if dir.length() < 1.0:
		return null
	var bullet := EnemyBullet2D.new()
	bullet.damage = dmg
	bullet.ap = penetration
	bullet.velocity = dir.normalized() * BASE_SPEED * SPEED_SCALE
	bullet.rotation = bullet.velocity.angle()
	bullet.player = parent.get_tree().get_first_node_in_group("player")
	bullet.z_index = 63
	parent.add_child(bullet)
	bullet.global_position = from
	return bullet


func _physics_process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	var prev := global_position
	var next := prev + velocity * delta

	# 墙体：射线只查 layer 1（玩家在 layer 2，单独用距离判定）。
	var query := PhysicsRayQueryParameters2D.create(prev, next, 1)
	query.hit_from_inside = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		Shot2D.wall_hit(get_parent(), hit["position"], velocity.normalized())
		queue_free()
		return

	# 玩家：用线段到躯干中心的最短距离判定，避免高速子弹穿过；翻滚无敌帧期间子弹直接擦身掠过。
	if player != null and is_instance_valid(player):
		var dodge_invuln: bool = player.has_method("is_dodge_invuln") and bool(player.is_dodge_invuln())
		if not dodge_invuln:
			var center: Vector2 = player.global_position + PLAYER_CENTER
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(center, prev, next)
			if center.distance_to(closest) <= radius + PLAYER_HIT_RADIUS:
				Shot2D.hit_burst(get_parent(), center, velocity.normalized(), "flesh", 0.6)
				player.take_damage(damage, ap)
				queue_free()
				return

	global_position = next


func _draw() -> void:
	# 外发光 → 弹体 → 白热核心；尾迹朝速度反方向拖一小段。
	draw_line(Vector2(-18.0, 0.0), Vector2.ZERO,
		Color(1.0, 0.32, 0.18, 0.20), radius * 1.6)
	draw_circle(Vector2.ZERO, radius * 2.0, Color(1.0, 0.20, 0.10, 0.16))
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.48, 0.24, 0.85))
	draw_circle(Vector2.ZERO, radius * 0.55, Color(1.0, 0.92, 0.72, 0.95))
