extends RefCounted
class_name LevelBuilder2D
## 2D 关卡几何体与场景节点构建器：负责地板、墙体合并与遮光体、贴花、门、竞技场边界、供电台与撤离点。

const LAYOUT := preload("res://scripts/level/LevelLayoutData.gd")
const PROPS := preload("res://scripts/level/LevelProps2D.gd")
const DOOR_SCRIPT := preload("res://scripts/level/Door2D.gd")

const TILE := LAYOUT.TILE
const MAP_W := LAYOUT.MAP_W
const MAP_H := LAYOUT.MAP_H
const DOOR_W := LAYOUT.DOOR_W
const ARENA_W := LAYOUT.ARENA_W
const ARENA_H := LAYOUT.ARENA_H

## 地板回退到旧版 256×256 地砖；墙面使用新的 128×128 暗色金属墙板。
const FLOOR_TEX := preload("res://assets/art/env/pixel_floor_256.png")
const WALL_TEX := preload("res://assets/art/env/wall_128.png")
## 128 贴图按世界坐标 1:1 重复，两块 64px 面板正好覆盖一个地块。
const WALL_UV_SCALE := 1.0
const C_WALL_TINT := Color(1.0, 1.0, 1.0)

static var _crisp_lit_mat: ShaderMaterial


## 地板与墙面启用 LINEAR 过滤让 PointLight2D 视野光照贴图走硬件双线性插值（彻底消除阶梯锯齿），
## 同时片段着色器把自身贴图 UV 对齐到纹素中心，保持像素风地砖/墙板 100% 锐利不发虚。
static func _crisp_pixel_material() -> ShaderMaterial:
	if _crisp_lit_mat == null:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
varying vec4 v_color;
void vertex() {
	v_color = COLOR;
}
void fragment() {
	vec2 sz = vec2(textureSize(TEXTURE, 0));
	vec2 uv = (floor(UV * sz) + 0.5) / sz;
	COLOR = texture(TEXTURE, uv) * v_color;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_crisp_lit_mat = mat
	return _crisp_lit_mat


static func build_floor(floor_layer: Node2D) -> void:
	for rect in LAYOUT.floor_rects():
		build_floor_rect(floor_layer, Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE))
	# 门槛也铺地板，避免开门后出现一条黑色缺口。
	for def in LAYOUT.ROOM_DEFS:
		for gap in LAYOUT.all_door_gaps(def):
			build_floor_rect(floor_layer, Rect2(Vector2(gap.position) * TILE, Vector2(gap.size) * TILE))
		for arch in def.get("arches", []):
			var ag := LAYOUT.arch_gap(arch)
			build_floor_rect(floor_layer, Rect2(Vector2(ag.position) * TILE, Vector2(ag.size) * TILE))


static func build_floor_rect(floor_layer: Node2D, rect: Rect2) -> void:
	var poly := Polygon2D.new()
	poly.texture = FLOOR_TEX
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	poly.material = _crisp_pixel_material()
	poly.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(rect.size.x, 0), rect.size, Vector2(0, rect.size.y),
	])
	# UV 用世界坐标，相邻矩形贴图才能连续。
	poly.uv = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])
	poly.position = rect.position
	floor_layer.add_child(poly)


static func build_arena_boundaries(sort_layer: Node2D) -> void:
	_arena_boundary(sort_layer, Rect2(-TILE, -TILE, (ARENA_W + 2) * TILE, TILE))
	_arena_boundary(sort_layer, Rect2(-TILE, ARENA_H * TILE, (ARENA_W + 2) * TILE, TILE))
	_arena_boundary(sort_layer, Rect2(-TILE, 0, TILE, ARENA_H * TILE))
	_arena_boundary(sort_layer, Rect2(ARENA_W * TILE, 0, TILE, ARENA_H * TILE))


