extends CanvasLayer
class_name RunHUD2D

## 2D 行动 HUD：左下角一块紧凑状态板（生命 / 资源 / 目标），
## 操作提示贴左上，右下武器面板，居中结算。
## 头像已移除；面板底图由 image2.5 生成，替代原先的大面积纯色黑框。

const PLATE_TEX: Texture2D = preload("res://assets/art/ui/hud/status_plate.png")
const WEAPON_PLATE_TEX: Texture2D = preload("res://assets/art/ui/hud/weapon_plate.png")
const AMMO_CONTAINER := preload("res://scripts/ui/AmmoContainer2D.gd")
const DODGE_INDICATOR := preload("res://scripts/ui/DodgeIndicator2D.gd")
## 状态板贴左下角：生命条在屏幕左下，避开主要视野。
const PLATE_POS := Vector2(20, -148)
const PLATE_SIZE := Vector2(560, 132)
const WEAPON_PLATE_SIZE := Vector2(456, 164)
const AMMO_DISPLAY_MODES := ["both", "numeric", "graphic"]
const AMMO_DISPLAY_LABELS := {
	"both": "[J] 图文",
	"numeric": "[J] 数值",
	"graphic": "[J] 图形",
}

## 右上角小地图：只显示玩家附近敌情，目标点常显。
signal return_requested
signal restart_requested
signal fire_mode_toggle_requested

## 拾取信息在屏幕左侧滚动显示，不占左下状态板；默认 3 秒内连续拾取同类掉落自动合并计数并轻闪。
const FEED_LIFE := 3.6
const FEED_MAX := 6
const FEED_MERGE_WINDOW := 3.0

var main: Node2D
var pickup_merge_window := FEED_MERGE_WINDOW

var hp_label: Label
var objective_label: Label
var hint_label: Label
## 左上交互目标：靠近可搜刮容器时显示名称，并用容器稀有度着色。
var interact_label: Label
var result_label: Label
var result_detail: Label
var ammo_label: Label
var return_button: Button
var restart_button: Button
var armor_label: Label
## 结算界面的带出物资数量标签（资源 id → Label）与战斗统计（键 → Label）。
var debrief_loot_labels := {}
var debrief_stat_labels := {}

var _root: Control
var _minimap: Minimap2D
var _hint_bar: PanelContainer
var _hint_rich: RichTextLabel
var _interact_bar: PanelContainer
var _health: SegmentBar
var _armor_bar: SegmentBar
var _title: Label
var _ammo_name: Label
var _reserve: Label
var _count: Label
var _state: Label
var _mode_badge: Label
var _progress: ProgressBar
var _ammo_well: PanelContainer
var ammo_container: Control
var ammo_display_mode := "both"
var ammo_exact_rounds := false
var fire_selector: FireSelectorWidget2D
var dodge_indicator: DodgeIndicator2D
var _result_panel: PanelContainer
var _debrief_empty: Label
var _feed: VBoxContainer
var _feed_items: Array[Dictionary] = []
var _flash_t := 0.0
var _hp_tier := -1
var _armor_broken := false
var _bgm_toast: PanelContainer
var _bgm_toast_label: Label
var _bgm_toast_t := 0.0


func setup(run: Node2D) -> void:
	main = run
	if _minimap != null:
		_minimap.setup(run)


func _ready() -> void:
	layer = 40
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelUI.apply_theme(_root)
	_build_status_plate()
	_build_hint()
	_build_pickup_feed()
	_build_weapon_panel()
	_build_minimap()
	_build_bgm_toast()
	_build_result_panel()
	var progress := get_node_or_null("/root/Progress")
	if progress != null:
		if progress.has_method("pickup_merge_window"):
			set_pickup_merge_window(float(progress.pickup_merge_window()))
		if progress.has_method("ammo_display"):
			set_ammo_display_mode(String(progress.ammo_display()))
		elif progress.data is Dictionary:
			set_ammo_display_mode(String(progress.data.get("ammo_display", "both")))
		if progress.has_method("ammo_exact_rounds"):
			set_ammo_exact_rounds(bool(progress.ammo_exact_rounds()))
		elif progress.data is Dictionary:
			set_ammo_exact_rounds(bool(progress.data.get("ammo_exact_rounds", false)))


func set_ammo_exact_rounds(enabled: bool) -> void:
	ammo_exact_rounds = enabled
	if ammo_container != null and ammo_container.has_method("set_exact_rounds"):
		ammo_container.set_exact_rounds(ammo_exact_rounds)


func get_ammo_exact_rounds() -> bool:
	return ammo_exact_rounds


func set_ammo_display_mode(mode: String) -> void:
	var clean := mode if AMMO_DISPLAY_MODES.has(mode) else "both"
	ammo_display_mode = clean
	_apply_ammo_display_mode()


func get_ammo_display_mode() -> String:
	return ammo_display_mode


func cycle_ammo_display_mode() -> String:
	var idx := AMMO_DISPLAY_MODES.find(ammo_display_mode)
	var next_mode: String = AMMO_DISPLAY_MODES[(idx + 1) % AMMO_DISPLAY_MODES.size()]
	set_ammo_display_mode(next_mode)
	return next_mode


func _apply_ammo_display_mode() -> void:
	var show_graphic := ammo_display_mode != "numeric"
	var show_numeric := ammo_display_mode != "graphic"
	var graphic_focus := ammo_display_mode == "graphic"
	if _ammo_well != null:
		_ammo_well.visible = show_graphic
		_ammo_well.custom_minimum_size = Vector2(96, 116) if graphic_focus else Vector2(80, 114)
		var well_style := _ammo_well.get_theme_stylebox("panel") as StyleBoxFlat
		if well_style != null:
			well_style.border_color = Color(PixelUI.AMBER_BRIGHT, 0.62) if graphic_focus \
				else Color(PixelUI.AMBER, 0.34)
	if ammo_container != null:
		ammo_container.visible = show_graphic
		ammo_container.custom_minimum_size = Vector2(86, 106) if graphic_focus else Vector2(70, 104)
	if _count != null:
		_count.visible = show_numeric
		_count.add_theme_font_size_override(
			"font_size", PixelUI.FS_TITLE + 4 if ammo_display_mode == "numeric" else PixelUI.FS_TITLE)
	if _reserve != null:
		_reserve.add_theme_font_size_override(
			"font_size", PixelUI.FS_BODY + 4 if graphic_focus else PixelUI.FS_BODY)
		_reserve.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if graphic_focus else HORIZONTAL_ALIGNMENT_RIGHT
	if _mode_badge != null:
		_mode_badge.text = String(AMMO_DISPLAY_LABELS.get(ammo_display_mode, "[J] 图文"))


