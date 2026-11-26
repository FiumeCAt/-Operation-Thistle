extends CharacterBody2D
class_name Doll2D

## 4 向角色，图集 16 行 × 4 帧：
##   0-3   站立 idle_0..3（下 / 上 / 左 / 右）
##   4-7   行走 walk_0..3
##   8-11  跑步 run_0..3
##   12-15 瞄准 aim_0..3
## 默认使用 256 px 身高版本（与 1024 母版同比例导出），可通过 configure() 切换。
## 整身图集拆成「无头身体」与「独立头部」两张图，头部才能独立绕脖子摆动。
const UNITS := preload("res://scripts/core/GameUnits.gd")
const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const RIG_V2 := preload("res://scripts/actors/DollRigV2.gd")
const BODY_SHEET := preload("res://assets/art/characters/doll_b/lod/doll_lod_256_body.png")
const HEAD_SHEET := preload("res://assets/art/characters/doll_b/lod/doll_lod_256_head.png")
const LOD_BODY := "res://assets/art/characters/doll_b/lod/doll_lod_%d_body.png"
const LOD_HEAD := "res://assets/art/characters/doll_b/lod/doll_lod_%d_head.png"
const LOD_SHEET := "res://assets/art/characters/doll_b/lod/doll_lod_%d.png"
const DEFAULT_BODY_PX := 256
const WORLD_BODY := UNITS.DOLL_WORLD_HEIGHT_PX  # 角色在世界里的身高（2 格）
const FEET_RATIO := 0.95
const COLUMNS := 4
const DIRECTIONS := 4
## 4 向角色图集行契约（Phase 7A 兼容 16 行旧图集与 24 行 Phase 7B 新图集）：
##   0-3   站立 idle_0..3（下 / 上 / 左 / 右）
##   4-7   行走 walk_0..3
##   8-11  跑步 run_0..3
##   12-15 瞄准 aim_0..3
##   16-19 受击 hurt_0..3（可选，图集 ≥ 20 行时自动注册）
##   20-23 翻滚 dodge_0..3（可选，图集 ≥ 24 行时自动注册）
const ANIM_BLOCKS := {"idle": 0, "walk": 4, "run": 8, "aim": 12, "hurt": 16, "dodge": 20}
const DODGE_FPS := 13.3
const HURT_FPS := 12.0
## 4 帧一循环；行走约 0.38 秒一圈，跑步约 0.27 秒一圈。
const WALK_FPS := 10.4
const RUN_FPS := 14.8
## 4 帧循环的起伏：接触帧踩实下沉，过渡帧回到基准高度。
## 只向下沉，不向上抬，避免双脚离地出现悬空感。
const BOB := [1.2, 0.0, 1.2, 0.0]

## 头部独立层：头部图集是整帧尺寸，绕脖子支点（帧宽 48.7%、帧高 29.2%）随鼠标左右摆。
## 摆头会在脖子处产生接缝，暂时关闭，让头始终跟着身体帧走。
const HEAD_MOTION_ENABLED := false
const HEAD_NECK_UV := Vector2(0.487, 0.292)
const HEAD_MAX_TILT := 0.18
const HEAD_TILT_SPEED := 9.0
## 头部横向位移（占帧宽比例），让摆头在像素风下也看得出来。
const HEAD_MAX_SHIFT := 0.010
## 背后武器挂点（按角色世界身高归一化，不同朝向侧向偏移不同）。
const WEAPON_ANCHOR := {
	0: Vector2(0.0, -0.58),
	1: Vector2(0.0, -0.58),
	2: Vector2(0.14, -0.56),
	3: Vector2(-0.14, -0.56),
}
## 收枪后武器在背后的摆放：斜跨、压暗、朝向随身体翻转。
const STOW_ROTATION := -0.62
const STOW_OFFSET := Vector2(0.0, 2.0)
const STOW_TINT := Color(0.78, 0.82, 0.90, 1.0)
## 右键瞄准时移速降到一半，换取更低散布和更远视野。
const ADS_SPEED_MUL := 0.5
## 翻滚战术躲闪默认参数（挂载 DollConfig .tres 时由资源覆写）。
const DODGE_DISTANCE_M := 3.2
const DODGE_DURATION := 0.30
const DODGE_IFRAME_SEC := 0.20
const DODGE_COOLDOWN := 1.15
const DODGE_AFTERIMAGE_INTERVAL := 0.065
## 256px 默认 LOD 下脚底对齐的基准偏移；编辑器在 Doll2D.tscn 中微调 Body.offset 时自动保留差值。
const DEFAULT_BODY_OFFSET := Vector2(0.0, -144.0)

## 角色固定调优配置资源（resources/config/doll_default.tres）；未挂载时平滑回退上方 const 默认值。
@export var config: Resource
@export var walk_speed := 250.0
@export var sprint_speed := 380.0
@export var bounds := Rect2(72, 72, 1392, 1008)

@onready var body: AnimatedSprite2D = $Body

