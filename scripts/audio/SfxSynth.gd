extends RefCounted
class_name SfxSynth
## 运行时确定性程序化音效合成器（纯 PCM 波形生成，不依赖场景树）：
## 使用固定种子按原定顺序构建全部 38 条基础枪械（含 5 条消音版）/快慢机/命中/UI/敌人/环境 AudioStreamWAV，
## 新增条目固定追加在末尾，保证既有 32 条波形逐采样一致。

const SR := 44100
const SEED := 20261025


static func build_all() -> Dictionary:
	var synth := SfxSynth.new()
	return synth._build_bank()


var _rng := RandomNumberGenerator.new()


func _build_bank() -> Dictionary:
	_rng.seed = SEED
	var bank: Dictionary = {}
	bank["shotgun"] = _build_shotgun()
	bank["pistol"] = _build_pistol()
	bank["smg"] = _build_smg()
	bank["rifle"] = _build_rifle()
	bank["sniper"] = _build_sniper()
	bank["pump"] = _build_pump()
	bank["load"] = _build_load()
	bank["empty"] = _build_empty()
	bank["hit"] = _build_hit()
	bank["break"] = _build_break()
	bank["step"] = _build_step()
	bank["switch"] = _build_switch()
	bank["crate_open"] = _build_crate_open()
	bank["pickup"] = _build_pickup()
	bank["ui"] = _build_ui()
	bank["ui_hover"] = _build_ui_hover()
	bank["ui_click"] = _build_ui_click()
	bank["ambient"] = _build_ambient()
	bank["turret_lock"] = _build_turret_lock()
	bank["turret_shot"] = _build_turret_shot()
	bank["charge_up"] = _build_charge_up()
	bank["ram"] = _build_ram()
	bank["stab"] = _build_stab()
	bank["fuse"] = _build_fuse()
	bank["fuse_long"] = _build_fuse_long()
	bank["boom"] = _build_boom()
	bank["metal_hit"] = _build_metal_hit()
	bank["hit_low"] = _build_hit_low()
	bank["hit_mid"] = _build_hit_mid()
	bank["hit_air"] = _build_hit_air()
	bank["enemy_death"] = _build_enemy_death()
	bank["enemy_alert"] = _build_enemy_alert()
	# 追加在既有 32 条之后，保证原有音色 RNG 序列逐采样不变。
	bank["shotgun_sup"] = _build_shotgun_sup()
	bank["pistol_sup"] = _build_pistol_sup()
	bank["smg_sup"] = _build_smg_sup()
	bank["rifle_sup"] = _build_rifle_sup()
	bank["sniper_sup"] = _build_sniper_sup()
	bank["fire_select"] = _build_fire_select()
	# Phase 4：弱点命中叮响与弱点击穿破甲音效，固定追加在末尾保持既有 38 条波形一致。
	bank["weakspot_hit"] = _build_weakspot_hit()
	bank["armor_pierce"] = _build_armor_pierce()
	return bank


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


