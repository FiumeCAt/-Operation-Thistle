extends Node2D

## 俯视 2D 主流程：程序化关卡 + 敌人 + 搜刮 + 撤离。
## 玩法闭环：从走廊左端出发 → 进房间清敌 / 搜补给 → 带着资源到走廊尽头撤离。

enum RunState { ACTIVE, SUCCESS, FAILED }

## 行动期核心事件总线：供 UI、统计、音频或后续拆分出的子系统只读订阅。
signal shot_fired(weapon_id: StringName, ammo_id: StringName, pellet_count: int)
signal hit_resolved(target: Node, damage: float, killed: bool, material: String)
signal loot_gained(item_id: StringName, amount: int, is_advanced: bool)
signal wave_changed(wave: int, state: String)
signal run_finished(success: bool, stats: Dictionary)

@onready var doll: Doll2D = $World2D/SortLayer/Doll2D
@onready var sort_layer: Node2D = $World2D/SortLayer
@onready var fx_layer: Node2D = $World2D/FXLayer
@onready var level: Level2D = $Level2D
@onready var camera: Camera2D = $Camera2D
@onready var canvas_modulate: CanvasModulate = $World2D/CanvasModulate
@onready var debug_overlay: CanvasLayer = $DebugOverlay2D
@onready var debug_label: Label = $DebugOverlay2D/Panel/Label
@onready var hud: RunHUD2D = $HUD2D
@onready var reticle: AimReticle2D = $Reticle2D

## 编辑器可调场景导出属性与配置资源（未挂载时全部平滑回退下方 const 默认值）。
@export_group("Scene & Config")
## 视口背景清屏色（替代硬编码 Color("08090a")，可在 Main2D 检查器直接调整）。
@export var clear_color: Color = Color("08090a")
## 镜头手感与前探配置资源（resources/config/camera_feel_default.tres）。
@export var camera_config: Resource
## 后坐力、震屏与受击反馈配置资源（resources/config/combat_feel_default.tres）。
@export var combat_config: Resource
## 视野光照强度与色温配置资源（resources/config/vision_lighting_default.tres）。
@export var vision_config: Resource

const ZOOM := 0.95
## 100% 现在对应旧版 50% 的镜头缩放，基础视野翻倍；镜内放大由 ScopeSight2D 独立处理。
## 镜头上移，让玩家在画面里偏下，前方视野更大。
const CAMERA_LIFT := 44.0
const ADS_ZOOM_SPEED := 6.0
const SPREAD_MODEL := preload("res://scripts/combat/SpreadModel.gd")
## 开镜散布收紧系数改为按弹种配置（AmmoData.ads_spread_mul），此处不再全局固定。
## 连发累积：开镜（ADS）时每发增长更慢；换弹/切枪期间回落更快（单一来源：SpreadModel）。
const BURST_ADS_GROWTH_MUL := SPREAD_MODEL.BURST_ADS_GROWTH_MUL
const BURST_RECOVERY_BUSY_MUL := SPREAD_MODEL.BURST_RECOVERY_BUSY_MUL
## 瞄准基础前探距离（适配 64 px/m 与 0.95 广角缩放，约 5.3 米基础前探；高倍镜按倍率延伸）。
const ADS_LOOK_AHEAD := 340.0
const ADS_LOOK_SMOOTH := 10.0
## 高倍镜开镜时允许的最大半屏偏移比例：保证横纵双向拉满前探时角色始终留在屏内（纵向留出头顶与顶栏空间）。
const SCOPE_KEEP_PLAYER_RATIO_X := 0.88
const SCOPE_KEEP_PLAYER_RATIO_Y := 0.82
## 后坐力/散布/聚合窗口常量统一收口至 CombatSystem2D，保留兼容别名。
const RECOIL_LIMIT := COMBAT_SYSTEM.RECOIL_LIMIT
const RECOIL_RECOVER := COMBAT_SYSTEM.RECOIL_RECOVER
const RECOIL_ADS_MUL := COMBAT_SYSTEM.RECOIL_ADS_MUL
const RECOIL_CAM_SCALE := COMBAT_SYSTEM.RECOIL_CAM_SCALE
const RECOIL_CAM_LIMIT := COMBAT_SYSTEM.RECOIL_CAM_LIMIT
const RECOIL_BUILD_GAIN := COMBAT_SYSTEM.RECOIL_BUILD_GAIN
const FIRST_SHOT_WINDOW := COMBAT_SYSTEM.FIRST_SHOT_WINDOW
const BULLET_HIT_BATCH_WINDOW := COMBAT_SYSTEM.BULLET_HIT_BATCH_WINDOW
const RECOIL_ROLL_SCALE := COMBAT_SYSTEM.RECOIL_ROLL_SCALE
const RECOIL_ROLL_LIMIT := COMBAT_SYSTEM.RECOIL_ROLL_LIMIT
## 整体视角缩放：20%–200%，每格 10%；100% 为默认视野。
const VIEW_ZOOM_MIN := 20.0
const VIEW_ZOOM_MAX := 200.0
const VIEW_ZOOM_STEP := 10.0
const VIEW_ZOOM_LERP := 260.0
const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
## 新脚本用 preload 引用，避免依赖编辑器生成的全局类缓存。
const VISION_FOG := preload("res://scripts/fx/VisionFog2D.gd")
const LASER_SIGHT := preload("res://scripts/fx/LaserSight2D.gd")
const SCOPE_SIGHT := preload("res://scripts/fx/ScopeSight2D.gd")
const HEARING_INDICATOR := preload("res://scripts/fx/HearingIndicator2D.gd")
const LOOT_SYSTEM := preload("res://scripts/systems/LootSystem2D.gd")
const WAVE_SYSTEM := preload("res://scripts/systems/WaveSystem2D.gd")
const INTERACTION_SYSTEM := preload("res://scripts/systems/InteractionSystem2D.gd")
const COMBAT_SYSTEM := preload("res://scripts/systems/CombatSystem2D.gd")
const FEEDBACK_SYSTEM := preload("res://scripts/systems/FeedbackSystem2D.gd")
## 枪口偏移/震动缩放常量统一收口至 FeedbackSystem2D，保留兼容别名。
const MUZZLE_FX_GROUND := FEEDBACK_SYSTEM.MUZZLE_FX_GROUND
const SHAKE_SCALE_BASE := FEEDBACK_SYSTEM.SHAKE_SCALE_BASE
## 战利品/掉落常量统一收口至 LootSystem2D，此处保留只读别名供旧测试兼容引用。
const BASIC_DROP_TABLE := LOOT_SYSTEM.BASIC_DROP_TABLE
const CONTAINER_LOOT_MIN := LOOT_SYSTEM.CONTAINER_LOOT_MIN
const CONTAINER_LOOT_MAX := LOOT_SYSTEM.CONTAINER_LOOT_MAX
const CONTAINER_SECONDARY_CHANCE := LOOT_SYSTEM.CONTAINER_SECONDARY_CHANCE
const CONTAINER_ADVANCED_CHANCE := LOOT_SYSTEM.CONTAINER_ADVANCED_CHANCE
const ENEMY_SECONDARY_CHANCE := LOOT_SYSTEM.ENEMY_SECONDARY_CHANCE
## 全项目统一世界距离标尺：1 格 = 1 米 = 64 px（来自 GameUnits）。
const WORLD_PER_METER := UNITS.PIXELS_PER_METER
const INTERACT_RADIUS := INTERACTION_SYSTEM.INTERACT_RADIUS
const EXIT_RADIUS := INTERACTION_SYSTEM.EXIT_RADIUS
const SHOT_ORIGIN_OFFSET := Vector2(0, -8)
const HINT_DEFAULT := "WASD 移动 · SPACE 翻滚 · 左键开火 · 右键瞄准 · Q 切弹 · B 切模式 · R 换弹 · X 收枪 · TAB 背包 · E 交互"

## 结算标签由 RunHUD2D 构建，测试按名字读取。
var result_label: Label

var debug_visual_mode := false
var mouse_aim_enabled := true
var run_state := RunState.ACTIVE
## 本局带出的战利品：三种基础资源 + 稀有进阶资源；撤离时统一入库存。
var loot := {"electronics": 0, "energy": 0, "parts": 0}
var advanced_loot := {}
## 战利品总件数：撤离门槛与 XP/信用点结算沿用这个数。
var resources := 0
## 本局战斗统计：击杀由 Main2D 维护，射击/命中/伤害由 CombatSystem2D 维护并转发。
var kills := 0
var combat_system: CombatSystem2D = COMBAT_SYSTEM.new()
var shots_fired: int:
	get: return combat_system.shots_fired
	set(v): combat_system.shots_fired = v