var direction := 0
var frame_size := Vector2i(160, 160)
var sheet: Texture2D = BODY_SHEET
var head_sheet: Texture2D = HEAD_SHEET
var _base_offset := 0.0
var _editor_body_offset_delta := Vector2.ZERO
var _neck_base := Vector2.ZERO
var _current_block := 0
## 受击闪白：短暂把整身染成冷白再退回原色。
var _hurt_flash := 0.0
## 开火后坐造成的整体位移（Body 与武器层一起后退，影子不动）。
var _flinch := Vector2.ZERO
## 头部跟随的目标点（世界坐标）；aim_enabled 打开时才生效。
var aim_target := Vector2.ZERO
var aim_enabled := false
## 右键瞄准状态（Main2D 读它来拉远镜头 / 收紧散布）。
var ads := false
var _head_frames := {}
var _head_enabled := true
var _head_pivot: Node2D
var _head: Sprite2D
var _weapon_mount: Node2D
var _weapon_sprite: Sprite2D
var _stow_base := Vector2.ZERO
## 2D 持枪表现（武器 + 手 + 枪口焰），由 equip_weapon_id() 创建。
var weapon_rig: WeaponRig2D
## 旧版实验模块化骨架（通过 --rig=normal/chibi 启用）。
var rig: DollRig2D
## Phase 7B 主力模块化像素骨骼（SubViewport 160×160 像素光栅化 + 二段腿 + 弹簧发/衣摆 + 眨眼）。
var rig_v2: DollRigV2
@export var use_modular_rig_v2 := true

## 生命值：受伤后短暂无敌，归零发 died 信号交给 Main2D 结算。
signal died
## 受击结算：总伤害 / 护甲吸收 / 实际掉血 / 世界坐标，用于飘字与 HUD。
signal damaged(amount: int, armor_damage: int, hp_damage: int, world_pos: Vector2)
## 开火转发：换枪会重建 WeaponRig2D，Main2D 只连这一条，换枪后伤害结算不会断。
signal shot_fired(muzzle: Vector2, dir: Vector2)
## 翻滚状态信号：供 Main2D / HUD / Phase 7 正式动画接入。
signal dodge_started(dir: Vector2)
signal dodge_ended

## 翻滚输入拦截回调（如背包/地图/结算界面打开时禁止 Space 触发翻滚）。
var dodge_input_blocked_fn: Callable = Callable()
## 可选特效父层（由 Main2D 注入 FXLayer；未注入时回退到父节点）。
var fx_layer: Node2D = null

var _dodge_t := 0.0
var _dodge_total := DODGE_DURATION
var _dodge_invuln_t := 0.0
var _dodge_cd := 0.0
var _dodge_cd_total := DODGE_COOLDOWN
var _dodge_dir := Vector2.RIGHT
var _dodge_afterimage_t := 0.0
## 翻滚天赋倍率（由 Main2D 按 dodge_dist / dodge_cd 天赋写入）。
var dodge_dist_mul := 1.0
var dodge_cd_mul := 1.0
var _saved_collision_layer := 2
var _saved_collision_mask := 1
var _dodge_collision_overridden := false
var _base_body_scale := Vector2.ONE

var hp := 100
var hp_max := 100
var base_hp_max := 100
var invuln := 0.0
## 护甲：优先吸收按减伤比例计算出的伤害；耐久耗尽后不再减伤。
@export var armor := 100
@export var armor_max := 100
var base_armor_max := 100
var _base_vitals_set := false
var _applied_hp_mul := 1.0
var _applied_armor_mul := 1.0
var _hp_regen_acc := 0.0
var _armor_regen_acc := 0.0
## 护甲防御等级（RHA 体系：Lv1 = 30 / 3.0mm RHA，每级 +20 / +2.0mm RHA）。
@export var armor_level := 1
## 额外 RHA 护甲防御加值（0.1 mm 单位，供后续配件/天赋叠加）。
@export var armor_rha_bonus := 0.0
## 最低减伤率（护甲耐久耗尽后仍生效的保底减伤，由特定护甲组件或天赋提供，默认 0）。
@export var min_damage_reduction := 0.0
const ARMOR_BASE_REDUCTION := DAMAGE_MODEL.PLAYER_ARMOR_BASE_REDUCTION
## 减伤/吸收比例兼容常量与钝伤削减加成（开局由 Main2D 按护甲组件写入）。
const ARMOR_ABSORB_RATIO := DAMAGE_MODEL.PLAYER_ARMOR_ABSORB_RATIO
var armor_absorb_bonus := 0.0


func armor_rha() -> float:
	return DAMAGE_MODEL.player_base_rha(armor_level, armor_rha_bonus)


func effective_armor_rha() -> float:
	return DAMAGE_MODEL.effective_player_rha(armor, armor_max, armor_rha())

## 启用模块化骨架（"v2" 启用 Phase 7B 主力 Modular Doll Rig v2；"normal"/"chibi" 启用旧版实验骨架；"legacy" 退回图集）。
func enable_rig(rig_style: String = "normal") -> void:
	if rig_style == "v2":
		if rig != null:
			rig.queue_free()
			rig = null
		_enable_rig_v2()
		return
	if rig_style == "legacy":
		if rig_v2 != null:
			rig_v2.visible = false
		if rig != null:
			rig.queue_free()
			rig = null
		body.visible = true
		var old_sh := get_node_or_null("Shadow") as CanvasItem
		if old_sh != null:
			old_sh.visible = true
		return
	if rig_v2 != null:
		rig_v2.visible = false
	if rig != null:
		rig.queue_free()
	rig = DollRig2D.new()
	rig.name = "Rig"
	rig.height = WORLD_BODY
	rig.style = rig_style
	add_child(rig)
	body.visible = false


func _enable_rig_v2() -> void:
	if not ResourceLoader.exists(RIG_V2.PART_DIR + "head_front.png"):
		return
	if rig_v2 == null:
		rig_v2 = RIG_V2.new()
		rig_v2.name = "RigV2"
		add_child(rig_v2)
		rig_v2.footstep_planted.connect(_on_footstep_planted)
	rig_v2.visible = true
	body.visible = false
	var old_sh := get_node_or_null("Shadow") as CanvasItem
	if old_sh != null:
		old_sh.visible = false


func _on_footstep_planted(local_offset: Vector2, is_running: bool) -> void:
	var dust_parent: Node = fx_layer if (fx_layer != null and is_instance_valid(fx_layer)) else get_parent()
	if dust_parent != null and dust_parent.is_inside_tree():
		Shot2D.footstep_dust(dust_parent, global_position + local_offset, is_running)

