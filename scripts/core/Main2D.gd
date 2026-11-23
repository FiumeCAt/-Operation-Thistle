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

const ZOOM := 0.95
## 100% 现在对应旧版 50% 的镜头缩放，基础视野翻倍；镜内放大由 ScopeSight2D 独立处理。
## 镜头上移，让玩家在画面里偏下，前方视野更大。
const CAMERA_LIFT := 44.0
const ADS_ZOOM_SPEED := 6.0
const SPREAD_MODEL := preload("res://scripts/combat/SpreadModel.gd")
const BALLISTICS_MODEL := preload("res://scripts/combat/BallisticsModel.gd")
## 开镜散布收紧系数改为按弹种配置（AmmoData.ads_spread_mul），此处不再全局固定。
## 连发累积：开镜（ADS）时每发增长更慢；换弹/切枪期间回落更快（单一来源：SpreadModel）。
const BURST_ADS_GROWTH_MUL := SPREAD_MODEL.BURST_ADS_GROWTH_MUL
const BURST_RECOVERY_BUSY_MUL := SPREAD_MODEL.BURST_RECOVERY_BUSY_MUL
## 瞄准时镜头向准心方向前探，真正看清瞄准方向（仅非高倍镜使用）。
const ADS_LOOK_AHEAD := 210.0
const ADS_LOOK_SMOOTH := 8.0
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
## pixelfx 枪口特效的原点是枪口下方的地面参考点；插件的 height 默认 26px，
## 所以节点要沿枪管下移 26px，闪光才会正好落在枪口上。
const MUZZLE_FX_GROUND := 26.0
const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
## 新脚本用 preload 引用，避免依赖编辑器生成的全局类缓存。
const HIT_FX := preload("res://scripts/fx/HitFX2D.gd")
const PLAYER_BULLET := preload("res://scripts/fx/PlayerBullet2D.gd")
const COMBAT_FX_WARMUP := preload("res://scripts/fx/CombatFxWarmup.gd")
const VISION_FOG := preload("res://scripts/fx/VisionFog2D.gd")
const LASER_SIGHT := preload("res://scripts/fx/LaserSight2D.gd")
const SCOPE_SIGHT := preload("res://scripts/fx/ScopeSight2D.gd")
const HEARING_INDICATOR := preload("res://scripts/fx/HearingIndicator2D.gd")
const LOOT_SYSTEM := preload("res://scripts/systems/LootSystem2D.gd")
const WAVE_SYSTEM := preload("res://scripts/systems/WaveSystem2D.gd")
const INTERACTION_SYSTEM := preload("res://scripts/systems/InteractionSystem2D.gd")
const COMBAT_SYSTEM := preload("res://scripts/systems/CombatSystem2D.gd")
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
const HINT_DEFAULT := "WASD 移动 · 左键开火 · 右键瞄准 · R 换弹 · X 收/拔枪 · TAB 背包 · Alt+滚轮 缩放 · E 交互"

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
var enemies: Array[Enemy2D] = []
## 2D 天赋：枪械精度倍率与撤离资源倍率，在行动开始时从 Progress 读取。
var talent_accuracy := 1.0
var talent_scavenge := 1.0
## 设置项：关闭后所有命中/开火抖动都不再累积。
var screen_shake := true
## 设置项：命中顿帧默认关闭；shake_scale 为开火震动幅度（1.0 = 100%，上限 10 倍）。
var hitstop_enabled := false
var shake_scale := 1.0
## 设置项：命中特写层级 2 完整 / 1 减弱 / 0 关闭。
var hit_fx_level := 1
## 设置项：弹道线条（枪口到弹丸的长曳光线）默认开启；关闭后仅隐藏长线，弹丸实体与飞行/结算不变。
var bullet_trail_enabled := true
## 滑杆 100% 对应旧版 500% 的实际震动强度，统一在这里换算。
const SHAKE_SCALE_BASE := 5.0

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
var _shake := 0.0
## 镜头旋转抖动与衰减速度：不同武器（霰弹/狙击/冲锋枪）套不同档位。
var _shake_peak := 0.0
var _shake_roll_deg := 0.2
var _shake_decay := 32.0
var _shake_roll := 0.0
## 命中顿帧：命中/击杀瞬间把 time_scale 压到很低，让打击“咬住”。
var _hitstop_timer: Timer
## 受击红屏闪一下，强度随掉血量变化。
var _hurt_flash_rect: ColorRect
var _ads_t := 0.0
## 开镜期间是否由本脚本临时关闭了镜头位置平滑；松开瞄准后只恢复自己关掉的那一次。
var _ads_smoothing_off := false
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
## 枪口纯函数特效复用一个节点：无粒子实例，重播没有创建 spike。
var _muzzle_fx: PixelFx2D
var _muzzle_stop_ms := 0
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


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("08090a"))
	hud.setup(self)
	hud.return_requested.connect(_return_to_base)
	hud.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	loot_system = LOOT_SYSTEM.new()
	loot_system.setup(fx_layer, level, doll, hud, wave_loot_scale, _play_sfx, _add_loot)
	wave_system.setup(self, sort_layer, level, doll, hud, enemies,
		func() -> bool: return run_state == RunState.ACTIVE,
		_on_enemy_died, _play_sfx)
	wave_system.wave_changed.connect(func(w: int, state: String) -> void: wave_changed.emit(w, state))
	wave_system.finish_requested.connect(_finish_run)
	interaction_system.setup(level, doll, hud,
		func() -> bool: return run_state == RunState.ACTIVE,
		func() -> bool: return waves_mode,
		func() -> int: return resources,
		_default_hint, _play_sfx)
	interaction_system.container_search_requested.connect(_search_container)
	interaction_system.extract_requested.connect(func(via_switch: bool) -> void: _finish_run(true, via_switch))
	combat_system.setup(self, doll, fx_layer, reticle, enemies,
		func() -> bool: return run_state == RunState.ACTIVE,
		func() -> float: return _ads_t,
		func() -> float: return talent_accuracy,
		func() -> bool: return bullet_trail_enabled,
		func() -> int: return hit_fx_level,
		_play_muzzle_fx, _add_shake, _hitstop, _play_sfx)
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
	_build_hit_feedback()

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
	var bounds: Rect2 = level.camera_bounds()
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)
	camera.zoom = Vector2(ZOOM, ZOOM)
	doll.global_position = level.player_spawn
	camera.global_position = doll.global_position
	doll.bounds = Rect2(40, 40, size.x - 80, size.y - 80)
	doll.aim_enabled = true
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
	vision.setup(doll, level, canvas_modulate)
	laser_sight = LASER_SIGHT.new()
	laser_sight.name = "LaserSight2D"
	fx_layer.add_child(laser_sight)
	laser_sight.setup(self, doll)
	# 声纹：脚下细环 + 附近移动敌人的方位弧，便于察觉视野外/背后的敌人。
	hearing = HEARING_INDICATOR.new()
	hearing.name = "HearingIndicator2D"
	add_child(hearing)
	hearing.setup(self, doll)
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
	debug_overlay.visible = debug_visual_mode
	_warm_muzzle_fx()
	_warm_combat_fx()


