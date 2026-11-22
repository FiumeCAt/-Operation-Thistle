extends Node
## 自动截图：--capture <path> --mode beauty|fire|dirs|states|stress --frames N
## 供开发期用真实渲染验证相机、立绘方向、动画与 HUD。

const TITLE_MENU := preload("res://scripts/ui/TitleMenu.gd")

var main: Node3D
var base_path := ""
var mode := "beauty"
var frames := 24

func setup(m: Node3D, p: String, md: String, f: int) -> void:
	main = m
	base_path = p
	mode = md
	frames = f

func _ready() -> void:
	call_deferred("_run")

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_sec(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _run() -> void:
	await _wait(12)
	_prepare_dir()
	await _wait_sec(1.0)  # 等 Vulkan 着色器编译完成，FPS 计数才有意义

	var d: Doll = main.doll
	var rig: CameraRig = main.rig
	var blur = main.get_node_or_null("MotionBlur")
	if blur:
		blur.set_enabled(false)  # 截图检查时关闭动态模糊

	match mode:
		"dirs":
			d.global_position = Vector3(-20.0, 0.02, 0.0)
			rig.global_position = Vector3(-20.0, 0.0, 0.0)
			rig.rotation.y = 0.0
			d.debug_set_state("aim")
			await _wait(10)
			for i in 8:
				var a := float(i) * 45.0
				d.debug_set_facing(a)
				var f := Vector3(sin(deg_to_rad(a)), 0.0, cos(deg_to_rad(a)))
				d.debug_set_aim(d.global_position + f * 4.0)
				await _wait(4)
				await _save(_path("dir_%d.png" % i))

		"states":
			d.global_position = Vector3(-20.0, 0.02, -0.4)
			rig.global_position = Vector3(-20.0, 0.0, -0.4)
			d.debug_set_facing(20.0)
			d.debug_set_aim(Vector3(-11.0, 0.0, 1.6))
			await _wait(8)
			for st in ["idle", "walk", "aim", "fire", "reload", "hurt", "death"]:
				d.debug_set_state(st)
				if st == "fire":
					d.debug_hold_muzzle = true
					d.debug_fire()
				await _wait_sec(1.4 if st == "death" else 0.45)
				print("[state] %s frame=%d playing=%s" % [st, d.billboard.body.frame, str(d.billboard.body.is_playing())])
				await _save(_path("state_%s.png" % st))
				if st == "fire":
					d.debug_hold_muzzle = false
					d.debug_reset_muzzle()
			d.debug_hold_muzzle = false

		"probe":
			# 锚点探针：把三个握把锚点画在角色身上，附米制标尺，用于微调 HAND_LOCAL
			var pr := _stand_at()
			d.global_position = pr
			rig.global_position = Vector3(pr.x, 0.0, pr.z)
			rig.rotation.y = 0.0
			rig.distance = 5.2
			rig.fov = 30.0
			rig.follow_speed = 0.0    # 相机钉死在固定机位
			var wv_h = main.get_node_or_null("WeaponVisual")
			if wv_h:
				wv_h.set_enabled(false)
			var hud_h = main.get_node_or_null("HUD")
			if hud_h:
				hud_h.visible = false
			var layer2 := CanvasLayer.new()
			layer2.layer = 4
			main.add_child(layer2)
			var holder2 := Control.new()
			holder2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer2.add_child(holder2)
			await _wait_sec(0.6)
			for st in ["aim", "idle", "reload"]:
				d.debug_set_state(st)
				for i in 8:
					var a3 := float(i) * 45.0
					d.global_position = pr
					d.velocity = Vector3.ZERO
					rig.global_position = Vector3(pr.x, 0.0, pr.z)
					d.debug_set_facing(a3)
					var f3 := Vector3(sin(deg_to_rad(a3)), 0.0, cos(deg_to_rad(a3)))
					d.debug_set_aim(pr + f3 * 4.0)
					await _wait(3)
					_grid_overlay(holder2, d, true)
					_anchor_marks(holder2, d, true, false)
					await _save(_path("probe_%s_%d.png" % [st, i]))

		"grid":
			# 米制标尺（不带锚点），用于量取手部位置
			var gr := _stand_at()
			d.global_position = gr
			rig.global_position = Vector3(gr.x, 0.0, gr.z)
			rig.rotation.y = 0.0
			rig.pitch_deg = 0.0         # 俯角归零：竖直平面基本正对镜头，便于用眼睛读数
			rig.distance = 3.2
			rig.fov = 60.0
			rig.follow_speed = 0.0
			var wv_hide = main.get_node_or_null("WeaponVisual")
			if wv_hide:
				wv_hide.set_enabled(false)   # 标定时不画武器，避免遮挡手部
			var hud_hide = main.get_node_or_null("HUD")
			if hud_hide:
				hud_hide.visible = false
			var layer := CanvasLayer.new()
			layer.layer = 4
			main.add_child(layer)
			var holder := Control.new()
			holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(holder)
			await _wait_sec(0.6)
			for st in ["aim", "idle", "reload"]:
				d.debug_set_state(st)
				for i in 8:
					var a2 := float(i) * 45.0
					d.global_position = gr
					d.velocity = Vector3.ZERO
					d.debug_set_facing(a2)
					var f2 := Vector3(sin(deg_to_rad(a2)), 0.0, cos(deg_to_rad(a2)))
					d.debug_set_aim(gr + f2 * 4.0)
					await _wait(3)
					_grid_overlay(holder, d, true)
					_anchor_marks(holder, d, false, false)
					await _save(_path("grid_%s_%d.png" % [st, i]))

		"stress":
			rig.distance = 20.0
			rig.fov = 42.0
			main.set_stress(true)
			await _wait_sec(1.2)
			await _save(_path("stress.png"))

		"move":
			d.global_position = Vector3(-20.0, 0.02, 0.0)
			rig.global_position = Vector3(-20.0, 0.0, 0.0)
			d.debug_set_aim(Vector3(-20.0, 0.0, -12.0))
			await _wait(10)
			print("[move] start pos=", d.global_position)
			Input.action_press("move_right")
			await _wait_sec(0.9)
			print("[move] moving pos=", d.global_position, " speed=", d.get_speed())
			await _save(_path("move.png"))
			Input.action_release("move_right")

		"mouse":
			d.global_position = Vector3(-12.0, 0.02, 0.0)
			rig.global_position = Vector3(-12.0, 0.0, 0.0)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Input.warp_mouse(Vector2(1180, 330))
			await _wait_sec(0.4)
			print("[mouse] aim=", d.aim_point)
			await _save(_path("mouse.png"))

		"bench":
			main.set_stress(false)
			await _wait_sec(2.5)
			var idle_fps := Engine.get_frames_per_second()
			print("[bench] idle fps=", idle_fps)
			main.set_stress(true)
			await _wait_sec(2.5)
			var stress_fps := Engine.get_frames_per_second()
			print("[bench] stress20 fps=", stress_fps)
			await _save(_path("bench.png"))

		"fire":
			d.global_position = Vector3(-11.5, 0.02, -0.2)
			rig.global_position = Vector3(-11.5, 0.0, -0.2)
			var aim_f := Vector3(-9.2, 0.0, 1.5)
			d.debug_set_aim(aim_f)
			d.debug_set_facing(rad_to_deg(atan2(aim_f.x - d.global_position.x, aim_f.z - d.global_position.z)))
			d.debug_set_state("aim")
			await _wait(10)
			d.debug_set_state("")
			d.debug_hold_muzzle = true
			d.debug_fire()
			await _wait(12)
			await _save(_path("fire.png"))
			d.debug_hold_muzzle = false
			d.debug_reset_muzzle()

		"walk":
			d.global_position = Vector3(-11.5, 0.02, -0.2)
			rig.global_position = Vector3(-11.5, 0.0, -0.2)
			var aim_w := Vector3(-9.2, 0.0, 1.5)
			d.debug_set_aim(aim_w)
			d.debug_set_facing(rad_to_deg(atan2(aim_w.x - d.global_position.x, aim_w.z - d.global_position.z)))
			d.debug_set_state("walk")
			await _wait(24)
			await _save(_path("walk.png"))

		"ballistic":
			# 弹道诊断：量化「准心 vs 实际命中」的屏幕偏差，以及散布角
			d.global_position = Vector3(6.0, 0.02, 0.0)
			rig.global_position = Vector3(6.0, 0.0, 0.0)
			rig.rotation.y = 0.0
			d.debug_set_state("aim")
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await _wait(16)
			var c2 := get_viewport().get_camera_3d()
			# 鼠标固定到屏幕右上方的空地，避免依赖投影计算
			Input.warp_mouse(Vector2(1180, 330))
			await _wait(12)

			var mouse := get_viewport().get_mouse_position()
			var ap: Vector3 = d.aim_point
			var muzzle: Vector3 = d.get_muzzle_position()
			var ro := Vector3(d.global_position.x, Doll.AIM_HEIGHT, d.global_position.z)
			var dv := ap - ro
			dv.y = 0.0
			dv = dv.normalized()
			var hit := d.get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(ro, ro + dv * 28.0, 1 | 8))
			var hitpos: Vector3 = hit.get("position", ro + dv * 28.0)
			var rt = main.reticle
			var rt_screen: Vector2 = rt._pos if rt else Vector2.ZERO
			print("[ballistic] mouse=%s reticle=%s" % [str(mouse), str(rt_screen)])
			print("[ballistic] aim_point=%s ray_origin(y=%.2f) hit=%s" % [str(ap), ro.y, str(hitpos)])
			# 关键指标：准心（鼠标）与真实命中点在屏幕上的像素偏差
			var hit_screen := c2.unproject_position(hitpos)
			print("[ballistic] screen hit=%s  delta(reticle→hit)=%s  |d|=%.1fpx" % [
				str(hit_screen), str(hit_screen - rt_screen), (hit_screen - rt_screen).length()])
			# 垂直视差：同一 XZ 在地面 vs 弹道高度的投影差
			var same_xz := Vector3(hitpos.x, 0.0, hitpos.z)
			var par := c2.unproject_position(hitpos) - c2.unproject_position(same_xz)
			print("[ballistic] 垂直视差(弹道 y=%.2f vs 地面) = %s |d|=%.1fpx" % [ro.y, str(par), par.length()])

			# 散布统计（按当前弹种，抽样 400 发）
			var wpn: PlayerWeapon = d.weapon
			var ammo := wpn.current_ammo()
			var mx := 0.0
			var sum := 0.0
			for i in 400:
				var a := randf_range(-ammo.spread * 0.5, ammo.spread * 0.5)
				mx = maxf(mx, absf(a))
				sum += absf(a)
			var dist := Vector2(ap.x - ro.x, ap.z - ro.z).length()
			print("[ballistic] ammo=%s spread=%.3frad(%.1fdeg cone) max_dev=%.1fdeg mean=%.1fdeg lateral_at_%.1fm=%.2fm" % [
				ammo.display_name, ammo.spread, rad_to_deg(ammo.spread),
				rad_to_deg(mx), rad_to_deg(sum / 400.0), dist, tan(mx) * dist])
			await _save(_path("ballistic.png"))

		"aimtest":
			# 弹道验证：把鼠标移到靶子屏幕位置，连开 4 枪，看靶子命中数是否增加
			var tgt_pos := Vector3(10.0, 0.0, 1.8)
			d.global_position = Vector3(6.0, 0.02, 1.8)
			rig.global_position = Vector3(6.0, 0.0, 1.8)
			rig.rotation.y = 0.0
			d.debug_set_state("")
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# 等相机跟随完全稳定，否则取到的屏幕投影会偏（1 帧约 0.05m，累积可达 1m）
			await _wait(70)
			d.weapon.pump_action()          # 清掉可能的 FIRED 残留
			await _wait_sec(0.4)
			var c := get_viewport().get_camera_3d()
			# 瞄靶子「胸部」= 弹道高度，这样准心、弹道、命中在同一高度上
			var sp := c.unproject_position(Vector3(tgt_pos.x, Doll.AIM_HEIGHT, tgt_pos.z))
			Input.warp_mouse(sp)
			await _wait(8)
			var tgt = _find_target_near(tgt_pos)
			var before: int = tgt.hits if tgt != null else -1
			print("[aimtest] mouse=%s target_screen=%s aim_point=%s dist=%.2f hits_before=%d" % [
				str(get_viewport().get_mouse_position()), str(sp), str(d.aim_point),
				Vector2(d.aim_point.x - d.global_position.x, d.aim_point.z - d.global_position.z).length(), before])
			# 对齐检查：把「玩家中心 → 瞄准点」这条弹道投到屏幕上，看是否穿过准心
			var ro2 := Vector3(d.global_position.x, Doll.AIM_HEIGHT, d.global_position.z)
			var dir2 := d.aim_point - ro2
			dir2.y = 0.0
			dir2 = dir2.normalized()
			var aim_hit := d.get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(ro2, ro2 + dir2 * 28.0, 1 | 8))
			var hp: Vector3 = aim_hit.get("position", ro2 + dir2 * 28.0)
			var rt2 = main.reticle
			var rs: Vector2 = rt2._pos if rt2 else Vector2.ZERO
			var hs := c.unproject_position(hp)
			print("[aimtest] hit_world=%s hit_screen=%s reticle=%s 偏差=%.1fpx" % [
				str(hp), str(hs), str(rs), (hs - rs).length()])
			# 冻结瞄准点，避免系统鼠标在测试期间漂移干扰连发验证
			d.debug_set_aim(Vector3(tgt_pos.x, Doll.AIM_HEIGHT, tgt_pos.z))
			await _wait(4)
			for k in 4:
				var ch_before: String = d.weapon.chamber
				d.weapon.try_fire()
				await _wait_sec(0.4)
				print("[aimtest] shot %d: before=%s after=%s mag=%d tgt_hp=%.0f hits=%d" % [
					k, ch_before, d.weapon.chamber, d.weapon.mag,
					(tgt.hp if tgt != null else -1.0), (tgt.hits if tgt != null else -1)])
				d.weapon.pump_action()
				await _wait_sec(0.45)
			var after: int = tgt.hits if tgt != null else -1
			print("[aimtest] hits_after=%d delta=%d" % [after, after - before])
			var rt = main.reticle
			if rt != null:
				print("[aimtest] mouse=%s reticle_center=%s outline_points=%d viewport=%s window=%s" % [
					str(get_viewport().get_mouse_position()), str(rt._pos), rt._view.outline.size(),
					str(get_viewport().get_visible_rect().size), str(DisplayServer.window_get_size())])
			await _save(_path("aimtest.png"))

		"level":
			# 程序化关卡巡检：沿走廊取 4 个机位
			rig.pitch_deg = 58.0
			rig.distance = 16.0
			rig.fov = 42.0
			var lv = main.get_node_or_null("Level")
			var xs := [6.0, 30.0, 62.0, 100.0]
			for i in xs.size():
				var px: float = xs[i]
				d.global_position = Vector3(px, 0.02, 0.0)
				rig.global_position = Vector3(px, 0.0, 0.0)
				rig.rotation.y = 0.0
				await _wait(14)
				await _save(_path("level_%d.png" % i))
			if lv != null:
				print("[level] rooms=%d spans=%s spawns=%d navpolys=%d" % [
					lv.room_centers.size(), str(lv.room_centers), lv.enemy_spawns.size(),
					lv.nav_region.navigation_mesh.get_polygon_count() if lv.nav_region else -1])

		"rooms":
			# 每个侧房一个机位：检查隔断、小房间与摆件（隐藏 HUD 便于看空间）
			if main.run_hud:
				main.run_hud.hide()
			main.hud.hide()
			main.weapon_hud.hide()
			if main.reticle:
				main.reticle.hide()
			rig.pitch_deg = 42.0
			rig.distance = 15.0
			rig.fov = 44.0
			for i in main.level.room_centers.size():
				var rc: Vector3 = main.level.room_centers[i]
				d.global_position = Vector3(rc.x, 0.02, rc.z)
				rig.global_position = Vector3(rc.x, 0.0, rc.z)
				rig.rotation.y = 0.0
				await _wait(14)
				await _save(_path("room_%d.png" % i))

		"nav":
			# 寻路验证：玩家待在走廊，看敌人能否从侧房绕角追出来
			var lp: Vector3 = main.level.player_spawn
			d.global_position = Vector3(lp.x + 6.0, 0.02, 0.0)
			rig.global_position = Vector3(lp.x + 6.0, 0.0, 0.0)
			rig.rotation.y = 0.0
			d.debug_set_aim(Vector3(lp.x + 20.0, Doll.AIM_HEIGHT, 0.0))
			d.debug_set_state("aim")
			await _wait(8)
			var root0 = main.get_node_or_null("Enemies")
			for step in range(6):
				await _wait_sec(1.2)
				_dump_enemies()
				await _save(_path("nav_%d.png" % step))
			if root0:
				for c in root0.get_children():
					if c is Enemy:
						var e: Enemy = c
						var path := []
						if e.agent:
							path = e.agent.get_current_navigation_path()
						print("[nav] %s state=%s pos=%s path_pts=%d" % [
							String(e.kind), e.state_name(), str(e.global_position.round()), path.size()])

		"hip":
			# 腰射准心：不按右键、不设 aim 状态
			var hp0 := _stand_at()
			d.global_position = hp0
			rig.global_position = Vector3(hp0.x, 0.0, hp0.z)
			rig.rotation.y = 0.0
			d.debug_set_state("")
			var aim_h := Vector3(hp0.x + 4.0, Doll.AIM_HEIGHT, hp0.z - 1.6)
			d.debug_set_facing(rad_to_deg(atan2(aim_h.x - d.global_position.x, aim_h.z - d.global_position.z)))
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await _wait(10)
			Input.warp_mouse(Vector2(1180, 330))
			await _wait(18)
			await _save(_path("hip.png"))

		"ads":
			# 瞄准准心：与 hip 同机位，仅状态不同
			var ad0 := _stand_at()
			d.global_position = ad0
			rig.global_position = Vector3(ad0.x, 0.0, ad0.z)
			rig.rotation.y = 0.0
			d.debug_set_state("aim")
			var aim_a := Vector3(ad0.x + 4.0, Doll.AIM_HEIGHT, ad0.z - 1.6)
			d.debug_set_facing(rad_to_deg(atan2(aim_a.x - d.global_position.x, aim_a.z - d.global_position.z)))
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await _wait(10)
			Input.warp_mouse(Vector2(1180, 330))
			await _wait(18)
			await _save(_path("ads.png"))

		"hudhide":
			# 目标面板自动隐藏检查（9 秒后收起）
			await _wait_sec(10.5)
			await _save(_path("hud_hidden.png"))

		"hudlow":
			# 低血量检查：血条渐变、头像表情、体力数值
			var lp := _stand_at()
			d.global_position = lp
			rig.global_position = Vector3(lp.x, 0.0, lp.z)
			d.hp = d.hp_max * 0.22
			d.stamina = d.stamina_max * 0.45
			d.debug_set_state("aim")
			await _wait(16)
			await _save(_path("hud_low.png"))

		"menu":
			# 启动界面排版检查
			var menu = TITLE_MENU.new()
			main.add_child(menu)
			await _wait(20)
			await _save(_path("menu.png"))

		"ui":
			# 基地 / 技能树 / 天赋树 的 HUD 排版检查
			main.run_hud.show_base()
			await _wait(8)
			await _save(_path("ui_base.png"))
			main.run_hud._show_growth(false)
			await _wait(8)
			await _save(_path("ui_skill.png"))
			main.run_hud._show_growth(true)
			await _wait(8)
			await _save(_path("ui_talent.png"))

		"interact":
			var box: StaticBody3D = main.level.search_containers[0]
			d.global_position = box.global_position + Vector3(1.6, 0, 0)
			rig.global_position = Vector3(d.global_position.x, 0.0, d.global_position.z)
			await _wait(14)
			main._update_interact_highlights()
			await _save(_path("interact.png"))

		"clip":
			# 玩家站在房间内侧、相机在走廊隔着实墙：验证置顶立绘与玩家透窗
			var rc: Vector3 = main.level.room_centers[0]
			d.global_position = Vector3(rc.x, 0.02, rc.z + 2.0)
			rig.follow_speed = 0.0
			rig.pitch_deg = 58.0
			rig.distance = 12.0
			rig.global_position = Vector3(rc.x, 0.0, 0.0)
			rig.rotation.y = 0.0
			await _wait(20)
			main._update_player_wall_window()
			var wm: ShaderMaterial = main.level._window_materials[main.level.mat_wall]
			print("[clip] player_window_enabled=%s" % str(wm.get_shader_parameter("player_window_enabled")))
			await _save(_path("clip.png"))

		_:
			var bs0 := _stand_at()
			d.global_position = bs0
			rig.global_position = Vector3(bs0.x, 0.0, bs0.z)
			rig.rotation.y = 0.0
			var aim_b := Vector3(bs0.x + 5.0, Doll.AIM_HEIGHT, bs0.z - 1.2)
			d.debug_set_aim(aim_b)
			d.debug_set_facing(rad_to_deg(atan2(aim_b.x - d.global_position.x, aim_b.z - d.global_position.z)))
			d.debug_set_state("aim")
			await _wait(maxi(frames, 10))
			_dump_enemies()
			await _save(_path("beauty.png"))

	get_tree().quit()

