extends RefCounted
class_name WeaponDB
## 武器/弹药数据表。数值来自 data/weapons.json 与 data/ammo.json；
## 武器视觉参数（贴图、握把/枪口像素、枪长）优先从
## assets/art/weapons/<id>/meta.json 读取，读不到时用表里的 visual_length 兜底。

static var WEAPON_ORDER: Array[StringName] = _load_weapon_order()
static var AMMO_ORDER: Array[StringName] = _load_ammo_order()

const WEAPON_CATEGORIES: Array[StringName] = [
	&"all", &"pistol", &"smg", &"shotgun", &"rifle", &"dmr", &"sniper",
]
const WEAPON_CATEGORY_NAMES := {
	&"all": "全部",
	&"pistol": "手枪",
	&"smg": "冲锋枪",
	&"shotgun": "霰弹枪",
	&"rifle": "步枪",
	&"dmr": "射手步枪",
	&"sniper": "狙击步枪",
}
const WEAPON_CATEGORY_DESC := {
	&"all": "全部 18 种武器 · 主/副武器自动置顶",
	&"pistol": "手枪 // PISTOL — 轻便机动，适合近距应急与快速拔枪",
	&"smg": "冲锋枪 // SMG — 高射速压制，主打室内近战与巷战突击",
	&"shotgun": "霰弹枪 // SHOTGUN — 近距高爆发面杀伤，擅长破门清房",
	&"rifle": "步枪 // RIFLE — 全能主力，兼顾中远距点射与自动火力压制",
	&"dmr": "射手步枪 // DMR — 中间威力弹及以上，以半自动为主（含可全自动型号），兼顾高精度与优秀射程",
	&"sniper": "狙击步枪 // SNIPER — 专用狙击弹或大威力步枪弹，以栓动为主，极致精度与超远射程",
}


static func weapon_category(id: StringName) -> StringName:
	return StringName(_weapon_record(id).get("category", "shotgun"))


static func weapon_category_name(category: StringName) -> String:
	return String(WEAPON_CATEGORY_NAMES.get(category, String(category)))


static func weapon_category_desc(category: StringName) -> String:
	return String(WEAPON_CATEGORY_DESC.get(category, ""))


static func weapons_in_category(category: StringName) -> Array[StringName]:
	if category == &"all" or category == &"":
		return WEAPON_ORDER.duplicate()
	var out: Array[StringName] = []
	for id in WEAPON_ORDER:
		if weapon_category(id) == category:
			out.append(id)
	return out


static func _load_weapon_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameData.table("weapons").get("order", []):
		out.append(StringName(id))
	if out.is_empty():
		out = [&"m870", &"m1014", &"saiga12k", &"g17"]
	return out


static func _load_ammo_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in GameData.table("ammo").get("order", []):
		out.append(StringName(id))
	if out.is_empty():
		out = [&"buckshot", &"slug", &"ap_slug"]
	return out


static func _weapon_record(id: StringName) -> Dictionary:
	var table: Dictionary = GameData.table("weapons").get("data", {})
	return table.get(String(id), table.get("m870", {}))


static func get_weapon(id: StringName) -> WeaponData:
	var w := WeaponData.new()
	w.id = id
	var rec := _weapon_record(id)
	w.slot = WEAPON_ORDER.find(id) + 1
	w.category = StringName(rec.get("category", "shotgun"))
	w.display_name = String(rec.get("display_name", String(id)))
	w.caliber = StringName(rec.get("caliber", "12gauge"))
	w.caliber_label = String(rec.get("caliber_label",
		"12 GAUGE" if w.caliber == &"12gauge" else String(w.caliber).to_upper()))
	w.ammo_id = StringName(rec.get("ammo", "9mm" if w.caliber == &"9mm" else "buckshot"))
	w.ammo_category = category_of(w.ammo_id)
	w.sfx_kind = String(rec.get("sfx", "shotgun" if w.caliber == &"12gauge" else "pistol"))
	w.shake_amount = float(rec.get("shake", 2.4 if w.caliber == &"12gauge" else 0.6))
	_apply_impact_profile(w)
	w.default_auto_fire = bool(rec.get("full_auto", false))
	w.auto_fire = w.default_auto_fire
	w.mag_capacity = int(rec.get("mag", 5))
	w.chamber_size = int(rec.get("chamber", 0))
	w.pump_time = float(rec.get("pump_time", 0.0))
	w.load_time = float(rec.get("load_time", 0.35))
	w.fire_interval = float(rec.get("fire_interval", 0.28))
	w.range_m = float(rec.get("range", 26.0))
	w.visual_length = float(rec.get("visual_length", 0.9))
	w.base_spread = float(rec.get("base_spread", 0.0))
	_apply_recoil_profile(w, rec)
	w.sound_radius = float(rec.get("sound_radius", 20.0))
	w.model_kind = id
	w.auto_cycle = bool(rec.get("auto_cycle", id != &"m870"))
	w.feed_mode = StringName(rec.get("feed", "shell"))
	return w


