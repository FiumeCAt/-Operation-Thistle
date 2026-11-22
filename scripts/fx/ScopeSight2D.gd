extends CanvasLayer
class_name ScopeSight2D
## 高倍率瞄具的镜内视野：ADS 时在准心位置显示一个圆形放大窗口。
## 使用共享主世界场景的 SubViewport + 副 Camera2D，实现“角色不放大、镜内放大”。
## 不同瞄具绘制不同准心：红点 / 全息 / 十字 / PSO-1。

const LENS_SIZE := 480.0
const LENS_MARGIN := 28.0
## 镜内相机的基础倍率：1.0 表示 1 世界像素 = 1 屏幕像素；4× 镜即 4.0。
const LENS_BASE_ZOOM := 1.0
## PSO 透明背景准星贴图（箭尖在贴图正中心）。
const PSO_RETICLE_PATH := "res://assets/ui/reticles/pso_reticle.png"

static var _mask_shader: Shader
static var _pso_texture_cache: Texture2D

var main = null
var doll = null

var _sub: SubViewport
var _cam: Camera2D
var _lens: TextureRect
var _lens_mat: ShaderMaterial
var _overlay: Control
var _fade := 0.0
var _lens_visible := false
var _mini_active := false
var _blend := 0.0
var _center := Vector2.ZERO
var _aim_screen := Vector2.ZERO
var _reticle := "iron"
var _magnification := 1.0
var _has_scope := false
var _reticle_color := Color(1.0, 0.45, 0.22)
## 镜内特效：移动时的拖影（UV）与镜片畸变开关。
var _prev_aim_world := Vector2.ZERO
var _motion_uv := Vector2.ZERO
var _motion_blur_on := true
var _distortion_on := true


func setup(main_node, player) -> void:
	main = main_node
	doll = player
	layer = 30
	_sub = SubViewport.new()
	_sub.size = Vector2i(int(LENS_SIZE), int(LENS_SIZE))
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_sub)
	# 共享主世界：镜内看到的是同一套地图、灯光、迷雾与已隐藏的敌人。
	_sub.world_2d = get_viewport().world_2d
	_cam = Camera2D.new()
	_cam.enabled = true
	_cam.position_smoothing_enabled = false
	_sub.add_child(_cam)

	_lens = TextureRect.new()
	_lens.texture = _sub.get_texture()
	_lens.size = Vector2(LENS_SIZE, LENS_SIZE)
	_lens.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lens.stretch_mode = TextureRect.STRETCH_SCALE
	_lens.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = _get_mask_shader()
	_lens.material = mat
	_lens_mat = mat
	_lens.visible = false
	add_child(_lens)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(delta: float) -> void:
	if main == null or doll == null or not is_instance_valid(doll):
		_hide_all()
		return
	var rig = doll.weapon_rig
	if rig == null:
		_hide_all()
		return
	_reticle = String(rig.sight_reticle)
	_magnification = maxf(float(rig.sight_magnification), 1.0)
	_has_scope = bool(rig.has_scope_sight)
	var progress := get_node_or_null("/root/Progress")
	if progress != null and progress.has_method("reticle_color"):
		_reticle_color = progress.reticle_color()
	if progress != null:
		if progress.has_method("scope_motion_blur"):
			_motion_blur_on = bool(progress.scope_motion_blur())
		if progress.has_method("scope_lens_distortion"):
			_distortion_on = bool(progress.scope_lens_distortion())
	_blend = float(rig.get_ads_blend())
	var drawn: bool = not rig.is_holstered() and not rig.is_stowing()
	var want_scope: bool = _has_scope and _blend > 0.35 and drawn
	_fade = move_toward(_fade, 1.0 if want_scope else 0.0, delta * 8.0)
	_lens_visible = _fade > 0.01 and _has_scope
	_mini_active = not _has_scope and _blend > 0.5 and drawn \
		and (_reticle == "dot" or _reticle == "holo")

	var screen := get_viewport().get_visible_rect().size
	var canvas_xform := get_viewport().get_canvas_transform()
	_aim_screen = canvas_xform * doll.aim_target
	if _lens_visible:
		# 镜窗与准心严格同点：不做边界夹取，瞄准点靠近屏幕边缘时允许镜片部分出界。
		_center = _aim_screen
		_lens.position = _center - Vector2(LENS_SIZE * 0.5, LENS_SIZE * 0.5)
		_lens.modulate.a = _fade
		_lens.visible = true
		_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# 放大联动：玩家视角缩放越小，镜内实际放大同步降低，镜内与世界缩放保持一致。
		_cam.zoom = Vector2.ONE * (LENS_BASE_ZOOM * _effective_magnification())
		# 镜内始终以准心指向的世界点为中心，保证准心与放大区域一致；
		# 更远距离的视野由主镜头拉宽与镜内倍率共同负责。
		_cam.global_position = doll.aim_target
		_update_lens_effects(delta)
	else:
		_lens.visible = false
		_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_prev_aim_world = doll.aim_target
		_motion_uv = Vector2.ZERO
		if _lens_mat != null:
			_lens_mat.set_shader_parameter("motion", Vector2.ZERO)
	if _lens_visible or _mini_active:
		_overlay.queue_redraw()
	else:
		_overlay.queue_redraw()