## 不可见边界：只负责挡住玩家/子弹/敌人，不参与画面。
static func _arena_boundary(sort_layer: Node2D, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.position
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.size * 0.5
	body.add_child(collision)


## 构建整张 K-17 设施墙体并返回可通行格集合（供 NavGrid2D 合成最终寻路网格）。
static func build_walls(floor_layer: Node2D, sort_layer: Node2D) -> Dictionary:
	var floor_cells := {}
	for rect in LAYOUT.floor_rects():
		for y in rect.size.y:
			for x in rect.size.x:
				floor_cells[Vector2i(rect.position.x + x, rect.position.y + y)] = true

	var wall_cells := {}
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in floor_cells:
		for dir in dirs:
			var n: Vector2i = cell + dir
			if n.x < 0 or n.y < 0 or n.x >= MAP_W or n.y >= MAP_H:
				continue
			if not floor_cells.has(n):
				wall_cells[n] = true

	# 设施是一个实心矩形，未挖空的内部也补成墙体，
	# 否则俯视图里会出现一片片没有贴图的黑色空洞。
	var min_cell := Vector2i(MAP_W, MAP_H)
	var max_cell := Vector2i.ZERO
	for cell in floor_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	for y in range(min_cell.y - 1, max_cell.y + 2):
		for x in range(min_cell.x - 1, max_cell.x + 2):
			var cell := Vector2i(x, y)
			if not floor_cells.has(cell):
				wall_cells[cell] = true

	# 门洞从墙里挖掉；门本身负责阻挡，但寻路网格把它们视为可通行。
	var passable := floor_cells.duplicate()
	for def in LAYOUT.ROOM_DEFS:
		for gap in LAYOUT.all_door_gaps(def):
			for y in gap.size.y:
				for x in gap.size.x:
					var cell := Vector2i(gap.position.x + x, gap.position.y + y)
					wall_cells.erase(cell)
					passable[cell] = true
		for arch in def.get("arches", []):
			var ag := LAYOUT.arch_gap(arch)
			for y in ag.size.y:
				for x in ag.size.x:
					var cell := Vector2i(ag.position.x + x, ag.position.y + y)
					wall_cells.erase(cell)
					passable[cell] = true

	_merge_walls(floor_layer, sort_layer, wall_cells)
	return passable


## 贪心合并成较大的矩形，避免每个墙格一个 StaticBody2D。
static func _merge_walls(floor_layer: Node2D, sort_layer: Node2D, wall_cells: Dictionary) -> void:
	var visited := {}
	var cells: Array = wall_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell in cells:
		if visited.has(cell):
			continue
		var w := 1
		while wall_cells.has(cell + Vector2i(w, 0)) and not visited.has(cell + Vector2i(w, 0)):
			w += 1
		var h := 1
		while true:
			var ok := true
			for i in w:
				var c: Vector2i = cell + Vector2i(i, h)
				if not wall_cells.has(c) or visited.has(c):
					ok = false
					break
			if not ok:
				break
			h += 1
		for yy in h:
			for xx in w:
				visited[cell + Vector2i(xx, yy)] = true
		_wall_rect(floor_layer, sort_layer, Rect2(Vector2(cell) * TILE, Vector2(w, h) * TILE))


static func _wall_rect(floor_layer: Node2D, sort_layer: Node2D, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	# 以墙底边作为 y 排序基准：站在墙下方的角色会正确遮挡墙脚，
	# 站在墙上方的角色则被墙体挡住，避免立绘像穿出墙外。
	body.position = Vector2(rect.position.x, rect.end.y)
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)

	var top_left := Vector2(0.0, -rect.size.y)
	var uv_origin := rect.position * WALL_UV_SCALE
	var uv_size := rect.size * WALL_UV_SCALE
	var slab := Polygon2D.new()
	slab.texture = WALL_TEX
	slab.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	slab.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	slab.material = _crisp_pixel_material()
	slab.color = C_WALL_TINT
	slab.polygon = PackedVector2Array([
		top_left, top_left + Vector2(rect.size.x, 0), Vector2(rect.size.x, 0), Vector2.ZERO,
	])
	slab.uv = PackedVector2Array([
		uv_origin,
		uv_origin + Vector2(uv_size.x, 0),
		uv_origin + uv_size,
		uv_origin + Vector2(0, uv_size.y),
	])
	body.add_child(slab)

	# 墙顶只留一条很淡的高光，细节交给新贴图本身，避免出现亮边框。
	var cap := Line2D.new()
	cap.points = PackedVector2Array([
		top_left + Vector2(0, 1), top_left + Vector2(rect.size.x, 1),
	])
	cap.width = 2.0
	cap.default_color = Color(0.44, 0.43, 0.40, 0.65)
	body.add_child(cap)

	var bottom := Line2D.new()
	bottom.points = PackedVector2Array([Vector2(0, -1), Vector2(rect.size.x, -1)])
	bottom.width = 2.0
	bottom.default_color = Color(0.05, 0.05, 0.06, 0.85)
	body.add_child(bottom)

	# 墙脚投在地板上的阴影带
	var strip := Polygon2D.new()
	strip.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(rect.size.x, 0), Vector2(rect.size.x, 16), Vector2(0, 16),
	])
	strip.color = Color(0, 0, 0, 0.42)
	strip.position = Vector2(rect.position.x, rect.end.y)
	floor_layer.add_child(strip)

	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(rect.size.x * 0.5, -rect.size.y * 0.5)
	body.add_child(collision)
	# 视野系统：墙体切断玩家视野锥与灯光，形成真实的墙后阴影。
	PROPS.add_light_occluder(body, Rect2(Vector2(0, -rect.size.y), rect.size))


