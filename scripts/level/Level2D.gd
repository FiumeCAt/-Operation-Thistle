extends Node
class_name Level2D

## 俯视 2D 关卡：单层工业巨构 K-17。
## 设计骨架：西侧物流脊（装卸/仓储/医疗/废弃）+ 北侧四座大车间 + 中央装配大厅
## （两翼挂着数据仓与军械库）+ 南侧窄服务廊与生活区 + 东侧货运竖廊（通风/撤离）。
## 走廊宽窄不一（6 格主廊 / 4 格服务廊 / 8 格大厅门厅），房间互相穿插形成多入口。
## 1 格 = 64 px；整图 176×116 格。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const LAYOUT := preload("res://scripts/level/LevelLayoutData.gd")
const NAV_GRID := preload("res://scripts/level/NavGrid2D.gd")
const CONTAINERS := preload("res://scripts/level/ContainerRuntime2D.gd")
const TILE := LAYOUT.TILE
const MAP_W := LAYOUT.MAP_W
const MAP_H := LAYOUT.MAP_H
const DOOR_W := LAYOUT.DOOR_W
const HALL_MACHINE_CELL := LAYOUT.HALL_MACHINE_CELL
const ARENA_W := LAYOUT.ARENA_W
const ARENA_H := LAYOUT.ARENA_H
const FLOOR_RECTS: Array[Rect2i] = LAYOUT.FLOOR_RECTS
const ROOM_DEFS: Array[Dictionary] = LAYOUT.ROOM_DEFS
const SPAWNS := LAYOUT.SPAWNS
const EXTRACTS := LAYOUT.EXTRACTS
const RING_PATROLS: Array[Dictionary] = LAYOUT.RING_PATROLS


static func floor_rects() -> Array[Rect2i]:
	return LAYOUT.floor_rects()

## 地板回退到旧版 256×256 地砖；墙面使用新的 128×128 暗色金属墙板。
const FLOOR_TEX := preload("res://assets/art/env/pixel_floor_256.png")
const WALL_TEX := preload("res://assets/art/env/wall_128.png")
## 128 贴图按世界坐标 1:1 重复，两块 64px 面板正好覆盖一个地块。
const WALL_UV_SCALE := 1.0
const SHELF_TEX := preload("res://assets/art/env/pixel_shelf_128.png")
const SHELF_B_TEX := preload("res://assets/art/env/pixel_shelf_128_b.png")
const CRATE_TEX := preload("res://assets/art/env/pixel_crate_48.png")
const BARREL_TEX := preload("res://assets/art/env/pixel_barrel_40.png")
const SHADOW := preload("res://assets/art/fx/shadow_radial.png")
const DOOR_SCRIPT := preload("res://scripts/level/Door2D.gd")

const DECO_ART := CONTAINERS.DECO_ART
const CLOTH_TEX: Array[Texture2D] = CONTAINERS.CLOTH_TEX
const CLOTH_IDS: Array[StringName] = CONTAINERS.CLOTH_IDS
const CONTAINER_BASE_SCALE := CONTAINERS.CONTAINER_BASE_SCALE
const CONTAINER_GROUND := CONTAINERS.CONTAINER_GROUND
const CONTAINER_ART := CONTAINERS.CONTAINER_ART
const CONTAINER_NAMES := CONTAINERS.CONTAINER_NAMES
const RARITY_COMMON := CONTAINERS.RARITY_COMMON
const RARITY_UNCOMMON := CONTAINERS.RARITY_UNCOMMON
const RARITY_RARE := CONTAINERS.RARITY_RARE
const RARITY_EPIC := CONTAINERS.RARITY_EPIC
const RARITY_LEGENDARY := CONTAINERS.RARITY_LEGENDARY
const ADVANCED_GUARANTEE_SAFES: Array[StringName] = CONTAINERS.ADVANCED_GUARANTEE_SAFES

const C_WALL_TINT := Color(1.0, 1.0, 1.0)

@onready var sort_layer: Node2D = get_node("../World2D/SortLayer")
@onready var floor_layer: Node2D = get_node("../World2D/FloorLayer")
@onready var light_layer: Node2D = get_node("../World2D/LightLayer")

var rooms: Array[Dictionary] = []
var doors: Array[Dictionary] = []
var containers: Array[Dictionary] = []
var enemy_spawns: Array[Vector2] = []
var enemy_kinds: Array[StringName] = []

