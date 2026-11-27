extends RefCounted
class_name NavGrid2D
## 2D 关卡 A* 寻路网格子系统：管理可行走格、家具/容器障碍格、贴墙最近可行走点与直线路径拉直。
## 从 Level2D 抽离，可完全脱离场景树独立单测。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE

var astar := AStarGrid2D.new()
var ready := false
var width := 0
var height := 0
var passable: Dictionary = {}
var blocked: Dictionary = {}


func clear() -> void:
	ready = false
	passable.clear()
	blocked.clear()


## 把带碰撞的家具/箱子所占格标记为寻路障碍。
func mark_obstacle(pos: Vector2, size: Vector2) -> void:
	var min_x := int(floor((pos.x - size.x * 0.5) / TILE))
	var min_y := int(floor((pos.y - size.y * 0.5) / TILE))
	var max_x := int(floor((pos.x + size.x * 0.5 - 0.01) / TILE))
	var max_y := int(floor((pos.y + size.y * 0.5 - 0.01) / TILE))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			blocked[Vector2i(x, y)] = true


## 用 AStarGrid2D 建立整图寻路网格：passable 为可走，其余（含 blocked 障碍）为实心。
func build(grid_w: int, grid_h: int, passable_cells: Dictionary) -> void:
	width = grid_w
	height = grid_h
	passable = passable_cells
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(TILE, TILE)
	# 让路径点落在格子中心，而不是格子左上角。
	astar.offset = Vector2(TILE, TILE) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	astar.fill_solid_region(Rect2i(0, 0, width, height), true)
	for cell in passable_cells:
		if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height:
			astar.set_point_solid(cell, false)
	for cell in blocked:
		if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height:
			astar.set_point_solid(cell, true)
	ready = true


## 世界坐标是否落在可行走格内。
func is_walkable(world_pos: Vector2) -> bool:
	if not ready or width <= 0 or height <= 0:
		return false
	var cell := world_to_cell(world_pos)
	return not astar.is_point_solid(cell)


## 返回世界坐标路径（含起点与终点）；无路可走时为空。
func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	if not ready:
		return PackedVector2Array()
	var from_cell := nearest_walkable_cell(world_to_cell(from_world), 3)
	var to_cell := nearest_walkable_cell(world_to_cell(to_world), 3)
	if from_cell.x < 0 or to_cell.x < 0:
		return PackedVector2Array()
	var points: PackedVector2Array = astar.get_point_path(from_cell, to_cell)
	if points.size() < 2:
		return points
	return smooth_path(points)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(floor(world_pos.x / TILE)), 0, width - 1),
		clampi(int(floor(world_pos.y / TILE)), 0, height - 1),
	)


## 起点/终点贴墙时，向外找最近的可行走格。
func nearest_walkable_cell(cell: Vector2i, radius: int) -> Vector2i:
	if not astar.is_point_solid(cell):
		return cell
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var probe := cell + Vector2i(dx, dy)
				if probe.x < 0 or probe.y < 0 or probe.x >= width or probe.y >= height:
					continue
				if not astar.is_point_solid(probe):
					return probe
	return Vector2i(-1, -1)


## 拉直路径：只保留能直线走到的拐点，减少格子中心的锯齿感。
func smooth_path(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(points[0])
	var anchor := 0
	while anchor < points.size() - 1:
		var next := points.size() - 1
		while next > anchor + 1 and not line_clear(points[anchor], points[next]):
			next -= 1
		out.append(points[next])
		anchor = next
	return out


func line_clear(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	if dist < 1.0:
		return is_walkable(a)
	var perp := ((b - a) / dist).orthogonal() * 14.0
	var steps := maxi(1, int(ceil(dist / 20.0)))
	for i in steps + 1:
		var pt := a.lerp(b, float(i) / float(steps))
		if not is_walkable(pt):
			return false
		if i > 0 and i < steps:
			if not is_walkable(pt + perp) or not is_walkable(pt - perp):
				return false
	return true
