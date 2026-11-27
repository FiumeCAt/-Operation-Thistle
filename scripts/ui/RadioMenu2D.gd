extends Control
class_name RadioMenu2D
## 游戏内「战术电台」面板：
## 1) 展示当前正在播放的 BGM 曲名、曲池来源（内置 / 自定义）与播放模式；
## 2) 支持三种播放模式（随机轮播 / 顺序播放 / 固定单曲）并持久化至 Progress；
## 3) 支持上一曲 / 下一曲 / 锁定当前曲 / 刷新自定义曲库，自动识别 res://assets/audio/bgm/ 与 user://bgm/ 下的 .ogg / .mp3 / .wav。

signal closed

const PANEL_SIZE := Vector2(820, 580)
const MODE_DEFS: Array[Dictionary] = [
	{"id": "shuffle", "label": "随机轮播", "tip": "同池随机切歌，自动防连播同一首"},
	{"id": "sequential", "label": "顺序播放", "tip": "按曲目列表依次循环播放"},
	{"id": "single", "label": "固定单曲", "tip": "非战斗状态下锁定播放当前选定曲目"},
]

var _panel: PixelUI.PixelPanel
var _title_label: Label
var _divider: HSeparator
var now_playing_label: Label
var _now_title: Label
var _now_meta: Label
var _mode_hint: Label
var _dir_hint: Label
var _mode_buttons: Dictionary = {}
var _track_list: VBoxContainer
var _track_buttons: Dictionary = {}
var _close_button: Button
var _sfx_connected := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	PixelUI.apply_theme(self)
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -PANEL_SIZE.x * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5
	_panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_bottom = PANEL_SIZE.y * 0.5
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_panel.add_child(rows)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	rows.add_child(hdr)
	_title_label = PixelUI.emphasize(
		PixelUI.label(hdr, "战术电台", PixelUI.FS_TITLE, PixelUI.theme_accent()), 2, 1)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var esc_lbl := PixelUI.label(hdr, "ESC 关闭", 16, PixelUI.theme_dim())
	esc_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_divider = HSeparator.new()
	_divider.add_theme_color_override("color", PixelUI.theme_accent())
	rows.add_child(_divider)

	# 正在播放信息卡
	var now_box := PanelContainer.new()
	var nst := PixelUI.panel_style(PixelUI.BG_LIGHT, 1, Color(PixelUI.theme_accent(), 0.45))
	nst.content_margin_left = 14
	nst.content_margin_right = 14
	nst.content_margin_top = 10
	nst.content_margin_bottom = 10
	now_box.add_theme_stylebox_override("panel", nst)
	rows.add_child(now_box)

	var now_col := VBoxContainer.new()
	now_col.add_theme_constant_override("separation", 4)
	now_box.add_child(now_col)
	_now_title = PixelUI.emphasize(PixelUI.label(now_col, "♪ 未播放", 22, PixelUI.theme_accent_bright()), 2, 1)
	now_playing_label = _now_title
	_now_meta = PixelUI.label(now_col, "状态：待机", 15, PixelUI.theme_dim())

	# 切歌与刷新控制栏
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 8)
	rows.add_child(ctrl_row)
	var prev_btn := PixelUI.button("上一曲", 38)
	prev_btn.add_theme_font_size_override("font_size", 17)
	prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_btn.pressed.connect(_on_prev)
	ctrl_row.add_child(prev_btn)

	var next_btn := PixelUI.button("下一曲", 38)
	next_btn.add_theme_font_size_override("font_size", 17)
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.pressed.connect(_on_next)
	ctrl_row.add_child(next_btn)

	var pin_btn := PixelUI.button("锁定当前曲", 38)
	pin_btn.add_theme_font_size_override("font_size", 17)
	pin_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pin_btn.pressed.connect(_on_pin_current)
	ctrl_row.add_child(pin_btn)

	var refresh_btn := PixelUI.button("刷新曲库", 38)
	refresh_btn.add_theme_font_size_override("font_size", 17)
	refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_btn.pressed.connect(_on_refresh)
	ctrl_row.add_child(refresh_btn)

	# 播放模式选择行
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	rows.add_child(mode_row)
	var mlbl := PixelUI.label(mode_row, "播放模式", 17, PixelUI.theme_text())
	mlbl.custom_minimum_size.x = 84
	mlbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for md in MODE_DEFS:
		var mid := String(md["id"])
		var mbtn := PixelUI.button(String(md["label"]), 36)
		mbtn.add_theme_font_size_override("font_size", 16)
		mbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mbtn.pressed.connect(_on_select_mode.bind(mid))
		mode_row.add_child(mbtn)
		_mode_buttons[mid] = mbtn
	_mode_hint = PixelUI.label(rows, "", 14, PixelUI.theme_dim())

	# 曲库列表（滚动）
	var list_lbl := PixelUI.label(rows, "可用曲目（点击立即切歌；战斗时将自动平滑切换战斗曲池）", 15, PixelUI.theme_accent())
	list_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)

	_track_list = VBoxContainer.new()
	_track_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_track_list)

	# 自定义音乐目录提示 + 返回按钮
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	rows.add_child(footer)
	_dir_hint = PixelUI.label(footer, "", 13, PixelUI.theme_dim())
	_dir_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dir_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_close_button = PixelUI.button("返回", 40)
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.custom_minimum_size.x = 140
	_close_button.pressed.connect(close_menu)
	footer.add_child(_close_button)