## Alt 作为「整体视角缩放」修饰键；运行时注册，避免依赖 project.godot 的输入表。
func _ensure_view_zoom_action() -> void:
	if InputMap.has_action("view_zoom"):
		return
	InputMap.add_action("view_zoom")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ALT
	InputMap.action_add_event("view_zoom", key)


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
	if rig_style == "" or rig_style == "off":
		return
	doll.enable_rig(rig_style)


## 把 2D 天赋树等级应用到本局角色/武器；升级从下一次行动开始生效。
func _apply_talents() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	var hp_level := int(progress.talent_2d_level(&"hp"))
	doll.hp_max = 100 + hp_level * 15
	doll.hp = doll.hp_max
	var move_mul := 1.0 + float(progress.talent_2d_level(&"move")) * 0.04
	doll.walk_speed *= move_mul
	doll.sprint_speed *= move_mul
	talent_accuracy = pow(0.94, float(progress.talent_2d_level(&"gun")))
	talent_scavenge = 1.0 + float(progress.talent_2d_level(&"scavenge")) * 0.1
	# 屏幕震动：设置里关闭后不再累积抖屏。
	screen_shake = bool(progress.data.get("screen_shake", true))
	hitstop_enabled = bool(progress.data.get("hitstop_enabled", false))
	shake_scale = clampf(float(progress.data.get("shake_scale", 100.0)) / 100.0, 0.0, 10.0) \
		* SHAKE_SCALE_BASE
	hit_fx_level = clampi(int(progress.data.get("hit_fx_level", 1)), 0, 2)
	bullet_trail_enabled = bool(progress.data.get("bullet_trail_enabled", true))
	_apply_bullet_trail_setting()
	# 整体视角缩放档位是持久设置；Alt+滚轮调整后立即保存。
	view_zoom_pct = clampf(
		roundf(float(progress.data.get("view_zoom", 100)) / 10.0) * 10.0,
		VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)
	_view_zoom_visual = view_zoom_pct
	# 护甲：基础存档值 + 护甲组件 + 护甲强化天赋，进入行动时补满。
	var armor_mods := ModDB.modifiers(progress.armor_mods_2d(), true)
	doll.armor_max = maxi(10, int(progress.data.get("armor_max", 100))
		+ int(armor_mods["armor_max_add"]))
	doll.armor_max += int(progress.talent_2d_level(&"armor")) * 20
	doll.armor = doll.armor_max
	doll.armor_level = int(progress.data.get("armor_level", 1)) \
		+ int(armor_mods["armor_level_add"])
	doll.armor_absorb_bonus = float(armor_mods["absorb_add"])
	doll.walk_speed *= float(armor_mods["move_mul"])
	doll.sprint_speed *= float(armor_mods["move_mul"])
	if doll.weapon_rig != null:
		doll.weapon_rig.reload_time_mul = pow(0.94, float(progress.talent_2d_level(&"reload")))
		doll.weapon_rig.hold_reload_enabled = progress.talent_2d_level(&"loading") > 0
		var reserve_mul := 1.0 + float(progress.talent_2d_level(&"reserve")) * 0.2
		doll.weapon_rig.apply_reserve_talent(reserve_mul)
	hud.set_hp(doll.hp, doll.hp_max)
	hud.set_armor(doll.armor, doll.armor_max)


