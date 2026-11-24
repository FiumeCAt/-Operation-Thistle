extends RefCounted
class_name SfxSamples
## 外部命中采样库（CC0，位于 assets/audio/sfx/impacts）：
## 负责材质映射表、惰性加载与预热，以及按材质随机抽样与通用回退。

const IMPACT_SAMPLE_ROOT := "res://assets/audio/sfx/impacts/"
const IMPACT_SAMPLE_SETS := {
	"concrete": [
		"concrete/concrete_hit_01.ogg",
		"concrete/concrete_hit_02.ogg",
		"concrete/concrete_hit_03.ogg",
		"concrete/concrete_shatter_01.ogg",
	],
	"metal": [
		"metal/metal_hit_01.ogg",
		"metal/metal_hit_02.ogg",
		"metal/metal_hit_03.ogg",
		"metal/metal_ping_01.wav",
		"metal/metal_clink_01.wav",
		"metal/metal_thud_01.wav",
	],
	"ricochet": [
		"ricochet/ricochet_01.ogg",
		"ricochet/ricochet_02.ogg",
		"ricochet/ricochet_03.ogg",
		"ricochet/metal_ring_long.wav",
	],
	"flesh": [
		"flesh/flesh_hit_01.mp3",
		"flesh/flesh_hit_02.mp3",
		"flesh/flesh_hit_03.mp3",
		"flesh/flesh_hit_04.mp3",
	],
	"generic": [
		"generic/bullet_impact_01.wav",
		"generic/bullet_impact_02.wav",
		"generic/bullet_impact_03.wav",
		"generic/bullet_impact_heavy_01.wav",
		"generic/bullet_impact_heavy_02.wav",
		"generic/impact_rash_01.wav",
		"generic/impact_rash_02.wav",
	],
}

var _samples: Dictionary = {}
var _loaded := false


## 惰性加载采样；文件缺失（未导入/被删）时该项为空，调用方自动退回程序化层。
func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for key in IMPACT_SAMPLE_SETS:
		var loaded: Array = []
		for rel in IMPACT_SAMPLE_SETS[key]:
			var path: String = IMPACT_SAMPLE_ROOT + String(rel)
			if not ResourceLoader.exists(path):
				continue
			var res = load(path)
			if res is AudioStream:
				loaded.append(res)
		_samples[key] = loaded


func is_loaded() -> bool:
	return _loaded


func count(material: String) -> int:
	ensure_loaded()
	return (_samples.get(material, []) as Array).size()


## 按材质抽取一条命中采样；未知或缺失材质自动回落到 generic；均无可用时返回 null。
func pick_for_material(material: String) -> AudioStream:
	ensure_loaded()
	var key := material
	if (_samples.get(key, []) as Array).is_empty():
		key = "generic"
	var list: Array = _samples.get(key, [])
	if list.is_empty():
		return null
	return list.pick_random() as AudioStream


## 金属跳弹尾音采样。
func pick_ricochet() -> AudioStream:
	ensure_loaded()
	var list: Array = _samples.get("ricochet", [])
	if list.is_empty():
		return null
	return list.pick_random() as AudioStream
