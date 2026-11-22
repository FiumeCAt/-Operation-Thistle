extends Node2D
class_name VisionFog2D
## 玩家分层视野 + 视野迷雾。
##
## 三层可见度：
##   2 清晰视野：前方主锥（40° 半角 / 32 米），由主 Light2D 照亮；
##   1 相对暗：外圈余光（60° 半角 / 32 米）与近身黑暗视野（4.5 米），由弱光与径向光覆盖；
##   0 视野迷雾：三层之外，世界被 CanvasModulate 压成灰暗阴影，敌人直接隐藏。
##
## 墙体与大型家具挂了 LightOccluder2D，光照会被正确遮挡；
## 敌人可见性额外用关卡导航网格做视线采样，避免隔墙看到敌人。

const TILE := 64.0
## 视野距离按“格 = 米”换算，与敌人 view_range 的约定一致。
const PIXELS_PER_METER := TILE
## 视线与视野锥的原点：优先使用角色头部；没有头部节点时回退到该高度。
const EYE_HEIGHT := 82.0

## 与旧 3D 视野系统保持一致：80° 清晰 + 120° 总视野；基础视野距离 40 米。
const CLEAR_HALF_DEG := 40.0
const TOTAL_HALF_DEG := 60.0
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
## 光照贴图分辨率：384 配合大角度羽化与软阴影，让 32 米视野锥边缘平滑无锯齿。
const TEX_SIZE := 384
## 敌人可见性刷新间隔：50ms 一次，避免每帧遍历与视线采样。
const ENEMY_REFRESH := 0.05
## 视线采样步长：墙格 64px，24px 已能可靠命中。
const LOS_STEP := 24.0

static var _textures: Dictionary = {}

var player = null
var level = null
var canvas_modulate: CanvasModulate

var _clear_light: PointLight2D
var _dark_light: PointLight2D
var _self_light: PointLight2D
var _aim_angle := 0.0
var _enemy_timer := 0.0
var _debug := false
## 每个敌人当前的目标可见层级（2/1/0），用于逐帧平滑淡入淡出，避免边缘突然消失。
var _tiers: Dictionary = {}
## 瞄具提供的视野距离倍率：跟随当前武器 vision_mul 平滑变化，1.0 = 默认视野。
var vision_mul := 1.0


func setup(player_node: Node2D, level_node, modulate_node: CanvasModulate) -> void:
	player = player_node
	level = level_node
	canvas_modulate = modulate_node
	var half_px := TEX_SIZE * 0.5
	_clear_light = _make_light(_cone_texture(), CLEAR_ENERGY,
		TOTAL_RANGE_METERS * PIXELS_PER_METER / half_px, LIGHT_COLOR)
	_dark_light = _make_light(_radial_texture(), DARK_ENERGY,
		DARK_RADIUS_METERS * PIXELS_PER_METER / half_px, DARK_COLOR)
	_self_light = _make_light(_radial_texture(), SELF_ENERGY,
		SELF_RADIUS_METERS * PIXELS_PER_METER / half_px, Color(1.0, 0.95, 0.88))
	_self_light.shadow_enabled = false
	set_debug(false)


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
		canvas_modulate.color = Color(1, 1, 1) if enabled else AMBIENT
	if enabled:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var node := enemy as Node2D
			if node == null:
				continue
			node.visible = true
			node.modulate = Color.WHITE
	else:
		refresh_enemies()


## 当前瞄准角（弧度）。鼠标瞄准更新 aim_target；未更新时沿用上一帧角度。
func aim_angle() -> float:
	if player == null:
		return _aim_angle
	var offset: Vector2 = player.aim_target - _eye_position()
	if offset.length_squared() > 16.0:
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
	# 瞄具增加视野距离：主锥（含余光）同步放大，近身黑暗视野保持不变。
	var target_vision := 1.0
	if player.weapon_rig != null:
		target_vision = clampf(float(player.weapon_rig.vision_mul), 1.0, 2.2)
	var dbg_progress := get_node_or_null("/root/Progress")
	if dbg_progress != null:
		target_vision *= float(dbg_progress.debug_mul("vision"))
	target_vision = clampf(target_vision, 0.0, 100.0)
	vision_mul = lerpf(vision_mul, target_vision, clampf(delta * 6.0, 0.0, 1.0))
	var half_px := TEX_SIZE * 0.5
	_clear_light.texture_scale = TOTAL_RANGE_METERS * PIXELS_PER_METER * vision_mul / half_px
	# 视野倍率同时拓宽视野锥：只拉长距离的话，32 米早已超出屏幕，玩家看不出变化。
	_clear_light.scale = Vector2(1.0, maxf(vision_mul, 1.0))
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
		var tier := int(_tiers[node])
		var target_alpha := 1.0 if tier == 2 else (RING_ENEMY_ALPHA if tier == 1 else 0.0)
		var tint := Color.WHITE if tier == 2 else Color(0.78, 0.84, 0.95)
		var alpha := move_toward(float(node.modulate.a), target_alpha, delta * 6.0)
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
		var tier := tier_at(node.global_position)
		if not _tiers.has(node):
			# 初次进入直接到位，避免开局在迷雾里的敌人先闪一下。
			var alpha := 1.0 if tier == 2 else (RING_ENEMY_ALPHA if tier == 1 else 0.0)
			node.modulate.a = alpha
			node.visible = alpha > 0.01
		_tiers[node] = tier


