extends CanvasLayer
class_name WeaponHUD
## 右下角武器面板：主武器 / 弹种 / 膛内 + 管仓 / 备弹 / 状态 / 装填进度。

var weapon: PlayerWeapon

## 弹药显示偏好：both 图形+数值 / numeric 仅数值 / graphic 仅图形。
var display_mode := "both"

var _root: Control
var _title_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _count_label: Label
var _count_mode_label: Label
var _state_label: Label
var _progress: ProgressBar
var _strip: ShellStrip
var _acc := 0.0

func setup(w: PlayerWeapon) -> void:
	weapon = w

func _ready() -> void:
	_build()
	_load_display_mode()
	_apply_display_mode()

func _build() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelUI.apply_theme(_root)

	var p := PixelUI.panel()
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = -464
	p.offset_top = -224
	p.offset_right = -24
	p.offset_bottom = -24
	_root.add_child(p)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)

	_title_label = PixelUI.label(vb, "M870 // 12 GAUGE", PixelUI.FS_BODY, PixelUI.TEXT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var ammo_row := HBoxContainer.new()
	ammo_row.add_theme_constant_override("separation", 8)
	vb.add_child(ammo_row)
	PixelUI.icon(ammo_row, "ammo", 26)
	_ammo_label = PixelUI.label(ammo_row, "鹿弹", PixelUI.FS_BODY, PixelUI.AMBER)
	_ammo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reserve_label = PixelUI.label(ammo_row, "备弹 24", PixelUI.FS_BODY, PixelUI.DIM)
	_reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var shell_row := HBoxContainer.new()
	shell_row.add_theme_constant_override("separation", 14)
	vb.add_child(shell_row)
	_strip = ShellStrip.new()
	_strip.custom_minimum_size = Vector2(150, 40)
	_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shell_row.add_child(_strip)
	var count_box := VBoxContainer.new()
	count_box.add_theme_constant_override("separation", 2)
	count_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell_row.add_child(count_box)
	_count_label = PixelUI.label(count_box, "5 + 1", PixelUI.FS_TITLE, PixelUI.TEXT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_mode_label = PixelUI.label(count_box, "管仓 + 膛内", PixelUI.FS_BODY, PixelUI.DIM)
	_count_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_state_label = PixelUI.label(vb, "就绪", PixelUI.FS_BODY, PixelUI.AMBER)
	_progress = PixelUI.bar(8)
	_progress.max_value = 100
	_progress.value = 0
	_progress.custom_minimum_size.x = 120
	vb.add_child(_progress)

func _load_display_mode() -> void:
	var progress := get_node_or_null("/root/Progress")
	if progress:
		display_mode = String(progress.data.get("ammo_display", "both"))
	if not ProgressService.AMMO_DISPLAY_MODES.has(display_mode):
		display_mode = "both"

func _cycle_display_mode() -> void:
	var modes: Array = ProgressService.AMMO_DISPLAY_MODES
	display_mode = String(modes[(modes.find(display_mode) + 1) % modes.size()])
	var progress := get_node_or_null("/root/Progress")
	if progress:
		progress.set_ammo_display(display_mode)
	_apply_display_mode()

func _apply_display_mode() -> void:
	if _strip == null:
		return
	_strip.visible = display_mode != "numeric"
	_count_label.visible = display_mode != "graphic"

func _process(dt: float) -> void:
	if visible and Input.is_action_just_pressed("ammo_display"):
		_cycle_display_mode()
	_acc += dt
	if _acc < 0.05:
		return
	_acc = 0.0
	if weapon == null:
		return

	var ammo := weapon.get_ammo()
	_title_label.text = weapon.weapon.display_name
	_ammo_label.text = ammo.display_name
	_ammo_label.add_theme_color_override("font_color", ammo.color)
	_reserve_label.text = "备弹 %d" % weapon.get_reserve()
	var chamber_loaded := 1 if weapon.weapon.chamber_size > 0 and weapon.chamber == "LOADED" else 0
	if weapon.weapon.feed_mode == &"mag":
		_count_label.text = "%d / %d" % [weapon.mag, weapon.get_mag_capacity()]
		_count_mode_label.text = "弹匣 · J"
	else:
		_count_label.text = "%d + %d" % [weapon.mag, chamber_loaded]
		_count_mode_label.text = "管仓 + 膛内 · J"

	_strip.chamber = weapon.chamber
	_strip.mag = weapon.mag
	_strip.cap = weapon.get_mag_capacity()
	_strip.feed_mode = weapon.weapon.feed_mode
	_strip.queue_redraw()

	_state_label.text = "就绪" if weapon.state_text == "READY" else weapon.state_text
	var danger := (
		weapon.state_text.contains("泵动")
		or weapon.state_text.contains("空")
		or weapon.state_text.contains("上膛")
		or weapon.state_text.contains("耗尽")
	)
	_state_label.add_theme_color_override("font_color", PixelUI.DANGER if danger else PixelUI.AMBER)
	_progress.value = weapon.get_progress() * 100.0


class ShellStrip extends Control:
	## 第 1 格是膛内，后 5 格是管仓。弹匣武器画成弹匣形状的格子块。
	var chamber := "LOADED"
	var mag := 0
	var cap := 5
	var feed_mode: StringName = &"shell"

	func _draw() -> void:
		var amber := PixelUI.AMBER
		if feed_mode == &"mag":
			var cols := mini(cap, 8)
			var rows := ceili(float(cap) / float(maxi(cols, 1)))
			var cell := Vector2(11.0, 8.0)
			var gap := 3.0
			var box := Vector2(cols * (cell.x + gap) + gap, rows * (cell.y + gap) + gap)
			var origin := (size - box) * 0.5
			draw_rect(Rect2(origin - Vector2(3, 3), box + Vector2(6, 6)), Color(0.85, 0.89, 0.92, 0.85), false, 1.0)
			for i in cap:
				var pos := origin + Vector2(gap + (i % cols) * (cell.x + gap), gap + floori(float(i) / float(cols)) * (cell.y + gap))
				var loaded := i < mag
				draw_rect(Rect2(pos, cell), amber if loaded else Color(0.11, 0.14, 0.17, 0.95), true)
				draw_rect(Rect2(pos, cell), Color(0.55, 0.60, 0.64, 0.8), false, 1.0)
			return
		var w := 16.0
		var h := 30.0
		var gap2 := 4.0
		var total := float(cap + 1) * (w + gap2) - gap2
		var ox := maxf(0.0, (size.x - total) * 0.5)
		var oy := maxf(0.0, (size.y - h) * 0.5)
		for i in range(cap + 1):
			var x := ox + float(i) * (w + gap2)
			var loaded := (i == 0 and chamber == "LOADED") or (i > 0 and i <= mag)
			var fired := i == 0 and chamber == "FIRED"
			var col := amber if loaded else (Color(0.45, 0.15, 0.12) if fired else Color(0.13, 0.16, 0.20))
			draw_rect(Rect2(x, oy, w, h), col, true)
			var border := PixelUI.AMBER_BRIGHT if i == 0 else Color(0.38, 0.44, 0.50, 0.85)
			draw_rect(Rect2(x, oy, w, h), border, false, 2.0)
