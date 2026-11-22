extends Node3D
## M0 主场景装配：环境光/主光、相机目标、准星、HUD、压力测试、截图工具。

const RETICLE_SCENE := preload("res://scenes/fx/AimReticle.tscn")
const CAPTURE_SCRIPT := preload("res://scripts/dev/CaptureRunner.gd")
const ENEMY_SCRIPT := preload("res://scripts/actors/Enemy.gd")
const RUN_HUD_SCRIPT := preload("res://scripts/ui/RunHUD.gd")
const TITLE_MENU_SCRIPT := preload("res://scripts/ui/TitleMenu.gd")
const PAUSE_MENU_SCRIPT := preload("res://scripts/ui/PauseMenu.gd")
const HEALTH_VIGNETTE_SCRIPT := preload("res://scripts/ui/HealthVignette.gd")
const SCREEN_VIGNETTE_SCRIPT := preload("res://scripts/ui/ScreenVignette.gd")
const PIXEL_GRADE_SCRIPT := preload("res://scripts/ui/PixelGrade.gd")
const VISION_CONE_SCRIPT := preload("res://scripts/fx/VisionCone.gd")
const HEARING_SCRIPT := preload("res://scripts/fx/HearingIndicator.gd")
const ZPIX_FONT := preload("res://assets/art/ui/Zpix.ttf")
const INTERACT_RANGE := 2.2
const MAX_DEPTH := 5

## 摄像机预设：0 完全俯视 / 1 标准 / 2 折中。
## 配合剖面墙（2.4m）把俯角抬到 66° 以上，能看清房间布局，角色也不会被墙挡住。
const CAMERA_MODES := [
	{"name": "完全俯视", "pitch": 74.0, "distance": 15.0, "fov": 36.0},
	{"name": "标准", "pitch": 66.0, "distance": 14.0, "fov": 34.0},
	{"name": "折中", "pitch": 70.0, "distance": 14.5, "fov": 35.0},
]
const PLAYER_WINDOW_RADIUS := 92.0
## 明亮照明（场景黑暗关）与黑暗照明（场景黑暗开）两套固定的环境参数。
## 明亮是默认值，因此即便设置没生效，开局也不会是黑的。
const AMBIENT_BRIGHT := 4.0
const AMBIENT_DARK := 2.2
const EXPOSURE_BRIGHT := 1.35
const EXPOSURE_DARK := 1.2
var debug_visual_mode := false
var debug_mode_badge: Label
var debug_mode_stats: Label
var free_cam_badge: Label
var world_env: WorldEnvironment

enum RunState { ACTIVE, SUCCESS, FAILED }

var run_state := RunState.ACTIVE
var resources := 0
var extracted_resources := 0
var elapsed_time := 0.0
var interaction_hint := ""
var run_hud: CanvasLayer
var _run_ready := false
var depth := 1
var transitioning := false
var shaft_open := false
var reward_remainder := 0.0
var in_base := false
var support_cooldown := 0.0
var support_uses := 0
## 每局限用类支援的计数（后续 OP 技能预留）。
var support_run_uses := 0
var heal_cooldown := 0.0
var camera_mode := 1
var volume := 0.8
## 设置项：关闭场景黑暗、迷雾与视野遮罩，供测试和截图使用。
var bright_test := false
var pause_menu: PauseMenu
var health_vignette: HealthVignette
var screen_vignette: ScreenVignette
var vision_cone: VisionCone
var base_root: Node3D

func open_shaft() -> bool:
	if shaft_open or transitioning or not _run_ready or run_state != RunState.ACTIVE or doll.is_dead or not _near_exit():
		return false
	shaft_open = true
	rig.stop_orbit()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	run_hud.show_shaft()
	return true

func cancel_shaft() -> void:
	if not shaft_open or transitioning:
		return
	shaft_open = false
	run_hud.hide_shaft()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func descend() -> bool:
	if depth >= MAX_DEPTH:
		return false
	if transitioning or not shaft_open or run_state != RunState.ACTIVE or doll.is_dead:
		return false
	transitioning = true
	_run_ready = false
	shaft_open = false
	run_hud.hide_shaft()
	interaction_hint = "正在下潜 · 等待导航同步"
	rig.stop_orbit()
	ImpactFX.clear(self)
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.queue_free()
	_enemy_root.free()
	var next_seed := level.level_seed + 7919
	reticle.wall_level = null
	level.free()
	depth += 1
	# 每层限用类支援在下潜后重置；可恢复类只受冷却限制。
	support_uses = 0
	level = LevelGenerator.new()
	level.name = "Level"
	level.depth = depth
	level.level_seed = next_seed
	add_child(level)
	reticle.wall_level = level
	await _await_nav_sync()
	_place_player()
	doll.aim_point = doll.global_position + Vector3(3, Doll.AIM_HEIGHT, 0)
	_spawn_enemies()
	_run_ready = true
	transitioning = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	get_tree().paused = false
	return true

