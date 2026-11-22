extends Node
## 运行时合成的基础音效，另有一层可开关的外部命中采样（CC0，见 assets/audio/sfx/impacts）。
## 3D 音效用于枪声/脚步/命中，2D 用于 UI 与环境底噪。

const SR := 44100
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"

## 外部命中采样映射：材质 -> 文件列表（相对 IMPACT_SAMPLE_ROOT）。
## 这是"新方案"的唯一入口；想彻底退回程序化音效时，把 Progress.sample_impacts 默认值改为 false，
## 或直接清空这张表即可，play_hit / play_wall_impact 会自动落回合成层。
const IMPACT_SAMPLE_ROOT := "res://assets/audio/sfx/impacts/"
const IMPACT_SAMPLE_SETS := {
	"concrete": [
		"concrete/concrete_hit_01.ogg",
		"concrete/concrete_hit_02.ogg",
		"concrete/concrete_hit_03.ogg",
		"concrete/concrete_shatter_01.ogg",
	],
	"metal": [
		"metal/metal_hit_01.ogg",
		"metal/metal_hit_02.ogg",
		"metal/metal_hit_03.ogg",
		"metal/metal_ping_01.wav",
		"metal/metal_clink_01.wav",
		"metal/metal_thud_01.wav",
	],
	"ricochet": [
		"ricochet/ricochet_01.ogg",
		"ricochet/ricochet_02.ogg",
		"ricochet/ricochet_03.ogg",
		"ricochet/metal_ring_long.wav",
	],
	"flesh": [
		"flesh/flesh_hit_01.mp3",
		"flesh/flesh_hit_02.mp3",
		"flesh/flesh_hit_03.mp3",
		"flesh/flesh_hit_04.mp3",
	],
	"generic": [
		"generic/bullet_impact_01.wav",
		"generic/bullet_impact_02.wav",
		"generic/bullet_impact_03.wav",
		"generic/bullet_impact_heavy_01.wav",
		"generic/bullet_impact_heavy_02.wav",
		"generic/impact_rash_01.wav",
		"generic/impact_rash_02.wav",
	],
}

var streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _ambient_player: AudioStreamPlayer
## 命中三层音效的节流时间戳（毫秒），避免霰弹一枪叠出十几套。
var _last_hit_ms := 0
## 墙面弹着的独立节流，和命中分开计时。
var _last_wall_ms := 0
## 玩家受击音效的独立节流。
var _last_hurt_ms := 0
## 惰性加载的采样表：材质 -> Array[AudioStream]。
var _impact_samples: Dictionary = {}
var _impact_samples_loaded := false

func _ready() -> void:
	# 暂停菜单里的按钮/结算音也要能响。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(SFX_BUS)
	_ensure_bus(MUSIC_BUS)
	call_deferred("apply_saved_volumes")
	_rng.seed = 20261025
	streams["shotgun"] = _build_shotgun()
	streams["pistol"] = _build_pistol()
	streams["smg"] = _build_smg()
	streams["rifle"] = _build_rifle()
	streams["sniper"] = _build_sniper()
	streams["pump"] = _build_pump()
	streams["load"] = _build_load()
	streams["empty"] = _build_empty()
	streams["hit"] = _build_hit()
	streams["break"] = _build_break()
	streams["step"] = _build_step()
	streams["switch"] = _build_switch()
	streams["crate_open"] = _build_crate_open()
	streams["pickup"] = _build_pickup()
	streams["ui"] = _build_ui()
	streams["ui_hover"] = _build_ui_hover()
	streams["ui_click"] = _build_ui_click()
	streams["ambient"] = _build_ambient()
	# 四台新敌人：锁定 / 双发炮 / 冲锋 / 突刺 / 自爆引信 / 爆炸 / 金属命中 / 死亡
	streams["turret_lock"] = _build_turret_lock()
	streams["turret_shot"] = _build_turret_shot()
	streams["charge_up"] = _build_charge_up()
	streams["ram"] = _build_ram()
	streams["stab"] = _build_stab()
	streams["fuse"] = _build_fuse()
	streams["fuse_long"] = _build_fuse_long()
	streams["boom"] = _build_boom()
	streams["metal_hit"] = _build_metal_hit()
	streams["hit_low"] = _build_hit_low()
	streams["hit_mid"] = _build_hit_mid()
	streams["hit_air"] = _build_hit_air()
	streams["enemy_death"] = _build_enemy_death()
	streams["enemy_alert"] = _build_enemy_alert()

