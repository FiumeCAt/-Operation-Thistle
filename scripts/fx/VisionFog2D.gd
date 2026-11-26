extends Node2D
class_name VisionFog2D
## 玩家分层视野 + 视野迷雾。
##
## 三层可见度：
##   2 清晰视野：前方主锥（40° 半角 / 40 米），由主 Light2D 照亮；
##   1 相对暗：外圈余光（60° 半角 / 40 米）与近身黑暗视野（4.5 米），由弱光与径向光覆盖；
##   0 视野迷雾：三层之外，世界被 CanvasModulate 压成灰暗阴影，敌人直接隐藏。
##
## 墙体与大型家具挂了 LightOccluder2D，光照会被正确遮挡；
## 敌人可见性额外用关卡导航网格做视线采样，避免隔墙看到敌人。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
## 全项目统一世界距离标尺：1 格 = 1 米 = 64 px（来自 GameUnits）。
const PIXELS_PER_METER := UNITS.PIXELS_PER_METER
## 视线与视野锥的原点：优先使用角色头部；没有头部节点时回退到该高度。
const EYE_HEIGHT := 82.0

## 与旧 3D 视野系统保持一致：80° 清晰 + 120° 总视野；基础视野距离 40 米。
const CLEAR_HALF_DEG := 40.0
const TOTAL_HALF_DEG := 60.0
## 视野广角天赋上限：总半角严格 ≤ 82°（全角 164°），保留背后视觉盲区压迫感。
const MAX_CLEAR_HALF_DEG := 62.0
const MAX_TOTAL_HALF_DEG := 82.0
## 远距侦察天赋：每级 +10% 主锥距离与近身黑暗视野半径（Lv.5 达 1.50×，100% 缩放立即可感）。
const VISION_RANGE_TALENT_STEP := 0.10
## 广角视野天赋：每级 +4.4° 半角（Lv.5 达 +22° → 清晰 62° / 总视野 82° 上限）。
const VISION_ANGLE_TALENT_STEP_DEG := 4.4
const CLEAR_RANGE_METERS := 40.0
const TOTAL_RANGE_METERS := 40.0
## 近身黑暗视野：背后也能看到一圈“相对暗”的范围。
const DARK_RADIUS_METERS := 4.5
## 迷雾环境亮度：类阴影的灰暗，而不是完全黑暗。
const AMBIENT := Color(0.40, 0.43, 0.48)
## 边缘视野层（相对暗）的敌人不透明度。
const RING_ENEMY_ALPHA := 0.8
const CLEAR_ENERGY := 0.60
## 余光层亮度占主锥的比例，直接编码进同一张锥形贴图，省掉一盏全屏灯。
const RING_DIM := 0.40
const DARK_ENERGY := 0.18
## 贴身的补光：让角色在黑暗里始终可辨认，不参与视野判定。
const SELF_ENERGY := 0.18
const SELF_RADIUS_METERS := 1.1
const LIGHT_COLOR := Color(1.0, 0.97, 0.92)
const DARK_COLOR := Color(0.72, 0.82, 1.0)
## 光照贴图分辨率：512 配合线性过滤 + 半浮点格式 + 宽角度羽化，彻底消除 40 米视野锥边缘阶梯锯齿。
const TEX_SIZE := 512
## 敌人可见性刷新间隔：50ms 一次，避免每帧遍历与视线采样。
const ENEMY_REFRESH := 0.05
## 视线采样步长：精细 16px 采样，避免墙角与狭缝漏检或误判。
const LOS_STEP := 16.0
## 敌人躯干立绘采样偏移（脚底 / 胸口 / 头顶，匹配 128px 立绘高度）：避免仰视/平视时脚底掉出眼高光锥导致明亮区域内敌人突然消失。
const ENEMY_BODY_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2(0.0, -56.0), Vector2(0.0, -112.0)]

static var _textures: Dictionary = {}

var player = null
var level = null
var canvas_modulate: CanvasModulate
var lighting_config: Resource
var ambient_color: Color = AMBIENT

var _clear_light: PointLight2D
var _dark_light: PointLight2D
var _self_light: PointLight2D
var _aim_angle := 0.0
var _enemy_timer := 0.0
var _debug := false
## 每个敌人当前的目标可见层级（2/1/0），用于逐帧平滑淡入淡出，避免边缘突然消失。
var _tiers: Dictionary = {}
## 视野距离总倍率（瞄具 × 远距侦察天赋 × 调试视野倍率）；与视角宽度彻底解耦。
var vision_mul := 1.0
## 生存分支「远距侦察」与「广角视野」天赋等级（0..5）。
var vision_range_level := 0
var vision_angle_level := 0
var _active_clear_half_deg := CLEAR_HALF_DEG
var _active_total_half_deg := TOTAL_HALF_DEG
var _ring_dim_cached := RING_DIM


