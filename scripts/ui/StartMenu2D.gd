extends Control
class_name StartMenu2D
## 2D 开始菜单：去掉背景图，改用代码绘制的战术终端底纹 + 右列作战档案。
## 左列主菜单，右列展示资源/技能等级/天赋进度与本局目标。

const MAIN_SCENE := "res://scenes/core/Main2D.tscn"
const SAVE_SLOTS_MENU := preload("res://scripts/ui/SaveSlotsMenu2D.gd")
const COMBAT_FX_WARMUP := preload("res://scripts/fx/CombatFxWarmup.gd")
const HIT_FX := preload("res://scripts/fx/HitFX2D.gd")

var start_button: Button
var waves_button: Button
var talents_button: Button
var armory_button: Button
var stash_button: Button
var saves_button: Button
var settings_button: Button
var codex_button: Button
var quit_button: Button
var talents: TalentTree2D
var armory: ArmoryMenu2D
var stash: StashMenu2D
var save_slots
var deployment: DeploymentMenu2D
var settings_menu: SettingsMenu2D
var codex: CodexMenu2D
var _closing := false
## 当前选择的行动模式：raid 正常行动 / waves 浪潮生存。
var _pending_mode := "raid"
var _stats: Dictionary = {}
var _talent_rows: Dictionary = {}
## 档案面板的资源库存标签：资源 id → 数量 Label。
var _stash_labels: Dictionary = {}
## 主场景后台预加载：避免点击部署时同步加载 1 秒导致进局冻结。
var _main_scene: PackedScene
var _main_preload_started := false
var _loading_overlay: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	PixelUI.apply_theme(self)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.start_ambient()
	_build()
	_refresh_dossier()
	# 在菜单停留时就把命中/击杀特效与枪口火光分摊烘焙好，进场后不再卡帧。
	if DisplayServer.get_name() != "headless":
		var warmup := COMBAT_FX_WARMUP.new()
		warmup.name = "CombatFxWarmup"
		add_child(warmup)
		var variants := HIT_FX.impact_variants()
		# 枪口火光优先烘焙，保证玩家快速部署时第一次开火也不卡。
		variants.push_front({"id": "projectiles/muzzle-pistol", "opts": {}})
		warmup.setup(variants)
		_start_main_preload()


## 主菜单停留期间后台加载 Main2D.tscn，点击部署时只做实例化与入场。
func _start_main_preload() -> void:
	if _main_preload_started or _main_scene != null:
		return
	_main_preload_started = ResourceLoader.load_threaded_request(
		MAIN_SCENE, "PackedScene") == OK


func _process(_delta: float) -> void:
	if not _main_preload_started or _main_scene != null:
		return
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_main_scene = ResourceLoader.load_threaded_get(MAIN_SCENE) as PackedScene
		_main_preload_started = false
	elif status == ResourceLoader.THREAD_LOAD_FAILED \
			or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_main_preload_started = false


func _build() -> void:
	var backdrop := _Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_build_menu_column()
	_build_dossier()
	_build_controls_card()
	_build_footer()

	talents = TalentTree2D.new()
	talents.name = "TalentTree2D"
	talents.closed.connect(_on_talents_closed)
	add_child(talents)

	armory = ArmoryMenu2D.new()
	armory.name = "ArmoryMenu2D"
	armory.closed.connect(func() -> void: start_button.grab_focus())
	add_child(armory)

	stash = StashMenu2D.new()
	stash.name = "StashMenu2D"
	stash.closed.connect(func() -> void: start_button.grab_focus())
	add_child(stash)

	save_slots = SAVE_SLOTS_MENU.new()
	save_slots.name = "SaveSlotsMenu2D"
	save_slots.closed.connect(func() -> void: start_button.grab_focus())
	save_slots.slot_loaded.connect(_on_slot_loaded)
	add_child(save_slots)

	deployment = DeploymentMenu2D.new()
	deployment.name = "DeploymentMenu2D"
	deployment.deploy_confirmed.connect(_deploy)
	deployment.closed.connect(func() -> void: start_button.grab_focus())
	add_child(deployment)

	settings_menu = SettingsMenu2D.new()
	settings_menu.name = "SettingsMenu2D"
	settings_menu.closed.connect(func() -> void: start_button.grab_focus())
	add_child(settings_menu)

	codex = CodexMenu2D.new()
	codex.name = "CodexMenu2D"
	codex.closed.connect(func() -> void: start_button.grab_focus())
	add_child(codex)
	start_button.grab_focus()