## 设置页关闭时只刷新画面相关项，不重跑天赋/护甲，避免顺手把血补满。
func _on_settings_applied() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress == null:
		return
	screen_shake = bool(progress.data.get("screen_shake", true))
	hitstop_enabled = bool(progress.data.get("hitstop_enabled", false))
	shake_scale = clampf(float(progress.data.get("shake_scale", 100.0)) / 100.0, 0.0, 10.0) \
		* SHAKE_SCALE_BASE
	hit_fx_level = clampi(int(progress.data.get("hit_fx_level", 1)), 0, 2)
	bullet_trail_enabled = bool(progress.data.get("bullet_trail_enabled", true))
	_apply_bullet_trail_setting()
	view_zoom_pct = clampf(
		roundf(float(progress.data.get("view_zoom", 100)) / 10.0) * 10.0,
		VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)


## 立即套用弹道线条开关：只隐藏枪口到弹丸的长线，弹丸实体与命中不受影响。
func _apply_bullet_trail_setting() -> void:
	if fx_layer == null:
		return
	var bullets: Array = []
	for child in fx_layer.get_children():
		if child is PlayerBullet2D:
			bullets.append(child)
		elif child.has_meta("bullet_trail"):
			child.visible = bullet_trail_enabled
	# 单独处理子弹：重新开启时可能需要在子弹当前位置补建线条。
	for bullet in bullets:
		bullet.set_trail_visible(bullet_trail_enabled)


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
	# 右键瞄准只负责前探视野与散布收紧；整体缩放由 Alt+滚轮独立控制。
	var want_ads := 1.0 if (doll.ads and run_state == RunState.ACTIVE) else 0.0
	var ads_speed := ADS_ZOOM_SPEED
	if doll.weapon_rig != null:
		ads_speed *= doll.weapon_rig.ads_speed_mul
	var dbg_progress := get_node_or_null("/root/Progress")
	if dbg_progress != null:
		ads_speed *= float(dbg_progress.debug_mul("ads"))
	_ads_t = move_toward(_ads_t, want_ads, ads_speed * delta)
	combat_system.update(delta)
	# 高倍镜开镜时主镜头保持腰射时的缩放与位置：任何拉宽/前探都会在鼠标不动时
	# 改变准心下的世界点（瞄准箱子却看到旁边的门）。视野收益改由 40 米基础视野、
	# 瞄具视野锥加宽与 4× 镜窗放大共同提供。
	scope_magnification = 1.0
	if doll.weapon_rig != null and not doll.weapon_rig.has_scope_sight:
		scope_magnification = doll.weapon_rig.aim_zoom_mul
	if scope_sight != null:
		reticle.visible = not scope_sight.should_hide_reticle()
	if waves_mode:
		_update_waves(delta)
	_view_zoom_visual = move_toward(_view_zoom_visual, view_zoom_pct, VIEW_ZOOM_LERP * delta)
	# 倍镜接口默认 1.0；接上倍镜后只在 ADS 过渡里生效。
	var scope_mul := lerpf(1.0, scope_magnification, _ads_t)
	var zoom := ZOOM * (_view_zoom_visual / 100.0) * scope_mul
	if absf(camera.zoom.x - zoom) > 0.001:
		camera.zoom = Vector2(zoom, zoom)

	var look := Vector2.ZERO
	if _ads_t > 0.01:
		var scoped: bool = doll.weapon_rig != null and doll.weapon_rig.has_scope_sight
		if scoped:
			# 高倍镜：主镜头不做任何前探，镜头与腰射完全一致，准心下的世界点不会变。
			_ads_look = Vector2.ZERO
		else:
			var aim_dir := Vector2.RIGHT
			var raw_aim := doll.aim_target - doll.global_position
			if doll.weapon_rig != null:
				aim_dir = doll.weapon_rig.get_barrel_direction()
			if aim_dir.length_squared() < 0.0001:
				aim_dir = raw_aim.normalized()
			_ads_look = _ads_look.lerp(
				aim_dir.normalized(), clampf(delta * ADS_LOOK_SMOOTH, 0.0, 1.0))
			var look_ahead := ADS_LOOK_AHEAD * scope_magnification
			look = _ads_look * look_ahead * _ads_t
	else:
		_ads_look = Vector2.ZERO

	# 相机跟随按「屏幕像素」取整，避免角色和场景在半像素位置上被重采样而发虚。
	var snap := 1.0 / maxf(zoom, 0.001)
	var target := Vector2(
		roundf((doll.global_position.x + look.x + _recoil_cam.x) / snap) * snap,
		roundf((doll.global_position.y - CAMERA_LIFT + look.y + _recoil_cam.y) / snap) * snap,
	)
	if _shake > 0.0:
		_shake = maxf(_shake - delta * _shake_decay, 0.0)
		target += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		var ratio := clampf(_shake / maxf(_shake_peak, 0.001), 0.0, 1.0)
		_shake_roll = randf_range(-1.0, 1.0) * deg_to_rad(_shake_roll_deg) * ratio
		if _shake <= 0.0:
			_shake_roll = 0.0
	# 瞄准期间关闭镜头位置平滑：平滑会让准心下的世界点持续“滑行”，
	# 在 4× 镜里被放大成明显的瞄准偏移。腰射时恢复原有平滑，走位手感不变。
	if _ads_t > 0.01 and camera.position_smoothing_enabled:
		camera.position_smoothing_enabled = false
		camera.reset_smoothing()
		_ads_smoothing_off = true
	elif _ads_t < 0.01 and _ads_smoothing_off:
		camera.position_smoothing_enabled = true
		camera.reset_smoothing()
		_ads_smoothing_off = false
	camera.global_position = target
	camera.rotation = _shake_roll + _recoil_roll
	if _muzzle_fx != null and is_instance_valid(_muzzle_fx) and _muzzle_fx.is_playing():
		# 枪口特效每帧贴回当前枪口；节点原点是枪口下方 26px 的地面参考点。
		var barrel_angle := 0.0
		if doll.weapon_rig != null:
			barrel_angle = doll.weapon_rig.get_barrel_direction().angle()
		_muzzle_fx.global_position = doll.get_muzzle_position() \
			+ Vector2(0.0, MUZZLE_FX_GROUND).rotated(barrel_angle)
		_muzzle_fx.global_rotation = barrel_angle
		if Time.get_ticks_msec() >= _muzzle_stop_ms:
			_muzzle_fx.stop()
	if mouse_aim_enabled:
		doll.aim_target = get_global_mouse_position()
	_update_hud(delta)
	if debug_visual_mode:
		_label_timer += delta
		if _label_timer >= 0.25:
			_label_timer = 0.0
			_update_debug_label()