var player_spawn := Vector2(14.0, 51.0) * TILE
var exit_position := Vector2(157.0, 87.0) * TILE
var exit_radius := 58.0
## 本局可用的两个常开撤离点。
var exits: Array[Dictionary] = []
var spawn_id: StringName = &"insertion"
var extract_id: StringName = &"east"
var safe_rooms: Array = []
## 军械库货运电梯：恢复供电后可用，撤离额外 +10%。
var switch_exit_position := Vector2(54.0, 64.0) * TILE
var switch_exit_radius := 60.0
var switch_exit_node: Node2D
## 控制室供电台。
var power_position := Vector2(57.0, 101.0) * TILE
var power_node: Node2D
var power_on := false
## 恢复供电后的单局资源加成；未供电为 1.0。
var bonus_mul := 1.0

var _rng := RandomNumberGenerator.new()
var _switch_label: Label
var _power_lamp: Polygon2D
## 敌人寻路网格子系统（委托至 NavGrid2D）。
var nav_grid: NavGrid2D = NAV_GRID.new()
var _nav_passable := {}
## 歌利亚狂潮竞技场模式：不生成设施房间与墙体。
var arena_mode := false
var _nav_w := MAP_W
var _nav_h := MAP_H


func _ready() -> void:
	add_to_group("nav_level")
	var progress := get_node_or_null("/root/Progress")
	var goliath := progress != null and progress.has_method("map_id") \
		and String(progress.map_id()) == "goliath_arena" \
		and String(progress.run_mode()) == "waves"
	if goliath:
		_build_goliath_arena()
	else:
		generate(randi())
		_build_floor()
		_build_decals()
		_build_walls()
		_build_doors()
		_build_rooms()
		_build_containers()
		_build_power()
		_build_exits()
		# 所有家具与容器摆完后，再合成最终寻路网格。
		_build_nav_grid(_nav_passable)


func map_size() -> Vector2:
	if arena_mode:
		return Vector2(ARENA_W * TILE, ARENA_H * TILE)
	return Vector2(MAP_W * TILE, MAP_H * TILE)


## 小地图/大地图使用的地板格；竞技场只有一整块矩形。
func map_floor_rects() -> Array[Rect2i]:
	if arena_mode:
		var out: Array[Rect2i] = [Rect2i(0, 0, ARENA_W, ARENA_H)]
		return out
	return floor_rects()


## 相机活动范围：包住设施外墙，瞄准前探时不会露出大片黑底。
## 建筑地板范围 x8..167 / y10..109，外墙落在 x7..168 / y9..110。
func camera_bounds() -> Rect2:
	if arena_mode:
		return Rect2(Vector2.ZERO, map_size())
	return Rect2(Vector2(7, 9) * TILE, Vector2(162, 102) * TILE)


func tile_center(tx: float, ty: float) -> Vector2:
	return Vector2((tx + 0.5) * TILE, (ty + 0.5) * TILE)