func _cfg_float(prop: StringName, fallback: float) -> float:
	if lighting_config != null and prop in lighting_config:
		return float(lighting_config.get(prop))
	return fallback


func _cfg_color(prop: StringName, fallback: Color) -> Color:
	if lighting_config != null and prop in lighting_config:
		var val = lighting_config.get(prop)
		if val is Color:
			return val
	return fallback


func setup(player_node: Node2D, level_node, modulate_node: CanvasModulate,
		ambient_override := Color(-1.0, -1.0, -1.0, 1.0),
		cfg: Resource = null) -> void:
	player = player_node
	level = level_node
	canvas_modulate = modulate_node
	lighting_config = cfg
	if ambient_override.r >= 0.0:
		ambient_color = ambient_override
	elif modulate_node != null and not modulate_node.color.is_equal_approx(Color.WHITE):
		ambient_color = modulate_node.color
	else:
		ambient_color = AMBIENT
	var half_px := TEX_SIZE * 0.5
	_ring_dim_cached = clampf(_cfg_float(&"ring_dim", RING_DIM), 0.0, 1.0)
	_active_clear_half_deg = clear_half_deg()
	_active_total_half_deg = total_half_deg()
	_clear_light = _make_light(
		_cone_texture(_ring_dim_cached, _active_clear_half_deg, _active_total_half_deg),
		_cfg_float(&"clear_energy", CLEAR_ENERGY),
		TOTAL_RANGE_METERS * PIXELS_PER_METER / half_px, _cfg_color(&"light_color", LIGHT_COLOR))
	_dark_light = _make_light(_radial_texture(), _cfg_float(&"dark_energy", DARK_ENERGY),
		dark_radius_meters() * PIXELS_PER_METER / half_px, _cfg_color(&"dark_color", DARK_COLOR))
	_self_light = _make_light(_radial_texture(), _cfg_float(&"self_energy", SELF_ENERGY),
		SELF_RADIUS_METERS * PIXELS_PER_METER / half_px,
		_cfg_color(&"self_color", Color(1.0, 0.95, 0.88)))
	_self_light.shadow_enabled = false
	set_debug(false)


## 配置「远距侦察 / 广角视野」天赋等级：距离倍率与半角完全解耦，光照贴图按实际半角重建无拉伸畸变。
func set_vision_talents(range_lv: int, angle_lv: int) -> void:
	vision_range_level = maxi(0, range_lv)
	vision_angle_level = maxi(0, angle_lv)
	_active_clear_half_deg = clear_half_deg()
	_active_total_half_deg = total_half_deg()
	var half_px := TEX_SIZE * 0.5
	if _clear_light != null:
		_clear_light.texture = _cone_texture(_ring_dim_cached, _active_clear_half_deg, _active_total_half_deg)
		_clear_light.scale = Vector2.ONE
	if _dark_light != null:
		_dark_light.texture_scale = dark_radius_meters() * PIXELS_PER_METER / half_px
	if not _debug and player != null and is_instance_valid(player):
		refresh_enemies()


func vision_range_talent_mul() -> float:
	return 1.0 + float(vision_range_level) * VISION_RANGE_TALENT_STEP


func dark_radius_meters() -> float:
	return DARK_RADIUS_METERS * vision_range_talent_mul()


func clear_half_deg() -> float:
	return clampf(CLEAR_HALF_DEG + float(vision_angle_level) * VISION_ANGLE_TALENT_STEP_DEG,
		CLEAR_HALF_DEG, MAX_CLEAR_HALF_DEG)


func total_half_deg() -> float:
	return clampf(TOTAL_HALF_DEG + float(vision_angle_level) * VISION_ANGLE_TALENT_STEP_DEG,
		TOTAL_HALF_DEG, MAX_TOTAL_HALF_DEG)


