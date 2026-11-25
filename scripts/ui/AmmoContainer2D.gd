extends Control
class_name AmmoContainer2D
## 写实抽象供弹容器 HUD 控件：
## 透明/深黑底 + 清晰亮白外轮廓 + 内部黄铜金色子弹条（低弹量橙红预警，空发暗灰），
## 与容器边缘保持明确内边距，支持 6 种实装供弹形态 + 预留弹箱样式：
## curved_mag / stick_mag / tube / cylinder / top_mag / drum / box。

const OUTLINE_NORMAL := Color(0.93, 0.95, 0.98, 0.96)
const OUTLINE_EMPTY := Color(0.96, 0.46, 0.42, 0.96)
const FILL_DARK := Color(0.016, 0.020, 0.028, 0.84)
const BRASS_TOP := Color(1.00, 0.80, 0.28, 0.98)
const BRASS_BOT := Color(0.88, 0.66, 0.24, 0.98)
const BRASS_SPEC := Color(1.00, 0.92, 0.62, 0.90)
const LOW_TOP := Color(1.00, 0.42, 0.22, 0.98)
const LOW_BOT := Color(0.88, 0.24, 0.16, 0.98)
const LOW_SPEC := Color(1.00, 0.72, 0.52, 0.90)
const EMPTY_SLOT := Color(0.19, 0.21, 0.26, 0.62)
const SHELL_HULL := Color(0.90, 0.42, 0.18, 0.98)
const SHELL_HULL_LOW := Color(0.98, 0.26, 0.18, 0.98)
const SHELL_RIM := Color(1.00, 0.84, 0.34, 0.98)
const OUTLINE_WIDTH := 2.0
const LOW_RATIO := 0.25

var mag := 0
var cap := 0
var mag_style: StringName = &"stick_mag"
var mag_scale := 1.0
var reloading := false
var _pulse_t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 96)


func configure(current_mag: int, capacity: int, style: StringName,
		scale_ratio := 1.0, is_reloading := false) -> void:
	var clean_cap := maxi(capacity, 0)
	var clean_mag := clampi(current_mag, 0, clean_cap)
	var clean_style := style if WeaponDB.MAG_STYLES.has(style) else &"stick_mag"
	var clean_scale := clampf(scale_ratio, 0.75, 1.45)
	var changed := (mag != clean_mag) or (cap != clean_cap) \
		or (mag_style != clean_style) or (absf(mag_scale - clean_scale) > 0.005) \
		or (reloading != is_reloading)
	mag = clean_mag
	cap = clean_cap
	mag_style = clean_style
	mag_scale = clean_scale
	reloading = is_reloading
	set_process(reloading)
	if not reloading:
		_pulse_t = 0.0
	if changed:
		queue_redraw()


func _process(delta: float) -> void:
	if not reloading:
		set_process(false)
		return
	_pulse_t += delta * 6.5
	queue_redraw()


## 容量 <= 12 发逐发 1:1 显示；容量 > 12 发抽象为 8~16 格清晰横条/圆弧段，避免挤成色块。
static func visual_slots(capacity: int, style: StringName) -> int:
	if capacity <= 0:
		return 0
	if style == &"cylinder":
		return clampi(capacity, 5, 8)
	if capacity <= 12:
		return capacity
	if style == &"drum":
		if capacity <= 24:
			return 12
		if capacity <= 55:
			return 14
		return 16
	if style == &"top_mag":
		return 8 if capacity <= 30 else 10
	if style == &"box":
		return 10 if capacity <= 60 else 12
	if capacity <= 20:
		return 10
	if capacity <= 35:
		return 12
	if capacity <= 55:
		return 14
	return 16


## 按剩余弹量计算点亮格数：<=12 发精确 1:1；>12 发向上取整确保剩 1 发仍点亮 1 格。
static func filled_slots(current_mag: int, capacity: int, slots: int) -> int:
	if capacity <= 0 or slots <= 0 or current_mag <= 0:
		return 0
	if current_mag >= capacity:
		return slots
	if capacity <= 12 and slots == capacity:
		return clampi(current_mag, 0, slots)
	return clampi(int(ceil(float(current_mag) / float(capacity) * float(slots))), 1, slots)


