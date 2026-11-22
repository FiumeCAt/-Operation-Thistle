extends SceneTree
## 一次性工具：写入 InputMap 到 project.godot
## 运行：godot --headless --path . --script res://tools/setup_input.gd

func _key(code: Key, physical := true) -> InputEventKey:
	var ev := InputEventKey.new()
	if physical:
		ev.physical_keycode = code
	else:
		ev.keycode = code
	return ev

func _mb(idx: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx
	return ev

func _initialize() -> void:
	var actions := {
		"move_forward": [_key(KEY_W), _key(KEY_UP)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT)],
		"sprint": [_key(KEY_SHIFT), _key(KEY_SHIFT, false)],
		"fire": [_mb(MOUSE_BUTTON_LEFT)],
		"aim": [_mb(MOUSE_BUTTON_RIGHT)],
		"interact": [_key(KEY_E)],
		"reload": [_key(KEY_R)],
		"reload_mag": [_key(KEY_F)],
		"ammo_switch": [_key(KEY_Q)],
		"grenade": [_key(KEY_G)],
		"heal": [_key(KEY_H)],
		"flashlight": [_key(KEY_T)],
		"support": [_key(KEY_X)],
		"ammo_display": [_key(KEY_J)],
		"weapon_1": [_key(KEY_1)],
		"weapon_2": [_key(KEY_2)],
		"weapon_3": [_key(KEY_3)],
		"weapon_4": [_key(KEY_4)],
		"debug_cursor": [_key(KEY_F1)],
		"debug_capture": [_key(KEY_F12)],
		"debug_stress": [_key(KEY_F3)],
		"debug_reset": [_key(KEY_F5)],
	}

	for name in actions.keys():
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		for ev in actions[name]:
			InputMap.action_add_event(name, ev)
		var evs: Array = []
		for ev in InputMap.action_get_events(name):
			evs.append(ev)
		ProjectSettings.set_setting("input/" + name, {
			"deadzone": 0.2,
			"events": evs,
		})

	var err := ProjectSettings.save()
	print("[setup_input] saved project.godot: ", error_string(err))
	quit(0 if err == OK else 1)
