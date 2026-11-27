extends Node
class_name BgmPlayer
## 状态化多曲 Crossfade BGM 与战术电台播放器：
## 1) 支持 menu / explore / combat / none 双轨平滑 Crossfade；
## 2) 支持三种播放模式：shuffle（随机防连播）/ sequential（顺序播放）/ single（固定单曲）；
## 3) 自动扫描 res://assets/audio/bgm/ 与 user://bgm/（.ogg/.mp3/.wav）并广播 track_changed(track_info)；
## 4) 预留 set_context(context) 条件/权重选曲扩展接口（区域、波次、Boss/撤离阶段）。

signal track_changed(track_info: Dictionary)

const BUS_SERVICE := preload("res://scripts/audio/AudioBusService.gd")
const CATALOG_SCRIPT := preload("res://scripts/audio/BgmCatalog.gd")

const VALID_STATES := ["none", "menu", "explore", "combat"]
const VALID_MODES := ["shuffle", "sequential", "single"]
const STATE_GAIN_DB := {
	"menu": -11.0,
	"explore": -12.5,
	"combat": -9.5,
}
const SILENT_DB := -54.0

var catalog: BgmCatalog = CATALOG_SCRIPT.new()
var play_mode := "shuffle"
var pinned_track_id := ""

var _samples: SfxSamples = null
var _fallback_stream: AudioStream = null
var _track_a: AudioStreamPlayer
var _track_b: AudioStreamPlayer
var _active_is_a := true
var _state := "none"
var _context: Dictionary = {"state": "none"}
var _current_track: Dictionary = {}
var _fade_t := 1.0
var _fade_dur := 1.2
var _fade_from_db := SILENT_DB
var _target_db := -12.0
var _paused_for_mute := false


func setup(samples_ref: SfxSamples, fallback_ambient: AudioStream = null) -> void:
	_samples = samples_ref
	_fallback_stream = fallback_ambient
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _track_a == null:
		_track_a = AudioStreamPlayer.new()
		_track_a.name = "BgmTrackA"
		_track_a.bus = BUS_SERVICE.MUSIC_BUS
		_track_a.volume_db = SILENT_DB
		_track_a.finished.connect(_on_player_finished.bind(true))
		add_child(_track_a)
	if _track_b == null:
		_track_b = AudioStreamPlayer.new()
		_track_b.name = "BgmTrackB"
		_track_b.bus = BUS_SERVICE.MUSIC_BUS
		_track_b.volume_db = SILENT_DB
		_track_b.finished.connect(_on_player_finished.bind(false))
		add_child(_track_b)
	catalog.ensure_scanned()


func current_state() -> String:
	return _state


func get_current_track() -> Dictionary:
	return _current_track.duplicate(true)


func get_current_title() -> String:
	return String(_current_track.get("title", ""))


func get_tracks(pool := "") -> Array[Dictionary]:
	return catalog.all_tracks() if pool.is_empty() else catalog.tracks_for_pool(pool, _context)


func refresh_catalog() -> Array[Dictionary]:
	catalog.refresh()
	return catalog.all_tracks()


func active_player() -> AudioStreamPlayer:
	return _track_a if _active_is_a else _track_b


func inactive_player() -> AudioStreamPlayer:
	return _track_b if _active_is_a else _track_a


func is_playing() -> bool:
	var a := active_player()
	return a != null and a.playing


func set_play_mode(mode: String) -> void:
	var clean := mode if VALID_MODES.has(mode) else "shuffle"
	play_mode = clean
	if clean == "single" and pinned_track_id.is_empty() and not _current_track.is_empty():
		pinned_track_id = String(_current_track.get("id", ""))


func set_pinned_track(track_id: String) -> void:
	pinned_track_id = track_id.strip_edges()


func set_state(new_state: String, fade_sec := 1.2) -> void:
	var ctx := _context.duplicate(true)
	ctx["state"] = new_state
	set_context(ctx, fade_sec)


## 扩展上下文切换接口：支持传入 state / region / wave / is_boss / is_extracting / tags。
func set_context(context: Dictionary, fade_sec := 1.2, force_reselect := false) -> void:
	var raw_state := String(context.get("state", _state))
	var clean := raw_state if VALID_STATES.has(raw_state) else "explore"
	if _track_a == null:
		setup(_samples, _fallback_stream)
	var prev_state := _state
	_context = context.duplicate(true)
	_context["state"] = clean
	if clean == prev_state and not force_reselect:
		_sync_mute_state()
		return
	_state = clean
	_fade_dur = maxf(fade_sec, 0.05)

	if clean == "none":
		var cur := active_player()
		_fade_from_db = cur.volume_db if (cur != null and cur.playing) else SILENT_DB
		_target_db = SILENT_DB
		_fade_t = 0.0
		_current_track = {}
		return

	var cur_id := String(_current_track.get("id", ""))
	var next_track := catalog.select_track(_context, play_mode, pinned_track_id, cur_id, 1)
	_crossfade_to_track(next_track, fade_sec)


func play_track_by_id(track_id: String, fade_sec := 0.45) -> bool:
	if _track_a == null:
		setup(_samples, _fallback_stream)
	var track := catalog.track_by_id(track_id)
	if track.is_empty():
		return false
	if _state == "none":
		_state = "menu"
		_context["state"] = "menu"
	if play_mode == "single":
		pinned_track_id = track_id
	_crossfade_to_track(track, fade_sec)
	return true


func next_track(fade_sec := 0.45) -> Dictionary:
	return _step_track(1, fade_sec)


