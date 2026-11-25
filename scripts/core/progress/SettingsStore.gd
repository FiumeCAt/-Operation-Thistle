extends RefCounted
class_name ProgressSettingsStore
## 设置项与外观/调试参数存储（纯逻辑，直接读写 Progress.data 字典，无 I/O 副作用）。

const SAVE_STORE := preload("res://scripts/core/progress/SaveStore.gd")
const DEFAULT_LASER_COLOR := SAVE_STORE.DEFAULT_LASER_COLOR
const DEFAULT_RETICLE_COLOR := SAVE_STORE.DEFAULT_RETICLE_COLOR
const AMMO_DISPLAY_MODES := SAVE_STORE.AMMO_DISPLAY_MODES


static func laser_color(data: Dictionary) -> Color:
	return _sight_color(data, "laser_color", DEFAULT_LASER_COLOR)


static func reticle_color(data: Dictionary) -> Color:
	return _sight_color(data, "reticle_color", DEFAULT_RETICLE_COLOR)


static func _sight_color(data: Dictionary, key: String, fallback: String) -> Color:
	var raw := String(data.get(key, fallback))
	return Color.html(raw) if Color.html_is_valid(raw) else Color.html(fallback)


static func set_laser_color(data: Dictionary, color: Color) -> void:
	data["laser_color"] = "#" + color.to_html(false)


static func set_reticle_color(data: Dictionary, color: Color) -> void:
	data["reticle_color"] = "#" + color.to_html(false)


static func ui_theme(data: Dictionary) -> String:
	var id := String(data.get("ui_theme", SAVE_STORE.DEFAULT_UI_THEME))
	return id if SAVE_STORE.UI_THEME_IDS.has(id) else SAVE_STORE.DEFAULT_UI_THEME


static func set_ui_theme(data: Dictionary, theme_id: String) -> bool:
	if not SAVE_STORE.UI_THEME_IDS.has(theme_id):
		return false
	data["ui_theme"] = theme_id
	return true


static func ui_theme_color(data: Dictionary) -> Color:
	return _sight_color(data, "ui_theme_color", SAVE_STORE.DEFAULT_UI_THEME_COLOR)


static func set_ui_theme_color(data: Dictionary, color: Color) -> void:
	data["ui_theme_color"] = "#" + color.to_html(false)


static func ammo_display(data: Dictionary) -> String:
	var mode := String(data.get("ammo_display", "both"))
	return mode if AMMO_DISPLAY_MODES.has(mode) else "both"


static func set_ammo_display(data: Dictionary, mode: String) -> bool:
	if not AMMO_DISPLAY_MODES.has(mode):
		return false
	data["ammo_display"] = mode
	return true


static func set_fire_rate_display(data: Dictionary, mode: String) -> bool:
	if not ["interval", "rpm"].has(mode):
		return false
	data["fire_rate_display"] = mode
	return true


static func armor_display(data: Dictionary) -> String:
	var mode := String(data.get("armor_display", "value"))
	return mode if ["value", "rha_mm"].has(mode) else "value"


static func set_armor_display(data: Dictionary, mode: String) -> bool:
	if not ["value", "rha_mm"].has(mode):
		return false
	data["armor_display"] = mode
	return true


static func set_volume(data: Dictionary, value: float) -> void:
	data["volume"] = clampf(value, 0.0, 1.0)


static func set_sfx_volume(data: Dictionary, value: float) -> void:
	data["sfx_volume"] = clampf(value, 0.0, 1.0)


static func set_music_volume(data: Dictionary, value: float) -> void:
	data["music_volume"] = clampf(value, 0.0, 1.0)


static func set_screen_shake(data: Dictionary, enabled: bool) -> void:
	data["screen_shake"] = enabled


static func set_bullet_trail_enabled(data: Dictionary, enabled: bool) -> void:
	data["bullet_trail_enabled"] = enabled


static func set_hitstop_enabled(data: Dictionary, enabled: bool) -> void:
	data["hitstop_enabled"] = enabled