## 切换调试照明：F7 后恢复原亮度并显示全部敌人，方便排查碰撞/寻路。
func set_debug(enabled: bool) -> void:
	_debug = enabled
	if _clear_light != null:
		_clear_light.visible = not enabled
	if _dark_light != null:
		_dark_light.visible = not enabled
	if _self_light != null:
		_self_light.visible = not enabled
	if canvas_modulate != null:
		canvas_modulate.color = Color(1, 1, 1) if enabled else ambient_color
	if enabled:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var node := enemy as Node2D
			if node == null:
				continue
			node.visible = true
			node.modulate = Color.WHITE
	else:
		refresh_enemies()


## 当前瞄准角（弧度）。鼠标瞄准更新 aim_target；贴近头部 16px 内保持原角度，避免光标掠过头顶时视野锥突然 180° 翻转。
func aim_angle() -> float:
	if player == null:
		return _aim_angle
	var offset: Vector2 = player.aim_target - _eye_position()
	if offset.length_squared() > 256.0:
		return offset.angle()
	return _aim_angle


## 视野原点：优先取角色头部（Doll2D.head_position），缺失时退回固定眼高。
func _eye_position() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	if player.has_method("head_position"):
		return player.head_position()
	return player.global_position + Vector2(0, -EYE_HEIGHT)


## 导航网格记录的是地面占用；视线必须从脚底附近出发。
## 用头部位置会让射线起点落进上方墙格，导致玩家明明在开阔地、视野内的敌人却被整片隐藏。
func _los_position() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	return player.global_position


func _process(delta: float) -> void:
	if _debug or player == null or not is_instance_valid(player):
		return
	var origin := _eye_position()
	_clear_light.global_position = origin
	_dark_light.global_position = origin
	_self_light.global_position = origin
	_aim_angle = lerp_angle(_aim_angle, aim_angle(), clampf(delta * 14.0, 0.0, 1.0))
	_clear_light.rotation = _aim_angle
	# 视野距离倍率（瞄具 × 远距侦察天赋 × 调试视野倍率）仅缩放距离；半角由广角视野天赋独立控制，彻底取消 Y 轴拉伸畸变。
	var target_vision := vision_range_talent_mul()
	if player.weapon_rig != null:
		target_vision *= clampf(float(player.weapon_rig.vision_mul), 1.0, 2.2)
	var dbg_progress := get_node_or_null("/root/Progress")
	if dbg_progress != null:
		target_vision *= float(dbg_progress.debug_mul("vision"))
	target_vision = clampf(target_vision, 0.0, 100.0)
	vision_mul = lerpf(vision_mul, target_vision, clampf(delta * 6.0, 0.0, 1.0))
	var half_px := TEX_SIZE * 0.5
	_clear_light.texture_scale = TOTAL_RANGE_METERS * PIXELS_PER_METER * vision_mul / half_px
	_clear_light.scale = Vector2.ONE
	_dark_light.texture_scale = dark_radius_meters() * PIXELS_PER_METER / half_px
	_enemy_timer -= delta
	if _enemy_timer <= 0.0:
		_enemy_timer = ENEMY_REFRESH
		refresh_enemies()
	_update_enemy_fade(delta)


## 敌人可见度逐帧平滑：清晰 1.0、边缘层 0.8、迷雾 0，淡出而不是瞬间消失。
func _update_enemy_fade(delta: float) -> void:
	for node in _tiers.keys():
		if not is_instance_valid(node):
			_tiers.erase(node)
			continue
		# 已死亡的敌人交给自己的死亡动画/引信收尾，视野系统不再改写其透明度与可见性，
		# 否则尸体在迷雾里会被瞬间隐藏，爆炸引信的红圈也会被吞掉。
		if bool(node.get("_dead")):
			_tiers.erase(node)
			continue
		var tier := int(_tiers[node])
		var ring_alpha := clampf(_cfg_float(&"ring_enemy_alpha", RING_ENEMY_ALPHA), 0.1, 1.0)
		var target_alpha := 1.0 if tier == 2 else (ring_alpha if tier == 1 else 0.0)
		var tint := Color.WHITE if tier == 2 else Color(0.78, 0.84, 0.95)
		var alpha := move_toward(float(node.modulate.a), target_alpha, delta * 4.0)
		node.modulate = Color(tint.r, tint.g, tint.b, alpha)
		node.visible = alpha > 0.01


## 按玩家视野层级刷新敌人可见性：清晰=正常，相对暗=80% 透明，迷雾=淡出隐藏。
func refresh_enemies() -> void:
	if _debug or player == null or not is_instance_valid(player):
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var node := enemy as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var tier := tier_for_enemy(node.global_position)
		if not _tiers.has(node):
			# 初次进入直接到位，避免开局在迷雾里的敌人先闪一下。
			var ring_alpha := clampf(_cfg_float(&"ring_enemy_alpha", RING_ENEMY_ALPHA), 0.1, 1.0)
			var alpha := 1.0 if tier == 2 else (ring_alpha if tier == 1 else 0.0)
			node.modulate.a = alpha
			node.visible = alpha > 0.01
		_tiers[node] = tier