var shots_hit: int:
	get: return combat_system.shots_hit
	set(v): combat_system.shots_hit = v
var damage_dealt: float:
	get: return combat_system.damage_dealt
	set(v): combat_system.damage_dealt = v
var run_elapsed := 0.0
var _bgm_combat_hold := 0.0
var _bgm_check_t := 0.0
var enemies: Array[Enemy2D] = []
## 2D 天赋：枪械精度倍率与撤离资源倍率，在行动开始时从 Progress 读取。
var talent_accuracy := 1.0
var talent_scavenge := 1.0
## 打击反馈子系统（震屏/顿帧/红屏/枪口特效/预热/音效）及设置项兼容转发。
var feedback_system: FeedbackSystem2D = FEEDBACK_SYSTEM.new()
var screen_shake: bool:
	get: return feedback_system.screen_shake
	set(v): feedback_system.screen_shake = v
var hitstop_enabled: bool:
	get: return feedback_system.hitstop_enabled
	set(v): feedback_system.hitstop_enabled = v
var shake_scale: float:
	get: return feedback_system.shake_scale
	set(v): feedback_system.shake_scale = v
var _shake: float:
	get: return feedback_system.shake
	set(v): feedback_system.shake = v
## 设置项：命中特写层级 2 完整 / 1 减弱 / 0 关闭。
var hit_fx_level := 1
## 设置项：弹道线条（枪口到弹丸的长曳光线）默认开启；关闭后仅隐藏长线，弹丸实体与飞行/结算不变。
var bullet_trail_enabled := true

## 浪潮模式常量统一收口至 WaveSystem2D，保留别名供测试兼容引用。
const WAVES_BASE_COUNT := WAVE_SYSTEM.BASE_COUNT
const WAVES_STAT_STEP := WAVE_SYSTEM.STAT_STEP
const WAVES_INTERMISSION := WAVE_SYSTEM.INTERMISSION
const WAVES_SPAWN_INTERVAL := WAVE_SYSTEM.SPAWN_INTERVAL
const WAVES_START_DELAY := WAVE_SYSTEM.START_DELAY
const WAVES_EXTRACT_EVERY := WAVE_SYSTEM.EXTRACT_EVERY
const WAVES_EARLY_RATIO := WAVE_SYSTEM.EARLY_RATIO
const WAVES_EXTRACT_RATIO := WAVE_SYSTEM.EXTRACT_RATIO
const WAVES_LOOT_STEP := WAVE_SYSTEM.LOOT_STEP

var _label_timer := 0.0
var interaction_system: InteractionSystem2D = INTERACTION_SYSTEM.new()
var _ads_t := 0.0
## 开镜期间是否由本脚本临时关闭了镜头位置平滑；松开瞄准后只恢复自己关掉的那一次。
var _ads_smoothing_off := false
## 高倍镜方案 B（增量外推前探）：记录按下右键瞬间光标的屏幕位置作为前探零点，
## 不篡改/拉扯系统鼠标；开镜瞬间主镜头围绕光标位置平滑拉远（zoom-to-cursor 零偏移），
## 仅在继续向外推鼠标时平滑叠加额外前探。
var _camera_bounds := Rect2()
var _scope_ads_active := false
var _scope_entry_mouse := Vector2.ZERO
var _scope_entry_cam_bias := Vector2.ZERO
var _scope_cam_offset := Vector2.ZERO
## 战斗/散布/后坐力状态转发至 combat_system（保持测试读写字段兼容）。
var _burst_spread: float:
	get: return combat_system.burst_spread
	set(v): combat_system.burst_spread = v
var _recoil_offset: Vector2:
	get: return combat_system.recoil_offset
	set(v): combat_system.recoil_offset = v
var _recoil_cam: Vector2:
	get: return combat_system.recoil_cam
	set(v): combat_system.recoil_cam = v
var _recoil_roll: float:
	get: return combat_system.recoil_roll
	set(v): combat_system.recoil_roll = v
var last_shot_origin: Vector2:
	get: return combat_system.last_shot_origin
	set(v): combat_system.last_shot_origin = v
var last_shot_dir: Vector2:
	get: return combat_system.last_shot_dir
	set(v): combat_system.last_shot_dir = v
var last_pellet_dirs: Array[Vector2]:
	get: return combat_system.last_pellet_dirs
	set(v): combat_system.last_pellet_dirs = v
var last_pellet_spread: float:
	get: return combat_system.last_pellet_spread
	set(v): combat_system.last_pellet_spread = v
var _shot_clock: float:
	get: return combat_system.shot_clock
	set(v): combat_system.shot_clock = v
var _last_shot_time: float:
	get: return combat_system.last_shot_time
	set(v): combat_system.last_shot_time = v
var _burst_weapon: StringName:
	get: return combat_system.burst_weapon
	set(v): combat_system.burst_weapon = v
## 整体视角缩放倍率与平滑值；滚轮改前者，镜头跟后者，避免跳变。
var view_zoom_pct := 100.0
var _view_zoom_visual := 100.0
## 基准镜头缩放与环境色：启动时从 Main2D.tscn 的 Camera2D.zoom / CanvasModulate.color 读取，不再硬编码覆盖。
var _base_zoom := ZOOM
var _ambient_color := Color(0.40, 0.43, 0.48, 1.0)
## 倍镜接口：倍率 >1 时只在 ADS 期间生效；默认 1.0 表示当前无倍镜。
var scope_magnification := 1.0
var _ads_look := Vector2.ZERO
## 2D 游戏内 ESC 菜单，层高于 HUD 和调试层。
var pause_menu: PauseMenu2D
var map_overlay: MapOverlay2D
var backpack: BackpackMenu2D
var loot_system: LootSystem2D
## 玩家分层视野与视野迷雾：清晰主锥 / 相对暗外圈 / 近身黑暗视野。
var vision: VisionFog2D
## 下挂激光：装备后从枪口绘制绿色光束与命中点光斑。
var laser_sight: LaserSight2D
## 声纹指示：视野外移动敌人的方位弧。
var hearing: HearingIndicator2D
## 高倍率瞄具：ADS 时在准心位置显示圆形镜内放大视野与对应准心。
var scope_sight: ScopeSight2D
## 浪潮模式子系统与对外兼容属性转发（单一状态源在 wave_system 内）。
var wave_system: WaveSystem2D = WAVE_SYSTEM.new()
var waves_mode: bool:
	get: return wave_system.waves_mode
	set(v): wave_system.waves_mode = v
var goliath_map: bool:
	get: return wave_system.goliath_map
	set(v): wave_system.goliath_map = v
var wave_index: int:
	get: return wave_system.wave_index
	set(v): wave_system.wave_index = v
var wave_active: bool:
	get: return wave_system.wave_active
	set(v): wave_system.wave_active = v
var wave_alive: int:
	get: return wave_system.wave_alive
	set(v): wave_system.wave_alive = v
var wave_loot_mul: float:
	get: return wave_system.wave_loot_mul
	set(v): wave_system.wave_loot_mul = v
var _wave_spawn_queue: Array[Dictionary]:
	get: return wave_system.spawn_queue
	set(v): wave_system.spawn_queue = v
var _wave_total: int:
	get: return wave_system.wave_total
	set(v): wave_system.wave_total = v
var _wave_intermission: float:
	get: return wave_system.intermission
	set(v): wave_system.intermission = v
var _wave_popup: CanvasLayer:
	get: return wave_system.popup
	set(v): wave_system.popup = v


func _cam_float(prop: StringName, fallback: float) -> float:
	if camera_config != null and prop in camera_config:
		return float(camera_config.get(prop))
	return fallback


