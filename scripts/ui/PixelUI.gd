class_name PixelUI
extends RefCounted
## 像素风 HUD 统一规范：Zpix 字体、琥珀描边 + 切角面板、12px 栅格字号。

const FONT: Font = preload("res://assets/art/ui/Zpix.ttf")

const AMBER := Color(1.0, 0.62, 0.24)
const AMBER_BRIGHT := Color(1.0, 0.80, 0.48)
const TEXT := Color(0.87, 0.91, 0.95)
const DIM := Color(0.56, 0.64, 0.72)
const DANGER := Color(0.97, 0.36, 0.28)
const OK := Color(0.40, 0.94, 0.69)
const BG := Color(0.014, 0.020, 0.028, 0.94)
const BG_LIGHT := Color(0.055, 0.068, 0.082, 0.98)

## Zpix 原生 12px 栅格，只用整数倍避免字形被缩放糊掉
const FS_TITLE := 36
const FS_BODY := 24
const FS_NUM := 48
const FS_HUGE := 72

## 生命条绿→红渐变；体力用独立冷色，避免两条混在一起
const HP_LOW := Color(0.96, 0.28, 0.22)
const HP_HIGH := Color(0.36, 0.92, 0.52)
const STAM_LOW := Color(0.26, 0.62, 0.94)
const STAM_HIGH := Color(0.56, 0.94, 1.0)

const ICON_ROOT := "res://assets/art/ui/icons/"
const PORTRAIT_ROOT := "res://assets/art/ui/portraits/"

static func icon(parent: Node, icon_name: String, px: int) -> TextureRect:
	var path := ICON_ROOT + icon_name + ".png"
	var tex := TextureRect.new()
	if ResourceLoader.exists(path):
		tex.texture = load(path)
	tex.custom_minimum_size = Vector2(px, px)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(tex)
	return tex

static func apply_theme(root: Control) -> void:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = FS_BODY
	root.theme = theme

## 切角描边：2px 外框 + 1px 内细线 + 四角加粗。
## 直接画在面板自身矩形上，内容边距由 StyleBox 决定，两者互不挤压。
class PixelPanel extends PanelContainer:
	var accent := Color(1, 1, 1)
	var weight := 2.0
	var corner := 24.0

	func _draw() -> void:
		var s := size
		if s.x < 12.0 or s.y < 12.0:
			return
		draw_rect(Rect2(Vector2.ZERO, s), accent, false, weight)
		draw_rect(Rect2(Vector2(5.0, 5.0), s - Vector2(10.0, 10.0)), Color(accent, 0.30), false, 1.0)
		var thick := weight + 2.0
		var c := minf(corner, minf(s.x, s.y) * 0.4)
		for p in [Vector2.ZERO, Vector2(s.x - c, 0.0), Vector2(0.0, s.y - thick), Vector2(s.x - c, s.y - thick)]:
			draw_rect(Rect2(p, Vector2(c, thick)), accent, true)
		for p in [Vector2.ZERO, Vector2(s.x - thick, 0.0), Vector2(0.0, s.y - c), Vector2(s.x - thick, s.y - c)]:
			draw_rect(Rect2(p, Vector2(thick, c)), accent, true)

static func panel_style(bg: Color = BG, border := 0, border_color: Color = AMBER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border > 0:
		s.border_color = border_color
		s.set_border_width_all(border)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	return s

## 带切角描边的面板；正文内容请加给返回的 PanelContainer
static func panel(bg: Color = BG, accent: Color = AMBER) -> PixelPanel:
	var p := PixelPanel.new()
	p.accent = accent
	p.add_theme_stylebox_override("panel", panel_style(bg))
	return p

static func label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_LIGHT
	normal.border_color = Color(AMBER, 0.75)
	normal.set_border_width_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.11, 0.05, 1.0)
	hover.border_color = AMBER_BRIGHT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.26, 0.15, 0.05, 1.0)
	pressed.border_color = AMBER_BRIGHT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.035, 0.042, 0.048, 0.9)
	disabled.border_color = Color(0.26, 0.29, 0.31)
	# 焦点只画描边：默认主题的焦点样式会在按钮上盖一层白底，破坏像素配色。
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = AMBER_BRIGHT
	focus.set_border_width_all(2)
	focus.draw_center = false
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", AMBER_BRIGHT)
	button.add_theme_color_override("font_pressed_color", AMBER_BRIGHT)
	button.add_theme_color_override("font_disabled_color", DIM)
	button.add_theme_font_size_override("font_size", FS_BODY)
	_attach_ui_sfx(button)

static func button(text: String, height := 56) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = height
	style_button(b)
	return b

## 主行动按钮：琥珀实心，一屏只用于唯一主操作（开始/确认）。
static func primary_button(text: String, height := 56) -> Button:
	var b := button(text, height)
	var normal := StyleBoxFlat.new()
	normal.bg_color = AMBER
	normal.border_color = AMBER_BRIGHT
	normal.set_border_width_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = AMBER_BRIGHT
	hover.border_color = Color(1.0, 0.92, 0.78)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.86, 0.48, 0.16)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.24, 0.20, 0.14)
	disabled.border_color = Color(0.34, 0.30, 0.24)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
	b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.01))
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.03, 0.01))
	b.add_theme_color_override("font_disabled_color", DIM)
	return b

## 给所有按钮统一挂上悬停/点击音；跨场景可用，不依赖具体菜单。
static func _attach_ui_sfx(button: Button) -> void:
	if button.has_meta(&"ui_sfx"):
		return
	button.set_meta(&"ui_sfx", true)
	button.mouse_entered.connect(func() -> void: _play_ui_sfx("ui_hover", -14.0))
	button.focus_entered.connect(func() -> void: _play_ui_sfx("ui_hover", -18.0))
	button.pressed.connect(func() -> void: _play_ui_sfx("ui_click", -6.0))

static func _play_ui_sfx(kind: String, volume_db: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.play_2d(kind, volume_db, randf_range(0.97, 1.03))

static func bar(height: int, fill_color: Color = AMBER) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.y = height
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.055, 0.07, 0.95)
	bg.border_color = Color(AMBER, 0.55)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fill)
	return p