func extract_from_shaft() -> void:
	if shaft_open and not transitioning and resources > 0 and run_state == RunState.ACTIVE and not doll.is_dead and _near_exit():
		shaft_open = false
		run_hud.hide_shaft()
		finish_run(true)

func grant_resource_reward(base: int) -> int:
	var value := float(base) * pow(1.05, depth - 1) + reward_remainder
	var amount := floori(value + 0.000001)
	reward_remainder = value - amount
	resources += amount
	return amount

@onready var level: LevelGenerator = $Level
@onready var doll: Doll = $Doll
@onready var rig: CameraRig = $CameraRig
@onready var hud: DebugHUD = $HUD
@onready var weapon_hud: WeaponHUD = $WeaponHUD
@onready var motion_blur: MotionBlur = $MotionBlur
@onready var weapon_visual: WeaponVisual = $WeaponVisual

var reticle: AimReticle
var hearing_indicator: HearingIndicator
var _stress_root: Node3D
var _enemy_root: Node3D

var stress_count: int:
	get:
		return 0 if _stress_root == null else _stress_root.get_child_count()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_environment()
	_apply_persistent_upgrades()
	var test_mode := false
	var force_base := false
	for arg in OS.get_cmdline_args():
		var text := String(arg)
		if text.ends_with("_test.gd") or text == "--start-run":
			test_mode = true
		# 基地回归需要真实走一遍「基地 → 行动」流程
		if text.ends_with("base_room_test.gd"):
			force_base = true
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "--base-mode":
			force_base = true
		# 截图工具始终在行动关卡中运行，否则会拍到基地或空场景。
		if text == "--capture" or text == "--start-run":
			test_mode = true
	if force_base:
		test_mode = false
	if test_mode:
		in_base = false
	else:
		in_base = true
		_build_base()
		level.visible = false
		doll.visible = false
		hud.hide()
		weapon_hud.hide()
	rig.set_target(doll)
	doll.camera_rig = rig
	_apply_saved_settings()

	reticle = RETICLE_SCENE.instantiate()
	add_child(reticle)
	reticle.setup(doll)
	reticle.wall_level = level
	if in_base:
		reticle.hide()

	hearing_indicator = HEARING_SCRIPT.new()
	hearing_indicator.name = "HearingIndicator"
	add_child(hearing_indicator)
	hearing_indicator.setup(doll)
	hearing_indicator.visible = not in_base

	vision_cone = VISION_CONE_SCRIPT.new()
	vision_cone.name = "VisionCone"
	add_child(vision_cone)
	vision_cone.setup(doll)
	vision_cone.visible = not in_base

	var pixel_grade := PIXEL_GRADE_SCRIPT.new()
	pixel_grade.name = "PixelGrade"
	add_child(pixel_grade)

	_build_debug_mode_badge()

	health_vignette = HEALTH_VIGNETTE_SCRIPT.new()
	health_vignette.name = "HealthVignette"
	add_child(health_vignette)
	health_vignette.setup(doll)
	health_vignette.visible = not in_base

	screen_vignette = SCREEN_VIGNETTE_SCRIPT.new()
	screen_vignette.name = "ScreenVignette"
	add_child(screen_vignette)
	screen_vignette.visible = not in_base
	_apply_debug_visual_mode()

	hud.setup(doll, rig, self)
	weapon_hud.setup(doll.weapon)
	motion_blur.setup(doll)
	weapon_visual.setup(doll, doll.weapon)
	doll.died.connect(_on_doll_died)
	run_hud = RUN_HUD_SCRIPT.new()
	run_hud.name = "RunHUD"
	add_child(run_hud)
	run_hud.setup(self)
	pause_menu = PAUSE_MENU_SCRIPT.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(self)
	doll.weapon.weapon_switched.connect(_on_weapon_switched)
	var sfx := get_tree().root.get_node_or_null("Sfx")
	if sfx:
		sfx.start_ambient()

	# 基地界面用系统光标，进入行动后再锁定并隐藏
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if in_base else Input.MOUSE_MODE_CONFINED_HIDDEN
	call_deferred("_spawn_enemies_deferred")
	_parse_capture_args()
	if _should_show_menu(test_mode):
		_show_title_menu()

## 启动界面只在正常启动时出现；测试、自动截图和 --no-menu 直接进游戏
func _should_show_menu(test_mode: bool) -> bool:
	if test_mode:
		return false
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "--no-menu" or text == "--capture" or text == "--base-mode":
			return false
	return true

func _show_title_menu() -> void:
	var menu := TITLE_MENU_SCRIPT.new()
	menu.name = "TitleMenu"
	add_child(menu)
	menu.started.connect(_on_menu_started)