## 关卡内的标准站位（走廊第一段，靠近训练靶）
func _stand_at() -> Vector3:
	if main != null and main.level != null:
		var p: Vector3 = main.level.player_spawn
		return Vector3(p.x + 2.0, 0.02, 0.0)
	return Vector3(6.0, 0.02, 0.0)

## 找到离指定位置最近的训练靶
func _find_target_near(pos: Vector3):
	var level = main.get_node_or_null("Level")
	if level == null:
		return null
	var best = null
	var bd := 1e9
	for c in level.get_children():
		if not c.has_method("on_hit"):
			continue
		var dd: float = c.global_position.distance_to(pos)
		if dd < bd:
			bd = dd
			best = c
	return best

func _dump_enemies() -> void:
	var root := main.get_node_or_null("Enemies")
	if root == null:
		print("[enemies] 没有 Enemies 节点")
		return
	var lines := []
	for c in root.get_children():
		if not (c is Enemy):
			continue
		var e: Enemy = c
		var pts := 0
		if e.agent:
			pts = e.agent.get_current_navigation_path().size()
		lines.append("%s/%s@%s(path %d)" % [
			String(e.kind), e.state_name(), str(e.global_position.round()), pts])
	print("[enemies] n=%d | %s" % [lines.size(), "  ".join(lines)])