func set_pickup_merge_window(seconds: float) -> void:
	pickup_merge_window = clampf(seconds, 0.0, 10.0)


func get_pickup_merge_window() -> float:
	return pickup_merge_window


func _build_minimap() -> void:
	_minimap = Minimap2D.new()
	_root.add_child(_minimap)


## 局内 BGM 切歌提示角标（位于左上操作提示栏下方，切歌/进出战斗时淡入展示 3.5s）。
func _build_bgm_toast() -> void:
	_bgm_toast = PanelContainer.new()
	_bgm_toast.name = "BgmToast"
	_bgm_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bgm_toast.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_bgm_toast.offset_left = 18
	_bgm_toast.offset_top = 60
	_bgm_toast.offset_right = 400
	_bgm_toast.offset_bottom = 92
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.06, 0.09, 0.86)
	st.border_color = Color(PixelUI.CYAN, 0.72)
	st.set_border_width_all(1)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	_bgm_toast.add_theme_stylebox_override("panel", st)
	_bgm_toast_label = PixelUI.label(_bgm_toast, "", 16, PixelUI.CYAN)
	_bgm_toast.visible = false
	_root.add_child(_bgm_toast)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_signal("bgm_track_changed"):
		sfx.bgm_track_changed.connect(_on_bgm_track_changed)
		var cur_t := String(sfx.bgm_current_title()) if sfx.has_method("bgm_current_title") else ""
		if not cur_t.is_empty():
			show_bgm_toast(cur_t)


func _exit_tree() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_signal("bgm_track_changed") and sfx.bgm_track_changed.is_connected(_on_bgm_track_changed):
		sfx.bgm_track_changed.disconnect(_on_bgm_track_changed)


func _on_bgm_track_changed(info: Dictionary) -> void:
	var title := String(info.get("title", ""))
	if not title.is_empty():
		show_bgm_toast(title)


func show_bgm_toast(title: String) -> void:
	if _bgm_toast == null or _bgm_toast_label == null:
		return
	_bgm_toast_label.text = "♪ 正在播放：%s" % title
	_bgm_toast.modulate.a = 1.0
	_bgm_toast.visible = true
	_bgm_toast_t = 3.5


## 左下：生成式金属板 + 两行信息（生命/资源、目标），不再放头像。
func _build_status_plate() -> void:
	var plate := TextureRect.new()
	plate.texture = PLATE_TEX
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(plate)
	plate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	plate.offset_left = PLATE_POS.x
	plate.offset_top = PLATE_POS.y
	plate.offset_right = PLATE_POS.x + PLATE_SIZE.x
	plate.offset_bottom = PLATE_POS.y + PLATE_SIZE.y

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	plate.add_child(margin)

	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	rows.add_child(top_row)
	_health = SegmentBar.new()
	_health.segments = 18
	_health.color_low = PixelUI.HP_LOW
	_health.color_high = PixelUI.HP_HIGH
	_health.custom_minimum_size.y = 20
	_health.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_health)
	hp_label = PixelUI.emphasize(PixelUI.label(top_row, "-- / --", PixelUI.FS_BODY, PixelUI.HP_HIGH), 3, 2)
	hp_label.custom_minimum_size.x = 104
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var armor_row := HBoxContainer.new()
	armor_row.add_theme_constant_override("separation", 10)
	rows.add_child(armor_row)
	_armor_bar = SegmentBar.new()
	_armor_bar.segments = 18
	_armor_bar.color_low = Color(0.28, 0.56, 0.86)
	_armor_bar.color_high = PixelUI.CYAN
	_armor_bar.custom_minimum_size.y = 12
	_armor_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armor_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	armor_row.add_child(_armor_bar)
	armor_label = PixelUI.emphasize(PixelUI.label(armor_row, "护甲 --", PixelUI.FS_BODY, PixelUI.CYAN), 3, 2)
	armor_label.custom_minimum_size.x = 104
	armor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	armor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	objective_label = PixelUI.emphasize(PixelUI.label(rows, "", 22, PixelUI.GOLD), 2, 1)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	objective_label.clip_text = true

	# 左下状态板右侧翻滚/躲闪冷却指示器（与右下快慢机拨片镜像对称）。
	dodge_indicator = DODGE_INDICATOR.new()
	dodge_indicator.name = "DodgeIndicator"
	_root.add_child(dodge_indicator)
	dodge_indicator.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dodge_indicator.offset_left = PLATE_POS.x + PLATE_SIZE.x + 10
	dodge_indicator.offset_right = PLATE_POS.x + PLATE_SIZE.x + 10 + 82
	dodge_indicator.offset_top = -16 - 82
	dodge_indicator.offset_bottom = -16


