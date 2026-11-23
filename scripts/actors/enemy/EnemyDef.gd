extends RefCounted
class_name EnemyDef
## 敌人类型化只读配置对象：从 EnemyDB.stats(kind) 字典一次性解析，
## 替代 Enemy2D / 视觉 / 感知 / 战斗子系统里散落的无类型字符串字典读写。

var kind: StringName = &"rifleman"
var display_name: String = ""
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


static func from_dict(kind_id: StringName, raw: Dictionary) -> EnemyDef:
	var d := EnemyDef.new()
	d.kind = kind_id
	d.display_name = String(raw.get("name", String(kind_id)))
	d.hit_material = String(raw.get("hit_material", "metal"))
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
	return d


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
