extends Node2D
class_name MuzzleFlash2D
## 射击枪口火光与局部点亮表现层：
## 1) 枪口方向性炽白-金橙火舌（含口径强度缩放、连发自然抖动与消音器抑制）；
## 2) PointLight2D 动态暖色点光源（受墙体遮光体投影，照亮暗区地面、掩体与角色）；
## 3) 叠加模式局部柔光晕（BLEND_MODE_ADD），在清晰视野与暗区均呈现类似参考图的局部闪屏点亮质感；
## 4) 枪口飞溅火星颗粒 + 瞬时受火光映照的硝烟团（单常驻节点零分配复用，高射速连发零卡顿）。

const TEX_SIZE := 256
const FLAME_LIFE := 0.064
const CORE_BLOOM_LIFE := 0.085
const LIGHT_LIFE := 0.145
const BLOOM_LIFE := 0.160
const MAX_SPARKS := 64
const MAX_SMOKES := 28

static var _radial_tex: ImageTexture = null

var _light: PointLight2D
var _bloom: Sprite2D
var _core_bloom: Sprite2D

var _muzzle_pos := Vector2.ZERO
var _angle := 0.0
var _intensity := 1.0
var _suppressed := false
var _flame_t := 0.0
var _core_t := 0.0
var _light_t := 0.0
var _bloom_t := 0.0
var _flame_seed := 0.0
var _flame_len_mul := 1.0
var _flame_spread_mul := 1.0
var _sparks: Array[Dictionary] = []
var _smokes: Array[Dictionary] = []


func _ready() -> void:
	z_index = 62
	var tex := _get_radial_texture()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# 1. 动态物理点光源：真实照亮周边地面/角色/障碍并受墙体 LightOccluder2D 遮挡。
	_light = PointLight2D.new()
	_light.name = "MuzzleLight"
	_light.texture = tex
	_light.color = Color(1.0, 0.74, 0.30)
	_light.energy = 0.0
	_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_light.shadow_enabled = true
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_filter_smooth = 2.5
	_light.visible = false
	add_child(_light)

	# 2. 广域局部暖光闪屏晕：确保在清晰主视野锥内开火同样拥有柔和的局部点亮氛围。
	_bloom = Sprite2D.new()
	_bloom.name = "LocalFlashBloom"
	_bloom.texture = tex
	_bloom.material = add_mat
	_bloom.z_index = 4
	_bloom.visible = false
	add_child(_bloom)

	# 3. 枪口近端高能亮芯光晕。
	_core_bloom = Sprite2D.new()
	_core_bloom.name = "MuzzleCoreBloom"
	_core_bloom.texture = tex
	_core_bloom.material = add_mat
	_core_bloom.z_index = 5
	_core_bloom.visible = false
	add_child(_core_bloom)


## 触发一次开火枪口表现（支持连续快速重触发，全自动连发自然跳动闪烁）。
func trigger(world_pos: Vector2, angle: float, intensity := 1.0, suppressed := false) -> void:
	_muzzle_pos = world_pos
	_angle = angle
	_suppressed = suppressed
	var jitter := randf_range(0.90, 1.12)
	_intensity = clampf(intensity, 0.25, 1.8) * (0.30 if suppressed else 1.0) * jitter
	_flame_t = FLAME_LIFE * (0.65 if suppressed else 1.0)
	_core_t = CORE_BLOOM_LIFE * (0.65 if suppressed else 1.0)
	_light_t = LIGHT_LIFE * (0.72 if suppressed else 1.0)
	_bloom_t = BLOOM_LIFE * (0.72 if suppressed else 1.0)
	_flame_seed = randf() * TAU
	_flame_len_mul = randf_range(0.86, 1.22)
	_flame_spread_mul = randf_range(0.84, 1.18)

	_spawn_sparks(world_pos, angle, intensity, suppressed)
	_spawn_smoke(world_pos, angle, intensity, suppressed)
	_sync_light_nodes()
	queue_redraw()


## 开火极短时间内让火光与近端光源紧贴移动/摆动中的枪口；火星与硝烟保留在世界坐标自然飘散。
func sync_muzzle(world_pos: Vector2, angle: float) -> void:
	if _flame_t <= 0.0 and _light_t <= 0.0 and _bloom_t <= 0.0:
		return
	_muzzle_pos = world_pos
	_angle = angle
	_sync_light_nodes()


