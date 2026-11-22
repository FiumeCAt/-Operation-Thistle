extends CanvasLayer
## 启动界面：高清走廊背景 + 标题 + 开始/退出。回车或点击「开始游戏」进入基地。

signal started

var _root: Control
var _menu_panel: Control
var _closing := false

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.apply_theme(_root)

	var bg := TextureRect.new()
	bg.texture = load("res://assets/art/ui/menu/menu_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = preload("res://shaders/title_pixel.gdshader")
	bg.material = bg_mat
	_root.add_child(bg)

	# 左侧压暗，保证文字可读且不盖住画面中央的角色
	var shade := ColorRect.new()
	shade.color = Color(0.006, 0.010, 0.016, 0.74)
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 720
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var edge := ColorRect.new()
	edge.color = Color(PixelUI.AMBER, 0.55)
	edge.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	edge.offset_left = 720
	edge.offset_right = 722
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)

	_menu_panel = Control.new()
	_menu_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_menu_panel.offset_left = 88
	_menu_panel.offset_right = 660
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_menu_panel)

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rows.offset_top = 150
	rows.offset_bottom = -96
	rows.add_theme_constant_override("separation", 12)
	_menu_panel.add_child(rows)

	PixelUI.label(rows, "OPERATION THISTLE", PixelUI.FS_NUM, PixelUI.AMBER)
	var title := PixelUI.label(rows, "蓟花行动 // DOLL PROTOCOL", PixelUI.FS_TITLE, PixelUI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", PixelUI.AMBER)
	rows.add_child(divider)
	var subtitle := PixelUI.label(rows, "2.5D 俯视战术射击 · 下潜 / 搜刮 / 撤离", PixelUI.FS_BODY, PixelUI.DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 32
	rows.add_child(spacer)

	var start := PixelUI.button("开始游戏", 64)
	start.custom_minimum_size.x = 340
	start.pressed.connect(_start)
	rows.add_child(start)

	var quit := PixelUI.button("退出游戏", 56)
	quit.custom_minimum_size.x = 340
	quit.pressed.connect(func() -> void: get_tree().quit())
	rows.add_child(quit)

	var hint := PixelUI.label(rows, "ENTER 开始 · ESC 退出", PixelUI.FS_BODY, PixelUI.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	_build_operator_card()
	start.grab_focus()

## 右下角干员卡：用立绘头像 + 存档概览
func _build_operator_card() -> void:
	var card := PixelUI.panel()
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = -404
	card.offset_top = -252
	card.offset_right = -48
	card.offset_bottom = -48
	_root.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)

	var portrait := TextureRect.new()
	portrait.texture = load("res://assets/art/ui/portraits/avatar_sheet.png")
	portrait.custom_minimum_size = Vector2(148, 148)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	PixelUI.label(info, "DOLL-01", PixelUI.FS_TITLE, PixelUI.AMBER)
	var progress := get_node_or_null("/root/Progress")
	if progress:
		var data: Dictionary = progress.data
		PixelUI.label(info, "Lv.%d    XP %d" % [int(data.get("skill_level", 1)), int(data.get("xp", 0))], PixelUI.FS_BODY, PixelUI.TEXT)
		PixelUI.label(info, "信用点 %d" % int(data.get("resources", 0)), PixelUI.FS_BODY, PixelUI.DIM)
		PixelUI.label(info, "配装 %s" % String(data.get("loadout", {}).get("weapon", "m870")), PixelUI.FS_BODY, PixelUI.DIM)
	PixelUI.label(info, "状态 就绪", PixelUI.FS_BODY, PixelUI.OK)

func _start() -> void:
	if _closing:
		return
	_closing = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	started.emit()
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.22)
	tween.tween_callback(_on_faded)

func _on_faded() -> void:
	_root.hide()
	queue_free()

func _input(event: InputEvent) -> void:
	if _closing or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_start()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()