func _update_hud(delta: float) -> void:
	hud.set_hp(doll.hp, doll.hp_max)
	hud.set_armor(doll.armor, doll.armor_max)
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


## 枪口用 BAKED 模式。烘焙已交给主菜单/局内的 CombatFxWarmup 分摊，
## 这里只创建节点，避免进局瞬间同步烘焙 50 多帧造成半秒级卡顿。
func _warm_muzzle_fx() -> void:
	_muzzle_fx = Shot2D.pixel_fx(fx_layer, "projectiles/muzzle-pistol",
		Vector2.ZERO, 0.0, 60, 1.0, PixelFx2D.Mode.BAKED)
	if _muzzle_fx == null:
		return
	_muzzle_fx.free_when_done = false
	_muzzle_fx.modulate.a = 0.0
	_muzzle_fx.stop()


func _play_muzzle_fx(pos: Vector2, angle: float) -> void:
	if _muzzle_fx == null or not is_instance_valid(_muzzle_fx):
		_warm_muzzle_fx()
		if _muzzle_fx == null:
			return
	_muzzle_fx.global_position = pos + Vector2(0.0, MUZZLE_FX_GROUND).rotated(angle)
	_muzzle_fx.rotation = angle
	_muzzle_fx.play()
	_muzzle_fx.modulate.a = 1.0
	# 保留前 0.45 秒的闪光/烟，之后的烟不再占资源。
	_muzzle_stop_ms = Time.get_ticks_msec() + 450


