extends RefCounted
class_name ModInstallService
## 武备库业务服务层（纯逻辑，不依赖 UI 节点）：
## 负责主/副武器定置排序、装备切换写档、配件价格/材料校验与安装、瞄具摘要与准星样式表。

const SLOT_ENGLISH := {
	"muzzle": "MUZZLE",
	"magazine": "MAGAZINE",
	"core": "BOLT",
	"stock": "STOCK",
	"grip": "GRIP",
	"sight": "SIGHT",
}

const SCOPE_RETICLE_STYLES: Array = [
	["native", "默认"],
	["cross", "十字"],
	["pso", "PSO"],
	["mildot", "密位点"],
	["vudu", "Vudu"],
]

const REFLEX_RETICLE_STYLES: Array = [
	["dot", "红点"],
	["holo", "全息"],
]


## 当前装备的主/副武器固定到列表最上方，其余保持 WeaponDB.WEAPON_ORDER 原顺序。
static func pinned_weapon_order(primary: StringName, secondary: StringName) -> Array[String]:
	var order: Array[String] = []
	if primary != &"":
		order.append(String(primary))
	if secondary != &"" and secondary != primary:
		order.append(String(secondary))
	for id in WeaponDB.WEAPON_ORDER:
		var sid := String(id)
		if not order.has(sid):
			order.append(sid)
	return order


## 从 Progress 读取主/副武器配置。
static func read_loadout(progress: Node, fallback_primary := &"m870",
		fallback_secondary := &"g17") -> Dictionary:
	var primary := fallback_primary
	var secondary := fallback_secondary
	if progress != null:
		var loadout: Array = progress.loadout_2d()
		if not loadout.is_empty():
			primary = StringName(loadout[0])
		if loadout.size() > 1:
			secondary = StringName(loadout[1])
	return {"primary": primary, "secondary": secondary}


## 把选中武器设为主或副武器（若与另一槽位冲突则自动互换），并写入 Progress。
static func equip_weapon(progress: Node, selected: StringName, primary: StringName,
		secondary: StringName, primary_slot: bool) -> Dictionary:
	if progress == null:
		return {"ok": false, "primary": primary, "secondary": secondary, "message": ""}
	var new_primary := primary
	var new_secondary := secondary
	if primary_slot:
		new_primary = selected
		if selected == secondary:
			new_secondary = primary
	else:
		new_secondary = selected
		if selected == primary:
			new_primary = secondary
	if not progress.set_loadout_2d(new_primary, new_secondary):
		return {
			"ok": false,
			"primary": primary,
			"secondary": secondary,
			"message": "装备失败：主副武器不能相同",
		}
	return {
		"ok": true,
		"primary": new_primary,
		"secondary": new_secondary,
		"message": "已装备为%s · 开始行动后生效" % ("主武器" if primary_slot else "副武器"),
	}


static func cost_line(entry: Dictionary) -> String:
	var credits := int(entry.get("credits", 0))
	return "免费" if credits <= 0 else "%d 信用点" % credits


static func material_line(entry: Dictionary) -> String:
	var cost: Dictionary = entry.get("cost", {})
	var parts: Array[String] = []
	for id in cost:
		parts.append("%s×%d" % [ResourceDB.display_name(StringName(id)), int(cost[id])])
	if parts.is_empty():
		return "无材料"
	return "、".join(PackedStringArray(parts))


## 瞄具属性摘要（单一真相源，仅列非零项并含前探加成，避免与 desc 重复）。
static func sight_stats_line(entry: Dictionary) -> String:
	var mag := float(entry.get("magnification", 1.0))
	var look_ahead := (float(entry.get("look_ahead_mul", 1.0)) - 1.0) * 100.0
	var fx: Dictionary = entry.get("effects", {})
	var vision := (float(fx.get("vision_mul", 1.0)) - 1.0) * 100.0
	var spread := (float(fx.get("spread_mul", 1.0)) - 1.0) * 100.0
	var range_pct := (float(fx.get("range_mul", 1.0)) - 1.0) * 100.0
	var ads_pct := (float(fx.get("ads_time_mul", 1.0)) - 1.0) * 100.0
	var parts: Array[String] = ["倍率 %.1f×" % mag]
	if absf(vision) >= 0.5:
		parts.append("视野 %+d%%" % int(round(vision)))
	if absf(look_ahead) >= 0.5:
		parts.append("前探 %+d%%" % int(round(look_ahead)))
	if absf(spread) >= 0.5:
		parts.append("散布 %+d%%" % int(round(spread)))
	if absf(range_pct) >= 0.5:
		parts.append("射程 %+d%%" % int(round(range_pct)))
	if absf(ads_pct) >= 0.5:
		parts.append("瞄准时间 %+d%%" % int(round(ads_pct)))
	return " · ".join(PackedStringArray(parts))


static func can_pay_mod(progress: Node, entry: Dictionary) -> bool:
	if progress == null:
		return false
	if progress.credits() < int(entry.get("credits", 0)):
		return false
	var cost: Dictionary = entry.get("cost", {})
	for id in cost:
		if progress.advanced_count(StringName(id)) < int(cost[id]):
			return false
	return true


## 安装武器配件或护甲组件；返回统一结果字典供 UI 渲染提示文案。
static func install_mod(progress: Node, item: String, slot: String,
		option_id: String) -> Dictionary:
	if progress == null:
		return {"ok": false, "message": ""}
	var ok: bool = progress.install_armor_mod(StringName(slot), StringName(option_id)) \
		if item == "armor" \
		else progress.install_weapon_mod(StringName(item), StringName(slot), StringName(option_id))
	if ok:
		return {"ok": true, "message": "已安装 · 开始行动后生效"}
	return {"ok": false, "message": "信用点或进阶资源不足"}


static func reticle_styles_for(entry: Dictionary) -> Array:
	return SCOPE_RETICLE_STYLES if bool(entry.get("scope", false)) else REFLEX_RETICLE_STYLES


static func slot_english_name(slot: String) -> String:
	return String(SLOT_ENGLISH.get(slot, ""))


static func armor_display_mode(progress: Node) -> String:
	if progress != null and progress.has_method("armor_display"):
		return String(progress.armor_display())
	return "value"
