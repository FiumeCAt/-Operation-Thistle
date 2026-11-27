extends Control
class_name StartMenu2D
## 2D 开始菜单（重构版）：
## 1) 3 张暗调工业像素风 16:9 占位背景缓慢交叉淡入轮播 + 柔和暗角与左侧暗渐变蒙版；
## 2) 左侧紧凑半透明导航栏（主行动 / 战前整备 / 系统与档案 / 主题配色切换），中央大面积留白透出场景氛围；
## 3) 右侧精致紧凑的「DOLL-01 作战档案」「当前主/副武器携行预览卡」与精简按键提示条；
## 4) 支持 4 套预设主题（默认琥珀 / 终端绿 / 科幻亮青 / 简约黑白）与自定义主色，实时换肤并持久化。

const MAIN_SCENE := "res://scenes/core/Main2D.tscn"
const SAVE_SLOTS_MENU := preload("res://scripts/ui/SaveSlotsMenu2D.gd")
const CHARACTER_MENU := preload("res://scripts/ui/CharacterMenu2D.gd")
const COMBAT_FX_WARMUP := preload("res://scripts/fx/CombatFxWarmup.gd")
const HIT_FX := preload("res://scripts/fx/HitFX2D.gd")

const BG_SLIDES: Array[Dictionary] = [
	{"path": "res://assets/art/ui/menu_bg/bg_01_hangar.png", "label": "01 K-17 整备库"},
	{"path": "res://assets/art/ui/menu_bg/bg_02_airlock.png", "label": "02 隔离闸门"},
	{"path": "res://assets/art/ui/menu_bg/bg_03_outpost.png", "label": "03 雨夜哨站"},
]
const BG_HOLD_SECONDS := 8.5
const BG_FADE_SECONDS := 1.8

## 主菜单背景轮播与暗角蒙版可调配置资源（resources/config/start_menu_default.tres）；
## 未挂载时平滑回退上方 const 默认值；玩家主题配色与音量仍由 Progress 动态驱动。
@export var config: Resource

var start_button: Button
var waves_button: Button
var character_button: Button
var talents_button: Button
var armory_button: Button
var stash_button: Button
var saves_button: Button
var settings_button: Button
var codex_button: Button
var quit_button: Button
var character_menu: CharacterMenu2D
var talents: TalentTree2D
var armory: ArmoryMenu2D
var stash: StashMenu2D
var save_slots
var deployment: DeploymentMenu2D
var settings_menu: SettingsMenu2D
var codex: CodexMenu2D

## 主题切换控件（供单测与实机切换）
var theme_buttons: Dictionary = {}
var theme_picker: ColorPickerButton

var _closing := false
var _pending_mode := "raid"
var _stats: Dictionary = {}
var _stash_labels: Dictionary = {}
var _loadout_slots: Dictionary = {}
var _main_scene: PackedScene
var _main_preload_started := false
var _loading_overlay: Control

## 背景轮播层与主题联动节点列表
var _bg_textures: Array[Texture2D] = []
var _bg_cur: TextureRect
var _bg_next: TextureRect
var _bg_index := 0
var _bg_timer := 0.0
var _bg_fading := false
var _bg_fade_t := 0.0
var _bg_scene_label: Label
var _bg_dot_buttons: Array[Button] = []
var _backdrop_overlay: Control
var _themed_panels: Array[PixelUI.PixelPanel] = []
var _themed_accent_labels: Array[Label] = []
var _themed_bright_labels: Array[Label] = []
var _themed_dividers: Array[HSeparator] = []
var _themed_buttons: Array[Button] = []
var _nav_bg_panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("ui_theme"):
		PixelUI.set_theme_palette(p.ui_theme(), p.ui_theme_color())
		if p.has_signal("ui_theme_changed") and not p.ui_theme_changed.is_connected(_on_ui_theme_changed):
			p.ui_theme_changed.connect(_on_ui_theme_changed)
		if p.has_signal("progress_mutated") and not p.progress_mutated.is_connected(_refresh_dossier):
			p.progress_mutated.connect(_refresh_dossier)
	PixelUI.apply_theme(self)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		if sfx.has_method("set_bgm_state"):
			sfx.set_bgm_state("menu", 0.9)
		else:
			sfx.start_ambient()
	_load_bg_textures()
	_build()
	_apply_menu_theme()
	_refresh_dossier()
	if DisplayServer.get_name() != "headless":
		var warmup := COMBAT_FX_WARMUP.new()
		warmup.name = "CombatFxWarmup"
		add_child(warmup)
		var variants := HIT_FX.impact_variants()
		variants.push_front({"id": "projectiles/muzzle-pistol", "opts": {}})
		warmup.setup(variants)
		_start_main_preload()


func _cfg_float(prop: StringName, fallback: float) -> float:
	if config != null and prop in config:
		return float(config.get(prop))
	return fallback


func _cfg_color(prop: StringName, fallback: Color) -> Color:
	if config != null and prop in config:
		var val = config.get(prop)
		if val is Color:
			return val
	return fallback


func _bg_slides() -> Array[Dictionary]:
	if config != null and &"slide_paths" in config:
		var paths = config.get(&"slide_paths")
		var labels = config.get(&"slide_labels") if (&"slide_labels" in config) else PackedStringArray()
		if paths is PackedStringArray and paths.size() > 0:
			var out: Array[Dictionary] = []
			for i in paths.size():
				var lbl := String(labels[i]) if (labels is PackedStringArray and i < labels.size()) \
					else ("0%d SCENE" % (i + 1))
				out.append({"path": String(paths[i]), "label": lbl})
			return out
	return BG_SLIDES


