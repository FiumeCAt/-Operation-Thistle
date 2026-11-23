extends SceneTree
## NavGrid2D 独立单元测试：验证 A* 建网、障碍格标记、贴墙回退、拐角绕行与路径拉直。
## godot --headless --path . --script res://tests/nav_grid_2d_test.gd

const NAV_GRID := preload("res://scripts/level/NavGrid2D.gd")
const TILE := 64.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _run() -> void:
	var nav: NavGrid2D = NAV_GRID.new()
	_check(not nav.is_walkable(Vector2(100, 100)) and nav.find_path(Vector2.ZERO, Vector2(200, 200)).is_empty(),
		"unbuilt NavGrid2D safely returns non-walkable and empty path")

	# 搭建 10x10 房间，中间竖着一道墙 (x=5, y=0..7)，只在 y=8..9 留通道
	var passable := {}
	for y in 10:
		for x in 10:
			if x == 5 and y <= 7:
				continue
			passable[Vector2i(x, y)] = true

	# 在 (2, 2) 放置一个 64x64 障碍物
	nav.mark_obstacle(Vector2(2.5 * TILE, 2.5 * TILE), Vector2(TILE, TILE))
	nav.build(10, 10, passable)

	_check(nav.is_walkable(Vector2(1.5 * TILE, 1.5 * TILE)), "open floor cell is walkable")
	_check(not nav.is_walkable(Vector2(5.5 * TILE, 3.5 * TILE)), "wall cell is solid")
	_check(not nav.is_walkable(Vector2(2.5 * TILE, 2.5 * TILE)), "marked obstacle cell is solid")

	# 直线空旷路径会被 smooth_path 拉直成 2 个点（起点和终点）
	var straight := nav.find_path(Vector2(0.5 * TILE, 0.5 * TILE), Vector2(4.5 * TILE, 0.5 * TILE))
	_check(straight.size() == 2, "open straight path smooths down to 2 endpoints (%d)" % straight.size())

	# 绕墙路径：从墙左 (2, 1) 到墙右 (8, 1) 必须绕行南侧 y>=8 通道且所有点均可行走
	var detour := nav.find_path(Vector2(2.5 * TILE, 1.5 * TILE), Vector2(8.5 * TILE, 1.5 * TILE))
	var max_y := 0.0
	var all_ok := detour.size() >= 3
	for pt in detour:
		max_y = maxf(max_y, pt.y)
		if not nav.is_walkable(pt):
			all_ok = false
	_check(all_ok and max_y >= 8.0 * TILE, "detour path routes through gap at y>=8 and stays walkable")

	# 起点略微贴墙（落在实心格 (5, 3)）也能向外吸附到邻近可行走格继续寻路
	var nudged := nav.find_path(Vector2(5.5 * TILE, 3.5 * TILE), Vector2(8.5 * TILE, 3.5 * TILE))
	_check(nudged.size() >= 2, "nearest_walkable_cell recovers path when start is inside wall edge")

	# 完全封闭孤岛：超出 radius=3 或不可达返回空路径
	var island := {Vector2i(0, 0): true, Vector2i(9, 9): true}
	nav.clear()
	nav.build(10, 10, island)
	_check(nav.find_path(Vector2(32, 32), Vector2(9.5 * TILE, 9.5 * TILE)).is_empty(),
		"unreachable island target returns empty path")

	print("\n=== nav grid 2d: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