static func build_decals(floor_layer: Node2D, rooms: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for i in 56:
		var rect := LAYOUT.FLOOR_RECTS[rng.randi_range(0, LAYOUT.FLOOR_RECTS.size() - 1)]
		var pos := Vector2(
			rng.randf_range(rect.position.x + 0.5, rect.end.x - 0.5) * TILE,
			rng.randf_range(rect.position.y + 0.5, rect.end.y - 0.5) * TILE,
		)
		if rng.randf() < 0.4:
			_paper(floor_layer, pos)
		else:
			_decal(floor_layer, pos, Vector2(rng.randf_range(26, 52), rng.randf_range(16, 30)),
				Color(0.24, 0.08, 0.07, rng.randf_range(0.14, 0.3)))
	for room in rooms:
		var rect: Rect2 = room["rect"]
		for k in 2:
			_decal(floor_layer, PROPS.spot_in_room(rng, rect, 1.0), Vector2(30, 18), Color(0.06, 0.06, 0.06, 0.22))


static func _decal(floor_layer: Node2D, pos: Vector2, size: Vector2, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 13.0 + pos.y * 7.0)
	var poly := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 18:
		var angle := TAU * i / 18.0
		var r := 0.45 + rng.randf() * 0.55
		points.append(Vector2(cos(angle) * size.x * r, sin(angle) * size.y * r))
	poly.polygon = points
	poly.color = color
	poly.position = pos
	floor_layer.add_child(poly)


static func _paper(floor_layer: Node2D, pos: Vector2) -> void:
	var sheet := Polygon2D.new()
	sheet.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(14, -3), Vector2(17, 9), Vector2(3, 12),
	])
	sheet.color = Color(0.72, 0.70, 0.63, 0.55)
	sheet.position = pos
	floor_layer.add_child(sheet)


## 主门先全部建完，保证 doors[房间号] 的索引稳定（视角/测试都依赖）；再追加侧门。
static func build_doors(sort_layer: Node2D, rooms: Array[Dictionary], doors: Array[Dictionary]) -> void:
	for i in rooms.size():
		var room := rooms[i]
		var def: Dictionary = LAYOUT.ROOM_DEFS[i]
		room["door_node"] = _spawn_door(sort_layer, doors, room["door"], bool(def["vertical"]), i)
	for i in rooms.size():
		var def: Dictionary = LAYOUT.ROOM_DEFS[i]
		for extra in def.get("extra_doors", []):
			var cell: Vector2i = extra["cell"]
			_spawn_door(
				sort_layer, doors,
				Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE),
				bool(extra["vertical"]), i, true)