func _ready() -> void:
	RenderingServer.set_default_clear_color(clear_color)
	if camera != null and camera.zoom.x > 0.05:
		_base_zoom = clampf(camera.zoom.x, 0.2, 4.0)
	else:
		_base_zoom = ZOOM
	if canvas_modulate != null:
		_ambient_color = canvas_modulate.color
	if debug_overlay != null and debug_overlay.visible:
		debug_visual_mode = true
	hud.setup(self)
	hud.return_requested.connect(_return_to_base)
	hud.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	hud.fire_mode_toggle_requested.connect(_on_fire_mode_toggle_requested)
	feedback_system.apply_config(combat_config)
	feedback_system.setup(self, fx_layer, doll, hud)
	combat_system.apply_config(combat_config)
	loot_system = LOOT_SYSTEM.new()
	loot_system.setup(fx_layer, level, doll, hud, wave_loot_scale, feedback_system.play_sfx, _add_loot)
	wave_system.setup(self, sort_layer, level, doll, hud, enemies,
		func() -> bool: return run_state == RunState.ACTIVE,
		_on_enemy_died, feedback_system.play_sfx)
	wave_system.wave_changed.connect(func(w: int, state: String) -> void: wave_changed.emit(w, state))
	wave_system.finish_requested.connect(_finish_run)
	interaction_system.setup(level, doll, hud,
		func() -> bool: return run_state == RunState.ACTIVE,
		func() -> bool: return waves_mode,
		func() -> int: return resources,
		_default_hint, feedback_system.play_sfx)
	interaction_system.container_search_requested.connect(_search_container)
	interaction_system.extract_requested.connect(func(via_switch: bool) -> void: _finish_run(true, via_switch))
	combat_system.setup(self, doll, fx_layer, reticle, enemies,
		func() -> bool: return run_state == RunState.ACTIVE,
		func() -> float: return _ads_t,
		func() -> float: return talent_accuracy,
		func() -> bool: return bullet_trail_enabled,
		func() -> int: return hit_fx_level,
		feedback_system.play_muzzle_fx, feedback_system.add_shake,
		feedback_system.hitstop, feedback_system.play_sfx)
	combat_system.shot_fired.connect(func(wid: StringName, aid: StringName, pellets: int) -> void:
		shot_fired.emit(wid, aid, pellets))
	combat_system.hit_resolved.connect(func(target: Node, dmg: float, killed: bool, mat: String) -> void:
		hit_resolved.emit(target, dmg, killed, mat))
	reticle.setup(self)
	scope_sight = SCOPE_SIGHT.new()
	scope_sight.name = "ScopeSight2D"
	add_child(scope_sight)
	scope_sight.setup(self, doll)
	pause_menu = PauseMenu2D.new()
	pause_menu.name = "PauseMenu2D"
	add_child(pause_menu)
	# 暂停菜单里的设置与开始菜单共用同一份存档；关闭设置页后立即套用到本局。
	pause_menu.settings_applied.connect(_on_settings_applied)
	pause_menu.retreat_requested.connect(_on_waves_retreat)
	feedback_system.build_hit_feedback()

	map_overlay = MapOverlay2D.new()
	map_overlay.name = "MapOverlay2D"
	add_child(map_overlay)
	map_overlay.setup(self)
	map_overlay.opened.connect(_on_overlay_visibility_changed.bind(true))
	map_overlay.closed.connect(_on_overlay_visibility_changed.bind(false))

	backpack = BackpackMenu2D.new()
	backpack.name = "BackpackMenu2D"
	add_child(backpack)
	backpack.setup(self)
	backpack.opened.connect(_on_overlay_visibility_changed.bind(true))
	backpack.closed.connect(_on_overlay_visibility_changed.bind(false))
	result_label = hud.result_label
	var size: Vector2 = level.map_size()
	_camera_bounds = level.camera_bounds()
	camera.limit_left = int(_camera_bounds.position.x)
	camera.limit_top = int(_camera_bounds.position.y)
	camera.limit_right = int(_camera_bounds.end.x)
	camera.limit_bottom = int(_camera_bounds.end.y)
	camera.zoom = Vector2(_base_zoom, _base_zoom)
	doll.global_position = level.player_spawn
	camera.global_position = doll.global_position
	doll.bounds = Rect2(40, 40, size.x - 80, size.y - 80)
	doll.aim_enabled = true
	doll.fx_layer = fx_layer
	doll.dodge_input_blocked_fn = _is_dodge_blocked
	_ensure_view_zoom_action()
	# 行动模式在进入本局前由基地菜单写入 Progress；浪潮模式不刷常规关卡敌人。
	var progress := get_node_or_null("/root/Progress")
	waves_mode = progress != null and String(progress.run_mode()) == "waves"
	goliath_map = waves_mode and progress != null and progress.has_method("map_id") \
		and String(progress.map_id()) == "goliath_arena"
	_apply_visual_override()
	_apply_talents()
	# 分层视野：先建立光照与迷雾，再刷敌人，首帧就按视野决定可见性。
	vision = VISION_FOG.new()
	vision.name = "VisionFog2D"
	$World2D.add_child(vision)
	vision.setup(doll, level, canvas_modulate, _ambient_color, vision_config)
	if progress != null and progress.has_method("talent_2d_level"):
		vision.set_vision_talents(
			int(progress.talent_2d_level(&"vision_range")),
			int(progress.talent_2d_level(&"vision_angle")))
	laser_sight = LASER_SIGHT.new()
	laser_sight.name = "LaserSight2D"
	fx_layer.add_child(laser_sight)
	laser_sight.setup(self, doll)
	# 声纹：Lv.0~4 脚下方向弧环 + 每级扩大听距；Lv.5 解锁声波涟漪（默认共存，可在设置切换）。
	hearing = HEARING_INDICATOR.new()
	hearing.name = "HearingIndicator2D"
	add_child(hearing)
	hearing.setup(self, doll)
	if progress != null:
		if progress.has_method("talent_2d_level"):
			hearing.set_hearing_level(int(progress.talent_2d_level(&"hearing")))
		if progress.has_method("hearing_display_mode"):
			hearing.set_display_mode(String(progress.hearing_display_mode()))
	# 连角色转发信号而不是武器节点：换枪会重建 WeaponRig2D，伤害结算不能跟着断。
	doll.shot_fired.connect(_on_weapon_fired)
	doll.died.connect(_on_player_died)
	doll.damaged.connect(_on_player_damaged)
	if waves_mode:
		pause_menu.set_waves_mode(true)
		_build_waves_exit_popup()
		_wave_intermission = WAVES_START_DELAY
		hud.set_hint("浪潮模式：守住每一波 · 每 5 波可撤离")
	else:
		_spawn_enemies()
		hud.set_hint(HINT_DEFAULT)
	var bgm_sfx := get_node_or_null("/root/Sfx")
	if bgm_sfx != null and bgm_sfx.has_method("set_bgm_state"):
		bgm_sfx.set_bgm_state("combat" if waves_mode else "explore", 1.2)
	if debug_visual_mode:
		_apply_debug_visual_mode()
	else:
		debug_overlay.visible = false
	feedback_system.warm_muzzle_fx()
	feedback_system.warm_combat_fx()


## Alt（视角缩放）与 B（开火模式切换）运行时兜底注册，避免依赖 editor 重新保存输入表。
func _ensure_view_zoom_action() -> void:
	if not InputMap.has_action("view_zoom"):
		InputMap.add_action("view_zoom")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ALT
		InputMap.action_add_event("view_zoom", key)
	if not InputMap.has_action("fire_mode"):
		InputMap.add_action("fire_mode")
		var b_key := InputEventKey.new()
		b_key.physical_keycode = KEY_B
		InputMap.action_add_event("fire_mode", b_key)
	if not InputMap.has_action("ammo_display"):
		InputMap.add_action("ammo_display")
		var j_key := InputEventKey.new()
		j_key.physical_keycode = KEY_J
		InputMap.action_add_event("ammo_display", j_key)
	if not InputMap.has_action("ammo_switch"):
		InputMap.add_action("ammo_switch")
		var q_key := InputEventKey.new()
		q_key.physical_keycode = KEY_Q
		InputMap.action_add_event("ammo_switch", q_key)
	if not InputMap.has_action("dodge"):
		InputMap.add_action("dodge")
		var space_key := InputEventKey.new()
		space_key.physical_keycode = KEY_SPACE
		InputMap.action_add_event("dodge", space_key)


func _is_dodge_blocked() -> bool:
	if run_state != RunState.ACTIVE:
		return true
	if pause_menu != null and pause_menu.visible:
		return true
	if map_overlay != null and map_overlay.visible:
		return true
	if backpack != null and backpack.visible:
		return true
	return false


## 通过命令行切换角色表现：
##   默认：整身图集 + 独立头部（头随鼠标摆动）+ 手持 g17
##   `-- --rig=normal` / `--rig=chibi`  实验性的分件骨架（头/躯干/四肢/武器箱）
##   `-- --lod=1024`                    切换整身图集精度
##   `-- --weapon=off`                  不举枪
func _apply_visual_override() -> void:
	var rig_style := ""
	var weapon := "g17"
	var loadout_ids: Array[StringName] = []
	var progress := get_node_or_null("/root/Progress")
	if progress != null:
		for id in progress.loadout_2d():
			loadout_ids.append(StringName(id))
		if not loadout_ids.is_empty():
			weapon = String(loadout_ids[0])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rig="):
			rig_style = arg.get_slice("=", 1)
		elif arg.begins_with("--weapon="):
			weapon = arg.get_slice("=", 1)
		elif arg.begins_with("--lod="):
			var body_px := int(arg.get_slice("=", 1))
			if body_px > 0:
				doll.configure(body_px)
				return
	if weapon != "off":
		var rig := doll.equip_weapon_id(StringName(weapon))
		if not loadout_ids.has(StringName(weapon)):
			loadout_ids.push_front(StringName(weapon))
		var allowed: Array[StringName] = []
		for i in mini(loadout_ids.size(), 2):
			allowed.append(loadout_ids[i])
		rig.loadout = allowed
		rig.fire_input_blocked_fn = hud.is_pointer_over_interactive
		rig.fire_mode_changed.connect(_on_fire_mode_changed)
		rig.ammo_switched.connect(_on_ammo_switched)
	if rig_style == "" or rig_style == "off":
		return
	doll.enable_rig(rig_style)


