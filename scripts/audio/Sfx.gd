extends Node
## 全局音效协调外壳（Autoload `/root/Sfx`）：
## 对外保留全部既有 API 与字段契约（play_2d / play_hit / play_wall_impact / play_player_hurt / start_ambient），
## 内部委托给 AudioBusService（总线音量）、SfxSynth（程序化合成）与 SfxSamples（外部 CC0 命中采样）。

const BUS_SERVICE := preload("res://scripts/audio/AudioBusService.gd")
const SAMPLES := preload("res://scripts/audio/SfxSamples.gd")
const SYNTH := preload("res://scripts/audio/SfxSynth.gd")

const SR := SYNTH.SR
const SFX_BUS := BUS_SERVICE.SFX_BUS
const MUSIC_BUS := BUS_SERVICE.MUSIC_BUS
const IMPACT_SAMPLE_ROOT := SAMPLES.IMPACT_SAMPLE_ROOT
const IMPACT_SAMPLE_SETS := SAMPLES.IMPACT_SAMPLE_SETS
## 浪潮模式生成敌人提示音冷却（毫秒）：5 秒内最多保留 1 次，避免后期多目标刷屏刺耳。
const WAVE_SPAWN_CUE_COOLDOWN_MS := 5000

var streams: Dictionary = {}
var _samples: SfxSamples = SAMPLES.new()
var _ambient_player: AudioStreamPlayer
## 命中三层音效 / 墙面弹着 / 玩家受击的独立节流时间戳（毫秒），避免霰弹叠音爆音。
var _last_hit_ms := 0
var _last_weakspot_ms := 0
var _last_wall_ms := 0
var _last_ground_ms := 0
var _last_hurt_ms := 0
var _last_wave_cue_ms := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	BUS_SERVICE.ensure_bus(SFX_BUS)
	BUS_SERVICE.ensure_bus(MUSIC_BUS)
	call_deferred("apply_saved_volumes")
	streams = SYNTH.build_all()


func get_stream(kind: String) -> AudioStream:
	return streams.get(kind, null)


func apply_volumes(master: float, sfx: float) -> void:
	BUS_SERVICE.apply_volumes(master, sfx)


func apply_music_volume(music: float) -> void:
	BUS_SERVICE.apply_music_volume(music)


func apply_saved_volumes() -> void:
	BUS_SERVICE.apply_saved_volumes(get_node_or_null("/root/Progress"))


func play_2d(kind: String, volume_db := 0.0, pitch := 1.0) -> void:
	play_stream(streams.get(kind), volume_db, pitch)


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


func play_stream(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = SFX_BUS
	add_child(p)
	p.play()
	var t := get_tree().create_timer(stream.get_length() + 0.25)
	t.timeout.connect(p.queue_free)


## 命中音效总入口：优先外部采样，不可用或玩家关闭时自动退回程序化三层。
func play_hit(material: String, weight := 1.0, volume_db := -10.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 28:
		return
	_last_hit_ms = now
	if sampled_impacts_enabled() and _play_sample_hit(material, weight, volume_db):
		return
	_play_hit_procedural(material, weight, volume_db)


## 玩家被敌人子弹击中：沿用程序化命中音，不混外部采样。
func play_player_hurt(volume_db := -9.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hurt_ms < 60:
		return
	_last_hurt_ms = now
	_play_hit_procedural("flesh", 0.7, volume_db)


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


## 伪 3D 子弹落地扬尘轻闷音：避免与硬墙撞击混淆。
func play_ground_impact(volume_db := -18.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ground_ms < 50:
		return
	_last_ground_ms = now
	play_2d("hit_low", volume_db - 2.0, randf_range(0.75, 0.92))
	play_2d("hit_air", volume_db + 2.0, randf_range(0.72, 0.88))


## 墙面弹着：混凝土采样 + 低频层；无采样时用合成中/高频兜底。
func play_wall_impact(volume_db := -14.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_wall_ms < 45:
		return
	_last_wall_ms = now
	if sampled_impacts_enabled() and _play_sample_hit("concrete", 1.0, volume_db):
		return
	play_2d("hit_mid", volume_db, randf_range(0.85, 1.0))
	play_2d("hit_air", volume_db + 5.0, randf_range(1.0, 1.15))


func sampled_impacts_enabled() -> bool:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return true
	return bool(p.data.get("sample_impacts", true))


func warm_impact_samples() -> void:
	if sampled_impacts_enabled():
		_samples.ensure_loaded()


func impact_sample_count(material: String) -> int:
	return _samples.count(material)


func _play_sample_hit(material: String, weight: float, volume_db: float) -> bool:
	var sample := _samples.pick_for_material(material)
	if sample == null:
		return false
	var w := clampf(weight, 0.6, 1.8)
	play_stream(sample, volume_db + (w - 1.0) * 2.0, randf_range(0.94, 1.06))
	play_2d("hit_low", volume_db + 1.0 + (w - 1.0) * 3.0, randf_range(0.92, 1.03))
	if material == "metal" and randf() < 0.35:
		var ric := _samples.pick_ricochet()
		if ric != null:
			play_stream(ric, volume_db - 6.0, randf_range(0.95, 1.08))
	return true


func _play_hit_procedural(material: String, weight: float, volume_db: float) -> void:
	var w := clampf(weight, 0.6, 1.8)
	play_2d("hit_low", volume_db + 2.0 + (w - 1.0) * 3.0, randf_range(0.92, 1.04))
	if material == "metal":
		play_2d("metal_hit", volume_db + 1.0, randf_range(0.92, 1.12))
		play_2d("hit_air", volume_db + 6.0, randf_range(1.02, 1.22))
	else:
		play_2d("hit_mid", volume_db + 1.0, randf_range(0.82, 0.96))
		play_2d("hit_air", volume_db + 8.0, randf_range(0.9, 1.05))


func start_ambient() -> void:
	if _ambient_player != null:
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = streams["ambient"]
	_ambient_player.volume_db = -24.0
	_ambient_player.bus = MUSIC_BUS
	add_child(_ambient_player)
	_ambient_player.play()
