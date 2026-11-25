extends RefCounted
class_name WeaponFeedState2D
## 2D 武器供弹、备弹、换弹、切枪与收拔枪纯状态机（无节点/渲染依赖，可独立单测）。

const SWITCH_TIME := 0.36
const HOLSTER_TIME := 0.22
const DRAW_TIME := 0.26

var weapon_id: StringName = &"g17"
## 本局携带的武器（1-2 把）；数字键与滚轮只在其中循环。
var loadout: Array[StringName] = [&"m870", &"m1014", &"saiga12k", &"g17"]
var mag := 0
## category(light/medium/heavy/shotgun/special) → 备弹数量。
var reserve: Dictionary = {}
var mag_by_id: Dictionary = {}
## 每把武器独立的开火模式状态："auto"（全自动）/ "semi"（半自动）；仅半自动武器固定为 "semi"。
var fire_mode_by_id: Dictionary = {}
## 每把武器独立的当前装填弹种 ID（同口径 3 档：肉伤 / 常规 / 穿甲，切枪往返保持选择）。
var ammo_by_id: Dictionary = {}
## Q 键切弹中的目标弹种；为空表示常规换弹。
var pending_ammo_id: StringName = &""
var cooldown := 0.0
var shots := 0

var reload_t := 0.0
var reload_total := 0.0
## 2D 天赋「快速换弹」的比例；1.0 为原始换弹时间。
var reload_time_mul := 1.0
## 备弹天赋倍率；浪潮补满弹药时沿用，避免回满反而比开局少。
var reserve_talent_mul := 1.0
## 「持续装填」天赋：解锁后按住 R 可为管仓武器逐发续装。
var hold_reload_enabled := false

var switch_t := 0.0
var pending_id: StringName = &""

var holstered := false
var stow_t := 0.0
var stow_total := 0.0
var stow_kind := 0  # -1 收枪，1 拔枪


## 换装武器时恢复或初始化该枪的独立弹匣数与当前弹种。
func on_weapon_equipped(id: StringName, mag_capacity: int, data: WeaponData = null) -> void:
	weapon_id = id
	pending_ammo_id = &""
	if not mag_by_id.has(id):
		mag_by_id[id] = mag_capacity
	mag = int(mag_by_id[id])
	if data != null:
		if ammo_by_id.has(id):
			var saved := StringName(ammo_by_id[id])
			var ammo := WeaponDB.get_ammo(saved)
			if ammo != null and ammo.caliber == data.caliber:
				data.ammo_id = saved
		ammo_by_id[id] = data.ammo_id


static func ammo_reserve_cost(ammo_id: StringName) -> float:
	var ammo := WeaponDB.get_ammo(ammo_id)
	return clampf(float(ammo.reserve_cost), 0.5, 5.0) if ammo != null else 1.0


static func cost_for_rounds(rounds: int, unit_cost: float) -> int:
	if rounds <= 0:
		return 0
	return int(ceil(float(rounds) * maxf(unit_cost, 0.1)))


static func max_rounds_affordable(points: int, unit_cost: float) -> int:
	if points <= 0:
		return 0
	return int(floor(float(points) / maxf(unit_cost, 0.1)))


## 推进冷却、切枪、换弹、收拔枪计时器，并返回本帧触发的事件字典。
func tick(delta: float, data: WeaponData) -> Dictionary:
	var events := {
		"switch_swap": &"",
		"reload_finished": false,
		"ammo_switched": &"",
		"holster_completed": false,
	}
	if data == null:
		return events
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
	if switch_t > 0.0:
		var before := switch_t
		switch_t = maxf(switch_t - delta, 0.0)
		# 在动画最低点换模型，新旧枪交替正好被下沉遮住
		if before > SWITCH_TIME * 0.5 and switch_t <= SWITCH_TIME * 0.5 and pending_id != &"":
			events["switch_swap"] = pending_id
			pending_id = &""
	if reload_t > 0.0:
		reload_t = maxf(reload_t - delta, 0.0)
		if reload_t <= 0.0:
			var switched_to := pending_ammo_id
			finish_reload(data)
			events["reload_finished"] = true
			if switched_to != &"":
				events["ammo_switched"] = data.ammo_id
	if stow_t > 0.0:
		var was_stowing := stow_t
		stow_t = maxf(stow_t - delta, 0.0)
		# 收枪动作结束时才把枪挂到背后，避免手和背后同时出现两把枪
		if was_stowing > 0.0 and stow_t <= 0.0 and stow_kind < 0:
			events["holster_completed"] = true
	return events


## 尝试开火：返回 &"fired" / &"need_draw" / &"need_reload" / &"blocked"。
func try_fire(data: WeaponData) -> StringName:
	if data == null or cooldown > 0.0 or reload_t > 0.0 or switch_t > 0.0:
		return &"blocked"
	if holstered:
		return &"need_draw"
	if stow_t > 0.0:
		return &"blocked"
	if mag <= 0:
		return &"need_reload"
	mag -= 1
	mag_by_id[weapon_id] = mag
	cooldown = data.fire_interval
	shots += 1
	return &"fired"