func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	rooms.clear()
	doors.clear()
	containers.clear()
	enemy_spawns.clear()
	enemy_kinds.clear()
	power_on = false
	bonus_mul = 1.0
	spawn_id = &"insertion"
	extract_id = &"east"
	var progress := get_node_or_null("/root/Progress")
	if progress != null:
		var dep: Dictionary = progress.deployment()
		var sid := StringName(dep.get("spawn", "insertion"))
		if SPAWNS.has(sid):
			spawn_id = sid
		var eid := StringName(dep.get("extract", "east"))
		if EXTRACTS.has(eid):
			extract_id = eid
	if extract_id == &"":
		extract_id = SPAWNS[spawn_id]["default_exit"]
	safe_rooms = SPAWNS[spawn_id]["safe_rooms"]
	player_spawn = Vector2(SPAWNS[spawn_id]["pos"]) * TILE
	exit_position = Vector2(EXTRACTS[extract_id]["pos"]) * TILE
	switch_exit_position = Vector2(54.0, 64.0) * TILE
	power_position = Vector2(57.0, 101.0) * TILE

	for i in ROOM_DEFS.size():
		var def: Dictionary = ROOM_DEFS[i]
		var cell_rect: Rect2i = def["rect"]
		var rect := Rect2(Vector2(cell_rect.position) * TILE, Vector2(cell_rect.size) * TILE)
		var door_cell: Vector2i = def["door_cell"]
		var vertical := bool(def["vertical"])
		var door_pos := Vector2(
			(door_cell.x + 0.5) * TILE,
			(door_cell.y + 0.5) * TILE,
		)
		rooms.append({
			"index": i,
			"type": def["type"],
			"name": def["name"],
			"rect": rect,
			"center": rect.get_center(),
			"door": door_pos,
			"door_vertical": vertical,
			"explored": false,
		})
		# 出生点安全区：附近房间不刷怪。
		if safe_rooms.has(i):
			continue
		for kind in def["roster"]:
			var spawn_pos := _spot_in_room(rect, 2.0)
			if def["type"] == &"hall":
				# 巨型压铸机占着大厅中央，敌人不能刷进机器碰撞体里。
				for _retry in 12:
					if spawn_pos.distance_to(HALL_MACHINE_CELL * TILE) >= 3.5 * TILE:
						break
					spawn_pos = _spot_in_room(rect, 2.0)
			enemy_spawns.append(spawn_pos)
			enemy_kinds.append(kind)

	for patrol in RING_PATROLS:
		var cell: Vector2i = patrol["pos"]
		var patrol_pos := tile_center(cell.x, cell.y)
		# 出生点 16 格内的环廊巡逻也不刷，避免一落地就被围。
		if patrol_pos.distance_to(player_spawn) < 16.0 * TILE:
			continue
		enemy_spawns.append(patrol_pos)
		enemy_kinds.append(patrol["kind"])

	for plan in LAYOUT.LOOT_PLAN:
		var room_index := int(plan["room"])
		var pos: Vector2 = (
			Vector2(plan["pos"]) * TILE if plan.has("pos")
			else _spot_in_room(rooms[room_index]["rect"], 1.5)
		)
		containers.append({
			"room": room_index,
			"position": pos,
			"loot": plan["loot"],
			"art": plan["art"],
			"searched": false,
			"node": null,
		})


func _spot_in_room(rect: Rect2, margin_tiles: float) -> Vector2:
	var margin := margin_tiles * TILE
	return Vector2(
		_rng.randf_range(rect.position.x + margin, rect.end.x - margin),
		_rng.randf_range(rect.position.y + margin, rect.end.y - margin),
	)


func _gap_rect(cell: Vector2i, vertical: bool) -> Rect2i:
	return LAYOUT.gap_rect(cell, vertical)


func _door_gap(def: Dictionary) -> Rect2i:
	return LAYOUT.door_gap(def)


func _arch_gap(cell: Vector2i) -> Rect2i:
	return LAYOUT.arch_gap(cell)


func _all_door_gaps(def: Dictionary) -> Array[Rect2i]:
	return LAYOUT.all_door_gaps(def)


func set_power_on(value: bool) -> void:
	if power_on == value:
		return
	power_on = value
	bonus_mul = 1.2 if value else 1.0
	if _power_lamp != null:
		_power_lamp.color = Color(0.42, 0.96, 0.62) if value else Color(0.95, 0.68, 0.24)
	if switch_exit_node != null:
		switch_exit_node.modulate = Color(1, 1, 1, 1) if value else Color(0.55, 0.55, 0.55, 0.7)
	if _switch_label != null:
		_switch_label.text = "CARGO LIFT // 已供电" if value else "CARGO LIFT // 未供电"
		_switch_label.add_theme_color_override(
			"font_color", Color(0.42, 0.96, 0.72, 0.95) if value else Color(0.82, 0.66, 0.36, 0.85))


# ---------------------------------------------------------------- 地板与墙体

func _build_floor() -> void:
	for rect in floor_rects():
		_floor_rect(Rect2(Vector2(rect.position) * TILE, Vector2(rect.size) * TILE))
	# 门槛也铺地板，避免开门后出现一条黑色缺口。
	for def in ROOM_DEFS:
		for gap in _all_door_gaps(def):
			_floor_rect(Rect2(Vector2(gap.position) * TILE, Vector2(gap.size) * TILE))
		for arch in def.get("arches", []):
			var ag := _arch_gap(arch)
			_floor_rect(Rect2(Vector2(ag.position) * TILE, Vector2(ag.size) * TILE))


func _floor_rect(rect: Rect2) -> void:
	var poly := Polygon2D.new()
	poly.texture = FLOOR_TEX
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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