## 高倍镜联动：玩家视角缩放越小，镜内实际放大按同比例降低。
func _effective_magnification() -> float:
	var view := 1.0
	if main != null and main.has_method("view_zoom_scale"):
		view = float(main.view_zoom_scale())
	return _magnification * clampf(view, 0.25, 1.0)


## 镜内特效：瞄准点移动 → 镜内画面反向拖影；畸变始终按设置应用。
func _update_lens_effects(delta: float) -> void:
	var aim_world: Vector2 = doll.aim_target
	var world_delta := aim_world - _prev_aim_world
	_prev_aim_world = aim_world
	if _motion_blur_on:
		# 世界位移 × 镜内实际缩放 = 镜内像素位移；换算成 UV。
		var lens_zoom := _cam.zoom.x if _cam != null else _magnification
		var target := (-world_delta * lens_zoom) / LENS_SIZE
		if target.length() > 0.030:
			target = target.normalized() * 0.030
		_motion_uv = _motion_uv.lerp(target, clampf(delta * 16.0, 0.0, 1.0))
	else:
		_motion_uv = Vector2.ZERO
	if _lens_mat != null:
		_lens_mat.set_shader_parameter("motion", _motion_uv)
		_lens_mat.set_shader_parameter("distort", 0.55 if _distortion_on else 0.0)


## 装备自瞄具的准心时隐藏默认准星，避免与镜内准心/红点重叠。
func should_hide_reticle() -> bool:
	if doll == null or not is_instance_valid(doll):
		return false
	var rig = doll.weapon_rig
	if rig == null:
		return false
	if float(rig.get_ads_blend()) < 0.35:
		return false
	return String(rig.sight_reticle) in ["dot", "holo", "cross", "pso", "mildot", "vudu"]


func _hide_all() -> void:
	_fade = 0.0
	_lens_visible = false
	_mini_active = false
	_motion_uv = Vector2.ZERO
	if _lens_mat != null:
		_lens_mat.set_shader_parameter("motion", Vector2.ZERO)
	if _lens != null:
		_lens.visible = false
	if _sub != null:
		_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _overlay != null:
		_overlay.queue_redraw()


static func _get_mask_shader() -> Shader:
	if _mask_shader == null:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
uniform vec2 motion = vec2(0.0);
uniform float distort = 0.0;