func get_visual_slot_count() -> int:
	return visual_slots(cap, mag_style)


func get_filled_slot_count() -> int:
	return filled_slots(mag, cap, get_visual_slot_count())


func is_low_ammo() -> bool:
	return cap > 0 and mag > 0 and (float(mag) / float(cap)) <= LOW_RATIO


func _outline_color() -> Color:
	if cap <= 0:
		return Color(0.45, 0.48, 0.54, 0.55)
	if reloading:
		var k := 0.5 + 0.5 * sin(_pulse_t)
		return OUTLINE_NORMAL.lerp(PixelUI.AMBER_BRIGHT, 0.35 + 0.45 * k)
	if mag <= 0:
		return OUTLINE_EMPTY
	return OUTLINE_NORMAL


func _bullet_color(frac: float, low: bool) -> Color:
	# frac = 0 底部，1 顶部；顶部略亮、底部微暖黄铜，贴近弯弹匣手绘稿层次。
	if low:
		return LOW_BOT.lerp(LOW_TOP, clampf(frac, 0.0, 1.0))
	return BRASS_BOT.lerp(BRASS_TOP, clampf(frac, 0.0, 1.0))


func _draw() -> void:
	if cap <= 0 or size.x < 16.0 or size.y < 16.0:
		return
	var slots := get_visual_slot_count()
	var filled := filled_slots(mag, cap, slots)
	var low := is_low_ammo()
	var outline := _outline_color()
	match mag_style:
		&"curved_mag":
			_draw_curved_mag(slots, filled, low, outline)
		&"stick_mag":
			_draw_stick_mag(slots, filled, low, outline)
		&"tube":
			_draw_tube(slots, filled, low, outline)
		&"cylinder":
			_draw_cylinder(slots, filled, low, outline)
		&"top_mag":
			_draw_top_mag(slots, filled, low, outline)
		&"drum":
			_draw_drum(slots, filled, low, outline)
		&"box":
			_draw_box_mag(slots, filled, low, outline)
		_:
			_draw_stick_mag(slots, filled, low, outline)


## 1) 弯弧弹匣（AKM / L85A2 / VSS / Saiga-12K）：
## 上平下弯向右下展开、底部斜切，内部横向黄铜子弹条与白线轮廓保持清晰内边距。
func _draw_curved_mag(slots: int, filled: int, low: bool, outline: Color) -> void:
	var w := size.x
	var h := size.y
	var base_ratio := 0.78 if cap <= 12 else 0.87
	var h_ratio := clampf(base_ratio * mag_scale, 0.72, 0.94)
	var body_h := (h - 8.0) * h_ratio
	var y_top := (h - body_h) * 0.5
	var y_bot := y_top + body_h
	var mag_w := clampf(w * 0.50, 24.0, 38.0)
	var bend := clampf(w * 0.30, 14.0, 25.0) * clampf(mag_scale, 0.92, 1.20)
	var cx_top := (w - bend) * 0.48

	var steps := 14
	var left_pts := PackedVector2Array()
	var right_pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var c := _curved_spine(cx_top, y_top, y_bot, bend, t)
		var n := _curved_normal(cx_top, y_top, y_bot, bend, t)
		left_pts.append(c - n * (mag_w * 0.5))
		right_pts.append(c + n * (mag_w * 0.5))

	var poly := PackedVector2Array()
	for p in left_pts:
		poly.append(p)
	for i in range(steps, -1, -1):
		poly.append(right_pts[i])
	draw_colored_polygon(poly, FILL_DARK)

	# 内部子弹条：自底向上计数（剩余子弹稳落底部，射击从顶部递减），与左右白壁留 5px 明确间距。
	var pad_x := 5.2
	var half_bar_w := maxf(mag_w * 0.5 - pad_x, 4.0)
	var t_bot := 0.89
	var t_top := 0.11
	var usable_len := body_h * (t_bot - t_top)
	var pitch := usable_len / float(maxi(slots, 1))
	var bar_h := clampf(pitch * 0.54, 2.2, 6.2)

	for i in range(slots):
		var frac := 0.5 if slots <= 1 else float(i) / float(slots - 1)
		var t := lerpf(t_bot, t_top, frac)
		var c := _curved_spine(cx_top, y_top, y_bot, bend, t)
		var n := _curved_normal(cx_top, y_top, y_bot, bend, t)
		var tang := Vector2(-n.y, n.x)
		var loaded := i < filled
		var col := _bullet_color(frac, low) if loaded else EMPTY_SLOT
		_draw_oriented_bar(c, n, tang, half_bar_w, bar_h * 0.5, col, loaded, low)

	# 清晰白色外轮廓 + 底部弹匣底板强调线。
	_draw_closed_outline(poly, outline, OUTLINE_WIDTH)
	var b_l := left_pts[steps]
	var b_r := right_pts[steps]
	var b_dir := (b_r - b_l).normalized()
	draw_line(b_l - b_dir * 2.0, b_r + b_dir * 2.0, outline, OUTLINE_WIDTH + 0.6, true)