func _cfg_float(prop: StringName, fallback: float) -> float:
	if config != null and prop in config:
		return float(config.get(prop))
	return fallback


func _cfg_bool(prop: StringName, fallback: bool) -> bool:
	if config != null and prop in config:
		return bool(config.get(prop))
	return fallback


func _cfg_vec2(prop: StringName, fallback: Vector2) -> Vector2:
	if config != null and prop in config:
		var val = config.get(prop)
		if val is Vector2:
			return val
	return fallback


func _cfg_color(prop: StringName, fallback: Color) -> Color:
	if config != null and prop in config:
		var val = config.get(prop)
		if val is Color:
			return val
	return fallback


func _step_bob(frame_idx: int) -> float:
	if config != null and &"step_bob_px" in config:
		var arr = config.get(&"step_bob_px")
		if arr is PackedFloat32Array and arr.size() > 0:
			return float(arr[mini(frame_idx, arr.size() - 1)])
	return float(BOB[mini(frame_idx, BOB.size() - 1)])


func _ready() -> void:
	add_to_group("actors")
	add_to_group("player")
	# 保留 Doll2D.tscn 中 Body.offset 相对默认 (-144) 的编辑器微调量，启动不再无条件丢弃。
	if body != null and not body.offset.is_equal_approx(Vector2.ZERO) \
			and not body.offset.is_equal_approx(DEFAULT_BODY_OFFSET):
		_editor_body_offset_delta = body.offset - DEFAULT_BODY_OFFSET
	_build_rig()
	frame_size = Vector2i(int(round(DEFAULT_BODY_PX * 1.25)), int(round(DEFAULT_BODY_PX * 1.25)))
	_apply_sheet(BODY_SHEET)
	_base_body_scale = Vector2.ONE * (WORLD_BODY / float(DEFAULT_BODY_PX))
	body.scale = _base_body_scale
	if use_modular_rig_v2:
		_enable_rig_v2()


func _exit_tree() -> void:
	if _dodge_collision_overridden:
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask
		_dodge_collision_overridden = false

## 切换到某一档素材：body_px 为该图集里角色的像素身高（供 LOD 对比与旧图集回退）。
func configure(body_px: int) -> void:
	if rig_v2 != null:
		rig_v2.visible = false
	body.visible = true
	var old_sh := get_node_or_null("Shadow") as CanvasItem
	if old_sh != null:
		old_sh.visible = true
	var split_body := LOD_BODY % body_px
	var split_head := LOD_HEAD % body_px
	var has_split := ResourceLoader.exists(split_body) and ResourceLoader.exists(split_head)
	var path := split_body if has_split else LOD_SHEET % body_px
	if not ResourceLoader.exists(path):
		push_warning("缺少 LOD 图集：" + path)
		return
	sheet = load(path)
	# 没拆过头的档位整张图都有头，独立头部层必须关掉，否则会出现两个头
	head_sheet = load(split_head) if has_split else sheet
	_head_enabled = has_split
	frame_size = Vector2i(int(round(body_px * 1.25)), int(round(body_px * 1.25)))
	_apply_sheet(sheet)
	_base_body_scale = Vector2.ONE * (WORLD_BODY / float(body_px))
	body.scale = _base_body_scale

func _apply_sheet(tex: Texture2D) -> void:
	body.sprite_frames = _build_frames(tex)
	_base_offset = -frame_size.y * (FEET_RATIO - 0.5) + _editor_body_offset_delta.y
	body.offset = Vector2(_editor_body_offset_delta.x, _base_offset)
	_build_head_frames()
	_layout_rig()
	_head.visible = _head_enabled
	body.play("idle_%d" % direction)
	body.stop()
	body.frame = 0
	body.speed_scale = 0.0
	_sync_head()

## 建立模块化节点：Body（无头身体）→ HeadPivot → Head（可独立摆动），外加背后武器挂点。
func _build_rig() -> void:
	_head_pivot = Node2D.new()
	_head_pivot.name = "HeadPivot"
	body.add_child(_head_pivot)

	_head = Sprite2D.new()
	_head.name = "Head"
	_head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_head.z_index = 1
	_head_pivot.add_child(_head)

	_weapon_mount = Node2D.new()
	_weapon_mount.name = "WeaponMount"
	add_child(_weapon_mount)

## 头部图集是整帧尺寸（只有头是实心的），逐帧建 AtlasTexture 保证和身体完全对齐。
func _build_head_frames() -> void:
	_head_frames.clear()
	if not _head_enabled:
		return
	var f := Vector2(frame_size)
	for row in ANIM_BLOCKS.size() * DIRECTIONS:
		for column in COLUMNS:
			var atlas := AtlasTexture.new()
			atlas.atlas = head_sheet
			atlas.region = Rect2(column * frame_size.x, row * frame_size.y, f.x, f.y)
			_head_frames["%d:%d" % [row, column]] = atlas

func _layout_rig() -> void:
	var f := Vector2(frame_size)
	var neck := Vector2(HEAD_NECK_UV.x * f.x, HEAD_NECK_UV.y * f.y)
	var neck_local := Vector2(
		neck.x - f.x * 0.5 + _editor_body_offset_delta.x,
		neck.y - f.y * 0.5 + _base_offset)
	_head_pivot.position = neck_local
	_neck_base = neck_local
	# 头部贴图是整帧大小：把整帧中心摆回身体贴图的位置，旋转支点即为脖子
	_head.position = Vector2(_editor_body_offset_delta.x, _base_offset) - neck_local
	_update_weapon_anchor()

