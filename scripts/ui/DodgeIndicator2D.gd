extends Control
class_name DodgeIndicator2D
## 像素战术翻滚/躲闪冷却指示器（Phase 5）：
## 置于左下状态板右侧（与右下武器面板左侧的快慢机拨片形成镜像对称），
## 实时展示翻滚就绪 / 无敌翻滚中 / 冷却充能进度与剩余秒数。

var ready_ratio := 1.0
var dodging := false
var invuln := false
var cooldown_left := 0.0
var _pulse_t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(82, 82)


func set_dodge_state(ratio: float, is_dodging: bool, is_invuln: bool, cd_left: float) -> void:
	var clean_ratio := clampf(ratio, 0.0, 1.0)
	var clean_cd := maxf(cd_left, 0.0)
	var changed := (
		absf(ready_ratio - clean_ratio) > 0.005
		or dodging != is_dodging
		or invuln != is_invuln
		or absf(cooldown_left - clean_cd) > 0.04
	)
	ready_ratio = clean_ratio
	dodging = is_dodging
	invuln = is_invuln
	cooldown_left = clean_cd
	if changed:
		queue_redraw()


func _process(delta: float) -> void:
	if dodging or invuln:
		_pulse_t += delta * 14.0
		queue_redraw()


func _draw() -> void:
	var is_ready := ready_ratio >= 0.999 and not dodging
	var accent := Color(0.36, 0.92, 1.0) if (is_ready or invuln) \
		else (PixelUI.GOLD if dodging else Color(0.56, 0.64, 0.72))

	# 1. 阶梯像素外框（与右下 FireSelectorWidget2D 保持一致的机匣质感）。
	var outline := Color(accent, 0.88) if (invuln or is_ready) else Color(0.06, 0.07, 0.09, 0.96)
	var body_col := Color(0.09, 0.12, 0.15, 0.95) if (is_ready or invuln) else Color(0.08, 0.09, 0.11, 0.94)
	var bevel := Color(0.20, 0.28, 0.34, 0.88) if is_ready else Color(0.16, 0.18, 0.21, 0.75)
	_draw_stepped_box(Rect2(4, 2, 74, 62), outline, body_col, bevel)

	# 2. 内部充能槽底与自下而上充能进度填充。
	var gauge := Rect2(10, 8, 62, 50)
	draw_rect(gauge, Color(0.03, 0.04, 0.06, 0.92), true)
	var fill_h := roundf(gauge.size.y * (1.0 if dodging else ready_ratio))
	if fill_h > 0.5:
		var fill_col := Color(0.28, 0.86, 1.0, 0.34 + 0.12 * sin(_pulse_t)) if invuln \
			else (Color(0.24, 0.76, 0.92, 0.22) if is_ready \
			else (Color(1.0, 0.76, 0.28, 0.26) if dodging else Color(0.32, 0.54, 0.72, 0.24)))
		draw_rect(Rect2(gauge.position.x, gauge.end.y - fill_h, gauge.size.x, fill_h), fill_col, true)
		# 充能前沿亮线
		if not is_ready and not dodging:
			draw_rect(Rect2(gauge.position.x, gauge.end.y - fill_h, gauge.size.x, 2.0),
				Color(0.46, 0.88, 1.0, 0.85), true)
	draw_rect(gauge, Color(accent, 0.45), false, 1.0)

	# 3. 居中像素双疾行箭头（>>）图标：无敌帧高亮白青，冷却中压暗。
	var icon_col := Color(0.94, 0.99, 1.0, 1.0) if invuln \
		else (Color(0.44, 0.95, 1.0, 0.98) if is_ready \
		else (PixelUI.GOLD if dodging else Color(0.48, 0.54, 0.62, 0.75)))
	_draw_chevron(Vector2(24, 21), icon_col)
	_draw_chevron(Vector2(40, 21), icon_col)
	# 脚下速度线
	draw_rect(Rect2(16, 46, 14, 2), Color(icon_col, 0.65), true)
	draw_rect(Rect2(34, 46, 26, 2), Color(icon_col, 0.85), true)

	# 4. 底部快捷键 / 冷却倒计时胶囊条。
	var tag_rect := Rect2(2, 66, 78, 15)
	draw_rect(tag_rect, Color(0.04, 0.05, 0.07, 0.90), true)
	var tag_border := Color(accent, 0.82) if (is_ready or invuln) else Color(0.35, 0.40, 0.46, 0.55)
	draw_rect(tag_rect, tag_border, false, 1.0)
	var font: Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var tag_text := "SPACE·闪避"
	var tag_col := Color(0.46, 0.94, 1.0)
	if invuln:
		tag_text = "无敌闪避"
		tag_col = Color(0.95, 1.0, 1.0)
	elif dodging:
		tag_text = "翻滚中"
		tag_col = PixelUI.GOLD
	elif not is_ready:
		tag_text = "冷却 %.1fs" % cooldown_left
		tag_col = Color(0.76, 0.80, 0.86)
	draw_string(font, Vector2(tag_rect.position.x, tag_rect.position.y + 11.5),
		tag_text, HORIZONTAL_ALIGNMENT_CENTER, tag_rect.size.x, 11, tag_col)


func _draw_chevron(o: Vector2, col: Color) -> void:
	# 像素风右向双折角箭头（12×18）
	for step in 5:
		var dx := float(step) * 2.0
		var dy := float(step) * 2.0
		draw_rect(Rect2(o.x + dx, o.y + dy, 4.0, 2.5), col, true)
		draw_rect(Rect2(o.x + dx, o.y + 18.0 - dy - 2.5, 4.0, 2.5), col, true)
	draw_rect(Rect2(o.x + 10.0, o.y + 7.5, 4.0, 3.0), col, true)


func _draw_stepped_box(r: Rect2, outline: Color, fill: Color, bevel: Color) -> void:
	draw_rect(Rect2(r.position.x + 6, r.position.y, r.size.x - 12, r.size.y), outline, true)
	draw_rect(Rect2(r.position.x + 2, r.position.y + 4, r.size.x - 4, r.size.y - 8), outline, true)
	draw_rect(Rect2(r.position.x, r.position.y + 8, r.size.x, r.size.y - 16), outline, true)
	draw_rect(Rect2(r.position.x + 8, r.position.y + 2, r.size.x - 16, r.size.y - 4), fill, true)
	draw_rect(Rect2(r.position.x + 4, r.position.y + 6, r.size.x - 8, r.size.y - 12), fill, true)
	draw_rect(Rect2(r.position.x + 2, r.position.y + 10, r.size.x - 4, r.size.y - 20), fill, true)
	draw_rect(Rect2(r.position.x + 8, r.position.y + 2, r.size.x - 16, 2), bevel, true)
	draw_rect(Rect2(r.position.x + 2, r.position.y + 10, 2, r.size.y - 24), bevel, true)
