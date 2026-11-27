extends RefCounted
class_name BgmCatalog
## 战术电台与多曲 BGM 曲库扫描与条件选曲服务：
## 1) 自动扫描内置目录 res://assets/audio/bgm/（根部 bgm_<state>.* 与 menu/explore/combat 子目录）
##    与玩家自定义目录 user://bgm/（支持 .ogg / .mp3 / .wav，丢入即识别曲名与播放）；
## 2) 支持可选 tracks.json 元数据（自定义中文曲名、权重 weight、条件 conditions）；
## 3) 预留条件/权重选曲扩展接口 select_track(context, play_mode, pinned_id, current_id, step)，
##    便于后续按区域、波次、Boss/撤离阶段筛选曲目。

const BUILTIN_ROOT := "res://assets/audio/bgm/"
const USER_ROOT := "user://bgm/"
const AUDIO_EXTS := ["ogg", "mp3", "wav"]
const POOLS := ["menu", "explore", "combat"]

const BUILTIN_TITLES := {
	"bgm_menu": "霓虹机库",
	"bgm_explore": "暗区低潜",
	"bgm_combat": "蓟花突击",
}

var _tracks: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _stream_cache: Dictionary = {}
var _scanned := false


func ensure_scanned() -> void:
	if not _scanned:
		refresh()


func ensure_user_dir() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_ROOT))
	return ProjectSettings.globalize_path(USER_ROOT)


func refresh() -> void:
	_scanned = true
	_tracks.clear()
	_by_id.clear()
	_stream_cache.clear()
	_scan_root(BUILTIN_ROOT, false)
	_scan_root(USER_ROOT, true)
	_sort_tracks()


## 仅供单测隔离扫描外部临时曲库目录，不影响真实 user://bgm/。
func scan_directory_for_test(root_path: String, is_custom := true) -> void:
	_scanned = true
	_tracks.clear()
	_by_id.clear()
	_stream_cache.clear()
	var norm := root_path if root_path.ends_with("/") else (root_path + "/")
	_scan_root(norm, is_custom)
	_sort_tracks()


func _sort_tracks() -> void:
	# 稳定排序：内置默认曲目在前，自定义曲目按标题字典序排列
	_tracks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := bool(a.get("custom", false))
		var cb := bool(b.get("custom", false))
		if ca != cb:
			return not ca
		return String(a.get("id", "")) < String(b.get("id", "")))


func all_tracks() -> Array[Dictionary]:
	ensure_scanned()
	var out: Array[Dictionary] = []
	for t in _tracks:
		out.append(t.duplicate(true))
	return out


func tracks_for_pool(pool: String, context: Dictionary = {}) -> Array[Dictionary]:
	ensure_scanned()
	var out: Array[Dictionary] = []
	for t in _tracks:
		var pools: Array = t.get("pools", [])
		if pool != "" and not pools.has(pool):
			continue
		if not _matches_conditions(t.get("conditions", {}), context):
			continue
		out.append(t)
	return out


func track_by_id(track_id: String) -> Dictionary:
	ensure_scanned()
	if _by_id.has(track_id):
		return (_by_id[track_id] as Dictionary).duplicate(true)
	return {}


