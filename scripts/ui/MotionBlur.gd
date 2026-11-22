extends CanvasLayer
class_name MotionBlur
## 屏幕空间径向动态模糊。B 键开关；速度越高越明显。

@export var enabled := true
@export var max_strength := 0.028

var doll: Doll

var _rect: ColorRect
var _mat: ShaderMaterial
var _cur := 0.0

func _ready() -> void:
	layer = 1
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/motion_blur.gdshader")
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = enabled

func setup(d: Doll) -> void:
	doll = d

func set_enabled(v: bool) -> void:
	enabled = v
	if _rect:
		_rect.visible = v

func _process(dt: float) -> void:
	if Input.is_action_just_pressed("toggle_blur"):
		set_enabled(not enabled)
		var s := get_tree().root.get_node_or_null("Sfx")
		if s:
			s.play_2d("ui", -12.0)
		var progress := get_tree().root.get_node_or_null("Progress")
		if progress:
			progress.set_motion_blur(enabled)

	if not enabled:
		return

	var speed := 0.0
	if doll:
		speed = Vector2(doll.velocity.x, doll.velocity.z).length()
	var target := clampf(speed / 7.0, 0.0, 1.0) * max_strength
	_cur = lerpf(_cur, target, 1.0 - exp(-6.0 * dt))
	_mat.set_shader_parameter("strength", _cur)
	_mat.set_shader_parameter("center", Vector2(0.5, 0.54))
