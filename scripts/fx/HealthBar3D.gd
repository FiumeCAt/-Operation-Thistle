extends Node3D
class_name HealthBar3D
## 头顶机械分段血条：绿→红渐变，段与段之间留缝，受伤时整体闪白。

const BAR_WIDTH := 0.94
const BAR_HEIGHT := 0.12

const GRADIENT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float ratio = 1.0;
uniform float segments = 14.0;
uniform vec3 color_low = vec3(0.96, 0.28, 0.22);
uniform vec3 color_high = vec3(0.36, 0.92, 0.52);
uniform float flash = 0.0;

void fragment() {
	if (UV.x > clamp(ratio, 0.0, 1.0)) {
		discard;
	}
	float local = fract(UV.x * segments);
	if (local < 0.08) {
		discard;
	}
	vec3 col = mix(color_low, color_high, smoothstep(0.10, 0.80, ratio));
	// 上沿高光、下沿压暗，得到有厚度的金属条
	col = mix(col, col * 1.35, step(0.78, UV.y));
	col = mix(col, col * 0.55, step(UV.y, 0.22));
	ALBEDO = mix(col, vec3(1.0, 0.95, 0.86), clamp(flash, 0.0, 1.0));
}
"""

var ratio := 1.0
var emphasis := 0.0
var _fill: MeshInstance3D
var _material: ShaderMaterial

func _ready() -> void:
	_quad(Vector2(BAR_WIDTH + 0.03, BAR_HEIGHT + 0.025), Color(0.02, 0.03, 0.04), -0.005)
	_fill = _quad(Vector2(BAR_WIDTH, BAR_HEIGHT), Color.WHITE, 0.0)
	var shader := Shader.new()
	shader.code = GRADIENT_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_fill.material_override = _material
	_apply()

func _quad(size: Vector2, color: Color, z: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position.z = z
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func update_health(current: float, maximum: float, dead := false, hurt := false) -> void:
	ratio = clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	visible = not dead and ratio > 0.0
	if hurt:
		emphasis = 0.18
	_apply()

func _apply() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("ratio", ratio)
	_material.set_shader_parameter("flash", emphasis / 0.18)

func _process(dt: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		global_basis = camera.global_basis.orthonormalized()
	if emphasis > 0.0:
		emphasis = maxf(0.0, emphasis - dt)
		_apply()
