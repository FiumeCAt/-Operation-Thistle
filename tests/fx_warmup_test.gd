extends SceneTree
## 战斗特效预热回归：变体选择、逐帧烘焙接口、预热后命中特效正常生成。
## godot --headless --path . --script res://tests/fx_warmup_test.gd

const HIT_FX := preload("res://scripts/fx/HitFX2D.gd")

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
	var p = root.get_node_or_null("Progress")
	_check(p != null, "Progress autoload exists")
	if p == null:
		quit(1)
		return
	p.reset_for_test()

	p.data["hit_fx_level"] = 1
	var variants_reduced := HIT_FX.impact_variants()
	_check(variants_reduced.size() == 4, "reduced hit fx warms four variants")
	p.data["hit_fx_level"] = 2
	var variants_full := HIT_FX.impact_variants()
	_check(variants_full.size() == 6, "full hit fx adds both crit variants")

	var ids := {}
	for variant in variants_full:
		ids[String(variant.get("id", ""))] = true
	_check(ids.has("impacts/blunt-hit") and ids.has("impacts/hit-spark")
		and ids.has("impacts/bullet-impact") and ids.has("impacts/crit-hit"),
		"warmup covers every impact effect")
	var opts: Dictionary = variants_full[1].get("opts", {})
	_check(not opts.is_empty() and opts.has("palette"),
		"warmup options include the expanded palette")

	var done := false
	var steps := 0
	while not done and steps < 120:
		done = PixelFx2D.prebake_step("impacts/hit-spark", opts, "", steps)
		steps += 1
	_check(done, "prebake_step finishes across frames (%d)" % steps)
	var again := PixelFx2D.prebake_step("impacts/hit-spark", opts, "", 0)
	_check(again, "finished effect reports ready immediately")

	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame
	var before: int = main.fx_layer.get_child_count()
	HIT_FX.enemy_hit(main.fx_layer, main.doll.global_position + Vector2(120, 0),
		Vector2.RIGHT, "flesh", 1.0, false, 1)
	await process_frame
	_check(main.fx_layer.get_child_count() > before, "hit fx spawns after warmup")

	main.queue_free()
	await process_frame
	print("\n=== fx warmup: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
