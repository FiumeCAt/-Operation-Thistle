extends SceneTree

var _checks := 0
var _fails := 0
var _main: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("[FAIL] " + label)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	node_added.connect(func(node: Node) -> void:
		if node is Enemy:
			node.set_physics_process(false)
			node.ready.connect(func() -> void: node.set_physics_process(false), CONNECT_ONE_SHOT)
	)
	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	var doll: Doll = _main.doll
	var bar := doll.health_bar
	var count := bar.get_child_count()
	for sample in [[50.0, 100.0, 0.5], [-2.0, 100.0, 0.0], [200.0, 100.0, 1.0], [1.0, 0.0, 0.0]]:
		bar.update_health(sample[0], sample[1])
		_check(is_equal_approx(bar.ratio, sample[2]), "health ratio clamp")
	_check(bar.get_child_count() == count and count == 2, "health nodes reused")
	doll._hurt_cd = 0.0
	doll.take_damage(25.0)
	_check(bar.ratio == 0.75 and bar.emphasis > 0.0, "player damage immediate bar")
	_check(doll.billboard.body.modulate.g < 0.5, "player immediate flash")
	await _frames(20)
	_check(bar.emphasis == 0.0 and doll._hurt_flash == 0.0, "player feedback expires")
	doll.respawn()
	_check(bar.ratio == 1.0 and bar.visible, "respawn restores health bar")
	var enemy := get_nodes_in_group("enemies")[0] as Enemy
	enemy.armor = 0.0
	enemy.take_damage(10.0, enemy.global_position + Vector3.UP)
	_check(is_equal_approx(enemy.health_bar.ratio, enemy.hp / enemy.max_hp), "enemy actual damage ratio")
	_check(enemy.health_bar.emphasis > 0.0 and enemy.sprite.modulate.r > 2.0, "enemy flash and emphasis")
	await _frames(20)
	_check(enemy._flash == 0.0, "enemy flash recovers without AI tick")
	enemy.hp = enemy.max_hp * 0.1
	enemy._state_t = 5.0
	enemy._tick_flee(0.0, false)
	await _frames(1)
	_check(is_equal_approx(enemy.health_bar.ratio, 0.3), "flee heal updates bar")
	enemy.take_damage(10000.0, enemy.global_position)
	_check(not enemy.health_bar.visible, "enemy death immediately hides bar")
	await _frames(30)
	_check(not is_instance_valid(enemy), "enemy death frees bar owner")
	doll.set_physics_process(false)
	doll.weapon.set_physics_process(false)
	doll.global_position = Vector3(0, 100, 0)
	doll.debug_set_facing(90)
	doll.debug_set_aim(Vector3(15, 101.1, 0))
	ImpactFX.clear(_main)
	await _frames(1)
	doll.weapon.try_fire()
	var pellets: Array = doll.weapon.last_shot.pellets
	var visuals := get_nodes_in_group("projectile_visuals")
	_check(visuals.size() == mini(pellets.size(), ProjectileVisual.MAX_PER_SHOT), "real shot bounded visual count")
	for i in visuals.size():
		var visual: ProjectileVisual = visuals[i]
		_check(visual.origin == pellets[i].origin and visual.endpoint == pellets[i].end, "last_shot exact endpoints")
		_check(visual.global_position == visual.origin, "starts at actual muzzle")
		visual.set_process(false)
		visual._process(visual.lifetime * 0.5)
		_check(visual.global_position.is_equal_approx(visual.origin.lerp(visual.endpoint, 0.5)), "moves along actual segment")
		_check(visual._head.scale.z + visual._tail.scale.z <= 0.621, "short head and tail")
		visual._process(10.0)
		_check(visual.global_position == visual.endpoint and visual.is_queued_for_deletion(), "endpoint clamp and lifetime")
	await _frames(1)
	_check(get_nodes_in_group("projectile_visuals").is_empty(), "expired visuals freed")
	ImpactFX.shot(_main, {"pellets": [{"origin": Vector3.ZERO, "end": Vector3.ONE, "muzzle_blocked": true}]})
	_check(get_nodes_in_group("projectile_visuals").is_empty(), "blocked muzzle never emits beyond wall")
	var near := ProjectileVisual.spawn(_main, Vector3(0, 100, 0), Vector3(0.02, 100, 0))
	near.set_process(false)
	near._process(near.lifetime * 0.5)
	_check(near.travelled <= 0.02 and near._head.scale.z <= near.travelled, "near wall geometry stays within segment")
	near._process(1.0)
	await _frames(1)
	var frozen := ProjectileVisual.spawn(_main, Vector3(0, 100, 0), Vector3(20, 100, 0))
	paused = true
	var before := frozen.global_position
	await _frames(10)
	_check(frozen.global_position == before and frozen.elapsed == 0.0, "tree pause freezes projectile lifetime")
	paused = false
	await _frames(2)
	_check(frozen.elapsed > 0.0, "unpause resumes projectile")
	doll._hurt_cd = 0.0
	doll.take_damage(1000.0)
	_check(not bar.visible and paused and not _main.run_hud._health.visible, "death hides world and HUD bars")
	var old_bar_id := bar.get_instance_id()
	var old_visual_id := frozen.get_instance_id()
	var old_main_id := _main.get_instance_id()
	var old_level_id: int = _main.level.get_instance_id()
	_main.restart_run()
	await _frames(2)
	_check(_main.get_instance_id() == old_main_id and _main.run_hud._at_base and paused, "restart 回到同一实例基地")
	_main.restart_run()
	await _frames(10)
	_check(_main.get_instance_id() == old_main_id and _main.level.get_instance_id() != old_level_id, "restart 同实例换新关卡")
	_check(not is_instance_id_valid(old_visual_id), "restart destroys old projectiles")
	_check(is_instance_id_valid(old_bar_id) and bar == _main.doll.health_bar, "restart 保留同一血条节点")
	_check(get_nodes_in_group("combat_feedback").is_empty(), "restart no lingering feedback")
	_check(_main.doll.health_bar.visible and _main.doll.health_bar.ratio == 1.0, "restart fresh full health")
	print("=== COMBAT FEEDBACK %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
