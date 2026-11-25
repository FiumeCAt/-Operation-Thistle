class_name PixelUI
extends RefCounted
## 像素风 HUD 统一规范：Zpix 字体、琥珀描边 + 切角面板、12px 栅格字号。

const FONT: Font = preload("res://assets/art/ui/Zpix.ttf")

const AMBER := Color(1.0, 0.62, 0.24)
const AMBER_BRIGHT := Color(1.0, 0.82, 0.48)
const GOLD := Color(1.0, 0.84, 0.34)
const CYAN := Color(0.34, 0.86, 1.0)
const PURPLE := Color(0.76, 0.56, 1.0)
const TEXT := Color(0.90, 0.94, 0.97)
const DIM := Color(0.58, 0.66, 0.75)
const DANGER := Color(0.98, 0.36, 0.28)
const OK := Color(0.38, 0.94, 0.68)
const BG := Color(0.014, 0.020, 0.028, 0.95)
const BG_LIGHT := Color(0.055, 0.070, 0.088, 0.98)
const SLATE := Color(0.085, 0.110, 0.145, 0.96)

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

## 界面主题预设（默认琥珀 + 终端绿 + 科幻亮青 + 简约黑白 + 自定义主色）：
## 既有 const AMBER / BG / TEXT 全部保留不动确保全库兼容，新控件与可换肤界面调用 theme_*() 取动态色。
const THEME_ORDER: Array[String] = ["amber", "terminal", "cyan", "mono", "custom"]
const THEME_NAMES := {
	"amber": "琥珀",
	"terminal": "终端绿",
	"cyan": "亮青",
	"mono": "黑白",
	"custom": "自定义",
}
const THEME_PRESETS := {
	"amber": {
		"accent": Color(1.0, 0.62, 0.24),
		"accent_bright": Color(1.0, 0.82, 0.48),
		"bg": Color(0.014, 0.020, 0.028, 0.95),
		"bg_light": Color(0.055, 0.070, 0.088, 0.98),
		"text": Color(0.90, 0.94, 0.97),
		"dim": Color(0.58, 0.66, 0.75),
	},
	"terminal": {
		"accent": Color(0.24, 0.91, 0.48),
		"accent_bright": Color(0.56, 1.0, 0.71),
		"bg": Color(0.012, 0.026, 0.018, 0.95),
		"bg_light": Color(0.038, 0.078, 0.052, 0.98),
		"text": Color(0.86, 0.98, 0.90),
		"dim": Color(0.48, 0.72, 0.56),
	},
	"cyan": {
		"accent": Color(0.21, 0.86, 1.0),
		"accent_bright": Color(0.61, 0.94, 1.0),
		"bg": Color(0.012, 0.024, 0.038, 0.95),
		"bg_light": Color(0.040, 0.075, 0.110, 0.98),
		"text": Color(0.88, 0.96, 1.0),
		"dim": Color(0.50, 0.70, 0.82),
	},
	"mono": {
		"accent": Color(0.93, 0.95, 0.97),
		"accent_bright": Color(1.0, 1.0, 1.0),
		"bg": Color(0.025, 0.027, 0.031, 0.95),
		"bg_light": Color(0.075, 0.080, 0.088, 0.98),
		"text": Color(0.96, 0.97, 0.98),
		"dim": Color(0.62, 0.65, 0.69),
	},
}

static var _active_theme_id := "amber"
static var _custom_accent := Color(1.0, 0.62, 0.24)


static func set_theme_palette(id: String, custom_color: Color = AMBER) -> void:
	_active_theme_id = id if THEME_ORDER.has(id) else "amber"
	_custom_accent = custom_color


static func theme_id() -> String:
	return _active_theme_id


static func theme_name(id: String) -> String:
	return String(THEME_NAMES.get(id, id))


static func theme_accent() -> Color:
	if _active_theme_id == "custom":
		return _custom_accent
	return THEME_PRESETS.get(_active_theme_id, THEME_PRESETS["amber"])["accent"]


static func theme_accent_bright() -> Color:
	if _active_theme_id == "custom":
		return _custom_accent.lightened(0.32)
	return THEME_PRESETS.get(_active_theme_id, THEME_PRESETS["amber"])["accent_bright"]