## 歌利亚狂潮：一整块矩形地板，无房间/门/掩体，仅在外围放不可见边界。
func _build_goliath_arena() -> void:
	arena_mode = true
	_nav_w = ARENA_W
	_nav_h = ARENA_H
	rooms.clear()
	doors.clear()
	containers.clear()
	enemy_spawns.clear()
	enemy_kinds.clear()
	_nav_passable.clear()
	nav_grid.clear()
	safe_rooms = []
	spawn_id = &"insertion"
	extract_id = &"east"
	power_on = false
	bonus_mul = 1.0
	var whole := Rect2(0, 0, ARENA_W * TILE, ARENA_H * TILE)
	rooms.append({
		"index": 0,
		"type": &"arena",
		"name": "歌利亚狂潮",
		"rect": whole,
		"center": whole.get_center(),
		"door": whole.get_center(),
		"door_vertical": false,
		"explored": true,
	})
	player_spawn = Vector2(ARENA_W * 0.5, ARENA_H * 0.72) * TILE
	exit_position = player_spawn
	# 竞技场不提供供电/货运电梯；撤离走浪潮弹窗。
	power_position = Vector2(-100000, -100000)
	switch_exit_position = power_position
	_floor_rect(whole)
	_build_arena_boundaries()
	for y in ARENA_H:
		for x in ARENA_W:
			_nav_passable[Vector2i(x, y)] = true
	_build_arena_spawns()
	_build_nav_grid(_nav_passable)


func _build_arena_boundaries() -> void:
	_arena_boundary(Rect2(-TILE, -TILE, (ARENA_W + 2) * TILE, TILE))
	_arena_boundary(Rect2(-TILE, ARENA_H * TILE, (ARENA_W + 2) * TILE, TILE))
	_arena_boundary(Rect2(-TILE, 0, TILE, ARENA_H * TILE))
	_arena_boundary(Rect2(ARENA_W * TILE, 0, TILE, ARENA_H * TILE))


## 不可见边界：只负责挡住玩家/子弹/敌人，不参与画面。
func _arena_boundary(rect: Rect2) -> void:
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


## 沿竞技场四边布置刷怪点，优先远离玩家，避免整波贴脸。
func _build_arena_spawns() -> void:
	var inset := 3.0
	for x in range(4, ARENA_W - 4, 7):
		enemy_spawns.append(Vector2(x + 0.5, inset + 0.5) * TILE)
		enemy_spawns.append(Vector2(x + 0.5, ARENA_H - inset - 0.5) * TILE)
	for y in range(7, ARENA_H - 7, 7):
		enemy_spawns.append(Vector2(inset + 0.5, y + 0.5) * TILE)
		enemy_spawns.append(Vector2(ARENA_W - inset - 0.5, y + 0.5) * TILE)
	for _i in enemy_spawns.size():
		enemy_kinds.append(&"goliath")


func _build_walls() -> void:
	var floor_cells := {}
	for rect in floor_rects():
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
	for def in ROOM_DEFS:
		for gap in _all_door_gaps(def):
			for y in gap.size.y:
				for x in gap.size.x:
					var cell := Vector2i(gap.position.x + x, gap.position.y + y)
					wall_cells.erase(cell)
					passable[cell] = true
		for arch in def.get("arches", []):
			var ag := _arch_gap(arch)
			for y in ag.size.y:
				for x in ag.size.x:
					var cell := Vector2i(ag.position.x + x, ag.position.y + y)
					wall_cells.erase(cell)
					passable[cell] = true

	_nav_passable = passable
	_merge_walls(wall_cells)


## --- 寻路网格（委托至 NavGrid2D）----------------------------------------------

func _build_nav_grid(passable: Dictionary) -> void:
	nav_grid.build(_nav_w, _nav_h, passable)


func _mark_nav_obstacle(pos: Vector2, size: Vector2) -> void:
	nav_grid.mark_obstacle(pos, size)


func is_nav_walkable(world_pos: Vector2) -> bool:
	return nav_grid.is_walkable(world_pos)


func find_nav_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	return nav_grid.find_path(from_world, to_world)


## 贪心合并成较大的矩形，避免每个墙格一个 StaticBody2D。
func _merge_walls(wall_cells: Dictionary) -> void:
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
		_wall_rect(Rect2(Vector2(cell) * TILE, Vector2(w, h) * TILE))