func _bg_hold_seconds() -> float:
	return maxf(_cfg_float(&"bg_hold_seconds", BG_HOLD_SECONDS), 0.2)


func _bg_fade_seconds() -> float:
	return maxf(_cfg_float(&"bg_fade_seconds", BG_FADE_SECONDS), 0.05)


func _load_bg_textures() -> void:
	_bg_textures.clear()
	for slide in _bg_slides():
		var path := String(slide["path"])
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_bg_textures.append(tex)


func _start_main_preload() -> void:
	if _main_preload_started or _main_scene != null:
		return
	_main_preload_started = ResourceLoader.load_threaded_request(
		MAIN_SCENE, "PackedScene") == OK


func _process(delta: float) -> void:
	_step_bg_carousel(delta)
	if not _main_preload_started or _main_scene != null:
		return
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_main_scene = ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
		_main_preload_started = false
	elif status == ResourceLoader.THREAD_LOAD_FAILED \
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_main_preload_started = false


func _step_bg_carousel(delta: float) -> void:
	if _bg_textures.size() <= 1 or _bg_cur == null or _bg_next == null:
		return
	if _bg_fading:
		_bg_fade_t = minf(_bg_fade_t + delta / _bg_fade_seconds(), 1.0)
		var smooth := _bg_fade_t * _bg_fade_t * (3.0 - 2.0 * _bg_fade_t)
		_bg_next.modulate.a = smooth
		if _bg_fade_t >= 1.0:
			_bg_index = (_bg_index + 1) % _bg_textures.size()
			_bg_cur.texture = _bg_textures[_bg_index]
			_bg_next.visible = false
			_bg_next.modulate.a = 0.0
			_bg_fading = false
			_bg_timer = 0.0
			_refresh_bg_indicator()
	else:
		_bg_timer += delta
		if _bg_timer >= _bg_hold_seconds():
			_begin_bg_transition((_bg_index + 1) % _bg_textures.size())


func _begin_bg_transition(target_idx: int) -> void:
	if _bg_textures.is_empty():
		return
	target_idx = posmod(target_idx, _bg_textures.size())
	if target_idx == _bg_index:
		return
	_bg_next.texture = _bg_textures[target_idx]
	_bg_next.modulate.a = 0.0
	_bg_next.visible = true
	_bg_fading = true
	_bg_fade_t = 0.0


## 允许玩家点击底部小点或测试立即切换背景图。
func select_bg_slide(index: int) -> void:
	if _bg_textures.is_empty():
		return
	_bg_index = posmod(index, _bg_textures.size())
	_bg_fading = false
	_bg_fade_t = 0.0
	_bg_timer = 0.0
	if _bg_cur != null:
		_bg_cur.texture = _bg_textures[_bg_index]
	if _bg_next != null:
		_bg_next.visible = false
		_bg_next.modulate.a = 0.0
	_refresh_bg_indicator()


func _refresh_bg_indicator() -> void:
	var slides := _bg_slides()
	if _bg_scene_label != null and _bg_index < slides.size():
		_bg_scene_label.text = String(slides[_bg_index]["label"])
	var acc := PixelUI.theme_accent()
	for i in _bg_dot_buttons.size():
		var btn := _bg_dot_buttons[i]
		var active := (i == _bg_index)
		btn.text = "■" if active else "□"
		btn.add_theme_color_override("font_color", acc if active else PixelUI.theme_dim())
		btn.add_theme_color_override("font_hover_color", PixelUI.theme_accent_bright())


func _build() -> void:
	_build_background_layer()
	_build_nav_sidebar()
	_build_right_cards()
	_build_footer()

	character_menu = CHARACTER_MENU.new()
	character_menu.name = "CharacterMenu2D"
	character_menu.closed.connect(_on_sub_closed)
	character_menu.character_changed.connect(_on_character_changed)
	add_child(character_menu)

	talents = TalentTree2D.new()
	talents.name = "TalentTree2D"
	talents.closed.connect(_on_sub_closed)
	add_child(talents)

	armory = ArmoryMenu2D.new()
	armory.name = "ArmoryMenu2D"
	armory.closed.connect(_on_sub_closed)
	add_child(armory)

	stash = StashMenu2D.new()
	stash.name = "StashMenu2D"
	stash.closed.connect(_on_sub_closed)
	add_child(stash)

	save_slots = SAVE_SLOTS_MENU.new()
	save_slots.name = "SaveSlotsMenu2D"
	save_slots.closed.connect(_on_sub_closed)
	save_slots.slot_loaded.connect(_on_slot_loaded)
	add_child(save_slots)

	deployment = DeploymentMenu2D.new()
	deployment.name = "DeploymentMenu2D"
	deployment.deploy_confirmed.connect(_deploy)
	deployment.closed.connect(_on_sub_closed)
	add_child(deployment)

	settings_menu = SettingsMenu2D.new()
	settings_menu.name = "SettingsMenu2D"
	settings_menu.closed.connect(_on_sub_closed)
	add_child(settings_menu)

	codex = CodexMenu2D.new()
	codex.name = "CodexMenu2D"
	codex.closed.connect(_on_sub_closed)
	add_child(codex)
	start_button.grab_focus()


