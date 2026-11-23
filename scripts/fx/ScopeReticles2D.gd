extends RefCounted
class_name ScopeReticles2D
## 写实光学瞄具分划绘制（纯绘制，无状态）：
## 镜筒暗角、棱镜 BDC 十字、密位点、PSO-1、Vudu 速瞄马蹄环、全息环点与红点。
## 所有线条开启抗锯齿并带半透明黑描边，明暗地面都保持清晰。


## 镜片边缘：由外向内的多层渐隐暗环（柔和暗角），外加极细镜筒黑圈与玻璃高光弧。
static func draw_lens_frame(cv: CanvasItem, c: Vector2, r: float, fade: float) -> void:
	for i in 8:
		var rr := r - 1.0 - float(i) * 2.8
		var a := (0.34 - float(i) * 0.04) * fade
		if a <= 0.0:
			break
		cv.draw_arc(c, rr, 0.0, TAU, 112, Color(0.0, 0.0, 0.0, a), 3.2, true)
	cv.draw_arc(c, r + 0.5, 0.0, TAU, 128, Color(0.01, 0.01, 0.015, 0.88 * fade), 3.0, true)
	cv.draw_arc(c, r - 10.0, PI * 1.06, PI * 1.40, 28, Color(1.0, 1.0, 1.0, 0.10 * fade), 2.0, true)
	cv.draw_arc(c, r - 10.0, PI * 0.06, PI * 0.28, 16, Color(1.0, 1.0, 1.0, 0.05 * fade), 1.5, true)


static func draw_reticle(cv: CanvasItem, kind: String, c: Vector2, r: float,
		col: Color, pso_tex: Texture2D = null) -> void:
	match kind:
		"cross":
			_draw_cross(cv, c, r, col)
		"pso":
			_draw_pso(cv, c, r, col, pso_tex)
		"mildot":
			_draw_mildot(cv, c, r, col)
		"vudu":
			_draw_vudu(cv, c, r, col)
		"holo":
			draw_holo(cv, c, 34.0, col)
		"dot":
			draw_dot(cv, c, col, 1.0)
		_:
			pass


## 写实光学蚀刻黑线（主分划与外圈粗杆）：微弱浅色外晕保证暗地面也能清晰辨认。
static func _etch(cv: CanvasItem, a: Vector2, b: Vector2, alpha: float, width: float) -> void:
	cv.draw_line(a, b, Color(0.95, 0.98, 1.0, 0.14 * alpha), width + 1.4, true)
	cv.draw_line(a, b, Color(0.04, 0.05, 0.06, 0.92 * alpha), width, true)