func _wall_rect(rect: Rect2) -> void:
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
	slab.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_add_light_occluder(body, Rect2(Vector2(0, -rect.size.y), rect.size))


## 给墙体/家具添加 2D 光照遮挡多边形（局部坐标）。
func _add_light_occluder(parent: Node2D, rect: Rect2) -> void:
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


func _build_decals() -> void:
	for i in 56:
		var rect := FLOOR_RECTS[_rng.randi_range(0, FLOOR_RECTS.size() - 1)]
		var pos := Vector2(
			_rng.randf_range(rect.position.x + 0.5, rect.end.x - 0.5) * TILE,
			_rng.randf_range(rect.position.y + 0.5, rect.end.y - 0.5) * TILE,
		)
		if _rng.randf() < 0.4:
			_paper(pos)
		else:
			_decal(pos, Vector2(_rng.randf_range(26, 52), _rng.randf_range(16, 30)),
				Color(0.24, 0.08, 0.07, _rng.randf_range(0.14, 0.3)))
	for room in rooms:
		var rect: Rect2 = room["rect"]
		for k in 2:
			_decal(_spot_in_room(rect, 1.0), Vector2(30, 18), Color(0.06, 0.06, 0.06, 0.22))


func _decal(pos: Vector2, size: Vector2, color: Color) -> void:
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


func _paper(pos: Vector2) -> void:
	var sheet := Polygon2D.new()
	sheet.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(14, -3), Vector2(17, 9), Vector2(3, 12),
	])
	sheet.color = Color(0.72, 0.70, 0.63, 0.55)
	sheet.position = pos
	floor_layer.add_child(sheet)


# ---------------------------------------------------------------- 门

func _build_doors() -> void:
	# 主门先全部建完，保证 doors[房间号] 的索引稳定（视角/测试都依赖）。
	for i in rooms.size():
		var room := rooms[i]
		var def: Dictionary = ROOM_DEFS[i]
		room["door_node"] = _spawn_door(room["door"], bool(def["vertical"]), i)
	# 侧门让穿堂房间有两个入口，绕后包夹时不用再走回主门。
	for i in rooms.size():
		var def: Dictionary = ROOM_DEFS[i]
		for extra in def.get("extra_doors", []):
			var cell: Vector2i = extra["cell"]
			_spawn_door(
				Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE),
				bool(extra["vertical"]), i, true)


func _spawn_door(pos: Vector2, vertical: bool, room_index: int, extra := false) -> Node2D:
	var door := Node2D.new()
	door.set_script(DOOR_SCRIPT)
	door.position = pos
	door.width = DOOR_W * TILE
	if vertical:
		door.rotation = PI * 0.5
	sort_layer.add_child(door)
	doors.append({"room": room_index, "node": door, "open": false, "extra": extra})
	return door


# ---------------------------------------------------------------- 房间陈设

func _build_rooms() -> void:
	for i in rooms.size():
		_populate_room(rooms[i], ROOM_DEFS[i])
		_decorate_room(rooms[i], ROOM_DEFS[i])
		_room_label(rooms[i])
	# 走廊拐角和瓶颈处放少量掩体，长距离对枪时有可利用的落点。
	for corner in [Vector2(39, 17), Vector2(39, 102), Vector2(139, 36), Vector2(139, 90)]:
		_barrel_prop(Vector2(corner) * TILE)
	for spot in [Vector2(48, 36), Vector2(124, 36), Vector2(48, 72), Vector2(124, 72)]:
		_barrel_prop(Vector2(spot) * TILE)


## 房间名印在地板上，俯视时不用打开地图也能知道自己在哪个区。
func _room_label(room: Dictionary) -> void:
	var rect: Rect2 = room["rect"]
	var label := Label.new()
	label.text = String(room["name"])
	label.position = Vector2(rect.position.x + 12, rect.position.y + 8)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.88, 0.64, 0.32, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	sort_layer.add_child(label)


