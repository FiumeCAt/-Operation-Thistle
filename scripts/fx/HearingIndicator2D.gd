extends CanvasLayer
class_name HearingIndicator2D
## 声纹指示（移植自 3D 版 HearingIndicator）：
## 玩家脚下常驻一圈细环，附近移动的敌人会在环上对应方向亮起一段声纹弧。
## 用屏幕空间绘制，不会被视野迷雾压暗，玩家能据此察觉背后的敌人。

const RADIUS := 92.0
const HEARING_METERS := 10.0
const TILE := 64.0
const BUCKETS := 12
const ARC_DEG := 26.0
const RING_ALPHA := 0.10
const ARC_ALPHA_MIN := 0.30
const ARC_ALPHA_MAX := 0.85
const COLOR := Color(0.72, 0.88, 1.0)

var main: Node = null
var player: Node2D = null
var _view: Control
var _alphas: Array[float] = []


func setup(main_node, player_node) -> void:
	main = main_node
	player = player_node
	layer = 6
	_view = Control.new()
	_view.name = "HearingView"
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_alphas.resize(BUCKETS)
	for i in BUCKETS:
		_alphas[i] = 0.0


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or _view == null:
		return
	var targets: Array[float] = []
	targets.resize(BUCKETS)
	for i in BUCKETS:
		targets[i] = 0.0
	var hearing := HEARING_METERS * TILE
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var hp_value = enemy.get("hp")
		if hp_value != null and float(hp_value) <= 0.0:
			continue
		var body := enemy as CharacterBody2D
		var speed := body.velocity.length() if body != null else 0.0
		if speed < 30.0:
			continue
		var offset: Vector2 = enemy.global_position - player.global_position
		var distance: float = offset.length()
		if distance > hearing or distance < 1.0:
			continue
		var idx := int(round(offset.angle() / (TAU / float(BUCKETS))))
		idx = ((idx % BUCKETS) + BUCKETS) % BUCKETS
		var strength := lerpf(ARC_ALPHA_MAX, ARC_ALPHA_MIN, distance / hearing)
		strength *= clampf(speed / 160.0, 0.55, 1.0)
		targets[idx] = maxf(targets[idx], strength)
	for i in BUCKETS:
		_alphas[i] = lerpf(_alphas[i], targets[i], 1.0 - exp(-12.0 * delta))
	if _view != null:
		_view.queue_redraw()


func _draw_view() -> void:
	if player == null or not is_instance_valid(player):
		return
	var ct: Transform2D = _view.get_viewport().get_canvas_transform()
	var center: Vector2 = ct * player.global_position
	_view.draw_arc(center, RADIUS, 0.0, TAU, 64, Color(COLOR, RING_ALPHA), 1.5)
	for i in BUCKETS:
		var alpha: float = _alphas[i]
		if alpha <= 0.02:
			continue
		var mid := float(i) * TAU / float(BUCKETS)
		var half := deg_to_rad(ARC_DEG) * 0.5
		_view.draw_arc(center, RADIUS + 8.0, mid - half, mid + half, 10,
			Color(COLOR, alpha), 3.0)
