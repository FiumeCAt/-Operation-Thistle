extends RefCounted
class_name LootSystem2D
## 2D 战利品、掉落、容器搜刮与撤离结算核算子系统。
## 从 Main2D 抽离，集中管理：
##   1. 敌人基础/进阶/弹药掉落表与随机抽取；
##   2. 容器搜刮（医疗箱/弹药箱/补给箱/保险箱保底）与开启表现；
##   3. 地面拾取物生成、收集与通用备弹发放；
##   4. 撤离入库（含搜刮天赋）与浪潮按比例回收核算。

## 敌人基础资源掉落权重；进阶资源走 EnemyDB 的 advanced_drop。
const BASIC_DROP_TABLE := {
	&"rifleman": [[&"electronics", 45], [&"energy", 35], [&"parts", 20]],
	&"rusher": [[&"parts", 55], [&"energy", 30], [&"electronics", 15]],
	&"heavy": [[&"parts", 45], [&"electronics", 35], [&"energy", 20]],
	&"hunter": [[&"energy", 50], [&"electronics", 50]],
}
## 容器产出比单个掉落物更多，且更容易同时出第二种资源。
## 所有资源概率已含 +5% 资源爆率修正（弹药不在调整范围内）。
const CONTAINER_LOOT_MIN := 2
const CONTAINER_LOOT_MAX := 4
const CONTAINER_SECONDARY_CHANCE := 0.68
const CONTAINER_ADVANCED_CHANCE := 0.084
## 敌人也能掉多种资源，但第二种的触发率明显低于容器，不减少原有必掉物。
const ENEMY_SECONDARY_CHANCE := 0.37

var fx_layer: Node2D
var level: Level2D
var doll: Doll2D
var hud: RunHUD2D
var loot_scale_fn: Callable = Callable()
var sfx_fn: Callable = Callable()
var add_loot_fn: Callable = Callable()


func setup(p_fx_layer: Node2D, p_level: Level2D, p_doll: Doll2D, p_hud: RunHUD2D,
		p_loot_scale_fn: Callable, p_sfx_fn: Callable, p_add_loot_fn: Callable) -> void:
	fx_layer = p_fx_layer
	level = p_level
	doll = p_doll
	hud = p_hud
	loot_scale_fn = p_loot_scale_fn
	sfx_fn = p_sfx_fn
	add_loot_fn = p_add_loot_fn


func _current_loot_scale() -> float:
	if loot_scale_fn.is_valid():
		return float(loot_scale_fn.call())
	return 1.0


## 掉落数量按当前浪潮倍率放大，至少保留 1 个。
static func scale_amount(value: int, loot_scale: float = 1.0) -> int:
	return maxi(1, int(round(float(value) * loot_scale)))


## 掉落概率按当前浪潮倍率放大，并夹在 0–1。
static func scale_chance(chance: float, loot_scale: float = 1.0) -> float:
	return clampf(chance * loot_scale, 0.0, 1.0)


func loot_amount(value: int) -> int:
	return scale_amount(value, _current_loot_scale())


func loot_chance(chance: float) -> float:
	return scale_chance(chance, _current_loot_scale())


static func roll_basic_drop(kind: StringName) -> StringName:
	var table: Array = BASIC_DROP_TABLE.get(kind, BASIC_DROP_TABLE[&"rifleman"])
	var total := 0
	for entry in table:
		total += int(entry[1])
	var roll := randi() % maxi(total, 1)
	for entry in table:
		roll -= int(entry[1])
		if roll < 0:
			return StringName(entry[0])
	return StringName(table[0][0])


## 第二种基础资源：排除已经掉过的主类型，保证一次掉落里类型不同。
static func roll_basic_excluding(excluded: StringName) -> StringName:
	var pool: Array[StringName] = []
	for id in ResourceDB.BASIC:
		if id != excluded:
			pool.append(id)
	if pool.is_empty():
		return excluded
	return pool[randi() % pool.size()]


## 进阶资源按权重抽取：枪械零件（1.5 阶）出现率高于其余进阶材料。
static func roll_advanced() -> StringName:
	var total := 0
	for id in ResourceDB.ADVANCED:
		total += int(ResourceDB.ADVANCED_WEIGHTS.get(id, 0))
	if total <= 0:
		return ResourceDB.ADVANCED[randi() % ResourceDB.ADVANCED.size()]
	var roll := randi() % total
	for id in ResourceDB.ADVANCED:
		roll -= int(ResourceDB.ADVANCED_WEIGHTS.get(id, 0))
		if roll < 0:
			return id
	return ResourceDB.ADVANCED[0]


