extends SceneTree
## ArmoryTooltipView & ArmoryArmorView 独立单测：
## 验证 CJK/ASCII 词元折行、悬浮面板显隐/定位、护甲视图 RHA 双模式与组件加成刷新。
## godot --headless --path . --script res://tests/armory_subview_test.gd

const TOOLTIP_VIEW := preload("res://scripts/ui/armory/ArmoryTooltipView.gd")
const ARMOR_VIEW := preload("res://scripts/ui/armory/ArmoryArmorView.gd")
const DETAIL_VIEW := preload("res://scripts/ui/armory/ArmoryDetailView.gd")

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
	root.size = Vector2i(1600, 900)
	await process_frame
	var host := Control.new()
	host.size = Vector2(1240, 820)
	PixelUI.apply_theme(host)
	root.add_child(host)
	await process_frame

	# 1. Tooltip 构建、折行与显隐
	var tip_view: ArmoryTooltipView = TOOLTIP_VIEW.new()
	tip_view.build(host)
	_check(tip_view.tip_panel != null and tip_view.tip_label != null and not tip_view.is_visible(),
		"ArmoryTooltipView builds hidden panel and label")

	var font: Font = tip_view.tip_label.get_theme_font("font")
	var tokens := TOOLTIP_VIEW.tip_tokens("测试12345abc文字", 520.0, font, 18)
	_check(tokens.has("12345abc") and tokens.has("测") and tokens.has("字"),
		"tip_tokens keeps ASCII runs intact while splitting CJK per-char")

	var wrapped := TOOLTIP_VIEW.wrap_tip_text("这是一段很长很长的中文说明用于验证固定像素宽度自动折行不会越界", 120.0, 18, font)
	_check(wrapped.contains("\n"), "wrap_tip_text wraps long text to fit pixel width")

	tip_view.tips["弹匣容量"] = "弹匣容量\n基础 5 发 → 实际 7 发\n加成来源：\n· 弹匣 · 加长管仓"
	tip_view.show_tip("弹匣容量")
	_check(tip_view.is_visible() and tip_view.tip_label.text.contains("加长管仓"),
		"show_tip displays formatted tooltip text")
	tip_view.hide_tip()
	_check(not tip_view.is_visible(), "hide_tip hides tooltip cleanly")

	# 2. ArmorView 构建与双模式 / 护甲组件刷新
	var armor_view: ArmoryArmorView = ARMOR_VIEW.new()
	armor_view.build(host)
	_check(armor_view.page != null and armor_view.values.size() == 6,
		"ArmoryArmorView builds six armor stat rows")

	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
		armor_view.refresh(p)
		_check(armor_view.values["耐久上限"].text == "100 / 100"
			and armor_view.values["防御等级"].text.contains("30"),
			"ArmorView displays default Lv.1 30 RHA value")
		p.set_armor_display("rha_mm")
		p.data["armor_mods_2d"] = {"plate": "ceramic", "liner": "gel"}
		armor_view.refresh(p)
		_check(armor_view.values["耐久上限"].text == "140 / 140"
			and armor_view.values["防御等级"].text.contains("3.0mm RHA")
			and armor_view.values["护甲吸收"].text.contains("+5%"),
			"ArmorView reflects ceramic plate, gel liner, and rha_mm format")

		# 3. DetailView 独立构建与刷新（定置排序 + 配件绿/红增减 + 悬浮来源同步）
		p.reset_for_test()
		p.data["weapon_mods_2d"]["m870"] = {"magazine": "tube_long"}
		var detail_view: ArmoryDetailView = DETAIL_VIEW.new()
		detail_view.build(host)
		detail_view.refresh(&"m870", &"akm", &"g17", p, tip_view)
		_check(detail_view.weapon_buttons.size() == WeaponDB.WEAPON_ORDER.size()
			and detail_view.weapon_list.get_child(0) == detail_view.weapon_buttons[&"akm"]
			and detail_view.weapon_list.get_child(1) == detail_view.weapon_buttons[&"g17"],
			"ArmoryDetailView pins primary and secondary weapons to top")
		_check(detail_view.detail_title.text.contains("M870")
			and detail_view.detail_values["弹匣容量"].text.contains("7")
			and detail_view.detail_deltas["弹匣容量"].text.contains("(+2)")
			and tip_view.tips["弹匣容量"].contains("加长管仓"),
			"ArmoryDetailView computes modded stats, deltas, and refreshes tooltips")
		p.reset_for_test()

	host.queue_free()
	await process_frame
	print("\n=== armory subviews: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
