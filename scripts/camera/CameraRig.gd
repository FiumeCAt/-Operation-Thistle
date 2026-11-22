extends Node3D
class_name CameraRig
## 中键独立旋转镜头；普通鼠标与人物朝向不驱动镜头。

@export_group("Lens")
@export var pitch_deg := 52.0
@export var distance := 12.0
@export var fov := 38.0

@export_group("Follow")
@export var follow_speed := 8.0
@export var aim_distance := 16.0
@export var aim_look_ahead := 2.0
var _view_distance := 12.0
var _aim_direction := Vector3.FORWARD
var _ignore_warp := false

var target: Node3D
var trauma := 0.0
@onready var cam: Camera3D = $Camera3D
var _t := 0.0
var _noise := FastNoiseLite.new()
var _shade: ShaderMaterial

@export_group("Orbit")
@export var orbit_degrees_per_pixel := 0.18
## 关闭后锁定水平旋转：立绘只有固定正面视角，转镜头会破坏透视。
@export var allow_orbit := false

@export_group("Zoom")
@export var zoom_step := 1.12
@export var zoom_min := 0.45
@export var zoom_max := 2.6
## 滚轮缩放倍率，作用在预设距离上；切换预设时保留。
var zoom_scale := 1.0

@export_group("Free Camera")
@export var free_pitch_min := 18.0
@export var free_pitch_max := 85.0
## 调试用自由镜头：F8 打开后可拖动改俯角与水平角，不受预设限制。
var free_camera_enabled := false

var orbit_dragging := false
var _orbit_mouse := Vector2.ZERO
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _window_focused := true

func aim_screen_position() -> Vector2:
	return _orbit_mouse if orbit_dragging else get_viewport().get_mouse_position()

## 滚轮缩放：steps > 0 拉近，< 0 拉远。
func zoom_by(steps: float) -> void:
	zoom_scale = clampf(zoom_scale * pow(zoom_step, -steps), zoom_min, zoom_max)

func reset_zoom() -> void:
	zoom_scale = 1.0

func set_free_camera(on: bool) -> void:
	free_camera_enabled = on
	if not on:
		stop_orbit()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not get_tree().paused:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-1.0)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if not allow_orbit and not free_camera_enabled:
			get_viewport().set_input_as_handled()
			return
		if not event.pressed or event.canceled:
			stop_orbit()
		elif not get_tree().paused and _window_focused and is_instance_valid(target):
			if not orbit_dragging:
				_orbit_mouse = get_viewport().get_mouse_position()
				_previous_mouse_mode = Input.mouse_mode
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				orbit_dragging = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and orbit_dragging:
		if get_tree().paused or not _window_focused:
			stop_orbit()
			return
		# 位移而非速度：不乘 dt，无插值尾巴，松开立即停止。
		var motion: Vector2 = event.screen_relative
		if motion == Vector2.ZERO:
			motion = event.relative
		rotation.y = wrapf(rotation.y - deg_to_rad(motion.x * orbit_degrees_per_pixel), -PI, PI)
		if free_camera_enabled and motion.y != 0.0:
			pitch_deg = clampf(pitch_deg - motion.y * orbit_degrees_per_pixel, free_pitch_min, free_pitch_max)
		if motion != Vector2.ZERO:
			_latch_aim_direction(_orbit_mouse)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _ignore_warp and event.position.distance_to(_orbit_mouse) < 1.0:
			_ignore_warp = false
			return
		_ignore_warp = false
		if event.relative != Vector2.ZERO or event.screen_relative != Vector2.ZERO:
			_latch_aim_direction(event.position)
	elif event.is_action_pressed("aim"):
		_latch_aim_direction(aim_screen_position())

func _latch_aim_direction(screen: Vector2) -> void:
	if get_tree().paused or not _window_focused or not is_instance_valid(target):
		return
	var hit = Plane(Vector3.UP, Doll.AIM_HEIGHT).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if hit != null:
		var direction: Vector3 = hit - target.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.04:
			_aim_direction = direction.normalized()

func stop_orbit() -> void:
	if not orbit_dragging:
		return
	orbit_dragging = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = _previous_mouse_mode
		# 先清除拖动状态，再恢复指针，warp 事件不会驱动旋转。
		_ignore_warp = true
		get_viewport().warp_mouse(_orbit_mouse)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		stop_orbit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true
	elif what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		stop_orbit()

func _ready() -> void:
	_noise.seed = 1337
	_noise.frequency = 6.0
	_noise.fractal_octaves = 2
	rotation_degrees.x = -pitch_deg
	_view_distance = distance
	cam.position = Vector3(0.0, 0.0, _view_distance)
	cam.fov = fov
	cam.near = 0.1
	cam.far = 400.0
	var layer := CanvasLayer.new()
	layer.name = "RearVisibility"
	layer.layer = 0
	add_child(layer)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = ShaderMaterial.new()
	_shade.shader = preload("res://shaders/rear_visibility.gdshader")
	rect.material = _shade
	layer.add_child(rect)

func set_target(t: Node3D) -> void:
	target = t
	if t:
		global_position = Vector3(t.global_position.x, 0.0, t.global_position.z)

## 应用摄像机预设；跟随距离由 _process 平滑过渡。
func apply_preset(pitch: float, dist: float, field_of_view: float) -> void:
	pitch_deg = pitch
	distance = dist
	fov = field_of_view

func add_shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(dt: float) -> void:
	if get_tree().paused:
		stop_orbit()
		return
	var aiming := _window_focused and is_instance_valid(target) and Input.is_action_pressed("aim")
	var blend := 1.0 - exp(-follow_speed * dt)
	var base_distance := aim_distance if aiming else distance
	_view_distance = lerpf(_view_distance, base_distance * zoom_scale, blend)
	if is_instance_valid(target):
		var tp := target.global_position
		tp.y = 0.0
		if aiming:
			tp += _aim_direction * aim_look_ahead
		global_position = global_position.lerp(tp, blend)
	rotation.x = deg_to_rad(-pitch_deg)
	cam.fov = fov
	trauma = maxf(0.0, trauma - dt * 2.2)
	_t += dt
	var amp := trauma * trauma
	var sx := _noise.get_noise_2d(_t * 140.0, 11.0) * 0.34 * amp
	var sy := _noise.get_noise_2d(7.0, _t * 120.0) * 0.28 * amp
	cam.position = Vector3(sx, sy, _view_distance)
	cam.rotation.z = _noise.get_noise_2d(_t * 90.0, 55.0) * 0.035 * amp
	_update_shade()

func _update_shade() -> void:
	if not is_instance_valid(target):
		return
	var size := get_viewport().get_visible_rect().size
	# 非归一化世界射线可在线性插值后与地面求交，不依赖深度/渲染后端。
	var origin := cam.global_position
	var rays: Array[Vector3] = []
	for point in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y)]:
		rays.append(cam.project_position(point, 1.0) - origin)
	_shade.set_shader_parameter("ray_origin", origin)
	_shade.set_shader_parameter("ray_tl", rays[0])
	_shade.set_shader_parameter("ray_dx", rays[1] - rays[0])
	_shade.set_shader_parameter("ray_dy", rays[2] - rays[0])
	_shade.set_shader_parameter("player_xz", Vector2(target.global_position.x, target.global_position.z))
	_shade.set_shader_parameter("forward_xz", Vector2(sin(target.global_rotation.y), cos(target.global_rotation.y)))
