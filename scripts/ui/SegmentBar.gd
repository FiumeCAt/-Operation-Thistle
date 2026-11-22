extends Control
class_name SegmentBar
## 机械分段条：等宽小格 + 斜纹纹理 + 随比例变化的绿到红渐变。
## 只用于 HUD，保持像素整数边缘，避免缩放糊化。

var ratio := 1.0
var segments := 20
var color_low := Color(0.96, 0.28, 0.22)
var color_high := Color(0.36, 0.92, 0.52)
var border_color := Color(1.0, 0.62, 0.24, 0.85)
var empty_color := Color(0.10, 0.13, 0.16, 0.95)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_ratio(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, ratio):
		return
	ratio = clamped
	queue_redraw()

func _draw() -> void:
	var s := size
	if s.x < 8.0 or s.y < 6.0:
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.042, 0.96), true)

	var pad := 3.0
	var inner := Rect2(pad, pad, s.x - pad * 2.0, s.y - pad * 2.0)
	var gap := 2.0
	var seg_w := (inner.size.x - gap * float(segments - 1)) / float(segments)
	if seg_w <= 0.0:
		return

	var color := color_low.lerp(color_high, smoothstep(0.05, 0.75, ratio))
	for i in segments:
		var x := inner.position.x + float(i) * (seg_w + gap)
		var fill := clampf(ratio * float(segments) - float(i), 0.0, 1.0)
		draw_rect(Rect2(x, inner.position.y, seg_w, inner.size.y), empty_color, true)
		if fill <= 0.0:
			continue
		var w := maxf(1.0, seg_w * fill)
		var body := Rect2(x, inner.position.y, w, inner.size.y)
		draw_rect(body, color, true)
		# 顶部高光 + 底部压暗，做出金属条的立体感
		draw_rect(Rect2(body.position, Vector2(body.size.x, 2.0)), color.lightened(0.32), true)
		draw_rect(Rect2(body.position + Vector2(0.0, body.size.y - 2.0), Vector2(body.size.x, 2.0)), color.darkened(0.32), true)
		# 斜纹：机械质感，只在已填充宽度内绘制
		var step := 7.0
		var offset := -body.size.y
		while offset < body.size.x:
			var x0 := body.position.x + offset
			var x1 := x0 + body.size.y
			if x1 > body.position.x and x0 < body.position.x + body.size.x:
				var a := maxf(x0, body.position.x)
				var b := minf(x1, body.position.x + body.size.x)
				if b - a > 1.5:
					draw_line(Vector2(a, body.position.y + body.size.y), Vector2(b, body.position.y), Color(0.0, 0.0, 0.0, 0.16), 2.0)
			offset += step

	draw_rect(Rect2(Vector2.ZERO, s), border_color, false, 2.0)
