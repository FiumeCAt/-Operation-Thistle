extends RefCounted
class_name AudioBusService
## 音频总线管理服务（无状态纯工具）：
## 负责创建/查询 SFX 与 Music 总线，并将线性 0–1 音量或 Progress 存档值同步到 AudioServer。

const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"


static func ensure_bus(bus_name: StringName) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	index = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	return index


static func set_bus_volume(index: int, value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	AudioServer.set_bus_mute(index, v <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.001)))


static func apply_volumes(master: float, sfx: float) -> void:
	set_bus_volume(0, master)
	set_bus_volume(ensure_bus(SFX_BUS), sfx)


static func apply_music_volume(music: float) -> void:
	set_bus_volume(ensure_bus(MUSIC_BUS), music)


static func apply_saved_volumes(progress: Node) -> void:
	if progress == null:
		return
	apply_volumes(
		float(progress.data.get("volume", 0.8)),
		float(progress.data.get("sfx_volume", 0.8)))
	apply_music_volume(float(progress.data.get("music_volume", 0.8)))