func _populate_room(room: Dictionary, def: Dictionary) -> void:
	var rect: Rect2 = room["rect"]
	var type: StringName = room["type"]
	var placed: Array[Vector2] = []
	var count := int(def.get("props", 3))
	for attempt in count * 4:
		if placed.size() >= count:
			break
		var pos := _spot_in_room(rect, 1.3)
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
				_shelf_prop(pos, attempt % 3 == 0) if attempt % 4 == 0 else _crate_prop(pos)
			&"medical":
				_bed_prop(pos) if attempt % 2 == 0 else _locker_prop(pos)
			&"armory":
				_locker_prop(pos) if attempt % 3 == 0 else _crate_prop(pos)
			&"control":
				_console_prop(pos) if attempt % 2 == 0 else _shelf_prop(pos, false)
			&"nest":
				_pod_prop(pos) if attempt % 2 == 0 else _crate_prop(pos)
			&"aux":
				_console_prop(pos) if attempt % 3 == 0 else _shelf_prop(pos, false)
			&"workshop":
				_shelf_prop(pos, attempt % 2 == 0) if attempt % 3 == 0 else _barrel_prop(pos)
			&"abandoned":
				_crate_prop(pos) if attempt % 2 == 0 else _barrel_prop(pos)
			&"extraction":
				_barrel_prop(pos) if attempt % 2 == 0 else _crate_prop(pos)
			&"refinery":
				_generator_prop(pos) if attempt % 2 == 0 else _barrel_prop(pos)
			&"foundry":
				_generator_prop(pos) if attempt % 2 == 0 else _crate_prop(pos)
			&"substation":
				_console_prop(pos) if attempt % 2 == 0 else _locker_prop(pos)
			&"qc":
				_console_prop(pos) if attempt % 2 == 0 else _shelf_prop(pos, true)
			&"locker":
				_locker_prop(pos) if attempt % 2 == 0 else _crate_prop(pos)
			&"vent":
				_barrel_prop(pos) if attempt % 2 == 0 else _shelf_prop(pos, false)
			&"break_room", &"canteen":
				_table_prop(pos) if attempt % 2 == 0 else _locker_prop(pos)
			&"hall":
				_crate_prop(pos) if attempt % 2 == 0 else _barrel_prop(pos)
			_:
				_crate_prop(pos)


func _prop_body(pos: Vector2, size: Vector2, color: Color, accent: Color) -> StaticBody2D:
	_mark_nav_obstacle(pos, size)
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)

	_shadow(body, Vector2(size.x * 1.1, size.y * 0.5), Vector2(0, size.y * 0.28), 0.4)
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
	_add_light_occluder(body, Rect2(-size * 0.5, size))
	return body


func _detail(parent: Node2D, rect: Rect2, color: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	])
	poly.color = color
	parent.add_child(poly)


func _shadow(parent: Node, size: Vector2, offset: Vector2, alpha: float) -> void:
	var shadow := Sprite2D.new()
	shadow.texture = SHADOW
	shadow.scale = Vector2(size.x / 200.0, size.y / 200.0)
	shadow.position = offset
	shadow.modulate = Color(0.02, 0.02, 0.02, alpha)
	parent.add_child(shadow)


func _shelf_prop(pos: Vector2, variant: bool) -> void:
	_mark_nav_obstacle(pos + Vector2(0, 16), Vector2(128, 58))
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	_shadow(body, Vector2(126, 50), Vector2(0, 34), 0.42)
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


func _crate_prop(pos: Vector2) -> void:
	_mark_nav_obstacle(pos + Vector2(0, 2), Vector2(44, 38))
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	_shadow(body, Vector2(44, 20), Vector2(0, 10), 0.42)
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


func _barrel_prop(pos: Vector2) -> void:
	_mark_nav_obstacle(pos, Vector2(36, 36))
	var body := StaticBody2D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 2
	sort_layer.add_child(body)
	_shadow(body, Vector2(38, 18), Vector2(0, 8), 0.4)
	var sprite := Sprite2D.new()
	sprite.texture = BARREL_TEX
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(sprite)
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)


func _bed_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(96, 152), Color(0.22, 0.24, 0.29), Color(0.42, 0.46, 0.52))
	_detail(body, Rect2(-40, -62, 80, 40), Color(0.55, 0.56, 0.55))
	_detail(body, Rect2(-40, -18, 80, 4), Color(0.14, 0.16, 0.20))


func _locker_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(58, 74), Color(0.26, 0.28, 0.31), Color(0.44, 0.47, 0.5))
	_detail(body, Rect2(-4, -30, 3, 60), Color(0.16, 0.17, 0.19))
	_detail(body, Rect2(16, -4, 8, 8), Color(0.72, 0.60, 0.24))