## 左列：标题 + 主操作。按钮宽度固定，避免不同字号把 VBox 撑歪。
func _build_menu_column() -> void:
	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rows.offset_left = 104
	rows.offset_right = 652
	rows.offset_top = 116
	rows.offset_bottom = -80
	rows.add_theme_constant_override("separation", 8)
	add_child(rows)

	PixelUI.label(rows, "OPERATION THISTLE // RAID CONTROL", PixelUI.FS_BODY, PixelUI.AMBER)
	var title := PixelUI.label(rows, "蓟花行动", PixelUI.FS_HUGE, PixelUI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var english := PixelUI.label(rows, "D O L L   P R O T O C O L", PixelUI.FS_TITLE, PixelUI.AMBER)
	english.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)

	var subtitle := PixelUI.label(rows, "俯视 2D 像素战术射击 // 下潜 · 搜刮 · 撤离",
		PixelUI.FS_BODY, PixelUI.DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 22
	rows.add_child(spacer)

	var select := PixelUI.label(rows, "行动选择 // SELECT", PixelUI.FS_BODY, PixelUI.DIM)
	select.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	rows.add_child(actions)

	start_button = PixelUI.primary_button("开始行动", 64)
	start_button.custom_minimum_size.x = 258
	start_button.pressed.connect(_start)
	actions.add_child(start_button)

	waves_button = PixelUI.button("浪潮生存", 64)
	waves_button.custom_minimum_size.x = 154
	waves_button.pressed.connect(_start_waves)
	actions.add_child(waves_button)

	talents_button = PixelUI.button("天赋树 // TALENTS", 52)
	talents_button.custom_minimum_size.x = 420
	talents_button.pressed.connect(_open_talents)
	rows.add_child(talents_button)

	armory_button = PixelUI.button("武备库 // ARSENAL", 52)
	armory_button.custom_minimum_size.x = 420
	armory_button.pressed.connect(_open_armory)
	rows.add_child(armory_button)

	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", 8)
	rows.add_child(utility)

	stash_button = PixelUI.button("仓库 // STASH", 52)
	stash_button.custom_minimum_size.x = 206
	stash_button.pressed.connect(_open_stash)
	utility.add_child(stash_button)

	saves_button = PixelUI.button("存档 // SLOTS", 52)
	saves_button.custom_minimum_size.x = 206
	saves_button.pressed.connect(_open_saves)
	utility.add_child(saves_button)

	var utility2 := HBoxContainer.new()
	utility2.add_theme_constant_override("separation", 8)
	rows.add_child(utility2)

	settings_button = PixelUI.button("设置 // SETTINGS", 48)
	settings_button.custom_minimum_size.x = 206
	settings_button.pressed.connect(_open_settings)
	utility2.add_child(settings_button)

	codex_button = PixelUI.button("图鉴 // CODEX", 48)
	codex_button.custom_minimum_size.x = 206
	codex_button.pressed.connect(_open_codex)
	utility2.add_child(codex_button)

	quit_button = PixelUI.button("退出游戏", 48)
	quit_button.custom_minimum_size.x = 420
	quit_button.pressed.connect(_quit_game)
	rows.add_child(quit_button)

	var hint := PixelUI.label(rows, "ENTER 开始 · ESC 退出", PixelUI.FS_BODY, PixelUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## 右列：DOLL-01 档案。读 Progress，天赋购买返回后自动刷新。
func _build_dossier() -> void:
	var panel := PixelUI.panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -712
	panel.offset_right = -88
	panel.offset_top = 116
	panel.offset_bottom = 656
	add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)

	PixelUI.label(rows, "DOLL-01 // 作战档案", PixelUI.FS_TITLE, PixelUI.AMBER)
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.6))
	rows.add_child(divider)

	_credit_row(rows)
	_resource_row(rows, "基础资源", ResourceDB.BASIC)
	_resource_row(rows, "进阶资源", ResourceDB.ADVANCED)
	_stat_row(rows, "经验 XP", "xp")
	_stat_row(rows, "技能等级", "skill")
	_stat_row(rows, "战术天赋", "talents")

	var talent_divider := HSeparator.new()
	talent_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.6))
	rows.add_child(talent_divider)
	PixelUI.label(rows, "战术天赋 // TALENTS", PixelUI.FS_BODY, PixelUI.AMBER)
	for def in TalentTree2D.NODES:
		_talent_row(rows, def)

	var objective_divider := HSeparator.new()
	objective_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.6))
	rows.add_child(objective_divider)
	PixelUI.label(rows, "本局目标 // OBJECTIVE", PixelUI.FS_BODY, PixelUI.AMBER)
	PixelUI.label(rows, "进入 K-17 设施，回收资源并抵达东侧撤离点", PixelUI.FS_BODY, PixelUI.TEXT)