static func auto_cycle(id: StringName) -> bool:
	return bool(_weapon_record(id).get("auto_cycle", id != &"m870"))


## 按武器音色给出打击感档位：霰弹/狙击重而慢收，冲锋枪轻而快收。
## 数值也可在 weapons.json 里用 shake_roll / shake_decay / knockback 覆盖。
static func _apply_impact_profile(w: WeaponData) -> void:
	var roll := 0.18
	var decay := 38.0
	var knock := 40.0
	match w.sfx_kind:
		"shotgun":
			roll = 0.85
			decay = 24.0
			knock = 115.0
		"sniper":
			roll = 0.62
			decay = 16.0
			knock = 140.0
		"rifle":
			roll = 0.30
			decay = 30.0
			knock = 75.0
		"smg":
			roll = 0.10
			decay = 46.0
			knock = 28.0
		_:
			roll = 0.18
			decay = 38.0
			knock = 48.0
	var rec := _weapon_record(w.id)
	w.shake_roll = float(rec.get("shake_roll", roll))
	w.shake_decay = float(rec.get("shake_decay", decay))
	w.knockback = float(rec.get("knockback", knock))


## 连发散布累积档位：不同枪型每发增量、上限、回落速度都不同。
## 数值可在 weapons.json 里用 spread_growth / spread_max / spread_recovery 覆盖。
static func _apply_recoil_profile(w: WeaponData, rec: Dictionary) -> void:
	var growth := 0.006
	var cap := 0.06
	var recovery := 0.50
	match w.sfx_kind:
		"shotgun":
			growth = 0.016
			cap = 0.13
			recovery = 0.30
		"sniper":
			growth = 0.022
			cap = 0.10
			recovery = 0.20
		"rifle":
			growth = 0.012
			cap = 0.19
			recovery = 0.30
		"smg":
			growth = 0.0042
			cap = 0.09
			recovery = 0.42
		_:
			growth = 0.006
			cap = 0.06
			recovery = 0.50
	w.spread_growth = float(rec.get("spread_growth", growth))
	w.spread_max = float(rec.get("spread_max", cap))
	w.spread_recovery = float(rec.get("spread_recovery", recovery))
	_apply_recoil_kick(w, rec)


