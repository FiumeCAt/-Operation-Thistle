extends RefCounted
class_name DamageModel

## 2D RHA 均质装甲与穿深纯计算模型（无节点依赖、无全局状态）：
##
## 单位约定：
##   内部采用 0.1 mm RHA 整数制（1 点 = 0.1 mm 均质装甲钢，如 46 = 4.6 mm RHA）。
##   UI 可按 Progress.data["armor_display"] 在 "value"（46）与 "rha_mm"（4.6mm RHA）间切换。
##
## 固定穿甲（不随距离衰减）+ 平滑过渡曲线 + 余穿加伤：
##   1. 击穿（ap >= eff_armor）：
##        dmg = amount + (ap - eff_armor) * 0.1
##   2. 未击穿（ap < eff_armor）：
##        r = clamp(ap / eff_armor, 0, 1)
##        blunt_mul = lerp(0.12, 1.0, r * r)
##        dmg = max(1.0, amount * blunt_mul)
##
## 玩家护甲耐久规则（护罩手感 × RHA 穿深折中方案）：
##   - 满耐久发挥 100% 标称 RHA 防护，残甲按耐久线性缓降至 50%；耐久耗尽时有效 RHA = 0。
##   - 未击穿（ap < eff_rha）：主要消耗护甲耐久 + 极轻钝伤入血（5%~20%）。
##   - 击穿（ap >= eff_rha）：护甲仍强行阻滞并剧烈碎裂——25%~50% 穿透入血，同时承受 100%~130% 碎甲耐久损耗，
##     保证常规战斗与穿透打击下护甲通常先于血条掉光。
##   - 破甲边界：剩余护甲不足本次耐久消耗时，按实际吸收比例在“满甲受击”与“空甲受击”间平滑插值，避免突变。
##   - 耐久归零：不再享受护甲基础减伤，仅受 min_reduction（护甲组件/天赋最低减伤率）保护。

const OVERPEN_BONUS_PER_POINT := 0.08
const OVERPEN_MAX_EXCESS := 30.0
const PLAYER_OVERPEN_PER_POINT := 0.10
const NON_PEN_BLUNT_FLOOR := 0.12
const PLAYER_BASE_RHA := 30.0          # 默认 Lv1 护甲 = 30 (3.0mm RHA)
const PLAYER_RHA_PER_LEVEL := 20.0     # 每提升 1 级防御 / 装甲组件 = +20 (+2.0mm RHA)
const PLAYER_MIN_DURABILITY_SCALE := 0.50
const PLAYER_UNPEN_MIN_HP_RATIO := 0.05
const PLAYER_UNPEN_MAX_HP_RATIO := 0.20
const PLAYER_PEN_MIN_HP_RATIO := 0.25
const PLAYER_PEN_MAX_HP_RATIO := 0.50
const PLAYER_PEN_ARMOR_WEAR_MIN := 1.00
const PLAYER_PEN_ARMOR_WEAR_MAX := 1.30
const PLAYER_MAX_ABSORB_BONUS := 0.50
const PLAYER_MAX_MIN_REDUCTION := 0.65
## 兼容旧常量引用（Armory / 测试可读取）。
const PLAYER_ARMOR_BASE_REDUCTION := 0.30
const PLAYER_ARMOR_ABSORB_RATIO := 0.75


## 格式化护甲防御力 / 穿深文本：
##   mode == "rha_mm" -> "4.6mm RHA"
##   mode == "value"  -> "46"
static func format_rha(value: float, mode: String = "value") -> String:
	if mode == "rha_mm":
		return "%.1fmm RHA" % (value * 0.1)
	return "%d" % int(round(value))


## 是否击穿目标当前有效 RHA 防护。
static func is_penetrated(ap: float, effective_armor: float) -> bool:
	return effective_armor <= 0.0 or ap >= effective_armor


## 敌人受击结算（Phase 3B：无甲不吃余穿增伤 + 有甲余穿封顶 + 三系生态钝伤保底与肉伤倍率）：
##   armor <= 0            -> amount * flesh_mul
##   armor > 0, ap >= armor -> (amount + min(ap - armor, 30) * 0.08) * flesh_mul
##   armor > 0, ap <  armor -> max(1.0, amount * lerp(blunt_floor, 1.0, (ap / armor)^2))
static func resolve_enemy_damage(amount: float, ap: float, armor: float,
		blunt_floor: float = NON_PEN_BLUNT_FLOOR, flesh_mul: float = 1.0) -> float:
	if amount <= 0.0:
		return 0.0
	var eff_armor := maxf(armor, 0.0)
	var eff_ap := maxf(ap, 0.0)
	var f_mul := maxf(flesh_mul, 0.1)
	if eff_armor <= 0.0:
		return amount * f_mul
	if is_penetrated(eff_ap, eff_armor):
		var excess := minf(eff_ap - eff_armor, OVERPEN_MAX_EXCESS)
		return (amount + excess * OVERPEN_BONUS_PER_POINT) * f_mul
	var r := clampf(eff_ap / eff_armor, 0.0, 1.0)
	var floor_val := clampf(blunt_floor, 0.02, 0.80)
	var blunt_mul := lerpf(floor_val, 1.0, r * r)
	return maxf(1.0, amount * blunt_mul)