func _console_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(104, 58), Color(0.18, 0.20, 0.23), Color(0.36, 0.40, 0.44))
	_detail(body, Rect2(-44, -22, 88, 30), Color(0.16, 0.42, 0.55))
	_detail(body, Rect2(-38, -16, 30, 4), Color(0.45, 0.78, 0.92))
	_detail(body, Rect2(-38, -8, 52, 3), Color(0.35, 0.62, 0.74))


func _generator_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(112, 78), Color(0.24, 0.25, 0.24), Color(0.42, 0.42, 0.4))
	_detail(body, Rect2(-46, -28, 92, 12), Color(0.70, 0.48, 0.16))
	var hub := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		points.append(Vector2(cos(a) * 18, sin(a) * 18 + 12))
	hub.polygon = points
	hub.color = Color(0.16, 0.17, 0.18)
	body.add_child(hub)


func _pod_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(88, 96), Color(0.14, 0.18, 0.15), Color(0.32, 0.42, 0.30))
	var glow := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		points.append(Vector2(cos(a) * 26, sin(a) * 34))
	glow.polygon = points
	glow.color = Color(0.35, 0.62, 0.36, 0.75)
	body.add_child(glow)


## 休息区/食堂的长条桌。
func _table_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(118, 54), Color(0.30, 0.27, 0.23), Color(0.48, 0.43, 0.35))
	_detail(body, Rect2(-52, -20, 104, 16), Color(0.38, 0.34, 0.28))
	_detail(body, Rect2(-44, 4, 30, 3), Color(0.20, 0.18, 0.16))
	_detail(body, Rect2(14, 4, 30, 3), Color(0.20, 0.18, 0.16))


## 主装配大厅的巨型压铸机：占地大，兼作掩体。
func _machine_prop(pos: Vector2) -> void:
	var body := _prop_body(pos, Vector2(228, 150), Color(0.20, 0.21, 0.21), Color(0.40, 0.41, 0.39))
	_detail(body, Rect2(-96, -58, 192, 22), Color(0.62, 0.42, 0.14))
	_detail(body, Rect2(-96, -14, 192, 10), Color(0.13, 0.14, 0.14))
	_detail(body, Rect2(-70, 26, 140, 30), Color(0.16, 0.17, 0.17))
	var hub := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		points.append(Vector2(cos(a) * 30, sin(a) * 30 + 22))
	hub.polygon = points
	hub.color = Color(0.34, 0.36, 0.35)
	body.add_child(hub)


func _deco_prop(pos: Vector2, art_id: StringName) -> void:
	CONTAINERS.spawn_deco_prop(sort_layer, containers, pos, art_id, Callable(self, "_mark_nav_obstacle"))


func _coat_prop(pos: Vector2, tex: Texture2D, art_id: StringName) -> void:
	CONTAINERS.spawn_coat_prop(sort_layer, containers, pos, tex, art_id, Callable(self, "_mark_nav_obstacle"))


## 按房间类型摆放装饰物，位置贴墙，避开随机陈设。
func _decorate_room(room: Dictionary, def: Dictionary) -> void:
	var rect: Rect2 = room["rect"]
	var type: StringName = def["type"]
	var inner := Vector2(1.1 * TILE, 1.1 * TILE)
	var top_left := rect.position + inner
	var top_right := rect.position + Vector2(rect.size.x - inner.x, inner.y)
	var bottom_left := rect.position + Vector2(inner.x, rect.size.y - inner.y)
	match type:
		&"insertion":
			_deco_prop(top_right + Vector2(-TILE, TILE), &"trunk_storage")
			_deco_prop(bottom_left + Vector2(0, -TILE), &"case_trolley_black")
		&"storage":
			_deco_prop(bottom_left + Vector2(0, -TILE * 2), &"material_case")
		&"medical":
			_deco_prop(top_right + Vector2(-TILE * 2, TILE), &"medcrate_large")
		&"armory":
			_deco_prop(top_left + Vector2(TILE, TILE), &"tactical_case")
		&"aux":
			_deco_prop(top_right + Vector2(-TILE * 2, TILE), &"box_document")
		&"refinery":
			_deco_prop(top_left + Vector2(TILE, TILE), &"material_case")
		&"foundry":
			_deco_prop(bottom_left + Vector2(0, -TILE * 2), &"trunk_storage")
		&"abandoned":
			_deco_prop(top_left + Vector2(TILE, TILE), &"case_luggage_black")
		&"canteen":
			_deco_prop(top_right + Vector2(-TILE * 2, TILE), &"case_luggage_green")
		&"break_room":
			_deco_prop(bottom_left + Vector2(0, -TILE * 2), &"case_trolley")
		&"hall":
			# 巨型压铸机固定在大厅中央，作为核心地标和掩体。
			_machine_prop(HALL_MACHINE_CELL * TILE)
			_deco_prop(top_left + Vector2(TILE * 4, TILE), &"material_case")
			_deco_prop(top_right + Vector2(-TILE * 5, TILE), &"material_case")
			_deco_prop(bottom_left + Vector2(TILE * 4, -TILE), &"trunk_storage")
		&"locker":
			for i in CLOTH_TEX.size():
				var px := rect.position.x + (2.4 + i * 2.6) * TILE
				_coat_prop(Vector2(px, rect.position.y + 1.6 * TILE), CLOTH_TEX[i], CLOTH_IDS[i])


