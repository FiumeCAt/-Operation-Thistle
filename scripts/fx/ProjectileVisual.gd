extends Node3D
class_name ProjectileVisual

const MAX_PER_SHOT := 8
var origin := Vector3.ZERO
var endpoint := Vector3.ZERO
var elapsed := 0.0
var lifetime := 0.0
var travelled := 0.0
var _distance := 0.0
var _head: MeshInstance3D
var _tail: MeshInstance3D

static func spawn(parent: Node, from: Vector3, to: Vector3) -> ProjectileVisual:
	if parent == null or from.distance_to(to) < 0.0001:
		return null
	var visual := ProjectileVisual.new()
	visual.origin = from
	visual.endpoint = to
	parent.add_child(visual)
	return visual

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("combat_feedback")
	add_to_group("projectile_visuals")
	_distance = origin.distance_to(endpoint)
	lifetime = clampf(_distance / 48.0, 0.045, 0.38)
	global_position = origin
	var direction := (endpoint - origin).normalized()
	look_at(endpoint, Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT)
	_head = _segment(0.045, Color(1.0, 0.95, 0.65))
	_tail = _segment(0.018, Color(1.0, 0.55, 0.18))
	_update_geometry()

func _segment(width: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, 1.0)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _process(dt: float) -> void:
	if get_tree().paused:
		return
	elapsed = minf(lifetime, elapsed + dt)
	travelled = _distance * elapsed / lifetime
	global_position = origin.lerp(endpoint, elapsed / lifetime)
	_update_geometry()
	if elapsed >= lifetime:
		hide()
		queue_free()

func _update_geometry() -> void:
	var head_length := minf(0.14, travelled)
	var tail_length := minf(0.48, maxf(0.0, travelled - head_length))
	_head.visible = head_length > 0.0
	_head.scale.z = maxf(0.0001, head_length)
	_head.position.z = head_length * 0.5
	_tail.visible = tail_length > 0.0
	_tail.scale.z = maxf(0.0001, tail_length)
	_tail.position.z = head_length + tail_length * 0.5
