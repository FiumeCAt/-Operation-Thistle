extends SceneTree
## EnemyPerception2D 独立单元测试：验证扇形视野几何、近身察觉、盲眼单位、朝向扫视与路径缓存。
## godot --headless --path . --script res://tests/enemy_perception_test.gd

const ENEMY_DEF := preload("res://scripts/actors/enemy/EnemyDef.gd")
const PERCEPTION := preload("res://scripts/actors/enemy/EnemyPerception2D.gd")

var _pass := 0
var _fail := 0


class StubNavLevel extends RefCounted:
	var calls := 0
	var path := PackedVector2Array()

	func find_nav_path(_from: Vector2, _to: Vector2) -> PackedVector2Array:
		calls += 1
		return path


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
	var rifle: EnemyDef = ENEMY_DEF.from_dict(&"rifleman", EnemyDB.stats(&"rifleman"))
	var blind_hunter: EnemyDef = ENEMY_DEF.from_dict(&"hunter", EnemyDB.stats(&"hunter"))
	var p: EnemyPerception2D = PERCEPTION.new()
	p.init_view(0.0, rifle.default_view_angle())

	# 1. 扇形视野、近身察觉、盲眼与距离上限
	_check(p.is_in_vision_cone(Vector2.ZERO, Vector2(320, 0), rifle),
		"front target within range is inside vision cone")
	_check(not p.is_in_vision_cone(Vector2.ZERO, Vector2(-320, 0), rifle),
		"back target beyond close-aware radius is outside cone")
	_check(p.is_in_vision_cone(Vector2.ZERO, Vector2(-120, 0), rifle),
		"point-blank back target triggers close-aware radius")
	_check(not p.is_in_vision_cone(Vector2.ZERO, Vector2(1200, 0), rifle),
		"target beyond view_range is excluded")
	_check(not p.is_in_vision_cone(Vector2.ZERO, Vector2(64, 0), blind_hunter),
		"blind unit never detects via vision cone")

	# 2. 朝向转向与原地扫视
	var body := CharacterBody2D.new()
	root.add_child(body)
	body.global_position = Vector2.ZERO
	p.view_dir = Vector2.RIGHT
	p.update_view_direction(body, "patrol", null, Vector2.ZERO, false, 0.25)
	_check(p.view_dir.angle() > 0.1, "idle patrol sweeps vision cone")

	p.view_dir = Vector2.RIGHT
	p.update_view_direction(body, "search", null, Vector2(0, 300), false, 0.2)
	_check(p.view_dir.y > 0.2, "search state turns view toward last_known")

	# 3. 寻路路径缓存与路径点推进
	var stub := StubNavLevel.new()
	stub.path = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var dir1 := p.chase_dir(body, stub, Vector2(100, 100))
	var dir2 := p.chase_dir(body, stub, Vector2(100, 100))
	_check(stub.calls == 1 and dir1.x > 0.99 and dir2.x > 0.99,
		"chase_dir caches nav path within repath cooldown")
	body.global_position = Vector2(95, 0)
	var dir3 := p.chase_dir(body, stub, Vector2(100, 100))
	_check(dir3.y > 0.9, "chase_dir advances to next waypoint upon arrival")

	body.queue_free()
	await process_frame
	print("\n=== enemy perception: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
