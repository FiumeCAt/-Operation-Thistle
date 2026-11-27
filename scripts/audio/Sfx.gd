extends Node

signal bgm_track_changed(track_info: Dictionary)
## 全局音效与状态化 BGM 协调外壳（Autoload `/root/Sfx`，Phase 6B 重构）：
## - 100% 保留既有对外 API 与字段契约（play_2d / play_hit / play_wall_impact / play_player_hurt /
##   play_weakspot_hit / play_ground_impact / play_dodge / start_ambient 等）；
## - 内部路由至 7 轨分层总线（Master[Limiter] <- Music / SFX <- Weapons / Impacts / UI / Ambience）；
## - 优先热插拔多变体外部采样（SfxSamples），缺失或关闭时自动无缝回退高品质 SfxSynth；
## - 内置并发声道上限与高频连射/霰弹叠音节流 + 重叠柔压，杜绝削波刺耳；
## - 持有 BgmPlayer 双轨 Crossfade 播放器（menu / explore / combat）。

const BUS_SERVICE := preload("res://scripts/audio/AudioBusService.gd")
const SAMPLES := preload("res://scripts/audio/SfxSamples.gd")
const SYNTH := preload("res://scripts/audio/SfxSynth.gd")
const BGM_PLAYER := preload("res://scripts/audio/BgmPlayer.gd")

const SR := SYNTH.SR
const SFX_BUS := BUS_SERVICE.SFX_BUS
const MUSIC_BUS := BUS_SERVICE.MUSIC_BUS
const WEAPONS_BUS := BUS_SERVICE.WEAPONS_BUS
const IMPACTS_BUS := BUS_SERVICE.IMPACTS_BUS
const UI_BUS := BUS_SERVICE.UI_BUS
const AMBIENCE_BUS := BUS_SERVICE.AMBIENCE_BUS
const IMPACT_SAMPLE_ROOT := SAMPLES.IMPACT_SAMPLE_ROOT
const IMPACT_SAMPLE_SETS := SAMPLES.IMPACT_SAMPLE_SETS
## 浪潮模式生成敌人提示音冷却（毫秒）：5 秒内最多保留 1 次，避免后期多目标刷屏刺耳。
const WAVE_SPAWN_CUE_COOLDOWN_MS := 5000
## 最大并发一次性音效声道数与单类连射最小间隔（毫秒），防止高频叠音爆音。
const MAX_ACTIVE_VOICES := 24
const WEAPON_FIRE_MIN_GAP_MS := 36
const UI_HOVER_MIN_GAP_MS := 45

## 一体消音武器集合（无论是否安装枪口配件始终走消音/亚音速声学特征）。
const INTEGRAL_SUPPRESSED_WEAPONS: Array[StringName] = [&"vss"]
## 按口径阶梯微调枪声响度（dB）：大口径狙击 / 霰弹 / 左轮 / 7.62 NATO 更有分量与压迫感，Master Limiter 防削波。
const WEAPON_GAIN_DB := {
	&"awm": 3.2,
	&"python": 2.4,
	&"m870": 2.2,
	&"m1014": 1.9,
	&"saiga12k": 1.8,
	&"sr25": 1.8,
	&"fal": 1.6,
	&"akm": 0.8,
	&"m1911": 0.6,
	&"ump45": 0.5,
	&"l85a2": 0.2,
	&"vss": 0.0,
	&"g17": -0.5,
	&"g18": -0.6,
	&"tmp": -0.6,
	&"fn57": -0.4,
	&"mp7": -0.4,
	&"p90": -0.4,
}

var streams: Dictionary = {}
var _ext_streams: Dictionary = {}
var _samples: SfxSamples = SAMPLES.new()
var _bgm: BgmPlayer = null
var _ambient_player: AudioStreamPlayer
var _active_voices: Array[AudioStreamPlayer] = []
## 命中三层音效 / 墙面弹着 / 玩家受击 / 枪声的独立节流时间戳（毫秒），避免霰弹与高速连射叠音爆音。
var _last_hit_ms := 0
var _last_weakspot_ms := 0
var _last_wall_ms := 0
var _last_ground_ms := 0
var _last_hurt_ms := 0
var _last_wave_cue_ms := -100000
var _last_fire_ms := 0
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	BUS_SERVICE.ensure_layout()
	# 按需懒合成：仅预登记键名（0.01ms，保持 streams.has(kind) 兼容），首次回退播放时才合成单条波形，消除冷启动 560ms 卡顿。
	for k in SYNTH.BASE_KEYS:
		streams[k] = null
	for k in SYNTH.EXT_KEYS:
		_ext_streams[k] = null
	_bgm = BGM_PLAYER.new()
	_bgm.name = "BgmPlayer"
	add_child(_bgm)
	_bgm.setup(_samples, null)
	_bgm.track_changed.connect(func(info: Dictionary) -> void: bgm_track_changed.emit(info))
	call_deferred("apply_saved_volumes")


