extends RefCounted
class_name LevelProps2D
## 2D 关卡房间陈设、地标压铸机、走廊掩体与贴墙装饰构建子系统。
## 同时提供家具通用基座、阴影与 2D 光照遮挡体工具，供 LevelBuilder2D 复用。

const LAYOUT := preload("res://scripts/level/LevelLayoutData.gd")
const CONTAINERS := preload("res://scripts/level/ContainerRuntime2D.gd")
const TILE := LAYOUT.TILE
const HALL_MACHINE_CELL := LAYOUT.HALL_MACHINE_CELL

const SHELF_TEX := preload("res://assets/art/env/pixel_shelf_128.png")
const SHELF_B_TEX := preload("res://assets/art/env/pixel_shelf_128_b.png")
const CRATE_TEX := preload("res://assets/art/env/pixel_crate_48.png")
const BARREL_TEX := preload("res://assets/art/env/pixel_barrel_40.png")
const SHADOW := preload("res://assets/art/fx/shadow_radial.png")


static func spot_in_room(rng: RandomNumberGenerator, rect: Rect2, margin_tiles: float) -> Vector2:
	var margin := margin_tiles * TILE
	return Vector2(
		rng.randf_range(rect.position.x + margin, rect.end.x - margin),
		rng.randf_range(rect.position.y + margin, rect.end.y - margin),
	)


## 给墙体/家具添加 2D 光照遮挡多边形（局部坐标）。
static func add_light_occluder(parent: Node2D, rect: Rect2) -> void:
	var occluder := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	occluder.occluder = poly
	parent.add_child(occluder)


static func detail(parent: Node2D, rect: Rect2, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	])
	poly.color = color
	parent.add_child(poly)


static func shadow(parent: Node, size: Vector2, offset: Vector2, alpha: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = SHADOW
	spr.scale = Vector2(size.x / 200.0, size.y / 200.0)
	spr.position = offset
	spr.modulate = Color(0.02, 0.02, 0.02, alpha)
	parent.add_child(spr)


static var _sight_obstacle_fn: Callable = Callable()


static func prop_body(sort_layer: Node2D, mark_obstacle_fn: Callable,
		pos: Vector2, size: Vector2, color: Color, accent: Color) -> StaticBody2D:
	if mark_obstacle_fn.is_valid():
		mark_obstacle_fn.call(pos, size)
	if _sight_obstacle_fn.is_valid():
		_sight_obstacle_fn.call(pos, size)
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)

	shadow(body, Vector2(size.x * 1.1, size.y * 0.5), Vector2(0, size.y * 0.28), 0.4)
	var slab := Polygon2D.new()
	slab.polygon = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5),
		Vector2(-size.x * 0.5, size.y * 0.5),
	])
	slab.color = color
	body.add_child(slab)

	var edge := Line2D.new()
	edge.points = PackedVector2Array([
		Vector2(-size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, -size.y * 0.5),
		Vector2(size.x * 0.5, size.y * 0.5),
		Vector2(-size.x * 0.5, size.y * 0.5),
		Vector2(-size.x * 0.5, -size.y * 0.5),
	])
	edge.width = 3.0
	edge.default_color = accent
	body.add_child(edge)

	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	# 大型家具也会挡住视野，避免玩家隔着箱子看到后面的敌人。
	add_light_occluder(body, Rect2(-size * 0.5, size))
	return body


static func build_rooms(ctx: Dictionary) -> void:
	var sort_layer: Node2D = ctx["sort_layer"]
	var rooms: Array[Dictionary] = ctx["rooms"]
	var mark_obstacle: Callable = ctx["mark_obstacle"]
	_sight_obstacle_fn = ctx.get("mark_sight_obstacle", Callable())
	for i in rooms.size():
		_populate_room(ctx, rooms[i], LAYOUT.ROOM_DEFS[i])
		_decorate_room(ctx, rooms[i], LAYOUT.ROOM_DEFS[i])
		_room_label(sort_layer, rooms[i])
	# 走廊拐角和瓶颈处放少量掩体，长距离对枪时有可利用的落点。
	for corner in [Vector2(39, 17), Vector2(39, 102), Vector2(139, 36), Vector2(139, 90)]:
		_barrel_prop(sort_layer, mark_obstacle, Vector2(corner) * TILE)
	for spot in [Vector2(48, 36), Vector2(124, 36), Vector2(48, 72), Vector2(124, 72)]:
		_barrel_prop(sort_layer, mark_obstacle, Vector2(spot) * TILE)
	_sight_obstacle_fn = Callable()


