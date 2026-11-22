extends SceneTree
## 游戏内演示录像：把四台新敌人放到主环廊，自动索敌开火，录一段实机画面。
## 用法：
## godot --path . --write-movie screenshots/enemy_demo.avi --fixed-fps 30 \
##   --script res://tests/record_enemies.gd

const FPS := 30.0
const DURATION := 16.0

var _t := 0.0
var _fire_t := 0.0
var _wave := 0
var _main = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	await physics_frame
	if _main.doll == null:
		print("[record] no doll")
		quit(1)
		return

	var arena := Vector2(60.0, 44.0) * 64.0
	_main.doll.global_position = arena
	_main.mouse_aim_enabled = false
	_main.doll.aim_enabled = true
	_main.doll.hp_max = 99999.0
	_main.doll.hp = 99999.0
	_main.doll.armor_max = 9999.0
	_main.doll.armor = 9999.0

	for e in _main.enemies.duplicate():
		e.queue_free()
	_main.enemies.clear()
	await process_frame

	_spawn_wave()
	while _t < DURATION:
		await process_frame
		_t += 1.0 / FPS
		_main.doll.hp = _main.doll.hp_max
		_main.doll.armor = _main.doll.armor_max
		_aim_and_fire()
		if _main.enemies.size() <= 1 and _t > 6.0 and _wave < 3:
			_spawn_wave()

	print("[record] done, kills=", _main.kills)
	quit()


func _spawn_wave() -> void:
	_wave += 1
	var arena: Vector2 = _main.doll.global_position
	var roster := [
		[&"mobile_turret", Vector2(130, 10)],
		[&"sentry_type1", Vector2(-220, 10)],
		[&"hunter_type1", Vector2(-260, 140)],
		[&"goliath", Vector2(-80, 170)],
	]
	for entry in roster:
		_spawn(entry[0], arena + entry[1], 4)


func _spawn(kind: StringName, pos: Vector2, depth: int) -> void:
	var enemy := Enemy2D.new()
	enemy.setup(kind, pos, depth)
	_main.sort_layer.add_child(enemy)
	enemy.died.connect(_main._on_enemy_died)
	_main.enemies.append(enemy)


func _aim_and_fire() -> void:
	var target = null
	var best := 1e9
	for e in _main.enemies:
		if e == null or not is_instance_valid(e):
			continue
		var d: float = e.global_position.distance_to(_main.doll.global_position)
		if d < best:
			best = d
			target = e
	if target == null:
		return
	_main.doll.aim_target = target.global_position + Vector2(0, -36)
	_fire_t -= 1.0 / FPS
	if _fire_t <= 0.0 and _main.doll.weapon_rig != null and _t > 2.5:
		if _main.doll.weapon_rig.try_fire():
			_fire_t = 0.6
