extends CanvasLayer
class_name PixelGrade
## 全屏像素调色：色阶量化 + Bayer 抖动 + 冷暖分离。
## 层级 1：在世界之上、暗角/准心/HUD 之下，只影响场景与角色。

func _ready() -> void:
	layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_grade.gdshader")
	rect.material = mat
	add_child(rect)