func _sync_head() -> void:
	if _head == null or not _head_enabled:
		return
	var key := "%d:%d" % [_current_block + direction, body.frame]
	_head.texture = _head_frames.get(key)

## 瞄准朝鼠标方向倾斜并轻微侧移（只取水平分量，避免仰头穿帮）。
func _update_head_tilt(delta: float) -> void:
	if _head_pivot == null:
		return
	# 关闭时头完全跟随身体帧，不旋转、不横移，避免脖子处出现接缝
	if not _cfg_bool(&"head_motion_enabled", HEAD_MOTION_ENABLED):
		_head_pivot.rotation = 0.0
		_head_pivot.position.x = _neck_base.x
		return
	var ratio := 0.0
	if aim_enabled:
		var offset := aim_target - global_position
		if offset.length() > 2.0:
			ratio = clampf(offset.x / 120.0, -1.0, 1.0)
	var blend := clampf(_cfg_float(&"head_tilt_speed", HEAD_TILT_SPEED) * delta, 0.0, 1.0)
	_head_pivot.rotation = lerp_angle(
		_head_pivot.rotation, ratio * _cfg_float(&"head_max_tilt", HEAD_MAX_TILT), blend)
	var target_x := _neck_base.x + ratio * frame_size.x * _cfg_float(&"head_max_shift", HEAD_MAX_SHIFT)
	_head_pivot.position.x = move_toward(_head_pivot.position.x, target_x, frame_size.x * 0.02)

func _update_weapon_anchor() -> void:
	if _weapon_mount == null:
		return
	var anchor: Vector2 = WEAPON_ANCHOR.get(direction, Vector2(0.0, -0.58))
	_weapon_mount.position = anchor * WORLD_BODY
	# 正面视角时武器在身体后面，背面/侧面视角时压在身体上层
	_weapon_mount.z_index = -1 if direction == 0 else 1
	if _weapon_sprite != null:
		_weapon_sprite.flip_v = direction == 2

## 背后武器挂载：后续换枪只需要把美术资源传进来。
func equip_weapon(tex: Texture2D, offset := Vector2.ZERO, scale_mul := 1.0) -> Sprite2D:
	if _weapon_sprite == null:
		_weapon_sprite = Sprite2D.new()
		_weapon_sprite.name = "Weapon"
		_weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_weapon_mount.add_child(_weapon_sprite)
	_weapon_sprite.texture = tex
	_weapon_sprite.position = offset
	_weapon_sprite.scale = Vector2.ONE * scale_mul
	return _weapon_sprite

func unequip_weapon() -> void:
	if _weapon_sprite != null:
		_weapon_sprite.visible = false
		_weapon_sprite.queue_free()
		_weapon_sprite = null

## 持枪表现：创建/切换武器表现层，数据复用 WeaponDB。
func equip_weapon_id(id: StringName) -> WeaponRig2D:
	unequip_weapon()
	if weapon_rig != null:
		weapon_rig.queue_free()
	weapon_rig = WeaponRig2D.new()
	weapon_rig.name = "WeaponRig"
	weapon_rig.weapon_id = id
	add_child(weapon_rig)
	weapon_rig.fired.connect(_on_weapon_fired)
	weapon_rig.holstered_changed.connect(_on_holstered_changed)
	weapon_rig.weapon_switched.connect(_on_weapon_switched)
	return weapon_rig


## 收枪时把当前枪的侧视图挂到背后；拔枪时立刻移除。
func _on_holstered_changed(stowed: bool) -> void:
	if stowed:
		_show_stowed_weapon()
	else:
		unequip_weapon()


## 收枪状态下换枪，背后挂点的模型要跟着换。
func _on_weapon_switched(_id: StringName) -> void:
	if weapon_rig != null and weapon_rig.is_holstered():
		_show_stowed_weapon()


func _show_stowed_weapon() -> void:
	if weapon_rig == null:
		return
	var tex := weapon_rig.get_side_texture()
	if tex == null:
		return
	_stow_base = _cfg_vec2(&"stow_offset", STOW_OFFSET)
	var sprite := equip_weapon(tex, _stow_base, weapon_rig.get_stow_scale())
	sprite.rotation = _cfg_float(&"stow_rotation", STOW_ROTATION)
	sprite.flip_v = direction == 2
	sprite.modulate = _cfg_color(&"stow_tint", STOW_TINT)
	_update_weapon_anchor()

## 开火时整个人向后一顿，配合武器后坐让开火有反馈，并联动 Modular Doll Rig v2 胸肩头与发梢震动。
func _on_weapon_fired(muzzle: Vector2, dir: Vector2) -> void:
	_flinch = -dir * _cfg_float(&"fire_flinch_px", 2.2)
	if rig_v2 != null and rig_v2.visible:
		var strength := 1.0
		if weapon_rig != null and weapon_rig.data != null:
			match weapon_rig.data.category:
				&"sniper": strength = 1.85
				&"shotgun": strength = 1.65
				&"dmr": strength = 1.35
				&"rifle": strength = 1.10
				&"smg": strength = 0.72
				_: strength = 0.85
		rig_v2.trigger_recoil(strength, dir)
	shot_fired.emit(muzzle, dir)

func get_muzzle_position() -> Vector2:
	if weapon_rig != null:
		return weapon_rig.get_muzzle_position()
	return _weapon_mount.global_position