## 敌人全身多点可见性判定：只要脚底/躯干/上身任一部位落在清晰或余光锥内，且地面视线无墙体/高家具遮挡即保持可见。
## 彻底解决近中距仰视或平视时，因眼高 -82px 视差导致敌人躯干明亮却被脚底单点误判隐身的问题。
func tier_for_enemy(enemy_feet: Vector2) -> int:
	if player == null or not is_instance_valid(player):
		return 2
	var best_cone := 0
	for body_off in ENEMY_BODY_OFFSETS:
		var t := _cone_tier(enemy_feet + body_off)
		if t > best_cone:
			best_cone = t
			if best_cone == 2:
				break
	if best_cone == 0:
		# 近身黑暗视野也核对双脚距离，并随「远距侦察」天赋同步缩放。
		if enemy_feet.distance_to(_los_position()) <= dark_radius_meters() * PIXELS_PER_METER:
			best_cone = 1
	if best_cone == 0:
		return 0
	if not line_clear(_los_position(), enemy_feet):
		return 0
	return best_cone


## 0 = 视野迷雾（不可见），1 = 相对暗，2 = 清晰视野。
func tier_at(world_pos: Vector2) -> int:
	if player == null or not is_instance_valid(player):
		return 2
	var cone := _cone_tier(world_pos)
	if cone == 0:
		return 0
	if not line_clear(_los_position(), world_pos):
		return 0
	return cone


func _cone_tier(world_pos: Vector2) -> int:
	var origin := _eye_position()
	var offset: Vector2 = world_pos - origin
	var dist: float = offset.length()
	var dark_px := dark_radius_meters() * PIXELS_PER_METER
	var max_range: float = maxf(
		maxf(CLEAR_RANGE_METERS, TOTAL_RANGE_METERS) * PIXELS_PER_METER * vision_mul,
		dark_px)
	if dist > max_range:
		return 0
	var angle := 0.0 if dist <= 1.0 else absf(angle_difference(_aim_angle, offset.angle()))
	# 视野距离（vision_mul）与半角（广角视野天赋）彻底解耦，直接匹配按角烘焙的 _cone_texture。
	var clear_half := deg_to_rad(clear_half_deg())
	var total_half := deg_to_rad(total_half_deg())
	var in_clear: bool = dist <= CLEAR_RANGE_METERS * PIXELS_PER_METER * vision_mul \
		and angle <= clear_half
	var in_ring: bool = dist <= TOTAL_RANGE_METERS * PIXELS_PER_METER * vision_mul \
		and angle <= total_half
	var in_dark: bool = dist <= dark_px
	if not (in_clear or in_ring or in_dark):
		return 0
	return 2 if in_clear else 1


## 视线采样：三条平行线（中间 + 左右各 18px 肩宽）任意一条通畅即可。
## 优先查询 Level2D.is_sight_clear（仅墙体与带遮光体的高大家具阻挡，不因油桶/木箱/补给箱把清晰视野里的敌人藏掉）。
func line_clear(from: Vector2, to: Vector2) -> bool:
	if level == null:
		return true
	var delta := to - from
	var dist := delta.length()
	if dist <= 1.0:
		return true
	var dir := delta / dist
	var perp := Vector2(-dir.y, dir.x)
	# 避开玩家脚底与敌人身体所在边缘，减少贴墙/过门斜视角误判。
	var start := from + dir * 10.0
	var end := to - dir * 16.0
	if start.distance_to(end) <= 1.0:
		return true
	for side in [-18.0, 0.0, 18.0]:
		if _line_clear_one(start + perp * side, end + perp * side):
			return true
	return false


func _line_clear_one(from: Vector2, to: Vector2) -> bool:
	if _blocked_by_door(from, to):
		return false
	var use_sight_grid: bool = level.has_method("is_sight_clear")
	var dist := from.distance_to(to)
	var steps := maxi(1, int(ceil(dist / LOS_STEP)))
	for i in range(1, steps):
		var probe := from.lerp(to, float(i) / float(steps))
		var clear: bool = bool(level.is_sight_clear(probe)) if use_sight_grid \
			else bool(level.is_nav_walkable(probe))
		if not clear:
			return false
	return true


