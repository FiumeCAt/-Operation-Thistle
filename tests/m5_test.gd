extends SceneTree
## M5 第一批：手枪独立枪声、低血量视觉反馈与层级。

var _main: Node3D
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
	print("=== Operation Thistle M5 test ===")
	create_timer(90.0).timeout.connect(func() -> void: quit(2))
	var sfx := root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload 存在")
	_check(sfx.get_stream("pistol") != null, "手枪枪声已生成")
	if sfx.get_stream("pistol") != null and sfx.get_stream("shotgun") != null:
		_check(sfx.get_stream("pistol").get_length() < sfx.get_stream("shotgun").get_length(),
			"手枪枪声短于霰弹枪")

	change_scene_to_file("res://scenes/core/Main.tscn")
	await _frames(10)
	_main = current_scene
	for actor in get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	var doll: Doll = _main.doll
	var weapon: PlayerWeapon = doll.weapon

	weapon.switch_to(&"m870")
	_check(weapon.shot_sound_kind() == "shotgun", "霰弹枪使用霰弹枪声")
	weapon.switch_to(&"g17")
	_check(weapon.shot_sound_kind() == "pistol", "G17 使用独立手枪声")
	weapon.switch_to(&"saiga12k")
	_check(weapon.shot_sound_kind() == "shotgun", "SAIGA-12K 使用霰弹枪声")

	var vignette: HealthVignette = _main.health_vignette
	_check(vignette != null and vignette.visible, "行动中启用低血量反馈")
	_check(vignette.layer < _main.reticle.layer and vignette.layer < _main.run_hud.layer,
		"低血量反馈位于准心与 HUD 之下")
	var material: ShaderMaterial = vignette._mat
	_check(material != null and material.shader != null, "低血量着色器已加载")

	doll.hp = doll.hp_max
	for i in 10:
		vignette._process(0.1)
	await _frames(2)
	_check(float(material.get_shader_parameter("intensity")) < 0.05, "满血无红边")

	doll.hp = doll.hp_max * 0.2
	for i in 10:
		vignette._process(0.1)
	await _frames(2)
	var low_intensity := float(material.get_shader_parameter("intensity"))
	_check(low_intensity > 0.5, "低血量红边明显：%.2f" % low_intensity)

	doll.hp = doll.hp_max * 0.45
	for i in 10:
		vignette._process(0.1)
	await _frames(2)
	var mid_intensity := float(material.get_shader_parameter("intensity"))
	_check(mid_intensity > 0.0 and mid_intensity < low_intensity, "血量回升后红边减弱")

	doll.hp = doll.hp_max
	for i in 10:
		vignette._process(0.1)
	_check(float(material.get_shader_parameter("intensity")) < 0.05, "回满血后红边消失")

	# ---- 屏幕暗角与可互动物品描边
	var screen: ScreenVignette = _main.screen_vignette
	_check(screen != null and screen.visible, "行动中启用屏幕暗角")
	_check(screen.layer < _main.reticle.layer and screen.layer < _main.run_hud.layer,
		"暗角不遮挡准心与 HUD")

	var box: StaticBody3D = _main.level.search_containers[0]
	var highlight: MeshInstance3D = box.get_node_or_null("Highlight")
	_check(highlight != null and not highlight.visible, "可互动物品默认不高亮")
	doll.global_position = box.global_position + Vector3(1.4, 0, 0)
	_main._update_interact_highlights()
	_check(highlight.visible, "靠近物资箱显示白色描边")
	doll.global_position = _main.level.player_spawn
	_main._update_interact_highlights()
	_check(not highlight.visible, "离开后隐藏描边")

	var exit_hl: MeshInstance3D = _main.level.exit_highlight
	_check(exit_hl != null and not exit_hl.visible, "竖井默认不高亮")
	doll.global_position = _main.level.exit_position
	_main._update_interact_highlights()
	_check(exit_hl.visible, "靠近竖井显示白色描边")
	doll.global_position = _main.level.player_spawn
	_main._update_interact_highlights()

	print("=== M5 %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAILED", _checks, _fails])
	_main.free()
	await process_frame
	quit(0 if _fails == 0 else 1)