## R 换弹：弹匣枪整匣更换，霰弹枪一次压一发；高穿弹按 reserve_cost 消耗更多通用备弹点数。
func reload(data: WeaponData) -> bool:
	if data == null or reload_t > 0.0 or switch_t > 0.0 or holstered or stow_t > 0.0:
		return false
	var unit_cost := ammo_reserve_cost(data.ammo_id)
	if mag >= data.mag_capacity or max_rounds_affordable(get_reserve(data), unit_cost) <= 0:
		return false
	pending_ammo_id = &""
	reload_total = maxf(data.load_time * reload_time_mul, 0.15)
	reload_t = reload_total
	return true


## Q 键局内切弹：在当前武器所属口径的 3 档弹药（肉伤 / 常规 / 穿甲）间循环切换。
## 切弹完成时把旧弹匣余弹按原点数退回通用备弹池，再按新弹种单发点数装填。
func start_ammo_switch(data: WeaponData, step := 1) -> Dictionary:
	if data == null or switch_t > 0.0 or holstered or stow_t > 0.0:
		return {"ok": false, "target": &"", "cancelled": false}
	if reload_t > 0.0 and pending_ammo_id == &"":
		return {"ok": false, "target": &"", "cancelled": false}
	var options := WeaponDB.ammo_for_caliber(data.caliber)
	if options.size() <= 1:
		return {"ok": false, "target": &"", "cancelled": false}
	var base_id := pending_ammo_id if pending_ammo_id != &"" else data.ammo_id
	var cur_idx := options.find(base_id)
	if cur_idx < 0:
		cur_idx = 0
	var old_cost := ammo_reserve_cost(data.ammo_id)
	var pool_after_refund := get_reserve(data) + int(round(float(mag) * old_cost))
	for offset in range(1, options.size() + 1):
		var idx := (cur_idx + step * offset + options.size() * 4) % options.size()
		var cand: StringName = options[idx]
		if cand == data.ammo_id:
			if pending_ammo_id != &"":
				pending_ammo_id = &""
				reload_t = 0.0
				reload_total = 0.0
				return {"ok": true, "target": data.ammo_id, "cancelled": true}
			return {"ok": false, "target": &"", "cancelled": false}
		var cand_cost := ammo_reserve_cost(cand)
		if max_rounds_affordable(pool_after_refund, cand_cost) >= 1:
			pending_ammo_id = cand
			var switch_dur := data.load_time * (2.2 if data.feed_mode == &"shell" else 0.85) * reload_time_mul
			reload_total = maxf(switch_dur, 0.25 if data.feed_mode == &"shell" else 0.15)
			reload_t = reload_total
			return {"ok": true, "target": cand, "cancelled": false}
	return {"ok": false, "target": &"", "cancelled": false}


## 「持续装填」：按住 R 时，上一发装完后自动续压下一发（仅限管仓武器）。
func process_hold_reload(data: WeaponData) -> bool:
	if not hold_reload_enabled or data == null or data.feed_mode != &"shell":
		return false
	if holstered or stow_t > 0.0 or switch_t > 0.0 or reload_t > 0.0:
		return false
	return reload(data)


func finish_reload(data: WeaponData) -> void:
	if data == null:
		return
	if pending_ammo_id != &"":
		var old_cost := ammo_reserve_cost(data.ammo_id)
		var refund := int(round(float(mag) * old_cost))
		set_reserve(data, get_reserve(data) + refund)
		mag = 0
		data.ammo_id = pending_ammo_id
		ammo_by_id[weapon_id] = pending_ammo_id
		pending_ammo_id = &""
		var new_cost := ammo_reserve_cost(data.ammo_id)
		var take := mini(data.mag_capacity, max_rounds_affordable(get_reserve(data), new_cost))
		var spent := cost_for_rounds(take, new_cost)
		set_reserve(data, get_reserve(data) - spent)
		mag = take
		mag_by_id[weapon_id] = mag
		return
	var unit_cost := ammo_reserve_cost(data.ammo_id)
	if data.feed_mode == &"mag":
		var affordable := max_rounds_affordable(get_reserve(data), unit_cost)
		var take := mini(data.mag_capacity - mag, affordable)
		if take > 0:
			set_reserve(data, get_reserve(data) - cost_for_rounds(take, unit_cost))
			mag += take
	elif max_rounds_affordable(get_reserve(data), unit_cost) >= 1:
		set_reserve(data, get_reserve(data) - cost_for_rounds(1, unit_cost))
		mag += 1
	mag_by_id[weapon_id] = mag


## 切枪：返回 &"rejected" / &"instant_holstered" / &"animated"。
func start_switch(id: StringName, data: WeaponData) -> StringName:
	if data == null or switch_t > 0.0 or stow_t > 0.0 or id == weapon_id:
		return &"rejected"
	if not loadout.has(id):
		return &"rejected"
	# 换弹/切弹中切枪直接取消，避免两套动画打架
	if reload_t > 0.0:
		reload_t = 0.0
		reload_total = 0.0
		pending_ammo_id = &""
	if holstered:
		return &"instant_holstered"
	pending_id = id
	switch_t = SWITCH_TIME
	return &"animated"


