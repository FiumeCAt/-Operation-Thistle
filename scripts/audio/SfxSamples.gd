extends RefCounted
class_name SfxSamples
## 外部音频采样库与热插拔目录扫描器（Phase 6B）：
## 1) 保留既有 CC0 命中采样表（IMPACT_SAMPLE_ROOT / IMPACT_SAMPLE_SETS），100% 兼容原有契约；
## 2) 自动扫描 assets/audio/sfx/{weapons,combat,ui,impacts/weakspot,impacts/ground}/，
##    按逻辑 ID 聚类多变体并做防重复随机轮播，替换或新增同名 .wav/.ogg/.mp3 即可热插拔生效；
## 3) 加载 assets/audio/bgm/bgm_<state>.{ogg,wav} 并自动启用无缝循环模式。

const IMPACT_SAMPLE_ROOT := "res://assets/audio/sfx/impacts/"
const BGM_SAMPLE_ROOT := "res://assets/audio/bgm/"
const IMPACT_SAMPLE_SETS := {
	"concrete": [
		"concrete/concrete_hit_01.ogg",
		"concrete/concrete_hit_02.ogg",
		"concrete/concrete_hit_03.ogg",
		"concrete/concrete_shatter_01.ogg",
		"concrete/concrete_chip_01.wav",
		"concrete/concrete_chip_02.wav",
		"concrete/concrete_chip_03.wav",
		"concrete/concrete_chip_04.wav",
		"concrete/concrete_crack_01.wav",
		"concrete/concrete_crack_02.wav",
		"concrete/concrete_spall_01.wav",
		"concrete/concrete_spall_02.wav",
	],
	"metal": [
		"metal/metal_hit_01.ogg",
		"metal/metal_hit_02.ogg",
		"metal/metal_hit_03.ogg",
		"metal/metal_ping_01.wav",
		"metal/metal_clink_01.wav",
		"metal/metal_thud_01.wav",
		"metal/metal_plate_01.wav",
		"metal/metal_plate_02.wav",
		"metal/metal_plate_03.wav",
		"metal/metal_plate_04.wav",
		"metal/metal_clang_01.wav",
		"metal/metal_clang_02.wav",
		"metal/metal_clang_03.wav",
		"metal/metal_clang_04.wav",
	],
	"ricochet": [
		"ricochet/ricochet_01.ogg",
		"ricochet/ricochet_02.ogg",
		"ricochet/ricochet_03.ogg",
		"ricochet/metal_ring_long.wav",
		"ricochet/ricochet_zing_01.wav",
		"ricochet/ricochet_zing_02.wav",
		"ricochet/ricochet_zing_03.wav",
		"ricochet/ricochet_zing_04.wav",
	],
	"flesh": [
		"flesh/flesh_hit_01.mp3",
		"flesh/flesh_hit_02.mp3",
		"flesh/flesh_hit_03.mp3",
		"flesh/flesh_hit_04.mp3",
		"flesh/flesh_impact_01.wav",
		"flesh/flesh_impact_02.wav",
		"flesh/flesh_impact_03.wav",
		"flesh/flesh_impact_04.wav",
		"flesh/flesh_impact_05.wav",
		"flesh/flesh_impact_06.wav",
		"flesh/flesh_impact_07.wav",
		"flesh/flesh_impact_08.wav",
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

## 刻意跳过不适合快节奏枪弹命中的长音频文件（如 15s 撕裂长片段）。
const IMPACT_SCAN_IGNORE := ["flesh_rip_01.mp3"]

const HOTSWAP_DIRS: Array[Dictionary] = [
	{"dir": "res://assets/audio/sfx/weapons/", "kind": "weapons"},
	{"dir": "res://assets/audio/sfx/combat/", "kind": "combat"},
	{"dir": "res://assets/audio/sfx/ui/", "kind": "ui"},
	{"dir": "res://assets/audio/sfx/impacts/weakspot/", "kind": "impacts"},
	{"dir": "res://assets/audio/sfx/impacts/ground/", "kind": "impacts"},
]

const AUDIO_EXTS := ["ogg", "wav", "mp3"]

## 将新旧逻辑 ID 互作别名映射，确保既有调用点无缝吃到新采样。
const KEY_ALIASES := {
	"ui_confirm": ["ui"],
	"enemy_melee": ["stab"],
	"enemy_charge": ["charge_up"],
	"enemy_ram": ["ram"],
	"reload_shell": ["load"],
}

var _samples: Dictionary = {}
var _sfx_paths: Dictionary = {}
var _sfx_bank: Dictionary = {}
var _bgm_cache: Dictionary = {}
var _last_idx: Dictionary = {}
var _loaded := false
var _sfx_indexed := false


## 惰性加载既有与扩展命中采样；同时自动扫描对应材质目录中新增的 .wav/.ogg/.mp3 热插拔变体。
func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for key in IMPACT_SAMPLE_SETS:
		var loaded: Array = []
		var seen := {}
		for rel in IMPACT_SAMPLE_SETS[key]:
			var path: String = IMPACT_SAMPLE_ROOT + String(rel)
			if seen.has(path) or not ResourceLoader.exists(path):
				continue
			seen[path] = true
			var res = load(path)
			if res is AudioStream:
				loaded.append(res)
		var sub_dir := "%s%s/" % [IMPACT_SAMPLE_ROOT, String(key)]
		var dir := DirAccess.open(sub_dir)
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir() and not fname.begins_with("."):
					var clean := fname
					if clean.ends_with(".import"):
						clean = clean.substr(0, clean.length() - 7)
					elif clean.ends_with(".remap"):
						clean = clean.substr(0, clean.length() - 6)
					var ext := clean.get_extension().to_lower()
					if AUDIO_EXTS.has(ext) and not IMPACT_SCAN_IGNORE.has(clean):
						var full := sub_dir + clean
						if not seen.has(full) and ResourceLoader.exists(full):
							seen[full] = true
							var res2 = load(full)
							if res2 is AudioStream:
								loaded.append(res2)
				fname = dir.get_next()
			dir.list_dir_end()
		_samples[key] = loaded


## 轻量目录索引：仅记录 weapons / combat / ui / weakspot / ground 外部采样路径（<1ms），
## 真正播放到对应逻辑 ID 时再按需加载该条 WAV，避免开局一次性解码全部百余条采样导致卡顿。
func ensure_sfx_loaded() -> void:
	if _sfx_indexed:
		return
	_sfx_indexed = true
	for entry in HOTSWAP_DIRS:
		_scan_dir(String(entry["dir"]), String(entry["kind"]))


func _scan_dir(dir_path: String, folder_kind: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var seen_paths := {}
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and not fname.begins_with("."):
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.substr(0, clean.length() - 7)
			elif clean.ends_with(".remap"):
				clean = clean.substr(0, clean.length() - 6)
			var ext := clean.get_extension().to_lower()
			if AUDIO_EXTS.has(ext):
				var full := dir_path + clean
				if not seen_paths.has(full) and ResourceLoader.exists(full):
					seen_paths[full] = true
					_register_sfx_path(clean.get_basename(), folder_kind, full)
		fname = dir.get_next()
	dir.list_dir_end()


func _register_sfx_path(stem: String, folder_kind: String, full_path: String) -> void:
	var base := _strip_variant_suffix(stem)
	if folder_kind == "weapons":
		if base.ends_with("_fire"):
			var wid := base.substr(0, base.length() - 5)
			_append_path("weapon_" + wid, full_path)
			_append_path(base, full_path)
			return
		if base.ends_with("_sup"):
			var wid := base.substr(0, base.length() - 4)
			_append_path("weapon_" + wid + "_sup", full_path)
			_append_path(base, full_path)
			return
	_append_path(base, full_path)
	if KEY_ALIASES.has(base):
		for alias in KEY_ALIASES[base]:
			_append_path(String(alias), full_path)


static func _strip_variant_suffix(stem: String) -> String:
	var idx := stem.rfind("_")
	if idx > 0 and idx < stem.length() - 1:
		var tail := stem.substr(idx + 1)
		if tail.is_valid_int() and tail.length() <= 3:
			return stem.substr(0, idx)
	return stem


func _append_path(key: String, full_path: String) -> void:
	if not _sfx_paths.has(key):
		_sfx_paths[key] = []
	var arr: Array = _sfx_paths[key]
	if not arr.has(full_path):
		arr.append(full_path)


func _ensure_key_streams(key: String) -> Array:
	ensure_sfx_loaded()
	if _sfx_bank.has(key):
		return _sfx_bank[key] as Array
	var loaded: Array = []
	for path in (_sfx_paths.get(key, []) as Array):
		var res = load(String(path))
		if res is AudioStream:
			loaded.append(res)
	_sfx_bank[key] = loaded
	return loaded


func is_loaded() -> bool:
	return _loaded


func count(material: String) -> int:
	ensure_loaded()
	return (_samples.get(material, []) as Array).size()


func sfx_count(key: String) -> int:
	ensure_sfx_loaded()
	return (_sfx_paths.get(key, []) as Array).size()


func has_sfx(key: String) -> bool:
	return sfx_count(key) > 0


## 按逻辑 ID 抽取外部采样（多变体防连播同一条，按 key 惰性加载缓存）；缺失时返回 null 交给 SfxSynth 兜底。
func pick_sfx(key: String) -> AudioStream:
	var list := _ensure_key_streams(key)
	if list.is_empty():
		return null
	return _pick_non_repeating("sfx:" + key, list)


## 按材质抽取一条命中采样；未知或缺失材质自动回落到 generic；均无可用时返回 null。
func pick_for_material(material: String) -> AudioStream:
	ensure_loaded()
	var key := material
	if (_samples.get(key, []) as Array).is_empty():
		key = "generic"
	var list: Array = _samples.get(key, [])
	if list.is_empty():
		return null
	return _pick_non_repeating("imp:" + key, list)


## 金属跳弹尾音采样。
func pick_ricochet() -> AudioStream:
	ensure_loaded()
	var list: Array = _samples.get("ricochet", [])
	if list.is_empty():
		return null
	return _pick_non_repeating("imp:ricochet", list)


func _pick_non_repeating(bucket: String, list: Array) -> AudioStream:
	if list.size() == 1:
		return list[0] as AudioStream
	var recent: Array = _last_idx.get(bucket, [])
	var max_hist := mini(2, list.size() - 1) if list.size() >= 4 else 1
	var candidates: Array[int] = []
	for i in list.size():
		if not recent.has(i):
			candidates.append(i)
	var idx := candidates[randi() % candidates.size()] if not candidates.is_empty() else (randi() % list.size())
	recent.append(idx)
	while recent.size() > max_hist:
		recent.pop_front()
	_last_idx[bucket] = recent
	return list[idx] as AudioStream


## 加载状态化 BGM（优先 .ogg，其次 .wav），并确保循环播放属性已开启。
func load_bgm(state: String) -> AudioStream:
	if _bgm_cache.has(state):
		return _bgm_cache[state] as AudioStream
	for ext in ["ogg", "wav"]:
		var path := "%sbgm_%s.%s" % [BGM_SAMPLE_ROOT, state, ext]
		if not ResourceLoader.exists(path):
			continue
		var res = load(path)
		if res is AudioStreamWAV:
			var wav := (res as AudioStreamWAV).duplicate() as AudioStreamWAV
			var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
			var frames := wav.data.size() / maxi(bytes_per_frame, 1)
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = frames
			_bgm_cache[state] = wav
			return wav
		elif res is AudioStreamOggVorbis:
			var ogg := res as AudioStreamOggVorbis
			ogg.loop = true
			_bgm_cache[state] = ogg
			return ogg
		elif res is AudioStream:
			_bgm_cache[state] = res
			return res as AudioStream
	return null
