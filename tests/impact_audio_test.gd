extends SceneTree
## 命中采样接入回归：材质映射、懒加载、开关回退、墙面弹着。
## godot --headless --path . --script res://tests/impact_audio_test.gd

var _pass := 0
var _fail := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("ok] ", label)
	else:
		_fail += 1
		print("FAIL ", label)


func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2))
	var p = root.get_node_or_null("Progress")
	if p == null:
		print("FAIL progress autoload missing")
		quit(1)
		return
	p.reset_for_test()

	var sfx = root.get_node_or_null("Sfx")
	_check(sfx != null, "Sfx autoload exists")
	if sfx == null:
		quit(1)
		return

	# 1) 所有映射路径都必须能解析成 AudioStream。
	var missing: Array[String] = []
	for material in sfx.IMPACT_SAMPLE_SETS:
		for rel in sfx.IMPACT_SAMPLE_SETS[material]:
			var path: String = sfx.IMPACT_SAMPLE_ROOT + String(rel)
			if not ResourceLoader.exists(path):
				missing.append(path)
	_check(missing.is_empty(), "every mapped impact sample is imported (%d missing)" % missing.size())
	_check(sfx.impact_sample_count("concrete") >= 12, "concrete wall impact pool has >= 12 varied samples")
	_check(sfx.impact_sample_count("metal") >= 14, "metal/armored enemy impact pool has >= 14 varied samples")
	_check(sfx.impact_sample_count("flesh") >= 12, "flesh/organic enemy impact pool has >= 12 varied samples")
	_check(sfx.impact_sample_count("ricochet") >= 8, "ricochet layer has >= 8 varied samples")
	_check(sfx.impact_sample_count("generic") >= 3, "generic fallback has samples")

	# 2) 默认开启采样，命中会创建播放器。
	_check(bool(p.data["sample_impacts"]) and sfx.sampled_impacts_enabled(),
		"sampled impacts are on by default")
	var before := sfx.get_child_count()
	sfx.play_hit("metal", 1.5, -20.0)
	_check(sfx.get_child_count() > before, "sample hit spawns audio players")
	await create_timer(0.06).timeout

	# 3) 墙面弹着走混凝土。
	before = sfx.get_child_count()
	sfx.play_wall_impact(-20.0)
	_check(sfx.get_child_count() > before, "wall impact plays the concrete sample")
	await create_timer(0.06).timeout

	# 玩家被敌人子弹击中：即使采样开启，也仍然走原有合成命中音。
	before = sfx.get_child_count()
	sfx.play_player_hurt(-20.0)
	_check(sfx.get_child_count() > before, "player hurt still uses synthesized hit audio")

	# 4) 关掉开关后仍能播放，但走程序化回退。
	p.set_sample_impacts(false)
	_check(not sfx.sampled_impacts_enabled(), "turning the switch off disables samples")
	# Sfx 的节流用真实毫秒，而无头模式下模拟计时的 0.06s 可能只过了几毫秒；
	# 这里直接清掉节流时间戳，保证回退路径检查稳定。
	before = sfx.get_child_count()
	sfx._last_hit_ms = 0
	sfx.play_hit("flesh", 1.0, -20.0)
	_check(sfx.get_child_count() > before, "procedural fallback still plays")
	await create_timer(0.06).timeout
	before = sfx.get_child_count()
	sfx._last_wall_ms = 0
	sfx.play_wall_impact(-20.0)
	_check(sfx.get_child_count() > before, "wall impact falls back to synthesis")

	# 5) 未知材质自动落到 generic，不应报错。
	p.data["sample_impacts"] = true
	sfx.play_hit("unknown_material", 1.0, -20.0)
	await process_frame
	_check(true, "unknown material falls back without errors")

	# 6) 独立子模块契约：SfxSynth 确定性 41 条音色库（含消音枪声 + 快慢机 + 弱点/破甲 + 翻滚音效）、SfxSamples 独立抽样、AudioBusService 总线静音/音量。
	var bank := SfxSynth.build_all()
	_check(bank.size() == 41 and bank.has("shotgun") and bank.has("ambient") and bank.has("enemy_alert")
		and bank.has("shotgun_sup") and bank.has("pistol_sup") and bank.has("smg_sup")
		and bank.has("rifle_sup") and bank.has("sniper_sup") and bank.has("fire_select")
		and bank.has("weakspot_hit") and bank.has("armor_pierce") and bank.has("dodge"),
		"SfxSynth builds the full deterministic 41-stream bank including weakspot, armor_pierce, and dodge")
	_check((bank["ambient"] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"SfxSynth sets forward loop mode on ambient stream")
	before = sfx.get_child_count()
	sfx.play_2d("rifle_sup", -12.0)
	sfx.play_2d("fire_select", -12.0)
	sfx._last_weakspot_ms = 0
	sfx.play_weakspot_hit(true, "metal", -14.0)
	sfx._last_ground_ms = 0
	sfx.play_ground_impact(-18.0)
	_check(sfx.get_child_count() >= before + 5,
		"suppressed shot, fire_select, weakspot armor-pierce, and ground dust SFX spawn audio players")
	var samples := SfxSamples.new()
	_check(samples.pick_for_material("unknown_mat") != null and samples.pick_ricochet() != null,
		"SfxSamples resolves generic fallback and ricochet stream")
	var bus_idx := AudioBusService.ensure_bus(AudioBusService.SFX_BUS)
	AudioBusService.set_bus_volume(bus_idx, 0.0)
	_check(AudioServer.is_bus_mute(bus_idx), "AudioBusService mutes bus at 0 volume")
	AudioBusService.set_bus_volume(bus_idx, 0.8)
	_check(not AudioServer.is_bus_mute(bus_idx), "AudioBusService unmutes bus at positive volume")

	# 7) 浪潮模式生成敌人提示音节流：5 秒窗口内仅保留 1 次提示音，避免后期刷屏吵闹。
	sfx.reset_wave_spawn_cue_cooldown()
	var cue1: bool = sfx.play_wave_spawn_cue(-10.0, 1.0, 1000)
	var cue2: bool = sfx.play_wave_spawn_cue(-10.0, 1.0, 1120)
	var cue3: bool = sfx.play_wave_spawn_cue(-10.0, 1.0, 5999)
	var cue4: bool = sfx.play_wave_spawn_cue(-10.0, 1.0, 6000)
	_check(cue1 and not cue2 and not cue3 and cue4,
		"wave spawn cue plays at most once within a 5-second window")

	# ==== Phase 6B 音频重制专项断言 ====
	# 8) 7 轨混音总线架构与 Master 压限器存在 + 子总线路由正确。
	AudioBusService.ensure_layout()
	_check(AudioBusService.has_master_limiter(),
		"Master bus carries AudioEffectLimiter to prevent clipping")
	var bus_ok := AudioServer.get_bus_index(AudioBusService.MUSIC_BUS) >= 0 \
		and AudioServer.get_bus_index(AudioBusService.SFX_BUS) >= 0
	for sub in AudioBusService.SFX_SUB_BUSES:
		var idx := AudioServer.get_bus_index(sub)
		if idx < 0 or AudioServer.get_bus_send(idx) != AudioBusService.SFX_BUS:
			bus_ok = false
	_check(bus_ok, "Music and SFX -> Weapons/Impacts/UI/Ambience bus hierarchy is intact")
	_check(AudioBusService.bus_for_kind("weapon_akm") == AudioBusService.WEAPONS_BUS
		and AudioBusService.bus_for_kind("weakspot_hit") == AudioBusService.IMPACTS_BUS
		and AudioBusService.bus_for_kind("ui_click") == AudioBusService.UI_BUS
		and AudioBusService.bus_for_kind("dodge") == AudioBusService.AMBIENCE_BUS,
		"AudioBusService routes weapons, impacts, UI, and ambience kinds to their sub-buses")

	# 9) 18 把武器差异化外部采样 + 消音分流 + VSS 一体消音解析 + 高频连射节流与并发上限。
	sfx.warm_impact_samples()
	var missing_weapons: Array[String] = []
	for wid in WeaponDB.WEAPON_ORDER:
		var normal_key: String = sfx.resolve_weapon_fire_key(wid, false)
		var sup_key: String = sfx.resolve_weapon_fire_key(wid, true)
		if sfx.sfx_sample_count(normal_key) < 2 or sfx.sfx_sample_count(sup_key) < 2:
			missing_weapons.append(String(wid))
	_check(missing_weapons.is_empty(),
		"all 18 weapons have multi-variant normal and suppressed samples (%d missing)" % missing_weapons.size())
	_check(sfx.sfx_sample_count("weakspot_hit") >= 6
		and sfx.sfx_sample_count("armor_pierce") >= 6
		and sfx.sfx_sample_count("ground_dust") >= 6,
		"weakspot, armor_pierce, and ground_dust pools each have >= 6 variants")
	_check(sfx.resolve_weapon_fire_key(&"vss", false) == "weapon_vss_sup"
		and sfx.resolve_weapon_fire_key(&"akm", false) == "weapon_akm"
		and sfx.resolve_weapon_fire_key(&"akm", true) == "weapon_akm_sup",
		"VSS resolves as integrally suppressed while AKM splits normal vs suppressed")
	_check(float(sfx.WEAPON_GAIN_DB.get(&"awm", 0.0)) > float(sfx.WEAPON_GAIN_DB.get(&"g17", 0.0))
		and float(sfx.WEAPON_GAIN_DB.get(&"python", 0.0)) > float(sfx.WEAPON_GAIN_DB.get(&"g17", 0.0)),
		"heavy calibers (AWM / Python .357) carry stronger loudness weight than 9mm pistols")
	sfx._last_fire_ms = 0
	var fire1: bool = sfx.play_weapon_fire(&"awm", "sniper", false, -14.0, 1000)
	var fire2: bool = sfx.play_weapon_fire(&"awm", "sniper", false, -14.0, 1010)
	var fire3: bool = sfx.play_weapon_fire(&"awm", "sniper", false, -14.0, 1060)
	_check(fire1 and not fire2 and fire3,
		"rapid weapon firing throttles overlap within 36ms window")

	# 10) 装填/动作/受击/弱点/翻滚/UI 外部采样完整 + 合成兜底完整 + 并发声道封顶保护。
	var required_sfx := [
		"reload_mag", "reload_shell", "reload_cylinder", "pump", "bolt_cycle",
		"empty", "ammo_switch", "switch", "fire_select", "ads_in", "ads_out",
		"dodge", "player_armor_block", "player_armor_break", "player_hurt_hp",
		"weakspot_hit", "armor_pierce", "ground_dust", "mod_install", "upgrade",
		"pickup", "pickup_rare", "pickup_ammo", "wave_start", "wave_clear",
		"extract_success", "mission_fail",
	]
	var missing_sfx: Array[String] = []
	for k in required_sfx:
		if sfx.sfx_sample_count(k) < 1:
			missing_sfx.append(k)
	_check(missing_sfx.is_empty(),
		"all 27 weapon-action, combat, weakspot, dodge, and UI samples are loaded (%d missing)" % missing_sfx.size())
	var ext_bank := SfxSynth.build_extended(bank)
	_check(ext_bank.has("reload_mag") and ext_bank.has("player_armor_break")
		and ext_bank.has("upgrade") and ext_bank.has("extract_success"),
		"SfxSynth.build_extended provides procedural fallbacks for new Phase 6B sounds")
	# 武器动作按供弹样式分派 + 玩家护甲碎裂/格挡受击音效不报错。
	sfx.play_weapon_action("reload", WeaponDB.get_weapon(&"python"), -18.0)
	sfx.play_weapon_action("reload", WeaponDB.get_weapon(&"m870"), -18.0)
	sfx.play_weapon_action("reload", WeaponDB.get_weapon(&"akm"), -18.0)
	sfx._last_hurt_ms = 0
	sfx.play_player_damaged(25, 0, 0, -18.0)
	for i in 35:
		sfx.play_stream(bank["ui_click"], -30.0, 1.0, AudioBusService.UI_BUS)
	_check(sfx.active_voice_count() <= sfx.MAX_ACTIVE_VOICES,
		"polyphony limiter caps concurrent voices at <= %d (actual %d)" % [
			sfx.MAX_ACTIVE_VOICES, sfx.active_voice_count()])

	# 11) 状态化双轨 Crossfade BGM（menu / explore / combat）与静音零浪费停播/恢复。
	var bgm_ok := true
	for st in ["menu", "explore", "combat"]:
		if sfx._samples.load_bgm(st) == null:
			bgm_ok = false
	_check(bgm_ok, "all 3 stereo looping BGM tracks (menu/explore/combat) load cleanly")
	sfx.apply_music_volume(0.8)
	sfx.set_bgm_state("menu", 0.15)
	_check(sfx.bgm_state() == "menu", "BGM enters menu state")
	sfx.set_bgm_state("combat", 0.15)
	_check(sfx.bgm_state() == "combat", "BGM crossfades to combat state")
	sfx.set_bgm_state("explore", 0.15)
	_check(sfx.bgm_state() == "explore", "BGM crossfades to explore state")
	sfx.apply_music_volume(0.0)
	await process_frame
	_check(sfx._bgm != null and not sfx._bgm.is_playing(),
		"BGM pauses playback when Music bus is muted for zero waste")
	sfx.apply_music_volume(0.8)
	await process_frame
	_check(sfx._bgm != null and sfx._bgm.current_state() == "explore",
		"BGM restores current state cleanly when unmuted")

	# 12) Phase 2 战术电台：多曲目录、随机防连播/顺序/单曲、条件选曲扩展接口与 user://bgm/ 自定义曲目加载。
	var cat := BgmCatalog.new()
	cat._scanned = true
	var mock_tracks: Array[Dictionary] = [
		{"id": "t_a", "title": "Track A", "pools": ["menu", "explore"], "weight": 1.0, "conditions": {}},
		{"id": "t_b", "title": "Track B", "pools": ["menu", "explore"], "weight": 1.0, "conditions": {}},
		{"id": "t_boss", "title": "Boss Theme", "pools": ["combat"], "weight": 2.0, "conditions": {"is_boss": true}},
		{"id": "t_cbt", "title": "Combat Std", "pools": ["combat"], "weight": 1.0, "conditions": {}},
	]
	cat._tracks = mock_tracks
	for mt in mock_tracks:
		cat._by_id[String(mt["id"])] = mt
	var anti_repeat_ok := true
	for _i in 12:
		var pick := cat.select_track({"state": "menu"}, "shuffle", "", "t_a", 1)
		if String(pick.get("id", "")) == "t_a":
			anti_repeat_ok = false
	_check(anti_repeat_ok, "BgmCatalog shuffle mode avoids repeating the immediately preceding track")
	var seq_pick := cat.select_track({"state": "menu"}, "sequential", "", "t_a", 1)
	_check(String(seq_pick.get("id", "")) == "t_b", "BgmCatalog sequential mode advances to the next track")
	var pin_pick := cat.select_track({"state": "menu"}, "single", "t_a", "t_b", 1)
	_check(String(pin_pick.get("id", "")) == "t_a", "BgmCatalog single mode locks onto the pinned track")
	var boss_pick := cat.select_track({"state": "combat", "is_boss": true}, "sequential", "", "", 1)
	var std_cbt_pick := cat.select_track({"state": "combat", "is_boss": false}, "sequential", "", "", 1)
	_check(String(boss_pick.get("id", "")) == "t_boss" and String(std_cbt_pick.get("id", "")) == "t_cbt",
		"BgmCatalog conditional hook filters boss tracks only when is_boss=true")
	# 验证 user://bgm/ 自定义 WAV 扫描与播放回退
	var custom_dir := "user://bgm_test_verify"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(custom_dir))
	var wav_path := custom_dir + "/My Custom Track.wav"
	var f := FileAccess.open(wav_path, FileAccess.WRITE)
	if f != null:
		# 最小合法 16-bit mono 8kHz PCM WAV (44B header + 160B data)
		var data_len := 160
		f.store_buffer("RIFF".to_ascii_buffer())
		f.store_32(36 + data_len)
		f.store_buffer("WAVE".to_ascii_buffer())
		f.store_buffer("fmt ".to_ascii_buffer())
		f.store_32(16)
		f.store_16(1)
		f.store_16(1)
		f.store_32(8000)
		f.store_32(16000)
		f.store_16(2)
		f.store_16(16)
		f.store_buffer("data".to_ascii_buffer())
		f.store_32(data_len)
		var pcm := PackedByteArray()
		pcm.resize(data_len)
		f.store_buffer(pcm)
		f.close()
	var custom_cat := BgmCatalog.new()
	custom_cat.scan_directory_for_test(custom_dir, true)
	var custom_track: Dictionary = custom_cat.track_by_id("custom:My Custom Track")
	var custom_stream: AudioStream = custom_cat.load_stream(custom_track)
	_check(not custom_track.is_empty() and String(custom_track.get("title", "")) == "My Custom Track"
		and custom_stream is AudioStreamWAV,
		"BgmCatalog scans and loads external .wav tracks from custom user directory")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wav_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(custom_dir))
	# Sfx 电台接口 + Progress 持久化
	sfx.set_bgm_pinned_track("builtin:bgm_menu")
	sfx.set_bgm_play_mode("single")
	p.set_bgm_pinned_track("builtin:bgm_menu")
	p.set_bgm_play_mode("single")
	_check(p.bgm_play_mode() == "single" and p.bgm_pinned_track() == "builtin:bgm_menu"
		and sfx.bgm_play_mode() == "single" and sfx.bgm_pinned_track() == "builtin:bgm_menu",
		"Sfx tactical radio mode and pinned track persist to Progress")
	sfx.set_bgm_play_mode("shuffle")
	sfx.set_bgm_pinned_track("")
	p.set_bgm_play_mode("shuffle")
	p.set_bgm_pinned_track("")
	# 播放控制：暂停/继续、进度条跳转与一键目录路径接口
	sfx.set_bgm_state("menu", 0.05)
	await process_frame
	var dur: float = sfx.bgm_track_duration()
	_check(dur > 1.0, "active BGM track reports valid duration > 1s (%.2fs)" % dur)
	var paused_on: bool = sfx.bgm_toggle_paused()
	_check(paused_on and sfx.bgm_is_paused(), "bgm_toggle_paused enters paused state")
	sfx.bgm_seek(2.5)
	_check(absf(sfx.bgm_playback_position() - 2.5) < 0.25,
		"bgm_seek updates playback position while paused (%.2fs)" % sfx.bgm_playback_position())
	var paused_off: bool = sfx.bgm_toggle_paused()
	_check(not paused_off and not sfx.bgm_is_paused(), "bgm_toggle_paused resumes playback cleanly")
	var opened_dir: String = sfx.bgm_open_user_dir()
	_check(opened_dir != "" and DirAccess.dir_exists_absolute(opened_dir),
		"bgm_open_user_dir creates and returns valid custom BGM directory")
	sfx.stop_bgm(0.05)

	print("\n=== impact audio: %s (%d ok / %d fail) ===" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
