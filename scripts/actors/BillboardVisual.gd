extends Node3D
class_name BillboardVisual
## 8 向像素立绘控制器（固定 Y billboard）。
##
## 图集：8 列（方向 0=正面/朝向镜头，顺时针）x 23 行（动画帧）。
## 骨骼逻辑仍在 XZ 平面，朝向由 Doll.rotation.y 决定，这里只负责选帧。
##
## 与旧版的区别：使用 BILLBOARD_FIXED_Y，立绘始终竖直。
## 玩家立绘另由 Doll 打开 no_depth_test，墙体不再把角色裁成两半。

const SHEET_PATH := "res://assets/art/characters/doll_a/doll_a_8dir_cel.png"
const CELL_W := 128
const CELL_H := 192
const BODY_H := 1.72
const BODY_HEIGHT_RATIO := 15.0 / 16.0
const BASELINE_RATIO := 31.0 / 32.0
const COLS := 8
const SHADOW_TEX := preload("res://assets/art/fx/shadow_radial.png")
## HD-2D 外描边：背后放大的深色剪影，比例越大描边越粗。
const OUTLINE_SCALE := 1.03
const OUTLINE_COLOR := Color(0.02, 0.03, 0.045, 1.0)

const ROWS := {
	"idle":   {"start": 0,  "count": 4, "fps": 6.0,  "loop": true},
	"walk":   {"start": 4,  "count": 8, "fps": 10.0, "loop": true},
	"aim":    {"start": 12, "count": 1, "fps": 1.0,  "loop": true},
	"fire":   {"start": 13, "count": 2, "fps": 18.0, "loop": false},
	"reload": {"start": 15, "count": 3, "fps": 8.0,  "loop": false},
	"hurt":   {"start": 18, "count": 1, "fps": 1.0,  "loop": false},
	"death":  {"start": 19, "count": 4, "fps": 8.0,  "loop": false},
}

const DIR_NAMES := [
	"FRONT", "FRONT-R", "RIGHT", "BACK-R",
	"BACK", "BACK-L", "LEFT", "FRONT-L",
]

signal anim_finished(name: String)

@onready var body: AnimatedSprite3D = $Body

var doll: CharacterBody3D
var current_dir := 0
var current_anim := "idle"
var outline: Sprite3D

static func calculate_projection(cell_height: float, character_height: float = BODY_H, source_height_ratio: float = BODY_HEIGHT_RATIO, baseline_ratio: float = BASELINE_RATIO) -> Vector2:
	var pixel_size := character_height / (cell_height * source_height_ratio)
	var local_y := (baseline_ratio - 0.5) * cell_height * pixel_size
	return Vector2(pixel_size, local_y)

## 共享贴地软阴影：主角与敌人使用同一套投影规则。
static func add_ground_shadow(host: Node3D, size := 1.55, alpha := 0.6, height := 0.026) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0
	mi.position.y = height
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = SHADOW_TEX
	mat.albedo_color = Color(1, 1, 1, alpha)
	mat.render_priority = 1
	mi.material_override = mat
	mi.cast_shadow = 0
	host.add_child(mi)
	return mi