func get_stream(kind: String) -> AudioStream:
	return streams.get(kind, null)


## 设置菜单：主音量控制 Master，音效滑杆控制 SFX 总线，立即生效。
func apply_volumes(master: float, sfx: float) -> void:
	_set_bus_volume(0, master)
	_set_bus_volume(_ensure_bus(SFX_BUS), sfx)


## 背景音乐 / 环境氛围独立总线。
func apply_music_volume(music: float) -> void:
	_set_bus_volume(_ensure_bus(MUSIC_BUS), music)


func apply_saved_volumes() -> void:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	apply_volumes(float(p.data.get("volume", 0.8)), float(p.data.get("sfx_volume", 0.8)))
	apply_music_volume(float(p.data.get("music_volume", 0.8)))


func _ensure_bus(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	return index


func _set_bus_volume(index: int, value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, v <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.001)))

func play_3d(parent: Node, kind: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(kind) or parent == null:
		return
	if not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[kind]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = 45.0
	p.unit_size = 4.0
	p.bus = SFX_BUS
	parent.add_child(p)
	p.global_position = pos
	p.play()
	var t := parent.get_tree().create_timer(streams[kind].get_length() + 0.25)
	t.timeout.connect(p.queue_free)

func play_2d(kind: String, volume_db := 0.0, pitch := 1.0) -> void:
	play_stream(streams.get(kind), volume_db, pitch)


## 任意 AudioStream 的一次性 2D 播放，供外部采样复用。
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
## material = "metal" / "flesh" / "concrete" / 其他（generic）。
func play_hit(material: String, weight := 1.0, volume_db := -10.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 28:
		return
	_last_hit_ms = now
	if sampled_impacts_enabled() and _play_sample_hit(material, weight, volume_db):
		return
	_play_hit_procedural(material, weight, volume_db)


## 玩家被敌人子弹击中：先继续用原有的合成命中音，不混外部采样。
func play_player_hurt(volume_db := -9.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hurt_ms < 60:
		return
	_last_hurt_ms = now
	_play_hit_procedural("flesh", 0.7, volume_db)


## 墙面弹着：混凝土采样 + 低频层；没有采样时用合成中/高频兜底。
func play_wall_impact(volume_db := -14.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_wall_ms < 45:
		return
	_last_wall_ms = now
	if sampled_impacts_enabled() and _play_sample_hit("concrete", 1.0, volume_db):
		return
	play_2d("hit_mid", volume_db, randf_range(0.85, 1.0))
	play_2d("hit_air", volume_db + 5.0, randf_range(1.0, 1.15))


## 设置开关：默认开启；关闭后 play_hit / play_wall_impact 全部回到合成层。
func sampled_impacts_enabled() -> bool:
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return true
	return bool(p.data.get("sample_impacts", true))


## 外部采样命中：采样本体 + 合成低频垫底；金属偶尔叠一记跳弹尾音。
## 返回 false 表示没有可用采样，让调用方退回程序化。
func _play_sample_hit(material: String, weight: float, volume_db: float) -> bool:
	_load_impact_samples()
	var key := material
	if (_impact_samples.get(key, []) as Array).is_empty():
		key = "generic"
	var list: Array = _impact_samples.get(key, [])
	if list.is_empty():
		return false
	var w := clampf(weight, 0.6, 1.8)
	play_stream(list.pick_random(), volume_db + (w - 1.0) * 2.0, randf_range(0.94, 1.06))
	# 采样负责材质细节，低频合成层负责"重量"，避免录音听起来发飘。
	play_2d("hit_low", volume_db + 1.0 + (w - 1.0) * 3.0, randf_range(0.92, 1.03))
	if material == "metal" and randf() < 0.35:
		var ric: Array = _impact_samples.get("ricochet", [])
		if not ric.is_empty():
			play_stream(ric.pick_random(), volume_db - 6.0, randf_range(0.95, 1.08))
	return true


## 惰性加载采样；文件缺失（未导入/被删）时该项为空，逻辑自动退回合成。
func _load_impact_samples() -> void:
	if _impact_samples_loaded:
		return
	_impact_samples_loaded = true
	for key in IMPACT_SAMPLE_SETS:
		var loaded: Array = []
		for rel in IMPACT_SAMPLE_SETS[key]:
			var path: String = IMPACT_SAMPLE_ROOT + String(rel)
			if not ResourceLoader.exists(path):
				continue
			var res = load(path)
			if res is AudioStream:
				loaded.append(res)
		_impact_samples[key] = loaded


## 开局预热：把外部命中采样一次性载入，避免第一次命中时才同步读盘造成卡顿。
func warm_impact_samples() -> void:
	if sampled_impacts_enabled():
		_load_impact_samples()


## 测试/调试用：返回某材质已加载的采样条数。
func impact_sample_count(material: String) -> int:
	_load_impact_samples()
	return (_impact_samples.get(material, []) as Array).size()


## 旧的程序化三层命中：低频重击（重量）+ 中频碎裂（材质）+ 高频破空（速度感）。
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

func _stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var v := int(round(clampf(samples[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	return s

func _build_shotgun() -> AudioStreamWAV:
	var n := int(0.42 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.24
		var s := (
			lp * 0.55
			+ wn * exp(-t * 55.0) * 0.85
			+ sin(TAU * 62.0 * t) * exp(-t * 10.0) * 0.8
			+ sin(TAU * 180.0 * t) * exp(-t * 20.0) * 0.25
		)
		a[i] = s * 0.95
	return _stream(a)

## 手枪：更短、更脆的高频枪声，与霰弹枪的低频轰响区分。
func _build_pistol() -> AudioStreamWAV:
	var n := int(0.22 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.35
		var s := (
			lp * 0.45
			+ wn * exp(-t * 90.0) * 0.8
			+ sin(TAU * 210.0 * t) * exp(-t * 28.0) * 0.45
			+ sin(TAU * 520.0 * t) * exp(-t * 60.0) * 0.2
		)
		a[i] = s * 0.9
	return _stream(a)

## 冲锋枪：短促、偏脆，比手枪更密。
func _build_smg() -> AudioStreamWAV:
	var n := int(0.18 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.4
		var s := (
			lp * 0.5
			+ wn * exp(-t * 110.0) * 0.85
			+ sin(TAU * 250.0 * t) * exp(-t * 34.0) * 0.4
			+ sin(TAU * 640.0 * t) * exp(-t * 75.0) * 0.18
		)
		a[i] = s * 0.88
	return _stream(a)


## 步枪：更厚的中频爆响与尾音。
func _build_rifle() -> AudioStreamWAV:
	var n := int(0.30 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.3
		var s := (
			lp * 0.65
			+ wn * exp(-t * 70.0) * 0.85
			+ sin(TAU * 120.0 * t) * exp(-t * 16.0) * 0.55
			+ sin(TAU * 340.0 * t) * exp(-t * 45.0) * 0.3
		)
		a[i] = s * 0.95
	return _stream(a)


## 狙击枪：低频轰响 + 高频裂音 + 较长尾音。
func _build_sniper() -> AudioStreamWAV:
	var n := int(0.55 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.2
		var s := (
			lp * 0.75
			+ wn * exp(-t * 55.0) * 0.9
			+ sin(TAU * 70.0 * t) * exp(-t * 9.0) * 0.85
			+ sin(TAU * 280.0 * t) * exp(-t * 30.0) * 0.35
			+ sin(TAU * 900.0 * t) * exp(-t * 90.0) * 0.18
		)
		a[i] = s * 0.95
	return _stream(a)


func _build_pump() -> AudioStreamWAV:
	var n := int(0.36 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for c in [0.015, 0.17]:
			var u: float = t - c
			if u >= 0.0 and u < 0.09:
				var wn := _rng.randf_range(-1.0, 1.0)
				s += wn * exp(-u * 50.0) * 0.5 + sin(TAU * 700.0 * u) * exp(-u * 28.0) * 0.35
		s += sin(TAU * 90.0 * t) * exp(-t * 30.0) * 0.25
		a[i] = s * 0.9
	return _stream(a)

func _build_load() -> AudioStreamWAV:
	var n := int(0.14 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		if t < 0.06:
			s += (_rng.randf_range(-1.0, 1.0) * 0.4 + sin(TAU * 850.0 * t) * 0.2) * exp(-t * 60.0)
		s += sin(TAU * 160.0 * t) * exp(-t * 22.0) * 0.3
		a[i] = s
	return _stream(a)

func _build_empty() -> AudioStreamWAV:
	var n := int(0.06 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		if t < 0.045:
			s = (sin(TAU * 1300.0 * t) * 0.45 + _rng.randf_range(-1.0, 1.0) * 0.2) * exp(-t * 70.0)
		a[i] = s
	return _stream(a)

func _build_hit() -> AudioStreamWAV:
	var n := int(0.07 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := sin(TAU * 1500.0 * t) * exp(-t * 55.0) * 0.35
		s += sin(TAU * 700.0 * t) * exp(-t * 40.0) * 0.15
		a[i] = s
	return _stream(a)

func _build_break() -> AudioStreamWAV:
	var n := int(0.40 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.18
		var s := (lp * 0.55 + sin(TAU * 75.0 * t) * 0.6 + sin(TAU * 150.0 * t) * 0.2) * exp(-t * 8.0)
		a[i] = s
	return _stream(a)

func _build_step() -> AudioStreamWAV:
	var n := int(0.13 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.12
		var s := (lp * 0.5 + sin(TAU * 95.0 * t) * 0.35) * exp(-t * 35.0)
		a[i] = s
	return _stream(a)

func _build_switch() -> AudioStreamWAV:
	var n := int(0.12 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for c in [0.0, 0.05]:
			var u: float = t - c
			if u >= 0.0 and u < 0.04:
				s += sin(TAU * 950.0 * u) * exp(-u * 70.0) * 0.3
		a[i] = s
	return _stream(a)

## 容器开启：锁扣弹开的两下金属声 + 铰链转动的吱呀 + 盖板落定的闷响。
func _build_crate_open() -> AudioStreamWAV:
	var n := int(0.6 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.09
		var latch := sin(TAU * 1180.0 * t) * exp(-t * 65.0) * 0.42
		var u2: float = t - 0.07
		if u2 >= 0.0:
			latch += sin(TAU * 820.0 * u2) * exp(-u2 * 48.0) * 0.30
		var creak := 0.0
		if t > 0.1 and t < 0.46:
			var u := (t - 0.1) / 0.36
			phase += TAU * (150.0 + sin(u * 11.0) * 45.0) / SR
			var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
			creak = (saw * 0.45 + lp * 1.1) * sin(u * PI) * 0.26
		var thud := 0.0
		var u3: float = t - 0.46
		if u3 >= 0.0:
			thud = sin(TAU * 105.0 * u3) * exp(-u3 * 20.0) * 0.40
		a[i] = (latch + creak + thud) * 0.9
	return _stream(a)


## 拾取：两声上行短音，短到不会和枪声抢注意力。
func _build_pickup() -> AudioStreamWAV:
	var n := int(0.12 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := sin(TAU * 760.0 * t) * exp(-t * 42.0) * 0.20
		var u: float = t - 0.045
		if u >= 0.0:
			s += sin(TAU * 1140.0 * u) * exp(-u * 38.0) * 0.18
		a[i] = s
	return _stream(a)

func _build_ui() -> AudioStreamWAV:
	var n := int(0.09 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := sin(TAU * 880.0 * t) * exp(-t * 30.0) * 0.25
		s += sin(TAU * 1320.0 * t) * exp(-t * 40.0) * 0.08
		a[i] = s
	return _stream(a)


## 悬停：极短的高频轻点，避免菜单划动时吵闹。
func _build_ui_hover() -> AudioStreamWAV:
	var n := int(0.045 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		a[i] = sin(TAU * 1500.0 * t) * exp(-t * 95.0) * 0.14
	return _stream(a)


## 点击：短促双音确认，第一下触底、第二下抬起。
func _build_ui_click() -> AudioStreamWAV:
	var n := int(0.13 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := sin(TAU * 620.0 * t) * exp(-t * 46.0) * 0.22
		s += _rng.randf_range(-1.0, 1.0) * exp(-t * 180.0) * 0.10
		var u: float = t - 0.045
		if u >= 0.0:
			s += sin(TAU * 980.0 * u) * exp(-u * 55.0) * 0.14
		a[i] = s
	return _stream(a)

func _build_ambient() -> AudioStreamWAV:
	var n := 2 * SR
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var amp := 0.12 + 0.04 * sin(TAU * 0.5 * t)
		var s := (sin(TAU * 55.0 * t) + 0.45 * sin(TAU * 110.0 * t) + 0.2 * sin(TAU * 165.0 * t)) * amp
		a[i] = s
	return _stream(a, true)


## 哨戒炮激光锁定：0.75s 上行扫频，末尾一个短促锁定提示音。
func _build_turret_lock() -> AudioStreamWAV:
	var n := int(0.78 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var u := clampf(t / 0.75, 0.0, 1.0)
		var freq := lerpf(420.0, 1500.0, u * u)
		phase += TAU * freq / SR
		var env := minf(t * 20.0, 1.0) * (0.65 + 0.35 * sin(TAU * 9.0 * t))
		var s := sin(phase) * 0.16 * env
		var u2: float = t - 0.68
		if u2 >= 0.0 and u2 < 0.06:
			s += sin(TAU * 1800.0 * u2) * exp(-u2 * 55.0) * 0.22
		a[i] = s
	return _stream(a)


## 哨戒炮单发：低频炮座 + 金属机件，两发连射时自然叠成双响。
func _build_turret_shot() -> AudioStreamWAV:
	var n := int(0.26 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.30
		var s := (
			sin(TAU * 95.0 * t) * exp(-t * 24.0) * 0.70
			+ lp * exp(-t * 32.0) * 0.55
			+ sin(TAU * 1250.0 * t) * exp(-t * 50.0) * 0.16
		)
		a[i] = s * 0.9
	return _stream(a)


## 哨兵冲锋蓄力：电机转速上行的锯齿波 + 轮组摩擦。
func _build_charge_up() -> AudioStreamWAV:
	var n := int(0.58 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var u := clampf(t / 0.58, 0.0, 1.0)
		var freq := lerpf(65.0, 190.0, u)
		phase = fmod(phase + freq / SR, 1.0)
		var saw := phase * 2.0 - 1.0
		var wn := _rng.randf_range(-1.0, 1.0)
		var s := (saw * 0.32 + wn * 0.16) * pow(u, 1.3)
		a[i] = s * 0.85
	return _stream(a)


## 冲撞命中：沉重低频撞击 + 金属爆响。
func _build_ram() -> AudioStreamWAV:
	var n := int(0.34 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.20
		var s := (
			sin(TAU * 52.0 * t) * exp(-t * 12.0) * 0.85
			+ lp * exp(-t * 26.0) * 0.55
			+ sin(TAU * 880.0 * t) * exp(-t * 34.0) * 0.18
		)
		a[i] = s * 0.95
	return _stream(a)


## 巡猎者突刺：高频短促破风 + 腿尖金属点击。
func _build_stab() -> AudioStreamWAV:
	var n := int(0.20 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		var s := wn * exp(-t * 38.0) * 0.22
		var u: float = t - 0.03
		if u >= 0.0 and u < 0.05:
			s += sin(TAU * 2200.0 * u) * exp(-u * 65.0) * 0.26
		a[i] = s
	return _stream(a)


## 哥利亚引信：四声加速蜂鸣，坐地后越来越急。
func _build_fuse() -> AudioStreamWAV:
	var n := int(0.72 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for k in 4:
			var start := k * 0.16
			var u: float = t - start
			if u >= 0.0 and u < 0.07:
				s += sin(TAU * (820.0 + k * 170.0) * u) * exp(-u * 38.0) * 0.22
		a[i] = s
	return _stream(a)


## 2 秒自爆倒计时：每 1/3 秒一声，音高逐渐升高。
func _build_fuse_long() -> AudioStreamWAV:
	var n := int(2.0 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for k in 6:
			var start := k * (2.0 / 6.0)
			var u: float = t - start
			if u >= 0.0 and u < 0.10:
				s += sin(TAU * (680.0 + k * 130.0) * u) * exp(-u * 26.0) * 0.20
		a[i] = s
	return _stream(a)


## 自爆：低频冲击 + 长尾噪声，和枪声明显区分。
func _build_boom() -> AudioStreamWAV:
	var n := int(1.0 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.12
		var s := (
			sin(TAU * 42.0 * t) * exp(-t * 5.0) * 0.95
			+ lp * exp(-t * 6.5) * 0.85
			+ wn * exp(-t * 20.0) * 0.25
		)
		a[i] = clampf(s, -1.0, 1.0) * 0.95
	return _stream(a)


## 金属命中：短促高频，打装甲时和血肉命中有区别。
func _build_metal_hit() -> AudioStreamWAV:
	var n := int(0.10 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		var s := (
			sin(TAU * 1900.0 * t) * exp(-t * 70.0) * 0.22
			+ sin(TAU * 2900.0 * t) * exp(-t * 90.0) * 0.12
			+ wn * exp(-t * 120.0) * 0.10
		)
		a[i] = s
	return _stream(a)


## 命中低频层：60 Hz 上下的短促“咚”，负责重量与冲击力。
func _build_hit_low() -> AudioStreamWAV:
	var n := int(0.16 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.08
		var s := (
			sin(TAU * 62.0 * t) * exp(-t * 26.0) * 0.85
			+ sin(TAU * 39.0 * t) * exp(-t * 17.0) * 0.45
			+ lp * exp(-t * 30.0) * 0.35
		)
		a[i] = s * 0.95
	return _stream(a)


## 命中中频层：血肉的闷响，一段被快速衰减的带通噪声。
func _build_hit_mid() -> AudioStreamWAV:
	var n := int(0.14 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	var lp_slow := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.45
		lp_slow += (lp - lp_slow) * 0.12
		var s := (
			(lp - lp_slow) * exp(-t * 34.0) * 0.75
			+ sin(TAU * 380.0 * t) * exp(-t * 30.0) * 0.22
		)
		a[i] = s * 0.9
	return _stream(a)


## 命中高频层：被压缩的破空声，3 kHz 扫到 6 kHz，音量很轻但能提速度感。
func _build_hit_air() -> AudioStreamWAV:
	var n := int(0.18 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.05
		var hp := wn - lp
		var u := clampf(t / 0.18, 0.0, 1.0)
		var freq := lerpf(3000.0, 6200.0, u)
		phase += TAU * freq / SR
		var s := hp * exp(-t * 26.0) * 0.5 + sin(phase) * exp(-t * 34.0) * 0.15
		a[i] = s * 0.85
	return _stream(a)


## 敌方死亡：伺服失速下行 + 落地金属声。
func _build_enemy_death() -> AudioStreamWAV:
	var n := int(0.55 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var u := clampf(t / 0.55, 0.0, 1.0)
		var freq := lerpf(320.0, 60.0, u)
		phase += TAU * freq / SR
		var s := sin(phase) * (1.0 - u) * 0.22
		var u2: float = t - 0.18
		if u2 >= 0.0 and u2 < 0.12:
			s += sin(TAU * 640.0 * u2) * exp(-u2 * 30.0) * 0.18
		a[i] = s
	return _stream(a)


## 发现玩家：两声短促上行警报。
func _build_enemy_alert() -> AudioStreamWAV:
	var n := int(0.22 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		if t < 0.08:
			s += sin(TAU * 660.0 * t) * exp(-t * 28.0) * 0.16
		var u: float = t - 0.09
		if u >= 0.0 and u < 0.08:
			s += sin(TAU * 990.0 * u) * exp(-u * 28.0) * 0.16
		a[i] = s
	return _stream(a)