func open() -> void:
	_ensure_sfx_connected()
	if _panel != null:
		_panel.apply_active_theme()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("bgm_user_dir"):
		var udir := String(sfx.bgm_user_dir())
		_dir_hint.text = "自定义音乐目录（支持 .ogg / .mp3 / .wav）：%s" % udir
	_rebuild_track_list()
	_refresh_state()
	visible = true
	if _close_button != null:
		_close_button.grab_focus()


func close_menu() -> void:
	visible = false
	closed.emit()


func _ensure_sfx_connected() -> void:
	if _sfx_connected:
		return
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_signal("bgm_track_changed"):
		sfx.bgm_track_changed.connect(_on_track_changed)
		_sfx_connected = true


func _on_track_changed(_info: Dictionary) -> void:
	if visible:
		_refresh_state()


func _on_prev() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("bgm_prev_track"):
		var info: Dictionary = sfx.bgm_prev_track(0.4)
		_persist_pinned_if_single(info)
	_refresh_state()


func _on_next() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("bgm_next_track"):
		var info: Dictionary = sfx.bgm_next_track(0.4)
		_persist_pinned_if_single(info)
	_refresh_state()


func _on_pin_current() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	var p := get_node_or_null("/root/Progress")
	if sfx == null or not sfx.has_method("bgm_current_track"):
		return
	var cur: Dictionary = sfx.bgm_current_track()
	var tid := String(cur.get("id", ""))
	if tid.is_empty():
		return
	sfx.set_bgm_pinned_track(tid)
	sfx.set_bgm_play_mode("single")
	if p != null:
		if p.has_method("set_bgm_pinned_track"):
			p.set_bgm_pinned_track(tid)
		if p.has_method("set_bgm_play_mode"):
			p.set_bgm_play_mode("single")
	_refresh_state()


func _on_refresh() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("bgm_refresh_catalog"):
		sfx.bgm_refresh_catalog()
	_rebuild_track_list()
	_refresh_state()


func select_mode(mode: String) -> void:
	_on_select_mode(mode)