func _on_menu_started() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 等导航服务器完成一次地图同步，再生成敌人，否则敌人第一次寻路会失败
func _spawn_enemies_deferred() -> void:
	await _await_nav_sync()
	if in_base:
		_run_ready = false
		return
	_place_player()
	_spawn_enemies()
	_run_ready = true

func _await_nav_sync() -> void:
	var map: RID = level.nav_region.get_navigation_map() if level != null and level.nav_region != null else RID()
	for i in 120:
		await get_tree().physics_frame
		if i >= 1 and map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 \
				and (level == null or level.spawns_snapped):
			return

## 战前准备基地：一间带整备台、武器架、控制台与补给的封闭房间
func _build_base() -> void:
	base_root = Node3D.new()
	base_root.name = "Base"
	add_child(base_root)
	var w := 20.0
	var d := 14.0
	var h := 3.4
	var center := Vector3(2.0, 0.0, 0.0)

	_base_box(base_root, center + Vector3(0, -0.1, 0), Vector3(w, 0.2, d), &"floor")
	_base_box(base_root, center + Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.4), &"wall")
	_base_box(base_root, center + Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.4, h, d), &"wall")
	_base_box(base_root, center + Vector3(w * 0.5, h * 0.5, 0), Vector3(0.4, h, d), &"wall")
	# 入口两侧立柱，正面留空给镜头
	for sx in [-1.0, 1.0]:
		_base_box(base_root, center + Vector3(sx * (w * 0.5 - 1.2), h * 0.5, d * 0.5), Vector3(2.0, h, 0.4), &"wall")

	# 顶灯与地面引导线
	for i in 3:
		_base_box(base_root, Vector3(center.x - 6.0 + float(i) * 6.0, 3.24, 0), Vector3(3.4, 0.06, 0.1), &"amber", false)
		_base_box(base_root, Vector3(center.x - 6.0 + float(i) * 6.0, 0.014, 0), Vector3(1.4, 0.012, 0.08), &"amber", false)

	# 整备台区域：地面警示框标出待命位
	for offset in [Vector3(0, 0, -1.3), Vector3(0, 0, 1.3)]:
		_base_box(base_root, Vector3(4.0, 0.016, 0) + offset, Vector3(2.8, 0.012, 0.08), &"hazard", false)
	for offset in [Vector3(-1.3, 0, 0), Vector3(1.3, 0, 0)]:
		_base_box(base_root, Vector3(4.0, 0.016, 0) + offset, Vector3(0.08, 0.012, 2.8), &"hazard", false)
	_base_box(base_root, Vector3(4.0, 0.008, 0), Vector3(2.4, 0.008, 2.4), &"metal", false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	PropKit.table(base_root, Vector3(4.0, 0, -2.4))
	PropKit.console(base_root, Vector3(-3.4, 0, -5.2), 1.0)
	PropKit.weapon_rack(base_root, Vector3(9.4, 0, -6.4), 1.0)
	PropKit.armor_stand(base_root, Vector3(0.4, 0, -4.4))
	PropKit.armor_stand(base_root, Vector3(1.8, 0, -4.6))
	PropKit.locker(base_root, Vector3(11.0, 0, -3.0), 1.0)
	PropKit.shelf(base_root, Vector3(-6.6, 0, -4.0), 1.0)
	PropKit.crate_stack(base_root, Vector3(7.6, 0, 2.6), rng)
	PropKit.barrel(base_root, Vector3(-7.2, 0, 1.4))
	PropKit.barrel(base_root, Vector3(-6.3, 0, 1.8))
	PropKit.generator(base_root, Vector3(10.4, 0, 3.4))
	PropKit.pipe_run(base_root, Vector3(-8.6, 0, -6.6), Vector3(12.4, 0, -6.6), 2.7)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(4.0, 3.0, 0.0)
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 2.0
	lamp.omni_range = 16.0
	base_root.add_child(lamp)
	var cool := OmniLight3D.new()
	cool.position = Vector3(-4.0, 2.8, -3.0)
	cool.light_color = Color(0.62, 0.84, 1.0)
	cool.light_energy = 1.3
	cool.omni_range = 12.0
	base_root.add_child(cool)
	var warm := OmniLight3D.new()
	warm.position = Vector3(8.0, 2.9, 3.0)
	warm.light_color = Color(1.0, 0.78, 0.52)
	warm.light_energy = 1.6
	warm.omni_range = 12.0
	base_root.add_child(warm)

func _base_box(host: Node3D, pos: Vector3, size: Vector3, key: StringName, solid := true) -> Node3D:
	return PropKit.box(host, pos, size, key, solid)

func _apply_persistent_upgrades() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	var upgrades: Dictionary = progress.data.get("upgrades", {})
	doll.hp_max = 100.0 + float(upgrades.get("hp", 0)) * 15.0
	doll.hp = doll.hp_max
	# 枪械成长：每级基础散布 -6%，封顶 3 级；只影响散布，不改伤害与射速。
	doll.weapon.accuracy_multiplier = pow(0.94, float(upgrades.get("gun", 0)))
	# 视野成长：角度每级 +2.5° 总宽度（清晰区按 2:1 同比例扩展），范围每级 +0.5m。
	var fov_level := float(upgrades.get("fov", 0))
	var sight_level := float(upgrades.get("sight", 0))
	doll.vision_total_half = VisionCone.BASE_TOTAL_HALF + 1.25 * fov_level
	doll.vision_clear_half = minf(
		VisionCone.BASE_CLEAR_HALF + 0.8333333 * fov_level,
		doll.vision_total_half
	)
	doll.vision_range = VisionCone.BASE_RANGE + 0.5 * sight_level
	if vision_cone:
		vision_cone.apply(doll.vision_clear_half, doll.vision_total_half, doll.vision_range)

## 支援次数 = 基础 2 次 + 支援协议等级；单次伤害与冷却不随等级变化。
func support_max_uses() -> int:
	var progress := get_node_or_null("/root/Progress")
	var level := int(progress.data.get("upgrades", {}).get("support", 0)) if progress else 0
	return 2 + level

## 读取存档中的音量、动态模糊与摄像机模式并立即应用。
func _apply_saved_settings() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		_apply_camera_for_context()
		return
	apply_volume(float(progress.data.get("volume", 0.8)))
	motion_blur.set_enabled(bool(progress.data.get("motion_blur", true)))
	camera_mode = clampi(int(progress.data.get("camera_mode", 1)), 0, CAMERA_MODES.size() - 1)
	bright_test = bool(progress.data.get("bright_test", true))
	_apply_camera_for_context()
	_apply_debug_visual_mode()

func apply_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))