## 垂直/水平后坐力档位：两者独立配置，基础值决定每发偏移，上限决定连射封顶。
static func _apply_recoil_kick(w: WeaponData, rec: Dictionary) -> void:
	var v_base := 6.0
	var h_base := 4.0
	var v_max := 64.0
	var h_max := 50.0
	var spread_mul := 1.5
	var first_mul := 0.45
	match w.sfx_kind:
		"shotgun":
			v_base = 20.0
			h_base = 11.0
			v_max = 120.0
			h_max = 90.0
			spread_mul = 2.2
			first_mul = 0.55
		"sniper":
			v_base = 24.0
			h_base = 7.0
			v_max = 140.0
			h_max = 64.0
			spread_mul = 1.8
			first_mul = 0.25
		"rifle":
			v_base = 10.0
			h_base = 6.0
			v_max = 110.0
			h_max = 72.0
			spread_mul = 1.9
			first_mul = 0.35
		"smg":
			v_base = 4.5
			h_base = 3.6
			v_max = 70.0
			h_max = 56.0
			spread_mul = 1.5
			first_mul = 0.40
	w.recoil_vertical = float(rec.get("recoil_vertical", rec.get("recoil_base", v_base)))
	w.recoil_horizontal = float(rec.get("recoil_horizontal", h_base))
	w.recoil_max_vertical = float(rec.get("recoil_max_vertical", rec.get("recoil_max", v_max)))
	w.recoil_max_horizontal = float(rec.get("recoil_max_horizontal", h_max))
	w.recoil_spread_mul = float(rec.get("recoil_spread_mul", spread_mul))
	w.first_shot_spread_mul = clampf(
		float(rec.get("first_shot_spread_mul", first_mul)), 0.0, 1.0)
	w.bullet_speed_mps = clampf(float(rec.get("bullet_speed_mps", 0.0)), 0.0, 2500.0)


static func feed_mode(id: StringName) -> StringName:
	return StringName(_weapon_record(id).get("feed", "shell"))


## 兼容旧调用点：默认泵动霰弹枪
static func pump_shotgun() -> WeaponData:
	return get_weapon(&"m870")


static func base_spread_mul() -> float:
	return float(GameData.table("weapons").get("global_spread_mul", 1.0))


## 通用弹药种类表：display_name / short / reserve_max / color / note。
static func category_table() -> Dictionary:
	var raw: Dictionary = GameData.table("ammo").get("categories", {})
	if raw.is_empty():
		raw = {
			"light": {"display_name": "轻型弹", "short": "轻型", "reserve_max": 108, "color": "#dbeaff"},
			"medium": {"display_name": "中型弹", "short": "中型", "reserve_max": 120, "color": "#c8ffcf"},
			"heavy": {"display_name": "重型弹", "short": "重型", "reserve_max": 40, "color": "#ffd18a"},
			"shotgun": {"display_name": "霰弹", "short": "霰弹", "reserve_max": 60, "color": "#ff9e40"},
			"special": {"display_name": "特殊弹药", "short": "特殊", "reserve_max": 20, "color": "#c9a0ff"},
		}
	return raw.duplicate(true)


## 某一口径对应的通用弹药种类；未知/空弹种归入霰弹。
static func category_of(ammo_id: StringName) -> StringName:
	var rec: Dictionary = GameData.table("ammo").get("data", {}).get(String(ammo_id), {})
	return StringName(rec.get("category", "shotgun"))


static func ammo_table() -> Dictionary:
	var out := {}
	var table: Dictionary = GameData.table("ammo").get("data", {})
	var spread_mul := base_spread_mul()
	for id in AMMO_ORDER:
		var rec: Dictionary = table.get(String(id), {})
		if rec.is_empty():
			continue
		var a := AmmoData.new()
		a.id = id
		a.display_name = String(rec.get("display_name", String(id)))
		a.short_name = String(rec.get("short", a.display_name))
		a.category = StringName(rec.get("category", "shotgun"))
		a.pellets = int(rec.get("pellets", 1))
		a.damage = float(rec.get("damage", 0.0))
		a.spread = float(rec.get("spread", 0.0)) * spread_mul
		a.muzzle_velocity_mps = clampf(
			float(rec.get("muzzle_velocity_mps", 400.0)), 50.0, 2500.0)
		a.bullet_time_scale = clampf(
			float(rec.get("bullet_time_scale", 0.294)), 0.05, 1.0)
		a.drag_per_m = clampf(float(rec.get("drag_per_m", 0.005)), 0.0, 0.05)
		a.ads_spread_mul = clampf(float(rec.get("ads_spread_mul", 0.45)), 0.05, 1.0)
		a.attachment_spread_scale = clampf(
			float(rec.get("attachment_spread_scale", 1.0)), 0.0, 1.0)
		a.ap = float(rec.get("ap", 0.0))
		a.reserve_max = int(rec.get("reserve_max", 0))
		a.color = Color.html(String(rec.get("color", "#ffffff")))
		out[a.id] = a
	return out