## 操作提示：左上角半透明战术胶囊条 + 彩色高亮按键名，亮暗画面均可一眼辨读。
func _build_hint() -> void:
	_hint_bar = PanelContainer.new()
	_hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.012, 0.018, 0.026, 0.72)
	hs.border_color = Color(PixelUI.AMBER, 0.45)
	hs.border_width_left = 3
	hs.border_width_bottom = 1
	hs.content_margin_left = 12
	hs.content_margin_right = 14
	hs.content_margin_top = 5
	hs.content_margin_bottom = 5
	_hint_bar.add_theme_stylebox_override("panel", hs)
	_root.add_child(_hint_bar)
	_hint_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint_bar.offset_left = 20
	_hint_bar.offset_top = 16
	_hint_bar.offset_right = 1040
	_hint_bar.offset_bottom = 48

	hint_label = PixelUI.label(_hint_bar, "", 19, PixelUI.DIM)
	hint_label.visible = false
	_hint_rich = PixelUI.rich_label(_hint_bar, "", 19, PixelUI.TEXT, 2)
	_hint_rich.autowrap_mode = TextServer.AUTOWRAP_OFF

	_interact_bar = PanelContainer.new()
	_interact_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var istyle := StyleBoxFlat.new()
	istyle.bg_color = Color(0.016, 0.024, 0.036, 0.86)
	istyle.border_color = PixelUI.AMBER_BRIGHT
	istyle.border_width_left = 4
	istyle.border_width_top = 1
	istyle.border_width_right = 1
	istyle.border_width_bottom = 1
	istyle.content_margin_left = 12
	istyle.content_margin_right = 16
	istyle.content_margin_top = 6
	istyle.content_margin_bottom = 6
	_interact_bar.add_theme_stylebox_override("panel", istyle)
	_root.add_child(_interact_bar)
	_interact_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_interact_bar.offset_left = 20
	_interact_bar.offset_top = 54
	_interact_bar.offset_right = 560
	_interact_bar.offset_bottom = 92
	_interact_bar.hide()

	interact_label = PixelUI.emphasize(PixelUI.label(_interact_bar, "", 22, PixelUI.TEXT), 3, 2)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	interact_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interact_label.clip_text = true
	interact_label.hide()


## 左侧拾取信息流：底部对齐，新消息以半透明战术胶囊条从下方出现，旧消息上移并淡出。
func _build_pickup_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 5)
	_feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_feed.offset_left = 24
	_feed.offset_right = 560
	_feed.offset_top = -560
	_feed.offset_bottom = -164
	_root.add_child(_feed)


## 拾取反馈：带图标/分类标签/稀有高亮的战术胶囊条，短时间内同项拾取自动合并计数。
func push_pickup(text: String, color: Color, opts: Dictionary = {}) -> void:
	if _feed == null:
		return
	var merge_key := String(opts.get("merge_key", ""))
	var add_amt := int(opts.get("amount", 0))
	var merge_fmt := String(opts.get("merge_fmt", ""))
	var merge_life := maxf(FEED_LIFE, pickup_merge_window + 0.6) if (merge_key != "" and pickup_merge_window > 0.001) else FEED_LIFE
	if pickup_merge_window > 0.001 and merge_key != "" and add_amt > 0 and merge_fmt != "":
		for i in range(_feed_items.size() - 1, -1, -1):
			var existing: Dictionary = _feed_items[i]
			if String(existing.get("merge_key", "")) != merge_key:
				continue
			if float(existing.get("merge_idle", 99.0)) > pickup_merge_window:
				continue
			var total_amt := int(existing.get("amount", 0)) + add_amt
			existing["amount"] = total_amt
			existing["t"] = merge_life
			existing["merge_idle"] = 0.0
			existing["pulse"] = 1.0
			var new_text := merge_fmt % total_amt
			var rt = existing.get("rich")
			if rt is RichTextLabel and is_instance_valid(rt):
				rt.text = _format_pickup_bbcode(new_text, color)
			return

	var is_rare := bool(opts.get("rare", false))
	var icon_name := String(opts.get("icon", ""))
	var badge_text := String(opts.get("badge", ""))
	if is_rare and badge_text == "":
		badge_text = "稀有"

	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		lerpf(0.015, color.r, 0.09 if is_rare else 0.04),
		lerpf(0.022, color.g, 0.09 if is_rare else 0.04),
		lerpf(0.032, color.b, 0.09 if is_rare else 0.04),
		0.88 if is_rare else 0.80)
	style.border_color = color.lightened(0.18) if is_rare else Color(color, 0.55)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 10
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", style)
	_feed.add_child(pill)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)

	var icon_path := PixelUI.ICON_ROOT + icon_name + ".png"
	if icon_name != "" and ResourceLoader.exists(icon_path):
		var icon := PixelUI.icon(row, icon_name, 20)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		var dot := ColorRect.new()
		dot.color = color.lightened(0.15)
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)

	if badge_text != "":
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bstyle := StyleBoxFlat.new()
		var bcol := PixelUI.GOLD if is_rare else color
		bstyle.bg_color = Color(bcol.r, bcol.g, bcol.b, 0.18)
		bstyle.border_color = Color(bcol.r, bcol.g, bcol.b, 0.72)
		bstyle.set_border_width_all(1)
		bstyle.content_margin_left = 5
		bstyle.content_margin_right = 5
		bstyle.content_margin_top = 1
		bstyle.content_margin_bottom = 1
		badge.add_theme_stylebox_override("panel", bstyle)
		row.add_child(badge)
		PixelUI.label(badge, badge_text, 14, bcol.lightened(0.22))

	var rich := PixelUI.rich_label(row, _format_pickup_bbcode(text, color), 21, color, 2)
	rich.autowrap_mode = TextServer.AUTOWRAP_OFF
	rich.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PixelUI.play_typewriter(rich)

	_feed_items.append({
		"label": pill,
		"rich": rich,
		"t": merge_life,
		"age": 0.0,
		"merge_idle": 0.0,
		"pulse": 0.0,
		"merge_key": merge_key,
		"amount": add_amt,
		"rare": is_rare,
	})
	while _feed_items.size() > FEED_MAX:
		var old: Dictionary = _feed_items.pop_front()
		var old_label = old["label"]
		if is_instance_valid(old_label):
			old_label.queue_free()


## 高亮拾取行中的数量字样（+N / ×N），让数量与物品名层次分明。
static func _format_pickup_bbcode(text: String, color: Color) -> String:
	var out := ""
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if (ch == "+" or ch == "×") and i + 1 < n and text[i + 1].is_valid_int():
			var j := i + 1
			while j < n and text[j].is_valid_int():
				j += 1
			out += PixelUI.bb(text.substr(i, j - i), PixelUI.GOLD.lerp(Color.WHITE, 0.35))
			i = j
		else:
			out += ch
			i += 1
	return PixelUI.bb(out, color.lightened(0.08))