func apply_camera_mode(index: int) -> void:
	camera_mode = clampi(index, 0, CAMERA_MODES.size() - 1)
	_apply_camera_for_context()

## 设置面板调用：开=正常黑暗，关=测试照明。
func apply_bright_test(enabled: bool) -> void:
	bright_test = enabled
	_apply_debug_visual_mode()

## 基地空间较大，使用同一预设时额外拉远一点，方便看清整备区。
## 每次都从预设值重算，避免反复进出基地把距离越加越远。
func _apply_camera_for_context() -> void:
	var mode: Dictionary = CAMERA_MODES[camera_mode]
	var dist := float(mode["distance"])
	var field_of_view := float(mode["fov"])
	if in_base:
		dist += 2.5
		field_of_view += 2.0
	rig.apply_preset(float(mode["pitch"]), dist, field_of_view)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		var grade := get_node_or_null("PixelGrade")
		if grade != null:
			grade.visible = not grade.visible
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		debug_visual_mode = not debug_visual_mode
		_apply_debug_visual_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_QUOTELEFT:
		toggle_free_camera()
		get_viewport().set_input_as_handled()
		return
	if pause_menu == null or not event.is_action_pressed("ui_cancel"): 
		return
	if pause_menu.visible or get_node_or_null("TitleMenu") != null:
		return
	if shaft_open or transitioning or run_state != RunState.ACTIVE:
		return
	pause_menu.open()
	get_viewport().set_input_as_handled()

func start_expedition() -> void:
	if not in_base:
		return
	get_tree().paused = false
	in_base = false
	_apply_camera_for_context()
	support_uses = 0
	support_run_uses = 0
	heal_cooldown = 0.0
	support_cooldown = 0.0
	if base_root:
		_set_base_collision(false)
	if _enemy_root:
		_enemy_root.free()
		_enemy_root = null
	if is_instance_valid(level):
		level.free()
	level = LevelGenerator.new()
	level.name = "Level"
	level.depth = 1
	level.level_seed = randi()
	add_child(level)
	reticle.wall_level = level
	level.visible = true
	doll.visible = true
	doll.respawn()
	run_state = RunState.ACTIVE
	_apply_debug_visual_mode()
	resources = 0
	extracted_resources = 0
	elapsed_time = 0.0
	depth = 1
	reward_remainder = 0.0
	shaft_open = false
	_run_ready = false
	doll.weapon.apply_loadout(true)
	call_deferred("_spawn_enemies_deferred")
	run_hud.show_expedition()
	reticle.show()
	if hearing_indicator:
		hearing_indicator.visible = true
	if vision_cone:
		vision_cone.visible = true
	if health_vignette:
		health_vignette.visible = true
	if screen_vignette:
		screen_vignette.visible = true
	hud.show()
	weapon_hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func return_to_base() -> void:
	in_base = true
	_apply_camera_for_context()
	_run_ready = false
	_clear_interact_highlights()
	if _enemy_root:
		_enemy_root.free()
		_enemy_root = null
	level.visible = false
	doll.visible = false
	reticle.hide()
	if hearing_indicator:
		hearing_indicator.visible = false
	if vision_cone:
		vision_cone.visible = false
	if health_vignette:
		health_vignette.visible = false
	if screen_vignette:
		screen_vignette.visible = false
	hud.hide()
	weapon_hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if base_root:
		_set_base_collision(true)
	run_hud.show_base()
	_apply_debug_visual_mode()

