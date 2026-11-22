extends StaticBody3D
## 训练靶：靶板 + 支架。层 4，可被武器射线命中；累计伤害、飘字、击毁后 2.5s 重生。

const BOARD_TEX := preload("res://assets/art/env/target_board.png")
const ZPIX_FONT := preload("res://assets/art/ui/Zpix.ttf")

var board_mat: StandardMaterial3D
var board: MeshInstance3D
var hits := 0
var max_hp := 120
var hp := 120
var dead := false

func _ready() -> void:
	collision_layer = 8   # 第 4 层（位掩码 8），与射线 1|8 匹配
	collision_mask = 0

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.055, 0.065, 0.08)
	dark.metallic = 0.35
	dark.roughness = 0.65

	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.08, 0.72, 0.08)
	post.mesh = pm
	post.position = Vector3(0, 0.36, 0)
	post.material_override = dark
	add_child(post)

	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.72, 0.08, 0.48)
	base.mesh = bm
	base.position = Vector3(0, 0.04, 0)
	base.material_override = dark
	add_child(base)

	board = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.02, 1.55)
	board.mesh = q
	board.position = Vector3(0, 0.98, 0.035)
	board_mat = StandardMaterial3D.new()
	board_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	board_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	board_mat.albedo_texture = BOARD_TEX
	board_mat.albedo_color = Color(1, 1, 1)
	board.material_override = board_mat
	board.cast_shadow = 0
	add_child(board)

func _sfx() -> Node:
	return get_tree().root.get_node_or_null("Sfx")

func on_hit(pos: Vector3, _normal: Vector3, damage := 0.0) -> void:
	if dead:
		return
	hits += 1
	var s := _sfx()
	if s:
		s.play_3d(get_parent(), "hit", pos, -6.0, randf_range(0.9, 1.1))

	var tw := create_tween()
	tw.tween_property(board_mat, "albedo_color", Color(2.2, 1.5, 0.9), 0.03)
	tw.tween_property(board_mat, "albedo_color", Color(1, 1, 1), 0.16)

	var punch := create_tween()
	punch.tween_property(self, "scale", Vector3(1.08, 0.94, 1.08), 0.05)
	punch.tween_property(self, "scale", Vector3.ONE, 0.12)

	if damage <= 0.0:
		return
	hp -= damage
	_spawn_damage(pos, damage)
	if hp <= 0.0:
		_die()

func _spawn_damage(pos: Vector3, dmg: float) -> void:
	var l := Label3D.new()
	l.text = str(int(round(dmg)))
	l.font = ZPIX_FONT
	l.font_size = 56
	l.pixel_size = 0.004
	l.modulate = Color(1.0, 0.78, 0.4)
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = 1
	l.no_depth_test = true
	add_child(l)
	l.global_position = pos + Vector3(0, 0.25, 0)

	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.7, 0.55)
	tw.tween_property(l, "modulate:a", 0.0, 0.55)
	tw.finished.connect(l.queue_free)

func _die() -> void:
	dead = true
	board.visible = false
	var s := _sfx()
	if s:
		s.play_3d(get_parent(), "break", global_position + Vector3(0, 0.8, 0), -3.0)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(_respawn)

func _respawn() -> void:
	hp = max_hp
	dead = false
	board.visible = true
	board_mat.albedo_color = Color(1, 1, 1)
