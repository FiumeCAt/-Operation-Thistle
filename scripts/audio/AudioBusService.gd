extends RefCounted
class_name AudioBusService
## 分层音频混音总线服务（Phase 6B，无状态纯工具）：
## 层级结构：Master（挂 AudioEffectLimiter 防削波爆音）
##   ├─ Music（独立背景音乐总线）
##   └─ SFX（音效总控）
##       ├─ Weapons（枪声 / 消音 / 装填 / 机械动作）
##       ├─ Impacts（命中 / 弱点 / 破甲 / 跳弹 / 爆炸 / 受击）
##       ├─ UI（按钮 / 拾取 / 升级 / 改枪 / 波次与撤离提示）
##       └─ Ambience（翻滚 / 脚步 / 环境底噪）

const MASTER_BUS := &"Master"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const WEAPONS_BUS := &"Weapons"
const IMPACTS_BUS := &"Impacts"
const UI_BUS := &"UI"
const AMBIENCE_BUS := &"Ambience"

const SFX_SUB_BUSES: Array[StringName] = [
	WEAPONS_BUS,
	IMPACTS_BUS,
	UI_BUS,
	AMBIENCE_BUS,
]


static func ensure_bus(bus_name: StringName, send_to: StringName = MASTER_BUS) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
	if bus_name != MASTER_BUS:
		var target := send_to
		if target != MASTER_BUS and AudioServer.get_bus_index(target) < 0:
			ensure_bus(target, MASTER_BUS)
		if AudioServer.get_bus_send(index) != target:
			AudioServer.set_bus_send(index, target)
	return index


## 确保完整 7 轨总线树与 Master 压限器就绪（兼容编辑器与无头命令行模式）。
static func ensure_layout() -> void:
	ensure_master_limiter()
	ensure_bus(MUSIC_BUS, MASTER_BUS)
	ensure_bus(SFX_BUS, MASTER_BUS)
	for sub in SFX_SUB_BUSES:
		ensure_bus(sub, SFX_BUS)


static func ensure_master_limiter() -> void:
	if has_master_limiter():
		return
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -0.5
	lim.threshold_db = -1.5
	lim.soft_clip_db = 2.0
	lim.soft_clip_ratio = 10.0
	AudioServer.add_bus_effect(0, lim)


static func has_master_limiter() -> bool:
	var count := AudioServer.get_bus_effect_count(0)
	for i in count:
		if AudioServer.get_bus_effect(0, i) is AudioEffectLimiter:
			return true
	return false


## 按音效逻辑 ID 自动路由至对应子总线，便于分层混音与独立限幅。
static func bus_for_kind(kind: String) -> StringName:
	if kind == "ambient" or kind.begins_with("bgm_"):
		return MUSIC_BUS
	if kind.begins_with("weapon_") or kind in [
		"shotgun", "pistol", "smg", "rifle", "sniper",
		"shotgun_sup", "pistol_sup", "smg_sup", "rifle_sup", "sniper_sup",
		"pump", "load", "reload_mag", "reload_shell", "reload_cylinder",
		"bolt_cycle", "empty", "switch", "fire_select", "ammo_switch",
		"ads_in", "ads_out", "turret_shot",
	]:
		return WEAPONS_BUS
	if kind.begins_with("hit") or kind.begins_with("player_") or kind in [
		"metal_hit", "weakspot_hit", "armor_pierce", "ground_dust", "ricochet",
		"break", "boom", "ram", "stab", "enemy_melee", "enemy_charge",
		"enemy_ram", "charge_up", "turret_lock", "fuse", "fuse_long",
		"enemy_death",
	]:
		return IMPACTS_BUS
	if kind.begins_with("ui") or kind.begins_with("pickup") or kind in [
		"crate_open", "mod_install", "upgrade", "enemy_alert",
		"wave_start", "wave_clear", "extract_success", "mission_fail",
	]:
		return UI_BUS
	if kind in ["dodge", "step"]:
		return AMBIENCE_BUS
	return SFX_BUS


static func set_bus_volume(index: int, value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, v <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.001)))


static func is_music_muted() -> bool:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx < 0:
		return false
	return AudioServer.is_bus_mute(idx) or AudioServer.is_bus_mute(0)


static func apply_volumes(master: float, sfx: float) -> void:
	ensure_layout()
	set_bus_volume(0, master)
	set_bus_volume(ensure_bus(SFX_BUS, MASTER_BUS), sfx)


static func apply_music_volume(music: float) -> void:
	ensure_layout()
	set_bus_volume(ensure_bus(MUSIC_BUS, MASTER_BUS), music)


static func apply_saved_volumes(progress: Node) -> void:
	ensure_layout()
	if progress == null:
		return
	apply_volumes(
		float(progress.data.get("volume", 0.8)),
		float(progress.data.get("sfx_volume", 0.8)))
	apply_music_volume(float(progress.data.get("music_volume", 0.8)))