void fragment() {
	vec2 raw = UV * 2.0 - 1.0;
	float r2 = dot(raw, raw);
	// 镜片畸变：边缘向外拉伸、中心轻微收紧，模拟玻璃弧度。
	vec2 p = raw * (1.0 + distort * (r2 * 0.18 - 0.03));
	float d = length(p);
	if (d > 1.0) {
		discard;
	}
	vec2 uv = p * 0.5 + 0.5;
	vec2 lo = vec2(0.001);
	vec2 hi = vec2(0.999);
	float vig = smoothstep(0.70, 1.0, d);
	// 运动拖影：沿瞄准移动方向做 7 次采样。
	vec3 c = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 7; i++) {
		float t = (float(i) / 6.0) * 2.0 - 1.0;
		float w = 1.0 - abs(t) * 0.55;
		c += texture(TEXTURE, clamp(uv + motion * t, lo, hi)).rgb * w;
		wsum += w;
	}
	c /= wsum;
	// 边缘径向模糊 + 压暗：去掉硬镜框，只保留镜片边缘的模糊过渡。
	vec2 blur = normalize(p + vec2(0.0001)) * (0.020 * vig);
	vec3 edge = texture(TEXTURE, clamp(uv + blur, lo, hi)).rgb * 0.25
		+ texture(TEXTURE, clamp(uv - blur, lo, hi)).rgb * 0.25
		+ texture(TEXTURE, clamp(uv + vec2(blur.y, -blur.x), lo, hi)).rgb * 0.25
		+ texture(TEXTURE, clamp(uv + vec2(-blur.y, blur.x), lo, hi)).rgb * 0.25;
	c = c * 0.55 + edge * 0.45;
	// 轻微色散：只在边缘明显，中心保持锐利。
	if (distort > 0.001) {
		vec2 ca = (uv - 0.5) * (distort * 0.012);
		c.r = texture(TEXTURE, clamp(uv + ca, lo, hi)).r;
		c.b = texture(TEXTURE, clamp(uv - ca, lo, hi)).b;
	}
	c *= mix(1.0, 0.62, vig);
	COLOR = vec4(c, 1.0);
}
"""
		_mask_shader = shader
	return _mask_shader


func _draw_overlay() -> void:
	if _lens_visible:
		_draw_lens_frame()
		_draw_reticle(_center, LENS_SIZE * 0.5, _reticle, _fade)
	if _mini_active:
		_draw_mini_reticle()


func _draw_lens_frame() -> void:
	var c := _center
	var r := LENS_SIZE * 0.5
	# 只保留一条极细的镜片边缘线；主要边界交给 shader 的边缘模糊。
	_overlay.draw_arc(c, r - 0.5, 0.0, TAU, 96,
		Color(0.02, 0.02, 0.03, 0.32 * _fade), 1.5)
	_overlay.draw_arc(c, r - 2.0, 0.0, TAU, 96,
		Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.18 * _fade), 1.0)


func _draw_reticle(c: Vector2, r: float, kind: String, alpha: float) -> void:
	match kind:
		"cross":
			_draw_cross(c, r, alpha)
		"pso":
			_draw_pso(c, r, alpha)
		"mildot":
			_draw_mildot(c, r, alpha)
		"vudu":
			_draw_vudu(c, r, alpha)
		"holo":
			_draw_holo(c, 42.0, alpha)
		"dot":
			_overlay.draw_circle(c, 3.0, Color(1.0, 0.22, 0.16, 0.95 * alpha))
			_overlay.draw_arc(c, 11.0, 0.0, TAU, 32,
				Color(1.0, 0.3, 0.2, 0.35 * alpha), 1.0)
		_:
			pass


## 标准十字：带描边的细十字 + 中心点 + 密位刻度。
func _draw_cross(c: Vector2, r: float, alpha: float) -> void:
	var col := Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.92 * alpha)
	var arm := r * 0.60
	var gap := 9.0
	_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), col, 2.0)
	_line(c + Vector2(gap, 0), c + Vector2(arm, 0), col, 2.0)
	_line(c + Vector2(0, -arm), c + Vector2(0, -gap), col, 2.0)
	_line(c + Vector2(0, gap), c + Vector2(0, arm), col, 2.0)
	_overlay.draw_circle(c, 2.6, col.lightened(0.2))
	for i in 4:
		var y := 30.0 + float(i) * 28.0
		_line(c + Vector2(-7, y), c + Vector2(7, y), col, 1.4)
	for i in 4:
		var x := 30.0 + float(i) * 28.0
		_line(c + Vector2(x, -7), c + Vector2(x, 7), col, 1.4)
		_line(c + Vector2(-x, -7), c + Vector2(-x, 7), col, 1.4)


## PSO-1：使用透明背景准星贴图（assets/ui/reticles/pso_reticle.png），
## 箭尖严格对准镜心；贴图缺失时退回程序化绘制。
func _draw_pso(c: Vector2, r: float, alpha: float) -> void:
	var tex := _pso_texture()
	if tex != null:
		var size := Vector2(r, r) * 2.0
		_overlay.draw_texture_rect(tex, Rect2(c - size * 0.5, size), false,
			Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, alpha))
		return
	var col := Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.95 * alpha)
	_line(c + Vector2(0, -r * 0.62), c + Vector2(0, r * 0.74), col, 2.0)
	for i in 4:
		var y := r * 0.16 + float(i) * 30.0
		var w := 22.0 + float(i) * 14.0
		_line(c + Vector2(-w, y), c + Vector2(w, y), col, 1.8)
	_line(c + Vector2(-14, -r * 0.2), c + Vector2(0, 0), col, 2.0)
	_line(c + Vector2(14, -r * 0.2), c + Vector2(0, 0), col, 2.0)
	_overlay.draw_circle(c, 2.4, col.lightened(0.2))
	_overlay.draw_arc(c, r * 0.56, PI * 0.55, PI * 0.95, 18, col, 1.5)


static func _pso_texture() -> Texture2D:
	if _pso_texture_cache == null and ResourceLoader.exists(PSO_RETICLE_PATH):
		_pso_texture_cache = load(PSO_RETICLE_PATH) as Texture2D
	return _pso_texture_cache


## 密位点：细十字 + 右下/左上密位点阵，适合 3× / 8× 狙击镜。
func _draw_mildot(c: Vector2, r: float, alpha: float) -> void:
	var col := Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.92 * alpha)
	var arm := r * 0.62
	_line(c + Vector2(-arm, 0), c + Vector2(-12, 0), col, 2.0)
	_line(c + Vector2(12, 0), c + Vector2(arm, 0), col, 2.0)
	_line(c + Vector2(0, -arm), c + Vector2(0, -12), col, 2.0)
	_line(c + Vector2(0, 12), c + Vector2(0, arm), col, 2.0)
	_overlay.draw_circle(c, 2.2, col.lightened(0.2))
	for i in 5:
		var y := 26.0 + float(i) * 26.0
		_overlay.draw_circle(c + Vector2(0, y), 1.5, col)
		_overlay.draw_circle(c + Vector2(0, -y), 1.5, col)
		for side in [-1.0, 1.0]:
			var x: float = (26.0 + float(i) * 26.0) * float(side)
			_overlay.draw_circle(c + Vector2(x, 0), 1.5, col)


## Vudu 速瞄：马蹄形外环 + 中心点 + 下方圣诞树刻度。
func _draw_vudu(c: Vector2, r: float, alpha: float) -> void:
	var col := Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.92 * alpha)
	_overlay.draw_arc(c, r * 0.30, PI * 0.15, PI * 0.85, 28,
		Color(col.r, col.g, col.b, 0.55 * alpha), 2.0)
	_overlay.draw_circle(c, 2.4, col.lightened(0.2))
	for i in 5:
		var y := r * 0.10 + float(i) * 26.0
		var w := 8.0 + float(i) * 7.0
		_line(c + Vector2(-w, y), c + Vector2(w, y), col, 1.6)
	for i in 4:
		var x := r * 0.16 + float(i) * 24.0
		_overlay.draw_circle(c + Vector2(x, 0), 1.5, col)
		_overlay.draw_circle(c + Vector2(-x, 0), 1.5, col)


## 全息准心：圆环 + 中心点 + 四向刻度。
func _draw_holo(c: Vector2, radius: float, alpha: float) -> void:
	var col := Color(_reticle_color.r, _reticle_color.g, _reticle_color.b, 0.92 * alpha)
	_overlay.draw_arc(c, radius, 0.0, TAU, 48, col, 2.0)
	_overlay.draw_circle(c, 3.0, col.lightened(0.2))
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_overlay.draw_line(c + dir * (radius - 9.0), c + dir * (radius + 5.0), col, 2.0)
	_overlay.draw_arc(c, radius + 6.0, 0.0, TAU, 48,
		Color(col.r, col.g, col.b, 0.22 * alpha), 1.0)


## 带黑色外描边的准心线：在明亮地面和昏暗阴影里都保持可读。
func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	_overlay.draw_line(a, b, Color(0.0, 0.0, 0.0, 0.42 * color.a), width + 2.0)
	_overlay.draw_line(a, b, color, width)


func _draw_mini_reticle() -> void:
	var a := clampf((_blend - 0.5) / 0.5, 0.0, 1.0)
	# 准心贴到屏幕边缘时也保持可见，避免鼠标移出画面时红点消失。
	var screen := get_viewport().get_visible_rect().size
	var c := _aim_screen.clamp(Vector2(26, 26), screen - Vector2(26, 26))
	if _reticle == "dot":
		_overlay.draw_circle(c, 3.0, Color(1.0, 0.22, 0.16, 0.95 * a))
		_overlay.draw_arc(c, 10.0, 0.0, TAU, 28,
			Color(1.0, 0.3, 0.2, 0.3 * a), 1.0)
	elif _reticle == "holo":
		_draw_holo(c, 26.0, a)