func _path(name: String) -> String:
	if base_path.ends_with(".png"):
		return base_path
	return base_path.path_join(name)

## 角色所在竖直平面的「屏幕右方向」（相机右向投影到 XZ）。
## 与 Doll.hand_anchor_world() 用的是同一个轴，保证标尺与真实锚点重合。
func _plane_right() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.RIGHT
	var right := cam.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return Vector3.RIGHT
	return right.normalized()

## 平面内一点 → 世界坐标（x = 横向米，y = 离地高度米）
func _plane_point(d: Doll, x: float, y: float) -> Vector3:
	return d.global_position + _plane_right() * x + Vector3.UP * y

## 平面内一点 → 屏幕坐标（精确投影，不做线性近似，避免大俯角下失真）
func _plane_screen(d: Doll, x: float, y: float) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.ZERO
	return cam.unproject_position(_plane_point(d, x, y))

## 在角色身上画米制标尺：竖线 = 横向偏移(米)，横线 = 离地高度(米)
func _grid_overlay(holder: Control, d: Doll, clear := true) -> void:
	if clear:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	if get_viewport().get_camera_3d() == null:
		return
	var x := -0.8
	while x <= 0.801:
		var major := absf(fmod(x + 0.0001, 0.4)) < 0.01
		_line(holder, _plane_screen(d, x, -0.05), _plane_screen(d, x, 1.8), major)
		if major:
			_text(holder, _plane_screen(d, x, 1.8) + Vector2(-14, -18), "%+.1f" % x,
				Color(1, 0.72, 0.25, 0.95))
		x += 0.2
	var y := 0.0
	while y <= 1.801:
		var major2 := absf(fmod(y + 0.0001, 0.2)) < 0.01
		_line(holder, _plane_screen(d, -0.8, y), _plane_screen(d, 0.8, y), major2)
		if major2:
			_text(holder, _plane_screen(d, -0.8, y) + Vector2(-52, -8), "%.1f" % y,
				Color(1, 0.72, 0.25, 0.95))
		y += 0.1

