extends OmniLight3D
## 廉价闪烁灯：正弦抖动 + 偶发掉电，不做 Tween/每帧随机。

@export var flicker_amount := 0.06
@export var dip_chance := 0.12

var base_energy := 2.0
var _t := 0.0
var _dip := 0.0

func _ready() -> void:
	base_energy = light_energy
	_t = randf() * 10.0

func _process(dt: float) -> void:
	_t += dt
	if _dip <= 0.0 and randf() < dip_chance * dt:
		_dip = randf_range(0.05, 0.18)
	_dip = maxf(0.0, _dip - dt)
	var n := sin(_t * 7.3) * flicker_amount + sin(_t * 23.0) * flicker_amount * 0.5
	var e := base_energy * (1.0 + n)
	if _dip > 0.0:
		e *= 0.25
	light_energy = e