func _ensure_synth_stream(kind: String) -> AudioStream:
	if streams.has(kind):
		var cached = streams[kind]
		if cached is AudioStream:
			return cached as AudioStream
		var built := SYNTH.build_one(kind)
		if built != null:
			streams[kind] = built
		return built
	if _ext_streams.has(kind):
		var ext_cached = _ext_streams[kind]
		if ext_cached is AudioStream:
			return ext_cached as AudioStream
		var ext_built := SYNTH.build_one(kind)
		if ext_built != null:
			_ext_streams[kind] = ext_built
		return ext_built
	return null


func get_stream(kind: String) -> AudioStream:
	var syn := _ensure_synth_stream(kind)
	if syn != null:
		return syn
	return _samples.pick_sfx(kind)


func apply_volumes(master: float, sfx: float) -> void:
	BUS_SERVICE.apply_volumes(master, sfx)
	if _bgm != null:
		_bgm.on_volume_changed()


func apply_music_volume(music: float) -> void:
	BUS_SERVICE.apply_music_volume(music)
	if _bgm != null:
		_bgm.on_volume_changed()


func apply_saved_volumes() -> void:
	var p := get_node_or_null("/root/Progress")
	BUS_SERVICE.apply_saved_volumes(p)
	if _bgm != null:
		if p != null:
			if p.has_method("bgm_play_mode"):
				_bgm.set_play_mode(String(p.bgm_play_mode()))
			if p.has_method("bgm_pinned_track"):
				_bgm.set_pinned_track(String(p.bgm_pinned_track()))
		_bgm.on_volume_changed()


## 通用 2D 音效入口：优先外部热插拔多变体采样，缺失时无缝回退 SfxSynth，并按类别路由至子总线。
func play_2d(kind: String, volume_db := 0.0, pitch := 1.0) -> void:
	if kind == "ui_hover":
		var now := Time.get_ticks_msec()
		if now - _last_hover_ms < UI_HOVER_MIN_GAP_MS:
			return
		_last_hover_ms = now
	var bus := BUS_SERVICE.bus_for_kind(kind)
	var stream := _resolve_sfx_stream(kind)
	if stream == null:
		return
	play_stream(stream, volume_db, pitch, bus)


func _resolve_sfx_stream(kind: String) -> AudioStream:
	var ext_sample := _samples.pick_sfx(kind)
	if ext_sample != null:
		return ext_sample
	return _ensure_synth_stream(kind)


## 解析 18 把武器的开火逻辑 ID（含一体消音武器 VSS 与加装消音器分流）。
static func resolve_weapon_fire_key(weapon_id: StringName, suppressed := false) -> String:
	var is_sup := suppressed or INTEGRAL_SUPPRESSED_WEAPONS.has(weapon_id)
	var wid := String(weapon_id)
	return "weapon_%s_sup" % wid if is_sup else "weapon_%s" % wid


## 18 把武器差异化开火入口：按武器 ID + 消音状态抽取专属多变体采样，缺失自动退回 5 档合成音色。
func play_weapon_fire(weapon_id: StringName, fallback_sfx_kind := "rifle",
		suppressed := false, volume_db := -5.0, now_ms := -1) -> bool:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now - _last_fire_ms < WEAPON_FIRE_MIN_GAP_MS:
		return false
	_last_fire_ms = now
	var is_sup := suppressed or INTEGRAL_SUPPRESSED_WEAPONS.has(weapon_id)
	var key := resolve_weapon_fire_key(weapon_id, is_sup)
	var stream := _samples.pick_sfx(key)
	var pitch := randf_range(0.97, 1.03)
	if stream == null:
		var fb_key := fallback_sfx_kind + "_sup" if is_sup else fallback_sfx_kind
		stream = _ensure_synth_stream(fb_key)
		if stream == null:
			stream = _ensure_synth_stream(fallback_sfx_kind)
	if stream == null:
		return false
	var caliber_trim := float(WEAPON_GAIN_DB.get(weapon_id, 0.0))
	if is_sup and not INTEGRAL_SUPPRESSED_WEAPONS.has(weapon_id):
		caliber_trim = caliber_trim * 0.45 - 2.0
	var db := volume_db + caliber_trim
	play_stream(stream, db, pitch, WEAPONS_BUS)
	return true