func _build_background_layer() -> void:
	var base := ColorRect.new()
	base.color = _cfg_color(&"base_bg_color", Color(0.008, 0.011, 0.016, 1.0))
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_bg_cur = TextureRect.new()
	_bg_cur.name = "BgSlideCurrent"
	_bg_cur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_cur.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_cur.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_cur.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg_cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _bg_textures.is_empty():
		_bg_cur.texture = _bg_textures[0]
	add_child(_bg_cur)

	_bg_next = TextureRect.new()
	_bg_next.name = "BgSlideNext"
	_bg_next.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_next.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_next.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_next.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_next.visible = false
	_bg_next.modulate.a = 0.0
	add_child(_bg_next)

	_backdrop_overlay = _BackdropOverlay.new()
	_backdrop_overlay.name = "BackdropOverlay"
	_backdrop_overlay.menu_config = config
	_backdrop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop_overlay)


## 左侧紧凑半透明导航栏：留出中央约 42% 画面呼吸感，完整展示 K-17 场景氛围。
func _build_nav_sidebar() -> void:
	_nav_bg_panel = PanelContainer.new()
	_nav_bg_panel.name = "NavSidebar"
	_nav_bg_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_nav_bg_panel.offset_left = 44
	_nav_bg_panel.offset_right = 492
	_nav_bg_panel.offset_top = 28
	_nav_bg_panel.offset_bottom = -74
	add_child(_nav_bg_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	_nav_bg_panel.add_child(rows)

	var tag := PixelUI.emphasize(
		PixelUI.label(rows, "OPERATION THISTLE // K-17", 18, PixelUI.theme_accent()), 2, 1)
	_themed_accent_labels.append(tag)
	var title := PixelUI.emphasize(PixelUI.label(rows, "蓟花行动", 60, PixelUI.theme_text()), 5, 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var english := PixelUI.emphasize(
		PixelUI.label(rows, "D O L L   P R O T O C O L", 24, PixelUI.theme_accent_bright()), 3, 2)
	english.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_themed_bright_labels.append(english)

	var div1 := HSeparator.new()
	rows.add_child(div1)
	_themed_dividers.append(div1)

	var subtitle := PixelUI.label(rows, "2D 俯视像素战术撤离 // 下潜 · 搜刮 · 撤离", 16, PixelUI.theme_dim())
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	# --- 行动部署 ---
	var deploy_hdr := PixelUI.label(rows, "行动部署 // DEPLOY", 16, PixelUI.theme_accent())
	_themed_accent_labels.append(deploy_hdr)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	rows.add_child(actions)

	start_button = PixelUI.primary_button("开始行动", 56)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(_start)
	actions.add_child(start_button)

	waves_button = PixelUI.button("浪潮生存", 56)
	waves_button.custom_minimum_size.x = 148
	waves_button.pressed.connect(_start_waves)
	actions.add_child(waves_button)
	_themed_buttons.append(waves_button)

	# --- 战前整备（2×2 紧凑布局：角色 / 武备库 / 天赋树 / 仓库）---
	var prep_hdr := PixelUI.label(rows, "战前整备 // PREP", 16, PixelUI.theme_accent())
	_themed_accent_labels.append(prep_hdr)

	var prep_row1 := HBoxContainer.new()
	prep_row1.add_theme_constant_override("separation", 8)
	rows.add_child(prep_row1)

	character_button = PixelUI.button("角色 // OPERATOR", 46)
	character_button.add_theme_font_size_override("font_size", 16)
	character_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_button.pressed.connect(_open_character)
	prep_row1.add_child(character_button)
	_themed_buttons.append(character_button)

	armory_button = PixelUI.button("武备库 // ARSENAL", 46)
	armory_button.add_theme_font_size_override("font_size", 16)
	armory_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armory_button.pressed.connect(_open_armory)
	prep_row1.add_child(armory_button)
	_themed_buttons.append(armory_button)

	var prep_row2 := HBoxContainer.new()
	prep_row2.add_theme_constant_override("separation", 8)
	rows.add_child(prep_row2)

	talents_button = PixelUI.button("天赋树 // TALENTS", 46)
	talents_button.add_theme_font_size_override("font_size", 16)
	talents_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talents_button.pressed.connect(_open_talents)
	prep_row2.add_child(talents_button)
	_themed_buttons.append(talents_button)

	stash_button = PixelUI.button("仓库 // STASH", 46)
	stash_button.add_theme_font_size_override("font_size", 16)
	stash_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stash_button.pressed.connect(_open_stash)
	prep_row2.add_child(stash_button)
	_themed_buttons.append(stash_button)

	# --- 次级功能行（存档 · 图鉴 · 设置 · 退出）---
	var sys_hdr := PixelUI.label(rows, "系统与档案 // SYSTEM", 16, PixelUI.theme_dim())
	sys_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var util_row1 := HBoxContainer.new()
	util_row1.add_theme_constant_override("separation", 8)
	rows.add_child(util_row1)

	saves_button = PixelUI.button("存档 // SLOTS", 40)
	saves_button.add_theme_font_size_override("font_size", 16)
	saves_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saves_button.pressed.connect(_open_saves)
	util_row1.add_child(saves_button)
	_themed_buttons.append(saves_button)

	codex_button = PixelUI.button("图鉴 // CODEX", 40)
	codex_button.add_theme_font_size_override("font_size", 16)
	codex_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	codex_button.pressed.connect(_open_codex)
	util_row1.add_child(codex_button)
	_themed_buttons.append(codex_button)

	var util_row2 := HBoxContainer.new()
	util_row2.add_theme_constant_override("separation", 8)
	rows.add_child(util_row2)

	settings_button = PixelUI.button("设置 // SETTINGS", 40)
	settings_button.add_theme_font_size_override("font_size", 16)
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.pressed.connect(_open_settings)
	util_row2.add_child(settings_button)
	_themed_buttons.append(settings_button)

	quit_button = PixelUI.button("退出游戏", 40)
	quit_button.add_theme_font_size_override("font_size", 16)
	quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit_button.pressed.connect(_quit_game)
	util_row2.add_child(quit_button)
	_themed_buttons.append(quit_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)

	var div2 := HSeparator.new()
	rows.add_child(div2)
	_themed_dividers.append(div2)

	# --- 主题配色切换条（4 套预设 + 自定义调色盘）---
	_build_theme_switcher(rows)


func _build_theme_switcher(parent: Node) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)

	var hdr := PixelUI.label(box, "界面主题 // THEME", 16, PixelUI.theme_dim())
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	for id in ["amber", "terminal", "cyan", "mono"]:
		var btn := PixelUI.button(PixelUI.theme_name(id), 32)
		btn.add_theme_font_size_override("font_size", 15)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_select_theme_preset.bind(id))
		row.add_child(btn)
		theme_buttons[id] = btn

	theme_picker = ColorPickerButton.new()
	theme_picker.name = "CustomThemePicker"
	theme_picker.custom_minimum_size = Vector2(46, 32)
	theme_picker.focus_mode = Control.FOCUS_NONE
	theme_picker.edit_alpha = false
	theme_picker.tooltip_text = "自定义主题配色"
	var p := get_node_or_null("/root/Progress")
	theme_picker.color = p.ui_theme_color() if (p != null and p.has_method("ui_theme_color")) else PixelUI.AMBER
	theme_picker.color_changed.connect(_on_custom_theme_color)
	row.add_child(theme_picker)


