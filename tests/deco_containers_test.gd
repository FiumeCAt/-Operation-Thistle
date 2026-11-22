extends SceneTree
## 装饰容器实装回归：衣服、物料箱等已摆件可以搜刮，标准容器仍会切换到开启贴图。
## godot --headless --path . --script res://tests/deco_containers_test.gd

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
	var p = root.get_node_or_null("Progress")
	if p != null:
		p.reset_for_test()
	var main = load("res://scenes/core/Main2D.tscn").instantiate()
	main.mouse_aim_enabled = false
	root.add_child(main)
	await process_frame
	await physics_frame

	var level = main.level
	_check(level.containers.size() == 52, "34 loot containers + 18 searchable props")

	var deco: Dictionary = {}
	var cloth: Dictionary = {}
	for entry in level.containers:
		if not bool(entry.get("keep_closed_art", false)):
			continue
		if deco.is_empty():
			deco = entry
		var art := String(entry.get("art", ""))
		if art.contains("coat") or art.contains("jacket") or art.contains("hazmat"):
			cloth = entry
			break
	_check(not deco.is_empty(), "decorative prop is registered as searchable")
	_check(not cloth.is_empty(), "clothing is registered as searchable")

	var all_ready := true
	for entry in level.containers:
		if entry.get("node") == null or entry.get("sprite") == null \
				or entry.get("hint") == null:
			all_ready = false
			break
	_check(all_ready, "every searchable has a node, sprite and hint")

	# 容器名字 / 稀有度配色 / 保险箱保底规则。
	_check(level.container_display_name(&"safe_military") == "军用保险箱",
		"military safe has a display name")
	_check(level.container_rarity_color(&"safe_military") \
			!= level.container_rarity_color(&"material_box"),
		"rarity colors differ between high and low value containers")
	_check(level.container_guarantees_advanced(&"safe_standard")
			and level.container_guarantees_advanced(&"safe_electronic")
			and level.container_guarantees_advanced(&"safe_military"),
		"standard / electronic / military safes guarantee an advanced material")
	_check(not level.container_guarantees_advanced(&"safe_small"),
		"small safe is excluded from the advanced guarantee")

	# 靠近未搜刮容器：HUD 左上角显示名字，容器上方显示 E 搜索。
	var near_entry: Dictionary = level.containers[0]
	var near_art := StringName(near_entry.get("art", &"material_box"))
	var saved_pos: Vector2 = main.doll.global_position
	main.doll.global_position = (near_entry["node"] as Node2D).global_position
	main._update_hud(0.016)
	_check(main.hud.interact_label.visible \
			and main.hud.interact_label.text == level.container_display_name(near_art),
		"HUD shows the nearby container name")
	_check(main.hud.interact_label.get_theme_color("font_color") \
			== level.container_rarity_color(near_art),
		"container name uses its rarity color")
	_check((near_entry["hint"] as Label).visible \
			and (near_entry["hint"] as Label).text == "E  搜索",
		"unsearched container shows the search hint")

	# 搜刮后靠近：悬浮文字变为“已搜索”，左上角交互名字隐藏。
	main._search_container(near_entry)
	main._update_hud(0.016)
	_check((near_entry["hint"] as Label).visible \
			and (near_entry["hint"] as Label).text == "已搜索",
		"searched container floats an already-searched label")
	_check(not main.hud.interact_label.visible,
		"searched container no longer shows the interaction name")
	main.doll.global_position = saved_pos

	# 保险箱保底：除小型保险箱外，每个保险箱必出至少 1 份进阶材料。
	var safes_found := 0
	for entry in level.containers:
		var art_id := StringName(entry.get("art", &""))
		if bool(entry["searched"]) or not level.container_guarantees_advanced(art_id):
			continue
		safes_found += 1
		var advanced_before := _advanced_total(main)
		main._search_container(entry)
		_check(_advanced_total(main) > advanced_before,
			"%s guarantees an advanced material" % level.container_display_name(art_id))
	_check(safes_found >= 3, "all guaranteed safe kinds are present (%d)" % safes_found)

	# 装饰物件：搜索后不发开箱图，但会变暗、隐藏提示并给资源。
	var deco_tex = deco["sprite"].texture
	var total_before: int = main.resources
	var parts_before: int = int(main.loot.get("parts", 0))
	main._search_container(deco)
	_check(bool(deco["searched"]), "decorative prop becomes searched")
	_check(deco["sprite"].texture == deco_tex, "decorative prop keeps its closed art")
	_check((deco["node"] as Node2D).modulate != Color(1, 1, 1, 1),
		"searched prop dims to show it is open")
	_check(not (deco["hint"] as Label).visible, "search hint hides after opening")
	_check(main.resources > total_before,
		"searching a decorative prop grants loot (%d -> %d)" % [total_before, main.resources])
	_check(int(main.loot.get("parts", 0)) + int(main.loot.get("electronics", 0)) \
			+ int(main.loot.get("energy", 0)) > parts_before,
		"decorative loot enters the run inventory")

	var cloth_tex = cloth["sprite"].texture
	main._search_container(cloth)
	_check(bool(cloth["searched"]) and cloth["sprite"].texture == cloth_tex,
		"clothing can be searched without changing its art")

	# 标准补给箱仍然有开启贴图。
	var normal: Dictionary = {}
	for entry in level.containers:
		if not bool(entry.get("searched", false)) \
				and not bool(entry.get("keep_closed_art", false)):
			normal = entry
			break
	_check(not normal.is_empty(), "an unsearched regular container remains")
	if not normal.is_empty():
		var art: Dictionary = level.container_art(StringName(normal["art"]))
		main._search_container(normal)
		_check(normal["sprite"].texture == art.get("open", null),
			"regular containers still swap to their open texture")

	main.queue_free()
	await process_frame
	print("\n=== deco containers: %s (%d ok / %d fail) ===" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit()


## 本局带出的进阶材料总数。
func _advanced_total(main) -> int:
	var total := 0
	for id in main.advanced_loot:
		total += int(main.advanced_loot[id])
	return total