## 开局预热命中/击杀特效与命中采样：把首次战斗的一次性加载成本提前分摊掉。
func _warm_combat_fx() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("warm_impact_samples"):
		sfx.warm_impact_samples()
	var warmup := COMBAT_FX_WARMUP.new()
	warmup.name = "CombatFxWarmup"
	add_child(warmup)
	var variants := HIT_FX.impact_variants()
	variants.push_front({"id": "projectiles/muzzle-pistol", "opts": {}})
	warmup.setup(variants)
	_warm_damage_fonts()


## 伤害跳字使用 15/17/19/21 号字与 4px 描边，首次出现才光栅化会卡一下；
## 先在不可见状态下画一帧，把字形与描边预热进字体缓存。
func _warm_damage_fonts() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = -8
	add_child(layer)
	var row := HBoxContainer.new()
	row.modulate.a = 0.0
	layer.add_child(row)
	for size in [15, 17, 19, 21, 23]:
		var label := Label.new()
		label.text = "-0123456789"
		label.add_theme_font_override("font", PixelUI.FONT)
		label.add_theme_font_size_override("font_size", size)
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.02, 0.95))
		label.add_theme_constant_override("outline_size", 4)
		row.add_child(label)
	await get_tree().process_frame
	if is_instance_valid(layer):
		layer.queue_free()


func _on_weapon_fired(muzzle: Vector2, dir: Vector2) -> void:
	combat_system.on_weapon_fired(muzzle, dir)


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


func _play_sfx(kind: String, volume_db := 0.0) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play_2d(kind, volume_db, randf_range(0.96, 1.04))


func add_shake(amount: float) -> void:
	_add_shake(amount)