## 玩家满耐久时的标称 RHA 防御值（0.1 mm 单位）。
static func player_base_rha(armor_level: int, armor_rha_bonus: float = 0.0) -> float:
	var lv := maxi(armor_level, 1)
	return maxf(0.0, PLAYER_BASE_RHA + PLAYER_RHA_PER_LEVEL * float(lv - 1) + armor_rha_bonus)


## 玩家当前有效 RHA 防御值：耐久归零时为 0；否则随耐久在 40%~100% 间线性缩放。
static func effective_player_rha(armor: int, armor_max: int, base_rha: float) -> float:
	if armor <= 0 or base_rha <= 0.0:
		return 0.0
	var durability_scale := lerpf(
		PLAYER_MIN_DURABILITY_SCALE, 1.0,
		clampf(float(armor) / maxf(1.0, float(armor_max)), 0.0, 1.0)
	)
	return base_rha * durability_scale


## 玩家受击结算：返回 {total, effective_rha, penetrated, mitigated, armor_damage, hp_damage, new_armor, new_hp}。
static func resolve_player_damage(amount: float, ap: float,
		armor: int, armor_max: int, armor_level: int,
		armor_absorb_bonus: float, hp: int,
		armor_rha_bonus: float = 0.0, min_reduction: float = 0.0) -> Dictionary:
	if amount <= 0.0 or hp <= 0:
		return {
			"total": 0, "effective_rha": 0.0, "penetrated": false, "mitigated": 0,
			"armor_damage": 0, "hp_damage": 0,
			"new_armor": maxi(armor, 0), "new_hp": maxi(hp, 0),
		}
	var total := int(round(amount))
	var eff_ap := maxf(ap, 0.0)
	var base_rha := player_base_rha(armor_level, armor_rha_bonus)
	var eff_rha := effective_player_rha(armor, armor_max, base_rha)
	var floor_red := clampf(min_reduction, 0.0, PLAYER_MAX_MIN_REDUCTION)
	var penetrated := is_penetrated(eff_ap, eff_rha)

	var armor_damage := 0
	var hp_damage := 0
	var bare_hp := maxi(1, int(round((amount + eff_ap * PLAYER_OVERPEN_PER_POINT) * (1.0 - floor_red))))
	if armor <= 0:
		# 耐久耗尽：不再享受护甲基础减伤，仅受组件/天赋提供的最低减伤率保护。
		hp_damage = bare_hp
	else:
		var armored_hp := 0
		var armor_need := 1
		if penetrated:
			# 击穿（偏护罩碎甲模型）：25%~50% 穿透入血 + 100%~130% 碎甲损耗，保证护甲通常先碎。
			var over_t := clampf((eff_ap - eff_rha) / maxf(eff_rha, 10.0), 0.0, 2.0) * 0.5
			var eff_dmg := amount + (eff_ap - eff_rha) * PLAYER_OVERPEN_PER_POINT
			var hp_ratio := lerpf(PLAYER_PEN_MIN_HP_RATIO, PLAYER_PEN_MAX_HP_RATIO, over_t)
			armored_hp = maxi(1, int(round(eff_dmg * hp_ratio * (1.0 - floor_red))))
			var wear := lerpf(PLAYER_PEN_ARMOR_WEAR_MIN, PLAYER_PEN_ARMOR_WEAR_MAX, over_t)
			armor_need = maxi(1, int(round(eff_dmg * wear)))
		else:
			# 未击穿：5%~20% 极轻钝伤入血，其余全部由护甲耐久吸收。
			var r := clampf(eff_ap / eff_rha, 0.0, 1.0)
			var absorb_cut := 1.0 - clampf(armor_absorb_bonus, 0.0, PLAYER_MAX_ABSORB_BONUS)
			var blunt_ratio := lerpf(PLAYER_UNPEN_MIN_HP_RATIO, PLAYER_UNPEN_MAX_HP_RATIO, r * r) * absorb_cut
			armored_hp = maxi(1, int(round(amount * blunt_ratio * (1.0 - floor_red))))
			var stopped := maxf(amount - float(armored_hp), 0.0)
			armor_need = maxi(1, int(round(stopped)))
		armor_damage = mini(armor, armor_need)
		var absorbed_frac := float(armor_damage) / float(armor_need)
		hp_damage = maxi(1, int(round(lerpf(float(bare_hp), float(armored_hp), absorbed_frac))))

	return {
		"total": total,
		"effective_rha": eff_rha,
		"penetrated": penetrated,
		"mitigated": armor_damage + hp_damage,
		"armor_damage": armor_damage,
		"hp_damage": hp_damage,
		"new_armor": maxi(armor - armor_damage, 0),
		"new_hp": maxi(hp - hp_damage, 0),
	}
