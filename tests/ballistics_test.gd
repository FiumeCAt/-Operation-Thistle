extends SceneTree

class HitTarget extends StaticBody3D:
	var hits := 0
	var damage := 0.0

	func on_hit(_pos: Vector3, _normal: Vector3, amount: float) -> void:
		hits += 1
		damage += amount

var _main: Node3D
var _doll: Doll
var _weapon: PlayerWeapon
var _visual: WeaponVisual
var _rig: CameraRig
var _checks := 0
var _fails := 0
var _max_origin := 0.0
var _max_grip := 0.0
var _max_range := 0.0
var _max_cross := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("[FAIL] " + label)

func _disable_enemy(node: Node) -> void:
	if node is Enemy:
		node.process_mode = Node.PROCESS_MODE_DISABLED

func _settle() -> void:
	for i in 3:
		await physics_frame
		await process_frame

func _ready_round() -> void:
	_weapon._physics_process(10.0)
	_weapon.mag = _weapon.weapon.mag_capacity
	_weapon.chamber = "LOADED" if _weapon.weapon.chamber_size > 0 else "EMPTY"

func _shoot(label: String) -> Dictionary:
	var before := _weapon.shots
	_weapon.try_fire()
	_check(_weapon.shots == before + 1, label + " actual try_fire")
	var shot := _weapon.last_shot
	_check(not shot.is_empty(), label + " last_shot")
	if shot.is_empty():
		return {}
	var error: float = shot.origin.distance_to(_visual.get_muzzle_position())
	_max_origin = maxf(_max_origin, error)
	_check(error < 0.0001, label + " synchronized muzzle")
	_check(shot.origin.distance_to(_doll.get_muzzle_position()) < 0.0001, label + " Doll muzzle")
	_check(shot.pellets.size() == _weapon.current_ammo().pellets, label + " pellet count")
	return shot