## 右下：独立图形化供弹容器展示区 + 枪名 / 弹匣数值 / 备弹 / 状态 / 换弹进度，共用生成式金属底板。
func _build_weapon_panel() -> void:
	var plate := TextureRect.new()
	plate.texture = WEAPON_PLATE_TEX
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(plate)
	plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	plate.offset_left = -24 - WEAPON_PLATE_SIZE.x
	plate.offset_top = -24 - WEAPON_PLATE_SIZE.y
	plate.offset_right = -24
	plate.offset_bottom = -24

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	plate.add_child(margin)

	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)

	# 左侧独立弹药容器展示区（支持 6 种供弹轮廓 + 预留弹箱，graphic 模式下自动放大突出）。
	_ammo_well = PanelContainer.new()
	_ammo_well.name = "AmmoContainerWell"
	_ammo_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_well.custom_minimum_size = Vector2(80, 114)
	_ammo_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var well_style := StyleBoxFlat.new()
	well_style.bg_color = Color(0.010, 0.014, 0.020, 0.72)
	well_style.border_color = Color(PixelUI.AMBER, 0.34)
	well_style.set_border_width_all(1)
	well_style.content_margin_left = 4
	well_style.content_margin_right = 4
	well_style.content_margin_top = 4
	well_style.content_margin_bottom = 4
	_ammo_well.add_theme_stylebox_override("panel", well_style)
	body.add_child(_ammo_well)

	ammo_container = AMMO_CONTAINER.new()
	ammo_container.name = "AmmoContainer2D"
	ammo_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ammo_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ammo_well.add_child(ammo_container)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 5)
	body.add_child(rows)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 8)
	rows.add_child(title_row)
	_title = PixelUI.emphasize(PixelUI.label(title_row, "G17 // 9MM", 20, PixelUI.AMBER_BRIGHT), 2, 1)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_state = PixelUI.emphasize(PixelUI.label(title_row, "就绪", 20, PixelUI.OK), 2, 1)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var count_row := HBoxContainer.new()
	count_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_row.add_theme_constant_override("separation", 8)
	rows.add_child(count_row)
	_count = PixelUI.emphasize(PixelUI.label(count_row, "-- / --", PixelUI.FS_TITLE, PixelUI.TEXT), 3, 2)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ammo_label = _count
	_reserve = PixelUI.emphasize(PixelUI.label(count_row, "备弹 --", PixelUI.FS_BODY, PixelUI.DIM), 2, 1)
	_reserve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reserve.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var meta_row := HBoxContainer.new()
	meta_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_theme_constant_override("separation", 8)
	rows.add_child(meta_row)
	_ammo_name = PixelUI.label(meta_row, "9mm", 18, PixelUI.AMBER)
	_ammo_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ammo_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ammo_name.clip_text = true
	_mode_badge = PixelUI.label(meta_row, "[J] 图文", 15, Color(PixelUI.DIM, 0.85))
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_progress = PixelUI.bar(6)
	_progress.max_value = 100
	_progress.value = 0
	rows.add_child(_progress)
	_apply_ammo_display_mode()

	# 武器面板左侧快慢机拨片：参照机匣拨片造型，支持鼠标左键点击与 B 键切换全自动/半自动。
	fire_selector = FireSelectorWidget2D.new()
	fire_selector.name = "FireSelector"
	_root.add_child(fire_selector)
	fire_selector.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_selector.offset_left = -24 - WEAPON_PLATE_SIZE.x - 10 - 76
	fire_selector.offset_right = -24 - WEAPON_PLATE_SIZE.x - 10
	fire_selector.offset_top = -24 - 82
	fire_selector.offset_bottom = -24
	fire_selector.toggled.connect(func() -> void: fire_mode_toggle_requested.emit())


## 鼠标指针是否正位于 HUD 可点击控件（如快慢机拨片）上，供 WeaponRig2D 拦截误开火。
func is_pointer_over_interactive() -> bool:
	if not visible or fire_selector == null or not fire_selector.visible:
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	return fire_selector.get_global_rect().has_point(vp.get_mouse_position())


