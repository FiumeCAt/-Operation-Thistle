extends CanvasLayer
class_name ScreenVignette
## 屏幕暗角：压暗画面边缘，带轻微雾噪。位于世界与准心/HUD 之间。

func _ready() -> void:
	layer = 3
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/screen_vignette.gdshader")
	mat.set_shader_parameter("edge_alpha", 0.86)
	rect.material = mat
	add_child(rect)