## 顿帧计时器与受击红屏只建一次，避免每次命中都新建节点。
func _build_hit_feedback() -> void:
	_hitstop_timer = Timer.new()
	_hitstop_timer.one_shot = true
	_hitstop_timer.ignore_time_scale = true
	_hitstop_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_hitstop_timer.timeout.connect(_end_hitstop)
	add_child(_hitstop_timer)

	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_hurt_flash_rect = ColorRect.new()
	_hurt_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_flash_rect.color = Color(0.72, 0.04, 0.04, 0.0)
	layer.add_child(_hurt_flash_rect)
	_hurt_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 命中/击杀的短暂顿帧：把全局时间压到 12%，用真实时间计时恢复。
func _hitstop(seconds: float) -> void:
	if seconds <= 0.0 or _hitstop_timer == null or not hitstop_enabled:
		return
	# 无头测试不需要画面顿帧，避免拖慢物理步进与测试时长。
	if DisplayServer.get_name() == "headless":
		return
	Engine.time_scale = 0.12
	_hitstop_timer.start(maxf(_hitstop_timer.time_left, seconds))


func _end_hitstop() -> void:
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## 玩家受击：血量越掉越多，红屏越明显；同时带一点抖动。
func _flash_hurt(hp_damage: int) -> void:
	if _hurt_flash_rect == null:
		return
	var alpha := clampf(0.10 + float(hp_damage) / 160.0, 0.10, 0.34)
	_hurt_flash_rect.color = Color(0.72, 0.04, 0.04, alpha)
	var tw := _hurt_flash_rect.create_tween()
	tw.tween_property(_hurt_flash_rect, "color:a", 0.0, 0.34)


func _add_shake(amount: float, roll_deg := 0.18, decay := 32.0) -> void:
	if not screen_shake:
		return
	amount *= shake_scale
	roll_deg *= shake_scale
	if amount <= 0.001:
		return
	var stronger := amount >= _shake
	_shake = maxf(_shake, amount)
	if stronger:
		_shake_peak = maxf(_shake, 0.001)
		_shake_roll_deg = roll_deg
		_shake_decay = decay


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
			_set_view_zoom(view_zoom_pct + VIEW_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_view_zoom(view_zoom_pct - VIEW_ZOOM_STEP)
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
		KEY_F9:
			get_tree().change_scene_to_file("res://scenes/core/Main.tscn")
			get_viewport().set_input_as_handled()


## 整体视角缩放：夹在 20%–200% 并对齐 10% 档位。
func _set_view_zoom(value: float) -> void:
	view_zoom_pct = clampf(
		roundf(value / VIEW_ZOOM_STEP) * VIEW_ZOOM_STEP,
		VIEW_ZOOM_MIN, VIEW_ZOOM_MAX)
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
	if _hitstop_timer != null:
		_hitstop_timer.stop()
	Engine.time_scale = 1.0
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
	doll.set_physics_process(false)
	if doll.weapon_rig != null:
		doll.weapon_rig.set_process(false)
	hud.set_hint("按 R 重新开始 · ESC 返回基地")
	run_finished.emit(success, stats)


func _on_player_damaged(_amount: int, armor_damage: int, hp_damage: int, pos: Vector2) -> void:
	# 护甲与生命同时承伤时分开飘字，玩家能直接看出哪一部分被打掉了。
	if armor_damage > 0:
		DamageNumber2D.spawn(fx_layer, pos + Vector2(-16, -6), armor_damage,
			Color(0.45, 0.72, 1.0), "armor")
	if hp_damage > 0:
		DamageNumber2D.spawn(fx_layer, pos + Vector2(12, 4), hp_damage,
			Color(1.0, 0.42, 0.38), "flesh", true)
		# 真正掉血才红屏 + 抖屏，纯破甲只飘蓝字，避免一直闪。
		_flash_hurt(hp_damage)
		_add_shake(2.2, 0.3, 24.0)
	hud.set_armor(doll.armor, doll.armor_max)


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
		canvas_modulate.color = Color(1, 1, 1) if debug_visual_mode else Color(0.9, 0.9, 0.92)
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