## 右侧紧凑浮窗组：1) 精炼作战档案；2) 当前主/副武器携行预览卡；3) 极简操作条。
func _build_right_cards() -> void:
	var stack := VBoxContainer.new()
	stack.name = "RightInfoStack"
	stack.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	stack.offset_left = -464
	stack.offset_right = -40
	stack.offset_top = 44
	stack.offset_bottom = -44
	stack.add_theme_constant_override("separation", 12)
	add_child(stack)

	# 1. 紧凑作战档案卡
	var dossier := PixelUI.panel(PixelUI.theme_bg(0.84))
	dossier.bg_alpha = 0.84
	_themed_panels.append(dossier)
	stack.add_child(dossier)

	var d_rows := VBoxContainer.new()
	d_rows.add_theme_constant_override("separation", 6)
	dossier.add_child(d_rows)

	var d_title := PixelUI.emphasize(
		PixelUI.label(d_rows, "DOLL-01 // 作战档案", 22, PixelUI.theme_accent()), 2, 1)
	_themed_accent_labels.append(d_title)
	_stats["dossier_title"] = d_title

	var d_div := HSeparator.new()
	d_rows.add_child(d_div)
	_themed_dividers.append(d_div)

	var op_line := HBoxContainer.new()
	op_line.add_theme_constant_override("separation", 8)
	d_rows.add_child(op_line)
	PixelUI.label(op_line, "出击人形", 15, PixelUI.theme_dim())
	var op_val := PixelUI.emphasize(PixelUI.label(op_line, "灰蓝猫耳", 16, PixelUI.theme_accent_bright()), 2, 1)
	op_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_themed_bright_labels.append(op_val)
	_stats["operator"] = op_val

	# 信用点 + 技能等级（第一行），XP + 天赋进度（第二行），宽度充裕永不溢出
	var top_metrics := HBoxContainer.new()
	top_metrics.add_theme_constant_override("separation", 12)
	d_rows.add_child(top_metrics)
	_credit_badge(top_metrics)
	_compact_stat(top_metrics, "等级", "skill")

	var sub_metrics := HBoxContainer.new()
	sub_metrics.add_theme_constant_override("separation", 12)
	d_rows.add_child(sub_metrics)
	_compact_stat_expand(sub_metrics, "经验 XP", "xp")
	_compact_stat(sub_metrics, "天赋", "talents")

	_resource_row(d_rows, "基础", ResourceDB.BASIC)
	_resource_row(d_rows, "进阶", ResourceDB.ADVANCED)

	var obj_line := PixelUI.label(d_rows, "目标：潜入 K-17 搜刮撤离 · 供电 +20%", 15, PixelUI.theme_dim())
	obj_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 2. 当前主/副武器携行预览卡
	var loadout_panel := PixelUI.panel(PixelUI.theme_bg(0.84))
	loadout_panel.bg_alpha = 0.84
	_themed_panels.append(loadout_panel)
	stack.add_child(loadout_panel)

	var l_rows := VBoxContainer.new()
	l_rows.add_theme_constant_override("separation", 8)
	loadout_panel.add_child(l_rows)

	var l_title := PixelUI.emphasize(
		PixelUI.label(l_rows, "当前携行 // LOADOUT", 20, PixelUI.theme_accent()), 2, 1)
	_themed_accent_labels.append(l_title)

	var l_div := HSeparator.new()
	l_rows.add_child(l_div)
	_themed_dividers.append(l_div)

	_build_loadout_slot(l_rows, "primary", "主")
	_build_loadout_slot(l_rows, "secondary", "副")

	var push_down := Control.new()
	push_down.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(push_down)

	# 3. 底部精简操作提示条
	var ctrl_panel := PixelUI.panel(PixelUI.theme_bg(0.80))
	ctrl_panel.bg_alpha = 0.80
	_themed_panels.append(ctrl_panel)
	stack.add_child(ctrl_panel)

	var c_rows := VBoxContainer.new()
	c_rows.add_theme_constant_override("separation", 4)
	ctrl_panel.add_child(c_rows)
	var c_hdr := PixelUI.label(c_rows, "快捷操作 // CONTROLS", 16, PixelUI.theme_accent())
	_themed_accent_labels.append(c_hdr)
	PixelUI.label(c_rows, "WASD 移动 · SPACE 翻滚 · 左键开火 · 右键瞄准 · R 换弹", 14, PixelUI.theme_text())
	PixelUI.label(c_rows, "1-2 切枪 · E 交互 · TAB 背包 · M 地图 · Alt+滚轮", 14, PixelUI.theme_dim())


