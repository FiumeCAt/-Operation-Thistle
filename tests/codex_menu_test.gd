extends SceneTree
## 图鉴回归：敌人/物品两个子页、条目数量、配图、数值、描述框、底角翻页与 ESC 关闭。
## godot --headless --path . --script res://tests/codex_menu_test.gd

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
	create_timer(60.0).timeout.connect(func() -> void: quit(2))
	root.size = Vector2i(1600, 900)
	await process_frame

	var menu = load("res://scenes/ui/StartMenu2D.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	_check(menu.codex_button != null and menu.codex_button.text.contains("图鉴"),
		"start menu has codex button")
	_check(menu.codex != null and not menu.codex.visible, "codex hidden at start")

	menu._open_codex()
	await process_frame
	await process_frame
	var codex = menu.codex
	_check(codex.visible, "codex opens from the base menu")

	# 敌人子页：8 条，默认第一条为哨兵。
	_check(codex.enemy_count() == 8, "eight enemy entries")
	_check(codex.item_count() == 55, "fifty-five item entries (18 weapons + 30 ammo + 7 resources)")
	_check(codex._detail_title.text.contains("哨兵"), "first enemy is rifleman")
	_check(codex._portrait.texture != null, "enemy portrait texture loaded")
	_check(codex._note_label.text.length() > 12, "enemy archive note has text")
	_check(codex._note_footer.text.contains("待补充"), "archive note keeps a placeholder footer")
	_check(codex._prev_button.disabled, "first enemy disables previous button")
	_check(codex._page_label.text.contains("01 / 08"), "enemy page counter starts at 1 / 8")

	codex._step(1)
	_check(codex._detail_title.text.contains("突击者"), "next enemy is rusher")
	_check(not codex._prev_button.disabled, "previous enabled after paging forward")

	# 歌利亚：额外显示爆炸半径/伤害/引信三项。
	for i in 6:
		codex._step(1)
	_check(codex._detail_title.text.contains("歌利亚"), "goliath page reachable")
	var visible_stats := 0
	var stat_names: Array[String] = []
	for row in codex._stat_rows:
		if row["cell"].visible:
			visible_stats += 1
			stat_names.append(row["name"].text)
	_check(visible_stats == 14, "goliath shows fourteen detail stats including weakspot")
	_check(stat_names.has("弱点部位") and stat_names.has("爆炸半径") and stat_names.has("爆炸伤害") and stat_names.has("引爆延迟"),
		"goliath weakspot and explosion stats listed")
	_check(codex._next_button.disabled, "last enemy disables next button")
	_check(codex._page_label.text.contains("08 / 08"), "enemy page counter ends at 8 / 8")

	# 物品子页：18 武器 + 30 弹药 + 7 资源 = 55 条。
	codex._show_page("item")
	await process_frame
	_check(codex._tab_item.text.begins_with("▶"), "item tab marked active")
	_check(codex._detail_title.text.contains("M870"), "first item is M870")
	var m870_ws_val := ""
	for row in codex._stat_rows:
		if row["cell"].visible and row["name"].text == "弱点加成":
			m870_ws_val = row["value"].text
	_check(m870_ws_val == "+15%", "codex weapon detail displays weakspot bonus (+15% for M870)")
	_check(codex._portrait.texture != null, "weapon portrait texture loaded")
	_check(codex._page_label.text.contains("01 / 55"), "item page counter starts at 1 / 55")
	_check(codex._note_label.text.length() > 12, "weapon archive note has text")

	var missing_portrait := 0
	var missing_title := 0
	for i in codex.item_count():
		codex._item_index = i
		codex._refresh_entry()
		if codex._portrait.texture == null:
			missing_portrait += 1
		if codex._detail_title.text.strip_edges() == "":
			missing_title += 1
	_check(missing_portrait == 0, "all 55 items have a portrait")
	_check(missing_title == 0, "all 55 items have a title")

	codex._item_index = codex.item_count() - 1
	codex._refresh_entry()
	_check(codex._next_button.disabled, "last item disables next button")
	_check(not codex._prev_button.disabled, "last item keeps previous enabled")
	_check(codex._page_label.text.contains("55 / 55"), "item page counter ends at 55 / 55")

	# 翻页按钮位于面板内部左下/右下，且图标已加载。
	await process_frame
	var panel_left := (root.size.x - 1240.0) * 0.5
	var panel_right := (root.size.x + 1240.0) * 0.5
	var panel_top := (root.size.y - 820.0) * 0.5
	var panel_bottom := (root.size.y + 820.0) * 0.5
	var prev_rect: Rect2 = codex._prev_button.get_global_rect()
	var next_rect: Rect2 = codex._next_button.get_global_rect()
	_check(prev_rect.position.x >= panel_left and prev_rect.end.x < root.size.x * 0.5,
		"previous button sits in the panel bottom-left")
	_check(next_rect.end.x <= panel_right and next_rect.position.x > root.size.x * 0.5,
		"next button sits in the panel bottom-right")
	_check(prev_rect.position.y > panel_top + (panel_bottom - panel_top) * 0.75,
		"previous button sits near the bottom")
	_check(next_rect.position.y > panel_top + (panel_bottom - panel_top) * 0.75,
		"next button sits near the bottom")
	_check(prev_rect.end.x < next_rect.position.x, "paging buttons do not overlap")
	var prev_icon = codex._prev_button.get_child(0)
	var next_icon = codex._next_button.get_child(0)
	_check(prev_icon is TextureRect and prev_icon.texture != null,
		"previous button uses the arrow icon")
	_check(next_icon is TextureRect and next_icon.texture != null,
		"next button uses the arrow icon")

	# ESC 只关闭图鉴，不触发主菜单退出。
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_input(esc)
	await process_frame
	_check(not codex.visible, "ESC closes the codex")
	_check(menu.start_button.has_focus(), "focus returns to the start button")

	menu.queue_free()
	await process_frame
	print("\n=== codex menu: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()