func _build_frames(tex: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var rows_available := int(tex.get_height() / frame_size.y)
	for anim_name in ANIM_BLOCKS:
		var block: int = ANIM_BLOCKS[anim_name]
		# 老档位图集没有瞄准行时直接跳过，避免取到空帧
		if block + DIRECTIONS > rows_available:
			continue
		var fps := _cfg_float(&"walk_fps", WALK_FPS)
		var loop := true
		if anim_name == "run":
			fps = _cfg_float(&"run_fps", RUN_FPS)
		elif anim_name == "idle":
			fps = 1.0
		elif anim_name == "aim":
			fps = 4.0
		elif anim_name == "hurt":
			fps = HURT_FPS
			loop = false
		elif anim_name == "dodge":
			fps = DODGE_FPS
			loop = false
		for row in DIRECTIONS:
			var anim := "%s_%d" % [anim_name, row]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, fps)
			frames.set_animation_loop(anim, loop)
			var source_row := block + row
			for column in COLUMNS:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(
					column * frame_size.x,
					source_row * frame_size.y,
					frame_size.x,
					frame_size.y,
				)
				frames.add_frame(anim, atlas)
	frames.remove_animation("default")
	return frames

## 受伤：统一委托 DamageModel 按 RHA 护甲与耐久规则结算（未击穿主扣甲+钝伤，击穿直入血+少量甲损）。
func take_damage(amount: float, ap: float = 0.0) -> void:
	if invuln > 0.0 or _dodge_invuln_t > 0.0 or hp <= 0 or amount <= 0.0:
		return
	var res: Dictionary = DAMAGE_MODEL.resolve_player_damage(
		amount, ap, armor, armor_max, armor_level, armor_absorb_bonus, hp,
		armor_rha_bonus, min_damage_reduction
	)
	var total: int = int(res["total"])
	var armor_damage: int = int(res["armor_damage"])
	var hp_damage: int = int(res["hp_damage"])
	armor = int(res["new_armor"])
	hp = int(res["new_hp"])
	invuln = _cfg_float(&"hurt_invuln_sec", 0.12)
	_hurt_flash = _cfg_float(&"hurt_flash_sec", 0.16)
	var hurt_sfx := get_node_or_null("/root/Sfx")
	if hurt_sfx != null and hurt_sfx.has_method("play_player_damaged"):
		hurt_sfx.play_player_damaged(armor_damage, hp_damage, armor, -8.5)
	damaged.emit(total, armor_damage, hp_damage, global_position)
	if hp <= 0:
		died.emit()
	else:
		_flinch = Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
		if rig_v2 != null and rig_v2.visible:
			rig_v2.trigger_hurt(_facing_vector(direction))


func repair_armor(amount: int) -> void:
	armor = clampi(armor + amount, 0, armor_max)

func heal(amount: int) -> void:
	hp = mini(hp + amount, hp_max)


## 记录开局由天赋/装备决定的基础生命与护甲上限，并立即套用当前调试倍率。
func set_base_vitals(new_base_hp_max: int, new_base_armor_max: int, fill_current := true) -> void:
	base_hp_max = maxi(1, new_base_hp_max)
	base_armor_max = maxi(1, new_base_armor_max)
	_base_vitals_set = true
	_applied_hp_mul = 1.0
	_applied_armor_mul = 1.0
	hp_max = base_hp_max
	armor_max = base_armor_max
	var dbg_p := get_node_or_null("/root/Progress")
	if dbg_p != null and dbg_p.has_method("debug_mul"):
		sync_debug_vitals(float(dbg_p.debug_mul("hp_max_mul")), float(dbg_p.debug_mul("armor_max_mul")))
	if fill_current:
		hp = hp_max
		armor = armor_max
	else:
		hp = clampi(hp, 0, hp_max)
		armor = clampi(armor, 0, armor_max)


## 按调试倍率实时同步生命/护甲上限，并等比缩放/钳制当前值（存活时绝不因降倍率误杀）。
func sync_debug_vitals(hp_mul: float, armor_mul: float) -> void:
	var clean_hp := clampf(hp_mul, 0.1, 100.0)
	var clean_arm := clampf(armor_mul, 0.1, 100.0)
	if is_equal_approx(clean_hp, _applied_hp_mul) and is_equal_approx(clean_arm, _applied_armor_mul):
		return
	if not _base_vitals_set:
		base_hp_max = maxi(1, hp_max)
		base_armor_max = maxi(1, armor_max)
		_base_vitals_set = true
	if not is_equal_approx(clean_hp, _applied_hp_mul):
		var old_max := maxi(1, hp_max)
		var new_max := maxi(1, int(round(float(base_hp_max) * clean_hp)))
		if hp > 0:
			hp = clampi(int(round(float(hp) * (float(new_max) / float(old_max)))), 1, new_max)
		else:
			hp = 0
		hp_max = new_max
		_applied_hp_mul = clean_hp
	if not is_equal_approx(clean_arm, _applied_armor_mul):
		var old_amax := maxi(1, armor_max)
		var new_amax := maxi(1, int(round(float(base_armor_max) * clean_arm)))
		if armor > 0:
			armor = clampi(int(round(float(armor) * (float(new_amax) / float(old_amax)))), 0, new_amax)
		else:
			armor = 0
		armor_max = new_amax
		_applied_armor_mul = clean_arm


## 调试一键满血满甲：先同步上限倍率再补满当前值。
func full_restore() -> void:
	var dbg_p := get_node_or_null("/root/Progress")
	if dbg_p != null and dbg_p.has_method("debug_mul"):
		sync_debug_vitals(float(dbg_p.debug_mul("hp_max_mul")), float(dbg_p.debug_mul("armor_max_mul")))
	hp = hp_max
	armor = armor_max
	_hp_regen_acc = 0.0
	_armor_regen_acc = 0.0