func _credit_badge(parent: Node) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	PixelUI.icon(box, "res_credit", 20)
	var val := PixelUI.emphasize(PixelUI.label(box, "0", 22, PixelUI.GOLD), 2, 1)
	_stats["credits"] = val


func _compact_stat(parent: Node, title: String, key: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	PixelUI.label(box, title, 16, PixelUI.theme_dim())
	var val := PixelUI.emphasize(PixelUI.label(box, "-", 18, PixelUI.theme_text()), 2, 1)
	_stats[key] = val


func _compact_stat_expand(parent: Node, title: String, key: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	PixelUI.label(box, title, 16, PixelUI.theme_dim())
	var val := PixelUI.label(box, "-", 17, PixelUI.theme_text())
	_stats[key] = val


func _stat_row(parent: Node, title: String, key: String, font_size := 18) -> void:
	var line := HBoxContainer.new()
	parent.add_child(line)
	var name_label := PixelUI.label(line, title, font_size, PixelUI.theme_dim())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := PixelUI.label(line, "-", font_size, PixelUI.theme_text())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats[key] = value


func _resource_row(parent: Node, title: String, ids: Array[StringName]) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var name_label := PixelUI.label(line, title, 16, PixelUI.theme_dim())
	name_label.custom_minimum_size.x = 46
	for id in ids:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		line.add_child(cell)
		PixelUI.icon(cell, "res_" + String(id), 18)
		var count := PixelUI.label(cell, "0", 17, PixelUI.theme_text())
		_stash_labels[String(id)] = count


func _build_loadout_slot(parent: Node, slot_key: String, badge_text: String) -> void:
	var box := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.04, 0.055, 0.78)
	st.border_color = Color(PixelUI.theme_accent(), 0.35)
	st.set_border_width_all(1)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", st)
	parent.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var badge := PixelUI.emphasize(
		PixelUI.label(row, "[%s]" % badge_text, 18, PixelUI.theme_accent()), 2, 1)
	badge.custom_minimum_size.x = 34
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_themed_accent_labels.append(badge)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(68, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	var name_lbl := PixelUI.emphasize(PixelUI.label(info, "-", 18, PixelUI.theme_text()), 2, 1)
	var meta_lbl := PixelUI.label(info, "-", 14, PixelUI.theme_dim())
	_loadout_slots[slot_key] = {
		"box": box,
		"icon": icon,
		"name": name_lbl,
		"meta": meta_lbl,
	}


## 左下状态与背景轮播指示条
func _build_footer() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 54
	bar.offset_top = -62
	bar.offset_right = 680
	bar.offset_bottom = -24
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	var hint := PixelUI.label(bar, "ENTER 部署 · ESC 退出", 16, PixelUI.theme_dim())
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var sep := PixelUI.label(bar, "|", 16, Color(PixelUI.DIM, 0.5))
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var slides := _bg_slides()
	var first_label := String(slides[0]["label"]) if not slides.is_empty() else ""
	_bg_scene_label = PixelUI.label(bar, first_label, 16, PixelUI.theme_accent())
	_bg_scene_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_themed_accent_labels.append(_bg_scene_label)

	_bg_dot_buttons.clear()
	for i in slides.size():
		var dot := Button.new()
		dot.text = "■" if i == 0 else "□"
		dot.flat = true
		dot.focus_mode = Control.FOCUS_NONE
		dot.custom_minimum_size = Vector2(22, 22)
		dot.add_theme_font_size_override("font_size", 16)
		dot.pressed.connect(select_bg_slide.bind(i))
		bar.add_child(dot)
		_bg_dot_buttons.append(dot)


func _select_theme_preset(theme_id: String) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_ui_theme"):
		p.set_ui_theme(theme_id)
	else:
		PixelUI.set_theme_palette(theme_id)
		_apply_menu_theme()


func _on_custom_theme_color(col: Color) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("set_ui_theme_color"):
		p.set_ui_theme_color(col)
	else:
		PixelUI.set_theme_palette("custom", col)
		_apply_menu_theme()


func _on_ui_theme_changed(_theme_id: String, _accent: Color) -> void:
	_apply_menu_theme()


func _apply_menu_theme() -> void:
	var acc := PixelUI.theme_accent()
	var bright := PixelUI.theme_accent_bright()
	var bg := PixelUI.theme_bg(0.82)
	var dim := PixelUI.theme_dim()
	var active_id := PixelUI.theme_id()

	if _nav_bg_panel != null:
		var nav_st := StyleBoxFlat.new()
		nav_st.bg_color = bg
		nav_st.border_color = Color(acc, 0.72)
		nav_st.border_width_left = 3
		nav_st.border_width_top = 1
		nav_st.border_width_right = 1
		nav_st.border_width_bottom = 1
		nav_st.content_margin_left = 20
		nav_st.content_margin_right = 20
		nav_st.content_margin_top = 14
		nav_st.content_margin_bottom = 12
		_nav_bg_panel.add_theme_stylebox_override("panel", nav_st)

	for p in _themed_panels:
		if is_instance_valid(p):
			p.apply_active_theme()

	for lbl in _themed_accent_labels:
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", acc)

	for lbl in _themed_bright_labels:
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", bright)

	for div in _themed_dividers:
		if is_instance_valid(div):
			div.add_theme_color_override("color", Color(acc, 0.65))

	if start_button != null:
		PixelUI.style_primary_button(start_button)

	for btn in _themed_buttons:
		if is_instance_valid(btn):
			var fs := btn.get_theme_font_size("font_size")
			PixelUI.style_button(btn)
			if fs > 0:
				btn.add_theme_font_size_override("font_size", fs)

	for id in theme_buttons:
		var sid := String(id)
		var btn: Button = theme_buttons[id]
		var preset_acc: Color = PixelUI.THEME_PRESETS[sid]["accent"]
		var is_active: bool = (active_id == sid)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(preset_acc, 0.28) if is_active else Color(0.04, 0.05, 0.07, 0.85)
		st.border_color = preset_acc if is_active else Color(preset_acc, 0.45)
		st.set_border_width_all(2 if is_active else 1)
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		var hov := st.duplicate() as StyleBoxFlat
		hov.bg_color = Color(preset_acc, 0.36)
		hov.border_color = preset_acc.lightened(0.2)
		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover", hov)
		btn.add_theme_stylebox_override("pressed", hov)
		btn.add_theme_color_override("font_color", preset_acc.lightened(0.25) if is_active else dim)
		btn.add_theme_color_override("font_hover_color", preset_acc.lightened(0.35))

	for slot_key in _loadout_slots:
		var box: PanelContainer = _loadout_slots[slot_key]["box"]
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.03, 0.04, 0.055, 0.78)
		st.border_color = Color(acc, 0.38)
		st.set_border_width_all(1)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 6
		st.content_margin_bottom = 6
		box.add_theme_stylebox_override("panel", st)

	if _backdrop_overlay != null:
		_backdrop_overlay.queue_redraw()
	_refresh_bg_indicator()


func _refresh_dossier() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	_stats["credits"].text = str(p.credits())
	for id in ResourceDB.BASIC:
		_set_stash(id, p.material_count(id))
	for id in ResourceDB.ADVANCED:
		_set_stash(id, p.advanced_count(id))
	_stats["xp"].text = str(int(p.data.get("xp", 0)))
	_stats["skill"].text = "Lv.%d" % int(p.data.get("skill_level", 1))
	var total := 0
	var max_total := 0
	for def in TalentTree2D.NODES:
		var id: StringName = def["id"]
		total += int(p.talent_2d_level(id))
		max_total += int(p.talent_2d_max(id))
	_stats["talents"].text = "%d/%d" % [total, max_total]
	var cur_skin := String(p.character_skin()) if p.has_method("character_skin") else "doll_v2"
	if _stats.has("dossier_title"):
		(_stats["dossier_title"] as Label).text = "%s // 作战档案" % CHARACTER_MENU.operator_code(cur_skin)
	if _stats.has("operator"):
		(_stats["operator"] as Label).text = CHARACTER_MENU.operator_short_label(cur_skin)
	_refresh_loadout_preview(p)


func _refresh_loadout_preview(p: Node) -> void:
	var loadout: Array = p.loadout_2d()
	var primary_id := StringName(loadout[0]) if loadout.size() > 0 else &"g17"
	var secondary_id := StringName(loadout[1]) if loadout.size() > 1 else &"m870"
	_fill_loadout_slot("primary", primary_id, p)
	_fill_loadout_slot("secondary", secondary_id, p)


func _fill_loadout_slot(slot_key: String, weapon_id: StringName, p: Node) -> void:
	if not _loadout_slots.has(slot_key):
		return
	var entry: Dictionary = _loadout_slots[slot_key]
	var data := WeaponDB.get_weapon(weapon_id)
	var icon_path := "res://assets/art/weapons/%s/icon.png" % weapon_id
	(entry["icon"] as TextureRect).texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
	var short_name := data.display_name.split(" // ")[0]
	(entry["name"] as Label).text = short_name
	var mods: Dictionary = p.weapon_mods_2d(weapon_id)
	var mod_count := 0
	for slot_name in mods:
		var opt := String(mods[slot_name])
		if opt != "" and opt != "std" and opt != "iron":
			mod_count += 1
	var mod_tag := "%d 改件" % mod_count if mod_count > 0 else "原厂配置"
	(entry["meta"] as Label).text = "%s · %d发 · %s" % [data.caliber_label, data.mag_capacity, mod_tag]


func _set_stash(id: StringName, value: int) -> void:
	var label: Label = _stash_labels.get(String(id))
	if label == null:
		return
	label.text = str(value)
	label.add_theme_color_override("font_color", PixelUI.theme_text() if value > 0 else PixelUI.theme_dim())


func _on_sub_closed() -> void:
	start_button.grab_focus()
	_refresh_dossier()


func _on_character_changed(_skin_id: String) -> void:
	_refresh_dossier()


func _open_character() -> void:
	if _closing or character_menu == null:
		return
	character_menu.open()


func _open_talents() -> void:
	if _closing or talents == null:
		return
	talents.open()


func _open_armory() -> void:
	if _closing or armory == null:
		return
	armory.open()


func _open_settings() -> void:
	if _closing or settings_menu == null:
		return
	settings_menu.open()


func _open_stash() -> void:
	if _closing or stash == null:
		return
	stash.open()


func _open_saves() -> void:
	if _closing or save_slots == null:
		return
	save_slots.open()


func _open_codex() -> void:
	if _closing or codex == null:
		return
	codex.open()


func _on_slot_loaded(_slot: int) -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null and p.has_method("ui_theme"):
		PixelUI.set_theme_palette(p.ui_theme(), p.ui_theme_color())
		_apply_menu_theme()
	_refresh_dossier()


func _quit_game() -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.autosave_on_exit()
	get_tree().quit()


func _start() -> void:
	if _closing:
		return
	_pending_mode = "raid"
	if deployment != null:
		deployment.set_mode("raid")
		deployment.open()


func _start_waves() -> void:
	if _closing:
		return
	_pending_mode = "waves"
	if deployment != null:
		deployment.set_mode("waves")
		deployment.open()


func _deploy(spawn_id: StringName, extract_id: StringName) -> void:
	if _closing:
		return
	_closing = true
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.set_deployment(spawn_id, extract_id)
		p.set_run_mode(_pending_mode)
		var map_id := "facility"
		if _pending_mode == "waves" and deployment != null:
			map_id = deployment.selected_map_id
		p.set_map_id(map_id)
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.play_2d("ui", -4.0, 0.82)
	if DisplayServer.get_name() != "headless":
		_show_loading_overlay()
		await get_tree().process_frame
	var packed: PackedScene = await _wait_main_scene()
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)