func _stat_row(parent: Node, title: String, key: String, font_size := PixelUI.FS_BODY) -> void:
	var line := HBoxContainer.new()
	parent.add_child(line)
	var name_label := PixelUI.label(line, title, font_size, PixelUI.DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := PixelUI.label(line, "-", font_size, PixelUI.TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats[key] = value


## 信用点：图标 + 名称 + 数值。
func _credit_row(parent: Node) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	PixelUI.icon(line, "res_credit", 22)
	var name_label := PixelUI.label(line, "信用点", 20, PixelUI.DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := PixelUI.label(line, "-", 20, PixelUI.AMBER)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats["credits"] = value


## 资源行：图标 + 数量，占位比长文本更紧凑。
func _resource_row(parent: Node, title: String, ids: Array[StringName]) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	var name_label := PixelUI.label(line, title, 20, PixelUI.DIM)
	name_label.custom_minimum_size.x = 100
	for id in ids:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		line.add_child(cell)
		PixelUI.icon(cell, "res_" + String(id), 20)
		var count := PixelUI.label(cell, "0", 20, PixelUI.TEXT)
		_stash_labels[String(id)] = count


func _talent_row(parent: Node, def: Dictionary) -> void:
	var line := HBoxContainer.new()
	parent.add_child(line)
	var name_label := PixelUI.label(line, String(def["title"]), 20, PixelUI.DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := PixelUI.label(line, "Lv.0 / 0", 20, PixelUI.DIM)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_talent_rows[def["id"]] = value


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
	for id in _talent_rows:
		var level := int(p.talent_2d_level(id))
		var maximum := int(p.talent_2d_max(id))
		total += level
		max_total += maximum
		var value: Label = _talent_rows[id]
		value.text = "Lv.%d / %d" % [level, maximum]
		value.add_theme_color_override("font_color", PixelUI.AMBER if level > 0 else PixelUI.DIM)
	_stats["talents"].text = "%d / %d" % [total, max_total]


func _set_stash(id: StringName, value: int) -> void:
	var label: Label = _stash_labels.get(String(id))
	if label == null:
		return
	label.text = str(value)
	label.add_theme_color_override("font_color", PixelUI.TEXT if value > 0 else PixelUI.DIM)


func _on_talents_closed() -> void:
	start_button.grab_focus()
	_refresh_dossier()


## 右下角操作卡：让首次进入的玩家不用记按键。
func _build_controls_card() -> void:
	var card := PixelUI.panel()
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	card.offset_left = -420
	card.offset_top = -236
	card.offset_right = -48
	card.offset_bottom = -48
	add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	card.add_child(rows)
	PixelUI.label(rows, "操作 // CONTROLS", PixelUI.FS_BODY, PixelUI.AMBER)
	PixelUI.label(rows, "WASD 移动 · 左键开火", PixelUI.FS_BODY, PixelUI.TEXT)
	PixelUI.label(rows, "右键瞄准 · Alt+滚轮 缩放视角", PixelUI.FS_BODY, PixelUI.TEXT)
	PixelUI.label(rows, "ESC 菜单 · M 地图", PixelUI.FS_BODY, PixelUI.TEXT)
	PixelUI.label(rows, "TAB 背包 · 1-2 切枪", PixelUI.FS_BODY, PixelUI.TEXT)
	PixelUI.label(rows, "E 交互 · X 收/拔枪", PixelUI.FS_BODY, PixelUI.DIM)


## 左下角行动摘要：补足一局的信息层级，同时平衡左侧留白。
func _build_footer() -> void:
	var footer := VBoxContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 104
	footer.offset_top = -104
	footer.offset_right = 652
	footer.offset_bottom = -40
	footer.add_theme_constant_override("separation", 2)
	add_child(footer)
	PixelUI.label(footer, "SESSION K-17 // INSERTION EAST", PixelUI.FS_BODY, Color(PixelUI.AMBER, 0.7))
	PixelUI.label(footer, "设施仍在运转 · 建议轻装下潜", PixelUI.FS_BODY, PixelUI.DIM)


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


## 读档后基地档案立即刷新，避免继续显示旧信用点/天赋。
func _on_slot_loaded(_slot: int) -> void:
	_refresh_dossier()


## 退出前先写盘，保证「退出游戏自动存档」在菜单退出路径上一定生效。
func _quit_game() -> void:
	var p := get_node_or_null("/root/Progress")
	if p != null:
		p.autosave_on_exit()
	get_tree().quit()


func _start() -> void:
	if _closing:
		return
	# 开始行动先进入部署页，选择出生点后再进场。
	_pending_mode = "raid"
	if deployment != null:
		deployment.set_mode("raid")
		deployment.open()


## 浪潮生存：同样先选出生点，进场后按波次刷怪。
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
		# 先让加载画面渲染一帧，再用后台已加载好的场景替换。
		await get_tree().process_frame
	var packed: PackedScene = await _wait_main_scene()
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)


## 部署时的全屏加载画面：覆盖场景替换与关卡生成的 200~300ms 冻结。
func _show_loading_overlay() -> void:
	if _loading_overlay != null:
		return
	_loading_overlay = ColorRect.new()
	_loading_overlay.color = Color(0.015, 0.018, 0.021, 0.97)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_loading_overlay)
	var title := PixelUI.label(_loading_overlay, "部署中 // DEPLOYING", 34, PixelUI.AMBER)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = -42
	title.offset_bottom = 6
	var sub := PixelUI.label(_loading_overlay, "正在装载设施与敌情数据…", 20, PixelUI.DIM)
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.offset_left = -300
	sub.offset_right = 300
	sub.offset_top = 16
	sub.offset_bottom = 48


## 等待后台场景加载完成；失败时返回 null，由调用方退回同步加载。
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
	# 部署/天赋树/武器库/仓库/存档/设置/图鉴打开时只响应 ESC 关闭，避免误触开始/退出。
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


## 无背景图：网格、扫描线、瞄准环与「01」水印全部用 draw 指令画。
class _Backdrop extends Control:
	var _sweep := 0.0


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)


	func _process(delta: float) -> void:
		_sweep = fmod(_sweep + delta * 0.055, 1.0)
		queue_redraw()


	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.009, 0.013, 0.019))
		var split := s.x * 0.52

		var grid := Color(PixelUI.AMBER, 0.05)
		var x := split
		while x < s.x:
			draw_line(Vector2(x, 0), Vector2(x, s.y), grid, 1.0)
			x += 72.0
		var y := 0.0
		while y < s.y:
			draw_line(Vector2(split, y), Vector2(s.x, y), grid, 1.0)
			y += 72.0

		draw_string(PixelUI.FONT, Vector2(s.x * 0.56, s.y * 0.53), "01",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 320, Color(PixelUI.AMBER, 0.05))
		var center := Vector2(s.x * 0.78, s.y * 0.45)
		draw_arc(center, 176.0, 0.0, TAU, 64, Color(PixelUI.AMBER, 0.07), 2.0)
		draw_arc(center, 122.0, 0.0, TAU, 48, Color(PixelUI.AMBER, 0.04), 1.0)
		var tick := Color(PixelUI.AMBER, 0.12)
		draw_line(center + Vector2(-212, 0), center + Vector2(-128, 0), tick, 2.0)
		draw_line(center + Vector2(128, 0), center + Vector2(212, 0), tick, 2.0)
		draw_line(center + Vector2(0, -212), center + Vector2(0, -128), tick, 2.0)
		draw_line(center + Vector2(0, 128), center + Vector2(0, 212), tick, 2.0)

		var scan := Color(1, 1, 1, 0.014)
		var sy := 0.0
		while sy < s.y:
			draw_line(Vector2(0, sy), Vector2(s.x, sy), scan, 1.0)
			sy += 4.0
		var sweep_y := s.y * _sweep
		draw_line(Vector2(0, sweep_y), Vector2(s.x, sweep_y), Color(PixelUI.OK, 0.035), 2.0)

		draw_line(Vector2(split, 0), Vector2(split, s.y), Color(PixelUI.AMBER, 0.16), 1.0)
		draw_line(Vector2(88, 76), Vector2(604, 76), Color(PixelUI.AMBER, 0.28), 2.0)
		draw_line(Vector2(s.x - 712, 76), Vector2(s.x - 88, 76), Color(PixelUI.AMBER, 0.28), 2.0)
		_draw_corners(s)


	func _draw_corners(s: Vector2) -> void:
		var c := Color(PixelUI.AMBER, 0.35)
		var m := 24.0
		var l := 72.0
		draw_line(Vector2(m, m), Vector2(m + l, m), c, 2.0)
		draw_line(Vector2(m, m), Vector2(m, m + l), c, 2.0)
		draw_line(Vector2(s.x - m, m), Vector2(s.x - m - l, m), c, 2.0)
		draw_line(Vector2(s.x - m, m), Vector2(s.x - m, m + l), c, 2.0)
		draw_line(Vector2(m, s.y - m), Vector2(m + l, s.y - m), c, 2.0)
		draw_line(Vector2(m, s.y - m), Vector2(m, s.y - m - l), c, 2.0)
		draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m - l, s.y - m), c, 2.0)
		draw_line(Vector2(s.x - m, s.y - m), Vector2(s.x - m, s.y - m - l), c, 2.0)