## 房间名印在地板上，俯视时不用打开地图也能知道自己在哪个区。
static func _room_label(sort_layer: Node2D, room: Dictionary) -> void:
	var rect: Rect2 = room["rect"]
	var label := Label.new()
	label.text = String(room["name"])
	label.position = Vector2(rect.position.x + 12, rect.position.y + 8)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.88, 0.64, 0.32, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	sort_layer.add_child(label)


static func _populate_room(ctx: Dictionary, room: Dictionary, def: Dictionary) -> void:
	var sort_layer: Node2D = ctx["sort_layer"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var containers: Array[Dictionary] = ctx["containers"]
	var mark_obstacle: Callable = ctx["mark_obstacle"]
	var player_spawn: Vector2 = ctx["player_spawn"]
	var exit_position: Vector2 = ctx["exit_position"]
	var power_position: Vector2 = ctx["power_position"]
	var switch_exit_position: Vector2 = ctx["switch_exit_position"]
	var rect: Rect2 = room["rect"]
	var type: StringName = room["type"]
	var placed: Array[Vector2] = []
	var count := int(def.get("props", 3))
	for attempt in count * 4:
		if placed.size() >= count:
			break
		var pos := spot_in_room(rng, rect, 1.3)
		if pos.distance_to(room["door"]) < TILE * 2.6:
			continue
		var near_extra_door := false
		for extra in def.get("extra_doors", []):
			var cell: Vector2i = extra["cell"]
			if pos.distance_to(Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)) < TILE * 2.6:
				near_extra_door = true
				break
		if near_extra_door:
			continue
		if pos.distance_to(player_spawn) < TILE * 2.2:
			continue
		if pos.distance_to(exit_position) < TILE * 2.2:
			continue
		if pos.distance_to(power_position) < TILE * 2.2:
			continue
		if pos.distance_to(switch_exit_position) < TILE * 2.2:
			continue
		if pos.distance_to(HALL_MACHINE_CELL * TILE) < TILE * 4.0:
			continue  # 大厅压铸机周围留空，避免陈设压进机器。
		var blocked := false
		for other in placed:
			if pos.distance_to(other) < TILE * 1.8:
				blocked = true
				break
		if not blocked:
			for entry in containers:
				if int(entry["room"]) == int(room["index"]) \
					and pos.distance_to(entry["position"]) < TILE * 1.6:
					blocked = true
					break
		if blocked:
			continue
		placed.append(pos)
		match type:
			&"insertion", &"storage":
				_shelf_prop(sort_layer, mark_obstacle, pos, attempt % 3 == 0) if attempt % 4 == 0 else _crate_prop(sort_layer, mark_obstacle, pos)
			&"medical":
				_bed_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _locker_prop(sort_layer, mark_obstacle, pos)
			&"armory":
				_locker_prop(sort_layer, mark_obstacle, pos) if attempt % 3 == 0 else _crate_prop(sort_layer, mark_obstacle, pos)
			&"control":
				_console_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _shelf_prop(sort_layer, mark_obstacle, pos, false)
			&"nest":
				_pod_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _crate_prop(sort_layer, mark_obstacle, pos)
			&"aux":
				_console_prop(sort_layer, mark_obstacle, pos) if attempt % 3 == 0 else _shelf_prop(sort_layer, mark_obstacle, pos, false)
			&"workshop":
				_shelf_prop(sort_layer, mark_obstacle, pos, attempt % 2 == 0) if attempt % 3 == 0 else _barrel_prop(sort_layer, mark_obstacle, pos)
			&"abandoned":
				_crate_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _barrel_prop(sort_layer, mark_obstacle, pos)
			&"extraction":
				_barrel_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _crate_prop(sort_layer, mark_obstacle, pos)
			&"refinery":
				_generator_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _barrel_prop(sort_layer, mark_obstacle, pos)
			&"foundry":
				_generator_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _crate_prop(sort_layer, mark_obstacle, pos)
			&"substation":
				_console_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _locker_prop(sort_layer, mark_obstacle, pos)
			&"qc":
				_console_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _shelf_prop(sort_layer, mark_obstacle, pos, true)
			&"locker":
				_locker_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _crate_prop(sort_layer, mark_obstacle, pos)
			&"vent":
				_barrel_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _shelf_prop(sort_layer, mark_obstacle, pos, false)
			&"break_room", &"canteen":
				_table_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _locker_prop(sort_layer, mark_obstacle, pos)
			&"hall":
				_crate_prop(sort_layer, mark_obstacle, pos) if attempt % 2 == 0 else _barrel_prop(sort_layer, mark_obstacle, pos)
			_:
				_crate_prop(sort_layer, mark_obstacle, pos)