## 调试生存步进：同步上限倍率并按绝对值（点/秒）累计生命与护甲自动恢复。
func step_debug_vitals(delta: float, dbg_progress: Node) -> void:
	if dbg_progress == null:
		return
	if dbg_progress.has_method("debug_mul"):
		sync_debug_vitals(
			float(dbg_progress.debug_mul("hp_max_mul")),
			float(dbg_progress.debug_mul("armor_max_mul")))
	if hp <= 0 or not dbg_progress.has_method("debug_flat"):
		_hp_regen_acc = 0.0
		_armor_regen_acc = 0.0
		return
	var hp_r := float(dbg_progress.debug_flat("hp_regen"))
	if hp_r > 0.0 and hp < hp_max:
		_hp_regen_acc += hp_r * delta
		var add_hp := int(floor(_hp_regen_acc))
		if add_hp > 0:
			_hp_regen_acc -= float(add_hp)
			heal(add_hp)
	else:
		_hp_regen_acc = 0.0
	var armor_r := float(dbg_progress.debug_flat("armor_regen"))
	if armor_r > 0.0 and armor < armor_max:
		_armor_regen_acc += armor_r * delta
		var add_armor := int(floor(_armor_regen_acc))
		if add_armor > 0:
			_armor_regen_acc -= float(add_armor)
			repair_armor(add_armor)
	else:
		_armor_regen_acc = 0.0


## 头部世界坐标：视野与感知系统以眼睛为原点，而不是脚下。
func head_position() -> Vector2:
	if _head_pivot != null:
		return _head_pivot.global_position + Vector2(0, -6)
	return global_position + Vector2(0, -WORLD_BODY * 0.82)

## ---- Phase 5：翻滚与战术躲闪（逻辑 + 占位表现 + Phase 7 正式动画挂口）----

## 翻滚位移速度曲线因子（u ∈ [0, 1]）：初段强劲爆发（1.75×），末段顺滑减速至 0.25×；
## 解析积分 ∫_0^1 f(u) du = 1.0，保证总位移精确等于 dodge_distance_m * TILE。
static func dodge_speed_factor(u: float) -> float:
	return lerpf(1.75, 0.25, clampf(u, 0.0, 1.0))


func is_dodging() -> bool:
	return _dodge_t > 0.0


func is_dodge_invuln() -> bool:
	return _dodge_invuln_t > 0.0


func can_dodge() -> bool:
	return hp > 0 and _dodge_t <= 0.0 and _dodge_cd <= 0.0


func get_dodge_cooldown_left() -> float:
	return _dodge_cd


func get_dodge_cooldown_ratio() -> float:
	if _dodge_cd <= 0.0:
		return 1.0
	return clampf(1.0 - _dodge_cd / maxf(_dodge_cd_total, 0.01), 0.0, 1.0)


func get_dodge_progress() -> float:
	if _dodge_t <= 0.0:
		return 0.0
	return clampf(1.0 - _dodge_t / maxf(_dodge_total, 0.01), 0.0, 1.0)


func try_dodge(dir_override := Vector2.ZERO) -> bool:
	if not can_dodge():
		return false
	var dir := dir_override
	if dir.length_squared() <= 0.001:
		dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if dir.length_squared() <= 0.001 and aim_enabled:
		var to_aim := aim_target - global_position
		if to_aim.length_squared() > 16.0:
			dir = to_aim
	if dir.length_squared() <= 0.001:
		dir = _facing_vector(direction)
	_dodge_dir = dir.normalized()
	_dodge_total = maxf(_cfg_float(&"dodge_duration", DODGE_DURATION), 0.08)
	_dodge_t = _dodge_total
	_dodge_invuln_t = clampf(_cfg_float(&"dodge_iframe_sec", DODGE_IFRAME_SEC), 0.0, _dodge_total)
	_dodge_cd_total = maxf(
		_cfg_float(&"dodge_cooldown", DODGE_COOLDOWN) * clampf(dodge_cd_mul, 0.35, 2.0),
		_dodge_total + 0.05)
	_dodge_cd = _dodge_cd_total
	_dodge_afterimage_t = 0.0
	ads = false
	direction = _direction_index(_dodge_dir)

	# 临时忽略敌人碰撞（移除 layer 2 / mask 2 防围死卡角），但严格保留墙体碰撞（mask 1 防穿墙）。
	if not _dodge_collision_overridden:
		_saved_collision_layer = collision_layer
		_saved_collision_mask = collision_mask
		_dodge_collision_overridden = true
	collision_layer = _saved_collision_layer & ~2
	collision_mask = (_saved_collision_mask & ~2) | 1

	# Phase 7 正式动画挂口：若未来图集存在 dodge_0..3 动画，自动切换播放；否则走占位倾斜+残影。
	var formal_anim := "dodge_%d" % direction
	if body != null and body.sprite_frames != null and body.sprite_frames.has_animation(formal_anim):
		body.play(formal_anim)
		var count := maxi(1, body.sprite_frames.get_frame_count(formal_anim))
		var base_fps := maxf(body.sprite_frames.get_animation_speed(formal_anim), 1.0)
		body.speed_scale = (float(count) / _dodge_total) / base_fps

	var dust_parent: Node = fx_layer if (fx_layer != null and is_instance_valid(fx_layer)) else get_parent()
	Shot2D.dodge_dust(dust_parent, global_position, _dodge_dir, false)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play_dodge"):
		sfx.play_dodge()
	_spawn_dodge_afterimage()
	dodge_started.emit(_dodge_dir)
	return true


func _end_dodge() -> void:
	_dodge_t = 0.0
	_dodge_invuln_t = 0.0
	if _dodge_collision_overridden:
		collision_layer = _saved_collision_layer
		collision_mask = _saved_collision_mask
		_dodge_collision_overridden = false
	if body != null:
		body.rotation = 0.0
		body.scale = _base_body_scale
	var dust_parent: Node = fx_layer if (fx_layer != null and is_instance_valid(fx_layer)) else get_parent()
	Shot2D.dodge_dust(dust_parent, global_position, _dodge_dir, true)
	dodge_ended.emit()


