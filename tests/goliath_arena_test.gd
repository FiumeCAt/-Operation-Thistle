extends SceneTree
## 歌利亚狂潮回归：纯地板矩形竞技场、只刷歌利亚、每波清空后回满状态与弹药。
## godot --headless --path . --script res://tests/goliath_arena_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _run() -> void:
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()
	p.data["run_mode"] = "waves"
	p.data["map_id"] = "goliath_arena"
	_check(p.run_mode() == "waves" and p.map_id() == "goliath_arena",
		"progress stores the goliath arena mode")

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	var level: Level2D = main.level
	_check(main.waves_mode and main.goliath_map, "run enters the goliath arena")
	_check(level.arena_mode, "level uses arena generation")
	_check(level.map_size() == Vector2(Level2D.ARENA_W, Level2D.ARENA_H) * Level2D.TILE,
		"arena is a large rectangle")
	_check(level.rooms.size() == 1 and String(level.rooms[0]["name"]).contains("歌利亚"),
		"arena has one named region for the map overlay")
	_check(level.doors.is_empty() and level.containers.is_empty() and level.exits.is_empty(),
		"arena has no doors, containers or physical exits")
	_check(level.floor_layer.get_child_count() == 1, "arena floor is a single flat surface")
	_check(level.enemy_spawns.size() >= 20, "arena has a perimeter spawn ring")
	var all_goliath := true
	for kind in level.enemy_kinds:
		if StringName(kind) != &"goliath":
			all_goliath = false
			break
	_check(all_goliath, "arena spawn table only contains goliaths")
	_check(level.is_nav_walkable(level.player_spawn), "arena floor is walkable")
	_check(level.find_nav_path(level.player_spawn, level.rooms[0]["center"]).size() >= 2,
		"arena navigation grid connects the floor")

	# 歌利亚狂潮内爆炸友伤为 50%，避免一只歌利亚把整群同伴连锁引爆。
	var attacker := Enemy2D.new()
	attacker.setup(&"goliath", main.doll.global_position + Vector2(500, 0), 1)
	main.sort_layer.add_child(attacker)
	attacker.set_physics_process(false)
	var ally := Enemy2D.new()
	ally.setup(&"goliath", attacker.global_position + Vector2(60, 0), 1)
	main.sort_layer.add_child(ally)
	ally.set_physics_process(false)
	await process_frame
	p.data["map_id"] = "facility"
	_check(is_equal_approx(attacker.friendly_explosion_mul(), 0.8),
		"other wave maps keep the original 80% friendly damage")
	p.data["map_id"] = "goliath_arena"
	_check(is_equal_approx(attacker.friendly_explosion_mul(), 0.5),
		"goliath arena halves friendly explosion damage")
	var ally_hp_before: float = ally.hp
	attacker._explode_damage()
	var raw_friendly := float(attacker.stats["explode_damage"]) \
		* attacker.damage_mul * attacker.friendly_explosion_mul()
	var ally_armor := float(ally.stats["armor"])
	# 竞技场友伤按目标护甲等穿结算（不余穿放大也不减伤），50% 就是实打实的半伤。
	var expected_friendly: float = DamageModel.resolve_enemy_damage(raw_friendly, ally_armor, ally_armor)
	_check(is_equal_approx(ally_hp_before - ally.hp, expected_friendly),
		"friendly blast deals exactly 50% of the explosion damage")
	_check(ally.hp > 0.0, "a full-health goliath survives one friendly blast")
	attacker.queue_free()
	ally.queue_free()

	main.doll.hp = 12
	main.doll.armor = 0
	var rig = main.doll.weapon_rig
	if rig != null:
		rig.mag = 0
		rig.reserve.clear()
	main.wave_index = 1
	main.wave_active = true
	main._begin_wave(1)
	_check(not main._wave_spawn_queue.is_empty(), "wave one queues goliath spawns")
	var queue_ok := true
	for entry in main._wave_spawn_queue:
		if StringName(entry["kind"]) != &"goliath":
			queue_ok = false
			break
	_check(queue_ok, "every queued wave unit is a goliath")
	_check(main._wave_enemy_kind(12) == &"goliath",
		"later waves still only roll goliaths")

	main.wave_index = 1
	main._on_wave_cleared()
	_check(main.doll.hp == main.doll.hp_max, "wave clear restores full health")
	_check(main.doll.armor == main.doll.armor_max, "wave clear restores full armor")
	if rig != null:
		_check(rig.mag == rig.data.mag_capacity, "wave clear refills the magazine")
		var info: Dictionary = WeaponDB.category_table().get(
			String(rig.data.ammo_category), {})
		var expected_reserve := int(round(
			float(info.get("reserve_max", 0)) * rig.reserve_talent_mul))
		_check(rig.get_reserve() == expected_reserve, "wave clear refills reserve ammo")

	main.queue_free()
	await process_frame
	p.reset_for_test()
	print("\n=== goliath arena: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