static func _curved_spine(cx_top: float, y_top: float, y_bot: float, bend: float, t: float) -> Vector2:
	return Vector2(cx_top + bend * pow(t, 1.85), lerpf(y_top, y_bot, t))


static func _curved_normal(cx_top: float, y_top: float, y_bot: float, bend: float, t: float) -> Vector2:
	var dt := 0.015
	var p0 := _curved_spine(cx_top, y_top, y_bot, bend, maxf(0.0, t - dt))
	var p1 := _curved_spine(cx_top, y_top, y_bot, bend, minf(1.0, t + dt))
	var tang := (p1 - p0).normalized()
	return Vector2(tang.y, -tang.x)


## 2) 直/微斜条匣（手枪 / MP7 / TMP / UMP45 / FAL / SR-25 / AWM）：
## 加长弹匣按 mag_scale 明显拉长，带底座托板与顶部供弹唇倒角。
func _draw_stick_mag(slots: int, filled: int, low: bool, outline: Color) -> void:
	var w := size.x
	var h := size.y
	var base_ratio := 0.66 if cap <= 7 else (0.76 if cap <= 18 else 0.83)
	var h_ratio := clampf(base_ratio * mag_scale, 0.62, 0.94)
	var body_h := (h - 10.0) * h_ratio
	var y_top := (h - body_h) * 0.5
	var y_bot := y_top + body_h
	var mag_w := clampf(w * 0.45, 22.0, 34.0)
	var slant := 4.5 if cap > 10 else 2.0
	var cx_top := (w - slant) * 0.5

	var tl := Vector2(cx_top - mag_w * 0.5, y_top)
	var tr := Vector2(cx_top + mag_w * 0.5, y_top)
	var br := Vector2(cx_top + slant + mag_w * 0.5, y_bot)
	var bl := Vector2(cx_top + slant - mag_w * 0.5, y_bot)
	var poly := PackedVector2Array([
		tl + Vector2(2.0, 0.0), tr - Vector2(2.0, 0.0),
		tr + Vector2(0.0, 3.0), br, bl, tl + Vector2(0.0, 3.0),
	])
	draw_colored_polygon(poly, FILL_DARK)

	var pad_x := 4.8
	var half_bar_w := maxf(mag_w * 0.5 - pad_x, 4.0)
	var pad_y := 6.0
	var usable_h := maxf(body_h - pad_y * 2.0, 12.0)
	var pitch := usable_h / float(maxi(slots, 1))
	var bar_h := clampf(pitch * 0.54, 2.2, 6.8)

	for i in range(slots):
		var frac := 0.5 if slots <= 1 else float(i) / float(slots - 1)
		var y := lerpf(y_bot - pad_y - bar_h * 0.5, y_top + pad_y + bar_h * 0.5, frac)
		var t := (y - y_top) / maxf(body_h, 1.0)
		var cx := cx_top + slant * t
		var loaded := i < filled
		var col := _bullet_color(frac, low) if loaded else EMPTY_SLOT
		var rect := Rect2(Vector2(cx - half_bar_w, y - bar_h * 0.5), Vector2(half_bar_w * 2.0, bar_h))
		draw_rect(rect, col, true)
		if loaded and bar_h >= 3.0:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)),
				LOW_SPEC if low else BRASS_SPEC, true)

	_draw_closed_outline(poly, outline, OUTLINE_WIDTH)
	# 底部加宽弹匣底板托脚。
	draw_line(bl + Vector2(-3.0, 1.5), br + Vector2(3.0, 1.5), outline, OUTLINE_WIDTH + 1.0, true)


