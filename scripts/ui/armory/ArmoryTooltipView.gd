extends RefCounted
class_name ArmoryTooltipView
## 武备库武器数据悬浮来源面板：切角描边底板 + 固定宽度 CJK/ASCII 词元折行 + 鼠标跟随边缘翻转。
## 从 ArmoryMenu2D 抽离，对外暴露 tip_panel / tip_label / tips 供宿主与测试访问。

const TIP_WIDTH := 520.0

const STAT_KEYS: Array[String] = [
	"口径", "弹匣容量", "供弹方式", "换弹时间", "射速", "射程", "子弹速度", "散布",
	"枪声范围", "弹药", "弹丸数", "穿甲", "伤害",
	"后坐抑制", "垂直后坐", "水平后坐", "视野倍率", "瞄准速度",
]

const STAT_EFFECT := {
	"换弹时间": "reload_mul",
	"射速": "fire_mul",
	"射程": "range_mul",
	"子弹速度": "speed_mul",
	"散布": "spread_mul",
	"枪声范围": "sound_mul",
	"伤害": "damage_mul",
	"后坐抑制": "recoil_mul",
	"视野倍率": "vision_mul",
	"瞄准速度": "ads_speed_mul",
}

var _host: Control
var tip_panel: PanelContainer
var tip_label: Label
var tips: Dictionary = {}


## 构建悬浮窗节点，挂在宿主 Control 上层；尺寸由文本行数手动计算，避免容器自动布局抖动。
func build(host: Control) -> void:
	_host = host
	tip_panel = PixelUI.panel(PixelUI.BG_LIGHT)
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	host.add_child(tip_panel)
	tip_label = PixelUI.label(host, "", 18, PixelUI.TEXT)
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label.visible = false
	# 兜底：即使字体测量有亚像素误差，文本也不会越出底板边缘。
	tip_label.clip_text = true


func is_visible() -> bool:
	return tip_panel != null and tip_panel.visible


## 悬浮来源面板：先按固定宽度手动折行，再按行数反推底板尺寸，保证首帧排版正确。
func show_tip(key: String) -> void:
	if tip_panel == null or _host == null:
		return
	var text := String(tips.get(key, ""))
	if text == "":
		return
	var view := _host.get_viewport_rect().size
	var tip_width := minf(TIP_WIDTH, maxf(view.x - 80.0, 240.0))
	var font: Font = tip_label.get_theme_font("font")
	var wrapped := wrap_tip_text(text, tip_width, 18, font)
	var text_size := font.get_multiline_string_size(
		wrapped, HORIZONTAL_ALIGNMENT_LEFT, tip_width, 18)
	var content := Vector2(tip_width, maxf(ceilf(text_size.y) + 4.0, 22.0))
	tip_label.text = wrapped
	tip_panel.size = content + Vector2(28.0, 20.0)
	tip_label.size = content
	tip_panel.visible = true
	tip_label.visible = true
	tip_panel.move_to_front()
	tip_label.move_to_front()
	place_tip()


func hide_tip() -> void:
	if tip_panel != null:
		tip_panel.visible = false
	if tip_label != null:
		tip_label.visible = false


func place_tip() -> void:
	if tip_panel == null or not tip_panel.visible or _host == null:
		return
	var mouse := _host.get_global_mouse_position()
	var view := _host.get_viewport_rect().size
	var size := tip_panel.size
	var pos := mouse + Vector2(22, 16)
	if pos.x + size.x > view.x - 12.0:
		pos.x = mouse.x - size.x - 22.0
	if pos.y + size.y > view.y - 12.0:
		pos.y = mouse.y - size.y - 16.0
	var max_pos := view - size - Vector2(8, 8)
	if max_pos.x < 8.0 or max_pos.y < 8.0:
		# 文本比视口还高时贴左上角，至少保证左侧与顶部不越界。
		pos = Vector2(8, 8)
	else:
		pos = pos.clamp(Vector2(8, 8), max_pos)
	tip_panel.global_position = pos
	tip_label.global_position = pos + Vector2(14, 10)


