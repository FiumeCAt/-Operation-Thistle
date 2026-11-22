extends RefCounted
class_name DamageModel

## 2D 伤害、护甲与穿甲纯计算模型（无节点依赖、无全局状态）：
## 统一 Enemy2D 与 Doll2D 的受击结算公式；后续 RHA 护甲/穿甲重做仅需在此单一模块演进。

const PLAYER_ARMOR_BASE_REDUCTION := 0.30
const PLAYER_ARMOR_STEP_REDUCTION := 0.10
const PLAYER_ARMOR_MAX_REDUCTION := 0.65
const PLAYER_ARMOR_MIN_DURABILITY_SCALE := 0.40
const PLAYER_ARMOR_ABSORB_RATIO := 0.75
const PLAYER_ARMOR_MAX_ABSORB_RATIO := 0.95
const ENEMY_OVERPEN_STEP := 0.10


## 敌人受击结算（现行公式）：
##   ap > armor -> amount * (1 + (ap - armor) * 0.1)
##   ap <= armor -> max(1.0, amount - armor)
static func resolve_enemy_damage(amount: float, ap: float, armor: float) -> float:
	if amount <= 0.0:
		return 0.0
	if ap > armor:
		return amount * (1.0 + (ap - armor) * ENEMY_OVERPEN_STEP)
	return maxf(1.0, amount - armor)


## 玩家护甲减伤率（耐久归零时不减伤；AP 每 2 点抵消 1 级防御等级）。
static func player_damage_reduction(armor: int, armor_max: int,
		armor_level: int, ap: float) -> float:
	if armor <= 0:
		return 0.0
	var ap_levels := int(round(ap / 2.0))
	var effective_level := maxi(armor_level - ap_levels, 0)
	var base := 0.0
	if effective_level > 0:
		base = PLAYER_ARMOR_BASE_REDUCTION \
			+ PLAYER_ARMOR_STEP_REDUCTION * float(effective_level - 1)
	base = clampf(base, 0.0, PLAYER_ARMOR_MAX_REDUCTION)
	var durability_scale := lerpf(
		PLAYER_ARMOR_MIN_DURABILITY_SCALE, 1.0,
		float(armor) / maxf(1.0, float(armor_max))
	)
	return base * durability_scale


## 玩家受击结算：返回 {total, reduction, mitigated, armor_damage, hp_damage, new_armor, new_hp}。
static func resolve_player_damage(amount: float, ap: float,
		armor: int, armor_max: int, armor_level: int,
		armor_absorb_bonus: float, hp: int) -> Dictionary:
	if amount <= 0.0 or hp <= 0:
		return {
			"total": 0, "reduction": 0.0, "mitigated": 0,
			"armor_damage": 0, "hp_damage": 0,
			"new_armor": maxi(armor, 0), "new_hp": maxi(hp, 0),
		}
	var reduction := player_damage_reduction(armor, armor_max, armor_level, ap)
	var total := int(round(amount))
	var mitigated := maxi(1, int(round(float(total) * (1.0 - reduction))))
	var armor_part := 0
	if armor > 0:
		var absorb_ratio := clampf(
			PLAYER_ARMOR_ABSORB_RATIO + armor_absorb_bonus,
			0.0, PLAYER_ARMOR_MAX_ABSORB_RATIO
		)
		armor_part = clampi(int(round(float(mitigated) * absorb_ratio)), 0, mitigated)
	var armor_damage := mini(maxi(armor, 0), armor_part)
	var hp_damage := maxi(mitigated - armor_damage, 0)
	return {
		"total": total,
		"reduction": reduction,
		"mitigated": mitigated,
		"armor_damage": armor_damage,
		"hp_damage": hp_damage,
		"new_armor": maxi(armor - armor_damage, 0),
		"new_hp": maxi(hp - hp_damage, 0),
	}
