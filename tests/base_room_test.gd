extends SceneTree
## 基地房间回归：进入行动后基地墙体/摆件必须完全退出碰撞，否则会变成空气墙。

var _checks := 0
var _fails := 0
var _main

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("[FAIL] " + label)

func _frames(n := 4) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	print("=== Operation Thistle base room test ===")
	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(8)
	_main = current_scene
	_check(_main.in_base and _main.base_root != null, "启动进入基地并生成房间")
	_check(_count_live_colliders(_main.base_root) > 0, "基地墙体与摆件带碰撞")

	_main.start_expedition()
	await _frames(24)
	_check(not _main.in_base and not _main.base_root.visible, "进入行动后基地隐藏")
	_check(_count_live_colliders(_main.base_root) == 0, "进入行动后基地碰撞全部关闭")

	var space: PhysicsDirectSpaceState3D = _main.get_world_3d().direct_space_state
	var from: Vector3 = _main.level.player_spawn + Vector3(0, 0.9, 0)
	var clear := true
	for dist in [2.0, 4.0, 8.0, 12.0]:
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(dist, 0, 0), 1)
		if not space.intersect_ray(query).is_empty():
			clear = false
	_check(clear, "出生点向右走廊无可阻挡墙体")

	_main.return_to_base()
	await _frames(4)
	_check(_main.in_base and _main.base_root.visible and _count_live_colliders(_main.base_root) > 0,
		"回到基地后碰撞恢复")

	print("=== BASE ROOM %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	quit(0 if _fails == 0 else 1)

func _count_live_colliders(node: Node) -> int:
	var total := 0
	if node is CollisionObject3D and (node as CollisionObject3D).collision_layer != 0:
		total += 1
	for child in node.get_children():
		total += _count_live_colliders(child)
	return total
