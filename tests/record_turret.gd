extends SceneTree
## 哨戒炮激光锁定演示：只放一台移动哨卫炮，不还手，录 4 秒。
## godot --path . --write-movie screenshots/turret_lock.avi --fixed-fps 30 \
##   --script res://tests/record_turret.gd

const FPS := 30.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	await physics_frame
	var arena := Vector2(60.0, 44.0) * 64.0
	main.doll.global_position = arena
	main.mouse_aim_enabled = false
	main.doll.aim_enabled = true
	main.doll.hp_max = 99999.0
	main.doll.hp = 99999.0
	for e in main.enemies.duplicate():
		e.queue_free()
	main.enemies.clear()
	await process_frame

	var turret := Enemy2D.new()
	turret.setup(&"mobile_turret", arena + Vector2(210, 0), 3)
	main.sort_layer.add_child(turret)
	turret.died.connect(main._on_enemy_died)
	main.enemies.append(turret)

	var t := 0.0
	while t < 4.2:
		await process_frame
		t += 1.0 / FPS
		main.doll.hp = main.doll.hp_max
		main.doll.aim_target = turret.global_position + Vector2(0, -40)
	quit()