## 关卡导航网格把门洞标为可通行，视线判定需额外检查紧闭的滑门，防止隔门透视房间内敌人。
func _blocked_by_door(from: Vector2, to: Vector2) -> bool:
	var doors = level.get("doors")
	if typeof(doors) != TYPE_ARRAY:
		return false
	for entry in doors:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var door = entry.get("node", null)
		if door != null and is_instance_valid(door) and door.has_method("blocks_segment"):
			if bool(door.blocks_segment(from, to)):
				return true
	return false


func _make_light(tex: Texture2D, energy: float, light_scale: float,
		color: Color) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = tex
	light.texture_scale = light_scale
	light.energy = energy
	light.color = color
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 视野边缘用大范围角度羽化 + 软阴影，避免出现硬切边和阶梯锯齿。
	# PCF5 + 3px 平滑在视觉与开销之间取平衡；32 米主锥覆盖整屏，PCF13 太贵。
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 3.0
	add_child(light)
	return light


## 瞄具视野倍率同时拓宽灯光锥（Y 方向拉伸）：边缘半角 = atan(tan(基础半角) × 倍率)。
## 层级判定必须使用同一条几何，否则会出现“判定清晰、实际很暗”的错位。
static func widened_half_angle(base_deg: float, mul: float) -> float:
	var half := tan(deg_to_rad(clampf(base_deg, 1.0, 89.0))) * maxf(mul, 1.0)
	return atan(half)


## 清晰视野锥：按指定 clear_half_deg / total_half_deg 烘焙（默认 40°/60°，广角满级 62°/82°），各段 smoothstep 连续衔接。
static func _cone_texture(ring_dim := RING_DIM, clear_deg := CLEAR_HALF_DEG,
		total_deg := TOTAL_HALF_DEG) -> ImageTexture:
	var clean_clear := clampf(clear_deg, 10.0, MAX_CLEAR_HALF_DEG)
	var clean_total := clampf(maxf(total_deg, clean_clear + 8.0), 18.0, MAX_TOTAL_HALF_DEG)
	var key := "cone_%.3f_%.1f_%.1f" % [ring_dim, clean_clear, clean_total]
	if _textures.has(key):
		return _textures[key] as ImageTexture
	var clear_half := deg_to_rad(clean_clear)
	var total_half := deg_to_rad(clean_total)
	var tex := _build_texture(func(angle: float, radius: float) -> float:
		if radius > 1.0 or angle > total_half:
			return 0.0
		# 远处缓慢衰减到迷雾，避免视野边缘出现生硬的圆形切边。
		var radial := clampf(1.0 - pow(radius, 3.2), 0.0, 1.0)
		var edge := smoothstep(0.62, 1.0, radius)
		radial *= lerpf(1.0, 0.50, edge)
		# 角向：中心满亮 → 清晰边缘外 8° 降到余光 → 总视野边缘 20° 内渐隐为 0。
		var core := 1.0 - smoothstep(clear_half - deg_to_rad(14.0), clear_half + deg_to_rad(8.0), angle)
		var angular := lerpf(ring_dim, 1.0, core)
		angular *= smoothstep(0.0, deg_to_rad(20.0), total_half - angle)
		return radial * angular)
	_textures[key] = tex
	return tex


## 近身黑暗视野：以玩家为中心的径向弱光。
static func _radial_texture() -> ImageTexture:
	if _textures.has("radial"):
		return _textures["radial"] as ImageTexture
	var tex := _build_texture(func(_angle: float, radius: float) -> float:
		if radius > 1.0:
			return 0.0
		return clampf(1.0 - smoothstep(0.0, 1.0, radius) * pow(radius, 1.2), 0.0, 1.0))
	_textures["radial"] = tex
	return tex


## 把 (角度, 归一化半径) → 亮度 的函数烘焙成以 +X 为中心的贴图。
## 使用半精度浮点格式：8 位通道在暗部缓坡上会出现一圈圈色带。
static func _build_texture(shader_fn: Callable) -> ImageTexture:
	var half := TEX_SIZE * 0.5
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBAH)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := Vector2(x + 0.5 - half, y + 0.5 - half)
			var radius := v.length() / half
			var angle := absf(v.angle())
			var value := clampf(float(shader_fn.call(angle, radius)), 0.0, 1.0)
			img.set_pixel(x, y, Color(value, value, value, 1.0))
	return ImageTexture.create_from_image(img)
