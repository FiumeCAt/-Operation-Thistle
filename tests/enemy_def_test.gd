extends SceneTree
## EnemyDef 独立单元测试：验证类型化配置解析、视野角、穿甲值、自爆标记与体型权重。
## godot --headless --path . --script res://tests/enemy_def_test.gd

const ENEMY_DEF := preload("res://scripts/actors/enemy/EnemyDef.gd")

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
	var rifle: EnemyDef = ENEMY_DEF.from_dict(&"rifleman", EnemyDB.stats(&"rifleman"))
	_check(rifle.kind == &"rifleman" and is_equal_approx(rifle.hp, 75.0)
		and is_equal_approx(rifle.armor, 18.0) and rifle.hit_material == "flesh"
		and rifle.archetype == &"human",
		"rifleman parses base hp/armor/material/archetype")
	_check(is_equal_approx(rifle.default_view_angle(), 110.0)
		and is_equal_approx(rifle.attack_ap(), 22.0)
		and not rifle.is_self_destruct_unit(),
		"rifleman view angle, attack AP, and self-destruct flag match")

	var turret: EnemyDef = ENEMY_DEF.from_dict(&"mobile_turret", EnemyDB.stats(&"mobile_turret"))
	_check(turret.behavior == "turret" and turret.burst == 2
		and is_equal_approx(turret.default_view_angle(), 150.0)
		and is_equal_approx(turret.attack_ap(), 35.0),
		"mobile_turret parses burst, 150-degree view, and 35 AP")

	var goliath: EnemyDef = ENEMY_DEF.from_dict(&"goliath", EnemyDB.stats(&"goliath"))
	_check(goliath.is_self_destruct_unit() and goliath.death_explode
		and is_equal_approx(goliath.explode_radius, 4.0)
		and is_equal_approx(goliath.explode_damage, 100.0)
		and is_equal_approx(goliath.explode_delay, 1.8),
		"goliath parses self-destruct parameters accurately")

	var heavy: EnemyDef = ENEMY_DEF.from_dict(&"heavy", EnemyDB.stats(&"heavy"))
	_check(heavy.melee and is_equal_approx(heavy.default_view_angle(), 100.0)
		and is_equal_approx(heavy.attack_ap(), 55.0)
		and is_equal_approx(heavy.hit_weight(), 1.8),
		"heavy melee angle, 55 AP, and 1.8 hit weight match")

	var hunter: EnemyDef = ENEMY_DEF.from_dict(&"hunter", EnemyDB.stats(&"hunter"))
	_check(hunter.blind and is_equal_approx(hunter.hit_weight(), 0.7)
		and is_equal_approx(hunter.attack_ap(), 12.0),
		"blind hunter clamps hit weight and uses default AP")

	_check(is_equal_approx(rifle.scaled_hp(1, 1.0), 75.0)
		and is_equal_approx(rifle.scaled_hp(2, 1.5), 75.0 * 1.1 * 1.5)
		and is_equal_approx(heavy.blunt_floor, 0.10) and hunter.archetype == &"mech",
		"scaled_hp and archetype/override fields apply accurately")

	var p := root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		_check(is_equal_approx(ENEMY_DEF.friendly_explosion_mul(p), 0.8),
			"standard raid keeps 0.8 friendly explosion multiplier")
		p.data["run_mode"] = "waves"
		p.data["map_id"] = "goliath_arena"
		_check(is_equal_approx(ENEMY_DEF.friendly_explosion_mul(p), 0.5),
			"goliath arena lowers friendly explosion multiplier to 0.5")
		p.reset_for_test()
	else:
		_check(is_equal_approx(ENEMY_DEF.friendly_explosion_mul(null), 0.8),
			"null progress falls back to 0.8 friendly explosion multiplier")

	print("\n=== enemy def: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
