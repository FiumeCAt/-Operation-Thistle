extends Control
class_name Minimap2D
## 右上角 K-17 战术小地图 / 雷达：
## 支持方形 / 圆形切换、面板尺寸比例（70%–150%）与地图视野缩放（0.8×–2.5×），
## 带实时方位角（000°–359° + 8 方位罗盘）、视野扇区、目标光环与敌情追踪。

const SIZE := Vector2(320, 236)
const CIRCLE_BASE := 248.0
const CIRCLE_FOOTER := 28.0
const MAP_MARGIN := 10.0
const HEADER := 30.0
const RIGHT_MARGIN := 24.0
const TOP_MARGIN := 20.0
## 只显示玩家附近的敌人，保留探索紧张感。
const ENEMY_RADIUS := 760.0
const CARDINALS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var run: Node2D
var snapshot_provider: Callable = Callable()

## 当前渲染参数（自动从 Progress 同步，也可由单测直接覆盖）。
var map_shape := "square"
var map_scale := 1.0
var map_zoom := 1.0
var _use_progress_prefs := true

var _tick := 0.0
var _last_shape := ""
var _last_scale := -1.0
var _clip_poly: Polygon2D
var _map_canvas: Control
var _bezel_overlay: Control
var _cached_snap: Dictionary = {}


func setup(target: Node2D) -> void:
	run = target
	if target != null and target.has_method("get_map_snapshot"):
		snapshot_provider = target.get_map_snapshot
	else:
		snapshot_provider = Callable()


func set_snapshot_provider(provider: Callable) -> void:
	snapshot_provider = provider


## 供外部或单测显式覆写形状 / 比例 / 缩放（同时立即刷新布局与重绘）。
func configure(shape: String, ui_scale: float, zoom_level: float) -> void:
	_use_progress_prefs = false
	map_shape = shape if ["square", "circle"].has(shape) else "square"
	map_scale = clampf(ui_scale, 0.70, 1.50)
	map_zoom = clampf(zoom_level, 0.80, 2.50)
	_apply_layout(true)
	_redraw_all()


## 方位角（度）：正北（屏幕上方 -Y）= 0°，正东（+X）= 90°，正南（+Y）= 180°，正西（-X）= 270°。
static func bearing_degrees(aim_dir: Vector2) -> int:
	if aim_dir.length_squared() < 0.0001:
		return 90
	var deg := fposmod(rad_to_deg(aim_dir.angle()) + 90.0, 360.0)
	return int(round(deg)) % 360


static func bearing_cardinal(deg: int) -> String:
	var idx := int(floor(fposmod(float(deg) + 22.5, 360.0) / 45.0)) % 8
	return CARDINALS[idx]


static func bearing_text(aim_dir: Vector2) -> String:
	var deg := bearing_degrees(aim_dir)
	return "%03d° %s" % [deg, bearing_cardinal(deg)]