func _build_ui_hover() -> AudioStreamWAV:
	var n := int(0.045 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		a[i] = sin(TAU * 1500.0 * t) * exp(-t * 95.0) * 0.14
	return _stream(a)


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


func _build_shotgun_sup() -> AudioStreamWAV:
	var n := int(0.28 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.11
		lp2 += (lp - lp2) * 0.16
		var hiss := (wn - lp) * exp(-t * 44.0) * 0.34
		var thump := sin(TAU * lerpf(92.0, 48.0, clampf(t / 0.18, 0.0, 1.0)) * t) * exp(-t * 20.0) * 0.62
		var bolt := sin(TAU * 720.0 * t) * exp(-t * 95.0) * 0.14
		var s := lp2 * exp(-t * 16.0) * 0.58 + thump + hiss + bolt
		a[i] = s * 0.85
	return _stream(a)


func _build_pistol_sup() -> AudioStreamWAV:
	var n := int(0.14 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.18
		var puff := (wn - lp) * exp(-t * 72.0) * 0.36
		var body := lp * exp(-t * 42.0) * 0.42
		var thump := sin(TAU * 165.0 * t) * exp(-t * 48.0) * 0.30
		var mech := sin(TAU * 1350.0 * t) * exp(-t * 140.0) * 0.22
		a[i] = (puff + body + thump + mech) * 0.85
	return _stream(a)


func _build_smg_sup() -> AudioStreamWAV:
	var n := int(0.11 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.22
		var puff := (wn - lp) * exp(-t * 88.0) * 0.40
		var body := lp * exp(-t * 54.0) * 0.38
		var thump := sin(TAU * 205.0 * t) * exp(-t * 58.0) * 0.26
		var bolt := sin(TAU * 1580.0 * t) * exp(-t * 165.0) * 0.24
		a[i] = (puff + body + thump + bolt) * 0.82
	return _stream(a)


func _build_rifle_sup() -> AudioStreamWAV:
	var n := int(0.20 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	var lp_mid := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.15
		lp_mid += (wn - lp_mid) * 0.42
		var crack := (lp_mid - lp) * exp(-t * 78.0) * 0.56
		var baffle := lp * exp(-t * 28.0) * 0.50
		var thump := sin(TAU * 115.0 * t) * exp(-t * 32.0) * 0.42
		var bolt := sin(TAU * 1120.0 * t) * exp(-t * 120.0) * 0.18
		a[i] = (crack + baffle + thump + bolt) * 0.86
	return _stream(a)


func _build_sniper_sup() -> AudioStreamWAV:
	var n := int(0.32 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	var lp_mid := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.11
		lp_mid += (wn - lp_mid) * 0.34
		var crack := (lp_mid - lp) * exp(-t * 58.0) * 0.54
		var baffle := lp * exp(-t * 17.0) * 0.56
		var thump := sin(TAU * 78.0 * t) * exp(-t * 19.0) * 0.54
		var zip := sin(TAU * lerpf(1600.0, 620.0, clampf(t / 0.12, 0.0, 1.0)) * t) * exp(-t * 52.0) * 0.12
		a[i] = (crack + baffle + thump + zip) * 0.86
	return _stream(a)


func _build_fire_select() -> AudioStreamWAV:
	var n := int(0.08 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		var s := 0.0
		if t < 0.025:
			s += (sin(TAU * 1750.0 * t) * 0.28 + wn * 0.18) * exp(-t * 180.0)
		var u: float = t - 0.024
		if u >= 0.0 and u < 0.045:
			s += (sin(TAU * 2450.0 * u) * 0.34 + sin(TAU * 980.0 * u) * 0.20 + wn * 0.14) * exp(-u * 135.0)
		a[i] = s * 0.9
	return _stream(a)


func _build_weakspot_hit() -> AudioStreamWAV:
	var n := int(0.16 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		var crack := wn * exp(-t * 140.0) * 0.45
		var chime1 := sin(TAU * 1680.0 * t) * exp(-t * 28.0) * 0.36
		var chime2 := sin(TAU * 2520.0 * t) * exp(-t * 36.0) * 0.24
		var punch := sin(TAU * 240.0 * t) * exp(-t * 42.0) * 0.34
		a[i] = (crack + chime1 + chime2 + punch) * 0.92
	return _stream(a)


func _build_armor_pierce() -> AudioStreamWAV:
	var n := int(0.20 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var wn := _rng.randf_range(-1.0, 1.0)
		lp += (wn - lp) * 0.42
		var shatter := (wn - lp) * exp(-t * 68.0) * 0.52
		var sweep := sin(TAU * lerpf(2950.0, 1180.0, clampf(t / 0.14, 0.0, 1.0)) * t) * exp(-t * 24.0) * 0.34
		var body := sin(TAU * 360.0 * t) * exp(-t * 32.0) * 0.28
		a[i] = (shatter + sweep + body) * 0.9
	return _stream(a)
