extends CanvasLayer
class_name DebugHUD
## 战斗 HUD：底部操作提示条。F1 或进入行动 10 秒后自动隐藏，避免长期遮挡画面。

var doll: Doll
var rig: CameraRig
var main

var _root: Control
var _panel: PixelUI.PixelPanel

func setup(d: Doll, r: CameraRig, m) -> void:
	doll = d
	rig = r
	main = m

func _ready() -> void:
	_build()

func _build() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	PixelUI.apply_theme(_root)

	_panel = PixelUI.panel()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 444
	_panel.offset_top = -104
	_panel.offset_right = -476
	_panel.offset_bottom = -24
	_root.add_child(_panel)
	var hint := PixelUI.label(_panel, "WASD 移动 · SHIFT 冲刺 · 左键射击 · 右键瞄准\nE 交互 · T 手电 · R 换弹 · X 支援 · F1 隐藏提示", PixelUI.FS_BODY, PixelUI.TEXT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func set_hint_visible(on: bool) -> void:
	_panel.visible = on