static func _spawn_door(sort_layer: Node2D, doors: Array[Dictionary],
		pos: Vector2, vertical: bool, room_index: int, extra := false) -> Node2D:
	var door := Node2D.new()
	door.set_script(DOOR_SCRIPT)
	door.position = pos
	door.width = DOOR_W * TILE
	if vertical:
		door.rotation = PI * 0.5
	sort_layer.add_child(door)
	doors.append({"room": room_index, "node": door, "open": false, "extra": extra})
	return door


static func build_power(sort_layer: Node2D, power_position: Vector2, mark_obstacle_fn: Callable) -> Dictionary:
	var power_node := PROPS.prop_body(sort_layer, mark_obstacle_fn, power_position, Vector2(120, 64),
		Color(0.18, 0.21, 0.24), Color(0.45, 0.50, 0.55))
	PROPS.detail(power_node, Rect2(-50, -24, 100, 30), Color(0.12, 0.32, 0.40))
	PROPS.detail(power_node, Rect2(-42, -16, 34, 4), Color(0.45, 0.78, 0.92))
	PROPS.detail(power_node, Rect2(-42, -8, 54, 3), Color(0.35, 0.62, 0.74))
	var lamp := Polygon2D.new()
	lamp.polygon = PackedVector2Array([
		Vector2(34, -18), Vector2(46, -18), Vector2(46, -6), Vector2(34, -6),
	])
	lamp.color = Color(0.95, 0.68, 0.24)
	power_node.add_child(lamp)

	var label := Label.new()
	label.text = "POWER // 供电"
	label.position = Vector2(-56, -86)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.74, 0.38, 0.9))
	power_node.add_child(label)
	return {"node": power_node, "lamp": lamp}


static func build_exits(sort_layer: Node2D, exits: Array[Dictionary],
		switch_exit_position: Vector2, exit_radius: float) -> Dictionary:
	exits.clear()
	for id in LAYOUT.EXTRACTS:
		var def: Dictionary = LAYOUT.EXTRACTS[id]
		var pos := Vector2(def["pos"]) * TILE
		var res := _exit_visual(sort_layer, pos, Color(0.16, 0.72, 0.62),
			"EXTRACTION // %s" % String(def["name"]), true, exit_radius)
		exits.append({"id": id, "name": def["name"], "position": pos, "node": res["node"]})
	var lift := _exit_visual(sort_layer, switch_exit_position, Color(0.92, 0.62, 0.20),
		"CARGO LIFT // 未供电", false, exit_radius)
	var switch_exit_node: Node2D = lift["node"]
	switch_exit_node.modulate = Color(0.55, 0.55, 0.55, 0.7)
	return {"switch_exit_node": switch_exit_node, "switch_label": lift["label"]}


static func _exit_visual(sort_layer: Node2D, pos: Vector2, color: Color,
		text: String, is_direct: bool, exit_radius: float) -> Dictionary:
	var node := Node2D.new()
	node.name = "Extraction" if is_direct else "CargoLift"
	node.position = pos
	sort_layer.add_child(node)

	var halo := Sprite2D.new()
	halo.texture = PROPS.SHADOW
	halo.scale = Vector2(1.5, 1.5)
	halo.modulate = Color(color.r, color.g, color.b, 0.5)
	node.add_child(halo)

	for ring in 3:
		var poly := Polygon2D.new()
		var points := PackedVector2Array()
		var radius := exit_radius - ring * 13.0
		for i in 28:
			var a := TAU * i / 28.0
			points.append(Vector2(cos(a) * radius, sin(a) * radius))
		poly.polygon = points
		poly.color = Color(color.r, color.g, color.b, 0.16 + ring * 0.16)
		node.add_child(poly)

	var core := Polygon2D.new()
	var core_points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		core_points.append(Vector2(cos(a) * 10, sin(a) * 10))
	core.polygon = core_points
	core.color = Color(0.72, 1.0, 0.92, 0.9)
	node.add_child(core)

	var label := Label.new()
	label.text = text
	label.position = Vector2(-72, exit_radius + 8)
	label.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.9))
	label.add_theme_font_size_override("font_size", 15)
	node.add_child(label)
	return {"node": node, "label": label}
