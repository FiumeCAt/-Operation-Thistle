extends Node2D
class_name DollRigV2
## Modular Doll Rig v2（Phase 7B）：
## 参考《Zed Zone / 末日地带》纸娃娃模块化架构并针对战术人偶升级：
## 1) 独立 160×160 无抗锯齿 SubViewport（TEXTURE_FILTER_NEAREST）统一像素光栅化，
##    所有旋转四肢、衣摆与发梢严格对齐 128px×1 世界像素格，杜绝锯齿与剪纸感；
## 2) 分层纸娃娃结构：Shadow / BackGear / 2段式屈膝 Legs（Thigh+Shin）/ Torso（含 ArmorSlot）/
##    SecondaryMotion（2节弹簧阻尼后发发梢 + 左右风衣衣摆 + 格裙下摆）/ 4向 Head + 独立 BlinkLayer /
##    收枪自然垂摆双臂，无缝对接 WeaponRig2D 4 大持枪姿态模板；
## 3) 上下半身解耦（下身驱动静止/行走/冲刺/侧步/倒退步态；上身与头部独立跟随准心）；
## 4) 完整演出：呼吸、随机眨眼、急停刹车惯性、开火胸肩头后坐联动、受击后仰、Phase 5 团身翻滚。

signal footstep_planted(local_offset: Vector2, is_running: bool)

const SKIN_ROOT := "res://assets/art/characters/"
const DEFAULT_SKIN := "doll_v2"
## 兼容只读常量（指向默认正式皮分件目录）
const PART_DIR := "res://assets/art/characters/doll_v2/parts/"
const SHADOW_TEX_PATH := "res://assets/art/env/pixel_shadow_64.png"

const CORE_PART_NAMES: Array[String] = [
	"head_front", "head_front_blink", "head_back", "head_left", "head_left_blink",
	"torso_front", "torso_back", "torso_left",
	"hair_back_root", "hair_back_tip", "hair_side",
	"coat_flap_root", "coat_flap_tip", "skirt_hem",
	"thigh", "shin_boot",
	"arm_upper", "arm_forearm",
]
const OPTIONAL_PART_NAMES: Array[String] = ["gun_case"]
const PART_NAMES: Array[String] = [
	"head_front", "head_front_blink", "head_back", "head_left", "head_left_blink",
	"torso_front", "torso_back", "torso_left",
	"hair_back_root", "hair_back_tip", "hair_side",
	"coat_flap_root", "coat_flap_tip", "skirt_hem",
	"thigh", "shin_boot", "gun_case",
	"arm_upper", "arm_forearm",
]
const EXTRA_COMPONENT_KEYS: Array[StringName] = [
	&"back_gear",
	&"armor",
	&"backpack",
	&"coat_flaps",
	&"hair_secondary",
]
const LIMB_COLOR_PARTS: Array[String] = ["thigh", "shin_boot", "arm_upper", "arm_forearm"]
const MANNEQUIN_LEFT_TINT := Color(0.38, 0.80, 1.0, 1.0)
const MANNEQUIN_RIGHT_TINT := Color(1.0, 0.62, 0.24, 1.0)
static var _tinted_tex_cache: Dictionary = {}
static var _player_light_mat: ShaderMaterial = null

## 统一 128px×1 像素规格画布：脚底基线位于 (80, 148)，头顶猫耳约 y = 20。
const CANVAS_SIZE := Vector2i(160, 160)
const GROUND_ORIGIN := Vector2(80.0, 148.0)

## 解剖骨架比例常量（总高 128px，与 GameUnits.DOLL_WORLD_HEIGHT_PX 严格 1:1）。
const PELVIS_HEIGHT := 58.0
const THIGH_LEN := 28.0
const SHIN_LEN := 30.0
const TORSO_HEIGHT := 40.0
const NECK_OFFSET_Y := -39.0
const SHOULDER_OFFSET_Y := -33.0
const UPPER_ARM_LEN := 16.0
const FOREARM_LEN := 16.0

## 朝向索引约定（与 Doll2D 100% 一致）：0=下(正) 1=上(背) 2=左 3=右
var upper_direction := 0
var lower_direction := 0
var locomotion_mode: StringName = &"idle"
var armed := true
var holstered := false
var aiming := false
var ads := false

## 外部可读节点引用（供单元测试、换装系统与调试检查）
var viewport: SubViewport
var rig_canvas: Sprite2D
var shadow_sprite: Sprite2D
var rig_root: Node2D
var pelvis: Node2D
var back_gear_pivot: Node2D
var backpack_slot: Node2D
var gun_case: Sprite2D
var leg_l_hip: Node2D
var leg_l_knee: Node2D
var leg_r_hip: Node2D
var leg_r_knee: Node2D
var torso_pivot: Node2D
var torso_sprite: Sprite2D
var armor_slot: Node2D
var skirt_pivot: Node2D
var coat_l_pivot: Node2D
var coat_l_tip: Node2D
var coat_r_pivot: Node2D
var coat_r_tip: Node2D
var neck_pivot: Node2D
var head_pivot: Node2D
var head_sprite: Sprite2D
var blink_sprite: Sprite2D
var hair_back_pivot: Node2D
var hair_back_tip: Node2D
var hair_side_l_pivot: Node2D
var hair_side_r_pivot: Node2D
var arm_l_shoulder: Node2D
var arm_l_elbow: Node2D
var arm_r_shoulder: Node2D
var arm_r_elbow: Node2D

var skin_id := DEFAULT_SKIN
var _limb_side_coloring := false
var _left_limb_tint := MANNEQUIN_LEFT_TINT
var _right_limb_tint := MANNEQUIN_RIGHT_TINT
var _textures: Dictionary = {}
var _textures_left: Dictionary = {}
var _textures_right: Dictionary = {}
var _part_scale_base: Dictionary = {}
var _sprite_bindings: Array[Dictionary] = []
var _skin_extra_defaults: Dictionary = {}
var _extra_component_overrides: Dictionary = {}

## 运动学与物理状态
var _gait_phase := 0.0
var _prev_sin_phase := 0.0
var _breath_time := 0.0
var _blink_cd := 2.8
var _blink_t := 0.0
var _hip_bob := 0.0
var _torso_lean := 0.0
var _torso_sway := 0.0
var _head_tilt := 0.0
var _prev_vel := Vector2.ZERO
var _brake_impulse := 0.0
var _brake_vel := 0.0
var _prev_upper_dir := -1
var _turn_squash := 0.0

## 弹簧阻尼次级物理状态（[angle, angular_vel]）
var _hair_root_a := 0.0
var _hair_root_v := 0.0
var _hair_tip_a := 0.0
var _hair_tip_v := 0.0
var _coat_l_a := 0.0
var _coat_l_v := 0.0
var _coat_r_a := 0.0
var _coat_r_v := 0.0
var _coat_tip_a := 0.0
var _coat_tip_v := 0.0
var _skirt_a := 0.0
var _skirt_v := 0.0
var _gear_bob := 0.0
var _gear_bob_v := 0.0

## 演出瞬态状态（开火后坐 / 受击后仰 / 翻滚）
var _recoil_t := 0.0
var _recoil_strength := 0.0
var _recoil_sign := 1.0
var _hurt_t := 0.0
var _hurt_dir_sign := 1.0
var _dodging := false
var _dodge_u := 0.0
var _dodge_dir := Vector2.RIGHT
var _dodge_phase_name: StringName = &"none"

## 实时肩部世界偏移（由 WeaponRig2D 读取，让持枪臂随呼吸/奔跑/后坐/翻滚无缝贴合躯干）
var _dynamic_shoulder_offset := Vector2.ZERO
var _dynamic_dodge_weapon_offset := Vector2.ZERO
var _dynamic_dodge_weapon_rot := 0.0


func _ready() -> void:
	_load_skin_textures(skin_id)
	_build_viewport_and_rig()
	_apply_facing_layers()


static func sanitize_skin_id(raw_id: String) -> String:
	var clean := raw_id.strip_edges()
	if clean.is_empty() or clean.contains("..") or clean.contains("/") or clean.contains("\\"):
		return ""
	return clean


static func skin_parts_dir(id: String) -> String:
	var clean := sanitize_skin_id(id)
	if clean.is_empty():
		return PART_DIR
	return SKIN_ROOT + clean + "/parts/"


static func skin_manifest_path(id: String) -> String:
	var clean := sanitize_skin_id(id)
	if clean.is_empty():
		return ""
	return SKIN_ROOT + clean + "/skin_manifest.json"


static func skin_exists(id: String) -> bool:
	var clean := sanitize_skin_id(id)
	if clean.is_empty():
		return false
	var dir := skin_parts_dir(clean)
	return ResourceLoader.exists(dir + "head_front.png") \
		and ResourceLoader.exists(dir + "torso_front.png")


static func colorize_neutral_pixels(src: Texture2D, tint: Color) -> Texture2D:
	if src == null:
		return null
	var cache_key := "%s|%d|%d|%d" % [
		src.resource_path,
		int(round(tint.r * 255.0)),
		int(round(tint.g * 255.0)),
		int(round(tint.b * 255.0)),
	]
	if src.resource_path != "" and _tinted_tex_cache.has(cache_key):
		return _tinted_tex_cache[cache_key]
	var img := src.get_image()
	if img == null or img.is_empty():
		return src
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			# 保留高饱和红/黄关节圆心原色，仅对中性灰度肢体主体着色
			if sat > 0.14:
				continue
			var lum := c.r
			img.set_pixel(x, y, Color(
				clampf(lum * tint.r, 0.0, 1.0),
				clampf(lum * tint.g, 0.0, 1.0),
				clampf(lum * tint.b, 0.0, 1.0),
				c.a))
	var out := ImageTexture.create_from_image(img)
	if src.resource_path != "":
		_tinted_tex_cache[cache_key] = out
	return out


