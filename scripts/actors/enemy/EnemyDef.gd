extends RefCounted
class_name EnemyDef
## 敌人类型化只读配置对象：从 EnemyDB.stats(kind) 字典一次性解析，
## 替代 Enemy2D / 视觉 / 感知 / 战斗子系统里散落的无类型字符串字典读写。

var kind: StringName = &"rifleman"
var display_name: String = ""
## 敌人三系生态：mech（机械）/ human（人类）/ mutant（变异）；支持单单位覆写钝伤保底与肉伤倍率。
var archetype: StringName = &"human"
var blunt_floor: float = 0.14
var flesh_mul: float = 1.05
var hit_material: String = "metal"
var texture_path: String = ""
var frames_path: String = ""

var hp: float = 70.0
var armor: float = 0.0
var speed: float = 2.6
var damage: float = 7.0
var attack_range: float = 2.0
var view_range: float = 15.0
var hearing: float = 14.0
var cooldown: float = 1.2
var melee: bool = false
var patrol_radius: float = 6.0
var flees: bool = false
var strafe: bool = false
var blind: bool = false

var behavior: String = ""
var burst: int = 1
var burst_interval: float = 0.12
var charge_speed: float = 6.0
var charge_cooldown: float = 3.0
var explode_radius: float = 3.2
var explode_damage: float = 60.0
var explode_delay: float = 2.0
var death_explode: bool = false

var body_scale: float = 0.30
var collision_radius: float = 17.0

## Phase 4：可配置部位弱点区（严禁写死头部；由 enemies.json 三系默认或单单位覆写）。
var weakspot_enabled: bool = true
var weakspot_part: String = "head"
var weakspot_label: String = "头部"
var weakspot_offset_x: float = 0.0
var weakspot_offset_y_ratio: float = 0.80
var weakspot_flip_x: bool = false
var weakspot_radius: float = 11.0
var weakspot_tolerance: float = 1.18
var weakspot_armor_mul: float = 0.40
var weakspot_damage_mul: float = 1.80


static func from_dict(kind_id: StringName, raw: Dictionary) -> EnemyDef:
	var d := EnemyDef.new()
	d.kind = kind_id
	d.display_name = String(raw.get("name", String(kind_id)))
	d.hit_material = String(raw.get("hit_material", "metal"))
	var default_arch := "mech" if d.hit_material == "metal" else "human"
	d.archetype = StringName(raw.get("archetype", default_arch))
	var arch_profile := EnemyDB.archetype_profile(d.archetype)
	d.blunt_floor = clampf(float(raw.get("blunt_floor", arch_profile.get("blunt_floor", 0.14))), 0.02, 0.80)
	d.flesh_mul = clampf(float(raw.get("flesh_mul", arch_profile.get("flesh_mul", 1.0))), 0.5, 2.0)
	d.texture_path = String(raw.get("texture", ""))
	d.frames_path = String(raw.get("frames", ""))

	d.hp = float(raw.get("hp", 70.0))
	d.armor = float(raw.get("armor", 0.0))
	d.speed = float(raw.get("speed", 2.6))
	d.damage = float(raw.get("damage", 7.0))
	d.attack_range = float(raw.get("range", 2.0))
	d.view_range = float(raw.get("view_range", 15.0))
	d.hearing = float(raw.get("hearing", 14.0))
	d.cooldown = float(raw.get("cooldown", 1.2))
	d.melee = bool(raw.get("melee", false))
	d.patrol_radius = float(raw.get("patrol_radius", 6.0))
	d.flees = bool(raw.get("flees", false))
	d.strafe = bool(raw.get("strafe", false))
	d.blind = bool(raw.get("blind", false))

	d.behavior = String(raw.get("behavior", ""))
	d.burst = int(raw.get("burst", 1))
	d.burst_interval = float(raw.get("burst_interval", 0.12))
	d.charge_speed = float(raw.get("charge_speed", 6.0))
	d.charge_cooldown = float(raw.get("charge_cooldown", 3.0))
	d.explode_radius = float(raw.get("explode_radius", 3.2))
	d.explode_damage = float(raw.get("explode_damage", 60.0))
	d.explode_delay = float(raw.get("explode_delay", 2.0))
	d.death_explode = bool(raw.get("death_explode", false))

	d.body_scale = float(raw.get("body_scale", 0.30))
	d.collision_radius = float(raw.get("collision_radius", 17.0))

	# 解析可配置部位弱点：单单位 weakspot 字典优先，缺失键回退至所属 archetype 默认弱点配置。
	var arch_ws: Dictionary = arch_profile.get("weakspot", {}) if arch_profile.get("weakspot") is Dictionary else {}
	var raw_ws_val = raw.get("weakspot", null)
	if raw.has("weakspot") and raw_ws_val == null:
		d.weakspot_enabled = false
	else:
		var unit_ws: Dictionary = raw_ws_val if raw_ws_val is Dictionary else {}
		d.weakspot_enabled = bool(unit_ws.get("enabled", arch_ws.get("enabled", true)))
		d.weakspot_part = String(unit_ws.get("part", arch_ws.get("part", "head")))
		d.weakspot_label = String(unit_ws.get("label", arch_ws.get("label", "弱点")))
		d.weakspot_offset_x = float(unit_ws.get("offset_x", arch_ws.get("offset_x", 0.0)))
		d.weakspot_offset_y_ratio = clampf(
			float(unit_ws.get("offset_y_ratio", arch_ws.get("offset_y_ratio", 0.72))), 0.10, 0.96)
		d.weakspot_flip_x = bool(unit_ws.get("flip_x", arch_ws.get("flip_x", false)))
		d.weakspot_radius = clampf(
			float(unit_ws.get("radius", arch_ws.get("radius", d.collision_radius * 0.65))), 4.0, 48.0)
		d.weakspot_tolerance = clampf(
			float(unit_ws.get("tolerance", arch_ws.get("tolerance", 1.18))), 1.0, 1.50)
		d.weakspot_armor_mul = clampf(
			float(unit_ws.get("armor_mul", arch_ws.get("armor_mul", 0.50))), 0.0, 1.0)
		d.weakspot_damage_mul = clampf(
			float(unit_ws.get("damage_mul", arch_ws.get("damage_mul", 1.60))), 1.0, 4.0)
	return d