## 按像素宽度折行：中文逐字、连续 ASCII 视为一个词，避免把数字/英文拆断。
## 单个词本身就比悬浮窗宽时（长编号/网址），退化为逐字拆分，保证不越界。
static func wrap_tip_text(text: String, width: float, font_size: int, font: Font) -> String:
	if font == null:
		return text
	var lines: Array[String] = []
	for paragraph in text.split("\n"):
		var line := ""
		for token in tip_tokens(paragraph, width, font, font_size):
			if line != "" and font.get_string_size(
					line + token, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				lines.append(line)
				line = token
			else:
				line += token
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


## 把一段文字切成可折行的词元：ASCII 连续串算一个词，其他字符逐字。
static func tip_tokens(paragraph: String, width: float,
		font: Font, font_size: int) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < paragraph.length():
		var ch := paragraph[i]
		var token := paragraph.substr(i, 1)
		if ch != " " and _is_ascii_char(ch):
			var j := i
			while j + 1 < paragraph.length():
				var next := paragraph[j + 1]
				if next == " " or not _is_ascii_char(next):
					break
				j += 1
			token = paragraph.substr(i, j - i + 1)
			i = j
		if token != " " and font.get_string_size(
				token, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			for c in token:
				out.append(String(c))
		else:
			out.append(token)
		i += 1
	return out


static func _is_ascii_char(ch: String) -> bool:
	var code := ch.unicode_at(0)
	return code >= 32 and code < 127


## 悬浮提示：基础值 → 实际值，再列出参与该数值的配件与战术天赋。
func refresh_tooltips(selected: StringName, installed: Dictionary, reload_talent: float,
		ammo, detail_base: Dictionary, detail_values: Dictionary, progress: Node) -> void:
	for key in STAT_KEYS:
		var text := key
		if detail_base.has(key) and String(detail_base[key]) != "":
			text += "\n基础 %s → 实际 %s" % [
				String(detail_base[key]), detail_values[key].text]
		if key == "弹药" and ammo != null:
			# 弹药行只描述弹种自身属性，伤害计算放在「伤害」行。
			var cat: Dictionary = WeaponDB.category_table().get(String(ammo.category), {})
			text += "\n弹丸 %d · 散布 %.1f° · 穿甲 %d · 通用备弹 %d" % [
				ammo.pellets, rad_to_deg(ammo.spread), int(ammo.ap),
				int(cat.get("reserve_max", ammo.reserve_max))]
			if not cat.is_empty():
				text += "\n属性：%s · %s" % [
					String(cat.get("display_name", "")), String(cat.get("note", ""))]
			tips[key] = text
			continue
		if key == "弹丸数" and ammo != null:
			text += "\n每发 %d 颗弹丸，全部命中才吃满伤害" % ammo.pellets
			tips[key] = text
			continue
		if key == "穿甲" and ammo != null:
			var ap_val := int(round(float(ammo.ap)))
			text += "\n穿甲 %d（%.1f mm RHA）· 穿甲高于目标护甲时击穿并触发余穿增伤" % [
				ap_val, float(ammo.ap) * 0.1]
			tips[key] = text
			continue
		var effect_key := String(STAT_EFFECT.get(key, ""))
		var sources: Array[String] = []
		if effect_key != "":
			for slot_def in ModDB.WEAPON_SLOTS:
				var slot := String(slot_def["id"])
				var option_id := String(installed.get(slot, ""))
				if option_id == "":
					continue
				var entry := ModDB.option(slot, option_id, false, String(selected))
				if entry.is_empty():
					continue
				var effects: Dictionary = entry.get("effects", {})
				if not effects.has(effect_key):
					continue
				var summary := ModInstallService.sight_stats_line(entry) \
					if slot == "sight" else String(entry["desc"])
				sources.append("· %s · %s：%s" % [
					String(slot_def["name"]), String(entry["name"]), summary])
		if key == "弹匣容量":
			var mag_entry := ModDB.option(
				"magazine", String(installed.get("magazine", "")), false, String(selected))
			if not mag_entry.is_empty():
				sources.append("· 弹匣 · %s：%s" % [
					String(mag_entry["name"]), String(mag_entry["desc"])])
			if progress != null:
				var mag_level := int(progress.talent_2d_level(&"magazine"))
				if mag_level > 0:
					sources.append("· 战术天赋 · 弹匣扩容 Lv.%d：容量 +%d%%" % [
						mag_level, mag_level * 10])
		elif key == "射速":
			var core := ModDB.option(
				"core", String(installed.get("core", "")), false, String(selected))
			if not core.is_empty():
				var core_fx: Dictionary = core.get("effects", {})
				if core_fx.has("fire_interval_set"):
					sources.append("· 枪机 · %s：%s" % [
						String(core["name"]), String(core["desc"])])
		if key == "换弹时间" and reload_talent < 0.999:
			sources.append("· 战术天赋 · 快速换弹：换弹时间 %+.0f%%" % [
				(reload_talent - 1.0) * 100.0])
		if key == "散布":
			text += "\n腰射全锥角；配件收益与开镜收紧按弹种区分"
			if ammo != null:
				var ads_pct := int(round((1.0 - float(ammo.ads_spread_mul)) * 100.0))
				text += "\n本弹种开镜：散布收紧 %d%%（配件收益 %d%%）" % [
					ads_pct, int(round(float(ammo.attachment_spread_scale) * 100.0))]
			var gun_level := int(progress.talent_2d_level(&"gun")) if progress != null else 0
			if gun_level > 0:
				sources.append("· 战术天赋 · 枪械精度 Lv.%d：散布 %+.0f%%" % [
					gun_level, (WeaponStatsModel.gun_accuracy_mul(gun_level) - 1.0) * 100.0])
		if key == "子弹速度":
			text += "\n现实枪口初速，已包含弹种与枪管长度差异"
			var time_scale := float(ammo.bullet_time_scale) if ammo != null else 0.294
			text += "\n游戏内飞行时间按 %.3f 时间压缩" % time_scale
		if sources.is_empty():
			text += "\n无配件加成 · 使用基础数据"
		else:
			text += "\n加成来源：\n" + "\n".join(PackedStringArray(sources))
		tips[key] = text