## 防过曝角色光照衰减材质（缓存单例）：
## 在 VisionFog2D 多重叠加 PointLight2D（主视野+余光+可选补光）下压低角色受光增益并设上限，
## 避免白发/浅色服装被叠光烧成纯白看不清五官；无光源场景（选人界面 / F7 明亮模式）自动保持原色。
static func get_player_light_material() -> ShaderMaterial:
	if _player_light_mat != null:
		return _player_light_mat
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void light() {
	vec3 incoming = min(LIGHT_COLOR.rgb * LIGHT_ENERGY, vec3(0.85)) * 0.62;
	LIGHT = vec4(incoming * COLOR.rgb, LIGHT_COLOR.a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_player_light_mat = mat
	return _player_light_mat


func _read_skin_manifest(id: String) -> Dictionary:
	_limb_side_coloring = (id == "mannequin")
	_left_limb_tint = MANNEQUIN_LEFT_TINT
	_right_limb_tint = MANNEQUIN_RIGHT_TINT
	var extra_raw: Dictionary = {}
	var mpath := skin_manifest_path(id)
	if mpath.is_empty() or not FileAccess.file_exists(mpath):
		return extra_raw
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	if typeof(parsed) != TYPE_DICTIONARY:
		return extra_raw
	var root := parsed as Dictionary
	var cc = root.get("color_coding", null)
	if typeof(cc) == TYPE_DICTIONARY:
		var cc_dict := cc as Dictionary
		_limb_side_coloring = bool(cc_dict.get("limb_side_coloring", _limb_side_coloring))
		var lt = cc_dict.get("left_limb_tint", null)
		if lt is Array and (lt as Array).size() >= 3:
			_left_limb_tint = Color(float(lt[0]), float(lt[1]), float(lt[2]), 1.0)
		var rt = cc_dict.get("right_limb_tint", null)
		if rt is Array and (rt as Array).size() >= 3:
			_right_limb_tint = Color(float(rt[0]), float(rt[1]), float(rt[2]), 1.0)
	var ec = root.get("extra_components_default", null)
	if typeof(ec) == TYPE_DICTIONARY:
		extra_raw = ec as Dictionary
	return extra_raw


func _load_skin_textures(req_skin_id: String) -> bool:
	var clean := sanitize_skin_id(req_skin_id)
	var valid := not clean.is_empty() and skin_exists(clean)
	var active_id := clean if valid else DEFAULT_SKIN
	skin_id = active_id
	var extra_raw := _read_skin_manifest(active_id)
	_textures.clear()
	_textures_left.clear()
	_textures_right.clear()
	var dir := skin_parts_dir(active_id)
	var fallback_dir := skin_parts_dir(DEFAULT_SKIN)
	for n: String in CORE_PART_NAMES:
		var path: String = dir + n + ".png"
		var chosen := path if ResourceLoader.exists(path) else (fallback_dir + n + ".png")
		if ResourceLoader.exists(chosen):
			var tex := load(chosen) as Texture2D
			if tex != null:
				_textures[n] = tex
	# 可选额外分件（如 gun_case）：仅加载当前皮肤实际拥有的贴图，绝不串用到无背包角色上
	for opt_n: String in OPTIONAL_PART_NAMES:
		var opt_path: String = dir + opt_n + ".png"
		if ResourceLoader.exists(opt_path):
			var opt_tex := load(opt_path) as Texture2D
			if opt_tex != null:
				_textures[opt_n] = opt_tex
	_skin_extra_defaults = {
		&"back_gear": bool(extra_raw.get("back_gear", _textures.has("gun_case"))),
		&"armor": bool(extra_raw.get("armor", true)),
		&"backpack": bool(extra_raw.get("backpack", true)),
		&"coat_flaps": bool(extra_raw.get("coat_flaps", true)),
		&"hair_secondary": bool(extra_raw.get("hair_secondary", true)),
	}
	if _limb_side_coloring:
		for ln: String in LIMB_COLOR_PARTS:
			var base_tex: Texture2D = _textures.get(ln)
			if base_tex != null:
				_textures_left[ln] = colorize_neutral_pixels(base_tex, _left_limb_tint)
				_textures_right[ln] = colorize_neutral_pixels(base_tex, _right_limb_tint)
	return valid


func _resolve_part_texture(tex_key: String, side: String = "") -> Texture2D:
	if _limb_side_coloring:
		if side == "left" and _textures_left.has(tex_key):
			return _textures_left[tex_key]
		if side == "right" and _textures_right.has(tex_key):
			return _textures_right[tex_key]
	return _textures.get(tex_key)


## 运行时热切换皮肤包（默认 "doll_v2" / "doll_thistle" / 体模 "mannequin"）；非法或缺失核心分件自动安全回退 "doll_v2"。
func set_skin(new_skin_id: String) -> bool:
	var valid := _load_skin_textures(new_skin_id)
	_extra_component_overrides.clear()
	for bind: Dictionary in _sprite_bindings:
		var sp := bind.get("sprite") as Sprite2D
		if sp == null or not is_instance_valid(sp):
			continue
		var tex_key := String(bind.get("tex_key", ""))
		var target_h := float(bind.get("target_h", 0.0))
		var side := String(bind.get("side", ""))
		var tex := _resolve_part_texture(tex_key, side)
		sp.texture = tex
		if tex != null:
			if target_h > 0.0 and tex.get_height() > 0:
				var s := target_h / float(tex.get_height())
				sp.scale = Vector2(s, s)
			else:
				sp.scale = Vector2.ONE
			_part_scale_base[sp.name] = sp.scale
		else:
			sp.scale = Vector2.ONE
			_part_scale_base[sp.name] = Vector2.ONE
	if pelvis != null:
		_apply_facing_layers()
	return valid


func get_part_texture(tex_key: String) -> Texture2D:
	return _textures.get(tex_key)


func has_all_part_textures() -> bool:
	for n: String in CORE_PART_NAMES:
		if not _textures.has(n):
			return false
	return true


## ---- 角色额外组件显隐接口（back_gear / armor / backpack / coat_flaps / hair_secondary） ----

func set_extra_component_visible(component_id: StringName, enabled: bool) -> bool:
	if not EXTRA_COMPONENT_KEYS.has(component_id):
		return false
	_extra_component_overrides[component_id] = enabled
	_apply_extra_component_visibility()
	return true


func is_extra_component_visible(component_id: StringName) -> bool:
	if _extra_component_overrides.has(component_id):
		return bool(_extra_component_overrides[component_id])
	if _skin_extra_defaults.has(component_id):
		return bool(_skin_extra_defaults[component_id])
	return true


func set_extra_components(overrides: Dictionary) -> void:
	for raw_k in overrides:
		var key := StringName(String(raw_k))
		if EXTRA_COMPONENT_KEYS.has(key):
			_extra_component_overrides[key] = bool(overrides[raw_k])
	_apply_extra_component_visibility()


func clear_extra_component_overrides() -> void:
	_extra_component_overrides.clear()
	_apply_extra_component_visibility()


func get_extra_components() -> Dictionary:
	var out: Dictionary = {}
	for key: StringName in EXTRA_COMPONENT_KEYS:
		out[key] = is_extra_component_visible(key)
	return out


func get_skin_default_extra_components() -> Dictionary:
	return _skin_extra_defaults.duplicate()


func has_extra_component_asset(component_id: StringName) -> bool:
	match component_id:
		&"back_gear":
			return _textures.has("gun_case") or (backpack_slot != null and backpack_slot.get_child_count() > 0)
		&"backpack":
			return backpack_slot != null and backpack_slot.get_child_count() > 0
		&"armor":
			return armor_slot != null and armor_slot.get_child_count() > 0
		&"coat_flaps":
			return _textures.has("coat_flap_root")
		&"hair_secondary":
			return _textures.has("hair_back_root") or _textures.has("hair_side")
		_:
			return false


func _apply_extra_component_visibility() -> void:
	var show_back := is_extra_component_visible(&"back_gear")
	var show_backpack := show_back and is_extra_component_visible(&"backpack")
	var has_case := _textures.has("gun_case")
	if gun_case != null:
		gun_case.visible = show_back and has_case
	if backpack_slot != null:
		backpack_slot.visible = show_backpack
	if back_gear_pivot != null:
		var has_bp := backpack_slot != null and backpack_slot.get_child_count() > 0
		back_gear_pivot.visible = (show_back and has_case) or (show_backpack and has_bp)
	if armor_slot != null:
		armor_slot.visible = is_extra_component_visible(&"armor")
	var show_coat := is_extra_component_visible(&"coat_flaps")
	var side_u := upper_direction == 2 or upper_direction == 3
	if coat_l_pivot != null and coat_r_pivot != null:
		coat_l_pivot.visible = show_coat
		coat_r_pivot.visible = show_coat and (not side_u)
	var show_hair := is_extra_component_visible(&"hair_secondary")
	if hair_back_pivot != null:
		hair_back_pivot.visible = show_hair
	if hair_side_l_pivot != null and hair_side_r_pivot != null:
		hair_side_l_pivot.visible = show_hair and upper_direction == 0


func _make_sprite(node_name: String, tex_key: String, z: int,
		offset_px := Vector2.ZERO, target_h := 0.0, side := "") -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = node_name
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.z_index = z
	var tex := _resolve_part_texture(tex_key, side)
	if tex != null:
		sp.texture = tex
		if target_h > 0.0 and tex.get_height() > 0:
			var s := target_h / float(tex.get_height())
			sp.scale = Vector2(s, s)
	sp.offset = offset_px
	_part_scale_base[node_name] = sp.scale
	_sprite_bindings.append({
		"sprite": sp,
		"tex_key": tex_key,
		"target_h": target_h,
		"side": side,
	})
	return sp


func _build_viewport_and_rig() -> void:
	# 1) 脚底软阴影（留在主世界画布，始终贴地并随步态/翻滚缩放）
	shadow_sprite = Sprite2D.new()
	shadow_sprite.name = "Shadow"
	shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow_sprite.z_index = -3
	if ResourceLoader.exists(SHADOW_TEX_PATH):
		shadow_sprite.texture = load(SHADOW_TEX_PATH)
	shadow_sprite.position = Vector2(0.0, 2.0)
	shadow_sprite.scale = Vector2(0.72, 0.56)
	shadow_sprite.modulate = Color(1.0, 1.0, 1.0, 0.72)
	add_child(shadow_sprite)

	# 2) 160×160 无抗锯齿像素光栅化 SubViewport
	viewport = SubViewport.new()
	viewport.name = "PixelViewport"
	viewport.size = CANVAS_SIZE
	viewport.transparent_bg = true
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)

	# 3) 世界侧 1:1 显示精灵（承接 VisionFog2D 光照并挂载防过曝衰减材质，保留 Doll2D.modulate 受击闪白）
	rig_canvas = Sprite2D.new()
	rig_canvas.name = "RigCanvas"
	rig_canvas.texture = viewport.get_texture()
	rig_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rig_canvas.material = get_player_light_material()
	rig_canvas.centered = false
	rig_canvas.position = -GROUND_ORIGIN
	rig_canvas.scale = Vector2.ONE
	add_child(rig_canvas)

	# 4) SubViewport 内部模块化骨骼层级（脚底原点 (80, 148)）
	rig_root = Node2D.new()
	rig_root.name = "RigRoot"
	rig_root.position = GROUND_ORIGIN
	viewport.add_child(rig_root)

	pelvis = Node2D.new()
	pelvis.name = "Pelvis"
	pelvis.position = Vector2(0.0, -PELVIS_HEIGHT)
	rig_root.add_child(pelvis)

	# ---- 二段式屈膝双腿（Thigh -> Knee -> ShinBoot） ----
	var legs_container := Node2D.new()
	legs_container.name = "Legs"
	pelvis.add_child(legs_container)
	var leg_l_nodes := _build_leg(legs_container, "LegL", Vector2(5.5, 0.0), -3, "left")
	leg_l_hip = leg_l_nodes[0]
	leg_l_knee = leg_l_nodes[1]
	var leg_r_nodes := _build_leg(legs_container, "LegR", Vector2(-5.5, 0.0), -2, "right")
	leg_r_hip = leg_r_nodes[0]
	leg_r_knee = leg_r_nodes[1]

	# ---- 躯干层（含背后枪盒、未来护甲/胸挂预留槽 + 弹簧衣摆/格裙） ----
	torso_pivot = Node2D.new()
	torso_pivot.name = "Torso"
	pelvis.add_child(torso_pivot)

	# 背后战术装备层挂在 Torso 下，确保冲刺前倾与团身翻滚时紧贴背部不悬空
	back_gear_pivot = Node2D.new()
	back_gear_pivot.name = "BackGear"
	back_gear_pivot.position = Vector2(8.0, -24.0)
	torso_pivot.add_child(back_gear_pivot)
	gun_case = _make_sprite("GunCase", "gun_case", -6, Vector2(0.0, -6.0), 64.0)
	gun_case.rotation = 0.06
	back_gear_pivot.add_child(gun_case)
	backpack_slot = Node2D.new()
	backpack_slot.name = "BackpackSlot"
	back_gear_pivot.add_child(backpack_slot)

	# 格裙下摆（仅在正/背面叠于下沿微摆，侧面隐藏防双裙边）
	skirt_pivot = Node2D.new()
	skirt_pivot.name = "SkirtHem"
	skirt_pivot.position = Vector2(0.0, -2.0)
	torso_pivot.add_child(skirt_pivot)
	var skirt_sp := _make_sprite("SkirtHemSprite", "skirt_hem", -1, Vector2(0.0, 3.0), 13.0)
	skirt_pivot.add_child(skirt_sp)

	# 躯干主体（无持枪双臂的藏蓝风衣 + 马甲 + 领结）
	torso_sprite = _make_sprite("TorsoSprite", "torso_front", 1, Vector2(0.0, -20.0), 46.0)
	torso_pivot.add_child(torso_sprite)

	# 预留护甲/胸挂外观挂点（供未来换装系统挂接可见护甲片）
	armor_slot = Node2D.new()
	armor_slot.name = "ArmorSlot"
	armor_slot.position = Vector2(0.0, -24.0)
	armor_slot.z_index = 2
	torso_pivot.add_child(armor_slot)

	# 次级物理：左右两节式风衣下摆（贴合风衣下沿自然垂出，放在躯干背后层 z=0 衔接无缝）
	var coat_l_nodes := _build_coat_flap(torso_pivot, "CoatTailL", Vector2(-8.0, -12.0), 0, false)
	coat_l_pivot = coat_l_nodes[0]
	coat_l_tip = coat_l_nodes[1]
	var coat_r_nodes := _build_coat_flap(torso_pivot, "CoatTailR", Vector2(8.0, -12.0), 0, true)
	coat_r_pivot = coat_r_nodes[0]
	coat_r_tip = coat_r_nodes[1]

	# ---- 收枪双臂（2段上臂+前臂，持枪时交给 WeaponRig2D 避免双臂重叠） ----
	var arm_l_nodes := _build_arm(torso_pivot, "ArmL", Vector2(10.0, SHOULDER_OFFSET_Y), 3, "left")
	arm_l_shoulder = arm_l_nodes[0]
	arm_l_elbow = arm_l_nodes[1]
	var arm_r_nodes := _build_arm(torso_pivot, "ArmR", Vector2(-10.0, SHOULDER_OFFSET_Y), 3, "right")
	arm_r_shoulder = arm_r_nodes[0]
	arm_r_elbow = arm_r_nodes[1]

	# ---- 颈部 + 头部 + 独立眨眼层 + 二节弹簧后发/侧发 ----
	neck_pivot = Node2D.new()
	neck_pivot.name = "Neck"
	neck_pivot.position = Vector2(0.0, NECK_OFFSET_Y)
	torso_pivot.add_child(neck_pivot)

	# 独立飘动后发（锚定在发尾底缘 y=-4、层级 z=4 在头部之后/躯干之前，自然垂出飘动不遮脸或头顶）
	hair_back_pivot = Node2D.new()
	hair_back_pivot.name = "HairBack"
	hair_back_pivot.position = Vector2(0.0, -4.0)
	neck_pivot.add_child(hair_back_pivot)
	var hair_root_sp := _make_sprite("HairBackRootSprite", "hair_back_root", 3, Vector2(0.0, 5.0), 18.0)
	hair_back_pivot.add_child(hair_root_sp)
	hair_back_tip = Node2D.new()
	hair_back_tip.name = "HairBackTip"
	hair_back_tip.position = Vector2(0.0, 9.0)
	hair_back_pivot.add_child(hair_back_tip)
	var hair_tip_sp := _make_sprite("HairBackTipSprite", "hair_back_tip", 3, Vector2(0.0, 4.0), 12.0)
	hair_back_tip.add_child(hair_tip_sp)

	head_pivot = Node2D.new()
	head_pivot.name = "Head"
	neck_pivot.add_child(head_pivot)
	# 头部略向下压 3px 与衣领重叠，大角度摆头绝不露颈缝
	head_sprite = _make_sprite("HeadSprite", "head_front", 5, Vector2(0.0, -14.0), 36.0)
	head_pivot.add_child(head_sprite)
	blink_sprite = _make_sprite("BlinkLayer", "head_front_blink", 6, Vector2(0.0, -14.0), 36.0)
	blink_sprite.visible = false
	head_pivot.add_child(blink_sprite)

	# 两侧短发发梢微动片（仅在正面微摆，侧面隐藏防脸颊重影）
	hair_side_l_pivot = Node2D.new()
	hair_side_l_pivot.name = "HairSideL"
	hair_side_l_pivot.position = Vector2(-10.0, -8.0)
	head_pivot.add_child(hair_side_l_pivot)
	hair_side_l_pivot.add_child(_make_sprite("HairSideLSprite", "hair_side", 4, Vector2(0.0, 5.0), 12.0))

	hair_side_r_pivot = Node2D.new()
	hair_side_r_pivot.name = "HairSideR"
	hair_side_r_pivot.position = Vector2(10.0, -8.0)
	head_pivot.add_child(hair_side_r_pivot)
	var hsr := _make_sprite("HairSideRSprite", "hair_side", 4, Vector2(0.0, 5.0), 12.0)
	hsr.flip_h = true
	hair_side_r_pivot.add_child(hsr)


func _build_leg(parent: Node2D, base_name: String, hip_pos: Vector2, z: int, side := "") -> Array[Node2D]:
	var hip := Node2D.new()
	hip.name = base_name + "Hip"
	hip.position = hip_pos
	parent.add_child(hip)
	# 大腿段顶端向上延出 3px 圆角包边，与髋部/格裙完全重叠不露缝
	var thigh := _make_sprite(base_name + "Thigh", "thigh", z, Vector2(0.0, THIGH_LEN * 0.5 - 1.0), THIGH_LEN + 5.0, side)
	hip.add_child(thigh)

	var knee := Node2D.new()
	knee.name = base_name + "Knee"
	knee.position = Vector2(0.0, THIGH_LEN - 2.0)
	hip.add_child(knee)
	# 小腿+球鞋段顶端向上重叠 3px 盖住膝盖圆角，屈膝绝不裂开
	var shin := _make_sprite(base_name + "Shin", "shin_boot", z, Vector2(0.0, SHIN_LEN * 0.5 - 1.0), SHIN_LEN + 4.0, side)
	knee.add_child(shin)
	return [hip, knee]


func _build_coat_flap(parent: Node2D, base_name: String, root_pos: Vector2,
		z: int, mirror: bool) -> Array[Node2D]:
	var root_n := Node2D.new()
	root_n.name = base_name
	root_n.position = root_pos
	parent.add_child(root_n)
	var sp1 := _make_sprite(base_name + "Root", "coat_flap_root", z, Vector2(0.0, 9.0), 21.0)
	sp1.flip_h = mirror
	root_n.add_child(sp1)

	var tip_n := Node2D.new()
	tip_n.name = base_name + "Tip"
	tip_n.position = Vector2(0.0, 14.0)
	root_n.add_child(tip_n)
	var sp2 := _make_sprite(base_name + "TipSprite", "coat_flap_tip", z, Vector2(0.0, 5.0), 13.0)
	sp2.flip_h = mirror
	tip_n.add_child(sp2)
	return [root_n, tip_n]


func _build_arm(parent: Node2D, base_name: String, shoulder_pos: Vector2, z: int, side := "") -> Array[Node2D]:
	var sh := Node2D.new()
	sh.name = base_name + "Shoulder"
	sh.position = shoulder_pos
	parent.add_child(sh)
	var up := _make_sprite(base_name + "Upper", "arm_upper", z, Vector2(0.0, UPPER_ARM_LEN * 0.5 - 1.0), UPPER_ARM_LEN + 4.0, side)
	sh.add_child(up)

	var el := Node2D.new()
	el.name = base_name + "Elbow"
	el.position = Vector2(0.0, UPPER_ARM_LEN - 2.0)
	sh.add_child(el)
	var fo := _make_sprite(base_name + "Forearm", "arm_forearm", z, Vector2(0.0, FOREARM_LEN * 0.5 - 1.0), FOREARM_LEN + 4.0, side)
	el.add_child(fo)
	return [sh, el]


## ---- 外部事件脉冲入口（开火后坐 / 受击 / 翻滚） ----

func trigger_recoil(strength: float, fire_dir: Vector2) -> void:
	_recoil_t = 0.14
	_recoil_strength = clampf(strength, 0.3, 2.2)
	_recoil_sign = -1.0 if fire_dir.x >= 0.0 else 1.0
	# 开火瞬间给头发与衣摆注入反向震动脉冲
	_hair_root_v += _recoil_sign * 4.8 * _recoil_strength
	_hair_tip_v += _recoil_sign * 7.2 * _recoil_strength
	_coat_l_v += _recoil_sign * 3.2 * _recoil_strength
	_coat_r_v += _recoil_sign * 3.2 * _recoil_strength
	_gear_bob_v -= 24.0 * _recoil_strength


func trigger_hurt(impact_dir := Vector2.LEFT) -> void:
	_hurt_t = 0.22
	_hurt_dir_sign = -1.0 if impact_dir.x >= 0.0 else 1.0
	_blink_t = 0.18
	_hair_root_v += _hurt_dir_sign * 7.5
	_hair_tip_v += _hurt_dir_sign * 10.0
	_coat_l_v += _hurt_dir_sign * 5.0
	_coat_r_v += _hurt_dir_sign * 5.0


func get_weapon_shoulder_offset() -> Vector2:
	# 翻滚中段直接以旋转胸口偏移为准，不再叠加平时站立偏移
	return _dynamic_dodge_weapon_offset if _dodging else _dynamic_shoulder_offset


func get_dodge_weapon_rotation() -> float:
	return _dynamic_dodge_weapon_rot if _dodging else 0.0


func get_dodge_phase() -> StringName:
	return _dodge_phase_name


func get_secondary_deflection() -> float:
	return absf(_hair_root_a) + absf(_hair_tip_a) + absf(_coat_l_a) + absf(_coat_r_a)


func get_knee_bend_max() -> float:
	if leg_l_knee == null or leg_r_knee == null:
		return 0.0
	return maxf(absf(leg_l_knee.rotation), absf(leg_r_knee.rotation))


## 抓取当前 SubViewport 像素帧，供 Phase 5 翻滚生成完全吻合当前团滚姿势的像素残影。
func capture_snapshot_texture() -> Texture2D:
	if viewport == null:
		return null
	var vtex := viewport.get_texture()
	if vtex == null:
		return null
	var img := vtex.get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## ---- 主每帧驱动：上下半身解耦 + 二段式步态 + 弹簧次级物理 + 翻滚演出 ----

func update_rig(velocity: Vector2, walk_speed: float, sprint_speed: float,
		aim_world: Vector2, aim_on: bool, is_armed: bool, is_holstered: bool,
		is_ads: bool, is_dodging: bool, dodge_progress: float, dodge_dir: Vector2,
		delta: float) -> void:
	if pelvis == null:
		return
	var dt := clampf(delta, 0.001, 0.05)
	_breath_time += dt
	armed = is_armed
	holstered = is_holstered
	ads = is_ads
	aiming = is_armed and not is_holstered and aim_on
	_dodging = is_dodging
	_dodge_u = clampf(dodge_progress, 0.0, 1.0)
	if dodge_dir.length_squared() > 0.001:
		_dodge_dir = dodge_dir.normalized()

	var speed := velocity.length()
	var moving := speed > 10.0 and not is_dodging
	var sprinting := moving and speed > walk_speed * 1.18

	# 1) 上下半身朝向解耦：
	#    上半身优先跟随鼠标瞄准方向；下半身按移动矢量决定（静止时自然对齐上半身）。
	var aim_vec := aim_world - global_position
	var has_aim := aim_on and aim_vec.length_squared() > 16.0
	if is_dodging:
		lower_direction = _vec_to_dir(_dodge_dir)
		upper_direction = lower_direction
	else:
		if has_aim and (aiming or not moving):
			upper_direction = _vec_to_dir(aim_vec)
		elif moving:
			upper_direction = _vec_to_dir(velocity)
		if moving:
			lower_direction = _vec_to_dir(velocity)
		else:
			lower_direction = upper_direction

	# 2) 分类下身步态模式（idle / walk / run / strafe / backpedal / dodge）
	#    瞄准持枪时优先判定移动与瞄准夹角：即使按住 Shift 倒退/侧移，下身也必须保持面向瞄准侧，
	#    彻底杜绝「上身朝右瞄、下身朝左跑导致膝盖朝前反折」的解剖学穿帮。
	if is_dodging:
		locomotion_mode = &"dodge"
	elif not moving:
		locomotion_mode = &"idle"
	elif has_aim and aiming:
		var move_n := velocity.normalized()
		var aim_n := aim_vec.normalized()
		var align := move_n.dot(aim_n)
		if align < -0.45:
			locomotion_mode = &"backpedal"
		elif absf(align) < 0.45:
			locomotion_mode = &"strafe"
		else:
			locomotion_mode = &"run" if sprinting else &"walk"
	elif sprinting:
		locomotion_mode = &"run"
	else:
		locomotion_mode = &"walk"

	# 3) 计算加速度与急停刹车惯性
	var accel := (velocity - _prev_vel) / dt
	var prev_speed := _prev_vel.length()
	if prev_speed > walk_speed * 0.65 and speed < prev_speed * 0.55 and not is_dodging:
		var stop_dir := 1.0 if _prev_vel.x >= 0.0 else -1.0
		_brake_vel += stop_dir * clampf(prev_speed / maxf(sprint_speed, 1.0), 0.4, 1.4) * 3.8
	_prev_vel = velocity
	# 急停惯性阻尼弹簧
	var b_acc := -62.0 * _brake_impulse - 11.0 * _brake_vel
	_brake_vel += b_acc * dt
	_brake_impulse = clampf(_brake_impulse + _brake_vel * dt, -0.22, 0.22)

	# 4) 衰减后坐与受击计时器，更新左右转身柔化脉冲与眨眼状态
	if _prev_upper_dir != -1 and _prev_upper_dir != upper_direction and not is_dodging:
		var lr_flip := (_prev_upper_dir == 2 and upper_direction == 3) or (_prev_upper_dir == 3 and upper_direction == 2)
		_turn_squash = 0.18 if lr_flip else 0.09
		var turn_kick := 1.0 if upper_direction == 3 else -1.0
		_hair_root_v -= turn_kick * (4.2 if lr_flip else 2.2)
		_hair_tip_v -= turn_kick * (5.6 if lr_flip else 3.0)
		_coat_l_v -= turn_kick * (2.8 if lr_flip else 1.5)
		_coat_r_v -= turn_kick * (2.8 if lr_flip else 1.5)
	_prev_upper_dir = upper_direction
	if _turn_squash > 0.0:
		_turn_squash = maxf(_turn_squash - dt * 1.45, 0.0)
	if _recoil_t > 0.0:
		_recoil_t = maxf(_recoil_t - dt, 0.0)
	if _hurt_t > 0.0:
		_hurt_t = maxf(_hurt_t - dt, 0.0)
	_step_blink(dt)

	# 5) 刷新四向贴图与前后遮挡层级
	_apply_facing_layers()

	# 6) 驱动步态或翻滚骨骼姿态
	if is_dodging:
		_apply_dodge_pose(_dodge_u, dt)
	else:
		_dodge_phase_name = &"none"
		_dynamic_dodge_weapon_offset = Vector2.ZERO
		_dynamic_dodge_weapon_rot = 0.0
		_apply_locomotion_pose(velocity, speed, walk_speed, sprint_speed, aim_vec, has_aim, dt)

	# 7) 驱动次级物理弹簧（后发发梢、风衣左右衣摆、格裙、枪盒颠簸）
	_step_secondary_springs(velocity, accel, is_dodging, dt)

	# 8) 同步动态肩部世界偏移，供 WeaponRig2D 精确附着（ADS 前倾抵肩时避免前推抵消收枪回拉）
	var pelvis_delta := pelvis.position - Vector2(0.0, -PELVIS_HEIGHT)
	var lean_dx := sin(torso_pivot.rotation) * (-SHOULDER_OFFSET_Y)
	var lean_x_mul := 0.20 if ads else 0.65
	_dynamic_shoulder_offset = Vector2(pelvis_delta.x + lean_dx * lean_x_mul, pelvis_delta.y)


func _step_blink(dt: float) -> void:
	if _blink_t > 0.0:
		_blink_t = maxf(_blink_t - dt, 0.0)
	else:
		_blink_cd -= dt
		if _blink_cd <= 0.0:
			_blink_t = 0.11
			_blink_cd = randf_range(2.4, 5.2)
	var show_blink := (_blink_t > 0.0 or _dodging or _hurt_t > 0.06) and upper_direction != 1
	if blink_sprite != null:
		blink_sprite.visible = show_blink and blink_sprite.texture != null


func _apply_facing_layers() -> void:
	var side_u := upper_direction == 2 or upper_direction == 3
	var flip_u := upper_direction == 3  # 左侧贴图水平翻转即为右侧

	# 头部朝向与眨眼层同步
	var h_key := "head_front"
	var b_key := "head_front_blink"
	match upper_direction:
		1:
			h_key = "head_back"
			b_key = ""
		2, 3:
			h_key = "head_left"
			b_key = "head_left_blink"
	if head_sprite != null and _textures.has(h_key):
		head_sprite.texture = _textures[h_key]
		head_sprite.flip_h = flip_u
	if blink_sprite != null:
		if b_key != "" and _textures.has(b_key):
			blink_sprite.texture = _textures[b_key]
			blink_sprite.flip_h = flip_u
		else:
			blink_sprite.visible = false

	# 躯干朝向
	var t_key := "torso_front"
	match upper_direction:
		1: t_key = "torso_back"
		2, 3: t_key = "torso_left"
	if torso_sprite != null and _textures.has(t_key):
		torso_sprite.texture = _textures[t_key]
		torso_sprite.flip_h = flip_u

	# 背后枪盒随朝向自动切换躯干前后遮挡与横向位置
	if gun_case != null and back_gear_pivot != null:
		match upper_direction:
			0:
				gun_case.z_index = -6
				back_gear_pivot.position.x = 9.0
				gun_case.rotation = 0.08
				gun_case.flip_h = false
			1:
				gun_case.z_index = 7
				back_gear_pivot.position.x = 7.0
				gun_case.rotation = 0.06
				gun_case.flip_h = false
			2:
				gun_case.z_index = -2
				back_gear_pivot.position.x = 11.0
				gun_case.rotation = 0.05
				gun_case.flip_h = false
			3:
				gun_case.z_index = -2
				back_gear_pivot.position.x = -11.0
				gun_case.rotation = -0.05
				gun_case.flip_h = true

	# 后发与侧发层级：后发始终在头(z=5)之后、躯干(z=1)之前/之上自然垂出发尾
	if hair_back_pivot != null:
		var hb_z := 4 if upper_direction == 1 else -1
		for sp in hair_back_pivot.find_children("*", "Sprite2D", true, false):
			(sp as Sprite2D).z_index = hb_z
			(sp as Sprite2D).flip_h = flip_u
		hair_back_pivot.position.x = 3.0 if upper_direction == 2 else (-3.0 if upper_direction == 3 else 0.0)
	if hair_side_l_pivot != null and hair_side_r_pivot != null:
		hair_side_l_pivot.visible = upper_direction == 0
		hair_side_r_pivot.visible = upper_direction == 0
	if skirt_pivot != null:
		skirt_pivot.visible = not side_u

	# 风衣下摆按正/背/侧调整宽度与遮挡，紧贴风衣下沿无悬空
	if coat_l_pivot != null and coat_r_pivot != null:
		if side_u:
			var back_sign := 1.0 if upper_direction == 2 else -1.0
			coat_l_pivot.position.x = back_sign * 4.5
			coat_r_pivot.visible = false
			coat_l_pivot.visible = true
		else:
			coat_l_pivot.position.x = -8.0
			coat_r_pivot.position.x = 8.0
			coat_l_pivot.visible = true
			coat_r_pivot.visible = true

	# 双腿站位间距、解剖学左右一致性（0正：右腿在画面左/左腿在画面右；1背：左腿在画面左/右腿在画面右；
	# 2朝左：左腿近景/右腿远景；3朝右：右腿近景/左腿远景）；倒退走与侧步持枪时腿部朝向对齐上身瞄准方向，
	# 杜绝腰部 90°/180° 扭断与反关节屈膝。
	var lock_leg_to_upper := (locomotion_mode == &"backpedal" or locomotion_mode == &"strafe") and not _dodging
	var visual_leg_dir := upper_direction if lock_leg_to_upper else lower_direction
	var side_l := visual_leg_dir == 2 or visual_leg_dir == 3
	var leg_flip := visual_leg_dir == 3
	if leg_l_hip != null and leg_r_hip != null:
		var far_tint := Color(0.74, 0.78, 0.86, 1.0)
		var near_tint := Color.WHITE
		var ll_z := -3
		var lr_z := -3
		var ll_tint := near_tint
		var lr_tint := near_tint
		var strafe_front_back := locomotion_mode == &"strafe" and (upper_direction == 0 or upper_direction == 1)
		match visual_leg_dir:
			0:
				# 朝下(正)：自然并拢的站姿间距（±4.3px），告别外八宽站
				leg_r_hip.position.x = -4.3
				leg_l_hip.position.x = 4.3
			1:
				# 朝上(背)：解剖学左腿在画面左(-4.3)，右腿在画面右(+4.3)
				leg_l_hip.position.x = -4.3
				leg_r_hip.position.x = 4.3
			2:
				# 朝左：左腿近景置前、右腿远景压暗置后
				leg_l_hip.position.x = 2.6 if strafe_front_back else 1.5
				leg_r_hip.position.x = -2.6 if strafe_front_back else -2.1
				ll_z = -2
				lr_z = -4
				lr_tint = far_tint
			3:
				# 朝右：右腿近景置前、左腿远景压暗置后
				leg_r_hip.position.x = -2.6 if strafe_front_back else -1.5
				leg_l_hip.position.x = 2.6 if strafe_front_back else 2.1
				lr_z = -2
				ll_z = -4
				ll_tint = far_tint
		for sp in leg_l_hip.find_children("*", "Sprite2D", true, false):
			var s2d := sp as Sprite2D
			s2d.flip_h = leg_flip if side_l else (leg_l_hip.position.x > 0.0)
			s2d.z_index = ll_z
			s2d.modulate = ll_tint
		for sp in leg_r_hip.find_children("*", "Sprite2D", true, false):
			var s2d := sp as Sprite2D
			s2d.flip_h = leg_flip if side_l else (leg_r_hip.position.x > 0.0)
			s2d.z_index = lr_z
			s2d.modulate = lr_tint

	# 收枪手臂显隐与解剖学左右/远近层级（与双腿 360° 转向完全同侧一致）
	var show_holster_arms := (not armed) or holstered or _dodging
	if arm_l_shoulder != null and arm_r_shoulder != null:
		arm_l_shoulder.visible = show_holster_arms
		arm_r_shoulder.visible = show_holster_arms
		var arm_far_tint := Color(0.74, 0.78, 0.86, 1.0)
		var l_z := 4
		var r_z := 4
		var l_tint := Color.WHITE
		var r_tint := Color.WHITE
		match upper_direction:
			0:
				# 朝下(正)：右臂在画面左(-10)，左臂在画面右(+10)
				arm_r_shoulder.position.x = -10.0
				arm_l_shoulder.position.x = 10.0
			1:
				# 朝上(背)：左臂在画面左(-10)，右臂在画面右(+10)
				arm_l_shoulder.position.x = -10.0
				arm_r_shoulder.position.x = 10.0
				l_z = -2
				r_z = -2
			2:
				# 朝左：左臂近景置前、右臂远景压暗置后
				arm_l_shoulder.position.x = 2.0
				arm_r_shoulder.position.x = -3.0
				l_z = 4
				r_z = -3
				r_tint = arm_far_tint
			3:
				# 朝右：右臂近景置前、左臂远景压暗置后
				arm_r_shoulder.position.x = -2.0
				arm_l_shoulder.position.x = 3.0
				r_z = 4
				l_z = -3
				l_tint = arm_far_tint
		for sp in arm_l_shoulder.find_children("*", "Sprite2D", true, false):
			var s2d := sp as Sprite2D
			s2d.z_index = l_z
			s2d.modulate = l_tint
			s2d.flip_h = flip_u
		for sp in arm_r_shoulder.find_children("*", "Sprite2D", true, false):
			var s2d := sp as Sprite2D
			s2d.z_index = r_z
			s2d.modulate = r_tint
			s2d.flip_h = flip_u
	_apply_extra_component_visibility()


func _apply_locomotion_pose(velocity: Vector2, speed: float, walk_speed: float,
		sprint_speed: float, aim_vec: Vector2, has_aim: bool, dt: float) -> void:
	pelvis.rotation = lerp_angle(pelvis.rotation, 0.0, clampf(dt * 18.0, 0.0, 1.0))
	pelvis.scale = pelvis.scale.lerp(Vector2.ONE, clampf(dt * 16.0, 0.0, 1.0))

	var breath := sin(_breath_time * 2.55)
	var is_moving := locomotion_mode != &"idle"
	var is_run := locomotion_mode == &"run"
	var is_backpedal := locomotion_mode == &"backpedal"
	var is_strafe := locomotion_mode == &"strafe"

	var target_bob := breath * 0.85
	var target_pelvis_x := 0.0

	if is_moving:
		var base_ref := sprint_speed if is_run else walk_speed
		var speed_ratio := clampf(speed / maxf(base_ref, 1.0), 0.45, 1.85)
		var freq := (13.8 if is_run else (9.6 if not is_strafe else 10.6)) * speed_ratio
		var phase_dir := -1.0 if is_backpedal else 1.0
		_gait_phase = wrapf(_gait_phase + dt * freq * phase_dir, 0.0, TAU)
		var s := sin(_gait_phase)
		# 踩实过零检测：触发脚步轻尘信号
		if (_prev_sin_phase < 0.0 and s >= 0.0) or (_prev_sin_phase > 0.0 and s <= 0.0):
			var foot_side := -5.0 if s >= 0.0 else 5.0
			footstep_planted.emit(Vector2(foot_side, 0.0), is_run)
		_prev_sin_phase = s

		var lock_leg_to_upper := is_backpedal or is_strafe
		var visual_leg_dir := upper_direction if lock_leg_to_upper else lower_direction
		var side_lower := visual_leg_dir == 2 or visual_leg_dir == 3
		var face_sign := -1.0 if visual_leg_dir == 2 else 1.0
		var swing_amp := 0.66 if is_run else (0.34 if is_strafe else (0.36 if is_backpedal else 0.50))
		var knee_scale := 1.0 if is_run else (0.52 if is_strafe else (0.68 if is_backpedal else 0.80))
		var knee_base_y := THIGH_LEN - 2.0

		if side_lower:
			# 解剖学二段式屈膝步态（theta = 左腿相位，theta + PI = 右腿相位）：
			# - 无论前进(phase_dir=+1)还是倒退(phase_dir=-1)，cos(th) > 0 恒为腾空摆动相（深度后屈膝）；
			# - 支撑腿在重心正下方保持有力支撑，蹬离末段（pow 1.45）再迅捷后勾脚跟；
			# - 按双腿实时垂向投影 reach 自动计算贴地骨盆下沉量，走路全程踩实零漂浮，冲刺带利落弹跳。
			var th_l := _gait_phase
			var th_r := wrapf(_gait_phase + PI, 0.0, TAU)
			var l_fwd := sin(th_l) * swing_amp
			var r_fwd := sin(th_r) * swing_amp
			# Godot 2D：+rotation 顺时针（向 -X 摆），因此朝右(+1)前迈为 -fwd，朝左(-1)前迈为 +fwd
			var l_thigh := -l_fwd * face_sign
			var r_thigh := -r_fwd * face_sign

			var l_tuck := clampf(cos(th_l), 0.0, 1.0)
			var r_tuck := clampf(cos(th_r), 0.0, 1.0)
			var l_kick := pow(clampf(-sin(th_l) * phase_dir, 0.0, 1.0), 1.45)
			var r_kick := pow(clampf(-sin(th_r) * phase_dir, 0.0, 1.0), 1.45)
			var l_flex := clampf(0.10 + l_tuck * 0.96 + l_kick * 0.68 + clampf(sin(th_l) * phase_dir, 0.0, 1.0) * 0.16, 0.08, 1.40) * knee_scale
			var r_flex := clampf(0.10 + r_tuck * 0.96 + r_kick * 0.68 + clampf(sin(th_r) * phase_dir, 0.0, 1.0) * 0.16, 0.08, 1.40) * knee_scale
			# 膝盖严格向身体后方弯曲（朝右 +1 顺时针，朝左 -1 逆时针）
			var knee_back := face_sign
			leg_l_hip.rotation = lerp_angle(leg_l_hip.rotation, l_thigh, clampf(dt * 24.0, 0.0, 1.0))
			leg_r_hip.rotation = lerp_angle(leg_r_hip.rotation, r_thigh, clampf(dt * 24.0, 0.0, 1.0))
			leg_l_knee.rotation = lerp_angle(leg_l_knee.rotation, l_flex * knee_back, clampf(dt * 24.0, 0.0, 1.0))
			leg_r_knee.rotation = lerp_angle(leg_r_knee.rotation, r_flex * knee_back, clampf(dt * 24.0, 0.0, 1.0))
			leg_l_knee.position.y = lerpf(leg_l_knee.position.y, knee_base_y, clampf(dt * 20.0, 0.0, 1.0))
			leg_r_knee.position.y = lerpf(leg_r_knee.position.y, knee_base_y, clampf(dt * 20.0, 0.0, 1.0))
			leg_l_hip.scale = Vector2.ONE
			leg_r_hip.scale = Vector2.ONE
			for pair in [[leg_l_hip, "LegLThigh"], [leg_r_hip, "LegRThigh"], [leg_l_knee, "LegLShin"], [leg_r_knee, "LegRShin"]]:
				var sp := (pair[0] as Node2D).get_child(0) as Sprite2D
				var bs: Vector2 = _part_scale_base.get(String(pair[1]), Vector2.ONE)
				if sp != null:
					sp.scale = sp.scale.lerp(bs, clampf(dt * 22.0, 0.0, 1.0))
			# 由支撑腿实时几何投影计算精准贴地高度；冲刺经过腾空相时叠加轻盈 2.5px 蹬跃
			var l_reach := (THIGH_LEN - 2.0) * cos(leg_l_hip.rotation) + SHIN_LEN * cos(leg_l_hip.rotation + leg_l_knee.rotation)
			var r_reach := (THIGH_LEN - 2.0) * cos(leg_r_hip.rotation) + SHIN_LEN * cos(leg_r_hip.rotation + leg_r_knee.rotation)
			var max_reach := maxf(l_reach, r_reach)
			var ground_drop := clampf((PELVIS_HEIGHT - 1.0) - max_reach, -1.5, 9.0)
			var run_flight := -2.6 * (1.0 - absf(s)) if is_run else 0.0
			target_bob = ground_drop + run_flight
		else:
			# 正面/背面自然直行透视步态：双腿严格沿纵轴直迈（零外八撇腿、零鸭子摇摆），
			# 借由垂直提膝、纵向透视缩短、前亮后暗纵深着色与前后 z_index 交替呈现利落的向镜/背镜跑走感。
			var l_fwd := sin(_gait_phase)
			var r_fwd := -l_fwd
			var l_lift := clampf(l_fwd, 0.0, 1.0)
			var r_lift := clampf(r_fwd, 0.0, 1.0)
			var l_back := clampf(-l_fwd, 0.0, 1.0)
			var r_back := clampf(-r_fwd, 0.0, 1.0)
			var knee_lift_px := 8.6 if is_run else 5.4
			var l_shin_sp := leg_l_knee.get_child(0) as Sprite2D
			var r_shin_sp := leg_r_knee.get_child(0) as Sprite2D
			var l_thigh_sp := leg_l_hip.get_child(0) as Sprite2D
			var r_thigh_sp := leg_r_hip.get_child(0) as Sprite2D
			var l_base_ts: Vector2 = _part_scale_base.get("LegLThigh", Vector2.ONE)
			var r_base_ts: Vector2 = _part_scale_base.get("LegRThigh", Vector2.ONE)
			var l_base_ss: Vector2 = _part_scale_base.get("LegLShin", Vector2.ONE)
			var r_base_ss: Vector2 = _part_scale_base.get("LegRShin", Vector2.ONE)

			# 髋与膝保持近乎垂直直迈（彻底消除鸭子外八撇腿）
			leg_l_hip.rotation = lerp_angle(leg_l_hip.rotation, 0.0, clampf(dt * 24.0, 0.0, 1.0))
			leg_r_hip.rotation = lerp_angle(leg_r_hip.rotation, 0.0, clampf(dt * 24.0, 0.0, 1.0))
			leg_l_knee.rotation = lerp_angle(leg_l_knee.rotation, 0.0, clampf(dt * 24.0, 0.0, 1.0))
			leg_r_knee.rotation = lerp_angle(leg_r_knee.rotation, 0.0, clampf(dt * 24.0, 0.0, 1.0))
			leg_l_knee.position.y = lerpf(leg_l_knee.position.y, knee_base_y - l_lift * knee_lift_px, clampf(dt * 24.0, 0.0, 1.0))
			leg_r_knee.position.y = lerpf(leg_r_knee.position.y, knee_base_y - r_lift * knee_lift_px, clampf(dt * 24.0, 0.0, 1.0))

			# 前迈腿纵向透视略缩并微提亮置前，后蹬腿微压暗置后；正/背视角鞋尖水平收敛至 0.78× 消除横撇鸭脚感
			var front_foot_sx := 0.78
			var thigh_shrink := 0.26 if is_run else 0.16
			var shin_shrink := 0.14 if is_run else 0.08
			var l_depth_scale := 1.0 - l_back * 0.05
			var r_depth_scale := 1.0 - r_back * 0.05
			if l_thigh_sp != null:
				l_thigh_sp.scale = Vector2(l_base_ts.x * l_depth_scale, l_base_ts.y * (1.0 - l_lift * thigh_shrink) * l_depth_scale)
			if r_thigh_sp != null:
				r_thigh_sp.scale = Vector2(r_base_ts.x * r_depth_scale, r_base_ts.y * (1.0 - r_lift * thigh_shrink) * r_depth_scale)
			if l_shin_sp != null:
				l_shin_sp.scale = Vector2(l_base_ss.x * front_foot_sx * l_depth_scale, l_base_ss.y * (1.0 - l_lift * shin_shrink) * l_depth_scale)
			if r_shin_sp != null:
				r_shin_sp.scale = Vector2(r_base_ss.x * front_foot_sx * r_depth_scale, r_base_ss.y * (1.0 - r_lift * shin_shrink) * r_depth_scale)

			var trail_tint := Color(0.78, 0.82, 0.90, 1.0)
			var l_tint := Color.WHITE.lerp(trail_tint, l_back * 0.85)
			var r_tint := Color.WHITE.lerp(trail_tint, r_back * 0.85)
			var l_z_fb := -2 if l_fwd >= 0.0 else -4
			var r_z_fb := -2 if r_fwd >= 0.0 else -4
			for sp in leg_l_hip.find_children("*", "Sprite2D", true, false):
				var s2d := sp as Sprite2D
				s2d.modulate = l_tint
				s2d.z_index = l_z_fb
			for sp in leg_r_hip.find_children("*", "Sprite2D", true, false):
				var s2d := sp as Sprite2D
				s2d.modulate = r_tint
				s2d.z_index = r_z_fb

			leg_l_hip.scale = Vector2.ONE
			leg_r_hip.scale = Vector2.ONE
			target_bob = absf(s) * (2.6 if is_run else 1.5) - (1.2 if is_run else 0.6)
			target_pelvis_x = s * (0.45 if is_run else 0.25)

		# 收枪双臂二段式严格反向摆动（左手配右腿、右手配左腿，彻底杜绝顺拐；正/背面贴身前后摆，杜绝鸡翅外展）
		var arm_face := -1.0 if upper_direction == 2 else 1.0
		var arm_amp := 0.68 if is_run else 0.42
		var arm_l_fwd := -sin(_gait_phase) * arm_amp
		var arm_r_fwd := sin(_gait_phase) * arm_amp
		var elbow_fwd_sign := -arm_face  # 朝右(+1)肘向前弯为逆时针(-)，朝左(-1)为顺时针(+)
		var side_u := upper_direction == 2 or upper_direction == 3
		if side_u:
			arm_l_shoulder.rotation = lerp_angle(arm_l_shoulder.rotation, -arm_l_fwd * arm_face, clampf(dt * 20.0, 0.0, 1.0))
			arm_r_shoulder.rotation = lerp_angle(arm_r_shoulder.rotation, -arm_r_fwd * arm_face, clampf(dt * 20.0, 0.0, 1.0))
			var el_l := (0.38 if is_run else 0.22) + clampf(arm_l_fwd, -0.1, 1.0) * (0.95 if is_run else 0.55)
			var el_r := (0.38 if is_run else 0.22) + clampf(arm_r_fwd, -0.1, 1.0) * (0.95 if is_run else 0.55)
			arm_l_elbow.rotation = lerp_angle(arm_l_elbow.rotation, el_l * elbow_fwd_sign, clampf(dt * 20.0, 0.0, 1.0))
			arm_r_elbow.rotation = lerp_angle(arm_r_elbow.rotation, el_r * elbow_fwd_sign, clampf(dt * 20.0, 0.0, 1.0))
			arm_l_elbow.position.y = lerpf(arm_l_elbow.position.y, UPPER_ARM_LEN - 2.0, clampf(dt * 20.0, 0.0, 1.0))
			arm_r_elbow.position.y = lerpf(arm_r_elbow.position.y, UPPER_ARM_LEN - 2.0, clampf(dt * 20.0, 0.0, 1.0))
			arm_l_shoulder.scale = arm_l_shoulder.scale.lerp(Vector2.ONE, clampf(dt * 20.0, 0.0, 1.0))
			arm_r_shoulder.scale = arm_r_shoulder.scale.lerp(Vector2.ONE, clampf(dt * 20.0, 0.0, 1.0))
		else:
			# 正/背面自然贴身前后摆臂：肩部紧贴躯干不外甩，靠前摆轻微提肘+纵向透视缩放表现前后摆动
			var al_x := -1.0 if arm_l_shoulder.position.x < 0.0 else 1.0
			var ar_x := -1.0 if arm_r_shoulder.position.x < 0.0 else 1.0
			var al_fwd := clampf(-s, 0.0, 1.0)
			var ar_fwd := clampf(s, 0.0, 1.0)
			var al_back := clampf(s, 0.0, 1.0)
			var ar_back := clampf(-s, 0.0, 1.0)
			var pump_px := 4.2 if is_run else 2.2
			arm_l_shoulder.rotation = lerp_angle(arm_l_shoulder.rotation, -al_x * (0.04 + al_back * 0.04), clampf(dt * 18.0, 0.0, 1.0))
			arm_r_shoulder.rotation = lerp_angle(arm_r_shoulder.rotation, -ar_x * (0.04 + ar_back * 0.04), clampf(dt * 18.0, 0.0, 1.0))
			arm_l_elbow.rotation = lerp_angle(arm_l_elbow.rotation, al_x * (0.10 + al_fwd * (0.20 if is_run else 0.10)), clampf(dt * 18.0, 0.0, 1.0))
			arm_r_elbow.rotation = lerp_angle(arm_r_elbow.rotation, ar_x * (0.10 + ar_fwd * (0.20 if is_run else 0.10)), clampf(dt * 18.0, 0.0, 1.0))
			arm_l_elbow.position.y = lerpf(arm_l_elbow.position.y, (UPPER_ARM_LEN - 2.0) - al_fwd * pump_px, clampf(dt * 20.0, 0.0, 1.0))
			arm_r_elbow.position.y = lerpf(arm_r_elbow.position.y, (UPPER_ARM_LEN - 2.0) - ar_fwd * pump_px, clampf(dt * 20.0, 0.0, 1.0))
			arm_l_shoulder.scale = Vector2(1.0, 1.0 - al_fwd * (0.16 if is_run else 0.08))
			arm_r_shoulder.scale = Vector2(1.0, 1.0 - ar_fwd * (0.16 if is_run else 0.08))
	else:
		# 站立待机：双脚稳踩地面、微呼吸起伏；急停瞬间附加短暂单膝前撑缓冲（消除骤停僵直）
		var brake_mag := absf(_brake_impulse)
		var side_idle_leg := lower_direction == 2 or lower_direction == 3
		if side_idle_leg and brake_mag > 0.02:
			var b_sign := 1.0 if _brake_impulse >= 0.0 else -1.0
			var knee_b := -1.0 if lower_direction == 2 else 1.0
			leg_l_hip.rotation = lerp_angle(leg_l_hip.rotation, -b_sign * brake_mag * 1.45, clampf(dt * 22.0, 0.0, 1.0))
			leg_r_hip.rotation = lerp_angle(leg_r_hip.rotation, b_sign * brake_mag * 0.95, clampf(dt * 22.0, 0.0, 1.0))
			leg_l_knee.rotation = lerp_angle(leg_l_knee.rotation, knee_b * brake_mag * 1.85, clampf(dt * 22.0, 0.0, 1.0))
			leg_r_knee.rotation = lerp_angle(leg_r_knee.rotation, knee_b * brake_mag * 1.35, clampf(dt * 22.0, 0.0, 1.0))
			target_bob += clampf(brake_mag * 18.0, 0.0, 4.5)
		else:
			leg_l_hip.rotation = lerp_angle(leg_l_hip.rotation, 0.0, clampf(dt * 14.0, 0.0, 1.0))
			leg_r_hip.rotation = lerp_angle(leg_r_hip.rotation, 0.0, clampf(dt * 14.0, 0.0, 1.0))
			leg_l_knee.rotation = lerp_angle(leg_l_knee.rotation, 0.0, clampf(dt * 14.0, 0.0, 1.0))
			leg_r_knee.rotation = lerp_angle(leg_r_knee.rotation, 0.0, clampf(dt * 14.0, 0.0, 1.0))
		leg_l_knee.position.y = lerpf(leg_l_knee.position.y, THIGH_LEN - 2.0, clampf(dt * 16.0, 0.0, 1.0))
		leg_r_knee.position.y = lerpf(leg_r_knee.position.y, THIGH_LEN - 2.0, clampf(dt * 16.0, 0.0, 1.0))
		leg_l_hip.scale = leg_l_hip.scale.lerp(Vector2.ONE, clampf(dt * 14.0, 0.0, 1.0))
		leg_r_hip.scale = leg_r_hip.scale.lerp(Vector2.ONE, clampf(dt * 14.0, 0.0, 1.0))
		var idle_shin_sx := 1.0 if side_idle_leg else 0.78
		for pair in [[leg_l_hip, "LegLThigh", 1.0], [leg_r_hip, "LegRThigh", 1.0], [leg_l_knee, "LegLShin", idle_shin_sx], [leg_r_knee, "LegRShin", idle_shin_sx]]:
			var sp := (pair[0] as Node2D).get_child(0) as Sprite2D
			var bs: Vector2 = _part_scale_base.get(String(pair[1]), Vector2.ONE)
			var sx_mul := float(pair[2])
			if sp != null:
				sp.scale = sp.scale.lerp(Vector2(bs.x * sx_mul, bs.y), clampf(dt * 14.0, 0.0, 1.0))
		arm_l_elbow.position.y = lerpf(arm_l_elbow.position.y, UPPER_ARM_LEN - 2.0, clampf(dt * 14.0, 0.0, 1.0))
		arm_r_elbow.position.y = lerpf(arm_r_elbow.position.y, UPPER_ARM_LEN - 2.0, clampf(dt * 14.0, 0.0, 1.0))
		arm_l_shoulder.scale = arm_l_shoulder.scale.lerp(Vector2.ONE, clampf(dt * 14.0, 0.0, 1.0))
		arm_r_shoulder.scale = arm_r_shoulder.scale.lerp(Vector2.ONE, clampf(dt * 14.0, 0.0, 1.0))
		var side_u_idle := upper_direction == 2 or upper_direction == 3
		if side_u_idle:
			var arm_face_i := -1.0 if upper_direction == 2 else 1.0
			var elbow_fwd_i := -arm_face_i
			arm_l_shoulder.rotation = lerp_angle(arm_l_shoulder.rotation, 0.04 * arm_face_i + breath * 0.02, clampf(dt * 10.0, 0.0, 1.0))
			arm_r_shoulder.rotation = lerp_angle(arm_r_shoulder.rotation, -0.04 * arm_face_i - breath * 0.02, clampf(dt * 10.0, 0.0, 1.0))
			arm_l_elbow.rotation = lerp_angle(arm_l_elbow.rotation, elbow_fwd_i * 0.18, clampf(dt * 10.0, 0.0, 1.0))
			arm_r_elbow.rotation = lerp_angle(arm_r_elbow.rotation, elbow_fwd_i * 0.18, clampf(dt * 10.0, 0.0, 1.0))
		else:
			var al_xi := -1.0 if arm_l_shoulder.position.x < 0.0 else 1.0
			var ar_xi := -1.0 if arm_r_shoulder.position.x < 0.0 else 1.0
			arm_l_shoulder.rotation = lerp_angle(arm_l_shoulder.rotation, -al_xi * (0.04 + breath * 0.02), clampf(dt * 10.0, 0.0, 1.0))
			arm_r_shoulder.rotation = lerp_angle(arm_r_shoulder.rotation, -ar_xi * (0.04 + breath * 0.02), clampf(dt * 10.0, 0.0, 1.0))
			arm_l_elbow.rotation = lerp_angle(arm_l_elbow.rotation, al_xi * 0.08, clampf(dt * 10.0, 0.0, 1.0))
			arm_r_elbow.rotation = lerp_angle(arm_r_elbow.rotation, ar_xi * 0.08, clampf(dt * 10.0, 0.0, 1.0))

	_hip_bob = lerpf(_hip_bob, target_bob, clampf(dt * 18.0, 0.0, 1.0))
	pelvis.position = Vector2(
		lerpf(pelvis.position.x, target_pelvis_x, clampf(dt * 14.0, 0.0, 1.0)),
		-PELVIS_HEIGHT + _hip_bob
	)

	# 躯干前倾（冲刺前倾 / 倒退微后仰 / 急停惯性 / 开火后坐 / 受击后仰）
	var lean_target := 0.0
	if is_run:
		lean_target = (0.17 if velocity.x >= 0.0 else -0.17) if absf(velocity.x) > 20.0 else 0.06
	elif is_backpedal:
		lean_target = (-0.08 if velocity.x >= 0.0 else 0.08)
	elif is_moving:
		lean_target = (0.06 if velocity.x >= 0.0 else -0.06) if absf(velocity.x) > 20.0 else 0.0
	elif ads:
		# 右键瞄准抵肩轻微前倾稳定重心
		lean_target = (0.05 if aim_vec.x >= 0.0 else -0.05) if has_aim else 0.0

	var recoil_kick := (_recoil_t / 0.14) * _recoil_strength * 0.11 * _recoil_sign if _recoil_t > 0.0 else 0.0
	var hurt_kick := sin((_hurt_t / 0.22) * PI) * 0.26 * _hurt_dir_sign if _hurt_t > 0.0 else 0.0
	_torso_lean = lerpf(_torso_lean, lean_target, clampf(dt * 12.0, 0.0, 1.0))
	torso_pivot.rotation = _torso_lean + _brake_impulse * 0.55 + recoil_kick + hurt_kick

	# 胸腔柔和呼吸起伏 + 左右转身短暂透视挤压（消除镜像翻转突兀感）
	var base_ts: Vector2 = _part_scale_base.get("TorsoSprite", Vector2.ONE)
	var turn_sx := 1.0 - _turn_squash * 0.42
	torso_sprite.scale = Vector2(base_ts.x * (1.0 + breath * 0.015) * turn_sx, base_ts.y * (1.0 - breath * 0.012))
	head_pivot.scale = Vector2(1.0 - _turn_squash * 0.30, 1.0)

	# 头部独立跟随鼠标准心微转与后坐微仰（与躯干轻微错拍显得更鲜活）
	var target_head_tilt := 0.0
	if has_aim and not is_run:
		target_head_tilt = clampf(aim_vec.y / 260.0, -1.0, 1.0) * 0.14
		if upper_direction == 2:
			target_head_tilt = -target_head_tilt
	target_head_tilt += recoil_kick * 0.75 + hurt_kick * 1.15
	_head_tilt = lerp_angle(_head_tilt, target_head_tilt, clampf(dt * 15.0, 0.0, 1.0))
	head_pivot.rotation = _head_tilt
	neck_pivot.position.y = NECK_OFFSET_Y - breath * 0.55

	# 脚底阴影随步态轻度呼吸缩放
	if shadow_sprite != null:
		var sh_s := 1.0 - clampf(-_hip_bob * 0.03, -0.08, 0.14)
		shadow_sprite.scale = Vector2(0.72 * sh_s, 0.56 * sh_s)


## Phase 5 战术翻滚三阶段正式骨骼动画（下蹲前扑 -> 紧凑团身前滚 -> 落地缓冲起身）。
func _apply_dodge_pose(u: float, dt: float) -> void:
	var roll_sign := 1.0 if _dodge_dir.x >= 0.0 else -1.0
	if absf(_dodge_dir.x) < 0.18:
		roll_sign = 1.0 if _dodge_dir.y >= 0.0 else -1.0
	# 屈膝向后弯曲方向（朝右 +1，朝左 -1）
	var knee_back := roll_sign

	if u < 0.22:
		# 阶段 1：蓄力压低重心 + 前扑起势
		_dodge_phase_name = &"crouch"
		var k := u / 0.22
		var e := k * k
		pelvis.position = Vector2(roll_sign * 3.0 * e, -PELVIS_HEIGHT + 16.0 * e)
		pelvis.rotation = roll_sign * 0.44 * e
		torso_pivot.rotation = roll_sign * 0.34 * e
		head_pivot.rotation = -roll_sign * 0.16 * e
		leg_l_hip.rotation = -roll_sign * 0.72 * e
		leg_l_knee.rotation = knee_back * 1.25 * e
		leg_r_hip.rotation = roll_sign * 0.38 * e
		leg_r_knee.rotation = knee_back * 0.95 * e
		_dynamic_dodge_weapon_rot = roll_sign * 0.42 * e
	elif u < 0.78:
		# 阶段 2：紧凑团身前滚（大腿紧抱胸前、小腿折叠贴臀，尾段顺滑展开衔接落地缓冲无悬空跳变）
		_dodge_phase_name = &"tuck_roll"
		var k := (u - 0.22) / 0.56
		var arch := sin(k * PI)
		# 前 72% 保持极致团滚球态，后 28% 平滑展身落脚迎接 recover
		var uncurl := clampf((k - 0.72) / 0.28, 0.0, 1.0)
		var tuck := 1.0 - uncurl * uncurl
		pelvis.position = Vector2(
			lerpf(roll_sign * 4.0 * arch, roll_sign * 2.0, uncurl),
			lerpf(-52.0 - 11.0 * arch, -PELVIS_HEIGHT + 16.0, uncurl * uncurl)
		)
		pelvis.rotation = roll_sign * (0.44 + k * (TAU - 0.68))
		torso_pivot.rotation = roll_sign * lerpf(0.28, 0.62, tuck)
		head_pivot.rotation = roll_sign * lerpf(-0.10, 0.48, tuck)
		leg_l_hip.rotation = -roll_sign * lerpf(0.68, 2.08, tuck)
		leg_l_knee.rotation = knee_back * lerpf(1.15, 2.38, tuck)
		leg_r_hip.rotation = -roll_sign * lerpf(-0.30, 1.90, tuck)
		leg_r_knee.rotation = knee_back * lerpf(0.78, 2.30, tuck)
		arm_l_shoulder.rotation = -roll_sign * lerpf(0.40, 1.15, tuck)
		arm_l_elbow.rotation = -roll_sign * lerpf(0.45, 1.45, tuck)
		arm_r_shoulder.rotation = -roll_sign * lerpf(0.32, 0.96, tuck)
		arm_r_elbow.rotation = -roll_sign * lerpf(0.40, 1.32, tuck)
		_dynamic_dodge_weapon_rot = pelvis.rotation * 0.55
		_hair_root_v -= roll_sign * 18.0 * dt
		_coat_l_v -= roll_sign * 16.0 * dt
		_coat_r_v -= roll_sign * 16.0 * dt
	else:
		# 阶段 3：落地缓冲半蹲 -> 弹性起身回正
		_dodge_phase_name = &"recover"
		var k := (u - 0.78) / 0.22
		var inv := 1.0 - k
		var bounce := sin(k * PI) * 3.0
		pelvis.position = Vector2(roll_sign * 2.0 * inv, -PELVIS_HEIGHT + 16.0 * inv * inv + bounce)
		pelvis.rotation = roll_sign * (-0.24 * inv)
		torso_pivot.rotation = roll_sign * 0.28 * inv
		head_pivot.rotation = -roll_sign * 0.10 * inv
		leg_l_hip.rotation = -roll_sign * 0.68 * inv
		leg_l_knee.rotation = knee_back * 1.15 * inv
		leg_r_hip.rotation = roll_sign * 0.30 * inv
		leg_r_knee.rotation = knee_back * 0.78 * inv
		_dynamic_dodge_weapon_rot = roll_sign * 0.25 * inv
	head_pivot.scale = Vector2.ONE

	# 翻滚期间武器始终紧锁在旋转后的胸口位置，绝不悬空脱手
	var chest_now := pelvis.position + Vector2(0.0, -22.0).rotated(pelvis.rotation + torso_pivot.rotation)
	_dynamic_dodge_weapon_offset = chest_now - Vector2(0.0, -88.0)

	if shadow_sprite != null:
		var s_tuck := 1.18 if _dodge_phase_name == &"tuck_roll" else 0.92
		shadow_sprite.scale = Vector2(0.72 * s_tuck, 0.56 * (0.85 if _dodge_phase_name == &"tuck_roll" else 1.0))


func _step_secondary_springs(velocity: Vector2, accel: Vector2, is_dodging: bool, dt: float) -> void:
	# 水平速度产生的迎风拖尾角 + 加速度带来的惯性滞后
	var wind_x := clampf(-velocity.x / 360.0, -1.2, 1.2)
	var inertia_x := clampf(-accel.x / 1800.0, -0.8, 0.8)
	var speed_mag := clampf(velocity.length() / 360.0, 0.0, 1.3)
	var idle_sway := sin(_breath_time * 2.1 + 0.6) * 0.045

	# 后发主根弹簧（柔顺中阻尼）
	var hr_target := wind_x * 0.42 + inertia_x * 0.25 + idle_sway
	var hr_acc := 85.0 * (hr_target - _hair_root_a) - 10.5 * _hair_root_v
	_hair_root_v += hr_acc * dt
	_hair_root_a = clampf(_hair_root_a + _hair_root_v * dt, -0.78, 0.78)

	# 发梢二节滞后弹簧（稍低刚度，呈现清晰二次跟随飘逸感）
	var ht_target := _hair_root_a * 0.75 + wind_x * 0.32 + sin(_breath_time * 3.1) * 0.055
	var ht_acc := 64.0 * (ht_target - _hair_tip_a) - 8.2 * _hair_tip_v
	_hair_tip_v += ht_acc * dt
	_hair_tip_a = clampf(_hair_tip_a + _hair_tip_v * dt, -0.95, 0.95)

	if hair_back_pivot != null:
		hair_back_pivot.rotation = _hair_root_a
	if hair_back_tip != null:
		hair_back_tip.rotation = _hair_tip_a * 0.85
	if hair_side_l_pivot != null:
		hair_side_l_pivot.rotation = _hair_root_a * 0.55 + 0.04 + idle_sway
	if hair_side_r_pivot != null:
		hair_side_r_pivot.rotation = _hair_root_a * 0.55 - 0.04 - idle_sway

	# 左右风衣衣摆弹簧（冲刺/翻滚自然向外张开拖尾）
	var flare := (0.16 + speed_mag * 0.28 + (0.25 if is_dodging else 0.0))
	var cl_target := wind_x * 0.48 + inertia_x * 0.22 + flare
	var cr_target := wind_x * 0.48 + inertia_x * 0.22 - flare
	_coat_l_v += (76.0 * (cl_target - _coat_l_a) - 9.8 * _coat_l_v) * dt
	_coat_l_a = clampf(_coat_l_a + _coat_l_v * dt, -0.75, 0.88)
	_coat_r_v += (76.0 * (cr_target - _coat_r_a) - 9.8 * _coat_r_v) * dt
	_coat_r_a = clampf(_coat_r_a + _coat_r_v * dt, -0.88, 0.75)

	var ct_target := (wind_x * 0.42 + inertia_x * 0.18)
	_coat_tip_v += (58.0 * (ct_target - _coat_tip_a) - 7.8 * _coat_tip_v) * dt
	_coat_tip_a = clampf(_coat_tip_a + _coat_tip_v * dt, -0.85, 0.85)

	if coat_l_pivot != null:
		coat_l_pivot.rotation = _coat_l_a
	if coat_l_tip != null:
		coat_l_tip.rotation = _coat_tip_a * 0.72
	if coat_r_pivot != null:
		coat_r_pivot.rotation = _coat_r_a
	if coat_r_tip != null:
		coat_r_tip.rotation = _coat_tip_a * 0.72

	# 格裙下摆轻微跟随
	var sk_target := wind_x * 0.16 + inertia_x * 0.10
	_skirt_v += (95.0 * (sk_target - _skirt_a) - 12.0 * _skirt_v) * dt
	_skirt_a = clampf(_skirt_a + _skirt_v * dt, -0.30, 0.30)
	if skirt_pivot != null:
		skirt_pivot.rotation = _skirt_a

	# 背后枪盒随步态滞后弹跳
	var gear_target := -_hip_bob * 0.45
	_gear_bob_v += (110.0 * (gear_target - _gear_bob) - 12.5 * _gear_bob_v) * dt
	_gear_bob = clampf(_gear_bob + _gear_bob_v * dt, -5.0, 5.0)
	if back_gear_pivot != null:
		back_gear_pivot.position.y = -24.0 + _gear_bob


static func _vec_to_dir(v: Vector2) -> int:
	if absf(v.x) > absf(v.y):
		return 3 if v.x > 0.0 else 2
	return 0 if v.y > 0.0 else 1
