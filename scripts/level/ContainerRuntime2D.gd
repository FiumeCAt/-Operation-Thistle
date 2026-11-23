extends RefCounted
class_name ContainerRuntime2D
## 2D 容器美术目录、稀有度配色、保底保险箱判定与运行时构建/悬浮提示/刷新子系统。
## 从 Level2D 抽离，可脱离主场景独立单测容器目录、提示状态切换与浪潮重置逻辑。

const SHADOW := preload("res://assets/art/fx/shadow_radial.png")

## 纯装饰容器：不参与常规补给点生成，但仍可作为可搜刮物件注册。
const DECO_ART := {
	&"trunk_storage": {"tex": preload("res://assets/art/containers/trunk_storage/closed.png"), "width": 60.0},
	&"tactical_case": {"tex": preload("res://assets/art/containers/tactical_case/closed.png"), "width": 60.0},
	&"medcrate_large": {"tex": preload("res://assets/art/containers/medcrate_large/closed.png"), "width": 60.0},
	&"material_case": {"tex": preload("res://assets/art/containers/material_case/closed.png"), "width": 30.0},
	&"box_document": {"tex": preload("res://assets/art/containers/box_document/closed.png"), "width": 60.0},
	&"case_luggage": {"tex": preload("res://assets/art/containers/case_luggage/closed.png"), "width": 26.0},
	&"case_luggage_black": {"tex": preload("res://assets/art/containers/case_luggage_black/closed.png"), "width": 26.0},
	&"case_luggage_green": {"tex": preload("res://assets/art/containers/case_luggage_green/closed.png"), "width": 26.0},
	&"case_trolley": {"tex": preload("res://assets/art/containers/case_trolley/closed.png"), "width": 26.0},
	&"case_trolley_black": {"tex": preload("res://assets/art/containers/case_trolley_black/closed.png"), "width": 26.0},
}

## 更衣室的挂衣道具；每个衣物对应一种可搜索容器。
const CLOTH_TEX: Array[Texture2D] = [
	preload("res://assets/art/containers/coat_cold/closed.png"),
	preload("res://assets/art/containers/jacket_work/closed.png"),
	preload("res://assets/art/containers/jacket_casual/closed.png"),
	preload("res://assets/art/containers/hazmat_suit/closed.png"),
]
const CLOTH_IDS: Array[StringName] = [
	&"coat_cold", &"jacket_work", &"jacket_casual", &"hazmat_suit",
]

## 容器贴图：512 px 画布 → 96 世界像素（1.5 格）。物体在画布内底部对齐于 62/64 处。
const CONTAINER_BASE_SCALE := 0.15
const CONTAINER_GROUND := 16.0