func is_active() -> bool:
	return _flame_t > 0.0 or _light_t > 0.0 or _bloom_t > 0.0 \
		or not _sparks.is_empty() or not _smokes.is_empty()


func current_light_energy() -> float:
	if _light == null or not _light.visible:
		return 0.0
	return _light.energy


func current_bloom_alpha() -> float:
	if _bloom == null or not _bloom.visible:
		return 0.0
	return _bloom.modulate.a


func spark_count() -> int:
	return _sparks.size()


func _process(delta: float) -> void:
	var dirty := false
	if _flame_t > 0.0:
		_flame_t = maxf(_flame_t - delta, 0.0)
		dirty = true
	if _core_t > 0.0:
		_core_t = maxf(_core_t - delta, 0.0)
		dirty = true
	if _light_t > 0.0:
		_light_t = maxf(_light_t - delta, 0.0)
		dirty = true
	if _bloom_t > 0.0:
		_bloom_t = maxf(_bloom_t - delta, 0.0)
		dirty = true

	if not _sparks.is_empty():
		var next_sparks: Array[Dictionary] = []
		var drag := exp(-7.2 * delta)
		for s in _sparks:
			var age := float(s["age"]) + delta
			if age < float(s["life"]):
				var vel: Vector2 = s["vel"]
				s["pos"] = (s["pos"] as Vector2) + vel * delta
				s["vel"] = vel * drag
				s["age"] = age
				next_sparks.append(s)
		_sparks = next_sparks
		dirty = true

	if not _smokes.is_empty():
		var next_smokes: Array[Dictionary] = []
		var sdrag := exp(-4.2 * delta)
		for m in _smokes:
			var age := float(m["age"]) + delta
			if age < float(m["life"]):
				var vel: Vector2 = m["vel"]
				m["pos"] = (m["pos"] as Vector2) + vel * delta
				m["vel"] = vel * sdrag + Vector2(0.0, -14.0 * delta)
				m["age"] = age
				next_smokes.append(m)
		_smokes = next_smokes
		dirty = true

	if dirty:
		_sync_light_nodes()
		queue_redraw()


func _sync_light_nodes() -> void:
	var dir := Vector2.from_angle(_angle)
	var half_px := float(TEX_SIZE) * 0.5
	var forward_pos := _muzzle_pos + dir * (12.0 if _suppressed else 48.0)

	if _light != null:
		if _light_t > 0.0:
			var t := clampf(_light_t / LIGHT_LIFE, 0.0, 1.0)
			var ease_val := pow(t, 1.45)
			var radius_px := lerpf(280.0, 420.0, clampf(_intensity * 0.72, 0.0, 1.0))
			if _suppressed:
				radius_px = 110.0
			_light.visible = true
			_light.global_position = forward_pos
			_light.texture_scale = radius_px / half_px
			_light.energy = (0.18 if _suppressed else minf(0.80 * _intensity, 1.05)) * ease_val
			_light.color = Color(1.0, lerpf(0.56, 0.74, t), lerpf(0.14, 0.28, t))
		else:
			_light.visible = false
			_light.energy = 0.0

	if _bloom != null:
		if _bloom_t > 0.0:
			var t := clampf(_bloom_t / BLOOM_LIFE, 0.0, 1.0)
			var ease_val := pow(t, 1.40)
			# 广域暖金色局部照亮光池：克制亮度（比初版低两档），柔和点亮环境而不过曝角色。
			var radius_px := lerpf(260.0, 400.0, clampf(_intensity * 0.72, 0.0, 1.0))
			if _suppressed:
				radius_px = 95.0
			var sc := radius_px / half_px
			_bloom.visible = true
			_bloom.global_position = forward_pos
			_bloom.rotation = _angle
			_bloom.scale = Vector2(sc * 1.18, sc * 0.94)
			var alpha := (0.035 if _suppressed else clampf(0.13 * _intensity, 0.07, 0.18)) * ease_val
			_bloom.modulate = Color(1.0, lerpf(0.58, 0.72, t), lerpf(0.14, 0.24, t), alpha)
		else:
			_bloom.visible = false

	if _core_bloom != null:
		if _core_t > 0.0:
			var t := clampf(_core_t / CORE_BLOOM_LIFE, 0.0, 1.0)
			var ease_val := pow(t, 1.55)
			var core_r := 26.0 if _suppressed else lerpf(48.0, 82.0, clampf(_intensity * 0.65, 0.0, 1.0))
			var sc := core_r / half_px
			_core_bloom.visible = true
			_core_bloom.global_position = _muzzle_pos + dir * 14.0
			_core_bloom.rotation = _angle
			_core_bloom.scale = Vector2(sc * 1.20, sc * 0.88)
			var alpha := (0.07 if _suppressed else clampf(0.20 * _intensity, 0.12, 0.28)) * ease_val
			_core_bloom.modulate = Color(1.0, 0.86, 0.44, alpha)
		else:
			_core_bloom.visible = false