## 基地区域只在基地内可见且有碰撞；进入行动时必须关掉碰撞，
## 否则基地墙体与摆件会留在关卡里变成摸不到的空气墙。
func _set_base_collision(on: bool) -> void:
	if base_root == null:
		return
	base_root.visible = on
	_toggle_collision(base_root, on)

func _toggle_collision(node: Node, on: bool) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 1 if on else 0
	for child in node.get_children():
		_toggle_collision(child, on)

## 玩家放到关卡给的出生点
func _place_player() -> void:
	doll.global_position = level.player_spawn
	doll.velocity = Vector3.ZERO
	rig.global_position = Vector3(level.player_spawn.x, 0.0, level.player_spawn.z)
	rig.rotation.y = 0.0

## 按关卡生成器给的房间出生点撒敌人，类型按距离远近递进
func _spawn_enemies() -> void:
	_enemy_root = Node3D.new()
	_enemy_root.name = "Enemies"
	add_child(_enemy_root)
	var roster := [&"rifleman", &"rusher", &"rifleman", &"heavy", &"rusher", &"rifleman"]
	var pts := level.enemy_spawns
	for i in pts.size():
		spawn_enemy(level.enemy_kinds[i] if i < level.enemy_kinds.size() else roster[i % roster.size()], pts[i])
	print("[Main] spawned %d enemies" % pts.size())

func spawn_enemy(id: StringName, pos: Vector3) -> Enemy:
	var e: Enemy = ENEMY_SCRIPT.new()
	e.position = pos
	_enemy_root.add_child(e)
	e.setup(doll, id)
	e.max_hp *= pow(1.1, depth - 1)
	e.hp = e.max_hp
	e.damage *= pow(1.05, depth - 1)
	return e

func _on_weapon_switched(_id: StringName) -> void:
	weapon_visual.reload_visual()

func _parse_capture_args() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var mode := "beauty"
	var frames := 24
	for i in args.size():
		match args[i]:
			"--capture":
				if i + 1 < args.size():
					path = args[i + 1]
			"--mode":
				if i + 1 < args.size():
					mode = args[i + 1]
			"--frames":
				if i + 1 < args.size():
					frames = int(args[i + 1])
	if path == "":
		return
	var cr = CAPTURE_SCRIPT.new()
	cr.setup(self, path, mode, frames)
	add_child(cr)

func _build_debug_mode_badge() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugVisualMode"
	layer.layer = 30
	add_child(layer)
	debug_mode_badge = Label.new()
	debug_mode_badge.position = Vector2(16, 16)
	debug_mode_badge.add_theme_font_size_override("font_size", 16)
	debug_mode_badge.add_theme_color_override("font_color", Color(0.7, 1.0, 0.72))
	debug_mode_badge.text = "DEBUG VISUAL | F7 to toggle"
	debug_mode_badge.visible = false
	layer.add_child(debug_mode_badge)
	debug_mode_stats = Label.new()
	debug_mode_stats.position = Vector2(16, 40)
	debug_mode_stats.add_theme_font_size_override("font_size", 13)
	debug_mode_stats.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	debug_mode_stats.visible = false
	layer.add_child(debug_mode_stats)
	free_cam_badge = Label.new()
	free_cam_badge.position = Vector2(16, 64)
	free_cam_badge.add_theme_font_size_override("font_size", 14)
	free_cam_badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52))
	free_cam_badge.visible = false
	layer.add_child(free_cam_badge)

## `~` 或设置菜单：解锁预设限制，中键拖动改水平角与俯角，滚轮缩放，退出时回到预设。
## 不用 F8：Godot 编辑器里 F8 是「停止」快捷键，内嵌运行时会直接把游戏进程杀掉。
func toggle_free_camera() -> void:
	if rig == null:
		return
	var on := not rig.free_camera_enabled
	rig.set_free_camera(on)
	if not on:
		rig.reset_zoom()
		_apply_camera_for_context()
	if free_cam_badge:
		free_cam_badge.visible = on