func prev_track(fade_sec := 0.45) -> Dictionary:
	return _step_track(-1, fade_sec)


func _step_track(step: int, fade_sec: float) -> Dictionary:
	if _track_a == null:
		setup(_samples, _fallback_stream)
	if _state == "none":
		_state = "menu"
		_context["state"] = "menu"
	var cur_id := String(_current_track.get("id", ""))
	# 手动切歌时：即使在单曲模式或当前池只有 1 首，也允许在全曲库中切歌方便试听
	var mode_for_step := "sequential" if play_mode == "single" else play_mode
	var next_t := catalog.select_track(_context, mode_for_step, "", cur_id, step)
	var pool := catalog.tracks_for_pool(_state, _context)
	if pool.size() <= 1:
		var all_list := catalog.all_tracks()
		if all_list.size() > 1:
			var idx := -1
			for i in all_list.size():
				if String(all_list[i].get("id", "")) == cur_id:
					idx = i
					break
			var next_idx := 0 if idx < 0 else posmod(idx + step, all_list.size())
			next_t = all_list[next_idx]
	if not next_t.is_empty():
		if play_mode == "single":
			pinned_track_id = String(next_t.get("id", ""))
		_crossfade_to_track(next_t, fade_sec)
	return _current_track.duplicate(true)


func _crossfade_to_track(track: Dictionary, fade_sec: float) -> void:
	_fade_dur = maxf(fade_sec, 0.05)
	_target_db = float(STATE_GAIN_DB.get(_state, -12.0))
	var pool_size := catalog.tracks_for_pool(_state, _context).size()
	var loop_single := (play_mode == "single") or (pool_size <= 1)
	var next_stream: AudioStream = catalog.load_stream(track, loop_single) if not track.is_empty() else null
	if next_stream == null:
		next_stream = _resolve_legacy_fallback(_state)
	_current_track = track.duplicate(true) if not track.is_empty() else {
		"id": "fallback:" + _state,
		"title": "环境底噪 · Ambient",
		"pools": [_state],
		"custom": false,
	}

	var outgoing := active_player()
	var incoming := inactive_player()
	_active_is_a = not _active_is_a

	incoming.stream = next_stream
	incoming.bus = BUS_SERVICE.MUSIC_BUS
	_fade_from_db = outgoing.volume_db if (outgoing != null and outgoing.playing) else SILENT_DB
	_fade_t = 0.0

	track_changed.emit(_current_track.duplicate(true))

	if BUS_SERVICE.is_music_muted():
		_paused_for_mute = true
		if outgoing != null:
			outgoing.stop()
		incoming.stop()
		incoming.volume_db = _target_db
		_fade_t = 1.0
		return

	_paused_for_mute = false
	incoming.volume_db = SILENT_DB
	if next_stream != null:
		incoming.play()


func _on_player_finished(is_a: bool) -> void:
	if is_a != _active_is_a or _state == "none" or _paused_for_mute:
		return
	var cur := active_player()
	if cur == null:
		return
	var cur_id := String(_current_track.get("id", ""))
	var pool := catalog.tracks_for_pool(_state, _context)
	if play_mode == "single" or pool.size() <= 1:
		if cur.stream != null:
			cur.volume_db = _target_db
			cur.play()
		return
	var next_t := catalog.select_track(_context, play_mode, pinned_track_id, cur_id, 1)
	if not next_t.is_empty():
		_crossfade_to_track(next_t, 0.8)


func stop(fade_sec := 0.8) -> void:
	set_state("none", fade_sec)


func on_volume_changed() -> void:
	_sync_mute_state()


func _resolve_legacy_fallback(state: String) -> AudioStream:
	if _samples != null:
		var s := _samples.load_bgm(state)
		if s != null:
			return s
	return _fallback_stream


func _sync_mute_state() -> void:
	if _track_a == null or _track_b == null:
		return
	var muted := BUS_SERVICE.is_music_muted()
	if muted:
		if not _paused_for_mute:
			_paused_for_mute = true
			if _track_a.playing:
				_track_a.stop()
			if _track_b.playing:
				_track_b.stop()
		return
	if _paused_for_mute:
		_paused_for_mute = false
		if _state != "none":
			var cur := active_player()
			if cur.stream == null and not _current_track.is_empty():
				cur.stream = catalog.load_stream(_current_track, play_mode == "single")
			if cur.stream == null:
				cur.stream = _resolve_legacy_fallback(_state)
			cur.volume_db = _target_db
			if cur.stream != null and not cur.playing:
				cur.play()
			_fade_t = 1.0


func _process(delta: float) -> void:
	if _track_a == null or _track_b == null:
		return
	_sync_mute_state()
	if _paused_for_mute or _fade_t >= 1.0:
		return
	_fade_t = minf(1.0, _fade_t + delta / maxf(_fade_dur, 0.05))
	var k := _fade_t * _fade_t * (3.0 - 2.0 * _fade_t)
	var cur := active_player()
	var prev := inactive_player()
	if _state == "none":
		if cur != null and cur.playing:
			cur.volume_db = lerpf(_fade_from_db, SILENT_DB, k)
			if _fade_t >= 1.0:
				cur.stop()
		if prev != null and prev.playing:
			prev.stop()
		return
	if cur != null and cur.playing:
		cur.volume_db = lerpf(SILENT_DB, _target_db, k)
	if prev != null and prev.playing:
		prev.volume_db = lerpf(_fade_from_db, SILENT_DB, k)
		if _fade_t >= 1.0:
			prev.stop()
