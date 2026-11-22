extends SceneTree
## DamageModel 黄金基准与 Doll2D / Enemy2D 运行时一致性测试（Step 2.3）：
## 1. 锁定敌人受击公式（零甲 / 等穿 / 超穿加成 / 穿甲不足 1 点保底 / 零伤害）。
## 2. 锁定玩家受击公式（零甲 / 满甲 Lv1 / 残甲耐久衰减 / 高级甲 65% 上限 / AP 抵消 / 吸收加成 / 破甲溢出）。
## 3. 验证 Enemy2D.take_damage() 与 Doll2D.take_damage() 与 DamageModel 100% 一致。

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
	print("=== damage_model_test ===")

	# ---- 1) 敌人受击公式 ----
	_check(is_equal_approx(DAMAGE.resolve_enemy_damage(0.0, 0.0, 0.0), 0.0), "enemy 0 damage returns 0")
	_check(is_equal_approx(DAMAGE.resolve_enemy_damage(18.0, 0.0, 1.0), 17.0), "9mm vs rifleman armor 1 == 17.0")
	_check(is_equal_approx(DAMAGE.resolve_enemy_damage(4.0, 0.0, 6.0), 1.0), "low damage vs heavy armor floors at 1.0")
	_check(is_equal_approx(DAMAGE.resolve_enemy_damage(30.0, 3.0, 3.0), 27.0), "ap == armor subtracts armor (30-3=27)")
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(32.0, 5.0, 1.0), 32.0 * 1.4),
		"5.56 (AP 5) vs armor 1 gets +40% overpen (44.8)"
	)
	_check(
		is_equal_approx(DAMAGE.resolve_enemy_damage(110.0, 8.0, 6.0), 110.0 * 1.2),
		".338 (AP 8) vs heavy armor 6 gets +20% overpen (132.0)"
	)

	# ---- 2) 玩家护甲减伤率与吸收溢出 ----
	_check(is_equal_approx(DAMAGE.player_damage_reduction(0, 100, 1, 0.0), 0.0), "0 armor gives 0 reduction")
	_check(is_equal_approx(DAMAGE.player_damage_reduction(100, 100, 1, 0.0), 0.30), "full Lv1 armor gives 30% reduction")
	_check(
		is_equal_approx(DAMAGE.player_damage_reduction(50, 100, 1, 0.0), 0.30 * 0.70),
		"50% durability Lv1 armor scales reduction to 21%"
	)
	_check(
		is_equal_approx(DAMAGE.player_damage_reduction(100, 100, 10, 0.0), 0.65),
		"high armor level caps base reduction at 65%"
	)
	_check(
		is_equal_approx(DAMAGE.player_damage_reduction(100, 100, 2, 2.0), 0.30),
		"AP 2 strips 1 armor level (Lv2 -> Lv1 = 30%)"
	)
	_check(
		is_equal_approx(DAMAGE.player_damage_reduction(100, 100, 1, 4.0), 0.0),
		"AP 4 zeroes Lv1 armor reduction"
	)

	var p_full: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 100, 100, 1, 0.0, 100)
	_check(int(p_full["mitigated"]) == 14, "20 dmg vs full Lv1 mitigates to 14")
	_check(int(p_full["armor_damage"]) == 11 and int(p_full["hp_damage"]) == 3,
		"75% absorb splits 14 -> 11 armor / 3 hp")
	_check(int(p_full["new_armor"]) == 89 and int(p_full["new_hp"]) == 97,
		"post-hit state 89 armor / 97 hp")

	var p_bonus: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 100, 100, 1, 0.15, 100)
	_check(int(p_bonus["armor_damage"]) == 13 and int(p_bonus["hp_damage"]) == 1,
		"+15% absorb bonus (90%) splits 14 -> 13 armor / 1 hp")

	var p_break: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 4, 100, 1, 0.0, 100)
	# durability_scale = lerp(0.4, 1.0, 0.04) = 0.424 -> reduction = 0.1272 -> mitigated = round(17.456) = 17
	_check(int(p_break["mitigated"]) == 17, "near-broken armor mitigates 20 -> 17")
	_check(int(p_break["armor_damage"]) == 4 and int(p_break["hp_damage"]) == 13,
		"armor break absorbs remaining 4 and overflows 13 to HP")
	_check(int(p_break["new_armor"]) == 0 and int(p_break["new_hp"]) == 87,
		"post-break state 0 armor / 87 hp")

	var p_naked: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 0, 100, 1, 0.0, 100)
	_check(int(p_naked["armor_damage"]) == 0 and int(p_naked["hp_damage"]) == 20,
		"0 armor sends full 20 damage to HP")

	var p_floor: Dictionary = DAMAGE.resolve_player_damage(0.2, 0.0, 100, 100, 5, 0.0, 100)
	_check(int(p_floor["mitigated"]) == 1, "positive damage floors at mitigated == 1")

	# ---- 3) 与实机节点 Enemy2D / Doll2D 一致性验证 ----
	var enemy := Enemy2D.new()
	enemy.setup(&"rifleman", Vector2.ZERO, 1)
	root.add_child(enemy)
	await process_frame
	enemy.hp = 100.0
	var dealt: float = enemy.take_damage(32.0, 5.0)
	_check(
		is_equal_approx(dealt, DAMAGE.resolve_enemy_damage(32.0, 5.0, float(enemy.stats["armor"]))),
		"Enemy2D.take_damage() matches DamageModel.resolve_enemy_damage()"
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
	doll.invuln = 0.0
	var expected: Dictionary = DAMAGE.resolve_player_damage(20.0, 0.0, 100, 100, 1, 0.0, 100)
	doll.take_damage(20.0, 0.0)
	_check(doll.armor == int(expected["new_armor"]) and doll.hp == int(expected["new_hp"]),
		"Doll2D.take_damage() matches DamageModel.resolve_player_damage()")
	doll.queue_free()
	await process_frame

	print("=== damage_model_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
