extends SceneTree
## Phase 7B Modular Doll Rig v2 专项单元测试：
## 验证 160×160 SubViewport 像素光栅化、纸娃娃分层与预留槽、上下半身解耦、二段式屈膝步态、
## 弹簧头发/衣摆次级物理、眨眼、开火后坐联动、受击后仰、三阶段团身翻滚与 4 持枪姿态整合。
## godot --headless --path . --script res://tests/doll_rig_v2_test.gd

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
	create_timer(30.0).timeout.connect(func() -> void: quit(2))

	var doll: Doll2D = load("res://scenes/actors/Doll2D.tscn").instantiate()
	var stage := Node2D.new()
	root.add_child(stage)
	stage.add_child(doll)
	doll.global_position = Vector2(400, 400)
	doll.set_physics_process(false)
	for _i in 4:
		await process_frame

	# 1) 默认启用 Modular Doll Rig v2，并隐藏旧整图精灵，同时保留旧 sprite_frames 契约
	var rv2: DollRigV2 = doll.rig_v2
	_check(rv2 != null and rv2.visible, "Doll2D enables Modular Doll Rig v2 by default")
	_check(not doll.body.visible and doll.body.sprite_frames != null,
		"legacy Body sprite is hidden while preserving sprite_frames contract")
	_check(rv2.has_all_part_textures(), "all required modular pixel parts loaded from assets/art/characters/doll_v2/parts/")

	# 2) SubViewport 160×160 无抗锯齿 + NEAREST 1:1 像素光栅化
	_check(rv2.viewport != null and rv2.viewport.size == Vector2i(160, 160)
		and rv2.viewport.transparent_bg and rv2.viewport.msaa_2d == Viewport.MSAA_DISABLED,
		"SubViewport uses 160x160 transparent MSAA_DISABLED pixel rasterization")
	_check(rv2.rig_canvas != null and rv2.rig_canvas.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and rv2.rig_canvas.scale.is_equal_approx(Vector2.ONE),
		"RigCanvas renders 1:1 with TEXTURE_FILTER_NEAREST (128px x1 locked)")

	# 3) 完整纸娃娃分层与未来换装槽位（Shadow / Legs 二段膝 / Torso+ArmorSlot / BackGear+BackpackSlot / Head+Blink / SecondaryMotion）
	_check(rv2.shadow_sprite != null and rv2.leg_l_hip != null and rv2.leg_l_knee != null
		and rv2.leg_r_hip != null and rv2.leg_r_knee != null,
		"Shadow and 2-segment articulated legs (Thigh -> Knee -> Shin) exist")
	_check(rv2.torso_pivot != null and rv2.armor_slot != null and rv2.backpack_slot != null
		and rv2.gun_case != null and rv2.head_sprite != null and rv2.blink_sprite != null,
		"Torso, ArmorSlot, BackGear/BackpackSlot, Head, and independent BlinkLayer exist")
	_check(rv2.hair_back_pivot != null and rv2.hair_back_tip != null
		and rv2.coat_l_pivot != null and rv2.coat_l_tip != null
		and rv2.coat_r_pivot != null and rv2.coat_r_tip != null and rv2.skirt_pivot != null,
		"2-segment spring secondary motion chains (hair, coat flaps, skirt) exist")

	# 4) 上下半身解耦：向左移动同时朝右瞄准 -> 下身朝左、上身朝右、步态识别为 backpedal
	var aim_right := doll.global_position + Vector2(240, 0)
	var foot_events := [0]
	rv2.footstep_planted.connect(func(_off: Vector2, _run: bool) -> void: foot_events[0] += 1)
	var max_knee := 0.0
	for _i in 32:
		rv2.update_rig(Vector2(-240, 0), 250.0, 380.0, aim_right, true, true, false, false,
			false, 0.0, Vector2.ZERO, 0.03)
		max_knee = maxf(max_knee, rv2.get_knee_bend_max())
	_check(rv2.lower_direction == 2 and rv2.upper_direction == 3 and rv2.locomotion_mode == &"backpedal",
		"upper/lower body decouple cleanly (move left + aim right -> backpedal)")
	_check(max_knee > 0.25, "2-segment legs bend knees smoothly during gait (max %.2f rad)" % max_knee)
	_check(foot_events[0] >= 1, "footstep_planted signal emits on stride contact (%d)" % foot_events[0])

	# 4b) 验证正/背移动抬膝与收枪奔跑双臂肘部明显弯曲（确保四肢关节全向灵动）
	var max_front_lift := 0.0
	var max_elbow_bend := 0.0
	for _i in 24:
		rv2.update_rig(Vector2(0, 360), 250.0, 380.0, doll.global_position + Vector2(0, 240), true, false, true, false,
			false, 0.0, Vector2.ZERO, 0.03)
		var base_ky := DollRigV2.THIGH_LEN - 2.0
		max_front_lift = maxf(max_front_lift, maxf(base_ky - rv2.leg_l_knee.position.y, base_ky - rv2.leg_r_knee.position.y))
		max_elbow_bend = maxf(max_elbow_bend, maxf(absf(rv2.arm_l_elbow.rotation), absf(rv2.arm_r_elbow.rotation)))
	for _i in 18:
		rv2.update_rig(Vector2(360, 0), 250.0, 380.0, aim_right, true, false, true, false,
			false, 0.0, Vector2.ZERO, 0.03)
		max_elbow_bend = maxf(max_elbow_bend, maxf(absf(rv2.arm_l_elbow.rotation), absf(rv2.arm_r_elbow.rotation)))
	_check(max_front_lift > 4.0 and max_elbow_bend > 0.45,
		"front/back gait lifts knee joints (%.1fpx) and arms flex elbows clearly (%.2f rad)" % [max_front_lift, max_elbow_bend])

	# 5) 侧面移动 + 朝上瞄准 -> 识别为 strafe，且背后枪盒切至身体前层 (z > 0)
	var aim_up := doll.global_position + Vector2(0, -240)
	rv2.update_rig(Vector2(240, 0), 250.0, 380.0, aim_up, true, true, false, false,
		false, 0.0, Vector2.ZERO, 0.03)
	_check(rv2.locomotion_mode == &"strafe" and rv2.upper_direction == 1 and rv2.gun_case.z_index > 0,
		"strafe mode detected and BackGear gun case moves in front of torso when facing up")

	# 6) 次级物理弹簧（冲刺 -> 急停刹车 -> 开火后坐产生清晰飘动偏转）
	for _i in 24:
		rv2.update_rig(Vector2(380, 0), 250.0, 380.0, aim_right, true, true, false, false,
			false, 0.0, Vector2.ZERO, 0.025)
	var sprint_deflect := rv2.get_secondary_deflection()
	_check(sprint_deflect > 0.45, "spring hair & coat flaps trail strongly during sprint (%.2f rad)" % sprint_deflect)
	# 急停刹车 + 开火后坐脉冲
	rv2.update_rig(Vector2.ZERO, 250.0, 380.0, aim_right, true, true, false, false,
		false, 0.0, Vector2.ZERO, 0.025)
	var pre_recoil_rot := rv2.torso_pivot.rotation
	rv2.trigger_recoil(1.8, Vector2.RIGHT)
	rv2.update_rig(Vector2.ZERO, 250.0, 380.0, aim_right, true, true, false, false,
		false, 0.0, Vector2.ZERO, 0.02)
	_check(absf(rv2.torso_pivot.rotation - pre_recoil_rot) > 0.05,
		"weapon fire recoil visibly kicks upper torso and secondary springs")

	# 7) 独立眨眼层与受击后仰
	rv2.trigger_hurt(Vector2.RIGHT)
	rv2.update_rig(Vector2.ZERO, 250.0, 380.0, doll.global_position + Vector2(0, 200), true, true, false, false,
		false, 0.0, Vector2.ZERO, 0.02)
	_check(rv2.blink_sprite.visible, "independent BlinkLayer activates on hurt/blink")

	# 8) Phase 5 三阶段团身翻滚（crouch -> tuck_roll -> recover）
	rv2.update_rig(Vector2(500, 0), 250.0, 380.0, aim_right, true, true, false, false,
		true, 0.10, Vector2.RIGHT, 0.02)
	var p1 := rv2.get_dodge_phase()
	rv2.update_rig(Vector2(500, 0), 250.0, 380.0, aim_right, true, true, false, false,
		true, 0.50, Vector2.RIGHT, 0.02)
	var p2 := rv2.get_dodge_phase()
	var mid_roll_rot := absf(rv2.pelvis.rotation)
	rv2.update_rig(Vector2(200, 0), 250.0, 380.0, aim_right, true, true, false, false,
		true, 0.90, Vector2.RIGHT, 0.02)
	var p3 := rv2.get_dodge_phase()
	_check(p1 == &"crouch" and p2 == &"tuck_roll" and p3 == &"recover" and mid_roll_rot > 1.5,
		"dodge roll transitions cleanly through crouch -> tuck_roll (rot=%.2f) -> recover" % mid_roll_rot)

	# 9) 与 WeaponRig2D 4 大持枪姿态模板 + 收枪手臂切换整合
	var wr := doll.equip_weapon_id(&"akm")
	await process_frame
	rv2.update_rig(Vector2.ZERO, 250.0, 380.0, aim_right, true, true, false, false,
		false, 0.0, Vector2.ZERO, 0.02)
	var armed_arms_hidden := not rv2.arm_l_shoulder.visible and not rv2.arm_r_shoulder.visible
	rv2.update_rig(Vector2.ZERO, 250.0, 380.0, aim_right, true, false, true, false,
		false, 0.0, Vector2.ZERO, 0.02)
	var holstered_arms_shown := rv2.arm_l_shoulder.visible or rv2.arm_r_shoulder.visible
	_check(armed_arms_hidden and holstered_arms_shown and wr.get_stance_id() == &"rifle",
		"holstered rig arms cleanly hand off to WeaponRig2D when armed")

	# 10) 皮肤包完整性（doll_v2 / doll_thistle / mannequin 全 19+3 分件 + skin_manifest.json + 严格 1:1 target_h）
	for sid: String in ["doll_v2", "doll_thistle", "mannequin"]:
		_check(DollRigV2.skin_exists(sid) and WeaponRig2D.skin_has_arm2(sid),
			"%s skin has all required parts and 3 arm2 weapon-arm textures" % sid)
		var mpath := DollRigV2.skin_manifest_path(sid)
		var mraw = JSON.parse_string(FileAccess.get_file_as_string(mpath)) if FileAccess.file_exists(mpath) else null
		_check(mraw is Dictionary and int((mraw as Dictionary).get("parts_count", 0)) == 19
			and int((mraw as Dictionary).get("arm2_count", 0)) == 3,
			"%s skin_manifest.json exists and declares 19 parts + 3 arm2" % sid)

	# 10b) 验证默认正式皮 doll_v2 全部 19 分件严格 1:1 匹配 target_h（零非整数缩放畸变）
	var v2_1to1 := true
	for k in rv2._part_scale_base:
		var sc_v2: Vector2 = rv2._part_scale_base[k]
		if not sc_v2.is_equal_approx(Vector2.ONE):
			v2_1to1 = false
			break
	_check(v2_1to1, "all 19 refined doll_v2 parts match DollRigV2 target_h 1:1 (zero non-integer scale distortion)")

	# 11) set_skin('doll_thistle') 热切换 + 严格 1:1 + 无体模分色污染 + 新武器继承
	var switched_t := doll.set_skin("doll_thistle")
	await process_frame
	_check(switched_t and doll.get_skin() == "doll_thistle" and rv2.skin_id == "doll_thistle"
		and wr.skin_id == "doll_thistle" and rv2.has_all_part_textures(),
		"set_skin('doll_thistle') hot-swaps both DollRigV2 (19 parts) and WeaponRig2D (3 arm2)")
	var th_1to1 := true
	for k in rv2._part_scale_base:
		var sc_th: Vector2 = rv2._part_scale_base[k]
		if not sc_th.is_equal_approx(Vector2.ONE):
			th_1to1 = false
			break
	_check(th_1to1, "all 19 doll_thistle parts match DollRigV2 target_h 1:1 (zero non-integer scale distortion)")
	var l_thigh_th := rv2.leg_l_hip.get_child(0) as Sprite2D
	var r_thigh_th := rv2.leg_r_hip.get_child(0) as Sprite2D
	_check(l_thigh_th != null and r_thigh_th != null and l_thigh_th.texture == r_thigh_th.texture,
		"formal skin doll_thistle disables mannequin left-blue / right-orange limb tinting")
	var wr_th := doll.equip_weapon_id(&"g17")
	await process_frame
	_check(wr_th.skin_id == "doll_thistle", "newly equipped WeaponRig2D inherits active skin_id ('doll_thistle')")

	# 11b) set_skin('mannequin') 热切换同步 DollRigV2 与 WeaponRig2D + 1:1 scale 校验 + 左蓝/右橙分色
	var switched_m := doll.set_skin("mannequin")
	await process_frame
	_check(switched_m and doll.get_skin() == "mannequin" and rv2.skin_id == "mannequin"
		and wr_th.skin_id == "mannequin" and rv2.has_all_part_textures(),
		"set_skin('mannequin') hot-swaps both DollRigV2 (19 parts) and WeaponRig2D (3 arm2)")
	var all_1to1 := true
	for k in rv2._part_scale_base:
		var sc: Vector2 = rv2._part_scale_base[k]
		if not sc.is_equal_approx(Vector2.ONE):
			all_1to1 = false
			break
	_check(all_1to1, "all 19 mannequin parts match DollRigV2 target_h 1:1 (zero non-integer scale distortion)")
	var l_thigh_sp := rv2.leg_l_hip.get_child(0) as Sprite2D
	var r_thigh_sp := rv2.leg_r_hip.get_child(0) as Sprite2D
	_check(l_thigh_sp != null and r_thigh_sp != null and l_thigh_sp.texture != r_thigh_sp.texture,
		"mannequin mode applies distinct left-blue / right-orange limb textures")
	var wr2 := doll.equip_weapon_id(&"awm")
	await process_frame
	_check(wr2.skin_id == "mannequin", "newly equipped WeaponRig2D inherits active skin_id ('mannequin')")

	# 12) 非法或缺失皮肤自动安全回退至 doll_v2
	var bad_ok := doll.set_skin("nonexistent_skin_xyz")
	_check(not bad_ok and doll.get_skin() == "doll_v2" and rv2.skin_id == "doll_v2" and wr2.skin_id == "doll_v2",
		"invalid skin safely falls back to 'doll_v2' on both DollRigV2 and WeaponRig2D")
	var traversal_ok := doll.set_skin("../invalid")
	_check(not traversal_ok and doll.get_skin() == "doll_v2" and rv2.has_all_part_textures(),
		"path-traversal skin id rejected and safely falls back to 'doll_v2'")

	# 13) DebugMenu2D 一键外观轮切实时热切换当前场景角色皮肤（doll_v2 -> doll_thistle -> mannequin -> doll_v2）
	var dm := DebugMenu2D.new()
	stage.add_child(dm)
	await process_frame
	var toggled_1 := dm.toggle_character_skin()
	_check(toggled_1 == "doll_thistle" and doll.get_skin() == "doll_thistle" and wr2.skin_id == "doll_thistle",
		"DebugMenu2D toggle 1 switches live player to doll_thistle")
	var toggled_2 := dm.toggle_character_skin()
	_check(toggled_2 == "mannequin" and doll.get_skin() == "mannequin" and wr2.skin_id == "mannequin",
		"DebugMenu2D toggle 2 switches live player to mannequin")
	var toggled_3 := dm.toggle_character_skin()
	_check(toggled_3 == "doll_v2" and doll.get_skin() == "doll_v2" and wr2.skin_id == "doll_v2",
		"DebugMenu2D toggle 3 switches live player back to formal doll_v2")
	var p := root.get_node_or_null("Progress")
	if p != null and p.has_method("reset_debug"):
		p.reset_debug()

	# 14) 收尾清理 + 旧版回退模式可用
	doll.enable_rig("legacy")
	_check(not rv2.visible and doll.body.visible, "enable_rig('legacy') falls back to legacy sprite cleanly")
	doll.enable_rig("v2")
	_check(rv2.visible and not doll.body.visible, "enable_rig('v2') restores Modular Doll Rig v2 cleanly")

	stage.queue_free()
	await process_frame
	print("\n=== doll rig v2: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