## 结算界面：结构与 TAB 背包一致（左右分栏），但只展示本局带出的物资与战斗统计。
func _build_result_panel() -> void:
	_result_panel = PixelUI.panel()
	_root.add_child(_result_panel)
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.offset_left = -550
	_result_panel.offset_right = 550
	_result_panel.offset_top = -322
	_result_panel.offset_bottom = 322
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_result_panel.add_child(rows)

	var header := HBoxContainer.new()
	rows.add_child(header)
	var title := PixelUI.label(header, "行动结算 // DEBRIEF", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.label(header, "SESSION K-17", PixelUI.FS_BODY, PixelUI.DIM)

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	result_label = PixelUI.label(rows, "", PixelUI.FS_TITLE, PixelUI.TEXT)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail = PixelUI.label(rows, "", PixelUI.FS_BODY, PixelUI.DIM)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	columns.add_child(_build_debrief_loot())
	columns.add_child(_build_debrief_stats())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_child(buttons)
	return_button = PixelUI.button("返回基地", 46)
	return_button.custom_minimum_size.x = 260
	return_button.pressed.connect(func() -> void: return_requested.emit())
	buttons.add_child(return_button)
	restart_button = PixelUI.button("重新开始", 46)
	restart_button.custom_minimum_size.x = 260
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	buttons.add_child(restart_button)

	var tip := PixelUI.label(rows, "按 R 重新开始 · ESC 返回基地", PixelUI.FS_BODY, PixelUI.DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.hide()
	result_label.hide()
	result_detail.hide()
	return_button.hide()
	restart_button.hide()


## 左栏：带出物资，逐行显示图标 + 全名 + 数量；数量为 0 的行隐藏。
func _build_debrief_loot() -> Control:
	var panel := _debrief_column()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	PixelUI.label(rows, "带出物资 // EXTRACTED", PixelUI.FS_BODY, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	for id in ResourceDB.BASIC:
		_debrief_loot_row(rows, id)
	PixelUI.label(rows, "进阶 // RARE", 20, PixelUI.DIM)
	for id in ResourceDB.ADVANCED:
		_debrief_loot_row(rows, id)
	_debrief_empty = PixelUI.label(rows, "空手而归", PixelUI.FS_BODY, PixelUI.DIM)
	_debrief_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


func _debrief_loot_row(parent: Node, id: StringName) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	PixelUI.icon(row, "res_" + String(id), 26)
	var name_label := PixelUI.label(row, ResourceDB.display_name(id), 20, PixelUI.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := PixelUI.label(row, "×0", 20, PixelUI.DIM)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debrief_loot_labels[String(id)] = {"row": row, "count": count}


## 右栏：战斗统计。
func _build_debrief_stats() -> Control:
	var panel := _debrief_column()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	panel.add_child(rows)
	PixelUI.label(rows, "战斗统计 // COMBAT", PixelUI.FS_BODY, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	rows.add_child(divider)
	var stats := [
		["kills", "击杀敌人"], ["damage", "造成伤害"],
		["accuracy", "命中率"], ["shots", "射击次数"], ["time", "行动用时"],
	]
	for entry in stats:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var name_label := PixelUI.label(row, String(entry[1]), 20, PixelUI.DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value := PixelUI.label(row, "-", 20, PixelUI.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		debrief_stat_labels[String(entry[0])] = value
	return panel


func _debrief_column() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.AMBER, 0.35))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func set_hp(current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / maxf(1.0, float(maximum)), 0.0, 1.0)
	_health.set_ratio(ratio)
	hp_label.text = "%d / %d" % [current, maximum]
	var tier := 0 if ratio < 0.30 else (1 if ratio < 0.65 else 2)
	if tier != _hp_tier:
		_hp_tier = tier
		var col := PixelUI.DANGER if tier == 0 else (PixelUI.GOLD if tier == 1 else PixelUI.HP_HIGH)
		hp_label.add_theme_color_override("font_color", col)


func set_armor(current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / maxf(1.0, float(maximum)), 0.0, 1.0)
	_armor_bar.set_ratio(ratio)
	armor_label.text = "护甲 %d" % current
	var broken := current <= 0
	if broken != _armor_broken:
		_armor_broken = broken
		armor_label.add_theme_color_override(
			"font_color", PixelUI.DANGER if broken else PixelUI.CYAN)


func set_dodge(ready_ratio: float, dodging: bool, invuln: bool, cooldown_left: float) -> void:
	if dodge_indicator != null:
		dodge_indicator.set_dodge_state(ready_ratio, dodging, invuln, cooldown_left)


func set_objective(text: String) -> void:
	objective_label.text = text
	var col := PixelUI.OK if (text.contains("已通电") or text.contains("可撤离")) else PixelUI.GOLD
	objective_label.add_theme_color_override("font_color", col)


func set_hint(text: String) -> void:
	hint_label.text = text
	if _hint_rich != null:
		_hint_rich.text = _format_hint_bbcode(text)


## 自动将操作提示中的按键（WASD / 左键 / 右键 / B / R / X / TAB / Alt+滚轮 / E / M）着色加重。
static func _format_hint_bbcode(text: String) -> String:
	var out := text
	for key in ["WASD", "SPACE", "Alt+滚轮", "左键", "右键", "TAB", "ESC", " Q ", " B ", " R ", " X ", " E ", " M "]:
		var ks := String(key)
		var trimmed := ks.strip_edges()
		if out.contains(ks):
			out = out.replace(ks, ks.replace(trimmed, PixelUI.bb(trimmed, PixelUI.GOLD)))
	return out


## 左上角交互目标：显示可搜刮容器名字，并按稀有度着色。
func set_interact_target(text: String, color: Color) -> void:
	if interact_label == null:
		return
	interact_label.text = text
	interact_label.add_theme_color_override("font_color", color)
	interact_label.show()
	if _interact_bar != null:
		var sb := _interact_bar.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.border_color = color
		_interact_bar.show()


func clear_interact_target() -> void:
	if interact_label != null:
		interact_label.hide()
	if _interact_bar != null:
		_interact_bar.hide()


## 拾取/交互提示：左上提示临时变成亮绿色，2.2 秒后恢复。
func flash(text: String) -> void:
	hint_label.text = text
	hint_label.add_theme_color_override("font_color", PixelUI.OK)
	if _hint_rich != null:
		_hint_rich.text = PixelUI.bb(text, PixelUI.OK)
		PixelUI.play_typewriter(_hint_rich)
	_flash_t = 2.2


func update_weapon(rig) -> void:
	if rig == null or rig.data == null:
		_title.text = "未装备武器"
		_ammo_name.text = ""
		_reserve.text = ""
		_count.text = "--"
		_state.text = ""
		if ammo_container != null:
			ammo_container.configure(0, 0, &"stick_mag", 1.0, false, ammo_exact_rounds)
		_progress.value = 0.0
		if fire_selector != null:
			fire_selector.visible = false
		return
	var data = rig.data
	if fire_selector != null:
		fire_selector.visible = true
		var can_auto := bool(rig.supports_full_auto()) if rig.has_method("supports_full_auto") else bool(data.auto_fire)
		var mode := String(rig.get_fire_mode()) if rig.has_method("get_fire_mode") else ("auto" if can_auto else "semi")
		fire_selector.set_state(mode, can_auto)
	var ammo: AmmoData = WeaponDB.get_ammo(data.ammo_id)
	var short_name: String = String(data.display_name).split(" // ")[0]
	_title.text = "%s // %s" % [short_name, data.caliber_label]
	if ammo != null:
		var eff_ap := maxf(0.0, float(ammo.ap) + float(data.ap_bonus))
		var eff_tier := WeaponDB.tier_from_rha(eff_ap)
		var cost_tag := "" if ammo.reserve_cost <= 1.01 else " ×%.1f" % ammo.reserve_cost
		_ammo_name.text = "[%s] %s%s" % [WeaponDB.tier_label(eff_tier), ammo.short_name, cost_tag]
		_ammo_name.add_theme_color_override("font_color", WeaponDB.tier_color(eff_tier))
	var reserve_cnt: int = rig.get_reserve()
	_reserve.text = "备弹 %d" % reserve_cnt
	_reserve.add_theme_color_override(
		"font_color", PixelUI.DANGER if reserve_cnt <= 0 else (PixelUI.TEXT if ammo_display_mode == "graphic" else PixelUI.DIM))
	_count.text = "%d / %d" % [rig.mag, data.mag_capacity]
	var mag_ratio := float(rig.mag) / maxf(1.0, float(data.mag_capacity))
	var count_col := PixelUI.DANGER if rig.mag <= 0 \
		else (PixelUI.GOLD if mag_ratio <= 0.25 else PixelUI.TEXT)
	_count.add_theme_color_override("font_color", count_col)
	var reloading: bool = rig.reload_t > 0.0
	if ammo_container != null:
		var style: StringName = data.mag_style if ("mag_style" in data) else WeaponDB.mag_style(data.id)
		var scale_ratio: float = float(data.mag_scale) if ("mag_scale" in data) else 1.0
		ammo_container.configure(rig.mag, data.mag_capacity, style, scale_ratio, reloading, ammo_exact_rounds)
	var switching: bool = rig.switch_t > 0.0
	var state_color := PixelUI.OK
	if rig.is_drawing():
		_state.text = "拔枪中"
		state_color = PixelUI.AMBER
	elif rig.is_stowing():
		_state.text = "收枪中"
		state_color = PixelUI.AMBER
	elif rig.is_holstered():
		_state.text = "已收枪"
		state_color = PixelUI.DIM
	elif reloading:
		var pending_aid: StringName = rig.get_pending_ammo_id() if rig.has_method("get_pending_ammo_id") else &""
		if pending_aid != &"":
			var p_ammo := WeaponDB.get_ammo(pending_aid)
			_state.text = "切弹→%s" % (WeaponDB.role_label(p_ammo.role) if p_ammo != null else "")
			state_color = PixelUI.CYAN
		else:
			_state.text = "装填中"
			state_color = PixelUI.DANGER
	elif switching:
		_state.text = "切枪中"
		state_color = PixelUI.AMBER
	elif rig.mag <= 0:
		_state.text = "空仓"
		state_color = PixelUI.DANGER
	else:
		_state.text = "就绪"
	_state.add_theme_color_override("font_color", state_color)
	# 换弹显示换弹进度，收/拔枪显示收拔枪进度，其余保持空槽
	var progress := 0.0
	if reloading:
		progress = rig.get_reload_progress()
	elif rig.is_drawing() or rig.is_stowing():
		progress = rig.get_stow_progress()
	_progress.value = progress * 100.0


func show_result(success: bool, loot: Dictionary, advanced := {}, meta_reward := 0,
		xp_gain := 0, bonus_note := "", stats := {}) -> void:
	_result_panel.show()
	result_label.show()
	result_detail.show()
	return_button.show()
	restart_button.show()
	# 直接展示调用方传入的入仓物资；失败时 Main2D 传空表，浪潮阵亡则传入按比例回收的部分。
	_update_debrief_loot(loot, advanced)
	_update_debrief_stats(stats)
	if success:
		result_label.text = "撤离成功"
		result_label.add_theme_color_override("font_color", Color(0.82, 0.96, 0.82))
		var parts: Array[String] = []
		if meta_reward > 0 or xp_gain > 0:
			parts.append("信用点 +%d · +%d XP" % [meta_reward, xp_gain])
		if bonus_note != "":
			parts.append(bonus_note)
		result_detail.text = "    ".join(PackedStringArray(parts))
	else:
		result_label.text = "阵亡"
		result_label.add_theme_color_override("font_color", Color(0.96, 0.62, 0.58))
		var fail_parts: Array[String] = []
		if meta_reward > 0:
			fail_parts.append("回收信用点 +%d" % meta_reward)
		if bonus_note != "":
			fail_parts.append(bonus_note)
		if fail_parts.is_empty():
			result_detail.text = "本局物资全部丢失 · 仓库与装备保留"
		else:
			result_detail.text = "    ".join(PackedStringArray(fail_parts))
	PixelUI.play_typewriter(result_detail)


## 带出物资：只显示有产出的行，全部为 0 时给出空手提示。
func _update_debrief_loot(loot: Dictionary, advanced: Dictionary) -> void:
	var total := 0
	for id in ResourceDB.BASIC:
		var count := int(loot.get(String(id), 0))
		total += count
		_set_loot_row(String(id), count)
	for id in ResourceDB.ADVANCED:
		var count := int(advanced.get(String(id), 0))
		total += count
		_set_loot_row(String(id), count)
	if _debrief_empty != null:
		_debrief_empty.visible = total == 0


func _set_loot_row(id: String, count: int) -> void:
	var entry: Dictionary = debrief_loot_labels.get(id, {})
	if entry.is_empty():
		return
	var row: Control = entry["row"]
	var label: Label = entry["count"]
	row.visible = count > 0
	label.text = "×%d" % count


func _update_debrief_stats(stats: Dictionary) -> void:
	var shots := int(stats.get("shots", 0))
	var hits := int(stats.get("hits", 0))
	var accuracy := "—" if shots <= 0 else "%d%%" % int(round(float(hits) / float(shots) * 100.0))
	_set_stat_label("kills", "%d" % int(stats.get("kills", 0)))
	_set_stat_label("damage", "%d" % int(stats.get("damage", 0)))
	_set_stat_label("accuracy", accuracy)
	_set_stat_label("shots", "%d 发" % shots)
	_set_stat_label("time", _format_time(float(stats.get("time", 0.0))))


func _set_stat_label(key: String, text: String) -> void:
	var label: Label = debrief_stat_labels.get(key)
	if label != null:
		label.text = text


## 结算用时：MM:SS，超过一小时也只保留分钟。
func _format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var minutes := int(total / 60.0)
	return "%02d:%02d" % [minutes, total % 60]


func hide_result() -> void:
	_result_panel.hide()
	result_label.hide()
	result_detail.hide()
	return_button.hide()
	restart_button.hide()


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		if _flash_t <= 0.0:
			hint_label.add_theme_color_override("font_color", PixelUI.DIM)
			if _hint_rich != null:
				_hint_rich.text = _format_hint_bbcode(hint_label.text)
	var expired: Array[Dictionary] = []
	for item in _feed_items:
		item["t"] = float(item["t"]) - delta
		item["age"] = float(item.get("age", 0.0)) + delta
		item["merge_idle"] = float(item.get("merge_idle", 0.0)) + delta
		var pulse := maxf(float(item.get("pulse", 0.0)) - delta * 4.5, 0.0)
		item["pulse"] = pulse
		var line = item["label"]
		if not is_instance_valid(line):
			expired.append(item)
			continue
		var fade_in := clampf(float(item["age"]) / 0.14, 0.0, 1.0)
		var fade_out := clampf(float(item["t"]) / 0.75, 0.0, 1.0)
		var boost := 1.0 + pulse * 0.25
		line.modulate = Color(boost, boost, boost, minf(fade_in, fade_out))
		if float(item["t"]) <= 0.0:
			line.queue_free()
			expired.append(item)
	if _bgm_toast_t > 0.0 and _bgm_toast != null:
		_bgm_toast_t = maxf(_bgm_toast_t - delta, 0.0)
		_bgm_toast.modulate.a = clampf(_bgm_toast_t / 0.75, 0.0, 1.0)
		if _bgm_toast_t <= 0.0:
			_bgm_toast.visible = false
	for item in expired:
		_feed_items.erase(item)


## 像素机械快慢机拨片（F 全自动 / S 半自动）：置于右下武器面板左侧，支持鼠标点击与 B 键联动。
class FireSelectorWidget2D extends Control:
	signal toggled

	const PX := 2.0
	const PIVOT := Vector2(47.0, 44.0)
	const ANGLE_SEMI := PI
	const ANGLE_AUTO := -2.06  # 指向顶部 F 刻槽

	var fire_mode := "semi"
	var supports_auto := false
	var _hovered := false
	var _lever_t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(76, 82)
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw())

	func set_state(mode: String, can_auto: bool) -> void:
		var clean_mode := "auto" if (can_auto and mode == "auto") else "semi"
		var changed := (fire_mode != clean_mode) or (supports_auto != can_auto)
		fire_mode = clean_mode
		supports_auto = can_auto
		if supports_auto:
			tooltip_text = "全自动 (F) · 点击或按 B 切换半自动" if fire_mode == "auto" \
				else "半自动 (S) · 点击或按 B 切换全自动"
		else:
			tooltip_text = "半自动 (S) · 当前武器不支持全自动"
		if changed:
			queue_redraw()

	func _process(delta: float) -> void:
		var target := 1.0 if fire_mode == "auto" else 0.0
		if absf(_lever_t - target) > 0.002:
			_lever_t = move_toward(_lever_t, target, delta * 14.0)
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if event.pressed:
				toggled.emit()

	func _draw() -> void:
		var is_auto := fire_mode == "auto" and supports_auto
		# 1. 阶梯像素枪身机匣底座（参照机匣拨片轮廓，右下留出拨杆旋转弧缺口）。
		var outline := Color(PixelUI.AMBER_BRIGHT, 0.92) if _hovered else Color(0.05, 0.06, 0.07, 0.96)
		var body := Color(0.11, 0.12, 0.14, 0.96)
		var bevel := Color(0.20, 0.22, 0.26, 0.90)
		_draw_stepped_box(Rect2(4, 2, 66, 62), outline, body, bevel)

		# 2. 顶部红色 F 刻槽（全自动）。
		var f_rect := Rect2(26, 6, 22, 24)
		var f_border := Color(0.92, 0.26, 0.26) if is_auto else (Color(0.42, 0.16, 0.16) if supports_auto else Color(0.20, 0.22, 0.25))
		var f_bg := Color(0.18, 0.06, 0.07, 0.96) if is_auto else Color(0.08, 0.08, 0.09, 0.95)
		var f_glyph := Color(1.0, 0.32, 0.30) if is_auto else (Color(0.76, 0.20, 0.20) if supports_auto else Color(0.30, 0.32, 0.36))
		draw_rect(f_rect, f_border, true)
		draw_rect(f_rect.grow(-PX), f_bg, true)
		_draw_pixel_f(f_rect.position + Vector2(5, 4), f_glyph)
		if not supports_auto:
			draw_line(f_rect.position + Vector2(3, f_rect.size.y - 3),
				f_rect.position + Vector2(f_rect.size.x - 3, 3), Color(0.45, 0.48, 0.52, 0.55), 1.5)

		# 3. 左侧金色 S 刻槽（半自动）。
		var s_rect := Rect2(8, 34, 20, 24)
		var s_border := Color(0.92, 0.72, 0.22) if not is_auto else Color(0.44, 0.35, 0.16)
		var s_bg := Color(0.17, 0.13, 0.05, 0.96) if not is_auto else Color(0.09, 0.08, 0.06, 0.95)
		var s_glyph := Color(1.0, 0.80, 0.26) if not is_auto else Color(0.74, 0.56, 0.18)
		draw_rect(s_rect, s_border, true)
		draw_rect(s_rect.grow(-PX), s_bg, true)
		_draw_pixel_s(s_rect.position + Vector2(4, 4), s_glyph)

		# 4. 旋转金属拨杆 + 白色指向刻度线（指针指向 F 或 S，拇指尾翼落在右下/右侧）。
		var ang := lerp_angle(ANGLE_SEMI, ANGLE_AUTO, _lever_t)
		var dir := Vector2.from_angle(ang)
		var perp := Vector2(-dir.y, dir.x)
		var lever_outer := PackedVector2Array([
			PIVOT + dir * 18.0 + perp * 4.0,
			PIVOT + dir * 21.0,
			PIVOT + dir * 18.0 - perp * 4.0,
			PIVOT + dir * 6.0 - perp * 11.0,
			PIVOT - dir * 12.0 - perp * 11.0,
			PIVOT - dir * 21.0 - perp * 7.0,
			PIVOT - dir * 23.0,
			PIVOT - dir * 20.0 + perp * 7.0,
			PIVOT - dir * 8.0 + perp * 11.0,
			PIVOT + dir * 6.0 + perp * 11.0,
		])
		draw_colored_polygon(lever_outer, Color(0.05, 0.06, 0.07, 0.98))
		var lever_body := PackedVector2Array([
			PIVOT + dir * 16.0 + perp * 3.0,
			PIVOT + dir * 18.5,
			PIVOT + dir * 16.0 - perp * 3.0,
			PIVOT + dir * 5.0 - perp * 9.0,
			PIVOT - dir * 11.0 - perp * 9.0,
			PIVOT - dir * 19.0 - perp * 5.0,
			PIVOT - dir * 20.5,
			PIVOT - dir * 18.0 + perp * 5.0,
			PIVOT - dir * 7.0 + perp * 9.0,
			PIVOT + dir * 5.0 + perp * 9.0,
		])
		var steel := Color(0.24, 0.26, 0.30) if not _hovered else Color(0.30, 0.33, 0.38)
		draw_colored_polygon(lever_body, steel)
		# 上缘金属反光面与转轴鼓包。
		var lever_hi := PackedVector2Array([
			PIVOT + dir * 14.0 + perp * 1.0,
			PIVOT + dir * 4.0 - perp * 7.0,
			PIVOT - dir * 10.0 - perp * 7.0,
			PIVOT - dir * 15.0 - perp * 2.0,
			PIVOT - dir * 4.0 + perp * 2.0,
		])
		draw_colored_polygon(lever_hi, Color(0.34, 0.37, 0.42, 0.72))
		draw_circle(PIVOT, 8.5, Color(0.18, 0.20, 0.24))
		draw_circle(PIVOT, 5.5, Color(0.28, 0.30, 0.35))
		# 醒目白色指向槽线（复刻参考图中的白色指针标线）。
		var notch_a := PIVOT + dir * 3.0
		var notch_b := PIVOT + dir * 17.5
		draw_line(notch_a + perp * 1.5, notch_b + perp * 1.5, Color(0.06, 0.07, 0.08, 0.9), 2.5)
		draw_line(notch_a, notch_b, Color(0.94, 0.96, 0.98, 1.0), 2.5)

		# 5. 底部紧凑快捷键提示条（B · 全自动 / B · 半自动）。
		var tag_rect := Rect2(2, 66, 72, 15)
		draw_rect(tag_rect, Color(0.04, 0.05, 0.07, 0.88), true)
		var tag_border := Color(PixelUI.AMBER_BRIGHT, 0.85) if _hovered else Color(0.35, 0.40, 0.46, 0.55)
		draw_rect(tag_rect, tag_border, false, 1.0)
		var font: Font = get_theme_default_font()
		if font == null:
			font = ThemeDB.fallback_font
		var mode_tag := "B·全自动" if is_auto else ("B·半自动" if supports_auto else "仅半自动")
		var mode_col := Color(1.0, 0.44, 0.40) if is_auto else (Color(1.0, 0.82, 0.32) if supports_auto else Color(0.58, 0.62, 0.66))
		draw_string(font, Vector2(tag_rect.position.x, tag_rect.position.y + 11.5),
			mode_tag, HORIZONTAL_ALIGNMENT_CENTER, tag_rect.size.x, 11, mode_col)

	func _draw_stepped_box(r: Rect2, outline: Color, fill: Color, bevel: Color) -> void:
		# 阶梯切角像素外壳（模拟像素图圆角机匣）。
		draw_rect(Rect2(r.position.x + 6, r.position.y, r.size.x - 12, r.size.y), outline, true)
		draw_rect(Rect2(r.position.x + 2, r.position.y + 4, r.size.x - 4, r.size.y - 8), outline, true)
		draw_rect(Rect2(r.position.x, r.position.y + 8, r.size.x, r.size.y - 16), outline, true)
		draw_rect(Rect2(r.position.x + 8, r.position.y + 2, r.size.x - 16, r.size.y - 4), fill, true)
		draw_rect(Rect2(r.position.x + 4, r.position.y + 6, r.size.x - 8, r.size.y - 12), fill, true)
		draw_rect(Rect2(r.position.x + 2, r.position.y + 10, r.size.x - 4, r.size.y - 20), fill, true)
		draw_rect(Rect2(r.position.x + 8, r.position.y + 2, r.size.x - 16, 2), bevel, true)
		draw_rect(Rect2(r.position.x + 2, r.position.y + 10, 2, r.size.y - 24), bevel, true)

	func _draw_pixel_f(o: Vector2, col: Color) -> void:
		draw_rect(Rect2(o + Vector2(0, 0), Vector2(4, 16)), col, true)
		draw_rect(Rect2(o + Vector2(0, 0), Vector2(12, 3)), col, true)
		draw_rect(Rect2(o + Vector2(0, 7), Vector2(10, 3)), col, true)

	func _draw_pixel_s(o: Vector2, col: Color) -> void:
		draw_rect(Rect2(o + Vector2(2, 0), Vector2(8, 3)), col, true)
		draw_rect(Rect2(o + Vector2(0, 2), Vector2(3, 5)), col, true)
		draw_rect(Rect2(o + Vector2(2, 6), Vector2(8, 3)), col, true)
		draw_rect(Rect2(o + Vector2(9, 8), Vector2(3, 6)), col, true)
		draw_rect(Rect2(o + Vector2(2, 13), Vector2(8, 3)), col, true)
		draw_rect(Rect2(o + Vector2(0, 11), Vector2(3, 3)), col, true)
		draw_rect(Rect2(o + Vector2(9, 2), Vector2(3, 2)), col, true)
