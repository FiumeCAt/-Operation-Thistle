extends RefCounted
class_name ArmoryArmorView
## 武备库「护甲数据 // ARMOR」子页视图：当前护甲属性 + RHA 等级表 + 受击结算规则。
## 从 ArmoryMenu2D 抽离，与 DamageModel / ModInstallService 同源。

const DAMAGE_MODEL := preload("res://scripts/combat/DamageModel.gd")
const MOD_SERVICE := preload("res://scripts/ui/armory/ModInstallService.gd")

var page: VBoxContainer
var values: Dictionary = {}


func build(parent: Node) -> void:
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.visible = false
	parent.add_child(page)

	var title := PixelUI.label(page, "DOL-01 // 护甲数据", PixelUI.FS_TITLE, PixelUI.AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var divider := HSeparator.new()
	divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.5))
	page.add_child(divider)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)

	var stats := PixelUI.panel()
	stats.custom_minimum_size.x = 520
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(stats)
	var stat_rows := VBoxContainer.new()
	stat_rows.add_theme_constant_override("separation", 8)
	stats.add_child(stat_rows)
	for key in ["耐久上限", "防御等级", "基础减伤", "护甲吸收", "穿甲规则", "耐久衰减"]:
		var line := HBoxContainer.new()
		stat_rows.add_child(line)
		var name_label := PixelUI.label(line, key, PixelUI.FS_BODY, PixelUI.DIM)
		name_label.custom_minimum_size.x = 130
		var value := PixelUI.label(line, "-", PixelUI.FS_BODY, PixelUI.TEXT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		values[key] = value

	var rules := PixelUI.panel()
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(rules)
	var rule_rows := VBoxContainer.new()
	rule_rows.add_theme_constant_override("separation", 6)
	rules.add_child(rule_rows)
	PixelUI.label(rule_rows, "护甲等级 // RHA TIERS", PixelUI.FS_BODY, PixelUI.AMBER)
	for i in 4:
		var tier_rha := DAMAGE_MODEL.player_base_rha(i + 1)
		PixelUI.label(rule_rows, "Lv.%d    护甲防御 %d（%.1fmm RHA）" % [
			i + 1, int(round(tier_rha)), tier_rha * 0.1],
			PixelUI.FS_BODY, PixelUI.TEXT)
	var rule_divider := HSeparator.new()
	rule_divider.add_theme_color_override("color", Color(PixelUI.AMBER, 0.35))
	rule_rows.add_child(rule_divider)
	var hint := PixelUI.label(rule_rows,
		"RHA 均质装甲体系：10 点防御 = 1.0mm 均质装甲钢（可在设置切换显示格式）。\n"
		+ "未击穿（穿深 < 有效防御）：护甲承担主要伤害，仅 5%~20% 极轻钝伤入血。\n"
		+ "击穿（穿深 >= 有效防御）：25%~50% 穿透入血，同时护甲剧烈碎裂（100%~130% 耐久损耗），常规受击甲先于血碎。\n"
		+ "耐久越低有效防御越弱（缓降至 50%）；耐久归零后失去护甲防护（除非有组件/天赋最低减伤）。",
		PixelUI.FS_BODY, PixelUI.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL


func refresh(progress: Node) -> void:
	if values.is_empty():
		return
	var maximum := 100
	var level := 1
	var armor_mods := ModDB.default_modifiers()
	var mode := MOD_SERVICE.armor_display_mode(progress)
	if progress != null:
		maximum = int(progress.data.get("armor_max", 100))
		level = int(progress.data.get("armor_level", 1))
		armor_mods = ModDB.modifiers(progress.armor_mods_2d(), true)
	# 与局内 Doll2D 一致：护甲组件直接加在上限 / RHA 防御等级 / 钝伤削减上。
	maximum += int(armor_mods["armor_max_add"])
	level += int(armor_mods["armor_level_add"])
	var rha := DAMAGE_MODEL.player_base_rha(level)
	var absorb_bonus_pct := int(round(float(armor_mods["absorb_add"]) * 100.0))
	values["耐久上限"].text = "%d / %d" % [maximum, maximum]
	values["防御等级"].text = "Lv.%d · %s" % [level, DAMAGE_MODEL.format_rha(rha, mode)]
	values["基础减伤"].text = "未击穿 5%~20% 钝伤"
	values["护甲吸收"].text = "钝伤削减 +%d%%（主扣耐久）" % absorb_bonus_pct
	values["穿甲规则"].text = "击穿 25%~50% 穿血 · 剧烈碎甲"
	values["耐久衰减"].text = "满 100% → 残 50% · 0 失防"