## 武器装填与机械操作音效：自动按武器供弹样式区分弹匣 / 管仓 / 左轮弹巢 / 泵动 / 栓动 / 切弹 / 开镜。
func play_weapon_action(action: String, weapon_data: WeaponData = null, volume_db := -8.0, pitch := 1.0) -> void:
	var key := action
	if action == "reload" and weapon_data != null:
		if weapon_data.mag_style == &"cylinder":
			key = "reload_cylinder"
		elif weapon_data.feed_mode == &"shell":
			key = "reload_shell"
		else:
			key = "reload_mag"
	elif action == "cycle" and weapon_data != null:
		if weapon_data.category == &"sniper":
			key = "bolt_cycle"
		elif weapon_data.feed_mode == &"shell" and not weapon_data.auto_cycle:
			key = "pump"
		else:
			return
	play_2d(key, volume_db, pitch * randf_range(0.96, 1.04))


func reset_wave_spawn_cue_cooldown() -> void:
	_last_wave_cue_ms = -100000


## 浪潮模式敌人生成提示音：5 秒窗口内仅保留一次提示音，防止后期数十只敌人同时刷出导致爆音吵闹。
func play_wave_spawn_cue(volume_db := -10.0, pitch := 1.0, now_ms := -1) -> bool:
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	if now - _last_wave_cue_ms < WAVE_SPAWN_CUE_COOLDOWN_MS:
		return false
	_last_wave_cue_ms = now
	play_2d("enemy_alert", volume_db, pitch)
	return true


func active_voice_count() -> int:
	_prune_voices()
	return _active_voices.size()


func _prune_voices() -> void:
	var alive: Array[AudioStreamPlayer] = []
	for p in _active_voices:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			alive.append(p)
	_active_voices = alive


func play_stream(stream: AudioStream, volume_db := 0.0, pitch := 1.0, bus: StringName = SFX_BUS) -> void:
	if stream == null:
		return
	_prune_voices()
	# 超过最大并发声道时回收最早的一个语音，防止混音堆栈过载爆音。
	while _active_voices.size() >= MAX_ACTIVE_VOICES:
		var oldest: AudioStreamPlayer = _active_voices.pop_front()
		if is_instance_valid(oldest):
			oldest.stop()
			oldest.queue_free()
	var same_bus := 0
	for v in _active_voices:
		if v.bus == bus:
			same_bus += 1
	var duck_db := 0.0
	if same_bus >= 4:
		duck_db = -clampf(float(same_bus - 3) * 0.85, 0.0, 4.0)

	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db + duck_db
	p.pitch_scale = clampf(pitch, 0.4, 2.5)
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else SFX_BUS
	add_child(p)
	_active_voices.append(p)
	p.play()
	var pid := p.get_instance_id()
	# ignore_time_scale=true：防止顿帧（Engine.time_scale=0.12）时清理定时器变慢 8 倍导致已播完声道占坑驱逐活音。
	var t := get_tree().create_timer(maxf(stream.get_length(), 0.05) + 0.20, true, false, true)
	t.timeout.connect(func() -> void:
		var inst := instance_from_id(pid)
		if inst is AudioStreamPlayer:
			_active_voices.erase(inst)
			if is_instance_valid(inst) and not inst.is_queued_for_deletion():
				inst.queue_free())


## 命中音效总入口：优先外部采样，不可用或玩家关闭时自动退回程序化三层；
## armor_state 可传 "pierce"（护甲击穿）或 "ricochet"（未击穿跳弹）叠加专属声层。
func play_hit(material: String, weight := 1.0, volume_db := -10.0, armor_state := "") -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 28:
		return
	_last_hit_ms = now
	if sampled_impacts_enabled() and _play_sample_hit(material, weight, volume_db, armor_state):
		return
	_play_hit_procedural(material, weight, volume_db, armor_state)