static func theme_bg(alpha := -1.0) -> Color:
	var c: Color
	if _active_theme_id == "custom":
		var a := _custom_accent
		c = Color(lerpf(0.014, a.r, 0.03), lerpf(0.018, a.g, 0.03), lerpf(0.024, a.b, 0.03), 0.95)
	else:
		c = THEME_PRESETS.get(_active_theme_id, THEME_PRESETS["amber"])["bg"]
	if alpha >= 0.0:
		c.a = alpha
	return c


static func theme_bg_light(alpha := -1.0) -> Color:
	var c: Color
	if _active_theme_id == "custom":
		var a := _custom_accent
		c = Color(lerpf(0.052, a.r, 0.07), lerpf(0.062, a.g, 0.07), lerpf(0.076, a.b, 0.07), 0.98)
	else:
		c = THEME_PRESETS.get(_active_theme_id, THEME_PRESETS["amber"])["bg_light"]
	if alpha >= 0.0:
		c.a = alpha
	return c


static func theme_text() -> Color:
	if _active_theme_id == "custom":
		return Color(0.92, 0.95, 0.98)
	return THEME_PRESETS.get(_active_theme_id, THEME_PRESETS["amber"])["text"]


static func theme_dim() -> Color:
	if _active_theme_id == "custom":
		return Color(0.60, 0.67, 0.75)
	return THEME_PRESETS.get(_active_theme_id, THEME_PRESETS["amber"])["dim"]


static func theme_on_primary() -> Color:
	var a := theme_accent()
	return Color(0.05, 0.05, 0.06) if a.get_luminance() > 0.36 else Color(0.97, 0.98, 1.0)

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
	var use_theme_accent := false
	var bg_alpha := -1.0

	func apply_active_theme() -> void:
		if use_theme_accent:
			accent = PixelUI.theme_accent()
		var bg := PixelUI.theme_bg(bg_alpha)
		var st := get_theme_stylebox("panel")
		if st is StyleBoxFlat:
			var dup := (st as StyleBoxFlat).duplicate() as StyleBoxFlat
			dup.bg_color = bg
			add_theme_stylebox_override("panel", dup)
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 12.0 or s.y < 12.0:
			return
		var draw_acc := PixelUI.theme_accent() if use_theme_accent else accent
		draw_rect(Rect2(Vector2.ZERO, s), draw_acc, false, weight)
		draw_rect(Rect2(Vector2(5.0, 5.0), s - Vector2(10.0, 10.0)), Color(draw_acc, 0.30), false, 1.0)
		var thick := weight + 2.0
		var c := minf(corner, minf(s.x, s.y) * 0.4)
		for p in [Vector2.ZERO, Vector2(s.x - c, 0.0), Vector2(0.0, s.y - thick), Vector2(s.x - c, s.y - thick)]:
			draw_rect(Rect2(p, Vector2(c, thick)), draw_acc, true)
		for p in [Vector2.ZERO, Vector2(s.x - thick, 0.0), Vector2(0.0, s.y - c), Vector2(s.x - thick, s.y - c)]:
			draw_rect(Rect2(p, Vector2(thick, c)), draw_acc, true)

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

## 带切角描边的面板；默认自动跟随当前主题配色，显式传参时使用指定颜色。
static func panel(bg: Color = Color(-1, -1, -1, -1), accent: Color = Color(-1, -1, -1, -1)) -> PixelPanel:
	var p := PixelPanel.new()
	var use_default_accent := accent.r < 0.0
	var use_default_bg := bg.r < 0.0
	p.use_theme_accent = use_default_accent
	p.accent = theme_accent() if use_default_accent else accent
	var final_bg := theme_bg() if use_default_bg else bg
	p.bg_alpha = final_bg.a
	p.add_theme_stylebox_override("panel", panel_style(final_bg))
	return p

static func label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 强化关键标题/数字可读性：增加深色描边与投影，让字形在亮暗画面下都立体突出。
static func emphasize(l: Label, outline_size := 3, shadow_offset := 2) -> Label:
	l.add_theme_constant_override("outline_size", outline_size)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.92))
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", shadow_offset)
	l.add_theme_constant_override("shadow_offset_y", shadow_offset)
	return l