func _read_snapshot() -> Dictionary:
	if snapshot_provider.is_valid():
		var data = snapshot_provider.call()
		if data is Dictionary:
			return data
	if run != null and run.has_method("get_map_snapshot"):
		var data = run.get_map_snapshot()
		if data is Dictionary:
			return data
	return {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 内层裁剪蒙版：圆形用多边形 CLIP_CHILDREN_ONLY 精确裁成真圆，方形覆盖内区矩形。
	_clip_poly = Polygon2D.new()
	_clip_poly.name = "ClipMask"
	_clip_poly.color = Color.WHITE
	_clip_poly.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(_clip_poly)

	_map_canvas = Control.new()
	_map_canvas.name = "MapCanvas"
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_canvas.draw.connect(_draw_map_content)
	_clip_poly.add_child(_map_canvas)

	_bezel_overlay = Control.new()
	_bezel_overlay.name = "BezelOverlay"
	_bezel_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bezel_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bezel_overlay.draw.connect(_draw_bezel)
	add_child(_bezel_overlay)

	_sync_preferences()
	_apply_layout(true)
	set_process(true)


func _sync_preferences() -> void:
	if not _use_progress_prefs:
		return
	var p := get_node_or_null("/root/Progress")
	if p == null:
		return
	if p.has_method("minimap_shape"):
		map_shape = String(p.minimap_shape())
	if p.has_method("minimap_scale"):
		map_scale = float(p.minimap_scale())
	if p.has_method("minimap_zoom"):
		map_zoom = float(p.minimap_zoom())


func _apply_layout(force := false) -> void:
	if not force and map_shape == _last_shape and is_equal_approx(map_scale, _last_scale):
		return
	_last_shape = map_shape
	_last_scale = map_scale
	var target_size := Vector2(
		roundf(CIRCLE_BASE * map_scale),
		roundf((CIRCLE_BASE + CIRCLE_FOOTER) * map_scale),
	) if map_shape == "circle" else (SIZE * map_scale).round()
	custom_minimum_size = target_size
	if get_parent() is Control:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_right = -RIGHT_MARGIN
		offset_left = -RIGHT_MARGIN - target_size.x
		offset_top = TOP_MARGIN
		offset_bottom = TOP_MARGIN + target_size.y
	else:
		size = target_size
	_rebuild_clip_geometry(target_size)


func _rebuild_clip_geometry(s: Vector2) -> void:
	if _clip_poly == null or _map_canvas == null:
		return
	if map_shape == "circle":
		var radius := minf(s.x, s.y - CIRCLE_FOOTER * map_scale) * 0.5 - 6.0
		var center := Vector2(s.x * 0.5, radius + 6.0)
		var pts := PackedVector2Array()
		const SEGS := 56
		pts.resize(SEGS)
		for i in SEGS:
			var a := float(i) / float(SEGS) * TAU
			pts[i] = center + Vector2(cos(a) * radius, sin(a) * radius)
		_clip_poly.polygon = pts
	else:
		var top_y := HEADER + 6.0
		var r := Rect2(Vector2(MAP_MARGIN, top_y),
			Vector2(maxf(8.0, s.x - MAP_MARGIN * 2.0), maxf(8.0, s.y - top_y - 10.0)))
		_clip_poly.polygon = PackedVector2Array([
			r.position,
			Vector2(r.end.x, r.position.y),
			r.end,
			Vector2(r.position.x, r.end.y),
		])
	_map_canvas.position = Vector2.ZERO
	_map_canvas.size = s


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 0.08:
		_tick = 0.0
		_sync_preferences()
		_apply_layout(false)
		_redraw_all()


func _redraw_all() -> void:
	_cached_snap = _read_snapshot()
	queue_redraw()
	if _map_canvas != null:
		_map_canvas.queue_redraw()
	if _bezel_overlay != null:
		_bezel_overlay.queue_redraw()


func _map_area(s: Vector2) -> Rect2:
	if map_shape == "circle":
		var radius := minf(s.x, s.y - CIRCLE_FOOTER * map_scale) * 0.5 - 6.0
		var center := Vector2(s.x * 0.5, radius + 6.0)
		return Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var top_y := HEADER + 6.0
	return Rect2(Vector2(MAP_MARGIN, top_y),
		Vector2(maxf(8.0, s.x - MAP_MARGIN * 2.0), maxf(8.0, s.y - top_y - 10.0)))


## 背景底板（位于裁剪地图下层）。
func _draw() -> void:
	var s := size
	if s.x < 16.0 or s.y < 16.0:
		return
	if map_shape == "circle":
		var radius := minf(s.x, s.y - CIRCLE_FOOTER * map_scale) * 0.5 - 6.0
		var center := Vector2(s.x * 0.5, radius + 6.0)
		draw_circle(center, radius + 4.0, Color(0.010, 0.016, 0.024, 0.94), true, -1.0, true)
	else:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.010, 0.016, 0.024, 0.93), true)
		draw_rect(Rect2(Vector2(2, 2), Vector2(s.x - 4, HEADER + 2)),
			Color(0.04, 0.055, 0.075, 0.85), true)