func _open_pellet(p: Dictionary, axis: Vector3, label: String) -> void:
	var delta: Vector3 = p.end - p.origin
	var range_error := absf(delta.length() - _weapon.weapon.range_m)
	var cross_error := delta.cross(p.direction).length()
	_max_range = maxf(_max_range, range_error)
	_max_cross = maxf(_max_cross, cross_error)
	_check(p.hit.is_empty() and not p.muzzle_blocked, label + " unobstructed")
	_check(range_error < 0.0002 and cross_error < 0.0002 and delta.dot(p.direction) > 0.0, label + " collinear full range")
	_check(absf(p.direction.length() - 1.0) < 0.00001, label + " normalized")
	_check(axis.angle_to(p.direction) <= _weapon.get_spread_half_angle() + 0.00003, label + " spread bound")

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	seed(20261026)
	node_added.connect(_disable_enemy)
	_main = (load("res://scenes/core/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main
	await _settle()
	await _settle()
	_doll = _main.get_node("Doll") as Doll
	_weapon = _doll.weapon
	_visual = _main.get_node("WeaponVisual") as WeaponVisual
	_rig = _main.get_node("CameraRig") as CameraRig
	for enemy in get_nodes_in_group("enemies"):
		_check(enemy.process_mode == Node.PROCESS_MODE_DISABLED, "enemy disabled")
	_main.set_process(false)
	_doll.set_physics_process(false)
	_weapon.set_physics_process(false)
	_visual.set_process(false)
	_rig.set_process(false)
	_doll.billboard.set_process(false)
	_doll.global_position = Vector3(0, 100, 0)
	_rig.global_position = _doll.global_position
	await _settle()
	_test_switch_and_grip()
	_test_cone()
	await _test_wall_and_behind()
	await _test_ap()
	print("METRICS origin_max=%.9fm grip_max=%.9fm range_max=%.9fm cross_max=%.9f" % [_max_origin, _max_grip, _max_range, _max_cross])
	print("=== BALLISTICS %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	await create_timer(2.0).timeout
	for audio in root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stop()
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)

func _test_switch_and_grip() -> void:
	for id in WeaponDB.WEAPON_ORDER:
		_weapon.switch_to(id)
		_ready_round()
		_weapon.switch_to(&"g17" if id != &"g17" else &"m870")
		_doll.debug_set_facing(90.0)
		_doll.debug_set_aim(_doll.global_position + Vector3(15, 1.1, 0))
		_weapon.switch_to(id)
		var shot := _shoot(str(id) + " immediate switch")
		if not shot.is_empty():
			for p in shot.pellets:
				_open_pellet(p, shot.direction, str(id))
		print("SWITCH %s range=%.1f pellets=%d origin=%s" % [id, _weapon.weapon.range_m, shot.get("pellets", []).size(), str(shot.get("origin"))])
		for pitch in [0.0, 35.0, 58.0, 75.0]:
			_rig.rotation_degrees = Vector3(-pitch, 0, 0)
			for direction in 8:
				var angle := float(direction) * 45.0
				_doll.debug_set_facing(angle)
				_doll.debug_set_aim(_doll.global_position + Vector3(sin(deg_to_rad(angle)) * 15.0, 1.1, cos(deg_to_rad(angle)) * 15.0))
				for state in ["idle", "aim", "reload"]:
					_doll.debug_set_state(state)
					_visual.sync_pose()
					var error := _visual.get_grip_position().distance_to(_doll.hand_anchor_world(_visual.current_group()))
					_max_grip = maxf(_max_grip, error)
					_check(error < 0.0001, "%s pitch=%s dir=%d state=%s grip" % [id, pitch, direction, state])
					_check(_doll.billboard.current_dir == direction, "eight direction selection")
	print("GRIP 4 weapons x 4 pitches x 8 directions x 3 groups = 384 poses")

func _test_cone() -> void:
	_rig.rotation_degrees = Vector3(-58, 0, 0)
	for id in WeaponDB.WEAPON_ORDER:
		_weapon.switch_to(id)
		for ammo in ([&"9mm"] if id == &"g17" else PlayerWeapon.AMMO_ORDER):
			_weapon.ammo_type = ammo
			_doll.debug_set_aim(_doll.global_position + Vector3(15, 1.1, 0))
			var context := _weapon.query_aim(true)
			var maximum := 0.0
			for radial in [-1.0, 0.0, 0.25, 1.0, 2.0]:
				for azimuth in [0.0, PI * 0.5, PI, PI * 1.5]:
					var pellet := _weapon.query_pellet(context, radial, azimuth)
					_open_pellet(pellet, context.direction, "cone query")
					var angle: float = context.direction.angle_to(pellet.direction)
					maximum = maxf(maximum, angle)
					if radial <= 0.0:
						_check(angle < 0.00003, "cone center clamp")
					if radial >= 1.0:
						_check(absf(angle - _weapon.get_spread_half_angle()) < 0.00003, "cone edge clamp")
			for axis in [Vector3.UP, Vector3.DOWN, Vector3(0.00001, 1, 0).normalized()]:
				var cone := _weapon.get_cone_direction(axis, 1.0, 1.7)
				_check(cone.is_finite() and absf(cone.angle_to(axis) - _weapon.get_spread_half_angle()) < 0.00003, "vertical cone")
			_ready_round()
			var shot := _shoot("ammo " + str(ammo))
			for pellet in shot.get("pellets", []):
				_open_pellet(pellet, shot.direction, "actual ammo pellet")
			print("CONE %s/%s max=%.6fdeg bound=%.6fdeg" % [id, ammo, rad_to_deg(maximum), rad_to_deg(_weapon.get_spread_half_angle())])

func _box(body: StaticBody3D, pos: Vector3, size: Vector3, layer: int) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.collision_layer = layer
	body.collision_mask = 0
	_main.add_child(body)
	body.global_position = pos

func _test_wall_and_behind() -> void:
	for id in WeaponDB.WEAPON_ORDER:
		_weapon.switch_to(id)
		_weapon.ammo_type = &"9mm" if id == &"g17" else &"buckshot"
		_ready_round()
		_doll.debug_set_facing(90)
		_doll.debug_set_aim(_doll.global_position + Vector3(10, 1.1, 0))
		var context := _weapon.query_aim(true)
		var grip := _visual.get_grip_position()
		var muzzle := _visual.get_muzzle_position()
		var wall := StaticBody3D.new()
		var wall_x := (grip.x + muzzle.x) * 0.5
		_box(wall, Vector3(wall_x, 101, 0), Vector3(0.02, 4, 4), 1)
		var target := HitTarget.new()
		_box(target, Vector3(muzzle.x + 2, 101, 0), Vector3(0.3, 4, 4), 8)
		await _settle()
		_check(muzzle.x > wall_x + 0.01 and grip.x < wall_x - 0.01, str(id) + " muzzle beyond wall fixture")
		context = _weapon.query_aim(true)
		_check(context.muzzle_blocked and context.obstruction.get("collider") == wall, str(id) + " real wall query")
		var shot := _shoot(str(id) + " wall")
		for pellet in shot.get("pellets", []):
			_check(pellet.muzzle_blocked and pellet.hit.get("collider") == wall, "wall stops pellet")
		_check(target.hits == 0, "wall prevents damage")
		wall.free()
		await _settle()
		_ready_round()
		_shoot(str(id) + " wall removed positive control")
		_check(target.hits == 1 and target.damage > 0, "same target hittable without wall")
		print("WALL %s blocked_hits=0 control_hits=%d control_damage=%.1f" % [id, target.hits, target.damage])
		target.free()
		_ready_round()
		_doll.debug_set_state("aim")
		_visual.sync_pose()
		var close_point := _visual.get_grip_position() + Vector3(0.05, 0, 0)
		_doll.debug_set_aim(close_point)
		context = _weapon.query_aim(true)
		var behind_target := HitTarget.new()
		_box(behind_target, close_point, Vector3.ONE * 0.02, 8)
		await _settle()
		_check(context.behind_muzzle and not context.muzzle_blocked, "close target behind muzzle fixture")
		shot = _shoot(str(id) + " behind")
		var barrel := _visual.get_barrel_direction()
		for pellet in shot.get("pellets", []):
			_check(pellet.direction.dot(barrel) > 0.99 and (pellet.end - pellet.origin).dot(barrel) > 0, "no backward pellet")
		_check(behind_target.hits == 0, "no backward damage")
		print("BEHIND %s behind=%s hits=%d distance=%.6f" % [id, context.behind_muzzle, behind_target.hits, context.origin.distance_to(close_point)])
		behind_target.free()
		await _settle()

func _test_ap() -> void:
	var enemy := get_nodes_in_group("enemies")[0] as Enemy
	enemy.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	enemy.global_position = _doll.global_position + Vector3(3, 0, 0)
	enemy.armor = 4.0
	enemy.hp = 1000.0
	_weapon.switch_to(&"m870")
	_doll.debug_set_aim(enemy.global_position + Vector3(0, 0.85, 0))
	await _settle()
	for sample in [[&"slug", 56.0], [&"ap_slug", 54.0]]:
		_weapon.ammo_type = sample[0]
		_ready_round()
		var before := enemy.hp
		var shot := _shoot("AP actual Enemy")
		_check(shot.pellets[0].hit.get("collider") == enemy, "AP actual ray hits Enemy")
		var actual := before - enemy.hp
		_check(is_equal_approx(actual, sample[1]), "AP end to end expected " + str(sample[1]))
		print("AP %s armor=4 actual=%.1f expected=%.1f" % [sample[0], actual, sample[1]])