## 3) 霰弹弹管（M870 / M1014）：
## 圆柱管仓 + 顶部圆弧堵头 + 管箍刻度，内部逐发绘制黄铜底缘 + 弹壳筒身。
func _draw_tube(slots: int, filled: int, low: bool, outline: Color) -> void:
	var w := size.x
	var h := size.y
	var h_ratio := clampf(0.75 * mag_scale, 0.72, 0.94)
	var body_h := (h - 8.0) * h_ratio
	var tube_w := clampf(w * 0.42, 22.0, 32.0)
	var r := tube_w * 0.5
	var cx := w * 0.5
	var y_top := (h - body_h) * 0.5
	var y_bot := y_top + body_h
	var cap_cy := y_top + r

	var poly := PackedVector2Array()
	var arc_steps := 10
	for i in range(arc_steps + 1):
		var a := lerpf(PI, 0.0, float(i) / float(arc_steps))
		poly.append(Vector2(cx + cos(a) * r, cap_cy - sin(a) * r))
	poly.append(Vector2(cx + r, y_bot))
	poly.append(Vector2(cx - r, y_bot))
	draw_colored_polygon(poly, FILL_DARK)

	var inner_top := y_top + r * 0.72 + 3.0
	var inner_bot := y_bot - 5.5
	var usable_h := maxf(inner_bot - inner_top, 14.0)
	var pitch := usable_h / float(maxi(slots, 1))
	var shell_h := clampf(pitch * 0.62, 3.0, 8.2)
	var shell_w := maxf(tube_w - 9.0, 10.0)
	var rim_w := maxf(shell_w * 0.28, 3.5)

	for i in range(slots):
		var frac := 0.5 if slots <= 1 else float(i) / float(slots - 1)
		var y := lerpf(inner_bot - shell_h * 0.5, inner_top + shell_h * 0.5, frac)
		var sx := cx - shell_w * 0.5
		var sy := y - shell_h * 0.5
		var loaded := i < filled
		if loaded:
			draw_rect(Rect2(sx, sy, rim_w, shell_h), SHELL_RIM, true)
			draw_rect(Rect2(sx + rim_w, sy, shell_w - rim_w, shell_h),
				SHELL_HULL_LOW if low else SHELL_HULL, true)
			draw_line(Vector2(sx + rim_w, sy), Vector2(sx + rim_w, sy + shell_h),
				Color(0.10, 0.08, 0.06, 0.85), 1.0)
			if shell_h >= 4.0:
				draw_rect(Rect2(sx, sy, shell_w, 1.0), Color(1.0, 0.90, 0.68, 0.55), true)
		else:
			draw_rect(Rect2(sx, sy, shell_w, shell_h), EMPTY_SLOT, true)

	_draw_closed_outline(poly, outline, OUTLINE_WIDTH)
	# 管仓顶部堵头横缝 + 中上部管箍凸耳 + 底部进弹口凸缘。
	draw_line(Vector2(cx - r + 1.0, cap_cy), Vector2(cx + r - 1.0, cap_cy),
		Color(outline, 0.45), 1.2, true)
	var clamp_y := lerpf(y_top, y_bot, 0.34)
	draw_line(Vector2(cx - r - 3.5, clamp_y), Vector2(cx - r, clamp_y), outline, 2.0, true)
	draw_line(Vector2(cx + r, clamp_y), Vector2(cx + r + 3.5, clamp_y), outline, 2.0, true)
	draw_line(Vector2(cx - r - 2.5, y_bot + 1.0), Vector2(cx + r + 2.5, y_bot + 1.0),
		outline, OUTLINE_WIDTH + 0.6, true)