## BBCode 彩色包裹，便于在单行文案中突出关键数值、增益（绿）、惩罚（红）或按键提示（金）。
static func bb(text: String, col: Color) -> String:
	return "[color=#%s]%s[/color]" % [col.to_html(false), text]


## 富文本标签（支持 BBCode 局部着色与加重，自动撑开高度，沿用 Zpix 像素字体与投影）。
static func rich_label(parent: Node, bbcode: String, size: int,
		default_color: Color = TEXT, outline_size := 2) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_override("normal_font", FONT)
	rt.add_theme_font_override("bold_font", FONT)
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_font_size_override("bold_font_size", size)
	rt.add_theme_color_override("default_color", default_color)
	rt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.80))
	rt.add_theme_constant_override("shadow_offset_x", 1)
	rt.add_theme_constant_override("shadow_offset_y", 2)
	if outline_size > 0:
		rt.add_theme_constant_override("outline_size", outline_size)
		rt.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05, 0.90))
	rt.text = bbcode
	parent.add_child(rt)
	return rt


## 分组小标题：左侧 4px 彩色竖条 + 主标题 + 英文副标，拉出清晰视觉层级。
static func section_bar(parent: Node, title: String, tag: String = "",
		accent: Color = AMBER) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var bar_rect := ColorRect.new()
	bar_rect.color = accent
	bar_rect.custom_minimum_size = Vector2(4, 22)
	bar_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_rect)
	var lbl := emphasize(label(row, title, FS_BODY, accent), 2, 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if tag != "":
		var sub := label(row, "// " + tag, 18, DIM)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row

static func style_button(button: Button) -> void:
	var acc := theme_accent()
	var bright := theme_accent_bright()
	var bg_l := theme_bg_light()
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_l
	normal.border_color = Color(acc, 0.75)
	normal.set_border_width_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(
		lerpf(bg_l.r, acc.r, 0.16),
		lerpf(bg_l.g, acc.g, 0.16),
		lerpf(bg_l.b, acc.b, 0.16),
		1.0)
	hover.border_color = bright
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(
		lerpf(bg_l.r, acc.r, 0.28),
		lerpf(bg_l.g, acc.g, 0.28),
		lerpf(bg_l.b, acc.b, 0.28),
		1.0)
	pressed.border_color = bright
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.035, 0.042, 0.048, 0.9)
	disabled.border_color = Color(0.26, 0.29, 0.31)
	# 焦点只画描边：默认主题的焦点样式会在按钮上盖一层白底，破坏像素配色。
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = bright
	focus.set_border_width_all(2)
	focus.draw_center = false
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", theme_text())
	button.add_theme_color_override("font_hover_color", bright)
	button.add_theme_color_override("font_pressed_color", bright)
	button.add_theme_color_override("font_disabled_color", theme_dim())
	button.add_theme_font_size_override("font_size", FS_BODY)
	_attach_ui_sfx(button)

static func button(text: String, height := 56) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = height
	style_button(b)
	return b

## 主行动按钮：主题主色实心，一屏只用于唯一主操作（开始/确认）。
static func style_primary_button(b: Button) -> void:
	style_button(b)
	var acc := theme_accent()
	var bright := theme_accent_bright()
	var on_acc := theme_on_primary()
	var normal := StyleBoxFlat.new()
	normal.bg_color = acc
	normal.border_color = bright
	normal.set_border_width_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bright
	hover.border_color = bright.lightened(0.30)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = acc.darkened(0.16)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.24, 0.24, 0.26)
	disabled.border_color = Color(0.34, 0.34, 0.36)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", on_acc)
	b.add_theme_color_override("font_hover_color", on_acc)
	b.add_theme_color_override("font_pressed_color", on_acc)
	b.add_theme_color_override("font_focus_color", on_acc)
	b.add_theme_color_override("font_disabled_color", theme_dim())

static func primary_button(text: String, height := 56) -> Button:
	var b := button(text, height)
	style_primary_button(b)
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
