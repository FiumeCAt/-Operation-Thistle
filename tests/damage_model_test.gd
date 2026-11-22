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

	# ---- 2) 敌人固定 RHA 护甲：击穿余穿加伤 + 未击穿平滑曲线 ----
	_check(is_equal_approx(DAMAGE.resolve_enemy_damage(0.0, 0.0, 0.0), 0.0), "enemy 0 damage returns 0")
	# 用户指定示例：17 伤害、15 穿甲打 0 护甲 = 17 + 15 * 0.1 = 18.5
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(17.0, 15.0, 0.0), 18.5),
		"17 dmg / 15 AP vs 0 armor == 18.5 (overpen +0.1/pt)"
	)
	# 等穿：无余穿加伤也无减伤
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(30.0, 55.0, 55.0), 30.0),
		"ap == armor deals exact base damage (30.0)"
	)
	# 9mm (18 dmg, AP 22) vs rifleman (armor 18) -> penetrated: 18 + 4*0.1 = 18.4
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(18.0, 22.0, 18.0), 18.4),
		"9mm (AP 22) penetrates rifleman (18) -> 18.4"
	)
	# .338 (110 dmg, AP 180) vs heavy (armor 140) -> penetrated: 110 + 40*0.1 = 114.0
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(110.0, 180.0, 140.0), 114.0),
		".338 (AP 180) penetrates heavy (140) -> 114.0"
	)
	# 未击穿 0 AP 打重甲 -> 12% 钝伤保底
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(100.0, 0.0, 100.0), 12.0),
		"0 AP vs 100 armor hits 12% blunt floor (12.0)"
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
	_check(is_equal_approx(DAMAGE.effective_player_rha(50, 100, 30.0), 21.0), "50% durability -> 21.0 RHA (70%)")

	# 未击穿（30 伤 / 0 穿 vs 满甲 Lv1 30 RHA）：主扣甲（20），少钝伤（4）
	var p_unpen: Dictionary = DAMAGE.resolve_player_damage(30.0, 0.0, 100, 100, 1, 0.0, 100)
	_check(not bool(p_unpen["penetrated"]), "0 AP does not penetrate Lv1 30 RHA")
	_check(int(p_unpen["armor_damage"]) > int(p_unpen["hp_damage"]) and int(p_unpen["hp_damage"]) == 4,
		"unpenetrated hit drains armor mainly (%d) + light blunt hp (%d)" % [
			int(p_unpen["armor_damage"]), int(p_unpen["hp_damage"])])

	# 缓冲层 +15% 削减未击穿钝伤
	var p_unpen_gel: Dictionary = DAMAGE.resolve_player_damage(30.0, 15.0, 100, 100, 1, 0.15, 100)
	var p_unpen_plain: Dictionary = DAMAGE.resolve_player_damage(30.0, 15.0, 100, 100, 1, 0.0, 100)
	_check(int(p_unpen_gel["hp_damage"]) < int(p_unpen_plain["hp_damage"]),
		"armor_absorb_bonus reduces unpenetrated blunt HP damage (%d < %d)" % [
			int(p_unpen_gel["hp_damage"]), int(p_unpen_plain["hp_damage"])])

	# 击穿（30 伤 / 50 穿 vs 满甲 Lv1 30 RHA）：直扣血 32 + 少量穿孔甲损 8
	var p_pen: Dictionary = DAMAGE.resolve_player_damage(30.0, 50.0, 100, 100, 1, 0.0, 100)
	_check(bool(p_pen["penetrated"]), "50 AP penetrates Lv1 30 RHA")
	_check(int(p_pen["hp_damage"]) == 32 and int(p_pen["armor_damage"]) == 8,
		"penetrated hit deals overpen HP (32) + light hole wear (8), got hp=%d arm=%d" % [
			int(p_pen["hp_damage"]), int(p_pen["armor_damage"])])

	# 同样的 50 穿遇到 Lv2 (50 RHA) 刚好击穿无余穿；遇到 Lv3 (70 RHA) 被挡下转未击穿！
	var p_lv3: Dictionary = DAMAGE.resolve_player_damage(30.0, 50.0, 100, 100, 3, 0.0, 100)
	_check(not bool(p_lv3["penetrated"]) and int(p_lv3["hp_damage"]) < int(p_pen["hp_damage"]),
		"Lv3 (70 RHA) stops 50 AP and greatly reduces HP loss (%d < %d)" % [
			int(p_lv3["hp_damage"]), int(p_pen["hp_damage"])])

	# 破甲溢出（剩余 10 甲挡 30 伤 0 穿 -> 吃光 10 甲 + 溢出 10 + 钝伤 4 = 14 HP）
	var p_break: Dictionary = DAMAGE.resolve_player_damage(30.0, 0.0, 10, 100, 1, 0.0, 100)
	_check(int(p_break["new_armor"]) == 0 and int(p_break["hp_damage"]) == 14,
		"armor break consumes last 10 armor and overflows into HP (hp_dmg=%d)" % int(p_break["hp_damage"]))

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
		is_equal_approx(dealt, DAMAGE.resolve_enemy_damage(32.0, 95.0, float(enemy.stats["armor"]))),
		"Enemy2D.take_damage() matches RHA DamageModel (%.2f)" % dealt
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