func _apply_debug_visual_mode() -> void:
	var bright := debug_visual_mode or bright_test
	if debug_mode_badge:
		debug_mode_badge.visible = debug_visual_mode
	if debug_mode_stats:
		debug_mode_stats.visible = debug_visual_mode
	if vision_cone:
		vision_cone.visible = not in_base and not bright
	if screen_vignette:
		screen_vignette.visible = not in_base and not bright
	if health_vignette:
		health_vignette.visible = not in_base and not bright
	# 2.5D 调色是画面主体风格，只随 F7 调试照明关闭；关掉场景黑暗也要保留。
	var grade := get_node_or_null("PixelGrade")
	if grade:
		grade.visible = not debug_visual_mode
	# 直接持有引用，避免节点改名/重建后按名字查找失败导致亮度设置静默失效。
	var world := world_env if is_instance_valid(world_env) else null
	if world == null:
		world = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		world.environment.fog_enabled = not bright
		world.environment.ambient_light_energy = AMBIENT_BRIGHT if bright else AMBIENT_DARK
		world.environment.tonemap_exposure = EXPOSURE_BRIGHT if bright else EXPOSURE_DARK
		# 提亮暗部：比继续堆环境光更不容易把地面洗白。
		world.environment.adjustment_enabled = bright
		world.environment.adjustment_brightness = 1.18
		world.environment.adjustment_contrast = 1.02
	if level:
		level.visible = not in_base
	if doll:
		doll.visible = not in_base

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.008, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.54, 0.64)
	env.ambient_light_energy = AMBIENT_BRIGHT
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = EXPOSURE_BRIGHT

	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.01
	env.glow_hdr_threshold = 1.0

	env.ssao_enabled = true
	env.ssao_radius = 1.3
	env.ssao_intensity = 0.45

	env.fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.18
	env.adjustment_contrast = 1.02
	env.fog_light_color = Color(0.10, 0.13, 0.17)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
	env.fog_aerial_perspective = 0.08

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.94

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	world_env = we
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54.0, -36.0, 0.0)
	sun.light_color = Color(0.62, 0.72, 0.92)
	sun.light_energy = 0.55
	sun.light_specular = 0.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38.0, 135.0, 0.0)
	fill.light_color = Color(0.88, 0.74, 0.58)
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	add_child(fill)

func _process(dt: float) -> void:
	if free_cam_badge and free_cam_badge.visible and rig:
		free_cam_badge.text = "自由镜头 // ~ 退出 · 中键拖动改角度 · 滚轮缩放 | 俯角 %.0f° 距离 %.1fm" % [
			rig.pitch_deg, rig.distance * rig.zoom_scale]
	if debug_visual_mode and debug_mode_stats:
		var enemy_count := get_tree().get_nodes_in_group("enemies").size()
		var env_info := "env=none"
		if is_instance_valid(world_env) and world_env.environment:
			var e := world_env.environment
			env_info = "amb=%.2f exp=%.2f fog=%s" % [e.ambient_light_energy, e.tonemap_exposure, str(e.fog_enabled)]
		debug_mode_stats.text = "FPS %d | Depth %d | Player %s | Enemies %d | %s | bright=%s" % [Engine.get_frames_per_second(), depth, str(doll.global_position.snapped(Vector3.ONE * 0.1)), enemy_count, env_info, str(bright_test)]
	if support_cooldown > 0.0:
		support_cooldown = maxf(0.0, support_cooldown - dt)
	if heal_cooldown > 0.0:
		heal_cooldown = maxf(0.0, heal_cooldown - dt)
	if in_base or run_state != RunState.ACTIVE:
		return
	if _run_ready:
		elapsed_time += dt
	if Input.is_action_just_pressed("support"):
		use_support()
	if Input.is_action_just_pressed("heal"):
		use_heal_support()

	if Input.is_action_just_pressed("debug_cursor"):
		rig.stop_orbit()
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if Input.is_action_just_pressed("debug_stress"):
		set_stress(_stress_root == null)

	if Input.is_action_just_pressed("debug_reset"):
		_reset_doll()

	if Input.is_action_just_pressed("debug_capture"):
		_manual_screenshot()

func _reset_doll() -> void:
	if run_state != RunState.ACTIVE:
		return
	doll.debug_clear()
	doll.respawn()
	doll.rotation.y = 0.0

func _physics_process(_dt: float) -> void:
	if not _run_ready or run_state != RunState.ACTIVE:
		return
	level.explore(doll.global_position)
	_update_player_wall_window()
	if Input.is_action_just_pressed("interact"):
		try_interact()
	else:
		interaction_hint = _get_interaction_hint()
	_update_interact_highlights()

## 玩家被墙挡住时，在玩家屏幕位置开一个小透窗；立绘本身已置顶，不会再有硬裁切。
func _update_player_wall_window() -> void:
	if level == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if in_base or debug_visual_mode or run_state != RunState.ACTIVE or doll.is_dead or get_tree().paused:
		level.update_player_window(Vector2.ZERO, viewport_size, PLAYER_WINDOW_RADIUS, false)
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		level.update_player_window(Vector2.ZERO, viewport_size, PLAYER_WINDOW_RADIUS, false)
		return
	var target := doll.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, target, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var blocked := not hit.is_empty()
	var center := cam.unproject_position(doll.global_position + Vector3.UP * 1.25)
	level.update_player_window(center, viewport_size, PLAYER_WINDOW_RADIUS, blocked)