static func set_shake_scale(data: Dictionary, value: float) -> void:
	data["shake_scale"] = clampf(value, 0.0, 1000.0)


static func set_sample_impacts(data: Dictionary, enabled: bool) -> void:
	data["sample_impacts"] = enabled


static func set_hit_fx_level(data: Dictionary, level: int) -> void:
	data["hit_fx_level"] = clampi(level, 0, 2)


static func set_view_zoom(data: Dictionary, value: float) -> void:
	data["view_zoom"] = clampf(roundf(value / 10.0) * 10.0, 20.0, 200.0)


static func minimap_shape(data: Dictionary) -> String:
	var shape := String(data.get("minimap_shape", "square"))
	return shape if ["square", "circle"].has(shape) else "square"


static func set_minimap_shape(data: Dictionary, shape: String) -> bool:
	if not ["square", "circle"].has(shape):
		return false
	data["minimap_shape"] = shape
	return true


static func minimap_scale(data: Dictionary) -> float:
	return clampf(float(data.get("minimap_scale", 1.0)), 0.70, 1.50)


static func set_minimap_scale(data: Dictionary, value: float) -> void:
	data["minimap_scale"] = clampf(roundf(value * 20.0) / 20.0, 0.70, 1.50)


static func minimap_zoom_min(data: Dictionary) -> float:
	var zmin := clampf(
		roundf(float(data.get("minimap_zoom_min", SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MIN)) * 10.0) / 10.0,
		SAVE_STORE.MINIMAP_ZOOM_HARD_MIN, 2.00)
	var zmax := clampf(
		roundf(float(data.get("minimap_zoom_max", SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MAX)) * 10.0) / 10.0,
		1.00, SAVE_STORE.MINIMAP_ZOOM_HARD_MAX)
	return minf(zmin, zmax)


static func minimap_zoom_max(data: Dictionary) -> float:
	var zmin := clampf(
		roundf(float(data.get("minimap_zoom_min", SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MIN)) * 10.0) / 10.0,
		SAVE_STORE.MINIMAP_ZOOM_HARD_MIN, 2.00)
	var zmax := clampf(
		roundf(float(data.get("minimap_zoom_max", SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MAX)) * 10.0) / 10.0,
		1.00, SAVE_STORE.MINIMAP_ZOOM_HARD_MAX)
	return maxf(zmax, zmin)


static func set_minimap_zoom_min(data: Dictionary, value: float) -> void:
	var zmin := clampf(roundf(value * 10.0) / 10.0, SAVE_STORE.MINIMAP_ZOOM_HARD_MIN, 2.00)
	var zmax := minimap_zoom_max(data)
	if zmin > zmax:
		zmax = clampf(zmin, 1.00, SAVE_STORE.MINIMAP_ZOOM_HARD_MAX)
		zmin = minf(zmin, zmax)
		data["minimap_zoom_max"] = zmax
	data["minimap_zoom_min"] = zmin
	data["minimap_zoom"] = clampf(float(data.get("minimap_zoom", 1.0)), zmin, zmax)


static func set_minimap_zoom_max(data: Dictionary, value: float) -> void:
	var zmax := clampf(roundf(value * 10.0) / 10.0, 1.00, SAVE_STORE.MINIMAP_ZOOM_HARD_MAX)
	var zmin := minimap_zoom_min(data)
	if zmax < zmin:
		zmin = clampf(zmax, SAVE_STORE.MINIMAP_ZOOM_HARD_MIN, 2.00)
		zmax = maxf(zmax, zmin)
		data["minimap_zoom_min"] = zmin
	data["minimap_zoom_max"] = zmax
	data["minimap_zoom"] = clampf(float(data.get("minimap_zoom", 1.0)), zmin, zmax)


static func minimap_zoom(data: Dictionary) -> float:
	return clampf(float(data.get("minimap_zoom", 1.0)), minimap_zoom_min(data), minimap_zoom_max(data))


static func set_minimap_zoom(data: Dictionary, value: float) -> void:
	data["minimap_zoom"] = clampf(roundf(value * 10.0) / 10.0, minimap_zoom_min(data), minimap_zoom_max(data))