## 容器美术表：关闭/开启贴图、相对体型、关闭态内容宽度与顶边（逻辑像素）。
const CONTAINER_ART := {
	&"weapon_crate": {
		"closed": preload("res://assets/art/containers/weapon_crate/closed.png"),
		"open": preload("res://assets/art/containers/weapon_crate/open.png"),
		"scale": 1.0, "width": 60.0, "top": 21.0,
	},
	&"supplycrate_large": {
		"closed": preload("res://assets/art/containers/supplycrate_large/closed.png"),
		"open": preload("res://assets/art/containers/supplycrate_large/open.png"),
		"scale": 1.0, "width": 58.0, "top": 6.0,
	},
	&"ammo_can": {
		"closed": preload("res://assets/art/containers/ammo_can/closed.png"),
		"open": preload("res://assets/art/containers/ammo_can/open.png"),
		"scale": 0.9, "width": 48.0, "top": 18.0,
	},
	&"medbag_pro": {
		"closed": preload("res://assets/art/containers/medbag_pro/closed.png"),
		"open": preload("res://assets/art/containers/medbag_pro/open.png"),
		"scale": 0.9, "width": 55.0, "top": 11.0,
	},
	&"drawer_cabinet": {
		"closed": preload("res://assets/art/containers/drawer_cabinet/closed.png"),
		"open": preload("res://assets/art/containers/drawer_cabinet/open.png"),
		"scale": 1.35, "width": 35.0, "top": 6.0,
	},
	&"safe_standard": {
		"closed": preload("res://assets/art/containers/safe_standard/closed.png"),
		"open": preload("res://assets/art/containers/safe_standard/open.png"),
		"scale": 1.35, "width": 33.0, "top": 6.0,
	},
	&"safe_electronic": {
		"closed": preload("res://assets/art/containers/safe_electronic/closed.png"),
		"open": preload("res://assets/art/containers/safe_electronic/open.png"),
		"scale": 1.0, "width": 60.0, "top": 7.0,
	},
	&"safe_military": {
		"closed": preload("res://assets/art/containers/safe_military/closed.png"),
		"open": preload("res://assets/art/containers/safe_military/open.png"),
		"scale": 1.0, "width": 60.0, "top": 16.0,
	},
	&"drawer_steel": {
		"closed": preload("res://assets/art/containers/drawer_steel/closed.png"),
		"open": preload("res://assets/art/containers/drawer_steel/open.png"),
		"scale": 1.3, "width": 48.0, "top": 6.0,
	},
	&"case_trolley_green": {
		"closed": preload("res://assets/art/containers/case_trolley_green/closed.png"),
		"open": preload("res://assets/art/containers/case_trolley_green/open.png"),
		"scale": 1.0, "width": 26.0, "top": 6.0,
	},
	&"pc_military": {
		"closed": preload("res://assets/art/containers/pc_military/closed.png"),
		"open": preload("res://assets/art/containers/pc_military/open.png"),
		"scale": 1.1, "width": 37.0, "top": 6.0,
	},
	&"material_box": {
		"closed": preload("res://assets/art/containers/material_box/closed.png"),
		"open": preload("res://assets/art/containers/material_box/open.png"),
		"scale": 0.95, "width": 60.0, "top": 21.0,
	},
	&"ammo_box": {
		"closed": preload("res://assets/art/containers/ammo_box/closed.png"),
		"open": preload("res://assets/art/containers/ammo_box/open.png"),
		"scale": 0.88, "width": 60.0, "top": 17.0,
	},
	&"medical_box": {
		"closed": preload("res://assets/art/containers/medical_box/closed.png"),
		"open": preload("res://assets/art/containers/medical_box/open.png"),
		"scale": 0.82, "width": 58.0, "top": 16.0,
	},
	&"filing_cabinet": {
		"closed": preload("res://assets/art/containers/filing_cabinet/closed.png"),
		"open": preload("res://assets/art/containers/filing_cabinet/open.png"),
		"scale": 1.35, "width": 35.0, "top": 6.0,
	},
	&"suitcase": {
		"closed": preload("res://assets/art/containers/suitcase/closed.png"),
		"open": preload("res://assets/art/containers/suitcase/open.png"),
		"scale": 0.9, "width": 60.0, "top": 16.0,
	},
	&"computer_case": {
		"closed": preload("res://assets/art/containers/computer_case/closed.png"),
		"open": preload("res://assets/art/containers/computer_case/open.png"),
		"scale": 1.05, "width": 52.0, "top": 6.0,
	},
	&"toolbox": {
		"closed": preload("res://assets/art/containers/toolbox/closed.png"),
		"open": preload("res://assets/art/containers/toolbox/open.png"),
		"scale": 0.8, "width": 59.0, "top": 19.0,
	},
	&"mech_unit": {
		"closed": preload("res://assets/art/containers/mech_unit/closed.png"),
		"open": preload("res://assets/art/containers/mech_unit/open.png"),
		"scale": 1.1, "width": 53.0, "top": 15.0,
	},
	&"safe_small": {
		"closed": preload("res://assets/art/containers/safe_small/closed.png"),
		"open": preload("res://assets/art/containers/safe_small/open.png"),
		"scale": 0.95, "width": 60.0, "top": 9.0,
	},
}

const CONTAINER_NAMES := {
	&"weapon_crate": "武器箱",
	&"supplycrate_large": "大型补给箱",
	&"ammo_can": "弹药罐",
	&"medbag_pro": "高级医疗包",
	&"drawer_cabinet": "木制抽屉柜",
	&"safe_standard": "标准保险箱",
	&"safe_electronic": "电子保险箱",
	&"safe_military": "军用保险箱",
	&"safe_small": "小型保险箱",
	&"drawer_steel": "钢制抽屉",
	&"case_trolley_green": "绿色拉杆箱",
	&"pc_military": "军用机箱",
	&"material_box": "物料箱",
	&"ammo_box": "弹药箱",
	&"medical_box": "医疗箱",
	&"filing_cabinet": "文件柜",
	&"suitcase": "手提箱",
	&"computer_case": "电脑机箱",
	&"toolbox": "工具箱",
	&"mech_unit": "机械单元",
	&"trunk_storage": "储物箱",
	&"tactical_case": "战术箱",
	&"medcrate_large": "大型医疗箱",
	&"material_case": "物料盒",
	&"box_document": "文件盒",
	&"case_luggage": "行李箱",
	&"case_luggage_black": "黑色行李箱",
	&"case_luggage_green": "绿色行李箱",
	&"case_trolley": "拉杆箱",
	&"case_trolley_black": "黑色拉杆箱",
	&"coat_cold": "防寒大衣",
	&"jacket_work": "工作夹克",
	&"jacket_casual": "休闲夹克",
	&"hazmat_suit": "防护服",
}