## 发光中心分划（支持玩家自定义准星色，带柔和暗描边增强对比）。
static func _ln(cv: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	cv.draw_line(a, b, Color(0.0, 0.0, 0.0, 0.42 * col.a), width + 1.6, true)
	cv.draw_line(a, b, col, width, true)


## 2×–4× 战术光学镜（ACOG / 写实全镜径蚀刻分划）：
## 贯通全镜面的蚀刻细丝 + 三向粗外杆（duplex）+ 下方 BDC 弹道补偿刻度 + 中心发光瞄准点/短十字。
static func _draw_cross(cv: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var a := col.a
	var inner := r * 0.54
	var outer := r * 0.99
	var fine_gap := 14.0
	# 全镜径黑色蚀刻细丝（参考写实光学镜，贯通镜片边缘）。
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_etch(cv, c + dir * fine_gap, c + dir * inner, a, 1.1)
	_etch(cv, c + Vector2.LEFT * inner, c + Vector2.LEFT * outer, a, 3.6)
	_etch(cv, c + Vector2.RIGHT * inner, c + Vector2.RIGHT * outer, a, 3.6)
	_etch(cv, c + Vector2.DOWN * inner, c + Vector2.DOWN * outer, a, 3.6)
	_etch(cv, c + Vector2.UP * inner, c + Vector2.UP * outer, a, 1.2)
	# 水平风偏短刻度 + 下方 BDC 弹道补偿横杆。
	for i in 4:
		var d := 28.0 * float(i + 1)
		var h := 4.5 if (i % 2 == 1) else 3.0
		_etch(cv, c + Vector2(d, -h), c + Vector2(d, h), a, 1.0)
		_etch(cv, c + Vector2(-d, -h), c + Vector2(-d, h), a, 1.0)
	for i in 4:
		var y := 28.0 + float(i) * 28.0
		var half := 5.5 + float(i) * 4.5
		_etch(cv, c + Vector2(-half, y), c + Vector2(half, y), a, 1.2)
	# 中心发光分划：细亮短十字 + 中心发光点，暗环境快速捕捉目标。
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_ln(cv, c + dir * 3.5, c + dir * fine_gap, col, 1.2)
	cv.draw_circle(c, 2.6, Color(col.r, col.g, col.b, 0.28 * a), true, -1.0, true)
	cv.draw_circle(c, 1.5, col.lightened(0.28), true, -1.0, true)


## 3× / 8× 狙击镜（FFP 全视野密位分划）：
## 贯通全镜面的极细蚀刻十字 + 四向粗外杆 + 0.5/1 mil 精确测距刻度 + 极细中心发光点。
static func _draw_mildot(cv: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var a := col.a
	var gap := 6.0
	var inner := r * 0.56
	var outer := r * 0.99
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var perp := Vector2(-dir.y, dir.x)
		_etch(cv, c + dir * gap, c + dir * inner, a, 1.0)
		_etch(cv, c + dir * inner, c + dir * outer, a, 3.2)
		# 每 24px 一个 1 mil 主刻度 / 密位点，中间 12px 放 0.5 mil 极细短线。
		for i in range(1, 6):
			var d := 24.0 * float(i)
			if d >= inner - 6.0:
				break
			var tick := 5.0 if (i % 2 == 0) else 3.5
			_etch(cv, c + dir * d - perp * tick, c + dir * d + perp * tick, a, 1.0)
			cv.draw_circle(c + dir * d, 1.6, Color(0.04, 0.05, 0.06, 0.92 * a), true, -1.0, true)
			var half_d := d - 12.0
			if half_d > gap + 3.0:
				_etch(cv, c + dir * half_d - perp * 2.2, c + dir * half_d + perp * 2.2, a, 0.9)
	# 中心发光微点：不遮挡远距目标，同时在暗影里一眼定位中心。
	cv.draw_circle(c, 3.2, Color(col.r, col.g, col.b, 0.24 * a), true, -1.0, true)
	cv.draw_circle(c, 1.4, col.lightened(0.30), true, -1.0, true)


## PSO-1：优先使用透明贴图（箭尖在贴图正中心）；贴图缺失时程序化绘制尖顶折线与测距弧。
static func _draw_pso(cv: CanvasItem, c: Vector2, r: float, col: Color,
		tex: Texture2D) -> void:
	if tex != null:
		var size := Vector2(r, r) * 2.0
		cv.draw_texture_rect(tex, Rect2(c - size * 0.5, size), false, col)
		return
	var a := col.a
	_etch(cv, c + Vector2(-r * 0.98, 0), c + Vector2(-14.0, 0), a, 1.2)
	_etch(cv, c + Vector2(14.0, 0), c + Vector2(r * 0.98, 0), a, 1.2)
	_etch(cv, c + Vector2(0, 14.0), c + Vector2(0, r * 0.98), a, 1.2)
	for i in 4:
		var y := 26.0 + float(i) * 28.0
		var w := 12.0 + float(i) * 10.0
		_etch(cv, c + Vector2(-w, y), c + Vector2(w, y), a, 1.1)
	_ln(cv, c + Vector2(-11.0, 12.0), c, col, 1.7)
	_ln(cv, c + Vector2(11.0, 12.0), c, col, 1.7)
	cv.draw_arc(c, r * 0.56, PI * 0.55, PI * 0.95, 20, Color(0.04, 0.05, 0.06, 0.85 * a), 1.4, true)


## Vudu 6×：贯通全镜面的蚀刻细丝 + 圣诞树弹道补偿阵列 + 发光速瞄马蹄环与中心点。
static func _draw_vudu(cv: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var a := col.a
	var ring := r * 0.24
	var outer := r * 0.99
	# 全镜径黑色蚀刻外丝 + 粗外杆。
	_etch(cv, c + Vector2(-outer, 0), c + Vector2(-r * 0.62, 0), a, 3.2)
	_etch(cv, c + Vector2(-r * 0.62, 0), c + Vector2(-(ring + 8.0), 0), a, 1.0)
	_etch(cv, c + Vector2(ring + 8.0, 0), c + Vector2(r * 0.62, 0), a, 1.0)
	_etch(cv, c + Vector2(r * 0.62, 0), c + Vector2(outer, 0), a, 3.2)
	_etch(cv, c + Vector2(0, -outer), c + Vector2(0, -(ring + 8.0)), a, 1.0)
	_etch(cv, c + Vector2(0, ring * 0.45), c + Vector2(0, outer), a, 1.0)
	# 下方蚀刻圣诞树弹道刻度 + 水平风偏刻度。
	for i in 5:
		var y := ring + 10.0 + float(i) * 24.0
		var w := 10.0 + float(i) * 9.0
		_etch(cv, c + Vector2(-w, y), c + Vector2(w, y), a, 1.1)
	for i in 4:
		var x := ring + 18.0 + float(i) * 22.0
		_etch(cv, c + Vector2(x, -3.5), c + Vector2(x, 3.5), a, 1.0)
		_etch(cv, c + Vector2(-x, -3.5), c + Vector2(-x, 3.5), a, 1.0)
	# 发光速瞄开口马蹄环 + 中心点（EOTech Vudu SR 标志性发光外环）。
	cv.draw_arc(c, ring + 0.8, PI * 0.5 + 0.48, PI * 2.5 - 0.48, 56,
		Color(0.0, 0.0, 0.0, 0.36 * a), 4.4, true)
	cv.draw_arc(c, ring, PI * 0.5 + 0.48, PI * 2.5 - 0.48, 56, col, 2.4, true)
	cv.draw_circle(c, 3.0, Color(col.r, col.g, col.b, 0.25 * a), true, -1.0, true)
	cv.draw_circle(c, 1.7, col.lightened(0.28), true, -1.0, true)


## 全息（EOTech 风格）：68 MOA 环 + 1 MOA 中心点 + 三向短刻度。
static func draw_holo(cv: CanvasItem, c: Vector2, radius: float, col: Color) -> void:
	cv.draw_arc(c, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.30 * col.a), 4.0, true)
	cv.draw_arc(c, radius, 0.0, TAU, 64, col, 2.0, true)
	cv.draw_circle(c, 2.0, col.lightened(0.2), true, -1.0, true)
	for dir in [Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		_ln(cv, c + dir * (radius + 2.0), c + dir * (radius + 9.0), col, 2.0)


## 红点：带柔和光晕的单点。alpha 为外部淡入系数。
static func draw_dot(cv: CanvasItem, c: Vector2, col: Color, alpha: float) -> void:
	var base := Color(col.r, col.g, col.b, 1.0)
	cv.draw_circle(c, 10.0, Color(base.r, base.g, base.b, 0.10 * alpha), true, -1.0, true)
	cv.draw_circle(c, 6.0, Color(base.r, base.g, base.b, 0.24 * alpha), true, -1.0, true)
	cv.draw_circle(c, 2.8, Color(base.r, base.g, base.b, 0.96 * alpha), true, -1.0, true)
	cv.draw_circle(c, 1.2, Color(1.0, 0.9, 0.85, 0.9 * alpha), true, -1.0, true)