## 弱点有效判定半径（叠加 +15%~20% 宽容系数，提升俯视像素射击的精准命中体感）。
func effective_weakspot_radius() -> float:
	return weakspot_radius * weakspot_tolerance


## 弱点在敌人本地坐标系下的中心偏移（按立绘高度比例与朝向翻转计算，绝不写死头部）。
func weakspot_local_offset(sprite_h: float, facing_left: bool = false) -> Vector2:
	var h := maxf(sprite_h, 48.0)
	var ox := -weakspot_offset_x if (weakspot_flip_x and facing_left) else weakspot_offset_x
	return Vector2(ox, -h * weakspot_offset_y_ratio)


## 按深度与倍率计算最终最大血量。
func scaled_hp(depth: int, hp_mul := 1.0) -> float:
	return hp * pow(1.1, float(maxi(depth - 1, 0))) * maxf(hp_mul, 0.01)


## 扇形视野总角度：炮塔更宽，近战单位略窄，普通枪兵 110°。
func default_view_angle() -> float:
	if behavior == "turret":
		return 150.0
	if melee:
		return 100.0
	return 110.0


## 敌人攻击穿甲值（0.1 mm RHA 体系）：区分普通近战/9mm 与装甲单位高穿火力。
func attack_ap() -> float:
	match kind:
		&"rifleman":
			return 22.0
		&"sentry_type1":
			return 25.0
		&"mobile_turret":
			return 35.0
		&"hunter_type1":
			return 40.0
		&"heavy":
			return 55.0
		_:
			return 12.0


## 自爆单位：哥利亚这类单位血量不会归零，而是锁在 1 点并点燃引信。
func is_self_destruct_unit() -> bool:
	return death_explode or behavior == "suicide"


## 体型权重：大血量单位吃枪时反馈更重（火花更多、低频更沉）。
func hit_weight() -> float:
	return clampf(hp / 100.0, 0.7, 1.8)


## 爆炸友伤比例：歌利亚狂潮内降到 50%，减少歌利亚互相引爆；其他模式保持 80%。
static func friendly_explosion_mul(progress: Node) -> float:
	if progress != null and progress.has_method("map_id") \
			and String(progress.run_mode()) == "waves" \
			and String(progress.map_id()) == "goliath_arena":
		return 0.5
	return 0.8
