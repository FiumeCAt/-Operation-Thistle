extends CanvasLayer
class_name FpsOverlay2D
## 全局轻量 FPS 帧率浮层（由 Progress 自动挂载并响应设置开关 `show_fps`）：
## - 关闭时完全隐藏且停止 _process（零每帧开销）；
## - 开启时每 0.20s 刷新一次帧率与帧耗时，自动避让战斗右上角小地图（贴小地图正下方），
##   在主菜单 / 地图遮罩等界面自动贴右上角顶栏上方，不遮挡操作与 HUD。

const UPDATE_INTERVAL := 0.20
const PILL_WIDTH := 152.0
const PILL_HEIGHT := 26.0
const RIGHT_MARGIN_MENU := 10.0
const RIGHT_MARGIN_HUD := 24.0
const TOP_DEFAULT := 8.0

var _enabled := false
var _root: Control
var _pill: PanelContainer
var _label: Label
var _accent_bar: StyleBoxFlat
var _accum_time := 0.0
var _accum_frames := 0
var _anchor_tick := 0.0
var _last_top := -1.0
var _last_right := -1.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	set_enabled(_enabled)


func _build() -> void:
	_root = Control.new()
	_root.name = "FpsOverlayRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_pill = PanelContainer.new()
	_pill.name = "FpsPill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent_bar = StyleBoxFlat.new()
	_accent_bar.bg_color = Color(0.012, 0.018, 0.026, 0.80)
	_accent_bar.border_color = PixelUI.OK
	_accent_bar.border_width_left = 3
	_accent_bar.border_width_top = 1
	_accent_bar.border_width_right = 1
	_accent_bar.border_width_bottom = 1
	_accent_bar.content_margin_left = 8
	_accent_bar.content_margin_right = 8
	_accent_bar.content_margin_top = 2
	_accent_bar.content_margin_bottom = 2
	_pill.add_theme_stylebox_override("panel", _accent_bar)
	_root.add_child(_pill)

	_label = Label.new()
	_label.name = "FpsLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", PixelUI.FONT)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", PixelUI.OK)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	_label.add_theme_constant_override("outline_size", 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = "FPS -- · --ms"
	_pill.add_child(_label)

	_apply_position(TOP_DEFAULT, RIGHT_MARGIN_MENU)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	set_process(enabled)
	if enabled:
		_accum_time = 0.0
		_accum_frames = 0
		_anchor_tick = 0.0
		_update_anchor()
		_refresh_text(Engine.get_frames_per_second(), 0.0)


func is_enabled() -> bool:
	return _enabled


func current_text() -> String:
	return _label.text if _label != null else ""


func _process(delta: float) -> void:
	_accum_time += delta
	_accum_frames += 1
	_anchor_tick += delta
	if _anchor_tick >= 0.15:
		_anchor_tick = 0.0
		_update_anchor()
	if _accum_time >= UPDATE_INTERVAL:
		var avg_ms := (_accum_time / float(maxi(1, _accum_frames))) * 1000.0
		var fps := int(round(float(_accum_frames) / maxf(_accum_time, 0.0001)))
		if fps <= 0:
			fps = int(round(Engine.get_frames_per_second()))
		_refresh_text(float(fps), avg_ms)
		_accum_time = 0.0
		_accum_frames = 0


func _refresh_text(fps_val: float, frame_ms: float) -> void:
	if _label == null:
		return
	var fps_i := maxi(0, int(round(fps_val)))
	var ms := frame_ms if frame_ms > 0.01 else (1000.0 / float(fps_i) if fps_i > 0 else 0.0)
	_label.text = "FPS %d · %.1fms" % [fps_i, ms]
	var col := PixelUI.OK if fps_i >= 55 else (PixelUI.GOLD if fps_i >= 30 else PixelUI.DANGER)
	_label.add_theme_color_override("font_color", col)
	if _accent_bar != null:
		_accent_bar.border_color = col


func _update_anchor() -> void:
	var target_top := TOP_DEFAULT
	var target_right := RIGHT_MARGIN_MENU
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var hud = tree.current_scene.get("hud")
		if hud is CanvasLayer and is_instance_valid(hud) and (hud as CanvasLayer).visible:
			var minimap = hud.get("_minimap")
			if minimap is Control and is_instance_valid(minimap) and (minimap as Control).visible:
				var rect := (minimap as Control).get_global_rect()
				if rect.size.y > 16.0:
					target_top = rect.end.y + 6.0
					target_right = RIGHT_MARGIN_HUD
	if absf(target_top - _last_top) > 0.5 or absf(target_right - _last_right) > 0.5:
		_apply_position(target_top, target_right)


func _apply_position(top_y: float, right_margin: float) -> void:
	_last_top = top_y
	_last_right = right_margin
	if _pill == null:
		return
	_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pill.offset_right = -right_margin
	_pill.offset_left = -right_margin - PILL_WIDTH
	_pill.offset_top = top_y
	_pill.offset_bottom = top_y + PILL_HEIGHT
