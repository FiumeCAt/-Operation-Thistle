extends Node
## 命中/击杀特效预热：把 pixelfx 的烘焙拆成「每帧只烘一帧动画」，
## 避免第一次命中时一次性烘焙几十帧造成明显卡顿。
## 主菜单会提前启动；局内再启动一次作为兜底，缓存已就绪时会很快跑完。

var _queue: Array[Dictionary] = []
var _variant: Dictionary = {}
var _frame := 0


func setup(variants: Array[Dictionary]) -> void:
	# 无头测试没有渲染与真实帧预算，跳过预热，避免拖慢用例。
	if DisplayServer.get_name() == "headless":
		set_process(false)
		queue_free()
		return
	_queue = variants.duplicate(true)
	set_process(not _queue.is_empty())


func _process(_delta: float) -> void:
	# 每帧最多占用约 4ms，超过预算就留到下一帧，避免菜单或局内出现长卡顿。
	var deadline := Time.get_ticks_usec() + 4000
	while Time.get_ticks_usec() < deadline:
		if _variant.is_empty():
			if _queue.is_empty():
				set_process(false)
				queue_free()
				return
			_variant = _queue.pop_front()
			_frame = 0
		var done := PixelFx2D.prebake_step(
			String(_variant.get("id", "")), _variant.get("opts", {}), "", _frame)
		_frame += 1
		if done:
			_variant = {}