## 容器一次开箱的完整产物：主资源必出，按概率追加不同种类的基础/进阶资源。
## 浪潮模式下数量与概率都随存活波次提升。
static func roll_container_bundle(primary: StringName, amount_min: int, amount_max: int,
		secondary_chance: float, advanced_chance: float,
		loot_scale: float = 1.0) -> Array[Dictionary]:
	var min_amount := scale_amount(amount_min, loot_scale)
	var max_amount := maxi(min_amount, scale_amount(amount_max, loot_scale))
	var gains: Array[Dictionary] = [{
		"id": primary, "amount": randi_range(min_amount, max_amount),
	}]
	if randf() < scale_chance(secondary_chance, loot_scale):
		gains.append({
			"id": roll_basic_excluding(primary),
			"amount": randi_range(scale_amount(1, loot_scale), maxi(1, scale_amount(2, loot_scale))),
		})
	if randf() < scale_chance(advanced_chance, loot_scale):
		gains.append({"id": roll_advanced(), "amount": scale_amount(1, loot_scale)})
	return gains


## 撤离结算用：基础资源吃搜刮天赋加成，进阶资源按原样入库。
static func compute_banked_materials(basic_loot: Dictionary, adv_loot: Dictionary,
		scavenge_mul: float = 1.0) -> Dictionary:
	var banked := {}
	for id in basic_loot:
		var count := int(basic_loot[id])
		if count > 0:
			banked[String(id)] = maxi(1, int(round(float(count) * scavenge_mul)))
	for id in adv_loot:
		var count := int(adv_loot[id])
		if count > 0:
			banked[String(id)] = count
	return banked


## 浪潮结算：按比例回收物资，并把基础/进阶拆开供结算面板展示。
static func compute_scaled_materials(basic_loot: Dictionary, adv_loot: Dictionary,
		scavenge_mul: float, ratio: float) -> Dictionary:
	var basic := {}
	var advanced := {}
	var merged := {}
	var banked := compute_banked_materials(basic_loot, adv_loot, scavenge_mul)
	for key in banked:
		var count := int(banked[key])
		var value := count
		if ratio < 1.0:
			value = int(round(float(count) * ratio))
			if count > 0 and value < 1:
				value = 1
		merged[key] = value
		if ResourceDB.BASIC.has(StringName(key)):
			basic[key] = value
		else:
			advanced[key] = value
	return {"materials": merged, "basic": basic, "advanced": advanced}


## 敌人尸体掉落：基础资源必掉，37% 额外掉一种不同资源，远程概率掉弹药，稀有进阶小概率。
func spawn_enemy_drops(enemy: Enemy2D) -> void:
	var origin: Vector2 = enemy.global_position + Vector2(0, -18)
	var pieces := loot_amount(2 if enemy.kind == &"heavy" else 1)
	var primary := &"parts"
	for i in pieces:
		primary = roll_basic_drop(enemy.kind)
		spawn_pickup(origin + Vector2(randf_range(-16, 16), randf_range(-10, 10)),
			"resource", primary, 1)
	if randf() < loot_chance(ENEMY_SECONDARY_CHANCE):
		var secondary := roll_basic_excluding(primary)
		spawn_pickup(origin + Vector2(randf_range(-16, 16), randf_range(-10, 10)),
			"resource", secondary, 1)
	var ammo_chance := float(enemy.stats.get("ammo_drop", 0.0))
	if ammo_chance > 0.0 and randf() < loot_chance(ammo_chance):
		# 敌人掉落的弹药按通用种类合并，9mm / 5.7 / .45 都归入轻型弹。
		var ammo_key := StringName(enemy.stats.get("ammo", &"9mm"))
		var category := WeaponDB.category_of(ammo_key)
		var bounds: Array = enemy.stats.get("ammo_amount", [12, 24])
		var count := loot_amount(randi_range(int(bounds[0]), int(bounds[1])))
		spawn_pickup(origin + Vector2(randf_range(-14, 14), randf_range(-8, 8)),
			"ammo", category, count)
	var advanced_chance := float(enemy.stats.get("advanced_drop", 0.0525))
	if randf() < loot_chance(advanced_chance):
		spawn_pickup(origin + Vector2(randf_range(-12, 12), randf_range(-8, 8)),
			"resource", roll_advanced(), 1)


func spawn_pickup(pos: Vector2, kind: String, id: StringName, amount: int) -> LootPickup2D:
	if fx_layer == null:
		return null
	var pickup := LootPickup2D.new()
	pickup.setup(kind, id, amount, Callable(self, "on_pickup_collected"))
	fx_layer.add_child(pickup)
	pickup.global_position = pos
	return pickup