const RARITY_COMMON := Color(0.79, 0.83, 0.87)
const RARITY_UNCOMMON := Color(0.42, 1.0, 0.62)
const RARITY_RARE := Color(0.45, 0.75, 1.0)
const RARITY_EPIC := Color(0.68, 0.52, 1.0)
const RARITY_LEGENDARY := Color(1.0, 0.71, 0.32)

const ADVANCED_GUARANTEE_SAFES: Array[StringName] = [
	&"safe_standard", &"safe_electronic", &"safe_military",
]


static func container_art(id: StringName) -> Dictionary:
	return CONTAINER_ART.get(id, CONTAINER_ART[&"weapon_crate"])


static func display_name(id: StringName) -> String:
	return String(CONTAINER_NAMES.get(id, "补给箱"))


static func rarity_color(id: StringName) -> Color:
	match id:
		&"safe_military":
			return RARITY_LEGENDARY
		&"safe_electronic", &"weapon_crate":
			return RARITY_EPIC
		&"safe_standard", &"pc_military", &"mech_unit", &"supplycrate_large", \
				&"medbag_pro", &"ammo_box", &"drawer_steel":
			return RARITY_RARE
		&"safe_small", &"drawer_cabinet", &"tactical_case", &"medcrate_large":
			return RARITY_UNCOMMON
		_:
			return RARITY_COMMON


static func guarantees_advanced(id: StringName) -> bool:
	return ADVANCED_GUARANTEE_SAFES.has(id)


## 装饰容器按外观给一点合理的产物：医疗箱出维修件，文件箱出电子件，其余出零件。
static func deco_loot(art_id: StringName) -> StringName:
	match art_id:
		&"medcrate_large":
			return &"repair"
		&"box_document":
			return &"electronics"
		&"coat_cold", &"jacket_work", &"jacket_casual", &"hazmat_suit":
			return &"parts"
		_:
			return &"parts"


static func _make_hint_label(parent: Node, hint_y: float) -> Label:
	var hint := Label.new()
	hint.text = "E  搜索"
	hint.size = Vector2(120, 20)
	hint.position = Vector2(-60, hint_y)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72))
	hint.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05, 0.95))
	hint.add_theme_constant_override("outline_size", 5)
	hint.z_index = 5
	hint.visible = false
	parent.add_child(hint)
	return hint


static func _add_shadow(parent: Node, size: Vector2, offset: Vector2, alpha: float) -> void:
	var shadow := Sprite2D.new()
	shadow.texture = SHADOW
	shadow.scale = Vector2(size.x / 200.0, size.y / 200.0)
	shadow.position = offset
	shadow.modulate = Color(0.02, 0.02, 0.02, alpha)
	parent.add_child(shadow)


## 装饰容器统一注册为可搜刮对象：复用现有贴图和碰撞，不再额外生成一份。
static func register_deco_container(containers: Array[Dictionary], body: Node2D, sprite: Sprite2D,
		pos: Vector2, art_id: StringName, loot_id: StringName, hint_y: float,
		mark_obstacle_fn: Callable) -> void:
	var art: Dictionary = DECO_ART.get(art_id, {})
	var obstacle_w := float(art.get("width", 24.0))
	if mark_obstacle_fn.is_valid():
		mark_obstacle_fn.call(pos, Vector2(obstacle_w, 24.0))
	var hint := _make_hint_label(body, hint_y)
	containers.append({
		"room": -1,
		"position": pos,
		"loot": loot_id,
		"art": art_id,
		"searched": false,
		"node": body,
		"sprite": sprite,
		"hint": hint,
		"hint_y": hint_y,
		# 装饰物件只有关闭态贴图，搜索后保持原图并靠变暗表示已开。
		"keep_closed_art": true,
	})