## 按房间类型摆放装饰物，位置贴墙，避开随机陈设。
static func _decorate_room(ctx: Dictionary, room: Dictionary, def: Dictionary) -> void:
	var sort_layer: Node2D = ctx["sort_layer"]
	var containers: Array[Dictionary] = ctx["containers"]
	var mark_obstacle: Callable = ctx["mark_obstacle"]
	var rect: Rect2 = room["rect"]
	var type: StringName = def["type"]
	var inner := Vector2(1.1 * TILE, 1.1 * TILE)
	var top_left := rect.position + inner
	var top_right := rect.position + Vector2(rect.size.x - inner.x, inner.y)
	var bottom_left := rect.position + Vector2(inner.x, rect.size.y - inner.y)
	match type:
		&"insertion":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_right + Vector2(-TILE, TILE), &"trunk_storage", mark_obstacle)
			CONTAINERS.spawn_deco_prop(sort_layer, containers, bottom_left + Vector2(0, -TILE), &"case_trolley_black", mark_obstacle)
		&"storage":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, bottom_left + Vector2(0, -TILE * 2), &"material_case", mark_obstacle)
		&"medical":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_right + Vector2(-TILE * 2, TILE), &"medcrate_large", mark_obstacle)
		&"armory":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_left + Vector2(TILE, TILE), &"tactical_case", mark_obstacle)
		&"aux":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_right + Vector2(-TILE * 2, TILE), &"box_document", mark_obstacle)
		&"refinery":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_left + Vector2(TILE, TILE), &"material_case", mark_obstacle)
		&"foundry":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, bottom_left + Vector2(0, -TILE * 2), &"trunk_storage", mark_obstacle)
		&"abandoned":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_left + Vector2(TILE, TILE), &"case_luggage_black", mark_obstacle)
		&"canteen":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_right + Vector2(-TILE * 2, TILE), &"case_luggage_green", mark_obstacle)
		&"break_room":
			CONTAINERS.spawn_deco_prop(sort_layer, containers, bottom_left + Vector2(0, -TILE * 2), &"case_trolley", mark_obstacle)
		&"hall":
			# 巨型压铸机固定在大厅中央，作为核心地标和掩体。
			_machine_prop(sort_layer, mark_obstacle, HALL_MACHINE_CELL * TILE)
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_left + Vector2(TILE * 4, TILE), &"material_case", mark_obstacle)
			CONTAINERS.spawn_deco_prop(sort_layer, containers, top_right + Vector2(-TILE * 5, TILE), &"material_case", mark_obstacle)
			CONTAINERS.spawn_deco_prop(sort_layer, containers, bottom_left + Vector2(TILE * 4, -TILE), &"trunk_storage", mark_obstacle)
		&"locker":
			for i in CONTAINERS.CLOTH_TEX.size():
				var px := rect.position.x + (2.4 + i * 2.6) * TILE
				CONTAINERS.spawn_coat_prop(sort_layer, containers,
					Vector2(px, rect.position.y + 1.6 * TILE),
					CONTAINERS.CLOTH_TEX[i], CONTAINERS.CLOTH_IDS[i], mark_obstacle)