## 条件与权重选曲主入口：
## - context 支持 {"state": "menu"|"explore"|"combat", "region": "", "wave": 0, "is_boss": false, "is_extracting": false, "tags": []}
## - play_mode 支持 "shuffle"（随机轮播，防连播同一首）、"sequential"（顺序循环）、"single"（固定单曲）
func select_track(context: Dictionary, play_mode: String, pinned_id: String,
		current_id: String, step: int = 1) -> Dictionary:
	ensure_scanned()
	var state := String(context.get("state", "menu"))
	var pool := tracks_for_pool(state, context)
	if pool.is_empty():
		pool = tracks_for_pool(state)
	if pool.is_empty():
		pool = _tracks.duplicate()
	if pool.is_empty():
		return {}

	# 固定单曲：非战斗状态严格锁定玩家固定曲目（含跨池自定义曲）；进入战斗时若固定曲不在战斗池则切战斗池。
	if play_mode == "single" and not pinned_id.is_empty():
		var pinned := track_by_id(pinned_id)
		if not pinned.is_empty():
			var p_pools: Array = pinned.get("pools", [])
			if state != "combat" or p_pools.has("combat"):
				return pinned

	if pool.size() == 1:
		return (pool[0] as Dictionary).duplicate(true)

	if play_mode == "sequential":
		var cur_idx := -1
		for i in pool.size():
			if String((pool[i] as Dictionary).get("id", "")) == current_id:
				cur_idx = i
				break
		var next_idx := 0 if cur_idx < 0 else posmod(cur_idx + step, pool.size())
		return (pool[next_idx] as Dictionary).duplicate(true)

	# 默认 shuffle：加权随机且严格避免连续两首相同
	var candidates: Array[Dictionary] = []
	var total_w := 0.0
	for t in pool:
		var tid := String((t as Dictionary).get("id", ""))
		if tid == current_id and pool.size() > 1:
			continue
		var w := maxf(float((t as Dictionary).get("weight", 1.0)), 0.05)
		candidates.append(t)
		total_w += w
	if candidates.is_empty():
		return (pool[0] as Dictionary).duplicate(true)
	var pick := randf() * total_w
	var acc := 0.0
	for t in candidates:
		acc += maxf(float((t as Dictionary).get("weight", 1.0)), 0.05)
		if pick <= acc:
			return (t as Dictionary).duplicate(true)
	return (candidates[candidates.size() - 1] as Dictionary).duplicate(true)


## 加载曲目音频流（原生支持 res:// 与 user:// 下的 .ogg / .mp3 / .wav，并修复 QOA WAV 循环点计算）。
func load_stream(track: Dictionary, loop_single := false) -> AudioStream:
	if track.is_empty():
		return null
	var tid := String(track.get("id", ""))
	var path := String(track.get("path", ""))
	var cache_key := "%s|%d" % [tid, int(loop_single)]
	if _stream_cache.has(cache_key):
		return _stream_cache[cache_key] as AudioStream
	var stream: AudioStream = null
	var is_custom := bool(track.get("custom", false))
	var ext := path.get_extension().to_lower()
	if not is_custom and ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is AudioStream:
			stream = _configure_loop(res as AudioStream, loop_single, false)
	else:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			stream = _load_external_audio(abs_path, ext, loop_single)
	if stream != null:
		_stream_cache[cache_key] = stream
	return stream


static func _load_external_audio(abs_path: String, ext: String, loop_single: bool) -> AudioStream:
	match ext:
		"ogg":
			var ogg := AudioStreamOggVorbis.load_from_file(abs_path)
			if ogg != null:
				ogg.loop = loop_single
			return ogg
		"mp3":
			var bytes := FileAccess.get_file_as_bytes(abs_path)
			if bytes.is_empty():
				return null
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			mp3.loop = loop_single
			return mp3
		"wav":
			var wav: AudioStreamWAV = AudioStreamWAV.load_from_file(abs_path)
			if wav != null:
				return _configure_loop(wav, loop_single, true)
			return null
		_:
			return null