## 4) 左轮圆形弹巢（Python 6 发）：
## 带外圈减重凹槽轮廓、中心转轴销、以及 6 个环形弹膛（实弹黄铜底缘+底火点，空膛暗孔）。
func _draw_cylinder(slots: int, filled: int, low: bool, outline: Color) -> void:
	var center := size * 0.5
	var outer_r := minf(size.x, size.y) * 0.43
	var n := maxi(slots, 5)
	draw_circle(center, outer_r, FILL_DARK)
	draw_arc(center, outer_r, 0.0, TAU, 36, outline, OUTLINE_WIDTH, true)
	# 外圈 6 处轻微凹槽刻度，强化左轮转轮辨识度。
	for i in range(n):
		var mid_a := -PI * 0.5 + (float(i) + 0.5) * (TAU / float(n))
		var p_in := center + Vector2.from_angle(mid_a) * (outer_r - 2.2)
		var p_out := center + Vector2.from_angle(mid_a) * (outer_r + 0.5)
		draw_line(p_in, p_out, Color(outline, 0.72), 2.0, true)

	# 中心转轴销。
	draw_circle(center, outer_r * 0.16, Color(0.10, 0.12, 0.15, 0.95))
	draw_arc(center, outer_r * 0.16, 0.0, TAU, 16, Color(outline, 0.80), 1.4, true)

	var ring_r := outer_r * 0.57
	var ch_r := outer_r * 0.21
	for i in range(n):
		var a := -PI * 0.5 + float(i) * (TAU / float(n))
		var pos := center + Vector2.from_angle(a) * ring_r
		var loaded := i < filled
		draw_circle(pos, ch_r + 1.0, Color(0.05, 0.06, 0.08, 0.95))
		if loaded:
			var rim_col := LOW_TOP if low else BRASS_TOP
			draw_circle(pos, ch_r, rim_col)
			draw_arc(pos, ch_r, 0.0, TAU, 16, LOW_SPEC if low else BRASS_SPEC, 1.0, true)
			draw_circle(pos, ch_r * 0.34, Color(0.98, 0.92, 0.76, 0.95) if not low else Color(1.0, 0.78, 0.62))
		else:
			draw_circle(pos, ch_r, EMPTY_SLOT)
			draw_arc(pos, ch_r, 0.0, TAU, 14, Color(0.42, 0.46, 0.52, 0.55), 1.0, true)


## 5) P90 顶置平放弹匣：
## 水平扁长透明匣身 + 左端旋转供弹斜坡 + 内部横向竖排 5.7×28 弹列。
func _draw_top_mag(slots: int, filled: int, low: bool, outline: Color) -> void:
	var w := size.x
	var h := size.y
	var body_w := w - 6.0
	var body_h := clampf(h * 0.46, 36.0, 48.0)
	var x0 := (w - body_w) * 0.5
	var y0 := (h - body_h) * 0.5
	var x1 := x0 + body_w
	var y1 := y0 + body_h
	var nose := clampf(body_w * 0.16, 9.0, 14.0)

	var poly := PackedVector2Array([
		Vector2(x0 + nose, y0),
		Vector2(x1 - 3.0, y0),
		Vector2(x1, y0 + 3.0),
		Vector2(x1, y1 - 3.0),
		Vector2(x1 - 3.0, y1),
		Vector2(x0 + nose * 0.45, y1),
		Vector2(x0, y1 - body_h * 0.30),
		Vector2(x0, y0 + body_h * 0.28),
	])
	draw_colored_polygon(poly, FILL_DARK)

	# 左侧供弹旋盘示意线。
	var ramp_x := x0 + nose + 2.0
	draw_line(Vector2(ramp_x, y0 + 3.0), Vector2(ramp_x, y1 - 3.0), Color(outline, 0.36), 1.2, true)
	draw_arc(Vector2(x0 + nose * 0.55, (y0 + y1) * 0.5), body_h * 0.16, 0.0, TAU, 12,
		Color(outline, 0.50), 1.1, true)

	# 内部竖条子弹：从左（供弹端）向右排列，射击时从右尾端递减，还原透明顶置弹匣观感。
	var inner_l := ramp_x + 4.0
	var inner_r := x1 - 5.0
	var pad_y := 5.5
	var bar_h := maxf(body_h - pad_y * 2.0, 14.0)
	var usable_w := maxf(inner_r - inner_l, 16.0)
	var pitch := usable_w / float(maxi(slots, 1))
	var bar_w := clampf(pitch * 0.56, 1.8, 4.2)

	for i in range(slots):
		var frac := 0.5 if slots <= 1 else float(i) / float(slots - 1)
		var x := lerpf(inner_l + bar_w * 0.5, inner_r - bar_w * 0.5, frac)
		var loaded := i < filled
		var col := _bullet_color(1.0 - frac * 0.35, low) if loaded else EMPTY_SLOT
		var rect := Rect2(Vector2(x - bar_w * 0.5, y0 + pad_y), Vector2(bar_w, bar_h))
		draw_rect(rect, col, true)
		if loaded:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2.0)),
				LOW_SPEC if low else BRASS_SPEC, true)

	_draw_closed_outline(poly, outline, OUTLINE_WIDTH)
	# 顶部与底部透明导轨细线。
	draw_line(Vector2(inner_l - 1.0, y0 + 3.0), Vector2(inner_r + 1.0, y0 + 3.0),
		Color(outline, 0.25), 1.0)
	draw_line(Vector2(inner_l - 1.0, y1 - 3.0), Vector2(inner_r + 1.0, y1 - 3.0),
		Color(outline, 0.25), 1.0)


