extends SceneTree
## M5：未探索房间遮罩与探索揭示。

var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		print("  [ok] ", message)
	else:
		_fails += 1
		push_error("  [FAIL] " + message)

func _frames(count := 4) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	print("=== Operation Thistle occlusion test ===")
	var level := LevelGenerator.new()
	level.level_seed = 5150
	level.depth = 1
	root.add_child(level)
	await _frames(8)

	_check(level.rooms.size() == 5, "第一层生成 5 个房间")
	_check(level.room_fog.size() == level.rooms.size(), "每个房间都有未知遮罩")
	_check(level.room_fog_labels.size() == level.rooms.size(), "每个遮罩都有未探索标记")
	_check(level.explored.is_empty(), "开局没有已探索房间")
	var first: MeshInstance3D = level.room_fog[0]
	_check(first.visible, "未探索房间初始被遮罩")
	_check(level.room_fog_labels[0].text == "未探索", "标记文本为未探索")
	var box := first.mesh as BoxMesh
	_check(box != null and box.size.y < 0.5, "遮罩是薄顶板，不会形成黑墙")
	_check(first.position.y < LevelGenerator.H, "顶板低于墙顶，侧面由墙体遮挡")
	var has_collision := false
	for child in first.get_children():
		if child is CollisionObject3D:
			has_collision = true
	_check(not has_collision, "遮罩没有碰撞，不影响导航与射线")

	var center: Vector3 = level.rooms[0]["center"]
	level.explore(center)
	_check(level.explored.has(0) and level.explored.size() == 1, "进入房间后记录探索")
	_check(not level.room_fog_labels[0].visible, "探索后立即隐藏未探索标记")
	_check(not level.room_fog[0].visible, "探索后遮罩立即隐藏")
	_check(level.room_fog[1].visible and level.room_fog_labels[1].visible, "其他房间仍保持未知")

	level.explore(center)
	_check(level.explored.size() == 1, "重复进入不会重复揭示")

	level.free()
	await _frames(2)
	print("=== OCCLUSION %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	quit(0 if _fails == 0 else 1)
