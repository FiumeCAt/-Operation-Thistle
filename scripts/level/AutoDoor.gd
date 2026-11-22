extends StaticBody3D
class_name AutoDoor

signal opened

## 碰撞层：2 = 玩家，8 = 敌人。
const PLAYER_MASK := 2
const ENEMY_MASK := 8

var is_open := false
var automatic := true
var leaf: MeshInstance3D
var shape: CollisionShape3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.8, 0.35)
	shape.shape = box
	shape.position.y = 1.4
	add_child(shape)
	leaf = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	leaf.mesh = mesh
	leaf.position.y = 1.4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.38, 0.43)
	material.metallic = 0.6
	leaf.material_override = material
	add_child(leaf)

func actors_near(mask := PLAYER_MASK | ENEMY_MASK) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.4, 3.0, 4.6)
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 1.4)
	query.collision_mask = mask
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		if hit.collider is CharacterBody3D:
			return true
	return false

func set_open(value: bool) -> bool:
	if not value and actors_near():
		return false
	var was_open := is_open
	is_open = value
	collision_layer = 0 if value else 1
	leaf.position.y = 4.3 if value else 1.4
	if value and not was_open:
		opened.emit()
	return true

## 敌人靠近自动开门；玩家需要主动按 E 开门；关门只在完全无人时发生。
func _physics_process(_dt: float) -> void:
	if not automatic:
		return
	if not is_open and actors_near(ENEMY_MASK):
		set_open(true)
	elif is_open and not actors_near():
		set_open(false)