func on_pickup_collected(kind: String, id: StringName, amount: int) -> void:
	if kind == "ammo":
		grant_ammo(id, amount)
		var info: Dictionary = WeaponDB.category_table().get(String(id), {})
		var color := Color.html(String(info.get("color", "#ffd18a")))
		var label := String(info.get("display_name", String(id)))
		if hud != null:
			hud.push_pickup("+%d 发 %s" % [amount, label], color)
	else:
		if add_loot_fn.is_valid():
			add_loot_fn.call(id, amount)
		if hud != null:
			hud.push_pickup("+%d %s" % [amount, ResourceDB.display_name(id)],
				ResourceDB.color_of(id))
	if sfx_fn.is_valid():
		sfx_fn.call("pickup", -7.0)


## 拾取弹药：id 为通用弹药种类（light/medium/heavy/shotgun/special）。
func grant_ammo(category: StringName, amount: int) -> void:
	if doll == null or doll.weapon_rig == null or amount <= 0:
		return
	var info: Dictionary = WeaponDB.category_table().get(String(category), {})
	var base := int(info.get("reserve_max", 0))
	var current := int(doll.weapon_rig.reserve.get(category, base))
	doll.weapon_rig.reserve[category] = current + amount


func search_container(entry: Dictionary) -> void:
	if bool(entry["searched"]):
		return
	entry["searched"] = true
	var node: Node2D = entry["node"]
	if node != null:
		node.modulate = Color(0.86, 0.86, 0.86)
	# 换开启贴图：盖子/门/抽屉打开，箱体尺寸不变。
	# 衣服、物料箱等装饰物件只有关闭态贴图，保持原图并依靠变暗表示已搜刮。
	var chest: Sprite2D = entry.get("sprite")
	if chest != null and level != null and not bool(entry.get("keep_closed_art", false)):
		var art: Dictionary = level.container_art(StringName(entry.get("art", &"material_box")))
		if art.has("open"):
			chest.texture = art["open"]
	if sfx_fn.is_valid():
		sfx_fn.call("crate_open", -4.0)
	var hint: Label = entry.get("hint")
	if hint != null:
		hint.visible = false
	var scale := _current_loot_scale()
	var loot_id := StringName(entry.get("loot", &"parts"))
	match loot_id:
		&"repair":
			if doll != null:
				doll.heal(30)
				doll.repair_armor(30)
			if hud != null:
				hud.push_pickup("医疗包：生命 / 护甲 +30", PixelUI.OK)
			# 医疗箱同时带少量能量单元，偶尔再出第二种材料。
			grant_container_gains(roll_container_bundle(&"energy", 1, 2, 0.42, 0.032, scale))
		&"ammo":
			# 弹药箱按通用种类补给：轻型弹必出，再随机补一种其它通用弹药。
			var categories: Array[StringName] = [&"light", &"medium", &"heavy", &"shotgun"]
			var light_amount := loot_amount(30)
			grant_ammo(&"light", light_amount)
			var second: StringName = categories[randi() % categories.size()]
			var second_amount := loot_amount(
				30 if second == &"light" else (10 if second == &"heavy" else 12))
			grant_ammo(second, second_amount)
			var info: Dictionary = WeaponDB.category_table().get(String(second), {})
			if hud != null:
				hud.push_pickup("弹药补给 · 轻型弹 ×%d / %s ×%d" % [
					light_amount, String(info.get("display_name", "中型弹")), second_amount],
					Color.html(String(info.get("color", "#ffd18a"))))
			# 弹药箱同时带少量电子元件。
			grant_container_gains(roll_container_bundle(&"electronics", 1, 2, 0.42, 0.032, scale))
		_:
			var final_id := loot_id if ResourceDB.has(loot_id) else &"parts"
			grant_container_gains(roll_container_bundle(
				final_id, CONTAINER_LOOT_MIN, CONTAINER_LOOT_MAX,
				CONTAINER_SECONDARY_CHANCE, CONTAINER_ADVANCED_CHANCE, scale))
	# 保险箱保底：小型保险箱以外的保险箱必出 1 份进阶材料。
	if level != null and level.container_guarantees_advanced(StringName(entry.get("art", &"material_box"))):
		grant_container_gains([{"id": roll_advanced(), "amount": loot_amount(1)}])


func grant_container_gains(gains: Array[Dictionary]) -> void:
	for gain in gains:
		var id: StringName = gain["id"]
		var amount := int(gain["amount"])
		if add_loot_fn.is_valid():
			add_loot_fn.call(id, amount)
		if hud != null:
			hud.push_pickup("搜刮：%s ×%d" % [ResourceDB.display_name(id), amount],
				ResourceDB.color_of(id))