static func _shelf_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2, variant: bool) -> void:
	if mark_obstacle.is_valid():
		mark_obstacle.call(pos + Vector2(0, 16), Vector2(128, 58))
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	shadow(body, Vector2(126, 50), Vector2(0, 34), 0.42)
	var sprite := Sprite2D.new()
	sprite.texture = SHELF_B_TEX if variant else SHELF_TEX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.position = Vector2(-64, -64)
	sprite.scale = Vector2(1.0, 0.9)
	body.add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(128, 58)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, 16)
	body.add_child(collision)


static func _crate_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	if mark_obstacle.is_valid():
		mark_obstacle.call(pos + Vector2(0, 2), Vector2(44, 38))
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	shadow(body, Vector2(44, 20), Vector2(0, 10), 0.42)
	var sprite := Sprite2D.new()
	sprite.texture = CRATE_TEX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(0, -8)
	body.add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(44, 38)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, 2)
	body.add_child(collision)


static func _barrel_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	if mark_obstacle.is_valid():
		mark_obstacle.call(pos, Vector2(36, 36))
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	shadow(body, Vector2(38, 18), Vector2(0, 8), 0.4)
	var sprite := Sprite2D.new()
	sprite.texture = BARREL_TEX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(sprite)
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)


static func _bed_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(96, 152), Color(0.22, 0.24, 0.29), Color(0.42, 0.46, 0.52))
	detail(body, Rect2(-40, -62, 80, 40), Color(0.55, 0.56, 0.55))
	detail(body, Rect2(-40, -18, 80, 4), Color(0.14, 0.16, 0.20))


static func _locker_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(58, 74), Color(0.26, 0.28, 0.31), Color(0.44, 0.47, 0.5))
	detail(body, Rect2(-4, -30, 3, 60), Color(0.16, 0.17, 0.19))
	detail(body, Rect2(16, -4, 8, 8), Color(0.72, 0.60, 0.24))


static func _console_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(104, 58), Color(0.18, 0.20, 0.23), Color(0.36, 0.40, 0.44))
	detail(body, Rect2(-44, -22, 88, 30), Color(0.16, 0.42, 0.55))
	detail(body, Rect2(-38, -16, 30, 4), Color(0.45, 0.78, 0.92))
	detail(body, Rect2(-38, -8, 52, 3), Color(0.35, 0.62, 0.74))


static func _generator_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(112, 78), Color(0.24, 0.25, 0.24), Color(0.42, 0.42, 0.4))
	detail(body, Rect2(-46, -28, 92, 12), Color(0.70, 0.48, 0.16))
	var hub := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		points.append(Vector2(cos(a) * 18, sin(a) * 18 + 12))
	hub.polygon = points
	hub.color = Color(0.16, 0.17, 0.18)
	body.add_child(hub)


static func _pod_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(88, 96), Color(0.14, 0.18, 0.15), Color(0.32, 0.42, 0.30))
	var glow := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		points.append(Vector2(cos(a) * 26, sin(a) * 34))
	glow.polygon = points
	glow.color = Color(0.35, 0.62, 0.36, 0.75)
	body.add_child(glow)


## 休息区/食堂的长条桌。
static func _table_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(118, 54), Color(0.30, 0.27, 0.23), Color(0.48, 0.43, 0.35))
	detail(body, Rect2(-52, -20, 104, 16), Color(0.38, 0.34, 0.28))
	detail(body, Rect2(-44, 4, 30, 3), Color(0.20, 0.18, 0.16))
	detail(body, Rect2(14, 4, 30, 3), Color(0.20, 0.18, 0.16))


## 主装配大厅的巨型压铸机：占地大，兼作掩体。
static func _machine_prop(sort_layer: Node2D, mark_obstacle: Callable, pos: Vector2) -> void:
	var body := prop_body(sort_layer, mark_obstacle, pos, Vector2(228, 150), Color(0.20, 0.21, 0.21), Color(0.40, 0.41, 0.39))
	detail(body, Rect2(-96, -58, 192, 22), Color(0.62, 0.42, 0.14))
	detail(body, Rect2(-96, -14, 192, 10), Color(0.13, 0.14, 0.14))
	detail(body, Rect2(-70, 26, 140, 30), Color(0.16, 0.17, 0.17))
	var hub := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		points.append(Vector2(cos(a) * 30, sin(a) * 30 + 22))
	hub.polygon = points
	hub.color = Color(0.34, 0.36, 0.35)
	body.add_child(hub)
