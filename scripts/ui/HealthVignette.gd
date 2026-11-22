extends CanvasLayer
class_name HealthVignette
## 低血量视觉反馈：红色边缘 + 去饱和，生命越低越明显。
## 画在世界与动态模糊之上、准心与 HUD 之下，不会遮住瞄准信息。

const START_RATIO := 0.5

var doll: Doll
var _rect: ColorRect
var _mat: ShaderMaterial
var _current := 0.0

func _ready() -> void:
	layer = 2
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/health_vignette.gdshader")
	_mat.set_shader_parameter("intensity", 0.0)
	_rect.material = _mat
	add_child(_rect)

func setup(d: Doll) -> void:
	doll = d

func _process(dt: float) -> void:
	if doll == null:
		return
	var ratio := clampf(doll.hp / maxf(1.0, doll.hp_max), 0.0, 1.0)
	var target := clampf((START_RATIO - ratio) / START_RATIO, 0.0, 1.0)
	_current = lerpf(_current, target, 1.0 - exp(-8.0 * dt))
	_mat.set_shader_parameter("intensity", _current)