func _spawn_dodge_afterimage() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if rig_v2 != null and rig_v2.visible:
		var snap := rig_v2.capture_snapshot_texture()
		if snap != null:
			# RigCanvas 为 160×160 centered=false，偏移 (-80, -148) 换算为 Sprite2D centered=true 的 offset = (0, -68)
			var centered_off := Vector2(
				float(RIG_V2.CANVAS_SIZE.x) * 0.5 - RIG_V2.GROUND_ORIGIN.x,
				float(RIG_V2.CANVAS_SIZE.y) * 0.5 - RIG_V2.GROUND_ORIGIN.y
			)
			Shot2D.dodge_afterimage(parent, global_position, snap, null,
				centered_off, Vector2.ONE, 0.0, _dodge_invuln_t > 0.0)
			return
	if body == null or body.sprite_frames == null:
		return
	var anim_name := body.animation
	if not body.sprite_frames.has_animation(anim_name):
		return
	var body_tex := body.sprite_frames.get_frame_texture(anim_name, body.frame)
	var head_tex: Texture2D = _head.texture if (_head != null and _head_enabled) else null
	Shot2D.dodge_afterimage(parent, global_position, body_tex, head_tex,
		body.offset, body.scale, body.rotation, _dodge_invuln_t > 0.0)


func _facing_vector(dir_idx: int) -> Vector2:
	match dir_idx:
		0: return Vector2.DOWN
		1: return Vector2.UP
		2: return Vector2.LEFT
		_: return Vector2.RIGHT


func _physics_process(delta: float) -> void:
	if invuln > 0.0:
		invuln = maxf(invuln - delta, 0.0)
	if _dodge_cd > 0.0:
		_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	if _dodge_invuln_t > 0.0:
		_dodge_invuln_t = maxf(_dodge_invuln_t - delta, 0.0)
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		var flash_dur := maxf(_cfg_float(&"hurt_flash_sec", 0.16), 0.01)
		var t := _hurt_flash / flash_dur
		modulate = Color.WHITE.lerp(_cfg_color(&"hurt_flash_tint", Color(2.1, 0.62, 0.58)), t)
	elif _dodge_invuln_t > 0.0:
		modulate = Color(0.84, 1.18, 1.34, 0.88)
	elif modulate != Color.WHITE:
		modulate = Color.WHITE
	var dbg_progress := get_node_or_null("/root/Progress")
	if dbg_progress != null:
		step_debug_vitals(delta, dbg_progress)

	var dodge_blocked := dodge_input_blocked_fn.is_valid() and bool(dodge_input_blocked_fn.call())
	if not dodge_blocked and InputMap.has_action("dodge") and Input.is_action_just_pressed("dodge"):
		try_dodge()

	if is_dodging():
		var u := get_dodge_progress()
		var dist_px := maxf(
			_cfg_float(&"dodge_distance_m", DODGE_DISTANCE_M) * clampf(dodge_dist_mul, 0.5, 2.5),
			0.5) * UNITS.PIXELS_PER_METER
		var avg_speed := dist_px / maxf(_dodge_total, 0.05)
		var dodge_speed := avg_speed * dodge_speed_factor(u)
		if dbg_progress != null:
			dodge_speed *= float(dbg_progress.debug_mul("move"))
		velocity = _dodge_dir * dodge_speed
		move_and_slide()
		global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
		global_position.y = clampf(global_position.y, bounds.position.y, bounds.end.y)
		ads = false
		var has_formal := body != null and body.sprite_frames != null \
			and body.sprite_frames.has_animation("dodge_%d" % direction)
		if not has_formal and body != null:
			var arch := sin(PI * u)
			var lean_sign := 1.0 if _dodge_dir.x >= 0.0 else -1.0
			if absf(_dodge_dir.x) < 0.15:
				lean_sign = 1.0 if _dodge_dir.y > 0.0 else -1.0
			body.rotation = lean_sign * 0.28 * arch
			body.scale = Vector2(
				_base_body_scale.x * (1.0 + 0.12 * arch),
				_base_body_scale.y * (1.0 - 0.14 * arch))
		_dodge_afterimage_t += delta
		var ai_interval := maxf(_cfg_float(&"dodge_afterimage_interval", DODGE_AFTERIMAGE_INTERVAL), 0.025)
		if _dodge_afterimage_t >= ai_interval:
			_dodge_afterimage_t = 0.0
			_spawn_dodge_afterimage()
		if rig_v2 != null and rig_v2.visible:
			var w_armed := weapon_rig != null and (not weapon_rig.is_holstered() or weapon_rig.is_stowing())
			var w_holstered := weapon_rig == null or weapon_rig.is_holstered()
			rig_v2.update_rig(velocity, walk_speed, sprint_speed, aim_target, aim_enabled,
				w_armed, w_holstered, false, true, u, _dodge_dir, delta)
		elif rig != null:
			rig.set_state("run", direction, aim_target, false, delta)
		_sync_head()
		_update_head_tilt(delta)
		_dodge_t = maxf(_dodge_t - delta, 0.0)
		if _dodge_t <= 0.0:
			_end_dodge()
		if weapon_rig != null:
			weapon_rig.aim_world = aim_target
			weapon_rig.aim_enabled = aim_enabled
			weapon_rig.aiming = false
			weapon_rig.body_direction = direction
			weapon_rig.ads = false
			weapon_rig.sprinting = false
			weapon_rig.dodging = is_dodging()
			if rig_v2 != null and rig_v2.visible:
				weapon_rig.dynamic_shoulder_offset = rig_v2.get_weapon_shoulder_offset()
				weapon_rig.dodge_pose_rot = rig_v2.get_dodge_weapon_rotation()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprinting := Input.is_action_pressed("sprint")
	# 冲刺时不允许瞄准，避免“边冲边精准射击”
	ads = InputMap.has_action("aim") and Input.is_action_pressed("aim") and not sprinting
	var speed := sprint_speed if sprinting else walk_speed
	if ads:
		speed *= _cfg_float(&"ads_speed_mul", ADS_SPEED_MUL)
	if dbg_progress != null:
		speed *= float(dbg_progress.debug_mul("move"))

	velocity = input_vector * speed
	move_and_slide()

	global_position.x = clampf(global_position.x, bounds.position.x, bounds.end.x)
	global_position.y = clampf(global_position.y, bounds.position.y, bounds.end.y)

	var moving := input_vector.length_squared() > 0.01
	# 收枪动画期间仍保持举枪手型；完全收好后才回到 idle / 跑走姿态
	var armed := (weapon_rig != null and body.sprite_frames.has_animation("aim_0")
		and (not weapon_rig.is_holstered() or weapon_rig.is_stowing()))
	if moving:
		var target := _direction_index(input_vector)
		_play("run" if sprinting else "walk", target, speed)
	else:
		var face := direction
		if armed and aim_enabled:
			# 站定瞄准时身体按鼠标方向取最近的四向，让持枪姿态和枪口方向一致
			face = _direction_index(aim_target - global_position)
		# 手臂由武器层程序化绘制，身体不再使用图集里伸臂的瞄准帧
		_play("idle", face, 0.0)
	if rig_v2 != null and rig_v2.visible:
		var w_holstered := weapon_rig == null or weapon_rig.is_holstered()
		rig_v2.update_rig(velocity, walk_speed, sprint_speed, aim_target, aim_enabled,
			armed, w_holstered, ads, false, 0.0, Vector2.ZERO, delta)
		if armed and aim_enabled:
			direction = rig_v2.upper_direction
	elif rig != null:
		var mode := "idle"
		if moving:
			mode = "run" if sprinting else "walk"
		rig.set_state(mode, direction, aim_target, aim_enabled, delta)
	_apply_bob(moving)
	_sync_head()
	_update_head_tilt(delta)
	if weapon_rig != null:
		weapon_rig.aim_world = aim_target
		weapon_rig.aim_enabled = aim_enabled
		weapon_rig.aiming = armed and not moving
		weapon_rig.body_direction = rig_v2.upper_direction if (rig_v2 != null and rig_v2.visible) else direction
		weapon_rig.ads = ads
		# 冲刺时枪保持在手，只是压低，不会自动收枪
		weapon_rig.sprinting = sprinting and moving
		weapon_rig.dodging = false
		if rig_v2 != null and rig_v2.visible:
			weapon_rig.dynamic_shoulder_offset = rig_v2.get_weapon_shoulder_offset()
			weapon_rig.dodge_pose_rot = 0.0
		else:
			weapon_rig.dynamic_shoulder_offset = Vector2.ZERO
			weapon_rig.dodge_pose_rot = 0.0