func cycle_target(step: int) -> StringName:
	if loadout.is_empty():
		return &""
	var index := loadout.find(weapon_id)
	if index < 0:
		return loadout[0]
	return loadout[(index + step + loadout.size()) % loadout.size()]


func get_reserve(data: WeaponData) -> int:
	if data == null:
		return 0
	var category := data.ammo_category
	if reserve.has(category):
		return int(reserve[category])
	var info: Dictionary = WeaponDB.category_table().get(String(category), {})
	return int(info.get("reserve_max", 0))


func set_reserve(data: WeaponData, value: int) -> void:
	if data == null:
		return
	reserve[data.ammo_category] = maxi(value, 0)


## 备弹天赋：所有通用弹药种类按倍率给足初始备弹。
func apply_reserve_talent(mul: float) -> void:
	reserve_talent_mul = mul
	var table := WeaponDB.category_table()
	for category in table:
		var info: Dictionary = table[category]
		reserve[category] = int(round(float(info.get("reserve_max", 0)) * mul))


## 浪潮模式波次间整备：弹匣、所有武器弹匣与通用备弹全部回满。
func refill_all_ammo(data: WeaponData) -> void:
	var table := WeaponDB.category_table()
	for category in table:
		var info: Dictionary = table[category]
		reserve[category] = int(round(float(info.get("reserve_max", 0)) * reserve_talent_mul))
	for id in mag_by_id:
		var wd: WeaponData = WeaponDB.get_weapon(StringName(id))
		if wd != null:
			mag_by_id[id] = wd.mag_capacity
	if data != null:
		mag_by_id[data.id] = data.mag_capacity
		mag = data.mag_capacity
		reload_t = 0.0
		reload_total = 0.0


func get_reload_progress() -> float:
	if reload_total <= 0.0:
		return 1.0
	return clampf(1.0 - reload_t / reload_total, 0.0, 1.0)


func get_stow_progress() -> float:
	if stow_total <= 0.0:
		return 1.0
	return clampf(1.0 - stow_t / stow_total, 0.0, 1.0)


func holster() -> bool:
	if holstered or stow_t > 0.0 or reload_t > 0.0 or switch_t > 0.0:
		return false
	holstered = true
	stow_kind = -1
	stow_total = HOLSTER_TIME
	stow_t = HOLSTER_TIME
	return true


func draw() -> bool:
	if not holstered or stow_t > 0.0:
		return false
	holstered = false
	stow_kind = 1
	stow_total = DRAW_TIME
	stow_t = DRAW_TIME
	return true


func is_stowing() -> bool:
	return stow_t > 0.0 and stow_kind < 0


func is_drawing() -> bool:
	return stow_t > 0.0 and stow_kind > 0


func is_busy() -> bool:
	return reload_t > 0.0 or switch_t > 0.0 or stow_t > 0.0


## 当前武器是否具备全自动快慢机档位（含原生全自动或全自动枪机改件）。
func supports_full_auto(data: WeaponData) -> bool:
	return data != null and (data.auto_fire or data.default_auto_fire)


## 读取当前武器的生效开火模式："auto" 或 "semi"；切枪往返时保持每把武器各自选择。
func get_fire_mode(data: WeaponData) -> String:
	if data == null or not supports_full_auto(data):
		return "semi"
	if not fire_mode_by_id.has(data.id):
		fire_mode_by_id[data.id] = "auto"
	return String(fire_mode_by_id[data.id])


func is_auto_mode(data: WeaponData) -> bool:
	return get_fire_mode(data) == "auto"


func set_fire_mode(data: WeaponData, mode: String) -> bool:
	if data == null:
		return false
	if mode == "auto":
		if not supports_full_auto(data):
			return false
		fire_mode_by_id[data.id] = "auto"
		return true
	if mode == "semi":
		fire_mode_by_id[data.id] = "semi"
		return true
	return false


func toggle_fire_mode(data: WeaponData) -> Dictionary:
	if data == null or not supports_full_auto(data):
		if data != null:
			fire_mode_by_id[data.id] = "semi"
		return {"changed": false, "supported": false, "mode": "semi"}
	var next_mode := "semi" if get_fire_mode(data) == "auto" else "auto"
	fire_mode_by_id[data.id] = next_mode
	return {"changed": true, "supported": true, "mode": next_mode}


## HUD 文本：枪名 + 弹匣/备弹，空仓或换弹时附提示。
func get_ammo_text(data: WeaponData) -> String:
	if data == null:
		return ""
	var extra := ""
	if reload_t > 0.0:
		extra = "装填中"
	elif switch_t > 0.0:
		extra = "切枪中"
	elif mag <= 0:
		extra = "空仓 · R 换弹" if get_reserve(data) > 0 else "弹药耗尽"
	var line := "%s   %d / %d" % [data.display_name, mag, get_reserve(data)]
	return line + ("   " + extra if extra != "" else "")