## 6) 圆形弹鼓 + 顶部供弹颈（AKM 75 发 / G17·G18 50 发 / Saiga-12K 20 发）：
## 连续一体白色轮廓，中心发条轴心 + 外环 12~16 格清晰放射圆弧弹段。
func _draw_drum(slots: int, filled: int, low: bool, outline: Color) -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var outer_r := minf(w * 0.44, h * 0.34)
	var neck_w := clampf(outer_r * 0.62, 14.0, 22.0)
	var neck_h := clampf(h * 0.22, 14.0, 22.0)
	var total_h := neck_h + outer_r * 2.0
	var y_top := (h - total_h) * 0.5
	var center := Vector2(cx, y_top + neck_h + outer_r)

	var half_neck := neck_w * 0.5
	var dy := sqrt(maxf(outer_r * outer_r - half_neck * half_neck, 1.0))
	var join_r := Vector2(cx + half_neck, center.y - dy)
	var join_l := Vector2(cx - half_neck, center.y - dy)
	var ang_r := (join_r - center).angle()
	var ang_l := (join_l - center).angle()
	if ang_l <= ang_r:
		ang_l += TAU

	var poly := PackedVector2Array()
	poly.append(Vector2(cx - half_neck, y_top))
	poly.append(Vector2(cx + half_neck, y_top))
	poly.append(join_r)
	var arc_steps := 28
	for i in range(1, arc_steps):
		var a := lerpf(ang_r, ang_l, float(i) / float(arc_steps))
		poly.append(center + Vector2.from_angle(a) * outer_r)
	poly.append(join_l)
	draw_colored_polygon(poly, FILL_DARK)

	# 供弹颈内 2 发顶弹示意条（空仓时变暗）。
	var neck_pad := 4.0
	var nb_w := maxf(neck_w - neck_pad * 2.0, 5.0)
	for k in range(2):
		var ny := y_top + 4.5 + float(k) * 5.2
		var n_loaded := filled > 0
		draw_rect(Rect2(cx - nb_w * 0.5, ny, nb_w, 2.8),
			(LOW_TOP if low else BRASS_TOP) if n_loaded else EMPTY_SLOT, true)

	# 弹鼓环形弹道分段（与内外圈壁各保留 4.2px 清晰间距）。
	var hub_r := outer_r * 0.30
	var r_in := hub_r + 4.2
	var r_out := outer_r - 4.4
	var n := maxi(slots, 8)
	var step_ang := TAU / float(n)
	var gap_ang := clampf(step_ang * 0.24, 0.06, 0.14)
	for i in range(n):
		var a0 := -PI * 0.5 + float(i) * step_ang + gap_ang * 0.5
		var a1 := -PI * 0.5 + float(i + 1) * step_ang - gap_ang * 0.5
		var frac := 1.0 - float(i) / float(maxi(n - 1, 1))
		var loaded := i < filled
		var col := _bullet_color(frac, low) if loaded else EMPTY_SLOT
		var seg := PackedVector2Array([
			center + Vector2.from_angle(a0) * r_in,
			center + Vector2.from_angle(a0) * r_out,
			center + Vector2.from_angle(a1) * r_out,
			center + Vector2.from_angle(a1) * r_in,
		])
		draw_colored_polygon(seg, col)

	# 中心鼓轴与发条十字刻线。
	draw_circle(center, hub_r, Color(0.06, 0.07, 0.09, 0.96))
	draw_arc(center, hub_r, 0.0, TAU, 20, Color(outline, 0.82), 1.5, true)
	draw_line(center + Vector2(-hub_r * 0.45, 0), center + Vector2(hub_r * 0.45, 0),
		Color(outline, 0.45), 1.2)
	draw_line(center + Vector2(0, -hub_r * 0.45), center + Vector2(0, hub_r * 0.45),
		Color(outline, 0.45), 1.2)

	_draw_closed_outline(poly, outline, OUTLINE_WIDTH)


