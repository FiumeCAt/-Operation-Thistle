extends Node
class_name Level2D

## 俯视 2D 关卡：单层工业巨构 K-17 协调入口。
## 几何数据、寻路网格、容器运行时、场景构建器与房间陈设分别委托至：
## LevelLayoutData / NavGrid2D / ContainerRuntime2D / LevelBuilder2D / LevelProps2D。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const LAYOUT := preload("res://scripts/level/LevelLayoutData.gd")
const NAV_GRID := preload("res://scripts/level/NavGrid2D.gd")
const CONTAINERS := preload("res://scripts/level/ContainerRuntime2D.gd")
const BUILDER := preload("res://scripts/level/LevelBuilder2D.gd")
const PROPS := preload("res://scripts/level/LevelProps2D.gd")

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


static func floor_rects() -> Array[Rect2i]:
	return LAYOUT.floor_rects()


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
## 真正阻挡视线的实心家具矩形（与 LightOccluder2D 一一对应；低矮油桶/木箱/补给箱不阻挡视线）。
var _sight_rects: Array[Rect2] = []
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
		BUILDER.build_floor(floor_layer)
		BUILDER.build_decals(floor_layer, rooms, _rng)
		_nav_passable = BUILDER.build_walls(floor_layer, sort_layer)
		_sight_rects.clear()
		BUILDER.build_doors(sort_layer, rooms, doors)
		PROPS.build_rooms({
			"sort_layer": sort_layer,
			"rooms": rooms,
			"containers": containers,
			"rng": _rng,
			"mark_obstacle": Callable(self, "_mark_nav_obstacle"),
			"mark_sight_obstacle": Callable(self, "_mark_sight_obstacle"),
			"player_spawn": player_spawn,
			"exit_position": exit_position,
			"power_position": power_position,
			"switch_exit_position": switch_exit_position,
		})
		CONTAINERS.build_containers(sort_layer, containers)
		var power := BUILDER.build_power(sort_layer, power_position, Callable(self, "_mark_nav_obstacle"))
		power_node = power["node"]
		_power_lamp = power["lamp"]
		var built_exits := BUILDER.build_exits(sort_layer, exits, switch_exit_position, exit_radius)
		switch_exit_node = built_exits["switch_exit_node"]
		_switch_label = built_exits["switch_label"]
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
			var spawn_pos := PROPS.spot_in_room(_rng, rect, 2.0)
			if def["type"] == &"hall":
				# 巨型压铸机占着大厅中央，敌人不能刷进机器碰撞体里。
				for _retry in 12:
					if spawn_pos.distance_to(HALL_MACHINE_CELL * TILE) >= 3.5 * TILE:
						break
					spawn_pos = PROPS.spot_in_room(_rng, rect, 2.0)
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
			else PROPS.spot_in_room(_rng, rooms[room_index]["rect"], 1.5)
		)
		containers.append({
			"room": room_index,
			"position": pos,
			"loot": plan["loot"],
			"art": plan["art"],
			"searched": false,
			"node": null,
		})


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
	BUILDER.build_floor_rect(floor_layer, whole)
	BUILDER.build_arena_boundaries(sort_layer)
	for y in ARENA_H:
		for x in ARENA_W:
			_nav_passable[Vector2i(x, y)] = true
	_build_arena_spawns()
	_build_nav_grid(_nav_passable)


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


## --- 寻路网格（委托至 NavGrid2D）----------------------------------------------

func _build_nav_grid(passable: Dictionary) -> void:
	nav_grid.build(_nav_w, _nav_h, passable)


func _mark_nav_obstacle(pos: Vector2, size: Vector2) -> void:
	nav_grid.mark_obstacle(pos, size)


func _mark_sight_obstacle(pos: Vector2, size: Vector2) -> void:
	# 略微内缩 4px，与 LightOccluder2D 柔和阴影边缘一致，避免贴家具边缘时敌人突然消失。
	var inset := Vector2(minf(size.x * 0.12, 6.0), minf(size.y * 0.12, 6.0))
	var inner := size - inset * 2.0
	if inner.x > 2.0 and inner.y > 2.0:
		_sight_rects.append(Rect2(pos - inner * 0.5, inner))


func is_nav_walkable(world_pos: Vector2) -> bool:
	return nav_grid.is_walkable(world_pos)


## 视线判定专用：仅墙体与挂有 LightOccluder2D 的高大家具阻挡视线；
## 无遮光体的油桶、木箱、货架与补给箱不会在明亮清晰视野里把敌人凭空隐藏。
func is_sight_clear(world_pos: Vector2) -> bool:
	if arena_mode:
		return true
	if _nav_passable.is_empty():
		return is_nav_walkable(world_pos)
	var cell := Vector2i(int(floor(world_pos.x / TILE)), int(floor(world_pos.y / TILE)))
	if not _nav_passable.has(cell):
		return false
	for rect in _sight_rects:
		if rect.has_point(world_pos):
			return false
	return true


func find_nav_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	return nav_grid.find_path(from_world, to_world)


## --- 容器接口（委托至 ContainerRuntime2D）-------------------------------------

func container_art(id: StringName) -> Dictionary:
	return CONTAINERS.container_art(id)


func container_display_name(id: StringName) -> String:
	return CONTAINERS.display_name(id)


func container_rarity_color(id: StringName) -> Color:
	return CONTAINERS.rarity_color(id)


func container_guarantees_advanced(id: StringName) -> bool:
	return CONTAINERS.guarantees_advanced(id)


func set_container_hint(index: int, searched := false) -> void:
	CONTAINERS.set_container_hint(containers, index, searched)


func refresh_containers() -> void:
	CONTAINERS.refresh_containers(containers)


func _process(_delta: float) -> void:
	CONTAINERS.animate_hints(containers)
