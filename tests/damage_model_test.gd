extends SceneTree
## RHA 均质装甲与穿深系统黄金基准 + Doll2D / Enemy2D 运行时一致性测试：
## 1. 验证 0.1mm RHA 双显示格式化（46 vs 4.6mm RHA）。
## 2. 验证敌人固定 RHA 护甲公式：击穿余穿加伤（含 17 伤 15 穿打 0 甲 = 18.5）、未击穿平滑衰减曲线与 12% 钝伤保底。
## 3. 验证玩家护甲耐久与 RHA 规则：
##    - 未击穿主扣甲+少量钝伤（护甲先破、破甲溢出）
##    - 击穿直扣血+少量穿孔甲损
##    - 残甲有效 RHA 衰减（100% -> 40%）
##    - 耐久归零失去基础减伤，仅受 min_damage_reduction 保底保护
## 4. 验证实机节点 Enemy2D.take_damage() 与 Doll2D.take_damage() 与 DamageModel 100% 一致。

const DAMAGE := preload("res://scripts/combat/DamageModel.gd")

var _ok := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	print("=== damage_model_test (RHA) ===")

	# ---- 1) 双显示格式化 ----
	_check(DAMAGE.format_rha(46.0, "value") == "46", "format_rha value mode: 46 -> '46'")
	_check(DAMAGE.format_rha(46.0, "rha_mm") == "4.6mm RHA", "format_rha rha_mm mode: 46 -> '4.6mm RHA'")
	_check(DAMAGE.format_rha(180.0, "rha_mm") == "18.0mm RHA", "format_rha .338: 180 -> '18.0mm RHA'")

	# ---- 2) 敌人固定 RHA 护甲（Phase 3B：无甲无余穿加伤 + 有甲余穿封顶 + 三系钝伤与肉伤倍率） ----
	_check(is_equal_approx(DAMAGE.resolve_enemy_damage(0.0, 0.0, 0.0), 0.0), "enemy 0 damage returns 0")
	# 无甲目标不吃余穿增伤（防止高穿弹在无甲变异体上反超肉伤弹）
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(17.0, 15.0, 0.0), 17.0),
		"17 dmg / 15 AP vs 0 armor == 17.0 (no unarmored overpen inflation)"
	)
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(20.0, 12.0, 0.0, 0.22, 1.20), 24.0),
		"flesh ammo vs 0-armor mutant gets 1.20x flesh multiplier (24.0)"
	)
	# 等穿：无余穿加伤也无减伤
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(30.0, 55.0, 55.0), 30.0),
		"ap == armor deals exact base damage (30.0)"
	)
	# 击穿有甲目标：余穿增伤按 0.08/pt 且封顶 30pt (+2.4)
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(19.0, 32.0, 18.0), 19.0 + 14.0 * 0.08),
		"9mm FMJ (AP 32) penetrates rifleman (18) -> 20.12"
	)
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(102.0, 185.0, 125.0), 102.0 + 30.0 * 0.08),
		".338 AP (185) penetrates heavy (125) -> capped overpen +2.4 (104.4)"
	)
	# 未击穿 0 AP 打重甲 -> 默认 12% 钝伤保底；机械 8% / 变异 22%
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(100.0, 0.0, 100.0), 12.0),
		"0 AP vs 100 armor hits default 12% blunt floor (12.0)"
	)
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(100.0, 0.0, 100.0, 0.08), 8.0)
		and is_equal_approx(DAMAGE.resolve_enemy_damage(100.0, 0.0, 100.0, 0.22), 22.0),
		"mech (8%) resists blunt more than mutant bone carapace (22%)"
	)
	# 未击穿平滑曲线：50% 穿深 -> lerp(0.12, 1.0, 0.25) = 0.34；80% 穿深 -> lerp(0.12, 1.0, 0.64) = 0.6832
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(100.0, 50.0, 100.0), 34.0),
		"50% AP/armor ratio deals 34.0% smooth damage"
	)
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(100.0, 80.0, 100.0), 68.32),
		"80% AP/armor ratio deals 68.32% smooth damage"
	)
	# 极低基础伤害打重甲保底 1.0
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(2.0, 0.0, 140.0), 1.0),
		"tiny unpenetrated hit floors at 1.0"
	)

	# ---- 3) 玩家护甲耐久与 RHA 规则 ----
	_check(is_equal_approx(DAMAGE.player_base_rha(1), 30.0), "Lv1 base RHA == 30 (3.0mm)")
	_check(is_equal_approx(DAMAGE.player_base_rha(2), 50.0), "Lv2 base RHA == 50 (5.0mm)")
	_check(is_equal_approx(DAMAGE.player_base_rha(1, 15.0), 45.0), "armor_rha_bonus adds cleanly (45)")
	_check(is_equal_approx(DAMAGE.effective_player_rha(0, 100, 30.0), 0.0), "0 durability -> 0 effective RHA")
	_check(is_equal_approx(DAMAGE.effective_player_rha(100, 100, 30.0), 30.0), "100% durability -> 30.0 RHA")
	_check(is_equal_approx(DAMAGE.effective_player_rha(50, 100, 30.0), 22.5), "50% durability -> 22.5 RHA (75%)")

	# 未击穿（30 伤 / 0 穿 vs 满甲 Lv1 30 RHA）：主扣甲（28），极轻钝伤（2）
	var p_unpen: Dictionary = DAMAGE.resolve_player_damage(30.0, 0.0, 100, 100, 1, 0.0, 100)
	_check(not bool(p_unpen["penetrated"]), "0 AP does not penetrate Lv1 30 RHA")
	_check(int(p_unpen["armor_damage"]) == 28 and int(p_unpen["hp_damage"]) == 2,
		"unpenetrated hit drains armor mainly (%d) + light blunt hp (%d)" % [
			int(p_unpen["armor_damage"]), int(p_unpen["hp_damage"])])

	# 缓冲层 +15% 削减未击穿钝伤
	var p_unpen_gel: Dictionary = DAMAGE.resolve_player_damage(60.0, 25.0, 100, 100, 1, 0.15, 100)
	var p_unpen_plain: Dictionary = DAMAGE.resolve_player_damage(60.0, 25.0, 100, 100, 1, 0.0, 100)
	_check(int(p_unpen_gel["hp_damage"]) < int(p_unpen_plain["hp_damage"]),
		"armor_absorb_bonus reduces unpenetrated blunt HP damage (%d < %d)" % [
			int(p_unpen_gel["hp_damage"]), int(p_unpen_plain["hp_damage"])])

	# 击穿（30 伤 / 50 穿 vs 满甲 Lv1 30 RHA）：25%~50% 穿血 (11) + 剧烈碎甲 (35)，护甲掉得仍比血快
	var p_pen: Dictionary = DAMAGE.resolve_player_damage(30.0, 50.0, 100, 100, 1, 0.0, 100)
	_check(bool(p_pen["penetrated"]), "50 AP penetrates Lv1 30 RHA")
	_check(int(p_pen["hp_damage"]) == 11 and int(p_pen["armor_damage"]) == 35
		and int(p_pen["armor_damage"]) > int(p_pen["hp_damage"])
		and int(p_pen["hp_damage"]) > int(p_unpen["hp_damage"]),
		"penetrated hit deals higher HP (11) + heavy armor shatter (35), got hp=%d arm=%d" % [
			int(p_pen["hp_damage"]), int(p_pen["armor_damage"])])

	# 同样的 50 穿遇到 Lv3 (70 RHA) 被挡下转未击穿，穿血与甲损同步显著降低
	var p_lv3: Dictionary = DAMAGE.resolve_player_damage(30.0, 50.0, 100, 100, 3, 0.0, 100)
	_check(not bool(p_lv3["penetrated"]) and int(p_lv3["hp_damage"]) < int(p_pen["hp_damage"]),
		"Lv3 (70 RHA) stops 50 AP and greatly reduces HP loss (%d < %d)" % [
			int(p_lv3["hp_damage"]), int(p_pen["hp_damage"])])

	# 破甲边界平滑插值（剩余 10 甲挡 30 伤 0 穿 -> 吃光 10 甲，血伤 20 介于满甲 2 与空甲 30 之间）
	var p_break: Dictionary = DAMAGE.resolve_player_damage(30.0, 0.0, 10, 100, 1, 0.0, 100)
	_check(int(p_break["new_armor"]) == 0 and int(p_break["hp_damage"]) == 20,
		"armor break smoothly interpolates overflow HP (hp_dmg=%d)" % int(p_break["hp_damage"]))

	# 击穿破甲单调性（歌利亚 100 伤 45 穿：空甲 > 10残甲 > 满甲）
	var p_gol_0: Dictionary = DAMAGE.resolve_player_damage(100.0, 45.0, 0, 100, 1, 0.0, 100)
	var p_gol_10: Dictionary = DAMAGE.resolve_player_damage(100.0, 45.0, 10, 100, 1, 0.0, 100)
	var p_gol_100: Dictionary = DAMAGE.resolve_player_damage(100.0, 45.0, 100, 100, 1, 0.0, 100)
	_check(int(p_gol_0["hp_damage"]) > int(p_gol_10["hp_damage"])
		and int(p_gol_10["hp_damage"]) > int(p_gol_100["hp_damage"])
		and int(p_gol_100["new_armor"]) == 0 and int(p_gol_100["new_hp"]) > 0,
		"goliath blast scales monotonically by armor (0:%d > 10:%d > 100:%d) and breaks full Lv1 armor first" % [
			int(p_gol_0["hp_damage"]), int(p_gol_10["hp_damage"]), int(p_gol_100["hp_damage"])])

	# 游戏性硬约束：全敌种（含高穿炮塔/重装/高穿狙击）连续受击时，护甲一律先于血条归零（不会人死甲还在）
	var all_break_first := true
	for profile in [
		[9.0, 12.0], [7.0, 22.0], [12.0, 25.0],
		[10.0, 35.0], [25.0, 40.0], [14.0, 55.0], [45.0, 120.0]
	]:
		var sim_hp := 100
		var sim_arm := 100
		var steps := 0
		while sim_hp > 0 and steps < 60:
			var r: Dictionary = DAMAGE.resolve_player_damage(float(profile[0]), float(profile[1]),
				sim_arm, 100, 1, 0.0, sim_hp)
			sim_arm = int(r["new_armor"])
			sim_hp = int(r["new_hp"])
			steps += 1
			if sim_hp <= 0 and sim_arm > 0:
				all_break_first = false
				break
		if not all_break_first:
			break
	_check(all_break_first, "armor always breaks before player death across all enemy AP profiles")

	# 耐久归零：无基础减伤（20 伤 0 穿 -> 20 HP）；提供 20% min_reduction 时 -> 16 HP
	var p_naked: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 0, 100, 1, 0.0, 100)
	_check(int(p_naked["armor_damage"]) == 0 and int(p_naked["hp_damage"]) == 20,
		"0 durability removes base armor protection (20 -> 20 HP)")
	var p_floor_red: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 0, 100, 1, 0.0, 100, 0.0, 0.20)
	_check(int(p_floor_red["armor_damage"]) == 0 and int(p_floor_red["hp_damage"]) == 16,
		"0 durability still honors min_reduction floor (20% -> 16 HP)")

	# ---- 4) 与实机节点 Enemy2D / Doll2D 一致性验证 ----
	var enemy := Enemy2D.new()
	enemy.setup(&"rifleman", Vector2.ZERO, 1)
	root.add_child(enemy)
	await process_frame
	enemy.hp = 100.0
	var dealt: float = enemy.take_damage(32.0, 95.0)
	_check(
		is_equal_approx(dealt, DAMAGE.resolve_enemy_damage(32.0, 95.0, float(enemy.stats["armor"]), enemy.def.blunt_floor, 1.0)),
		"Enemy2D.take_damage() matches RHA DamageModel (%.2f)" % dealt
	)
	var dealt_flesh: float = enemy.take_damage(20.0, 30.0, Vector2.ZERO, true)
	_check(
		is_equal_approx(dealt_flesh, DAMAGE.resolve_enemy_damage(20.0, 30.0, float(enemy.stats["armor"]), enemy.def.blunt_floor, enemy.def.flesh_mul)),
		"Enemy2D.take_damage() applies archetype flesh_mul for flesh ammo (%.2f)" % dealt_flesh
	)
	enemy.queue_free()

	var doll: Doll2D = load("res://scenes/actors/Doll2D.tscn").instantiate()
	root.add_child(doll)
	await process_frame
	doll.hp = 100
	doll.hp_max = 100
	doll.armor = 100
	doll.armor_max = 100
	doll.armor_level = 1
	doll.armor_absorb_bonus = 0.0
	doll.min_damage_reduction = 0.0
	doll.invuln = 0.0
	var expected: Dictionary = DAMAGE.resolve_player_damage(30.0, 50.0, 100, 100, 1, 0.0, 100)
	doll.take_damage(30.0, 50.0)
	_check(doll.armor == int(expected["new_armor"]) and doll.hp == int(expected["new_hp"]),
		"Doll2D.take_damage() matches RHA DamageModel (arm=%d hp=%d)" % [doll.armor, doll.hp])
	doll.queue_free()
	await process_frame

	print("=== damage_model_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