## 只投影不显示的胶囊体：让立绘在方向光下也有真实影子。
static func add_shadow_caster(host: Node3D, radius := 0.34, height := 1.7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = height
	mi.mesh = cap
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.position.y = height * 0.5
	host.add_child(mi)
	return mi

func _ready() -> void:
	doll = get_parent() as CharacterBody3D
	body.billboard = 2                       # BILLBOARD_FIXED_Y：竖直平面，只绕 Y
	body.alpha_cut = 1                       # ALPHA_CUT_DISCARD
	body.texture_filter = 3                  # LINEAR_WITH_MIPMAPS
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 受光保留体积明暗，外描边与接地阴影负责把立绘"钉"进场景。
	body.shaded = true
	var projection := calculate_projection(CELL_H)
	body.pixel_size = projection.x
	body.position.y = projection.y
	body.modulate = Color(1.12, 1.14, 1.18)
	_build_frames()
	_build_outline()
	body.animation_finished.connect(_on_anim_finished)
	_apply("idle", 0)

func _build_frames() -> void:
	var tex := load(SHEET_PATH) as Texture2D
	if tex == null:
		push_error("BillboardVisual: 找不到图集 " + SHEET_PATH)
		return
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim_name in ROWS.keys():
		var cfg: Dictionary = ROWS[anim_name]
		var count := int(cfg["count"])
		for d in COLS:
			var an := "%s_%d" % [anim_name, d]
			sf.add_animation(an)
			sf.set_animation_speed(an, float(cfg["fps"]))
			sf.set_animation_loop(an, bool(cfg["loop"]))
			for f in count:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(
					float(d * CELL_W),
					float((int(cfg["start"]) + f) * CELL_H),
					float(CELL_W),
					float(CELL_H)
				)
				at.filter_clip = true
				sf.add_frame(an, at)
	body.sprite_frames = sf

func _process(_dt: float) -> void:
	sync_direction()
	_sync_outline()

## 背后剪影与主体共用同一帧纹理；沿相机视线后移 2cm，避免共面闪烁，
## 同时沿视线方向的位移不会改变屏幕位置。抬升量保证放大后脚底仍贴地。
func _build_outline() -> void:
	outline = Sprite3D.new()
	outline.name = "Outline"
	outline.billboard = 2
	outline.alpha_cut = 1
	outline.texture_filter = 3
	outline.shaded = false
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.pixel_size = body.pixel_size * OUTLINE_SCALE
	outline.modulate = OUTLINE_COLOR
	# 立绘与剪影都走透明管线时按 render_priority 排序：剪影先画，主体后画。
	outline.render_priority = -1
	add_child(outline)

func _sync_outline() -> void:
	if outline == null or body == null or body.sprite_frames == null:
		return
	if not body.sprite_frames.has_animation(body.animation):
		return
	outline.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
	# 放大后脚底会下移，需要抬升 half_h * (scale-1)；俯视镜头下抬升会拉近与相机
	# 的距离，因此剪影还要沿视线方向（远离相机）多推 3cm，才能在深度上稳定落后于主体。
	var lift := body.pixel_size * float(CELL_H) * 0.5 * (OUTLINE_SCALE - 1.0)
	var back_dir := Vector3(0.0, 0.0, -1.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		back_dir = -cam.global_transform.basis.z.normalized()
	var back_len := 0.03 - lift * back_dir.y
	outline.global_position = body.global_position + back_dir * back_len + Vector3.UP * lift

func sync_direction() -> void:
	var d := compute_dir()
	if d != current_dir:
		var frame := body.frame
		var progress := body.frame_progress
		current_dir = d
		_apply(current_anim, current_dir)
		body.set_frame_and_progress(frame, progress)

## 固定 Y 立绘：横向取相机右向在 XZ 平面的投影，纵向取世界 UP。
func pixel_to_world(pixel: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var point := Vector2(pixel.x, -pixel.y) + body.offset
	if body.centered:
		point += Vector2(-CELL_W * 0.5, CELL_H * 0.5)
	if body.flip_h:
		point.x = -point.x
	if body.flip_v:
		point.y = -point.y
	var right := Vector3.RIGHT
	if cam != null:
		right = cam.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
	var size := body.global_basis.get_scale()
	return body.global_position + right * point.x * body.pixel_size * size.x + Vector3.UP * point.y * body.pixel_size * size.y

func compute_dir() -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null or doll == null:
		return 0
	# 屏幕右 = 相机本地 +X 投影到 XZ；屏幕下 = 相机本地 +Z 投影到 XZ
	var right := cam.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return 0
	right = right.normalized()
	var down := cam.global_transform.basis.z
	down.y = 0.0
	if down.length_squared() < 0.0001:
		return 0
	down = down.normalized()

	var yaw := doll.rotation.y
	var facing := Vector3(sin(yaw), 0.0, cos(yaw))
	var ang := atan2(facing.dot(right), facing.dot(down))
	return wrapi(int(round(ang / (TAU / 8.0))), 0, 8)

func play_state(state: String) -> void:
	if state == current_anim:
		return
	current_anim = state
	_apply(current_anim, current_dir)

func play_state_dir(state: String, dir: int) -> void:
	current_dir = wrapi(dir, 0, 8)
	current_anim = state
	_apply(current_anim, current_dir)

func set_speed_scale(s: float) -> void:
	body.speed_scale = clampf(s, 0.4, 2.0)

func _apply(anim_name: String, dir: int) -> void:
	var an := "%s_%d" % [anim_name, dir]
	if body.sprite_frames == null or not body.sprite_frames.has_animation(an):
		return
	body.play(an)
	body.frame = 0

func dir_name() -> String:
	return DIR_NAMES[current_dir]

func _on_anim_finished() -> void:
	anim_finished.emit(current_anim)