static func typewriter_enabled(data: Dictionary) -> bool:
	return bool(data.get("typewriter_enabled", false))


static func set_typewriter_enabled(data: Dictionary, enabled: bool) -> void:
	data["typewriter_enabled"] = enabled


static func typewriter_speed(data: Dictionary) -> float:
	return clampf(roundf(float(data.get("typewriter_speed", SAVE_STORE.DEFAULT_TYPEWRITER_SPEED))), 15.0, 140.0)


static func set_typewriter_speed(data: Dictionary, speed: float) -> void:
	data["typewriter_speed"] = clampf(roundf(speed), 15.0, 140.0)


static func pickup_merge_window(data: Dictionary) -> float:
	return clampf(
		roundf(float(data.get("pickup_merge_window", SAVE_STORE.DEFAULT_PICKUP_MERGE_WINDOW)) * 2.0) / 2.0,
		SAVE_STORE.PICKUP_MERGE_MIN, SAVE_STORE.PICKUP_MERGE_MAX)


static func set_pickup_merge_window(data: Dictionary, seconds: float) -> void:
	data["pickup_merge_window"] = clampf(
		roundf(seconds * 2.0) / 2.0,
		SAVE_STORE.PICKUP_MERGE_MIN, SAVE_STORE.PICKUP_MERGE_MAX)


static func set_motion_blur(data: Dictionary, enabled: bool) -> void:
	data["motion_blur"] = enabled


static func scope_motion_blur(data: Dictionary) -> bool:
	return bool(data.get("scope_motion_blur", true))


static func set_scope_motion_blur(data: Dictionary, enabled: bool) -> void:
	data["scope_motion_blur"] = enabled


static func scope_lens_distortion(data: Dictionary) -> bool:
	return bool(data.get("scope_lens_distortion", true))


static func set_scope_lens_distortion(data: Dictionary, enabled: bool) -> void:
	data["scope_lens_distortion"] = enabled


static func reticle_style(data: Dictionary, sight_id: String, fallback: String) -> String:
	var styles: Dictionary = data.get("reticle_styles", {})
	return String(styles.get(sight_id, fallback))


static func set_reticle_style(data: Dictionary, sight_id: String, style: String) -> void:
	var styles: Dictionary = data.get("reticle_styles", {})
	styles[sight_id] = style
	data["reticle_styles"] = styles


static func debug_enabled(data: Dictionary) -> bool:
	return bool(data.get("debug_enabled", false))


static func set_debug_enabled(data: Dictionary, enabled: bool) -> void:
	data["debug_enabled"] = enabled


static func debug_value(data: Dictionary, key: String) -> float:
	var dbg: Dictionary = data.get("debug", {})
	return clampf(float(dbg.get(key, 1.0)), 0.0, 100.0)


static func debug_mul(data: Dictionary, key: String) -> float:
	if not debug_enabled(data):
		return 1.0
	return debug_value(data, key)


static func set_debug_value(data: Dictionary, key: String, value: float) -> void:
	var dbg: Dictionary = data.get("debug", {})
	dbg[key] = clampf(value, 0.0, 100.0)
	data["debug"] = dbg


static func reset_debug(data: Dictionary) -> void:
	data["debug"] = {
		"recoil_v": 1.0, "recoil_h": 1.0, "recoil_cap": 1.0,
		"spread": 1.0, "damage": 1.0, "ads": 1.0, "move": 1.0, "vision": 1.0,
	}
	data["minimap_zoom_min"] = SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MIN
	data["minimap_zoom_max"] = SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MAX
	data["minimap_zoom"] = clampf(float(data.get("minimap_zoom", 1.0)),
		SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MIN, SAVE_STORE.DEFAULT_MINIMAP_ZOOM_MAX)


static func set_camera_mode(data: Dictionary, mode: int) -> void:
	data["camera_mode"] = clampi(mode, 0, 2)


static func set_bright_test(data: Dictionary, enabled: bool) -> void:
	data["bright_test"] = enabled