## 标出当前三个姿态组的握把锚点（红=LOW 青=AIM 黄=RELOAD）
func _anchor_marks(holder: Control, d: Doll, labels := false, clear := true) -> void:
	if clear:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for g in ["LOW", "AIM", "RELOAD"]:
		var off: Vector2 = Doll.HAND_LOCAL[g]
		var sp := _plane_screen(d, off.x, off.y)
		var col: Color = Color(1, 0.25, 0.25) if g == "LOW" else (Color(0.3, 0.9, 1.0) if g == "AIM" else Color(1, 0.85, 0.25))
		var arm := 13.0 if labels else 6.0
		_box(holder, Vector2(sp.x - arm, sp.y), Vector2(arm * 2.0, 1.5), col)
		_box(holder, Vector2(sp.x, sp.y - arm), Vector2(1.5, arm * 2.0), col)
		_box(holder, sp - Vector2(2, 2), Vector2(4, 4), col)
		if labels:
			_text(holder, sp + Vector2(9, -26), "%s x=%.2f y=%.2f" % [g, off.x, off.y], col)
			print("  %s HAND_LOCAL=(%.2f, %.2f) screen=(%.1f,%.1f)" % [g, off.x, off.y, sp.x, sp.y])

func _box(holder: Control, pos: Vector2, size: Vector2, col: Color) -> void:
	var r := ColorRect.new()
	r.color = col
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(r)

func _line(holder: Control, a: Vector2, b: Vector2, major: bool) -> void:
	var r := ColorRect.new()
	r.color = Color(1, 0.72, 0.25, 0.55 if major else 0.20)
	if absf(a.x - b.x) < 0.5:
		r.position = Vector2(a.x, minf(a.y, b.y))
		r.size = Vector2(1, absf(b.y - a.y))
	else:
		r.position = Vector2(minf(a.x, b.x), a.y)
		r.size = Vector2(absf(b.x - a.x), 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(r)

func _text(holder: Control, pos: Vector2, s: String, col: Color) -> void:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)

func _prepare_dir() -> void:
	var dir := base_path.get_base_dir() if base_path.ends_with(".png") else base_path
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[capture] %s (err=%s) fps=%d" % [path, err, Engine.get_frames_per_second()])