func _on_select_mode(mode: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	var p := get_node_or_null("/root/Progress")
	if sfx != null and sfx.has_method("set_bgm_play_mode"):
		sfx.set_bgm_play_mode(mode)
	if p != null and p.has_method("set_bgm_play_mode"):
		p.set_bgm_play_mode(mode)
	if mode == "single" and sfx != null and sfx.has_method("bgm_pinned_track"):
		var pin := String(sfx.bgm_pinned_track())
		if not pin.is_empty() and p != null and p.has_method("set_bgm_pinned_track"):
			p.set_bgm_pinned_track(pin)
	_refresh_state()


func _on_play_track(track_id: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("bgm_play_track"):
		sfx.bgm_play_track(track_id, 0.4)
		if String(sfx.bgm_play_mode()) == "single":
			sfx.set_bgm_pinned_track(track_id)
			var p := get_node_or_null("/root/Progress")
			if p != null and p.has_method("set_bgm_pinned_track"):
				p.set_bgm_pinned_track(track_id)
	_refresh_state()


func _persist_pinned_if_single(info: Dictionary) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	var p := get_node_or_null("/root/Progress")
	if sfx != null and String(sfx.bgm_play_mode()) == "single":
		var tid := String(info.get("id", ""))
		if not tid.is_empty() and p != null and p.has_method("set_bgm_pinned_track"):
			p.set_bgm_pinned_track(tid)


func _rebuild_track_list() -> void:
	if _track_list == null:
		return
	for ch in _track_list.get_children():
		ch.queue_free()
	_track_buttons.clear()
	var sfx := get_node_or_null("/root/Sfx")
	if sfx == null or not sfx.has_method("bgm_tracks"):
		return
	var tracks: Array = sfx.bgm_tracks("")
	for t in tracks:
		var td := t as Dictionary
		var tid := String(td.get("id", ""))
		var title := String(td.get("title", tid))
		var src_tag := "自定义" if bool(td.get("custom", false)) else "内置"
		var pools_txt := _format_pools(td.get("pools", []))
		var btn := PixelUI.button("  %s   [%s · %s]" % [title, src_tag, pools_txt], 36)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_play_track.bind(tid))
		_track_list.add_child(btn)
		_track_buttons[tid] = btn


func _refresh_state() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	var acc := PixelUI.theme_accent()
	var mode := String(sfx.bgm_play_mode()) if (sfx != null and sfx.has_method("bgm_play_mode")) else "shuffle"
	var cur: Dictionary = sfx.bgm_current_track() if (sfx != null and sfx.has_method("bgm_current_track")) else {}
	var cur_id := String(cur.get("id", ""))
	var cur_title := String(cur.get("title", "未播放"))
	var pinned := String(sfx.bgm_pinned_track()) if (sfx != null and sfx.has_method("bgm_pinned_track")) else ""
	if _now_title != null:
		_now_title.text = "♪ 正在播放：%s" % cur_title
	if _now_meta != null:
		var src := "自定义曲库" if bool(cur.get("custom", false)) else "内置曲库"
		var mode_cn := "随机轮播" if mode == "shuffle" else ("顺序播放" if mode == "sequential" else "固定单曲")
		var pin_note := " · 已锁定单曲" if (mode == "single" and not pinned.is_empty()) else ""
		_now_meta.text = "来源：%s  ·  模式：%s%s" % [src, mode_cn, pin_note]
	for md in MODE_DEFS:
		var mid := String(md["id"])
		var btn: Button = _mode_buttons.get(mid)
		if btn != null:
			var active := mid == mode
			btn.text = ("▶ " if active else "   ") + String(md["label"])
			btn.add_theme_color_override("font_color", PixelUI.theme_accent_bright() if active else PixelUI.theme_text())
			if active and _mode_hint != null:
				_mode_hint.text = String(md["tip"])
	for tid in _track_buttons:
		var tb: Button = _track_buttons[tid]
		var is_cur := String(tid) == cur_id
		tb.add_theme_color_override("font_color", acc if is_cur else PixelUI.theme_text())


static func _format_pools(pools: Array) -> String:
	var names: Array[String] = []
	for p in pools:
		match String(p):
			"menu": names.append("主菜单")
			"explore": names.append("探索")
			"combat": names.append("战斗")
	return "/".join(names) if not names.is_empty() else "通用"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