func _show_loading_overlay() -> void:
	if _loading_overlay != null:
		return
	_loading_overlay = ColorRect.new()
	_loading_overlay.color = Color(0.015, 0.018, 0.021, 0.97)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_loading_overlay)
	var title := PixelUI.label(_loading_overlay, "部署中 // DEPLOYING", 34, PixelUI.theme_accent())
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -42
	title.offset_bottom = 6
	var sub := PixelUI.label(_loading_overlay, "正在装载设施与敌情数据…", 20, PixelUI.theme_dim())
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.offset_left = -300
	sub.offset_right = 300
	sub.offset_top = 16
	sub.offset_bottom = 48


func _wait_main_scene() -> PackedScene:
	if _main_scene != null:
		return _main_scene
	if not _main_preload_started:
		return null
	while _main_preload_started:
		var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_main_scene = ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
			_main_preload_started = false
			return _main_scene
		if status == ResourceLoader.THREAD_LOAD_FAILED \
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_main_preload_started = false
			return null
		await get_tree().process_frame
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _closing or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if character_menu != null and character_menu.visible:
		if event.keycode == KEY_ESCAPE:
			character_menu.close_menu()
			get_viewport().set_input_as_handled()
		return
	if codex != null and codex.visible:
		if event.keycode == KEY_ESCAPE:
			codex.close_menu()
			get_viewport().set_input_as_handled()
		return
	if stash != null and stash.visible:
		if event.keycode == KEY_ESCAPE:
			stash.close_menu()
			get_viewport().set_input_as_handled()
		return
	if save_slots != null and save_slots.visible:
		if event.keycode == KEY_ESCAPE:
			save_slots.close_menu()
			get_viewport().set_input_as_handled()
		return
	if settings_menu != null and settings_menu.visible:
		if event.keycode == KEY_ESCAPE:
			settings_menu.close_menu()
			get_viewport().set_input_as_handled()
		return
	if deployment != null and deployment.visible:
		if event.keycode == KEY_ESCAPE:
			deployment.close_menu()
			get_viewport().set_input_as_handled()
		return
	if armory != null and armory.visible:
		if event.keycode == KEY_ESCAPE:
			armory.close_menu()
			get_viewport().set_input_as_handled()
		return
	if talents != null and talents.visible:
		if event.keycode == KEY_ESCAPE:
			talents.close_tree()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_start()
		KEY_ESCAPE:
			_quit_game()


