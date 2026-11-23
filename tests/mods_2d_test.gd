extends SceneTree
## 配件 / 组件系统回归：进阶资源消耗、武器数据、护甲组件与存档持久化。
## godot --headless --path . --script res://tests/mods_2d_test.gd

var _pass := 0
var _fail := 0


## 视线测试替身：一根小柱子挡在直线正中，侧向偏移的采样线应能绕过。
class MockLevel extends Node:
	var block_center := Vector2.ZERO
	var block_radius := 9.0

	func is_nav_walkable(point: Vector2) -> bool:
		return point.distance_to(block_center) > block_radius


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
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()
	p.data["resources"] = 3000
	p.data["advanced_2d"] = {
		"weapon_parts": 10, "electronic_core": 10,
		"high_energy_cell": 10, "military_alloy": 10,
	}
	p.set_loadout_2d(&"m870", &"g17")

	# ---- 配件表 ----
	_check(ModDB.WEAPON_SLOTS.size() == 6 and ModDB.ARMOR_SLOTS.size() == 3,
		"weapon has six mod slots and armor keeps three")
	_check(ModDB.options("muzzle", false).size() == 3
		and ModDB.options("plate", true).size() == 3,
		"slots expose their options")
	_check(ModDB.options("stock", false).size() == 3
		and ModDB.options("grip", false).size() == 3
		and ModDB.options("sight", false).size() == 10,
		"stock/grip expose three options and all ten sights are available")
	_check(ModDB.option("muzzle", "bogus", false).is_empty(),
		"unknown mod option is rejected")

	# ---- 武器配件安装与扣费 ----
	_check(p.install_weapon_mod(&"m870", &"muzzle", &"compensator"),
		"install muzzle compensator")
	_check(p.credits() == 2820 and p.advanced_count(&"weapon_parts") == 7,
		"install spends credits and weapon parts")
	var mods: Dictionary = p.weapon_mods_2d(&"m870")
	_check(String(mods.get("muzzle", "")) == "compensator", "muzzle mod is stored")
	_check(p.install_weapon_mod(&"m870", &"muzzle", &"compensator")
		and p.credits() == 2820, "reinstalling the same mod is free")
	_check(p.install_weapon_mod(&"m870", &"magazine", &"tube_long")
		and p.install_weapon_mod(&"m870", &"core", &"reinforced"),
		"install magazine and core mods")
	_check(p.credits() == 2295 and p.advanced_count(&"weapon_parts") == 5
		and p.advanced_count(&"military_alloy") == 7,
		"mod costs stack across slots")

	# ---- 护甲组件安装 ----
	_check(p.install_armor_mod(&"plate", &"ceramic"), "install ceramic plate")
	_check(p.install_armor_mod(&"liner", &"gel"), "install gel liner")
	_check(p.install_armor_mod(&"core", &"servo"), "install servo core")
	_check(p.armor_mods_2d().size() == 3, "armor stores three components")
	_check(p.advanced_count(&"military_alloy") == 4
		and p.advanced_count(&"high_energy_cell") == 4,
		"armor components spend advanced resources")

	# ---- 本局生效：武器数据 ----
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	var rig: WeaponRig2D = main.doll.weapon_rig
	_check(rig != null and rig.weapon_id == &"m870", "run starts with the modded weapon")
	_check(is_equal_approx(rig.damage_mul, 1.15) and is_equal_approx(rig.spread_mul, 0.85),
		"core damage and muzzle spread mods apply")
	_check(rig.data.mag_capacity == 7, "long tube raises capacity to 7")
	_check(is_equal_approx(rig.data.load_time, 0.33), "long tube slows reload")
	_check(is_equal_approx(rig.data.fire_interval, 0.28 * 1.08),
		"reinforced bolt slows fire interval")

	# ---- 本局生效：护甲组件 ----
	_check(main.doll.armor_max == 140, "ceramic plate raises armor max to 140")
	_check(main.doll.armor == 140, "armor starts full at the new cap")
	_check(is_equal_approx(main.doll.armor_absorb_bonus, 0.05),
		"gel liner raises absorb ratio")
	_check(is_equal_approx(main.doll.walk_speed, 250.0 * 1.06),
		"servo core raises movement speed")

	# ---- 新槽位：后托 / 握把下挂 / 瞄具 ----
	p.data["resources"] = 2000
	p.data["advanced_2d"] = {
		"weapon_parts": 10, "electronic_core": 10,
		"high_energy_cell": 10, "military_alloy": 10,
	}
	_check(p.install_weapon_mod(&"m870", &"stock", &"heavy"),
		"install heavy stock")
	_check(p.install_weapon_mod(&"m870", &"grip", &"laser"),
		"install underbarrel laser")
	_check(p.install_weapon_mod(&"m870", &"sight", &"red_dot"),
		"install red dot sight")
	var new_mods: Dictionary = ModDB.modifiers(p.weapon_mods_2d(&"m870"), false, "m870")
	_check(is_equal_approx(float(new_mods["recoil_mul"]), 0.75),
		"heavy stock lowers recoil multiplier")
	_check(is_equal_approx(float(new_mods["vision_mul"]), 1.15),
		"red dot raises vision multiplier")
	_check(is_equal_approx(float(new_mods["ads_speed_mul"]), 1.30),
		"underbarrel laser speeds up aiming")
	_check(bool(new_mods["laser"]), "underbarrel laser flag is on")
	var scope_data := ModDB.option("sight", "scope", false, "m870")
	_check(is_equal_approx(float(scope_data.get("magnification", 0.0)), 4.0)
		and String(scope_data.get("reticle", "")) == "cross"
		and bool(scope_data.get("scope", false)),
		"4x scope metadata exposes magnification and cross reticle")
	var pso_data := ModDB.option("sight", "pso", false, "m870")
	_check(is_equal_approx(float(pso_data.get("magnification", 0.0)), 4.0)
		and String(pso_data.get("reticle", "")) == "pso",
		"PSO sight uses its own reticle")
	var rig2 := WeaponRig2D.new()
	root.add_child(rig2)
	await process_frame
	rig2.setup(&"m870")
	_check(rig2.has_laser and is_equal_approx(rig2.vision_mul, 1.15)
		and is_equal_approx(rig2.ads_speed_mul, 1.30),
		"new mods reach the live weapon rig")
	_check(rig2.sight_reticle == "dot" and not rig2.has_scope_sight
		and is_equal_approx(rig2.aim_zoom_mul, 1.1),
		"red dot exposes a 1.1x dot reticle and ADS zoom bonus")
	var base_growth := WeaponDB.get_weapon(&"m870").spread_growth
	_check(is_equal_approx(rig2.data.spread_growth, base_growth * 0.75),
		"stock lowers burst recoil growth")
	_check(is_equal_approx(rig2.data.shake_amount,
		WeaponDB.get_weapon(&"m870").shake_amount * 0.75),
		"stock lowers firing shake")
	rig2.queue_free()

	# ---- 本局表现：激光可见 + 瞄具扩展视野 ----
	main.doll.weapon_rig.setup(&"m870")
	main.doll.aim_target = main.doll.global_position + Vector2.RIGHT * 300.0
	for i in 12:
		await process_frame
	_check(main.laser_sight != null and main.laser_sight._active,
		"underbarrel laser draws a beam when equipped")
	var aim_dir: Vector2 = (main.doll.aim_target - main.laser_sight._from).normalized()
	var laser_seg: Vector2 = main.laser_sight._to - main.laser_sight._from
	_check(laser_seg.normalized().dot(aim_dir) > 0.985,
		"laser follows the crosshair instantly and extends to the wall")
	# 子弹应从信号里的枪口出发，中心线指向准心。
	var muzzle_before: Vector2 = main.doll.weapon_rig.get_muzzle_position()
	var aim_before: Vector2 = main.doll.aim_target
	main.doll.weapon_rig.cooldown = 0.0
	var fired_ok: bool = main.doll.weapon_rig.try_fire()
	await process_frame
	_check(fired_ok and main.last_shot_origin.distance_to(muzzle_before) < 8.0,
		"shots start from the visual muzzle")
	_check(main.last_shot_dir.dot((aim_before - muzzle_before).normalized()) > 0.98,
		"shot centerline points at the crosshair")
	_check(main.vision != null and main.vision.vision_mul > 1.05,
		"red dot sight expands the player's vision")
	_check(is_equal_approx(main.ZOOM, 0.95), "base camera zoom is halved for a wider view")

	# ---- 激光/准心颜色自定义 ----
	p.set_laser_color(Color(0.4, 0.8, 1.0))
	p.set_reticle_color(Color(0.9, 0.3, 0.9))
	for i in 4:
		await process_frame
	var lc: Color = p.laser_color()
	var rc: Color = p.reticle_color()
	_check(absf(lc.r - 0.4) < 0.02 and absf(lc.g - 0.8) < 0.02,
		"laser color is saved")
	_check(absf(rc.r - 0.9) < 0.02 and absf(rc.b - 0.9) < 0.02,
		"reticle color is saved")
	_check(absf(main.laser_sight._beam_color.g - 0.8) < 0.02,
		"laser uses the custom color")
	_check(absf(main.scope_sight._reticle_color.r - 0.9) < 0.02,
		"scope reticle uses the custom color")

	# ---- 瞄具固定属性：倍率 / 视野 / 镜内 / 射程 / 瞄准时间 ----
	var sight_cases := [
		["red_dot", 1.1, 1.15, false, 1.0, 1.0],
		["holo", 1.5, 1.20, false, 1.0, 1.0],
		["sight_2x", 2.0, 1.35, true, 1.0, 1.0],
		["sight_2_5x", 2.5, 1.40, true, 1.05, 1.10],
		["sight_3x", 3.0, 1.60, true, 1.08, 1.15],
		["scope", 4.0, 1.75, true, 1.10, 1.20],
		["pso", 4.0, 1.75, true, 1.10, 1.20],
		["vudu", 6.0, 1.80, true, 1.10, 1.20],
		["sniper_8x", 8.0, 2.00, true, 1.15, 1.35],
	]
	var base_range: float = WeaponDB.get_weapon(&"m870").range_m
	var saved_sight_mods: Dictionary = p.weapon_mods_2d(&"m870").duplicate()
	for sight_case in sight_cases:
		var sight_id := String(sight_case[0])
		p.data["weapon_mods_2d"]["m870"] = {"sight": sight_id}
		main.doll.weapon_rig.setup(&"m870")
		var sight_rig = main.doll.weapon_rig
		var stats_ok: bool = absf(sight_rig.sight_magnification - float(sight_case[1])) < 0.001 \
			and absf(sight_rig.vision_mul - float(sight_case[2])) < 0.001 \
			and sight_rig.has_scope_sight == bool(sight_case[3]) \
			and absf(sight_rig.sight_ads_time_mul - float(sight_case[5])) < 0.001 \
			and absf(sight_rig.data.range_m / base_range - float(sight_case[4])) < 0.001
		_check(stats_ok, "sight %s applies its fixed stats" % sight_id)
	# 准星切换：玩家选择的样式覆盖瞄具默认准心。
	p.data["weapon_mods_2d"]["m870"] = {"sight": "pso"}
	p.set_reticle_style("pso", "cross")
	main.doll.weapon_rig.setup(&"m870")
	_check(main.doll.weapon_rig.sight_reticle == "cross",
		"reticle switching overrides the sight's default reticle")
	p.set_reticle_style("pso", "pso")
	p.data["weapon_mods_2d"]["m870"] = saved_sight_mods
	main.doll.weapon_rig.setup(&"m870")

	# ---- 开镜不得移动准心下的世界点（瞄准箱子不能变成门）----
	_check(p.install_weapon_mod(&"m870", &"sight", &"pso"), "install PSO sight")
	main.doll.set_physics_process(false)
	main.doll.weapon_rig.setup(&"m870")
	main.doll.aim_target = main.doll.global_position + Vector2.RIGHT * 420.0
	main.doll.weapon_rig.ads = false
	main.doll.ads = false
	for i in 8:
		await process_frame
	main.doll.weapon_rig.ads = true
	main.doll.ads = true
	for i in 30:
		await process_frame
	# 头部无渲染时 Camera2D 的 canvas_transform 不刷新，因此这里只断言逻辑倍率；
	# 开镜前后准心下的世界点是否保持不变，由 tests/_capture_scope_align_video.gd 实机验证。
	_check(is_equal_approx(main.scope_magnification, 1.0),
		"scope ADS keeps the main camera steady so the aim point cannot shift")
	# PSO 准星贴图：透明背景，无残留。
	var pso_tex = main.scope_sight._pso_texture()
	_check(pso_tex != null, "PSO reticle texture is available")
	if pso_tex != null:
		var pso_img: Image = pso_tex.get_image()
		_check(pso_img != null and pso_img.get_pixel(0, 0).a < 0.01,
			"PSO reticle has a transparent background")
	# 镜内放大与玩家视角缩放联动：40% 视角时实际放大降到 40%。
	main._view_zoom_visual = 100.0
	for i in 2:
		await process_frame
	var lens_zoom_full: float = main.scope_sight._cam.zoom.x
	main._view_zoom_visual = 40.0
	for i in 2:
		await process_frame
	var lens_zoom_low: float = main.scope_sight._cam.zoom.x
	_check(lens_zoom_full > 3.5 and lens_zoom_full / maxf(lens_zoom_low, 0.01) > 2.0,
		"scope magnification follows the player view zoom")
	main._view_zoom_visual = float(p.data.get("view_zoom", 100))
	for i in 2:
		await process_frame
	_check(main.doll.weapon_rig.sight_reticle == "pso"
		and main.doll.weapon_rig.has_scope_sight
		and is_equal_approx(main.doll.weapon_rig.sight_magnification, 4.0),
		"PSO sight reaches the live weapon")
	_check(main.scope_sight != null and main.scope_sight._lens_visible
		and main.scope_sight._fade > 0.5, "4x scope lens appears while aiming")
	_check(main.scope_sight.should_hide_reticle(),
		"scope reticle replaces the default crosshair")
	_check(is_equal_approx(main.scope_sight._cam.zoom.x, 4.0),
		"scope lens magnifies by the sight's rated 4x")
	var scope_focus: Vector2 = main.scope_sight._cam.global_position
	_check(scope_focus.distance_to(main.doll.aim_target) < 8.0,
		"scope lens stays centered on the crosshair target")
	# 镜窗必须与准心的屏幕位置严格同点，靠近屏幕边缘也不能被夹取偏移。
	var aim_screen: Vector2 = main.get_viewport().get_canvas_transform() * main.doll.aim_target
	_check(main.scope_sight._center.distance_to(aim_screen) < 1.0,
		"scope lens sits exactly on the crosshair screen position")
	# 瞄准点接近/超出屏幕边缘时，镜窗不能被夹回屏幕内，否则会与准心错位。
	var edge_target: Vector2 = main.doll.global_position + Vector2.RIGHT * 2200.0
	main.doll.aim_target = edge_target
	for i in 4:
		await process_frame
	var edge_screen: Vector2 = main.get_viewport().get_canvas_transform() * edge_target
	var view_w: float = main.get_viewport().get_visible_rect().size.x
	_check(edge_screen.x > view_w
		and main.scope_sight._center.distance_to(edge_screen) < 1.0,
		"scope lens follows the crosshair past the screen edge without clamping")
	# 前探必须即时跟随：换方向后画面要马上停住，不能继续滑行把镜内目标带偏。
	main.doll.aim_target = main.doll.global_position + Vector2(300, 420)
	for i in 4:
		await process_frame
	var view_hold: Vector2 = main.get_viewport().get_canvas_transform().get_origin()
	for i in 12:
		await process_frame
	_check(view_hold.distance_to(
		main.get_viewport().get_canvas_transform().get_origin()) < 1.0,
		"scoped view stops as soon as the aim settles")
	# ---- 高倍镜前探距离必须随倍率增长，且角色缩放仍为 1.0× ----
	var look_by_sight: Dictionary = {}
	for sid in ["iron", "sight_2x", "pso", "sniper_8x"]:
		p.data["weapon_mods_2d"]["m870"]["sight"] = sid
		main.doll.weapon_rig.setup(&"m870")
		main.doll.aim_target = main.doll.global_position + Vector2.RIGHT * 600.0
		main.doll.weapon_rig.ads = true
		main.doll.ads = true
		for i in 28:
			await process_frame
		look_by_sight[sid] = main.camera.global_position.x - main.doll.global_position.x
	_check(float(look_by_sight["sight_2x"]) > float(look_by_sight["iron"]) + 20.0
		and float(look_by_sight["pso"]) > float(look_by_sight["sight_2x"]) + 20.0
		and float(look_by_sight["sniper_8x"]) > float(look_by_sight["pso"]) + 20.0,
		"magnified scopes extend ADS camera look-ahead progressively (iron < 2x < 4x < 8x)")
	# 恢复 PSO 供后续镜头特效检查。
	p.data["weapon_mods_2d"]["m870"]["sight"] = "pso"
	main.doll.weapon_rig.setup(&"m870")
	for i in 8:
		await process_frame
	# ---- 激光材质：自发光 + 加法混合 + 线性柔光过滤 ----
	var laser_mat := main.laser_sight.material as CanvasItemMaterial
	_check(laser_mat != null
		and laser_mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
		and laser_mat.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED
		and main.laser_sight.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
		"laser sight uses additive unshaded material with linear glow filtering")
	# ---- 镜内特效开关 ----
	var lens_mat: ShaderMaterial = main.scope_sight._lens.material
	p.data["scope_lens_distortion"] = false
	for i in 2:
		await process_frame
	_check(lens_mat != null and float(lens_mat.get_shader_parameter("distort")) == 0.0,
		"scope lens distortion can be turned off")
	p.data["scope_lens_distortion"] = true
	for i in 2:
		await process_frame
	_check(float(lens_mat.get_shader_parameter("distort")) > 0.1,
		"scope lens distortion is on by default")
	p.data["scope_motion_blur"] = false
	for i in 2:
		await process_frame
	_check((lens_mat.get_shader_parameter("motion") as Vector2).length() < 0.0001,
		"scope motion blur can be turned off")
	p.data["scope_motion_blur"] = true
	# ---- 瞄具视野倍率：必须拓宽视野锥，而不是只拉长早已超出屏幕的距离 ----
	var fog: VisionFog2D = main.vision
	var saved_level = fog.level
	fog.level = null
	fog._aim_angle = 0.0
	fog.vision_mul = 1.0
	var eye: Vector2 = fog._eye_position()
	var reach := 10.0 * fog.PIXELS_PER_METER
	var at45: Vector2 = eye + Vector2.from_angle(deg_to_rad(45.0)) * reach
	var at62: Vector2 = eye + Vector2.from_angle(deg_to_rad(62.0)) * reach
	var at70: Vector2 = eye + Vector2.from_angle(deg_to_rad(70.0)) * reach
	var at50: Vector2 = eye + Vector2.from_angle(deg_to_rad(50.0)) * reach
	_check(fog.tier_at(at50) == 1 and fog.tier_at(at70) == 0,
		"iron sights leave 50deg dim and 70deg fogged")
	# 灯光锥是 Y 方向拉伸 vision_mul 倍，判定同一几何：1.35× → 清晰半角 48.6°、总半角 66.8°。
	fog.vision_mul = 1.35
	_check(fog.tier_at(at45) == 2 and fog.tier_at(at62) == 1 and fog.tier_at(at70) == 0,
		"sight vision bonus widens both cones using the light's own stretch geometry")
	_check(absf(rad_to_deg(VisionFog2D.widened_half_angle(40.0, 1.35)) - 48.6) < 0.2,
		"widened_half_angle follows atan(tan(base) x mul)")
	_check(is_equal_approx(fog.CLEAR_RANGE_METERS, 40.0)
		and is_equal_approx(fog.TOTAL_RANGE_METERS, 40.0),
		"base vision range reaches 40 meters")
	# 细柱/墙角挡在视线正中时，三线采样应仍判定可见（旧单线会误判为遮挡）。
	var mock := MockLevel.new()
	mock.block_center = eye + Vector2(200, 0)
	fog.level = mock
	_check(fog.line_clear(eye, eye + Vector2(400, 0)),
		"thin obstacles no longer blank out an enemy that is clearly visible")
	fog.level = saved_level
	fog.vision_mul = 1.0
	# ---- 声纹：附近移动敌人在对应方向亮起方位弧 ----
	var listener = main.enemies[0] if not main.enemies.is_empty() else null
	if listener != null:
		listener.set_physics_process(false)
		listener.global_position = main.doll.global_position + Vector2(0, 300)
		listener.velocity = Vector2(0, 140)
		for i in 12:
			await process_frame
		_check(main.hearing != null and main.hearing._alphas[3] > 0.05,
			"hearing indicator shows an arc for a moving enemy behind the player")
		listener.velocity = Vector2.ZERO
		for i in 30:
			await process_frame
		_check(main.hearing._alphas[3] < 0.05,
			"hearing arc fades when the enemy stops moving")
	# ---- 边缘视野层 80% 不透明度 + 离开视野时淡出 ----
	main.doll.aim_target = main.doll.global_position + Vector2(1000, 0)
	for i in 12:
		await process_frame
	fog.level = null
	fog._aim_angle = 0.0
	var saved_vision: float = main.doll.weapon_rig.vision_mul
	main.doll.weapon_rig.vision_mul = 1.0
	fog.vision_mul = 1.0
	var edge_enemy = main.enemies[0] if not main.enemies.is_empty() else null
	if edge_enemy != null:
		edge_enemy.set_physics_process(false)
		edge_enemy.global_position = eye + Vector2.from_angle(deg_to_rad(52.0)) * reach
		fog.refresh_enemies()
		fog._update_enemy_fade(0.30)
		for i in 6:
			await process_frame
		_check(edge_enemy.visible and absf(edge_enemy.modulate.a - 0.8) < 0.06,
			"edge-tier enemy uses 80% opacity")
		edge_enemy.global_position = eye + Vector2.from_angle(deg_to_rad(80.0)) * reach
		fog.refresh_enemies()
		fog._update_enemy_fade(0.30)
		for i in 6:
			await process_frame
		_check(not edge_enemy.visible or edge_enemy.modulate.a < 0.05,
			"enemy fades out instead of popping when leaving the cone")
	main.doll.weapon_rig.vision_mul = saved_vision
	fog.level = saved_level
	main.doll.weapon_rig.ads = false
	main.doll.ads = false
	main.doll.set_physics_process(true)

	# ---- 存档持久化 ----
	p.save_data()
	p.data = {}
	p.load_data()
	_check(String(p.weapon_mods_2d(&"m870").get("muzzle", "")) == "compensator"
		and String(p.weapon_mods_2d(&"m870").get("grip", "")) == "laser"
		and String(p.armor_mods_2d().get("plate", "")) == "ceramic",
		"mods persist across reload")

	# ---- 弹匣绝对容量与全自动改件 ----
	p.data["resources"] = 2000
	p.data["advanced_2d"] = {
		"weapon_parts": 10, "electronic_core": 10,
		"high_energy_cell": 10, "military_alloy": 10,
	}
	_check(p.install_weapon_mod(&"saiga12k", &"magazine", &"mag_drum")
		and p.install_weapon_mod(&"saiga12k", &"core", &"auto"),
		"saiga drum and full-auto kit install")
	var saiga := WeaponRig2D.new()
	root.add_child(saiga)
	await process_frame
	saiga.setup(&"saiga12k")
	_check(saiga.data.mag_capacity == 20, "saiga drum gives 20 rounds")
	_check(saiga.data.auto_fire, "saiga full-auto kit enables automatic fire")
	_check(is_equal_approx(saiga.spread_mul, 1.5), "saiga auto kit widens spread")
	saiga.queue_free()

	_check(p.install_weapon_mod(&"g17", &"magazine", &"mag_long")
		and p.install_weapon_mod(&"g17", &"core", &"auto"),
		"g17 long magazine and full-auto kit install")
	var pistol := WeaponRig2D.new()
	root.add_child(pistol)
	await process_frame
	pistol.setup(&"g17")
	_check(pistol.data.mag_capacity == 33, "g17 long magazine gives 33 rounds")
	_check(pistol.data.auto_fire and is_equal_approx(pistol.data.fire_interval, 0.10),
		"g17 auto kit sets 600 RPM")
	pistol.queue_free()

	# ---- 资源不足拒绝安装 ----
	p.data["resources"] = 0
	p.data["advanced_2d"]["weapon_parts"] = 0
	_check(not p.install_weapon_mod(&"g17", &"muzzle", &"choke"),
		"install fails without credits or materials")

	main.queue_free()
	await process_frame
	print("\n=== mods 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