## 车间里的装饰容器：保留碰撞与外观，同时注册成可搜刮对象。
static func spawn_deco_prop(sort_layer: Node2D, containers: Array[Dictionary],
		pos: Vector2, art_id: StringName, mark_obstacle_fn: Callable) -> void:
	var art: Dictionary = DECO_ART[art_id]
	var s := CONTAINER_BASE_SCALE
	var body := Node2D.new()
	body.position = pos
	sort_layer.add_child(body)
	_add_shadow(body, Vector2(float(art["width"]) * 1.2, float(art["width"]) * 0.5),
		Vector2(0, CONTAINER_GROUND - 2), 0.38)
	var sprite := Sprite2D.new()
	sprite.texture = art["tex"]
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(0, CONTAINER_GROUND - 240.0 * s)
	body.add_child(sprite)
	var hit := StaticBody2D.new()
	hit.collision_layer = 1
	hit.collision_mask = 2
	hit.position = Vector2(0, -6)
	body.add_child(hit)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(art["width"]) * 1.0, 22.0)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	hit.add_child(collision)
	register_deco_container(containers, body, sprite, pos, art_id,
		deco_loot(art_id), -122.0, mark_obstacle_fn)


## 更衣室的挂衣钩：可作为衣物搜刮，无碰撞。
static func spawn_coat_prop(sort_layer: Node2D, containers: Array[Dictionary],
		pos: Vector2, tex: Texture2D, art_id: StringName, mark_obstacle_fn: Callable) -> void:
	var holder := Node2D.new()
	holder.position = pos
	sort_layer.add_child(holder)
	_add_shadow(holder, Vector2(34, 14), Vector2(0, 8), 0.3)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(0.16, 0.16)
	holder.add_child(sprite)
	register_deco_container(containers, holder, sprite, pos, art_id,
		deco_loot(art_id), -78.0, mark_obstacle_fn)


## 为尚未生成节点的标准补给容器创建精灵、阴影与悬浮提示。
static func build_containers(sort_layer: Node2D, containers: Array[Dictionary]) -> void:
	for entry in containers:
		if entry.get("node") != null:
			continue
		var pos: Vector2 = entry["position"]
		var art_id := StringName(entry.get("art", &"material_box"))
		var art := container_art(art_id)
		var mult := float(art["scale"])
		var s := CONTAINER_BASE_SCALE * mult

		var body := Node2D.new()
		body.position = pos
		sort_layer.add_child(body)
		var width := float(art["width"]) * mult
		_add_shadow(body, Vector2(width, width * 0.44), Vector2(0, CONTAINER_GROUND - 2), 0.42)

		var chest := Sprite2D.new()
		chest.texture = art["closed"]
		chest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		chest.scale = Vector2(s, s)
		# 画布内容底边在 62/64 处（距中心 240 texel），把它对齐到地面基线。
		chest.position = Vector2(0, CONTAINER_GROUND - 240.0 * s)
		body.add_child(chest)

		var top_y := CONTAINER_GROUND + (float(art["top"]) * 8.0 - 496.0) * s
		var hint := _make_hint_label(body, top_y - 24.0)
		entry["node"] = body
		entry["sprite"] = chest
		entry["hint"] = hint
		entry["hint_y"] = hint.position.y


## 只让目标容器显示悬浮提示；已搜刮的容器显示“已搜索”，index < 0 时全部隐藏。
static func set_container_hint(containers: Array[Dictionary], index: int, searched := false) -> void:
	for i in containers.size():
		var hint: Label = containers[i].get("hint")
		if hint != null:
			var show := i == index
			hint.visible = show
			if show:
				hint.text = "已搜索" if searched else "E  搜索"
				hint.add_theme_color_override("font_color",
					Color(0.72, 0.76, 0.80, 0.9) if searched else Color(1.0, 0.93, 0.72))


## 浪潮模式每 5 波刷新补给：所有容器恢复未搜刮，外观回到关闭态。
static func refresh_containers(containers: Array[Dictionary]) -> void:
	for entry in containers:
		entry["searched"] = false
		var node: Node2D = entry.get("node")
		if node != null:
			node.modulate = Color(1, 1, 1, 1)
		var sprite: Sprite2D = entry.get("sprite")
		if sprite != null and not bool(entry.get("keep_closed_art", false)):
			var art := container_art(StringName(entry.get("art", &"material_box")))
			if art.has("closed"):
				sprite.texture = art["closed"]
		var hint: Label = entry.get("hint")
		if hint != null:
			hint.visible = false


## 悬浮提示轻微上下浮动，提示“可交互”而不是固定标签。
static func animate_hints(containers: Array[Dictionary]) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0
	for entry in containers:
		var hint: Label = entry.get("hint")
		if hint != null and hint.visible:
			hint.position.y = float(entry.get("hint_y", 0.0)) + sin(t * 3.4) * 2.0