## 裁剪后的地图内容：雷达网格、地板、房间、未搜刮箱、供电/撤离点、敌情、玩家视锥与箭头。
func _draw_map_content() -> void:
	var s := size
	var area := _map_area(s)
	var c := _map_canvas
	if area.size.x <= 4.0 or area.size.y <= 4.0:
		return

	# 背景战术雷达网格。
	var grid_col := Color(0.28, 0.48, 0.62, 0.14)
	if map_shape == "circle":
		var center := area.get_center()
		var rad := area.size.x * 0.5
		for frac in [0.33, 0.66]:
			c.draw_arc(center, rad * frac, 0.0, TAU, 48, grid_col, 1.0, true)
		c.draw_line(center + Vector2(-rad, 0), center + Vector2(rad, 0), grid_col, 1.0)
		c.draw_line(center + Vector2(0, -rad), center + Vector2(0, rad), grid_col, 1.0)
	else:
		var step := maxf(24.0, area.size.x / 8.0)
		var gx := area.position.x + step
		while gx < area.end.x:
			c.draw_line(Vector2(gx, area.position.y), Vector2(gx, area.end.y), grid_col, 1.0)
			gx += step
		var gy := area.position.y + step
		while gy < area.end.y:
			c.draw_line(Vector2(area.position.x, gy), Vector2(area.end.x, gy), grid_col, 1.0)
			gy += step

	var snap := _cached_snap if not _cached_snap.is_empty() else _read_snapshot()
	if snap.is_empty():
		return
	var map_size: Vector2 = snap.get("map_size", Vector2.ZERO)
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return
	var tile_size := float(snap.get("tile_size", GameUnits.TILE))
	var fit_scale := minf(area.size.x / map_size.x, area.size.y / map_size.y)
	var zoom := clampf(map_zoom, 0.80, 2.50)
	var world_scale := fit_scale * zoom
	var player: Vector2 = snap.get("player_pos", Vector2.ZERO)
	var offset: Vector2
	if zoom > 1.02 or map_shape == "circle":
		# 放大或圆形雷达模式：以玩家为中心跟随，化身战术近距雷达。
		offset = area.get_center() - player * world_scale
	else:
		offset = area.position + (area.size - map_size * world_scale) * 0.5

	for rect in snap.get("floor_rects", []):
		var r := Rect2(
			offset + Vector2(rect.position) * tile_size * world_scale,
			Vector2(rect.size) * tile_size * world_scale,
		)
		c.draw_rect(r, Color(0.24, 0.28, 0.33, 0.95), true)
	for room in snap.get("rooms", []):
		var rect: Rect2 = room["rect"]
		var rr := Rect2(offset + rect.position * world_scale, rect.size * world_scale)
		c.draw_rect(rr, Color(PixelUI.AMBER, 0.20), true)
		c.draw_rect(rr, Color(PixelUI.AMBER, 0.52), false, 1.0)

	# 玩家视角扇区（半透明青琥珀光锥）。
	var p := offset + player * world_scale
	var dir: Vector2 = snap.get("aim_dir", Vector2.RIGHT)
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	var cone_r := clampf(54.0 * map_scale * clampf(zoom, 0.8, 1.4), 32.0, 96.0)
	var half_fov := deg_to_rad(38.0)
	var base_ang := dir.angle()
	var cone_pts := PackedVector2Array([p])
	for i in 13:
		var a := lerpf(base_ang - half_fov, base_ang + half_fov, float(i) / 12.0)
		cone_pts.append(p + Vector2(cos(a), sin(a)) * cone_r)
	c.draw_colored_polygon(cone_pts, Color(0.55, 0.88, 1.0, 0.14))

	for entry in snap.get("containers", []):
		if not bool(entry["searched"]):
			var container_pos: Vector2 = entry["position"]
			c.draw_circle(offset + container_pos * world_scale, 1.6,
				Color(0.98, 0.72, 0.26, 0.82))

	var power_on := bool(snap.get("power_on", false))
	var power_pos: Vector2 = snap.get("power_position", Vector2.ZERO)
	var switch_exit_pos: Vector2 = snap.get("switch_exit_position", Vector2.ZERO)
	var exit_pos: Vector2 = snap.get("exit_position", Vector2.ZERO)
	var pwr_col := PixelUI.OK if power_on else Color(0.35, 0.78, 1.0, 0.98)
	var sw_col := PixelUI.OK if power_on else Color(0.58, 0.52, 0.40, 0.85)
	var ex_col := Color(0.24, 0.94, 0.80, 0.98)
	_draw_poi(c, offset + power_pos * world_scale, 3.4, pwr_col)
	_draw_poi(c, offset + switch_exit_pos * world_scale, 3.4, sw_col)
	_draw_poi(c, offset + exit_pos * world_scale, 4.0, ex_col)

	var tracking := bool(snap.get("tracking", false))
	for enemy_pos in snap.get("enemy_positions", []):
		var ep_world: Vector2 = enemy_pos
		var dist := player.distance_to(ep_world)
		if not tracking and dist >= ENEMY_RADIUS:
			continue
		var ep := offset + ep_world * world_scale
		if tracking:
			c.draw_circle(ep, 2.8, Color(1.0, 0.22, 0.14, 1.0))
			c.draw_arc(ep, 5.2, 0.0, TAU, 14, Color(1.0, 0.34, 0.20, 0.82), 1.2, true)
		else:
			c.draw_circle(ep, 2.2, Color(0.98, 0.32, 0.26, 0.95))

	# 玩家方向箭头：高对比雪白三角 + 外框，清晰指示朝向。
	var perp := Vector2(-dir.y, dir.x)
	var arrow := PackedVector2Array([
		p + dir * 7.5,
		p - dir * 4.5 + perp * 4.5,
		p - dir * 2.2,
		p - dir * 4.5 - perp * 4.5,
	])
	c.draw_colored_polygon(arrow, Color(0.94, 0.98, 1.0, 1.0))
	c.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]),
		Color(0.05, 0.08, 0.12, 0.85), 1.2, true)