## 氛围暗角与左侧渐变蒙版 + 极细主题色战术四角与微弱扫描线：
## 保证前景 UI 高可读的同时，把中央大面积画面完全留给背景场景图。
class _BackdropOverlay extends Control:
	var menu_config: Resource
	var _sweep := 0.0

	func _f(prop: StringName, fallback: float) -> float:
		if menu_config != null and prop in menu_config:
			return float(menu_config.get(prop))
		return fallback

	func _c(prop: StringName, fallback: Color) -> Color:
		if menu_config != null and prop in menu_config:
			var val = menu_config.get(prop)
			if val is Color:
				return val
		return fallback

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_sweep = fmod(_sweep + delta * _f(&"sweep_speed", 0.045), 1.0)
		queue_redraw()

	func _draw() -> void:
		var s := size
		if s.x < 16.0 or s.y < 16.0:
			return
		var acc := PixelUI.theme_accent()
		var tint := _c(&"mask_tint", Color(0.008, 0.011, 0.016, 1.0))
		# 左侧渐变暗蒙版（确保左导航高可读，中央柔和淡出至通透）
		const STRIPS := 28
		var left_w := s.x * clampf(_f(&"left_mask_width_ratio", 0.42), 0.0, 0.8)
		var left_a := clampf(_f(&"left_mask_alpha", 0.72), 0.0, 1.0)
		if left_w > 1.0 and left_a > 0.001:
			for i in STRIPS:
				var t0 := float(i) / float(STRIPS)
				var t1 := float(i + 1) / float(STRIPS)
				var a := pow(1.0 - t0, 1.65) * left_a
				draw_rect(Rect2(Vector2(left_w * t0, 0.0), Vector2(left_w * (t1 - t0) + 1.0, s.y)),
					Color(tint.r, tint.g, tint.b, a), true)
		# 右侧柔和暗蒙版（托起右侧档案与携行卡）
		var right_w := s.x * clampf(_f(&"right_mask_width_ratio", 0.34), 0.0, 0.8)
		var right_a := clampf(_f(&"right_mask_alpha", 0.56), 0.0, 1.0)
		if right_w > 1.0 and right_a > 0.001:
			for i in 18:
				var t0 := float(i) / 18.0
				var t1 := float(i + 1) / 18.0
				var a := pow(t1, 1.8) * right_a
				draw_rect(Rect2(Vector2(s.x - right_w + right_w * t0, 0.0), Vector2(right_w * (t1 - t0) + 1.0, s.y)),
					Color(tint.r, tint.g, tint.b, a), true)
		# 上下微弱电影暗角（托起顶部空间与底部轮播条）
		var top_h := s.y * clampf(_f(&"top_vignette_ratio", 0.14), 0.0, 0.45)
		var bot_h := s.y * clampf(_f(&"bottom_vignette_ratio", 0.16), 0.0, 0.45)
		var top_a := clampf(_f(&"top_vignette_alpha", 0.42), 0.0, 1.0)
		var bot_a := clampf(_f(&"bottom_vignette_alpha", 0.54), 0.0, 1.0)
		for i in 12:
			var t := float(i) / 12.0
			if top_h > 1.0 and top_a > 0.001:
				var h_t := top_h / 12.0
				draw_rect(Rect2(Vector2(0.0, i * h_t), Vector2(s.x, h_t + 1.0)),
					Color(tint.r * 0.75, tint.g * 0.82, tint.b * 0.82, pow(1.0 - t, 1.6) * top_a), true)
			if bot_h > 1.0 and bot_a > 0.001:
				var h_b := bot_h / 12.0
				draw_rect(Rect2(Vector2(0.0, s.y - bot_h + i * h_b), Vector2(s.x, h_b + 1.0)),
					Color(tint.r * 0.75, tint.g * 0.82, tint.b * 0.82, pow(t, 1.6) * bot_a), true)
		# 极细扫描线与主题色光扫
		var scan_a := clampf(_f(&"scanline_alpha", 0.012), 0.0, 0.25)
		var scan_step := maxf(_f(&"scanline_step_px", 5.0), 2.0)
		if scan_a > 0.0005:
			var scan := Color(1, 1, 1, scan_a)
			var sy := 0.0
			while sy < s.y:
				draw_line(Vector2(0, sy), Vector2(s.x, sy), scan, 1.0)
				sy += scan_step
		var sweep_a := clampf(_f(&"sweep_alpha", 0.05), 0.0, 0.4)
		if sweep_a > 0.0005:
			var sweep_y := s.y * _sweep
			draw_line(Vector2(0, sweep_y), Vector2(s.x, sweep_y), Color(acc, sweep_a), 2.0)
		# 四角战术框线
		var bracket_a := clampf(_f(&"corner_bracket_alpha", 0.42), 0.0, 1.0)
		if bracket_a > 0.001:
			var c := Color(acc, bracket_a)
			var m := _f(&"corner_margin", 18.0)
			var l := _f(&"corner_length", 56.0)
			draw_line(Vector2(m, m), Vector2(m + l, m), c, 2.0)
			draw_line(Vector2(m, m), Vector2(m, m + l), c, 2.0)
			draw_line(Vector2(s.x - m, m), Vector2(s.x - m - l, m), c, 2.0)
			draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + l), c, 2.0)
			draw_line(Vector2(m, s.y - m), Vector2(m + l, s.y - m), c, 2.0)
			draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - l), c, 2.0)
			draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - l, s.y - m), c, 2.0)
			draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - l), c, 2.0)