## 切换动画：方向或动作变化时保留迈步相位，避免每次都从第 0 帧重新起步。
func _play(anim_name: String, target_direction: int, speed: float) -> void:
	var anim := "%s_%d" % [anim_name, target_direction]
	_current_block = ANIM_BLOCKS[anim_name]
	if body.animation != anim or not body.is_playing():
		var phase := float(body.frame) + body.frame_progress
		direction = target_direction
		body.play(anim)
		var count := body.sprite_frames.get_frame_count(anim)
		body.set_frame_and_progress(int(phase) % count, fmod(phase, 1.0))
		_update_weapon_anchor()
	elif target_direction != direction:
		direction = target_direction
		_update_weapon_anchor()
	if anim_name == "idle" or anim_name == "aim":
		body.speed_scale = 0.0
		body.frame = 0
	else:
		# 步频跟着实际速度走，冲刺时不会出现脚在原地打滑。
		var base_speed := sprint_speed if anim_name == "run" else walk_speed
		body.speed_scale = clampf(speed / base_speed, 0.4, 2.0)

## 走动时按帧号做轻微上下起伏，站立时回到基准高度。
func _apply_bob(moving: bool) -> void:
	var bob := 0.0
	if moving:
		bob = _step_bob(body.frame) * (frame_size.y / 160.0)
	var target := _base_offset + bob
	body.offset.y = move_toward(body.offset.y, target, frame_size.y * 0.06)
	# 头部挂在 Body 下不会跟着 offset 移动，这里手动跟随，避免走动时头身分离
	if _head_pivot != null:
		_head_pivot.position.y = _neck_base.y + (body.offset.y - _base_offset)
	# 开火后坐：Body 与武器层一起后退，影子保持不动
	_flinch = _flinch.move_toward(
		Vector2.ZERO, _cfg_float(&"flinch_recover_speed", 40.0) * get_physics_process_delta_time())
	body.position = _flinch
	if rig_v2 != null and rig_v2.visible:
		rig_v2.position = _flinch
	if weapon_rig != null:
		weapon_rig.position = _flinch
	# 背后挂点的枪不挂在 Body 下，手动跟随走路起伏
	if _weapon_sprite != null:
		_weapon_sprite.position = _stow_base + Vector2(0.0, body.offset.y - _base_offset)

func _direction_index(input_vector: Vector2) -> int:
	# 0=下 1=上 2=左 3=右，以主轴方向为准，避免斜向时抖动。
	if absf(input_vector.x) > absf(input_vector.y):
		return 3 if input_vector.x > 0.0 else 2
	return 0 if input_vector.y > 0.0 else 1
