extends RefCounted
class_name ImpactFX
## 极简 3D 版命中/曳光反馈。M0 只做“看得见打中了”这件事。

const FLASH_TEX := preload("res://assets/art/fx/muzzle_flash.png")

static func tracer(parent: Node, from: Vector3, to: Vector3) -> void:
	ProjectileVisual.spawn(parent, from, to)

static func shot(parent: Node, result: Dictionary) -> void:
	var pellets: Array = result.get("pellets", [])
	for i in mini(pellets.size(), ProjectileVisual.MAX_PER_SHOT):
		var pellet: Dictionary = pellets[i]
		if not pellet.get("muzzle_blocked", false):
			tracer(parent, pellet["origin"], pellet["end"])

static func clear(parent: Node) -> void:
	for effect in parent.get_tree().get_nodes_in_group("combat_feedback"):
		if parent.is_ancestor_of(effect):
			if effect is Node3D:
				effect.hide()
			effect.queue_free()

static func spawn(parent: Node, pos: Vector3) -> void:
	if parent == null:
		return

	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.24, 0.24)
	mi.mesh = qm

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = FLASH_TEX
	mat.albedo_color = Color(1.0, 0.88, 0.7, 1.0)
	mi.material_override = mat

	parent.add_child(mi)
	mi.add_to_group("combat_feedback")
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * randf_range(0.7, 1.15)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 0.7
	light.omni_range = 0.8
	parent.add_child(light)
	light.add_to_group("combat_feedback")
	light.global_position = pos + Vector3(0, 0.2, 0)

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", mi.scale * 1.9, 0.20)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.20)
	tw.finished.connect(mi.queue_free)

	var tw2 := light.create_tween()
	tw2.tween_property(light, "light_energy", 0.0, 0.16)
	tw2.tween_callback(light.queue_free)

## 枪声冲击波：一条半透明细线，只提示传播范围，不显示敌人位置。
static func gunshot_wave(parent: Node, pos: Vector3, radius: float) -> void:
	_spawn_wave(parent, pos, radius, Color(0.82, 0.88, 0.96), 0.45, 0.9)

static var _ring_wave: Mesh

static func _wave_mesh() -> Mesh:
	if _ring_wave == null:
		_ring_wave = _build_wave(360.0, 72, 7, 0.0012, 0.0032, 0.0025)
	return _ring_wave

## 随机抖动的极细环形条带，看起来像一条被轻微撕开的声波线。
static func _build_wave(arc_deg: float, segments: int, seed_value: int,
		width_min: float, width_max: float, wobble_amount: float) -> Mesh:
	var im := ImmediateMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segments + 1:
		var t := float(i) / float(segments)
		var ang := deg_to_rad(lerpf(-arc_deg * 0.5, arc_deg * 0.5, t))
		var wobble := rng.randf_range(-wobble_amount, wobble_amount)
		var width := rng.randf_range(width_min, width_max)
		var inner := 0.98 + wobble - width
		var outer := 0.98 + wobble + width
		im.surface_set_color(Color(1, 1, 1, rng.randf_range(0.35, 1.0)))
		im.surface_add_vertex(Vector3(cos(ang) * inner, 0.0, sin(ang) * inner))
		im.surface_set_color(Color(1, 1, 1, rng.randf_range(0.15, 0.6)))
		im.surface_add_vertex(Vector3(cos(ang) * outer, 0.0, sin(ang) * outer))
	im.surface_end()
	return im

static func _spawn_wave(parent: Node, pos: Vector3, radius: float, color: Color,
		peak_alpha: float, duration: float) -> void:
	if parent == null or radius <= 0.2 or parent.get_tree() == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _wave_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(color.r, color.g, color.b, peak_alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = 0
	parent.add_child(mi)
	mi.add_to_group("combat_feedback")
	mi.global_position = pos + Vector3(0, 0.035, 0)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3.ONE * maxf(0.2, radius * 0.1)

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.finished.connect(mi.queue_free)

static func shell(parent: Node, pos: Vector3, dir: Vector3) -> void:
	## 抛壳：小黄铜方块，受重力与地面碰撞，1.4s 后回收。
	if parent == null or parent.get_tree() == null:
		return
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.gravity_scale = 1.0
	rb.mass = 0.02

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, 0.055)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.55, 0.22)
	mat.metallic = 0.85
	mat.roughness = 0.3
	mi.material_override = mat
	mi.cast_shadow = 0
	rb.add_child(mi)

	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	rb.add_child(cs)

	parent.add_child(rb)
	rb.add_to_group("combat_feedback")
	rb.global_position = pos
	var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	rb.linear_velocity = dir * 1.2 + Vector3.UP * 2.4 + side * 1.1
	rb.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))

	var tween := rb.create_tween()
	tween.tween_interval(1.4)
	tween.tween_callback(rb.queue_free)