static func _configure_loop(res: AudioStream, loop_single: bool, is_owned: bool) -> AudioStream:
	if res is AudioStreamWAV:
		var wav := (res as AudioStreamWAV) if is_owned else ((res as AudioStreamWAV).duplicate() as AudioStreamWAV)
		if loop_single:
			# 仅对未压缩 PCM 计算 loop_end；FORMAT_QOA 保持默认 loop_end 避免压缩字节数截断曲尾。
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			if wav.format == AudioStreamWAV.FORMAT_16_BITS or wav.format == AudioStreamWAV.FORMAT_8_BITS:
				var bpf := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
				wav.loop_begin = 0
				wav.loop_end = wav.data.size() / maxi(bpf, 1)
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		return wav
	if res is AudioStreamOggVorbis:
		var ogg := (res as AudioStreamOggVorbis) if is_owned else ((res as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis)
		ogg.loop = loop_single
		return ogg
	if res is AudioStreamMP3:
		var mp3 := (res as AudioStreamMP3) if is_owned else ((res as AudioStreamMP3).duplicate() as AudioStreamMP3)
		mp3.loop = loop_single
		return mp3
	return res


func _scan_root(root_path: String, is_custom: bool) -> void:
	var meta_map := _read_meta_json(root_path + "tracks.json")
	# 1) 根目录曲目
	_scan_dir(root_path, "", is_custom, meta_map)
	# 2) 按状态子目录曲目（menu / explore / combat）
	for sub in POOLS:
		_scan_dir(root_path + sub + "/", sub, is_custom, meta_map)


func _scan_dir(dir_path: String, forced_pool: String, is_custom: bool, meta_map: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and not fname.begins_with(".") and not fname.ends_with(".import"):
			var ext := fname.get_extension().to_lower()
			if AUDIO_EXTS.has(ext):
				_register_file(dir_path + fname, fname, forced_pool, is_custom, meta_map)
		fname = dir.get_next()
	dir.list_dir_end()


func _register_file(full_path: String, fname: String, forced_pool: String,
		is_custom: bool, meta_map: Dictionary) -> void:
	var base := fname.get_basename()
	var id_prefix := "custom:" if is_custom else "builtin:"
	var sub_tag := (forced_pool + "/") if not forced_pool.is_empty() else ""
	var tid := "%s%s%s" % [id_prefix, sub_tag, base]
	if _by_id.has(tid):
		return
	var pools := _infer_pools(base, forced_pool, is_custom)
	var title := _format_title(base, is_custom)
	var weight := 1.0
	var conditions: Dictionary = {}
	var ov = meta_map.get(base, meta_map.get(fname, null))
	if ov is Dictionary:
		var ov_d := ov as Dictionary
		if ov_d.has("title"):
			title = String(ov_d["title"])
		if ov_d.has("weight"):
			weight = maxf(float(ov_d["weight"]), 0.05)
		if ov_d.has("pools") and ov_d["pools"] is Array:
			pools = []
			for p in ov_d["pools"]:
				pools.append(String(p))
		elif ov_d.has("pool"):
			pools = [String(ov_d["pool"])]
		if ov_d.has("conditions") and ov_d["conditions"] is Dictionary:
			conditions = (ov_d["conditions"] as Dictionary).duplicate(true)
	var entry := {
		"id": tid,
		"base": base,
		"title": title,
		"path": full_path,
		"pools": pools,
		"custom": is_custom,
		"weight": weight,
		"conditions": conditions,
	}
	_tracks.append(entry)
	_by_id[tid] = entry


static func _infer_pools(base: String, forced_pool: String, is_custom: bool) -> Array[String]:
	if not forced_pool.is_empty():
		return [forced_pool]
	var low := base.to_lower()
	if low == "bgm_menu" or low.begins_with("menu_"):
		return ["menu"]
	if low == "bgm_explore" or low.begins_with("explore_"):
		return ["explore"]
	if low == "bgm_combat" or low.begins_with("combat_") or low.begins_with("boss_"):
		return ["combat"]
	# 自定义根目录散放音频：默认同时进入主菜单与探索（及战斗兜底），玩家丢进来立刻能听
	if is_custom:
		return ["menu", "explore", "combat"]
	return ["menu", "explore"]


static func _format_title(base: String, is_custom: bool) -> String:
	if not is_custom and BUILTIN_TITLES.has(base):
		return String(BUILTIN_TITLES[base])
	var clean := base
	for prefix in ["bgm_", "menu_", "explore_", "combat_"]:
		if clean.to_lower().begins_with(prefix) and clean.length() > prefix.length():
			clean = clean.substr(prefix.length())
			break
	clean = clean.replace("_", " ").replace("-", " ").strip_edges()
	return clean if not clean.is_empty() else base


static func _read_meta_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _matches_conditions(cond: Dictionary, context: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("region") and String(cond["region"]) != "" \
			and String(context.get("region", "")) != String(cond["region"]):
		return false
	if cond.has("min_wave") and int(context.get("wave", 0)) < int(cond["min_wave"]):
		return false
	if cond.has("max_wave") and int(context.get("wave", 0)) > int(cond["max_wave"]):
		return false
	if cond.has("is_boss") and bool(context.get("is_boss", false)) != bool(cond["is_boss"]):
		return false
	if cond.has("is_extracting") and bool(context.get("is_extracting", false)) != bool(cond["is_extracting"]):
		return false
	if cond.has("tags") and cond["tags"] is Array:
		var ctx_tags: Array = context.get("tags", [])
		for req_tag in cond["tags"]:
			if not ctx_tags.has(req_tag):
				return false
	return true