func _spawn_sparks(world_pos: Vector2, angle: float, intensity: float, suppressed: bool) -> void:
	var count := randi_range(2, 3) if suppressed else clampi(int(round(randf_range(12.0, 18.0) * intensity)), 10, 24)
	for i in count:
		if _sparks.size() >= MAX_SPARKS:
			_sparks.pop_front()
		var spread := randf_range(-0.74, 0.74)
		if randf() < 0.30:
			spread *= 1.55
		var speed := randf_range(140.0, 260.0) if suppressed else randf_range(200.0, 580.0) * clampf(intensity, 0.78, 1.38)
		var dir := Vector2.from_angle(angle + spread)
		_sparks.append({
			"pos": world_pos + dir * randf_range(2.0, 14.0),
			"vel": dir * speed,
			"age": 0.0,
			"life": randf_range(0.11, 0.27),
			"size": randf_range(1.8, 3.6),
		})


func _spawn_smoke(world_pos: Vector2, angle: float, intensity: float, suppressed: bool) -> void:
	var count := 2 if suppressed else clampi(int(round(3.5 * intensity)), 3, 5)
	for i in count:
		if _smokes.size() >= MAX_SMOKES:
			_smokes.pop_front()
		var spread := randf_range(-0.55, 0.55)
		var dir := Vector2.from_angle(angle + spread)
		_smokes.append({
			"pos": world_pos + dir * randf_range(6.0, 20.0),
			"vel": dir * randf_range(45.0, 125.0),
			"age": 0.0,
			"life": randf_range(0.22, 0.38),
			"r0": randf_range(6.0, 10.0),
			"r1": randf_range(18.0, 30.0) * clampf(intensity, 0.85, 1.35),
		})


