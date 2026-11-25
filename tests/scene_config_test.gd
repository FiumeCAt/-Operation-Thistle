extends SceneTree
## Phase 1 回归：Godot 编辑器可调固定场景属性、.tres 配置资源生效、动态边界隔离与空配置安全回退。
## godot --headless --path . --script res://tests/scene_config_test.gd

const CAM_CFG := preload("res://scripts/config/CameraFeelConfig.gd")
const COMBAT_CFG := preload("res://scripts/config/CombatFeelConfig.gd")
const VISION_CFG := preload("res://scripts/config/VisionLightingConfig.gd")
const DOLL_CFG := preload("res://scripts/config/DollConfig.gd")
const MENU_CFG := preload("res://scripts/config/StartMenuConfig.gd")

var _ok := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(2))
	print("=== scene_config_test ===")
	root.size = Vector2i(1600, 900)
	await process_frame

	var p = root.get_node_or_null("Progress")
	if p == null:
		_check(false, "Progress autoload exists")
		quit(1)
		return
	p.reset_for_test()

	# 1) 5 份默认 .tres 配置资产均可正常加载
	for path in [
		"res://resources/config/camera_feel_default.tres",
		"res://resources/config/combat_feel_default.tres",
		"res://resources/config/vision_lighting_default.tres",
		"res://resources/config/doll_default.tres",
		"res://resources/config/start_menu_default.tres",
	]:
		var res := load(path)
		_check(res is Resource, "default config loads: " + path)

	# 2) 默认 Main2D.tscn 挂载 3 份配置资源，且动态边界/出生点不被固化
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	_check(main.camera_config != null and main.combat_config != null and main.vision_config != null,
		"Main2D.tscn attaches camera/combat/vision .tres configs")
	_check(main.get_node("Camera2D").zoom.is_equal_approx(Vector2(0.95, 0.95)),
		"Main2D.tscn Camera2D.zoom matches runtime 0.95 default")
	_check(main.get_node("World2D/CanvasModulate").color.is_equal_approx(Color(0.40, 0.43, 0.48, 1.0)),
		"Main2D.tscn CanvasModulate.color matches default fog ambient")
	root.add_child(main)
	await process_frame
	await physics_frame
	_check(main.doll.global_position.is_equal_approx(main.level.player_spawn),
		"Doll2D.position stays dynamically driven by procedural level.player_spawn")
	_check(main.camera.limit_right != 1536 and main.camera.limit_bottom != 1152,
		"Camera2D.limit_* stays dynamically driven by procedural level bounds")
	main.queue_free()
	await process_frame

	# 3) 编辑器修改场景节点属性 + 自定义 .tres 覆盖在运行时真正生效
	var main_custom = load("res://scenes/core/Main2D.tscn").instantiate()
	main_custom.mouse_aim_enabled = false
	main_custom.get_node("Camera2D").zoom = Vector2(1.25, 1.25)
	var custom_ambient := Color(0.55, 0.42, 0.35, 1.0)
	main_custom.get_node("World2D/CanvasModulate").color = custom_ambient
	main_custom.clear_color = Color(0.10, 0.12, 0.16, 1.0)
	main_custom.get_node("DebugOverlay2D").visible = true
	var custom_cam := CAM_CFG.new()
	custom_cam.camera_lift = 72.0
	custom_cam.view_zoom_max = 240.0
	custom_cam.ads_look_ahead = 480.0
	main_custom.camera_config = custom_cam
	var custom_combat := COMBAT_CFG.new()
	custom_combat.recoil_ads_mul = 0.25
	custom_combat.shake_scale_base = 8.0
	main_custom.combat_config = custom_combat
	var custom_vision := VISION_CFG.new()
	custom_vision.clear_energy = 0.95
	custom_vision.dark_energy = 0.35
	main_custom.vision_config = custom_vision
	p.data["talents_2d"]["hp"] = 2

	root.add_child(main_custom)
	await process_frame
	await physics_frame
	_check(is_equal_approx(main_custom._base_zoom, 1.25)
		and absf(main_custom.camera.zoom.x - 1.25) < 0.01,
		"Main2D honors editor-edited Camera2D.zoom (1.25)")
	_check(main_custom.vision.ambient_color.is_equal_approx(custom_ambient),
		"VisionFog2D honors editor-edited CanvasModulate.color")
	_check(main_custom.debug_visual_mode and main_custom.debug_overlay.visible,
		"Main2D honors editor-toggled DebugOverlay2D.visible=true")
	main_custom.debug_visual_mode = false
	main_custom._apply_debug_visual_mode()
	_check(main_custom.canvas_modulate.color.is_equal_approx(custom_ambient),
		"turning off F7 debug lighting restores editor custom ambient color")
	_check(is_equal_approx(main_custom.vision._clear_light.energy, 0.95)
		and is_equal_approx(main_custom.vision._dark_light.energy, 0.35),
		"VisionLightingConfig overrides clear/dark light energies")
	_check(is_equal_approx(main_custom.feedback_system.shake_scale, 8.0),
		"CombatFeelConfig overrides FeedbackSystem2D shake_scale_base")
	main_custom._ads_t = 1.0
	_check(is_equal_approx(main_custom.combat_system.recoil_strength(), 0.25),
		"CombatFeelConfig overrides CombatSystem2D recoil_ads_mul")
	main_custom._set_view_zoom(240.0)
	_check(is_equal_approx(main_custom.view_zoom_pct, 240.0),
		"CameraFeelConfig overrides view_zoom_max (240%)")
	_check(main_custom.doll.hp_max == 130,
		"Player HP max remains dynamically calculated from Progress talents (100 + 2*15)")
	main_custom.queue_free()
	await process_frame

	# 4) Doll2D.tscn：Body.offset 微调保留 + DollConfig 资源覆盖 + 动态血甲不固化
	var doll_scene = load("res://scenes/actors/Doll2D.tscn").instantiate()
	_check(doll_scene.config != null, "Doll2D.tscn attaches doll_default.tres")
	_check(doll_scene.get_node("Body").offset.is_equal_approx(Vector2(0, -144)),
		"Doll2D.tscn Body.offset matches default 256px LOD (-144)")
	doll_scene.get_node("Body").offset = Vector2(4, -152)
	var custom_doll := DOLL_CFG.new()
	custom_doll.ads_speed_mul = 0.75
	custom_doll.hurt_invuln_sec = 0.35
	custom_doll.fire_flinch_px = 5.0
	doll_scene.config = custom_doll
	root.add_child(doll_scene)
	await process_frame
	_check(doll_scene._editor_body_offset_delta.is_equal_approx(Vector2(4, -8))
		and doll_scene.body.offset.is_equal_approx(Vector2(4, -152)),
		"Doll2D preserves editor Body.offset adjustment across _apply_sheet")
	doll_scene.take_damage(10.0, 99.0)
	_check(is_equal_approx(doll_scene.invuln, 0.35),
		"DollConfig overrides hurt_invuln_sec")
	doll_scene._on_weapon_fired(Vector2.ZERO, Vector2.RIGHT)
	_check(is_equal_approx(doll_scene._flinch.x, -5.0),
		"DollConfig overrides fire_flinch_px")
	doll_scene.queue_free()
	await process_frame

	# 5) StartMenu2D.tscn：挂载 StartMenuConfig + 自定义轮播与蒙版参数生效 + 空配置回退
	var menu_scene = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	_check(menu_scene.config != null, "StartMenu2D.tscn attaches start_menu_default.tres")
	var custom_menu := MENU_CFG.new()
	custom_menu.bg_hold_seconds = 14.0
	custom_menu.bg_fade_seconds = 3.0
	custom_menu.left_mask_alpha = 0.25
	menu_scene.config = custom_menu
	root.add_child(menu_scene)
	await process_frame
	_check(is_equal_approx(menu_scene._bg_hold_seconds(), 14.0)
		and is_equal_approx(menu_scene._bg_fade_seconds(), 3.0)
		and menu_scene._backdrop_overlay.menu_config == custom_menu,
		"StartMenu2D honors custom StartMenuConfig carousel and overlay parameters")
	menu_scene.queue_free()
	await process_frame

	# 6) 脱离 .tscn（config == null）平滑回退全部 const 默认值
	var bare_menu := StartMenu2D.new()
	root.add_child(bare_menu)
	await process_frame
	_check(is_equal_approx(bare_menu._bg_hold_seconds(), StartMenu2D.BG_HOLD_SECONDS)
		and bare_menu._bg_textures.size() == 3,
		"StartMenu2D.new() without .tres falls back cleanly to const defaults")
	bare_menu.queue_free()
	await process_frame

	var main_null = load("res://scenes/core/Main2D.tscn").instantiate()
	main_null.mouse_aim_enabled = false
	main_null.camera_config = null
	main_null.combat_config = null
	main_null.vision_config = null
	main_null.get_node("World2D/SortLayer/Doll2D").config = null
	root.add_child(main_null)
	await process_frame
	await physics_frame
	_check(is_equal_approx(main_null._cam_float(&"camera_lift", main_null.CAMERA_LIFT), main_null.CAMERA_LIFT)
		and is_equal_approx(main_null.vision._clear_light.energy, VisionFog2D.CLEAR_ENERGY),
		"Main2D and Doll2D run cleanly when all config resources are null")
	main_null.queue_free()
	await process_frame

	p.reset_for_test()
	print("=== scene_config_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
