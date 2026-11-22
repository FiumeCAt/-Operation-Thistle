extends SceneTree
## M0 冒烟测试：场景能实例化、8 向动画齐全、相机参数正确、瞄准点有效。
## 运行：godot --headless --path . --script res://tests/smoke_test.gd

var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)

func _run() -> void:
	print("=== Operation Thistle M0 smoke test ===")

	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "fire", "aim"]:
		_check(InputMap.has_action(a), "input action: " + a)

	var packed: PackedScene = load("res://scenes/core/Main.tscn")
	_check(packed != null, "Main.tscn loads")
	if packed == null:
		quit(1)
		return

	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await physics_frame

	var doll: Doll = main.get_node_or_null("Doll")
	_check(doll != null, "Doll exists")
	_check(main.get_node_or_null("Level") != null, "Level exists")
	var lvl = main.get_node_or_null("Level")
	if lvl != null:
		_check(lvl.room_centers.size() >= 3, "procedural rooms >= 3, got %d" % lvl.room_centers.size())
		_check(lvl.enemy_spawns.size() >= 3, "enemy spawn points >= 3, got %d" % lvl.enemy_spawns.size())
		_check(lvl.nav_region != null and lvl.nav_region.navigation_mesh != null, "nav region baked")
		if lvl.nav_region != null and lvl.nav_region.navigation_mesh != null:
			_check(lvl.nav_region.navigation_mesh.get_polygon_count() > 0, "navmesh has polygons")
	_check(main.get_node_or_null("CameraRig/Camera3D") != null, "Camera3D exists")
	_check(main.get_node_or_null("MotionBlur") != null, "MotionBlur exists")
	_check(main.get_node_or_null("PixelGrade") != null, "PixelGrade exists")
	var wv = main.get_node_or_null("WeaponVisual")
	_check(wv != null, "WeaponVisual exists")
	_check(wv != null and wv is Node3D, "WeaponVisual is Node3D (not screen-space)")
	_check(doll != null and Doll.HAND_LOCAL.has("LOW") and Doll.HAND_LOCAL.has("AIM") and Doll.HAND_LOCAL.has("RELOAD"),
		"hand anchor groups LOW/AIM/RELOAD")
	# 握把锚点应为米制偏移（x 横向 / y 离地高度），且高度落在角色身高范围内
	for g2 in ["LOW", "AIM", "RELOAD"]:
		var off2: Vector2 = Doll.HAND_LOCAL[g2]
		_check(off2.y > 0.4 and off2.y < 1.7, "hand anchor %s height in body range, got %.2fm" % [g2, off2.y])
	# ---- 敌人与准心
	_check(EnemyDB.ORDER.size() >= 3, "enemy types >= 3, got %d" % EnemyDB.ORDER.size())
	for eid in EnemyDB.ORDER:
		var st := EnemyDB.stats(eid)
		_check(ResourceLoader.exists(String(st["texture"])), "enemy texture exists: " + String(eid))
	var eroot = main.get_node_or_null("Enemies")
	_check(eroot != null, "Enemies container exists")
	if eroot:
		var live := 0
		for c in eroot.get_children():
			if c is Enemy:
				live += 1
		_check(live >= 3, "enemies spawned, got %d" % live)
	_check(main.reticle != null, "AimReticle exists")

	var sfx = root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload exists")
	if sfx:
		_check(sfx.streams.size() >= 10, "sfx streams generated, got %d" % sfx.streams.size())
		_check(sfx.get_stream("shotgun") != null, "shotgun sfx exists")
		_check(sfx.get_stream("ambient") != null, "ambient sfx exists")

	if doll == null:
		print("=== FAILED: %d ===" % _fails)
		quit(1)
		return

	_check(doll.weapon != null, "weapon child exists")
	if doll.weapon:
		var w: PlayerWeapon = doll.weapon
		_check(w.chamber == "LOADED", "shotgun chamber loaded")
		_check(w.mag == 5, "shotgun mag = 5")
		_check(w.get_ammo().pellets == 8, "buckshot pellets = 8")

		w.try_fire()
		_check(w.chamber == "FIRED", "fire -> chamber FIRED")
		_check(w.mag == 5, "fire does not consume tube")
		w.pump_action()
		_check(w.chamber == "LOADED", "pump -> chamber LOADED")
		_check(w.mag == 4, "pump consumes one tube shell")
		await create_timer(0.45).timeout

		var reserve_before := w.get_reserve()
		w.try_load_shell()
		_check(w.mag == 5, "F loads one shell into tube")
		_check(w.get_reserve() == reserve_before - 1, "F consumes reserve")
		await create_timer(0.40).timeout

		w.switch_ammo()
		_check(w.ammo_type == &"slug", "Q switches to slug")
		_check(w.get_loaded_total() == 0, "Q empties chamber and tube")

	var cam: Camera3D = main.get_node("CameraRig/Camera3D")
	_check(is_equal_approx(cam.fov, 38.0), "camera fov = 38")
	_check(not cam.current == false, "camera is current")

	var names: PackedStringArray = doll.billboard.body.sprite_frames.get_animation_names()
	_check(names.size() == 56, "sprite frames has 56 animations (8 dir x 7 states), got %d" % names.size())
	for d in 8:
		_check(names.has("idle_%d" % d), "idle dir %d exists" % d)
	_check(names.has("death_7"), "death dir 7 exists")

	_check(is_finite(doll.aim_point.x) and is_finite(doll.aim_point.z), "aim point is finite")
	_check(doll.get_speed() < 100.0, "speed sane")

	print("=== %s (%d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _fails])
	quit(0 if _fails == 0 else 1)