func _draw_poi(c: Control, pos: Vector2, r: float, col: Color) -> void:
	c.draw_arc(pos, r + 2.4, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.38), 1.2, true)
	c.draw_circle(pos, r, col, true, -1.0, true)


## 外框、罗盘刻度与实时方位角读数（位于裁剪地图之上）。
func _draw_bezel() -> void:
	var s := size
	var o := _bezel_overlay
	if s.x < 16.0 or s.y < 16.0:
		return
	var snap := _cached_snap if not _cached_snap.is_empty() else _read_snapshot()
	var aim_dir: Vector2 = snap.get("aim_dir", Vector2.RIGHT)
	if aim_dir.length_squared() < 0.0001:
		aim_dir = Vector2.RIGHT
	var bearing := bearing_text(aim_dir)
	var zoom_tag := "%.1f×" % map_zoom

	if map_shape == "circle":
		var radius := minf(s.x, s.y - CIRCLE_FOOTER * map_scale) * 0.5 - 6.0
		var center := Vector2(s.x * 0.5, radius + 6.0)
		o.draw_arc(center, radius + 2.0, 0.0, TAU, 72, Color(PixelUI.AMBER, 0.88), 2.2, true)
		o.draw_arc(center, radius - 2.0, 0.0, TAU, 72, Color(PixelUI.AMBER, 0.25), 1.0, true)
		# 36 道罗盘刻度（每 10° 一格，主方位加长）。
		for i in 36:
			var ang := float(i) * deg_to_rad(10.0) - PI * 0.5
			var major := (i % 9 == 0)
			var mid := (i % 3 == 0)
			var tick_len := 7.0 if major else (4.5 if mid else 2.5)
			var dir := Vector2(cos(ang), sin(ang))
			var col := PixelUI.DANGER if i == 0 else (Color(PixelUI.AMBER_BRIGHT, 0.9) if major else Color(PixelUI.AMBER, 0.45))
			o.draw_line(center + dir * (radius - tick_len), center + dir * (radius + 1.0), col, 1.6 if major else 1.0, true)
		# 实时朝向指针三角（贴外圈指示当前方位角）。
		var aim_u := aim_dir.normalized()
		var perp := Vector2(-aim_u.y, aim_u.x)
		var tip := center + aim_u * (radius + 6.0)
		var base := center + aim_u * (radius - 1.0)
		o.draw_colored_polygon(PackedVector2Array([tip, base + perp * 4.5, base - perp * 4.5]),
			PixelUI.AMBER_BRIGHT)
		# 四向方位字标 N/E/S/W（内缩避开外圈刻度线）。
		var fs := clampi(int(round(12.0 * map_scale)), 11, 16)
		o.draw_string(PixelUI.FONT, center + Vector2(-4, -radius + 22), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PixelUI.DANGER)
		o.draw_string(PixelUI.FONT, center + Vector2(-4, radius - 11), "S",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PixelUI.DIM)
		o.draw_string(PixelUI.FONT, center + Vector2(radius - 20, 4), "E",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PixelUI.DIM)
		o.draw_string(PixelUI.FONT, center + Vector2(-radius + 11, 4), "W",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PixelUI.DIM)
		# 底部方位角胶囊条：显示「090° E · 1.2×」。
		var pill_h := maxf(22.0, CIRCLE_FOOTER * map_scale - 4.0)
		var pill_w := minf(s.x - 16.0, 176.0 * map_scale)
		var pill_rect := Rect2(Vector2((s.x - pill_w) * 0.5, s.y - pill_h), Vector2(pill_w, pill_h))
		o.draw_rect(pill_rect, Color(0.014, 0.020, 0.028, 0.94), true)
		o.draw_rect(pill_rect, Color(PixelUI.AMBER, 0.78), false, 1.5)
		var pill_fs := clampi(int(round(14.0 * map_scale)), 12, 18)
		var label_txt := "%s  ·  %s" % [bearing, zoom_tag]
		o.draw_string(PixelUI.FONT,
			Vector2(pill_rect.position.x, pill_rect.position.y + pill_h * 0.72),
			label_txt, HORIZONTAL_ALIGNMENT_CENTER, pill_rect.size.x, pill_fs, PixelUI.AMBER_BRIGHT)
	else:
		o.draw_rect(Rect2(Vector2.ZERO, s), Color(PixelUI.AMBER, 0.85), false, 2.0)
		for pt in [Vector2.ZERO, Vector2(s.x - 16, 0), Vector2(0, s.y - 4), Vector2(s.x - 16, s.y - 4)]:
			o.draw_rect(Rect2(pt, Vector2(16, 4)), PixelUI.AMBER, true)
		for pt in [Vector2.ZERO, Vector2(s.x - 4, 0), Vector2(0, s.y - 16), Vector2(s.x - 4, s.y - 16)]:
			o.draw_rect(Rect2(pt, Vector2(4, 16)), PixelUI.AMBER, true)
		o.draw_string(PixelUI.FONT, Vector2(12, 24), "K-17 // RADAR",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PixelUI.AMBER)
		var right_txt := "%s  %s" % [bearing, zoom_tag]
		o.draw_string(PixelUI.FONT, Vector2(12, 24), right_txt,
			HORIZONTAL_ALIGNMENT_RIGHT, s.x - 24, 15, PixelUI.AMBER_BRIGHT)
		o.draw_line(Vector2(10, 33), Vector2(s.x - 10, 33), Color(PixelUI.AMBER, 0.40), 1.0)
		# 四向罗盘方位标：北向高亮，其余淡色贴边。
		var area := _map_area(s)
		var cx := area.position.x + area.size.x * 0.5
		var cy := area.position.y + area.size.y * 0.5
		o.draw_string(PixelUI.FONT, Vector2(cx - 4, area.position.y + 13), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelUI.DANGER)
		o.draw_string(PixelUI.FONT, Vector2(cx - 4, area.end.y - 4), "S",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelUI.DIM)
		o.draw_string(PixelUI.FONT, Vector2(area.end.x - 13, cy + 4), "E",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelUI.DIM)
		o.draw_string(PixelUI.FONT, Vector2(area.position.x + 5, cy + 4), "W",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PixelUI.DIM)