## 玩家被敌人子弹击中：保留既有契约（沿用程序化命中音，不混外部命中采样）。
func play_player_hurt(volume_db := -9.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hurt_ms < 60:
		return
	_last_hurt_ms = now
	_play_hit_procedural("flesh", 0.7, volume_db)


## 玩家受击细分音效：区分碎甲（armor 归零）、护甲格挡与掉血受击。
func play_player_damaged(armor_damage: int, hp_damage: int, armor_remaining: int, volume_db := -8.5) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hurt_ms < 60:
		return
	_last_hurt_ms = now
	if armor_damage > 0 and armor_remaining <= 0:
		play_2d("player_armor_break", volume_db + 1.0, randf_range(0.96, 1.04))
		if hp_damage > 0:
			play_2d("player_hurt_hp", volume_db - 1.5, randf_range(0.95, 1.05))
	elif armor_damage > 0 and hp_damage <= 0:
		play_2d("player_armor_block", volume_db, randf_range(0.94, 1.06))
	elif armor_damage > 0 and hp_damage > 0:
		play_2d("player_armor_block", volume_db - 2.0, randf_range(0.94, 1.06))
		play_2d("player_hurt_hp", volume_db - 1.0, randf_range(0.95, 1.05))
	else:
		play_2d("player_hurt_hp", volume_db, randf_range(0.95, 1.05))


## 弱点 / 破甲专属命中提示音：高频清脆叮响 + 破甲时叠加穿甲脆裂层。
func play_weakspot_hit(broke_armor := false, material := "metal", volume_db := -7.5) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_weakspot_ms < 32:
		return
	_last_weakspot_ms = now
	play_2d("weakspot_hit", volume_db, randf_range(0.96, 1.06))
	if broke_armor:
		play_2d("armor_pierce", volume_db - 1.5, randf_range(0.95, 1.05))
	# 叠加一层低权重材质基础打击感，避免“只有叮响没有着弹重量”。
	play_hit(material, 1.15, volume_db - 4.0)


## 伪 3D 子弹落地扬尘轻闷音：优先外部扬尘采样，缺失退回合成低频/气声。
func play_ground_impact(volume_db := -18.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ground_ms < 50:
		return
	_last_ground_ms = now
	var dust := _samples.pick_sfx("ground_dust")
	if dust != null:
		play_stream(dust, volume_db + 3.0, randf_range(0.88, 1.10), IMPACTS_BUS)
		return
	play_2d("hit_low", volume_db - 2.0, randf_range(0.75, 0.92))
	play_2d("hit_air", volume_db + 2.0, randf_range(0.72, 0.88))


## Phase 5 翻滚战术躲闪正式音效（蹬地冲量 + 衣物破风 + 装备轻响 + 落地摩擦）。
func play_dodge(volume_db := -8.0) -> void:
	play_2d("dodge", volume_db, randf_range(0.95, 1.07))


## 墙面弹着：混凝土采样 + 低频层；无采样时用合成中/高频兜底。
func play_wall_impact(volume_db := -14.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_wall_ms < 45:
		return
	_last_wall_ms = now
	if sampled_impacts_enabled() and _play_sample_hit("concrete", 1.0, volume_db, ""):
		return
	play_2d("hit_mid", volume_db, randf_range(0.85, 1.0))
	play_2d("hit_air", volume_db + 5.0, randf_range(1.0, 1.15))


func sampled_impacts_enabled() -> bool:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return true
	return bool(p.data.get("sample_impacts", true))


func warm_impact_samples() -> void:
	_samples.ensure_sfx_loaded()
	if sampled_impacts_enabled():
		_samples.ensure_loaded()


func impact_sample_count(material: String) -> int:
	return _samples.count(material)


func sfx_sample_count(key: String) -> int:
	return _samples.sfx_count(key)


func _play_sample_hit(material: String, weight: float, volume_db: float, armor_state := "") -> bool:
	var sample := _samples.pick_for_material(material)
	if sample == null:
		return false
	var w := clampf(weight, 0.6, 1.8)
	var db_jit := randf_range(-1.0, 0.8)
	if material == "concrete":
		# 墙面命中保持干脆利落的碎石/混凝土清脆着弹感，不叠闷重低频 hit_low，偶发极轻钢筋跳弹点缀。
		play_stream(sample, volume_db + 1.5 + db_jit, randf_range(0.90, 1.10), IMPACTS_BUS)
		if randf() < 0.14:
			var wall_ric := _samples.pick_ricochet()
			if wall_ric != null:
				play_stream(wall_ric, volume_db - 6.5, randf_range(0.96, 1.14), IMPACTS_BUS)
		return true
	play_stream(sample, volume_db + 0.5 + (w - 1.0) * 2.0 + db_jit, randf_range(0.91, 1.09), IMPACTS_BUS)
	# 仅作极轻的低频重量托底（-7.5 dB），避免像之前 +1.0 dB 盖过真实命中纹理导致发闷。
	play_stream(_ensure_synth_stream("hit_low"), volume_db - 7.5 + (w - 1.0) * 2.5, randf_range(0.92, 1.04), IMPACTS_BUS)
	if armor_state == "pierce":
		play_2d("armor_pierce", volume_db - 1.5, randf_range(0.94, 1.06))
	elif armor_state == "ricochet" or (material == "metal" and randf() < 0.30):
		var ric := _samples.pick_ricochet()
		if ric != null:
			var ric_db := volume_db - (2.0 if armor_state == "ricochet" else 6.0)
			play_stream(ric, ric_db, randf_range(0.94, 1.12), IMPACTS_BUS)
	return true


func _play_hit_procedural(material: String, weight: float, volume_db: float, armor_state := "") -> void:
	var w := clampf(weight, 0.6, 1.8)
	play_stream(_ensure_synth_stream("hit_low"), volume_db + 2.0 + (w - 1.0) * 3.0, randf_range(0.92, 1.04), IMPACTS_BUS)
	if material == "metal":
		play_stream(_ensure_synth_stream("metal_hit"), volume_db + 1.0, randf_range(0.92, 1.12), IMPACTS_BUS)
		play_stream(_ensure_synth_stream("hit_air"), volume_db + 6.0, randf_range(1.02, 1.22), IMPACTS_BUS)
	else:
		play_stream(_ensure_synth_stream("hit_mid"), volume_db + 1.0, randf_range(0.82, 0.96), IMPACTS_BUS)
		play_stream(_ensure_synth_stream("hit_air"), volume_db + 8.0, randf_range(0.9, 1.05), IMPACTS_BUS)
	if armor_state == "pierce":
		play_2d("armor_pierce", volume_db - 2.0, randf_range(0.96, 1.05))


## ---- 状态化双轨 Crossfade BGM 与战术电台控制 ----

func set_bgm_state(state: String, fade_sec := 1.2) -> void:
	if _bgm != null:
		_bgm.set_state(state, fade_sec)
		_ambient_player = _bgm.active_player()


func set_bgm_context(context: Dictionary, fade_sec := 1.2, force_reselect := false) -> void:
	if _bgm != null:
		_bgm.set_context(context, fade_sec, force_reselect)
		_ambient_player = _bgm.active_player()


func bgm_state() -> String:
	return _bgm.current_state() if _bgm != null else "none"


func bgm_play_mode() -> String:
	return _bgm.play_mode if _bgm != null else "shuffle"


func set_bgm_play_mode(mode: String) -> void:
	if _bgm != null:
		_bgm.set_play_mode(mode)


func bgm_pinned_track() -> String:
	return _bgm.pinned_track_id if _bgm != null else ""


func set_bgm_pinned_track(track_id: String) -> void:
	if _bgm != null:
		_bgm.set_pinned_track(track_id)


func bgm_current_track() -> Dictionary:
	return _bgm.get_current_track() if _bgm != null else {}


func bgm_current_title() -> String:
	return _bgm.get_current_title() if _bgm != null else ""


func bgm_tracks(pool := "") -> Array[Dictionary]:
	return _bgm.get_tracks(pool) if _bgm != null else []


func bgm_refresh_catalog() -> Array[Dictionary]:
	return _bgm.refresh_catalog() if _bgm != null else []


func bgm_next_track(fade_sec := 0.45) -> Dictionary:
	return _bgm.next_track(fade_sec) if _bgm != null else {}


func bgm_prev_track(fade_sec := 0.45) -> Dictionary:
	return _bgm.prev_track(fade_sec) if _bgm != null else {}


func bgm_play_track(track_id: String, fade_sec := 0.45) -> bool:
	return _bgm.play_track_by_id(track_id, fade_sec) if _bgm != null else false


func bgm_user_dir() -> String:
	return _bgm.catalog.ensure_user_dir() if _bgm != null else ProjectSettings.globalize_path("user://bgm/")


func stop_bgm(fade_sec := 0.8) -> void:
	if _bgm != null:
		_bgm.stop(fade_sec)


## 兼容旧入口：主菜单启动时自动平滑切入 Vaporwave 菜单 BGM。
func start_ambient() -> void:
	if _bgm != null:
		if _bgm.current_state() == "none":
			set_bgm_state("menu", 0.8)
		return
	if _ambient_player != null:
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = _ensure_synth_stream("ambient")
	_ambient_player.volume_db = -24.0
	_ambient_player.bus = MUSIC_BUS
	add_child(_ambient_player)
	_ambient_player.play()
