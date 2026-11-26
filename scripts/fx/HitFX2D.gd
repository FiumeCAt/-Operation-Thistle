extends RefCounted
class_name HitFX2D
## 命中特效统一走 pixelfx 特效库（addons/pixelfx），不再手绘粒子。
##   金属：impacts/hit-spark（volt 冷黄高光）；击杀叠 impacts/crit-hit（gold 调）。
##   血肉：impacts/blunt-hit（血色调）；击杀叠 impacts/crit-hit（血色调）。
## 全部用 BAKED 模式，同参数的特效共用烘焙帧；方向用节点旋转，不会反复重烘焙。

const METAL_PRESET := "volt"
const METAL_KILL_PRESET := "gold"
const BLOOD_PRESET := "blood"


## 统一入口：材质决定特效库里的哪一支，方向决定喷溅朝向。
## level 控制"击中特写"：2 完整 / 1 减弱（默认，缩小且不叠击杀特写）/ 0 关闭。
static func enemy_hit(parent: Node, pos: Vector2, dir: Vector2,
		material := "metal", weight := 1.0, killed := false, level := 1,
		is_weakspot := false) -> void:
	if parent == null or not parent.is_inside_tree() or level <= 0:
		return
	var s := (1.05 + clampf(weight, 0.7, 1.8) * 0.28) * (1.0 if level >= 2 else 0.6)
	var with_crit := killed and level >= 2
	if material == "flesh":
		Shot2D.pixel_fx(parent, "impacts/blunt-hit", pos, dir.angle(), 70, s,
			PixelFx2D.Mode.BAKED, BLOOD_PRESET, {
				"height": 0,
				"warm": "#d42a30",
				"dust": "#6a101c",
				"clod": "#a01824",
			}, 0.75)
		if with_crit:
			Shot2D.pixel_fx(parent, "impacts/crit-hit", pos, dir.angle(), 71, s * 1.05,
				PixelFx2D.Mode.BAKED, BLOOD_PRESET, {"height": 0, "aim": 0.0}, 0.8)
	else:
		Shot2D.pixel_fx(parent, "impacts/hit-spark", pos, dir.angle(), 70, s,
			PixelFx2D.Mode.BAKED, METAL_PRESET, {"height": 0, "aim": 0.0}, 0.62)
		if with_crit:
			Shot2D.pixel_fx(parent, "impacts/crit-hit", pos, dir.angle(), 71, s * 1.05,
				PixelFx2D.Mode.BAKED, METAL_KILL_PRESET, {"height": 0, "aim": 0.0}, 0.8)
	if is_weakspot:
		# 弱点命中叠一层金红爆发火花（复用已预热的 gold hit-spark，零额外烘焙卡顿）。
		Shot2D.pixel_fx(parent, "impacts/hit-spark", pos, dir.angle(), 72, s * 1.18,
			PixelFx2D.Mode.BAKED, "gold", {"height": 0, "aim": 0.0}, 0.75)
		Shot2D.impact(parent, pos, Color(1.0, 0.34, 0.16))


## 所有会被首次命中/击杀触发的 pixelfx 变体（含不同调色板）。
## 击杀特写只在「完整」档位使用，因此该档位才预热 crit-hit，避免默认档位白烘 2 秒。
## opts 已按运行时的 fx_options() 展开，相对 prebake_step 才能命中同一份缓存。
static func impact_variants() -> Array[Dictionary]:
	var variants: Array[Dictionary] = [
		_variant("impacts/blunt-hit", BLOOD_PRESET, {
			"height": 0, "warm": "#d42a30", "dust": "#6a101c", "clod": "#a01824",
		}),
		_variant("impacts/hit-spark", METAL_PRESET, {"height": 0, "aim": 0.0}),
		_variant("impacts/bullet-impact", "", {"height": 0}),
	]
	if _hit_fx_level() >= 2:
		variants.append(_variant("impacts/crit-hit", BLOOD_PRESET,
			{"height": 0, "aim": 0.0}))
		variants.append(_variant("impacts/crit-hit", METAL_KILL_PRESET,
			{"height": 0, "aim": 0.0}))
	variants.append(_variant("impacts/hit-spark", "gold", {"height": 0, "aim": 0.0}))
	return variants


static func _hit_fx_level() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1
	var progress := tree.root.get_node_or_null("Progress")
	if progress == null:
		return 1
	return int(progress.data.get("hit_fx_level", 1))


static func _variant(id: String, preset: String, options: Dictionary) -> Dictionary:
	# 借一个不入树的节点把 palette_preset 展开成运行时完全一致的 opts。
	var probe := PixelFx2D.new()
	probe.effect = id
	if preset != "":
		probe.palette_preset = preset
	probe.options = options
	var opts := probe.fx_options()
	probe.free()
	return {"id": id, "opts": opts}