func _draw() -> void:
	# 1. 受枪口火光短暂映暖的硝烟团（参考图 2 中开枪后的暖黄余烟）。
	var flash_lit := clampf(_light_t / LIGHT_LIFE, 0.0, 1.0)
	for m in _smokes:
		var t := clampf(float(m["age"]) / maxf(float(m["life"]), 0.01), 0.0, 1.0)
		var local_pos := to_local(m["pos"] as Vector2)
		var r := lerpf(float(m["r0"]), float(m["r1"]), 1.0 - pow(1.0 - t, 1.6))
		var base_a := (1.0 - t) * (1.0 - t) * (0.20 if _suppressed else 0.28)
		var smoke_col := Color(0.70, 0.72, 0.76).lerp(Color(1.0, 0.78, 0.42), flash_lit * 0.82)
		draw_circle(local_pos, r, Color(smoke_col.r, smoke_col.g, smoke_col.b, base_a))

	# 2. 飞溅火星（初段白金高光，尾段冷成橙红余烬）。
	for s in _sparks:
		var t := clampf(float(s["age"]) / maxf(float(s["life"]), 0.01), 0.0, 1.0)
		var local_pos := to_local(s["pos"] as Vector2)
		var vel: Vector2 = s["vel"]
		var sz := float(s["size"])
		var fade := 1.0 - t * t
		var col := Color(1.0, 0.96, 0.78).lerp(Color(1.0, 0.44, 0.12), pow(t, 0.85))
		var tail := local_pos - vel * 0.014
		draw_line(tail, local_pos, Color(col.r, col.g, col.b, fade * 0.92), maxf(1.2, sz * 0.72), true)
		draw_circle(local_pos, maxf(1.0, sz * 0.52), Color(1.0, 0.98, 0.88, fade * 0.95))

	# 3. 方向性枪口火舌（尖锐金橙外焰 + 炽白内芯 + 中大口径微侧翼喷焰）。
	if _flame_t > 0.0:
		var t := clampf(_flame_t / FLAME_LIFE, 0.0, 1.0)
		var origin := to_local(_muzzle_pos)
		var dir := Vector2.from_angle(_angle)
		var perp := Vector2(-dir.y, dir.x)
		if _suppressed:
			var s_len := 13.0 * _flame_len_mul * lerpf(0.65, 1.0, t)
			var s_w := 3.6 * _flame_spread_mul
			var puff := PackedVector2Array([
				origin - perp * (s_w * 0.4),
				origin + dir * s_len,
				origin + perp * (s_w * 0.4),
			])
			draw_colored_polygon(puff, Color(0.95, 0.86, 0.62, t * 0.55))
		else:
			var scale_l := clampf(_intensity, 0.75, 1.55) * _flame_len_mul * lerpf(0.68, 1.10, t)
			var scale_w := clampf(_intensity, 0.75, 1.45) * _flame_spread_mul * lerpf(0.76, 1.10, t)
			var main_len := 36.0 * scale_l
			var main_w := 12.0 * scale_w
			var skew := sin(_flame_seed) * 2.2
			# 外层橙金火焰锥（降两档亮度，克制不刺眼）。
			var outer := PackedVector2Array([
				origin + perp * (main_w * 0.34),
				origin + dir * (main_len * 0.34) + perp * (main_w * 0.92 + skew * 0.4),
				origin + dir * (main_len * 0.64) + perp * (main_w * 0.42),
				origin + dir * main_len + perp * skew,
				origin + dir * (main_len * 0.62) - perp * (main_w * 0.46),
				origin + dir * (main_len * 0.32) - perp * (main_w * 0.90 - skew * 0.4),
				origin - perp * (main_w * 0.34),
			])
			draw_colored_polygon(outer, Color(0.98, 0.58, 0.14, minf(0.82, t * 0.92)))
			# 中大口径侧翼制退喷焰。
			if _intensity >= 0.95:
				var wing_l := 9.5 * scale_w
				var wing_base := origin + dir * 4.0
				for sgn in [-1.0, 1.0]:
					var wing := PackedVector2Array([
						wing_base - dir * 2.0,
						wing_base + dir * 3.0 + perp * (wing_l * sgn),
						wing_base + dir * 4.5,
					])
					draw_colored_polygon(wing, Color(0.98, 0.68, 0.20, t * 0.56))
			# 内层暖白焰芯。
			var inner_len := main_len * 0.60
			var inner_w := main_w * 0.44
			var inner := PackedVector2Array([
				origin + perp * (inner_w * 0.36),
				origin + dir * (inner_len * 0.42) + perp * inner_w,
				origin + dir * inner_len,
				origin + dir * (inner_len * 0.42) - perp * inner_w,
				origin - perp * (inner_w * 0.36),
			])
			draw_colored_polygon(inner, Color(1.0, 0.92, 0.72, minf(0.86, t * 1.00)))
			draw_circle(origin + dir * 3.5, 3.0 * scale_w, Color(1.0, 0.95, 0.80, t * 0.70))


## 生成一次平滑半浮点径向柔和衰减贴图（无 8 位暗部色带），供 PointLight2D 与叠加柔光共用。
static func _get_radial_texture() -> ImageTexture:
	if _radial_tex != null:
		return _radial_tex
	var half := float(TEX_SIZE) * 0.5
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBAH)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
			var v := 0.0
			if d < 1.0:
				# 宽域柔和暖光衰减：0~0.55 保持充沛的局部照亮覆盖面积，外缘平滑归零无硬边。
				var broad := pow(1.0 - d, 1.35)
				var core := pow(1.0 - d, 2.4) * 0.45
				v = clampf(broad * 0.76 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, v))
	_radial_tex = ImageTexture.create_from_image(img)
	return _radial_tex
