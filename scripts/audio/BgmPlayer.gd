extends Node
class_name BgmPlayer
## 状态化双轨 Crossfade BGM 播放器（Phase 6B）：
## 支持 menu（Vaporwave）/ explore（Dark Synth Ambient）/ combat（Outrun/Darksynth）/ none 平滑淡入淡出，
## 路由至 Music 总线，静音时自动暂停零开销，取消静音后无缝恢复。

const BUS_SERVICE := preload("res://scripts/audio/AudioBusService.gd")

const VALID_STATES := ["none", "menu", "explore", "combat"]
const STATE_GAIN_DB := {
	"menu": -11.0,
	"explore": -12.5,
	"combat": -9.5,
}
const SILENT_DB := -54.0

var _samples: SfxSamples = null
var _fallback_stream: AudioStream = null
var _track_a: AudioStreamPlayer
var _track_b: AudioStreamPlayer
var _active_is_a := true
var _state := "none"
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
		add_child(_track_a)
	if _track_b == null:
		_track_b = AudioStreamPlayer.new()
		_track_b.name = "BgmTrackB"
		_track_b.bus = BUS_SERVICE.MUSIC_BUS
		_track_b.volume_db = SILENT_DB
		add_child(_track_b)


func current_state() -> String:
	return _state


func active_player() -> AudioStreamPlayer:
	return _track_a if _active_is_a else _track_b


func inactive_player() -> AudioStreamPlayer:
	return _track_b if _active_is_a else _track_a


func is_playing() -> bool:
	var a := active_player()
	return a != null and a.playing


func set_state(new_state: String, fade_sec := 1.2) -> void:
	var clean := new_state if VALID_STATES.has(new_state) else "explore"
	if _track_a == null:
		setup(_samples, _fallback_stream)
	if clean == _state:
		_sync_mute_state()
		return
	_state = clean
	_fade_dur = maxf(fade_sec, 0.05)

	if clean == "none":
		var cur := active_player()
		_fade_from_db = cur.volume_db if (cur != null and cur.playing) else SILENT_DB
		_target_db = SILENT_DB
		_fade_t = 0.0
		return

	var next_stream := _resolve_stream(clean)
	_target_db = float(STATE_GAIN_DB.get(clean, -12.0))
	var outgoing := active_player()
	var incoming := inactive_player()
	_active_is_a = not _active_is_a

	incoming.stream = next_stream
	incoming.bus = BUS_SERVICE.MUSIC_BUS
	_fade_from_db = outgoing.volume_db if (outgoing != null and outgoing.playing) else SILENT_DB
	_fade_t = 0.0

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


func stop(fade_sec := 0.8) -> void:
	set_state("none", fade_sec)


func on_volume_changed() -> void:
	_sync_mute_state()


func _resolve_stream(state: String) -> AudioStream:
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
			if cur.stream == null:
				cur.stream = _resolve_stream(_state)
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
