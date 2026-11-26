extends Node2D
class_name DamageNumber2D
## 像素伤害数字：命中/受击时从世界坐标向上飘并淡出，字号很小，不遮挡战斗。
## style 决定颜色与弹出力度：metal=冷白、flesh=暖橙、armor=护甲蓝、weakspot=金红暴击。

const LIFE := 0.7
const RISE := 30.0
const WEAKSPOT_COLOR := Color(1.0, 0.84, 0.24)
const WEAKSPOT_OUTLINE := Color(0.76, 0.08, 0.08, 0.98)

var is_weakspot := false

static func spawn(parent: Node, world_pos: Vector2, amount: int, color: Color,
		style := "", big := false) -> void:
	if parent == null or amount <= 0:
		return
	var weakspot := style == "weakspot"
	var number := DamageNumber2D.new()
	number.is_weakspot = weakspot
	parent.add_child(number)
	number.global_position = world_pos + Vector2(randf_range(-8.0, 8.0), -62.0 if weakspot else -56.0)
	var use_color := WEAKSPOT_COLOR if weakspot else color
	number.modulate = Color.WHITE
	number.scale = Vector2.ONE * (0.58 if weakspot else (0.65 if big else 0.8))
	if weakspot:
		number.z_index = 85

	var label := Label.new()
	label.text = "-%d!" % amount if weakspot else "-%d" % amount
	label.add_theme_font_override("font", PixelUI.FONT)
	var font_size := 15
	if amount >= 40:
		font_size = 19
	elif amount >= 18:
		font_size = 17
	if big:
		font_size += 2
	if weakspot:
		font_size += 4
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", use_color)
	label.add_theme_color_override("font_outline_color",
		WEAKSPOT_OUTLINE if weakspot else Color(0.01, 0.01, 0.02, 0.95))
	label.add_theme_constant_override("outline_size", 5 if weakspot else 4)
	label.position = Vector2(-24 if weakspot else -18, -12 if weakspot else -10)
	number.add_child(label)
	if weakspot:
		label.add_theme_color_override("font_shadow_color", Color(0.95, 0.20, 0.10, 0.72))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 2)
	elif style == "metal":
		# 金属命中：数字右侧带一点点高光描边，和火花呼应。
		label.add_theme_color_override("font_shadow_color", Color(1.0, 0.85, 0.4, 0.5))

	var rise := RISE + (12.0 if weakspot else 0.0)
	var life := LIFE + (0.14 if weakspot else 0.0)
	var pop_scale := 1.34 if weakspot else (1.15 if big else 1.0)
	var tween := number.create_tween()
	tween.set_parallel(true)
	# 先弹大再回落，命中数字更有“砸出来”的感觉。
	tween.tween_property(number, "scale", Vector2.ONE * pop_scale, 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(number, "position:y", number.position.y - rise, life) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(number, "position:x", number.position.x + randf_range(-10.0, 10.0), life)
	tween.tween_property(number, "modulate:a", 0.0, life).set_delay(0.24 if weakspot else 0.18)
	tween.chain().tween_callback(number.queue_free)