## 把 2D 天赋树等级应用到本局角色/武器；升级从下一次行动开始生效。
func _apply_talents() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	var hp_level := int(progress.talent_2d_level(&"hp"))
	var body_adapt_pct := float(progress.body_adapt_hp_bonus()) if progress.has_method("body_adapt_hp_bonus") else 0.0
	var base_hp := int(round(100.0 * (1.0 + float(hp_level) * 0.15 + body_adapt_pct)))
	var move_mul := 1.0 + float(progress.talent_2d_level(&"move")) * 0.05
	doll.walk_speed *= move_mul
	doll.sprint_speed *= move_mul
	doll.dodge_dist_mul = 1.0 + float(progress.talent_2d_level(&"dodge_dist")) * 0.08
	doll.dodge_cd_mul = maxf(0.50, 1.0 - float(progress.talent_2d_level(&"dodge_cd")) * 0.08)
	talent_accuracy = WeaponStatsModel.gun_accuracy_mul(int(progress.talent_2d_level(&"gun")))
	var stipend_pct := float(progress.ops_stipend_bonus()) if progress.has_method("ops_stipend_bonus") else 0.0
	talent_scavenge = 1.0 + float(progress.talent_2d_level(&"scavenge")) * 0.10 + stipend_pct
	# 屏幕震动 / 顿帧 / 震动倍率同步至 FeedbackSystem2D。
	feedback_system.apply_settings(progress)
	if doll != null and doll.weapon_rig != null:
		doll.weapon_rig.set_muzzle_flash_mode(feedback_system.muzzle_flash_mode)
	hit_fx_level = clampi(int(progress.data.get("hit_fx_level", 1)), 0, 2)
	bullet_trail_enabled = bool(progress.data.get("bullet_trail_enabled", true))
	_apply_bullet_trail_setting()
	# 整体视角缩放档位是持久设置；Alt+滚轮调整后立即保存。
	var zoom_step := maxf(_cam_float(&"view_zoom_step", VIEW_ZOOM_STEP), 1.0)
	view_zoom_pct = clampf(
		roundf(float(progress.data.get("view_zoom", 100)) / zoom_step) * zoom_step,
		_cam_float(&"view_zoom_min", VIEW_ZOOM_MIN),
		_cam_float(&"view_zoom_max", VIEW_ZOOM_MAX))
	if hud != null:
		if progress.has_method("pickup_merge_window"):
			hud.set_pickup_merge_window(float(progress.pickup_merge_window()))
		if progress.has_method("ammo_display"):
			hud.set_ammo_display_mode(String(progress.ammo_display()))
		elif progress.data is Dictionary:
			hud.set_ammo_display_mode(String(progress.data.get("ammo_display", "both")))
		if progress.has_method("ammo_exact_rounds"):
			hud.set_ammo_exact_rounds(bool(progress.ammo_exact_rounds()))
		elif progress.data is Dictionary:
			hud.set_ammo_exact_rounds(bool(progress.data.get("ammo_exact_rounds", false)))
	_view_zoom_visual = view_zoom_pct
	# 护甲：基础存档值 + 护甲组件 + 护甲强化天赋，进入行动时补满（同步叠加调试上限倍率）。
	var armor_mods := ModDB.modifiers(progress.armor_mods_2d(), true)
	var base_armor := maxi(10, int(progress.data.get("armor_max", 100))
		+ int(armor_mods["armor_max_add"]))
	base_armor += int(progress.talent_2d_level(&"armor")) * 20
	doll.set_base_vitals(base_hp, base_armor, true)
	doll.armor_level = int(progress.data.get("armor_level", 1)) \
		+ int(armor_mods["armor_level_add"])
	doll.armor_absorb_bonus = float(armor_mods["absorb_add"])
	doll.walk_speed *= float(armor_mods["move_mul"])
	doll.sprint_speed *= float(armor_mods["move_mul"])
	if doll.weapon_rig != null:
		doll.weapon_rig.reload_time_mul = WeaponStatsModel.reload_talent_mul(int(progress.talent_2d_level(&"reload")))
		doll.weapon_rig.hold_reload_enabled = progress.talent_2d_level(&"loading") > 0
		var reserve_mul := 1.0 + float(progress.talent_2d_level(&"reserve")) * 0.20
		doll.weapon_rig.apply_reserve_talent(reserve_mul)
	hud.set_hp(doll.hp, doll.hp_max)
	hud.set_armor(doll.armor, doll.armor_max)


## 设置页关闭时只刷新画面相关项，不重跑天赋/护甲，避免顺手把血补满。
func _on_settings_applied() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	feedback_system.apply_settings(progress)
	if doll != null and doll.weapon_rig != null:
		doll.weapon_rig.set_muzzle_flash_mode(feedback_system.muzzle_flash_mode)
	hit_fx_level = clampi(int(progress.data.get("hit_fx_level", 1)), 0, 2)
	bullet_trail_enabled = bool(progress.data.get("bullet_trail_enabled", true))
	_apply_bullet_trail_setting()
	var zoom_step := maxf(_cam_float(&"view_zoom_step", VIEW_ZOOM_STEP), 1.0)
	view_zoom_pct = clampf(
		roundf(float(progress.data.get("view_zoom", 100)) / zoom_step) * zoom_step,
		_cam_float(&"view_zoom_min", VIEW_ZOOM_MIN),
		_cam_float(&"view_zoom_max", VIEW_ZOOM_MAX))
	if hud != null:
		if progress.has_method("pickup_merge_window"):
			hud.set_pickup_merge_window(float(progress.pickup_merge_window()))
		if progress.has_method("ammo_display"):
			hud.set_ammo_display_mode(String(progress.ammo_display()))
		elif progress.data is Dictionary:
			hud.set_ammo_display_mode(String(progress.data.get("ammo_display", "both")))
		if progress.has_method("ammo_exact_rounds"):
			hud.set_ammo_exact_rounds(bool(progress.ammo_exact_rounds()))
		elif progress.data is Dictionary:
			hud.set_ammo_exact_rounds(bool(progress.data.get("ammo_exact_rounds", false)))
	if doll != null and progress.has_method("debug_mul"):
		doll.sync_debug_vitals(
			float(progress.debug_mul("hp_max_mul")),
			float(progress.debug_mul("armor_max_mul")))
		if hud != null:
			hud.set_hp(doll.hp, doll.hp_max)
			hud.set_armor(doll.armor, doll.armor_max)
	if hearing != null and progress.has_method("hearing_display_mode"):
		hearing.set_display_mode(String(progress.hearing_display_mode()))


## 立即套用弹道线条开关：只隐藏枪口到弹丸的长线，弹丸实体与命中不受影响。
func _apply_bullet_trail_setting() -> void:
	feedback_system.apply_bullet_trail_setting(bullet_trail_enabled)


func _spawn_enemies() -> void:
	for i in level.enemy_spawns.size():
		var enemy := Enemy2D.new()
		enemy.setup(level.enemy_kinds[i], level.enemy_spawns[i], 1)
		enemy.nav_level = level
		sort_layer.add_child(enemy)
		enemy.died.connect(_on_enemy_died)
		enemies.append(enemy)


func _on_enemy_died(enemy: Enemy2D) -> void:
	kills += 1
	if waves_mode:
		wave_alive = maxi(wave_alive - 1, 0)
	_alert_enemies_near_death(enemy)
	_spawn_enemy_drops(enemy)
	enemies.erase(enemy)


## 队友在视野内被击杀会惊动附近单位：它们会朝玩家最后出现的位置转入搜索。
func _alert_enemies_near_death(victim: Enemy2D) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var pos := victim.global_position
	for other in enemies:
		if other == victim or not is_instance_valid(other) or other.hp <= 0.0:
			continue
		var view_px := float(other.stats.get("view_range", 15.0)) * TILE
		if other.global_position.distance_to(pos) > view_px:
			continue
		if not other.can_see_point(pos):
			continue
		other.alert_by_ally_death(pos)