## 7) 预留弹箱样式（box：供未来轻机枪 / 弹链箱武器使用）：
## 切角战术弹药箱 + 顶部供弹槽 + 内部横向双列/宽幅黄铜弹链条。
func _draw_box_mag(slots: int, filled: int, low: bool, outline: Color) -> void:
	var w := size.x
	var h := size.y
	var box_w := clampf(w - 12.0, 36.0, 56.0)
	var box_h := clampf(h * 0.72, 48.0, 74.0)
	var x0 := (w - box_w) * 0.5
	var y0 := (h - box_h) * 0.5 + 3.0
	var x1 := x0 + box_w
	var y1 := y0 + box_h
	var chute_w := box_w * 0.34

	var poly := PackedVector2Array([
		Vector2(x0 + 4.0, y0),
		Vector2(x1 - chute_w - 4.0, y0),
		Vector2(x1 - chute_w, y0 - 6.0),
		Vector2(x1 - 4.0, y0 - 6.0),
		Vector2(x1, y0 - 2.0),
		Vector2(x1, y1 - 4.0),
		Vector2(x1 - 4.0, y1),
		Vector2(x0 + 4.0, y1),
		Vector2(x0, y1 - 4.0),
		Vector2(x0, y0 + 4.0),
	])
	draw_colored_polygon(poly, FILL_DARK)

	var pad_x := 6.0
	var pad_y := 6.5
	var inner_w := maxf(box_w - pad_x * 2.0, 16.0)
	var inner_h := maxf(box_h - pad_y * 2.0, 20.0)
	var pitch := inner_h / float(maxi(slots, 1))
	var bar_h := clampf(pitch * 0.56, 2.2, 5.5)

	for i in range(slots):
		var frac := 0.5 if slots <= 1 else float(i) / float(slots - 1)
		var y := lerpf(y1 - pad_y - bar_h * 0.5, y0 + pad_y + bar_h * 0.5, frac)
		var loaded := i < filled
		var col := _bullet_color(frac, low) if loaded else EMPTY_SLOT
		var rect := Rect2(Vector2(x0 + pad_x, y - bar_h * 0.5), Vector2(inner_w, bar_h))
		draw_rect(rect, col, true)
		if loaded and bar_h >= 3.0:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)),
				LOW_SPEC if low else BRASS_SPEC, true)

	_draw_closed_outline(poly, outline, OUTLINE_WIDTH)


func _draw_oriented_bar(center: Vector2, axis_x: Vector2, axis_y: Vector2,
		half_w: float, half_h: float, col: Color, loaded: bool, low: bool) -> void:
	var dx := axis_x * half_w
	var dy := axis_y * half_h
	var quad := PackedVector2Array([
		center - dx - dy,
		center + dx - dy,
		center + dx + dy,
		center - dx + dy,
	])
	draw_colored_polygon(quad, col)
	if loaded and half_h >= 1.4:
		draw_line(center - dx - dy, center + dx - dy,
			LOW_SPEC if low else BRASS_SPEC, 1.0, true)


func _draw_closed_outline(poly: PackedVector2Array, col: Color, width: float) -> void:
	if poly.size() < 2:
		return
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, col, width, true)