## 靠近可互动物品时显示细白描边；离开或结算时隐藏。
func _update_interact_highlights() -> void:
	if level == null:
		return
	var nearest := _nearest_container()
	for container in level.search_containers:
		var highlight := container.get_node_or_null("Highlight")
		if highlight:
			highlight.visible = container == nearest
	if level.exit_highlight:
		level.exit_highlight.visible = _near_exit()

func _clear_interact_highlights() -> void:
	if level == null:
		return
	for container in level.search_containers:
		var highlight := container.get_node_or_null("Highlight")
		if highlight:
			highlight.visible = false
	if level.exit_highlight:
		level.exit_highlight.visible = false
	level.update_player_window(Vector2.ZERO, get_viewport().get_visible_rect().size, PLAYER_WINDOW_RADIUS, false)

func _can_reach(point: Vector3, target: CollisionObject3D = null) -> bool:
	var from := doll.global_position + Vector3.UP * 0.8
	if from.distance_to(point) > INTERACT_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, point, 1, [doll.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (target != null and hit.get("collider") == target)

func _near_exit() -> bool:
	return _can_reach(level.to_global(level.exit_position) + Vector3.UP * 0.8)

## 最近的可开启门：玩家必须主动按 E 开门；敌人由 AutoDoor 自行开门。
func _nearest_door() -> AutoDoor:
	if level == null:
		return null
	var nearest: AutoDoor
	var distance := INTERACT_RANGE
	for node in level.doors:
		var door := node as AutoDoor
		if door == null or door.is_open:
			continue
		var d := doll.global_position.distance_to(door.global_position)
		if d <= distance:
			distance = d
			nearest = door
	return nearest

func _nearest_container() -> StaticBody3D:
	var nearest: StaticBody3D
	var distance := INF
	for container in level.search_containers:
		var point := container.global_position
		var d := doll.global_position.distance_squared_to(point)
		if d < distance and _can_reach(point, container):
			distance = d
			nearest = container
	return nearest

func _get_interaction_hint() -> String:
	if _near_exit():
		return "E 竖井：撤离 / 下潜 / 取消"
	if _nearest_door() != null:
		return "E 开门 · 门后房间随即探明"
	var container := _nearest_container()
	if container != null:
		if container.get_meta("searched", false):
			return "已搜索 · 此箱为空"
		var hint := "E 搜索 · %s · 基础资源 +%d" % [container.get_meta("loot", "物资"), container.get_meta("reward", 1)]
		var effect: Dictionary = container.get_meta("loot_effect", {})
		match effect.get("type", &"resource"):
			&"ammo":
				var ammo := doll.weapon.current_ammo()
				hint += "\n当前武器 %s 备弹最多 +%d（上限 %d）" % [ammo.display_name, ceili(ammo.reserve_max * 0.5), ammo.reserve_max]
			&"repair":
				hint += "\n即时维修最多 +%.0f HP（不超过生命上限）" % float(effect["amount"])
		return hint
	return "靠近房间物资箱按 E 搜索，再前往走廊尽头撤离"

func try_interact() -> bool:
	if not _run_ready or run_state != RunState.ACTIVE or doll.is_dead or get_tree().paused:
		return false
	if _near_exit():
		return open_shaft()
	var door := _nearest_door()
	if door != null and door.set_open(true):
		return true
	var container := _nearest_container()
	if container == null or not level.search_container(container):
		return false
	var amount := grant_resource_reward(int(container.get_meta("reward", 1)))
	var feedback := "%s · 资源 +%d" % [container.get_meta("loot", "物资"), amount]
	var effect: Dictionary = container.get_meta("loot_effect", {})
	match effect.get("type", &"resource"):
		&"ammo":
			var supplied := doll.weapon.supply_reserve()
			feedback += " · %s 备弹 +%d%s" % [doll.weapon.current_ammo().display_name, supplied, "（已满）" if supplied == 0 else ""]
		&"repair":
			var restored := doll.repair(float(effect["amount"]))
			feedback += " · 维修 +%s HP%s" % [str(restored).trim_suffix(".0"), "（已满）" if restored == 0.0 else ""]
	run_hud.show_loot(feedback)
	var popup := Label3D.new()
	popup.text = feedback
	popup.position = container.position + Vector3.UP * 1.5
	popup.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	popup.font = ZPIX_FONT
	popup.font_size = 44
	popup.pixel_size = 0.004
	level.add_child(popup)
	var tween := popup.create_tween()
	tween.tween_property(popup, "position:y", popup.position.y + 0.6, 1.8)
	tween.tween_callback(popup.queue_free)
	interaction_hint = _get_interaction_hint()
	return true

func use_support() -> bool:
	var protocol := SupportDB.protocol(&"sniper")
	var max_uses := support_max_uses()
	if in_base or run_state != RunState.ACTIVE or doll.is_dead or get_tree().paused or not _run_ready or support_cooldown > 0.0 or support_uses >= max_uses:
		return false
	var target: Enemy
	var best := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is Enemy and not node.is_dead:
			var d := doll.global_position.distance_squared_to(node.global_position)
			if d < best:
				best = d
				target = node
	if target == null:
		return false
	var hit_damage := float(protocol["damage"])
	target.on_hit(target.global_position + Vector3.UP, Vector3.UP, hit_damage, 10.0)
	support_uses += 1
	support_cooldown = float(protocol["cooldown"])
	run_hud.show_loot("X 狙击支援命中 · 伤害 %d · 剩余 %d" % [int(hit_damage), max_uses - support_uses])
	return true

## 可恢复类支援：没有次数上限，只看冷却；满血时不消耗冷却。
func use_heal_support() -> bool:
	var protocol := SupportDB.protocol(&"self_heal")
	if in_base or run_state != RunState.ACTIVE or doll.is_dead or get_tree().paused or not _run_ready or heal_cooldown > 0.0:
		return false
	var restored := doll.repair(float(protocol["heal"]))
	if restored <= 0.0:
		return false
	heal_cooldown = float(protocol["cooldown"])
	run_hud.show_loot("H 自主恢复 · 维修 +%s HP" % str(restored).trim_suffix(".0"))
	return true

## 供 HUD/后续技能统一查询剩余次数：可恢复类只返回是否可用。
func support_remaining(scope: int) -> int:
	match scope:
		SupportDB.Scope.RECHARGE:
			return 0 if heal_cooldown > 0.0 else 1
		SupportDB.Scope.PER_LEVEL:
			return maxi(0, support_max_uses() - support_uses)
		SupportDB.Scope.PER_RUN:
			return 0 if support_run_uses > 0 else 1
	return 0

func _on_doll_died() -> void:
	finish_run(false)

func finish_run(success: bool) -> void:
	if run_state != RunState.ACTIVE:
		return
	if success and (not _run_ready or doll.is_dead or resources < 1 or not _near_exit()):
		return
	run_state = RunState.SUCCESS if success else RunState.FAILED
	extracted_resources = resources if success else 0
	if success:
		var progress := get_node_or_null("/root/Progress")
		if progress:
			progress.add_resources(extracted_resources)
			progress.add_xp(extracted_resources * 5 + depth - 1)
	doll.velocity = Vector3.ZERO
	interaction_hint = ""
	_clear_interact_highlights()
	reticle.hide()
	if hearing_indicator:
		hearing_indicator.visible = false
	if vision_cone:
		vision_cone.visible = false
	if health_vignette:
		health_vignette.visible = false
	if screen_vignette:
		screen_vignette.visible = false
	hud.hide()
	weapon_hud.hide()
	run_hud.show_result(success, resources, extracted_resources, elapsed_time)
	rig.stop_orbit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

## 统一的生命周期入口：同一个 Main 实例内完成「结算 → 基地 → 新一局」，不重载场景。
## 结算后第一次调用回到基地并保留结算信息；在基地再次调用直接开始新一局。
func restart_run() -> void:
	rig.stop_orbit()
	ImpactFX.clear(self)
	if in_base:
		start_expedition()
		return
	return_to_base()
	get_tree().paused = true

func set_stress(on: bool) -> void:
	if on and _stress_root == null:
		_spawn_stress()
	elif not on and _stress_root != null:
		_stress_root.queue_free()
		_stress_root = null

func _spawn_stress() -> void:
	_stress_root = Node3D.new()
	_stress_root.name = "StressDummies"
	add_child(_stress_root)

	var frames: SpriteFrames = doll.billboard.body.sprite_frames
	for i in 20:
		var s := AnimatedSprite3D.new()
		s.sprite_frames = frames
		s.billboard = 2
		s.alpha_cut = 1
		s.texture_filter = 3
		s.cast_shadow = 0
		s.shaded = false
		s.pixel_size = 1.70 / 192.0
		s.modulate = Color(1.06, 1.06, 1.08)
		var col := i % 5
		var row := int(i / 5)
		s.position = Vector3(-16.0 + col * 0.9, 0.78, -1.8 + row * 1.2)
		s.play("idle_%d" % (i % 8))
		s.speed_scale = 0.75 + float(i % 5) * 0.12
		_stress_root.add_child(s)

	# 压力测试时把角色放到走廊中央看得见的地方
	doll.debug_clear()
	doll.global_position = Vector3(-19, 0.02, 0.0)

func _manual_screenshot() -> void:
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("m0_%d.png" % Time.get_ticks_msec())
	_capture_to(path)

func _capture_to(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[screenshot] %s (err=%s)" % [path, err])