## 0 = 视野迷雾（不可见），1 = 相对暗，2 = 清晰视野。
func tier_at(world_pos: Vector2) -> int:
	if player == null or not is_instance_valid(player):
		return 2
	var origin := _eye_position()
	var offset: Vector2 = world_pos - origin
	var dist: float = offset.length()
	var max_range: float = maxf(CLEAR_RANGE_METERS, TOTAL_RANGE_METERS) * PIXELS_PER_METER * vision_mul
	if dist > max_range:
		return 0
	var angle := 0.0 if dist <= 1.0 else absf(angle_difference(_aim_angle, offset.angle()))
	# 瞄具的视野倍率同时拓宽清晰锥与余光锥，和灯光锥保持一致。
	var angle_mul: float = maxf(vision_mul, 1.0)
	var clear_half := deg_to_rad(CLEAR_HALF_DEG) * angle_mul
	var total_half := deg_to_rad(TOTAL_HALF_DEG) * angle_mul
	var in_clear: bool = dist <= CLEAR_RANGE_METERS * PIXELS_PER_METER * vision_mul \
		and angle <= clear_half
	var in_ring: bool = dist <= TOTAL_RANGE_METERS * PIXELS_PER_METER * vision_mul \
		and angle <= total_half
	var in_dark: bool = dist <= DARK_RADIUS_METERS * PIXELS_PER_METER
	if not (in_clear or in_ring or in_dark):
		return 0
	if not line_clear(_los_position(), world_pos):
		return 0
	return 2 if in_clear else 1


## 视线采样：三条平行线（中间 + 左右各 12px）任意一条通畅即可。
## 单线采样在墙角/家具边缘会因为一个点落在不可走格上而误判遮挡，
## 表现为“敌人明明在视野里却突然消失”。
func line_clear(from: Vector2, to: Vector2) -> bool:
	if level == null:
		return true
	var delta := to - from
	var dist := delta.length()
	if dist <= 1.0:
		return true
	var dir := delta / dist
	var perp := Vector2(-dir.y, dir.x)
	# 避开玩家眼睛与敌人身体所在的格子，减少贴身误判。
	var start := from + dir * 10.0
	var end := to - dir * 16.0
	if start.distance_to(end) <= 1.0:
		return true
	for side in [-12.0, 0.0, 12.0]:
		if _line_clear_one(start + perp * side, end + perp * side):
			return true
	return false


func _line_clear_one(from: Vector2, to: Vector2) -> bool:
	var dist := from.distance_to(to)
	var steps := maxi(1, int(ceil(dist / LOS_STEP)))
	for i in range(1, steps):
		var probe := from.lerp(to, float(i) / float(steps))
		if not level.is_nav_walkable(probe):
			return false
	return true


func _make_light(tex: Texture2D, energy: float, light_scale: float,
		color: Color) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = tex
	light.texture_scale = light_scale
	light.energy = energy
	light.color = color
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 视野边缘用大范围角度羽化 + 软阴影，避免出现硬切边和阶梯锯齿。
	# PCF5 + 2px 平滑在视觉与开销之间取平衡；32 米主锥覆盖整屏，PCF13 太贵。
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	add_child(light)
	return light


## 清晰视野锥：40° 内满亮，30°..44° 平滑过渡到 40% 亮度的外圈余光，60° 收边。
static func _cone_texture() -> ImageTexture:
	if _textures.has("cone"):
		return _textures["cone"] as ImageTexture
	var clear_half := deg_to_rad(CLEAR_HALF_DEG)
	var total_half := deg_to_rad(TOTAL_HALF_DEG)
	var tex := _build_texture(func(angle: float, radius: float) -> float:
		if radius > 1.0 or angle > total_half:
			return 0.0
		# 远处缓慢衰减到迷雾，避免视野边缘出现生硬的圆形切边。
		var radial := clampf(1.0 - pow(radius, 3.2), 0.0, 1.0)
		var edge := smoothstep(0.72, 1.0, radius)
		radial *= lerpf(1.0, 0.55, edge)
		var angular := RING_DIM
		if angle <= clear_half - deg_to_rad(14.0):
			angular = 1.0
		elif angle < clear_half + deg_to_rad(8.0):
			var blend := (clear_half + deg_to_rad(8.0) - angle) / deg_to_rad(22.0)
			angular = lerpf(RING_DIM, 1.0, clampf(blend, 0.0, 1.0))
		elif angle > total_half - deg_to_rad(18.0):
			angular = lerpf(0.0, RING_DIM,
				clampf((total_half - angle) / deg_to_rad(18.0), 0.0, 1.0))
		return radial * angular)
	_textures["cone"] = tex
	return tex


## 近身黑暗视野：以玩家为中心的径向弱光。
static func _radial_texture() -> ImageTexture:
	if _textures.has("radial"):
		return _textures["radial"] as ImageTexture
	var tex := _build_texture(func(_angle: float, radius: float) -> float:
		if radius > 1.0:
			return 0.0
		return clampf(1.0 - pow(radius, 2.2), 0.0, 1.0))
	_textures["radial"] = tex
	return tex


## 把 (角度, 归一化半径) → 亮度 的函数烘焙成以 +X 为中心的贴图。
static func _build_texture(shader_fn: Callable) -> ImageTexture:
	var half := TEX_SIZE * 0.5
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := Vector2(x + 0.5 - half, y + 0.5 - half)
			var radius := v.length() / half
			var angle := absf(v.angle())
			var value := clampf(float(shader_fn.call(angle, radius)), 0.0, 1.0)
			img.set_pixel(x, y, Color(value, value, value, 1.0))
	return ImageTexture.create_from_image(img)