## --- 掉落 / 拾取 / 入包（委托至 LootSystem2D）---------------------------------

func _spawn_enemy_drops(enemy: Enemy2D) -> void:
	loot_system.spawn_enemy_drops(enemy)


func _roll_basic_drop(kind: StringName) -> StringName:
	return LOOT_SYSTEM.roll_basic_drop(kind)


func _roll_basic_excluding(excluded: StringName) -> StringName:
	return LOOT_SYSTEM.roll_basic_excluding(excluded)


func _random_advanced() -> StringName:
	return LOOT_SYSTEM.roll_advanced()


func _spawn_pickup(pos: Vector2, kind: String, id: StringName, amount: int) -> void:
	loot_system.spawn_pickup(pos, kind, id, amount)


func _on_pickup_collected(kind: String, id: StringName, amount: int) -> void:
	loot_system.on_pickup_collected(kind, id, amount)


## 拾取/容器入包：只改本局库存，撤离时才写回存档。
func _add_loot(id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	var is_basic := ResourceDB.is_basic(id)
	if is_basic:
		loot[String(id)] = int(loot.get(String(id), 0)) + amount
	else:
		advanced_loot[String(id)] = int(advanced_loot.get(String(id), 0)) + amount
	resources += amount
	loot_gained.emit(id, amount, not is_basic)


## UI 只读快照：给 BackpackMenu2D 读取本局物资副本，避免直接访问内部字段。
func get_loot_snapshot() -> Dictionary:
	return {
		"basic": loot.duplicate(),
		"advanced": advanced_loot.duplicate(),
	}


## UI 只读快照：给 Minimap2D / MapOverlay2D 绘制地图、玩家与敌人状态，避免反向遍历 Main2D 节点。
func get_map_snapshot() -> Dictionary:
	if doll == null or level == null:
		return {}
	var player_pos: Vector2 = doll.global_position
	var aim_dir: Vector2 = (doll.aim_target - player_pos).normalized()
	if aim_dir == Vector2.ZERO:
		aim_dir = Vector2.RIGHT
	var enemy_positions: Array[Vector2] = []
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy_positions.append(enemy.global_position)
	return {
		"map_size": level.map_size(),
		"tile_size": Level2D.TILE,
		"floor_rects": level.map_floor_rects(),
		"rooms": level.rooms,
		"containers": level.containers,
		"exits": level.exits,
		"power_position": level.power_position,
		"power_on": level.power_on,
		"switch_exit_position": level.switch_exit_position,
		"exit_position": level.exit_position,
		"player_spawn": level.player_spawn,
		"player_pos": player_pos,
		"aim_dir": aim_dir,
		"tracking": waves_tracking_active(),
		"enemy_positions": enemy_positions,
	}


func _on_overlay_visibility_changed(active: bool) -> void:
	if hud != null:
		hud.visible = not active
	if reticle != null:
		reticle.visible = not active


## 拾取弹药：id 为通用弹药种类（light/medium/heavy/shotgun/special）。
func _grant_ammo(category: StringName, amount: int) -> void:
	loot_system.grant_ammo(category, amount)


## 撤离结算用：基础资源吃搜刮天赋加成，进阶资源按原样入库。
func _banked_materials() -> Dictionary:
	return LOOT_SYSTEM.compute_banked_materials(loot, advanced_loot, talent_scavenge)


## 浪潮结算：按比例回收物资，并把基础/进阶拆开供结算面板展示。
func _scaled_materials(ratio: float) -> Dictionary:
	return LOOT_SYSTEM.compute_scaled_materials(loot, advanced_loot, talent_scavenge, ratio)


func _process(delta: float) -> void:
	if run_state == RunState.ACTIVE:
		run_elapsed += delta
		_update_bgm_state(delta)
	# 右键瞄准只负责前探视野与散布收紧；整体缩放由 Alt+滚轮独立控制。
	# 与 WeaponRig2D._ads_t 共用同一套开镜速率（1 / ads_time），高倍镜与枪型手感完全同步。
	var want_ads := 1.0 if (doll.ads and run_state == RunState.ACTIVE) else 0.0
	var ads_speed := doll.weapon_rig.get_ads_rate() if doll.weapon_rig != null \
		else _cam_float(&"ads_zoom_speed", ADS_ZOOM_SPEED)
	var dbg_progress := get_node_or_null("/root/Progress")
	if dbg_progress != null:
		ads_speed *= float(dbg_progress.debug_mul("ads"))
	_ads_t = move_toward(_ads_t, want_ads, ads_speed * delta)
	combat_system.update(delta)
	var scoped: bool = doll.weapon_rig != null and doll.weapon_rig.has_scope_sight
	var sight_mag: float = float(doll.weapon_rig.sight_magnification) if doll.weapon_rig != null else 1.0
	# 红点/全息保持主镜头轻微放大（1.1×/1.5×）并靠额外前探提升远射能力；
	# 高倍镜（2×~8×）则随倍率平滑拉远主镜头（0.85×~0.62×），兼顾横纵视野大幅展开与角色不离屏，
	# 镜内 SubViewport 仍保持额定 2×~8× 放大。
	if scoped:
		scope_magnification = scope_camera_zoom_mul(
			sight_mag,
			_cam_float(&"scope_zoom_out_min_mag", 0.85),
			_cam_float(&"scope_zoom_out_max_mag", 0.62))
	elif doll.weapon_rig != null:
		scope_magnification = doll.weapon_rig.aim_zoom_mul
	else:
		scope_magnification = 1.0
	if scope_sight != null:
		reticle.visible = not scope_sight.should_hide_reticle()
	if waves_mode:
		_update_waves(delta)
	_view_zoom_visual = move_toward(
		_view_zoom_visual, view_zoom_pct, _cam_float(&"view_zoom_lerp", VIEW_ZOOM_LERP) * delta)
	var base_zoom := _base_zoom * (_view_zoom_visual / 100.0)
	var scope_mul := lerpf(1.0, scope_magnification, _ads_t)
	var zoom := base_zoom * scope_mul
	var cam_lift := _cam_float(&"camera_lift", CAMERA_LIFT)

	var vrect := get_viewport().get_visible_rect().size
	var half_view_default := vrect * 0.5 / _base_zoom
	var half_view_base := vrect * 0.5 / maxf(base_zoom, 0.001)
	var half_view := vrect * 0.5 / maxf(zoom, 0.001)

	# 先读取修改 limit_* 之前的真实相机中心 C0，确保紧贴墙边或低缩放开镜也能 0 偏移接管。
	var prev_cam_center := camera.get_screen_center_position()

	# 镜头缩放小于 100%（如 50% / 20%）或高倍镜拉远时，对称放宽 camera.limit_* 边界，
	# 防止左/上墙边界把镜头强行向右下方推挤造成严重开镜偏差。
	if _camera_bounds.size.x > 0.0 and _camera_bounds.size.y > 0.0:
		var pad_x := maxf(0.0, half_view.x - half_view_default.x)
		var pad_y := maxf(0.0, half_view.y - half_view_default.y)
		if scoped and _ads_t > 0.01:
			pad_x += half_view.x * 0.65
			pad_y += half_view.y * 0.65
		camera.limit_left = int(floor(_camera_bounds.position.x - pad_x))
		camera.limit_top = int(floor(_camera_bounds.position.y - pad_y))
		camera.limit_right = int(ceil(_camera_bounds.end.x + pad_x))
		camera.limit_bottom = int(ceil(_camera_bounds.end.y + pad_y))

	# 方案 B（增量外推前探 + zoom-to-cursor 零偏移）：
	# 进入高倍镜 ADS 瞬间记录鼠标屏幕位置 M0 与当前镜头贴墙偏置；
	# 不调用 warp_mouse，靠闭式 zoom_anchor 让主镜头围绕 M0 拉远（任意视角缩放下准心点 0 偏移），
	# 仅在继续向外推鼠标时平滑展开前探。
	var want_scope_b := mouse_aim_enabled and scoped and _ads_t > 0.01
	if want_scope_b:
		if not _scope_ads_active:
			_scope_ads_active = true
			_scope_entry_mouse = get_viewport().get_mouse_position().clamp(Vector2.ZERO, vrect)
			var ideal_base := doll.global_position - Vector2(0.0, cam_lift)
			_scope_entry_cam_bias = prev_cam_center - ideal_base
			_scope_cam_offset = Vector2.ZERO
	else:
		_scope_ads_active = false
		_scope_entry_cam_bias = Vector2.ZERO

	var look := Vector2.ZERO
	if _ads_t > 0.01:
		var look_mul := 1.0
		if doll.weapon_rig != null:
			look_mul = maxf(float(doll.weapon_rig.sight_look_ahead_mul), 1.0)
		var look_ahead := _cam_float(&"ads_look_ahead", ADS_LOOK_AHEAD) * look_mul
		if scoped:
			# 高倍镜前探上限严格约束在半屏比例内（Y 轴计入 cam_lift），角色全身始终留在屏内。
			var max_x := minf(look_ahead, half_view.x * _cam_float(&"scope_keep_player_ratio_x", SCOPE_KEEP_PLAYER_RATIO_X))
			var max_y := minf(look_ahead, half_view.y * _cam_float(&"scope_keep_player_ratio_y", SCOPE_KEEP_PLAYER_RATIO_Y))
			var y_min := -max_y + cam_lift
			var y_max := max_y + cam_lift
			var deadzone := _cam_float(&"scope_deadzone_px", 6.0)
			if mouse_aim_enabled:
				var cur_m := get_viewport().get_mouse_position()
				var dm := cur_m - _scope_entry_mouse
				var dm_len := dm.length()
				var desired_offset := Vector2.ZERO
				if doll.ads and dm_len > deadzone:
					# 减去静止防抖死区，并按外推方向剩余屏幕空间归一化，
					# 即使开镜初始光标靠近屏边，继续轻推也能顺畅拉满 100% 前探。
					var eff := dm * ((dm_len - deadzone) / dm_len)
					var room_x := clampf(
						(vrect.x - 40.0 - _scope_entry_mouse.x) if eff.x >= 0.0 else (_scope_entry_mouse.x - 40.0),
						120.0, maxf(120.0, vrect.x * 0.40))
					var room_y := clampf(
						(vrect.y - 40.0 - _scope_entry_mouse.y) if eff.y >= 0.0 else (_scope_entry_mouse.y - 40.0),
						90.0, maxf(90.0, vrect.y * 0.38))
					var norm := Vector2(
						clampf(eff.x / room_x, -1.0, 1.0),
						clampf(eff.y / room_y, -1.0, 1.0),
					)
					var nlen := norm.length()
					if nlen > 1.0:
						norm /= nlen
					desired_offset = Vector2(
						clampf(norm.x * max_x, -max_x, max_x),
						clampf(norm.y * max_y, y_min, y_max),
					)
				var scope_smooth := _cam_float(&"scope_look_smooth", 10.0)
				_scope_cam_offset = _scope_cam_offset.lerp(desired_offset, clampf(delta * scope_smooth, 0.0, 1.0))
				if _scope_cam_offset.distance_to(desired_offset) < 0.5:
					_scope_cam_offset = desired_offset
				_ads_look = desired_offset.normalized() if desired_offset.length_squared() > 1.0 else Vector2.ZERO
				# 闭式 zoom-to-cursor 补偿：无论 100% / 50% / 20% 镜头缩放，开镜拉远时准心下世界点严格保持不变。
				var zoom_anchor := (_scope_entry_mouse - vrect * 0.5) \
					* (1.0 / maxf(base_zoom, 0.001) - 1.0 / maxf(zoom, 0.001))
				look = _scope_entry_cam_bias + zoom_anchor + _scope_cam_offset * _ads_t
			else:
				var raw_d := doll.aim_target - doll.global_position
				var dir := raw_d.normalized() if raw_d.length_squared() > 1.0 else Vector2.ZERO
				_ads_look = dir
				var desired_offset := Vector2(
					clampf(dir.x * look_ahead, -max_x, max_x),
					clampf(dir.y * look_ahead, y_min, y_max),
				)
				_scope_cam_offset = desired_offset
				look = desired_offset * _ads_t
		else:
			_scope_cam_offset = Vector2.ZERO
			# 反射式低倍镜（红点 1.1× / 全息 1.5×）保留主镜头放大，按轴补偿缩放损失并增加额外前探，
			# 确保实际前方净视野严格递增（机瞄 < 红点 < 全息），强化中远距射击能力。
			var zoom_comp := Vector2(
				maxf(0.0, half_view_base.x - half_view.x),
				maxf(0.0, half_view_base.y - half_view.y),
			)
			var ads_smooth := _cam_float(&"ads_look_smooth", ADS_LOOK_SMOOTH)
			if mouse_aim_enabled:
				var rel := (get_viewport().get_mouse_position() - vrect * 0.5) / maxf(minf(vrect.x, vrect.y) * 0.45, 1.0)
				var raw_ratio := clampf(rel.length(), 0.0, 1.0)
				var mag_ratio := lerpf(0.35, 1.0, raw_ratio) if raw_ratio > 0.04 else 0.0
				var desired := rel.normalized() * mag_ratio if raw_ratio > 0.04 else Vector2.ZERO
				_ads_look = _ads_look.lerp(desired, clampf(delta * ads_smooth, 0.0, 1.0))
			else:
				var raw_aim := doll.aim_target - doll.global_position
				var aim_dir := raw_aim.normalized() if raw_aim.length_squared() > 1.0 else Vector2.RIGHT
				if raw_aim.length_squared() <= 1.0 and doll.weapon_rig != null:
					aim_dir = doll.weapon_rig.get_barrel_direction()
				_ads_look = _ads_look.lerp(
					aim_dir.normalized(), clampf(delta * ads_smooth, 0.0, 1.0))
			look = Vector2(
				_ads_look.x * (look_ahead + zoom_comp.x) * _ads_t,
				_ads_look.y * (look_ahead + zoom_comp.y) * _ads_t,
			)
			var max_non_scope := Vector2(
				maxf(half_view_base.x * 1.45, 1200.0),
				maxf(half_view_base.y * 1.65, 860.0),
			)
			look.x = clampf(look.x, -max_non_scope.x, max_non_scope.x)
			look.y = clampf(look.y, -max_non_scope.y, max_non_scope.y)
	else:
		_ads_look = Vector2.ZERO
		_scope_cam_offset = Vector2.ZERO

	if absf(camera.zoom.x - zoom) > 0.0005:
		camera.zoom = Vector2(zoom, zoom)
	# 相机跟随按「屏幕像素」取整，避免角色和场景在半像素位置上被重采样而发虚。
	var snap := 1.0 / maxf(zoom, 0.001)
	var target := Vector2(
		roundf((doll.global_position.x + look.x + _recoil_cam.x) / snap) * snap,
		roundf((doll.global_position.y - cam_lift + look.y + _recoil_cam.y) / snap) * snap,
	)
	var shake_step := feedback_system.step_shake(delta)
	target += shake_step["offset"]
	# 瞄准期间关闭镜头位置平滑：平滑会让准心下的世界点持续“滑行”，
	# 在高倍镜里被放大成明显的瞄准偏移。腰射时恢复原有平滑，走位手感不变。
	if _ads_t > 0.01 and camera.position_smoothing_enabled:
		camera.position_smoothing_enabled = false
		camera.reset_smoothing()
		_ads_smoothing_off = true
	elif _ads_t < 0.01 and _ads_smoothing_off:
		camera.position_smoothing_enabled = true
		camera.reset_smoothing()
		_ads_smoothing_off = false
	camera.global_position = target
	camera.rotation = float(shake_step["roll"]) + _recoil_roll
	# 立即刷新 Camera2D 视口矩阵，彻底消除同帧 get_global_mouse_position 与 ScopeSight2D 的 1 帧错位。
	camera.force_update_scroll()
	feedback_system.update_muzzle_fx()
	if mouse_aim_enabled:
		doll.aim_target = get_global_mouse_position()
	_update_hud(delta)
	if debug_visual_mode:
		_label_timer += delta
		if _label_timer >= 0.25:
			_label_timer = 0.0
			_update_debug_label()


## 高倍镜开镜主镜头拉远倍率：2×→min_mag(默认0.85) … 8×→max_mag(默认0.62)，
## 在横纵双向大幅展开视野的同时让角色始终留在屏内；镜内 SubViewport 仍保持额定倍率。
static func scope_camera_zoom_mul(sight_mag: float, min_mag := 0.85, max_mag := 0.62) -> float:
	if sight_mag <= 1.5:
		return 1.0
	var t := clampf((sight_mag - 2.0) / 6.0, 0.0, 1.0)
	return lerpf(min_mag, max_mag, pow(t, 0.85))


func _update_hud(delta: float) -> void:
	hud.set_hp(doll.hp, doll.hp_max)
	hud.set_armor(doll.armor, doll.armor_max)
	hud.set_dodge(doll.get_dodge_cooldown_ratio(), doll.is_dodging(),
		doll.is_dodge_invuln(), doll.get_dodge_cooldown_left())
	hud.set_objective(_objective_text())
	hud.update_weapon(doll.weapon_rig)
	interaction_system.update(delta)


## 目标文案跟着局内进度变化；直接撤离始终可用，供电只是可选收益线。
func _objective_text() -> String:
	if run_state == RunState.SUCCESS:
		return "行动结束"
	if waves_mode:
		return wave_system.objective_text()
	if level.power_on:
		return "目标：撤离 · 拉闸 +20%"
	return "目标：搜刮 → 撤离（可选：供电）"


## 底部操作提示：浪潮模式用波次信息替代常规搜刮提示。
func _default_hint() -> String:
	if not waves_mode:
		return HINT_DEFAULT
	return wave_system.default_hint()


func _flash_hint(text: String) -> void:
	interaction_system.flash_hint(text)


func _on_fire_mode_toggle_requested() -> void:
	if run_state != RunState.ACTIVE or doll == null or doll.weapon_rig == null:
		return
	doll.weapon_rig.toggle_fire_mode()


func _on_fire_mode_changed(mode: String, supported: bool) -> void:
	if hud == null:
		return
	if not supported:
		_flash_hint("当前武器仅支持半自动 (S)")
	elif mode == "auto":
		_flash_hint("开火模式：全自动 (F)")
	else:
		_flash_hint("开火模式：半自动 (S)")
	if doll != null:
		hud.update_weapon(doll.weapon_rig)


func _on_ammo_switched(ammo_id: StringName) -> void:
	if hud == null:
		return
	var ammo := WeaponDB.get_ammo(ammo_id)
	if ammo != null:
		var cost_tag := "" if ammo.reserve_cost <= 1.01 else "（耗弹 ×%.1f）" % ammo.reserve_cost
		_flash_hint("切弹完成：[%s %s] %s%s" % [
			WeaponDB.tier_label(ammo.tier), WeaponDB.role_label(ammo.role), ammo.display_name, cost_tag])
	if doll != null:
		hud.update_weapon(doll.weapon_rig)


## --- 战斗 / 弹道 / 散布 / 后坐力（委托至 CombatSystem2D）----------------------

func get_shot_origin() -> Vector2:
	return combat_system.get_shot_origin()


func get_safe_shot_origin(muzzle_override: Vector2 = Vector2.INF) -> Vector2:
	return combat_system.get_safe_shot_origin(muzzle_override)


## 玩家当前视角缩放系数（1.0 = 100%，0.4 = 40%）。高倍镜用它联动镜内放大。
func view_zoom_scale() -> float:
	return _view_zoom_visual / 100.0


func recoil_strength() -> float:
	return combat_system.recoil_strength()


func aim_direction_from(origin: Vector2) -> Vector2:
	return combat_system.aim_direction_from(origin)


func _wall_between(origin: Vector2, point: Vector2) -> Dictionary:
	return combat_system.wall_between(origin, point)


func current_ammo() -> AmmoData:
	return combat_system.current_ammo()


func get_aim_spread() -> float:
	return combat_system.get_aim_spread()


func _spread_offset(spread: float) -> float:
	return combat_system.spread_offset(spread)


func _add_burst_spread(data: WeaponData) -> void:
	combat_system.add_burst_spread(data)


func _update_burst_spread(delta: float) -> void:
	combat_system.update_burst_spread(delta)


func get_aim_block() -> Dictionary:
	return combat_system.get_aim_block()


func _shot_range() -> float:
	return combat_system.shot_range()


func bullet_speed_px_s(ammo: AmmoData, weapon_data: WeaponData = null) -> float:
	return combat_system.bullet_speed_px_s(ammo, weapon_data)


func bullet_travel_time(ammo: AmmoData, distance_m: float,
		weapon_data: WeaponData = null) -> float:
	return combat_system.bullet_travel_time(ammo, distance_m, weapon_data)


func _trace_pellet(origin: Vector2, direction: Vector2, length: float) -> Dictionary:
	return combat_system.trace_pellet(origin, direction, length)


func _on_weapon_fired(muzzle: Vector2, dir: Vector2) -> void:
	_bgm_combat_hold = 8.0
	combat_system.on_weapon_fired(muzzle, dir)


func _update_bgm_state(delta: float) -> void:
	if _bgm_combat_hold > 0.0:
		_bgm_combat_hold = maxf(_bgm_combat_hold - delta, 0.0)
	_bgm_check_t -= delta
	if _bgm_check_t > 0.0:
		return
	_bgm_check_t = 0.40
	var sfx := get_node_or_null("/root/Sfx")
	if sfx == null or not sfx.has_method("set_bgm_state"):
		return
	var in_combat := waves_mode or _bgm_combat_hold > 0.0
	if not in_combat:
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy._dead and String(enemy.state) == "combat":
				in_combat = true
				break
	if in_combat:
		sfx.set_bgm_state("combat", 0.9)
	else:
		sfx.set_bgm_state("explore", 2.2)


func spawn_player_bullet(origin: Vector2, direction: Vector2, speed_px_s: float,
		drag_px: float, dmg: float, pen: float, range_px: float,
		bullet_color: Color, ctx: Dictionary, knock: float) -> PlayerBullet2D:
	return combat_system.spawn_player_bullet(origin, direction, speed_px_s, drag_px,
		dmg, pen, range_px, bullet_color, ctx, knock)


func _player_bullet_hit_wall(bullet, point: Vector2, dir: Vector2) -> void:
	combat_system.on_bullet_hit_wall(bullet, point, dir)


func _player_bullet_hit_enemy(bullet, target, point: Vector2, dir: Vector2) -> void:
	combat_system.on_bullet_hit_enemy(bullet, target, point, dir)


func _flush_shot_buckets(ctx: Dictionary) -> void:
	combat_system.flush_shot_buckets(ctx)


func _player_bullet_finished(bullet) -> void:
	combat_system.on_bullet_finished(bullet)


func _apply_hit_batch(ctx: Dictionary, target, amount: float,
		point: Vector2, dir: Vector2) -> void:
	combat_system.apply_hit_batch(ctx, target, amount, point, dir)


## --- 打击反馈 / 特效 / 音效（委托至 FeedbackSystem2D）-------------------------

func _play_sfx(kind: String, volume_db := 0.0) -> void:
	feedback_system.play_sfx(kind, volume_db)


func add_shake(amount: float) -> void:
	feedback_system.add_shake(amount)


func _exit_tree() -> void:
	feedback_system.reset_time_scale()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if run_state != RunState.ACTIVE:
			_return_to_base()
			get_viewport().set_input_as_handled()
			return
		if pause_menu != null and not pause_menu.visible:
			pause_menu.open()
			get_viewport().set_input_as_handled()
		return
	# 任何状态下 Alt + 滚轮调整整体视角：20%–200%，每格 10%；松手后档位固定。
	if event is InputEventMouseButton and event.pressed \
			and run_state == RunState.ACTIVE \
			and (pause_menu == null or not pause_menu.visible) \
			and (map_overlay == null or not map_overlay.visible) \
			and Input.is_action_pressed("view_zoom"):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_view_zoom(view_zoom_pct + _cam_float(&"view_zoom_step", VIEW_ZOOM_STEP))
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_view_zoom(view_zoom_pct - _cam_float(&"view_zoom_step", VIEW_ZOOM_STEP))
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ammo_display"):
		if run_state == RunState.ACTIVE \
				and (pause_menu == null or not pause_menu.visible) \
				and (map_overlay == null or not map_overlay.visible) \
				and (backpack == null or not backpack.visible):
			_cycle_ammo_display()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_TAB:
			if run_state == RunState.ACTIVE \
					and (pause_menu == null or not pause_menu.visible) \
					and (map_overlay == null or not map_overlay.visible):
				backpack.open()
				get_viewport().set_input_as_handled()
		KEY_E:
			_try_interact()
			get_viewport().set_input_as_handled()
		KEY_R:
			if run_state != RunState.ACTIVE:
				get_tree().reload_current_scene()
		KEY_M:
			if run_state == RunState.ACTIVE \
					and (pause_menu == null or not pause_menu.visible):
				map_overlay.toggle()
				get_viewport().set_input_as_handled()
		KEY_F7:
			debug_visual_mode = not debug_visual_mode
			_apply_debug_visual_mode()
			get_viewport().set_input_as_handled()
		KEY_F8:
			get_tree().debug_collisions_hint = not get_tree().debug_collisions_hint
			get_viewport().set_input_as_handled()


## J 键轮换弹药显示模式（both 图文 → numeric 数值 → graphic 图形），同步写回存档并轻闪提示。
func _cycle_ammo_display() -> void:
	if hud == null:
		return
	var next_mode := hud.cycle_ammo_display_mode()
	var progress := get_node_or_null("/root/Progress")
	if progress != null and progress.has_method("set_ammo_display"):
		progress.set_ammo_display(next_mode)
	var labels := {
		"both": "弹药显示：图文（容器 + 数值）",
		"numeric": "弹药显示：纯数值",
		"graphic": "弹药显示：纯图形容器",
	}
	_flash_hint(String(labels.get(next_mode, "弹药显示已切换")))
	if doll != null and doll.weapon_rig != null:
		hud.update_weapon(doll.weapon_rig)


## 整体视角缩放：夹在可配上下限（默认 20%–200%）并按步进档位对齐。
func _set_view_zoom(value: float) -> void:
	var step := maxf(_cam_float(&"view_zoom_step", VIEW_ZOOM_STEP), 1.0)
	view_zoom_pct = clampf(
		roundf(value / step) * step,
		_cam_float(&"view_zoom_min", VIEW_ZOOM_MIN),
		_cam_float(&"view_zoom_max", VIEW_ZOOM_MAX))
	var progress := get_node_or_null("/root/Progress")
	if progress != null:
		progress.set_view_zoom(view_zoom_pct)


## 倍镜接口：武器接入倍镜时调用，例如 equip 后 set_scope_magnification(2.0)。
## 1.0 为无倍镜；倍率只在 ADS 过渡中叠加，不会污染整体视角档位。
func set_scope_magnification(value: float) -> void:
	scope_magnification = clampf(value, 1.0, 8.0)


func get_scope_magnification() -> float:
	return scope_magnification


## 撤离/阵亡后回到基地菜单；与 HUD 的“返回基地”按钮共用。
func _return_to_base() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/ui/StartMenu2D.tscn")


## --- 交互（委托至 InteractionSystem2D）----------------------------------------

func _try_interact() -> void:
	interaction_system.try_interact()


func _restore_power() -> void:
	interaction_system.restore_power()


func _try_switch_extract() -> void:
	interaction_system.try_switch_extract()


func _search_container(entry: Dictionary) -> void:
	loot_system.search_container(entry)


func _roll_container_bundle(primary: StringName, amount_min: int, amount_max: int,
		secondary_chance: float, advanced_chance: float) -> Array[Dictionary]:
	return LOOT_SYSTEM.roll_container_bundle(primary, amount_min, amount_max,
		secondary_chance, advanced_chance, wave_loot_scale())


func _grant_container_gains(gains: Array[Dictionary]) -> void:
	loot_system.grant_container_gains(gains)


func _try_extract() -> void:
	interaction_system.try_extract()


## 收尾结算：常规模式按 100% 入账；浪潮模式按 payout_ratio 回收。
## 浪潮的 payout_ratio：死亡 / ESC 提前撤离 0.3，每 5 波撤离 1.0。
func _finish_run(success: bool, via_switch := false,
		payout_ratio := 1.0, note := "") -> void:
	if run_state != RunState.ACTIVE:
		return
	# 结算时务必把顿帧的时间缩放收回，避免结算界面继续慢放。
	feedback_system.reset_time_scale()
	if _wave_popup != null and _wave_popup.visible:
		_wave_popup.visible = false
		get_tree().paused = false
	run_state = RunState.SUCCESS if success else RunState.FAILED
	var meta_reward := 0
	var xp_reward := 0
	var bonus_note := note
	var display_loot := loot
	var display_advanced := advanced_loot
	if waves_mode:
		var scaled := _scaled_materials(payout_ratio)
		# 面板只展示真正回收的部分，阵亡也能看到 30% 的回收成果。
		display_loot = scaled["basic"]
		display_advanced = scaled["advanced"]
		var progress := get_node_or_null("/root/Progress")
		if progress != null and payout_ratio > 0.0:
			meta_reward = int(round(float(resources) * 10.0 * talent_scavenge * payout_ratio))
			if success:
				xp_reward = 10 + kills * 2 + wave_index * 8
			if meta_reward > 0:
				progress.add_resources(meta_reward)
				meta_reward = progress.credit_gain(meta_reward)
			progress.add_materials(scaled["materials"])
			if xp_reward > 0:
				progress.add_xp(xp_reward)
	elif success:
		var progress_raid := get_node_or_null("/root/Progress")
		if progress_raid != null:
			var lift_bonus := 1.1 if via_switch else 1.0
			meta_reward = int(round(float(resources) * 10.0 * talent_scavenge
				* level.bonus_mul * lift_bonus))
			xp_reward = 10 + resources * 5 + (10 if via_switch else 0)
			# 先按原始数入账（add_resources 内部应用获取倍率），面板再显示实际到账额度。
			progress_raid.add_resources(meta_reward)
			meta_reward = progress_raid.credit_gain(meta_reward)
			progress_raid.add_materials(_banked_materials())
			progress_raid.add_xp(xp_reward)
		if level.power_on:
			bonus_note = "任务加成 +20%"
		if via_switch:
			bonus_note += (" · " if bonus_note != "" else "") + "拉闸撤离 +10%"
	else:
		display_loot = {}
		display_advanced = {}
	var stats := {
		"kills": kills,
		"damage": int(round(damage_dealt)),
		"shots": shots_fired,
		"hits": shots_hit,
		"time": run_elapsed,
	}
	hud.show_result(success, display_loot, display_advanced, meta_reward, xp_reward, bonus_note, stats)
	var end_sfx := get_node_or_null("/root/Sfx")
	if end_sfx != null:
		end_sfx.play_2d("extract_success" if success else "mission_fail", -5.0)
		if end_sfx.has_method("set_bgm_state"):
			end_sfx.set_bgm_state("explore" if success else "menu", 1.8)
	doll.set_physics_process(false)
	if doll.weapon_rig != null:
		doll.weapon_rig.set_process(false)
	hud.set_hint("按 R 重新开始 · ESC 返回基地")
	run_finished.emit(success, stats)


func _on_player_damaged(_amount: int, armor_damage: int, hp_damage: int, pos: Vector2) -> void:
	_bgm_combat_hold = 8.0
	feedback_system.on_player_damaged(armor_damage, hp_damage, pos)


func _on_player_died() -> void:
	if waves_mode:
		_finish_run(false, false, WAVES_EARLY_RATIO, "阵亡 · 信用点/材料按 30% 回收")
	else:
		_finish_run(false)


## 浪潮模式：每 5 波弹一次撤离窗口，同时刷新补给。
## --- 浪潮与歌利亚狂潮（委托至 WaveSystem2D）----------------------------------

func _build_waves_exit_popup() -> void:
	wave_system.build_exit_popup()


func _update_waves(delta: float) -> void:
	wave_system.update(delta)


func _begin_wave(index: int) -> void:
	wave_system.begin_wave(index)


func _wave_enemy_count(index: int) -> int:
	return WAVE_SYSTEM.enemy_count(index)


func wave_stat_scale(index: int) -> float:
	return WAVE_SYSTEM.stat_scale(index)


func waves_tracking_active() -> bool:
	return wave_system.tracking_active()


func _on_wave_cleared() -> void:
	wave_system.on_wave_cleared()


func wave_loot_scale() -> float:
	return wave_system.loot_scale()


func _loot_amount(value: int) -> int:
	return LOOT_SYSTEM.scale_amount(value, wave_loot_scale())


func _loot_chance(chance: float) -> float:
	return LOOT_SYSTEM.scale_chance(chance, wave_loot_scale())


func _wave_spawn_points() -> Array[Vector2]:
	return wave_system.spawn_points()


func _wave_enemy_kind(index: int) -> StringName:
	return wave_system.enemy_kind(index)


func _spawn_wave_enemy(entry: Dictionary) -> void:
	wave_system.spawn_enemy(entry)


func _on_waves_retreat() -> void:
	wave_system.on_retreat()


func _on_waves_extract() -> void:
	wave_system.on_extract()


func _on_waves_continue() -> void:
	wave_system.on_continue()


func _apply_debug_visual_mode() -> void:
	debug_overlay.visible = debug_visual_mode
	if vision != null:
		vision.set_debug(debug_visual_mode)
	else:
		canvas_modulate.color = Color(1, 1, 1) if debug_visual_mode else _ambient_color
	_update_debug_label()


func _update_debug_label() -> void:
	if not debug_visual_mode:
		return
	debug_label.text = "俯视像素 2D — F7 照明 / F8 碰撞体\nFPS %d   Zoom %.1f\nPlayer %s   Dir %d\nEnemies %d   资源 %d" % [
		Engine.get_frames_per_second(),
		camera.zoom.x,
		Vector2i(doll.global_position),
		doll.direction,
		enemies.size(),
		resources,
	]