func _build_containers() -> void:
	CONTAINERS.build_containers(sort_layer, containers)


## 容器外观表查询，供开箱后切换到开启贴图。
func container_art(id: StringName) -> Dictionary:
	return CONTAINERS.container_art(id)


## 容器显示名；未知外观退回通用补给箱名。
func container_display_name(id: StringName) -> String:
	return CONTAINERS.display_name(id)


## 稀有度配色：保险箱与高价值箱子用更亮的颜色区分。
func container_rarity_color(id: StringName) -> Color:
	return CONTAINERS.rarity_color(id)


## 是否为保底进阶材料的保险箱（小型保险箱除外）。
func container_guarantees_advanced(id: StringName) -> bool:
	return CONTAINERS.guarantees_advanced(id)


## 只让目标容器显示悬浮提示；已搜刮的容器显示“已搜索”，index < 0 时全部隐藏。
func set_container_hint(index: int, searched := false) -> void:
	CONTAINERS.set_container_hint(containers, index, searched)


## 浪潮模式每 5 波刷新补给：所有容器恢复未搜刮，外观回到关闭态。
func refresh_containers() -> void:
	CONTAINERS.refresh_containers(containers)


## 悬浮提示轻微上下浮动，提示“可交互”而不是固定标签。
func _process(_delta: float) -> void:
	CONTAINERS.animate_hints(containers)


# ---------------------------------------------------------------- 目标与撤离

func _build_power() -> void:
	power_node = _prop_body(power_position, Vector2(120, 64),
		Color(0.18, 0.21, 0.24), Color(0.45, 0.50, 0.55))
	_detail(power_node, Rect2(-50, -24, 100, 30), Color(0.12, 0.32, 0.40))
	_detail(power_node, Rect2(-42, -16, 34, 4), Color(0.45, 0.78, 0.92))
	_detail(power_node, Rect2(-42, -8, 54, 3), Color(0.35, 0.62, 0.74))
	_power_lamp = Polygon2D.new()
	_power_lamp.polygon = PackedVector2Array([
		Vector2(34, -18), Vector2(46, -18), Vector2(46, -6), Vector2(34, -6),
	])
	_power_lamp.color = Color(0.95, 0.68, 0.24)
	power_node.add_child(_power_lamp)

	var label := Label.new()
	label.text = "POWER // 供电"
	label.position = Vector2(-56, -86)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.74, 0.38, 0.9))
	power_node.add_child(label)


func _build_exits() -> void:
	exits.clear()
	for id in EXTRACTS:
		var def: Dictionary = EXTRACTS[id]
		var pos := Vector2(def["pos"]) * TILE
		var node := _exit_visual(pos, Color(0.16, 0.72, 0.62),
			"EXTRACTION // %s" % String(def["name"]), true)
		exits.append({"id": id, "name": def["name"], "position": pos, "node": node})
	switch_exit_node = _exit_visual(switch_exit_position, Color(0.92, 0.62, 0.20),
		"CARGO LIFT // 未供电", false)
	switch_exit_node.modulate = Color(0.55, 0.55, 0.55, 0.7)


func _exit_visual(pos: Vector2, color: Color, text: String, is_direct: bool) -> Node2D:
	var node := Node2D.new()
	node.name = "Extraction" if is_direct else "CargoLift"
	node.position = pos
	sort_layer.add_child(node)

	var halo := Sprite2D.new()
	halo.texture = SHADOW
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
	if not is_direct:
		_switch_label = label
	return node
