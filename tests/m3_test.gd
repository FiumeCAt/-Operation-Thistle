extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func run() -> void:
	for seed_value in 20:
		var level := LevelGenerator.new()
		level.level_seed = 1000 + seed_value
		level.depth = 1 + seed_value % 5
		root.add_child(level)
		await frames()
		check(level.seg_count == 5 + floori(float(level.depth - 1) / 2), "depth formula")
		var map := level.get_world_3d().navigation_map
		var points: Array[Vector3] = [level.exit_position]
		for i in level.rooms.size():
			points.append(level.rooms[i]["center"])
			points.append(level.rooms[i]["interaction"])
			for j in range(i + 1, level.rooms.size()):
				check(not (level.rooms[i]["rect"] as Rect2).intersects(level.rooms[j]["rect"]), "rooms overlap")
		for point in points:
			var path := NavigationServer3D.map_get_path(map, level.player_spawn, point, true)
			check(path.size() > 1 and path[-1].distance_to(point) < 0.8, "unreachable seed %d point %s" % [seed_value, point])
		for i in level.cover_rects.size():
			for reserved in level.reserved_rects:
				check(not level.cover_rects[i].intersects(reserved.grow(0.6)), "cover blocks reserved space")
			for j in range(i + 1, level.cover_rects.size()):
				check(not level.cover_rects[i].grow(0.6).intersects(level.cover_rects[j]), "cover overlap")
		var door = level.doors[0]
		door.automatic = false
		var from: Vector3 = door.global_position + Vector3(0, 1, -1)
		var to: Vector3 = door.global_position + Vector3(0, 1, 1)
		var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
		check(not level.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "closed door collision")
		door.set_open(true)
		await frames()
		check(level.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "open door passage")
		var actor := CharacterBody3D.new()
		actor.collision_layer = 2
		var collider := CollisionShape3D.new()
		collider.shape = CapsuleShape3D.new()
		actor.add_child(collider)
		root.add_child(actor)
		actor.position = door.position + Vector3.UP
		await frames()
		check(not door.set_open(false) and door.is_open, "door must not close on actor")
		actor.position = door.position + Vector3(0, 1, -4)
		await frames()
		check(door.set_open(false), "door closes after actor leaves")
		actor.position = from
		await frames()
		actor.move_and_collide(Vector3(0, 0, 2))
		check(actor.position.z < door.position.z, "closed leaf blocks character motion")
		door.set_open(true)
		await frames()
		actor.move_and_collide(Vector3(0, 0, 2))
		check(actor.position.z > door.position.z + 0.5, "open leaf permits character crossing")
		actor.position = door.position + Vector3(0, 1, -4)
		await frames()
		door.set_open(false)
		actor.collision_layer = 8
		actor.position = from
		door.automatic = true
		await frames()
		check(door.is_open, "enemy layer actor automatically pushes door")
		actor.free()
		level.explore(level.rooms[0]["center"])
		check(level.explored.size() == 1 and level.explored.has(0), "exploration")
		level.free()
		await frames()
	change_scene_to_file("res://scenes/core/Main.tscn")
	await frames(10)
	var main = current_scene
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	main.doll.position = main.level.exit_position
	await frames()
	check(main.open_shaft(), "empty shaft opens")
	main.extract_from_shaft()
	check(main.shaft_open and paused and main.run_state == main.RunState.ACTIVE, "empty extraction cannot strand modal")
	main.cancel_shaft()
	check(not paused and not main.shaft_open, "cancel resumes play")
	main.doll.hp = 47.0
	main.resources = 9
	var weapon: PlayerWeapon = main.doll.weapon
	weapon.switch_to(&"g17")
	weapon.mag = 0
	weapon.reload_magazine()
	check(main.open_shaft(), "shaft open")
	weapon._save_current()
	var ammo := weapon._saved.duplicate(true)
	var timer: float = weapon.load_t
	var elapsed: float = main.elapsed_time
	var doll_id: int = main.doll.get_instance_id()
	var level_id: int = main.level.get_instance_id()
	main.level.explore(main.level.rooms[0]["center"])
	ImpactFX.spawn(main, main.doll.position)
	main.descend()
	check(not await main.descend(), "duplicate descend rejected")
	while main.transitioning:
		await physics_frame
	check(main.depth == 2 and main.doll.get_instance_id() == doll_id and main.doll.hp == 47, "descent retains doll and health")
	check(weapon.load_t == timer and weapon._saved == ammo and weapon._pending_load > 0, "pending reload and all weapons conserved")
	check(main.resources == 9 and main.extracted_resources == 0 and main.elapsed_time == elapsed, "resource time conserved no settlement")
	check(main.reticle.wall_level == main.level and not main.rig.orbit_dragging, "rebind")
	check(not is_instance_id_valid(level_id) and main.level.explored.is_empty(), "old level removed and exploration reset")
	check(get_nodes_in_group("combat_feedback").is_empty(), "old combat feedback cleared")
	var path := NavigationServer3D.map_get_path(main.level.get_world_3d().navigation_map, main.level.player_spawn, main.level.exit_position, true)
	check(path.size() > 1 and path[-1].distance_to(main.level.exit_position) < 0.8, "new navigation synchronized before resume")
	var enemy: Enemy = get_nodes_in_group("enemies")[0]
	check(is_equal_approx(enemy.max_hp, float(EnemyDB.stats(enemy.kind)["hp"]) * 1.1), "hp multiplier")
	check(is_equal_approx(enemy.damage, float(EnemyDB.stats(enemy.kind)["damage"]) * 1.05), "damage multiplier")
	for i in 20:
		main.grant_resource_reward(1)
	check(main.resources == 30 and absf(main.reward_remainder) < 0.00001, "fraction reward accumulates")
	main.free()
	await process_frame
	print("M3: %d checks / %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
