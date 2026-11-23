extends RefCounted
class_name EnemyVisual2D
## 2D 敌人视觉表现与特效子系统：
## 统一管理旧静态立绘与新 16 帧 AnimatedSprite2D、碰撞/Hitbox、血条、头顶警觉图标、
## 受击闪白/压扁形变、炮塔激光/歌利亚自爆倒计时圆环绘制，以及刀光/爆炸/死亡收尾动画。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
const SHADOW_TEX: Texture2D = preload("res://assets/art/fx/shadow_radial.png")
## 发现玩家时的红色感叹号：8 帧贴图，带发光与 Wi-Fi 式外扩波纹。
const ALERT_ICON_SHEET: Texture2D = preload("res://assets/art/fx/enemy_alert.png")
const ALERT_FRAMES := 8
const ALERT_FPS := 12.0
const ALERT_LIFE := 1.25
const ALERT_ICON_SCALE := 0.68
const ALERT_ICON_LIFT := 38.0

var sprite: Sprite2D
var sprite_h := 0.0
var anim: AnimatedSprite2D
var bar_bg: Polygon2D
var bar_fill: Polygon2D
var alert_icon: Sprite2D
var alert_t := 0.0

var anim_override := ""
var anim_override_t := 0.0
var bob := 0.0
var hit_flash := 0.0
var squash := 0.0


func build(host: Node2D, def: EnemyDef) -> void:
	if def.frames_path != "" and ResourceLoader.exists(def.frames_path):
		_build_animated_visual(host, def, load(def.frames_path))
	else:
		_build_still_visual(host, def)
	_build_body_nodes(host, def)
	_build_alert_icon(host)


func _build_still_visual(host: Node2D, def: EnemyDef) -> void:
	var tex: Texture2D = load(def.texture_path)
	var s := def.body_scale
	sprite_h = tex.get_height() * s
	_make_shadow(host)
	sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(-tex.get_width() * s * 0.5, -sprite_h)
	host.add_child(sprite)


## 新单位：16 帧像素图集（640×384 单元格，脚底 y=372）。
func _build_animated_visual(host: Node2D, def: EnemyDef, frames: SpriteFrames) -> void:
	var s := def.body_scale
	sprite_h = 320.0 * s
	_make_shadow(host)
	anim = AnimatedSprite2D.new()
	anim.sprite_frames = frames
	anim.animation = "move"
	anim.centered = false
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.scale = Vector2(s, s)
	anim.position = Vector2(-320.0 * s, -372.0 * s)
	anim.play("move")
	host.add_child(anim)


func _make_shadow(host: Node2D) -> void:
	var shadow := Sprite2D.new()
	shadow.texture = SHADOW_TEX
	shadow.scale = Vector2(0.4, 0.15)
	shadow.modulate = Color(0.02, 0.02, 0.02, 0.45)
	host.add_child(shadow)


func _build_body_nodes(host: Node2D, def: EnemyDef) -> void:
	var shape := CircleShape2D.new()
	shape.radius = def.collision_radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0, -8)
	host.add_child(collision)

	# 受击判定：立绘是竖直画在脚底的，脚底那个小圆只覆盖小腿。
	# 单独加一个 Area2D 覆盖整个身体高度，射线（collide_with_areas）才能打中看到的部分。
	var hitbox := Area2D.new()
	hitbox.name = "Hitbox"
	hitbox.collision_layer = 2
	hitbox.collision_mask = 0
	hitbox.monitoring = false
	hitbox.input_pickable = false
	var hit_shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = shape.radius
	capsule.height = maxf(sprite_h * 0.78, 44.0)
	hit_shape.shape = capsule
	hit_shape.position = Vector2(0, -sprite_h * 0.45)
	hitbox.add_child(hit_shape)
	host.add_child(hitbox)

	bar_bg = Polygon2D.new()
	bar_bg.polygon = PackedVector2Array([
		Vector2(-22, -sprite_h - 12), Vector2(22, -sprite_h - 12),
		Vector2(22, -sprite_h - 6), Vector2(-22, -sprite_h - 6),
	])
	bar_bg.color = Color(0.08, 0.08, 0.09, 0.85)
	bar_bg.visible = false
	host.add_child(bar_bg)

	bar_fill = Polygon2D.new()
	bar_fill.color = Color(0.82, 0.26, 0.22)
	bar_fill.visible = false
	host.add_child(bar_fill)


## 头顶警觉图标：按帧播放，位置随敌人移动，初始隐藏。
func _build_alert_icon(host: Node2D) -> void:
	alert_icon = Sprite2D.new()
	alert_icon.texture = ALERT_ICON_SHEET
	alert_icon.hframes = ALERT_FRAMES
	alert_icon.vframes = 1
	alert_icon.frame = 0
	alert_icon.centered = true
	alert_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	alert_icon.scale = Vector2(ALERT_ICON_SCALE, ALERT_ICON_SCALE)
	alert_icon.position = Vector2(0.0, -sprite_h - ALERT_ICON_LIFT)
	alert_icon.z_index = 40
	alert_icon.visible = false
	host.add_child(alert_icon)


func show_alert_icon() -> void:
	if alert_icon == null:
		return
	alert_t = ALERT_LIFE
	alert_icon.visible = true
	alert_icon.frame = 0
	alert_icon.modulate = Color(1, 1, 1, 1)
	alert_icon.position = Vector2(0.0, -sprite_h - ALERT_ICON_LIFT)


func hide_alert_icon() -> void:
	if alert_icon != null:
		alert_icon.visible = false


func tick_alert_icon(delta: float) -> void:
	if alert_t <= 0.0 or alert_icon == null:
		return
	alert_t = maxf(alert_t - delta, 0.0)
	var elapsed := ALERT_LIFE - alert_t
	alert_icon.frame = int(elapsed * ALERT_FPS) % ALERT_FRAMES
	alert_icon.position.y = -sprite_h - ALERT_ICON_LIFT + sin(elapsed * 9.0) * 2.0
	# 尾段 0.28 秒淡出，避免图标突然消失。
	alert_icon.modulate.a = clampf(alert_t / 0.28, 0.0, 1.0)
	if alert_t <= 0.0:
		alert_icon.visible = false
		alert_icon.position.y = -sprite_h - ALERT_ICON_LIFT


func play_anim_override(anim_name: String, time: float) -> void:
	if anim == null:
		return
	anim_override = anim_name
	anim_override_t = maxf(anim_override_t, time)


func tick_flash(delta: float) -> void:
	hit_flash = maxf(hit_flash - delta, 0.0)


func tick_squash(host: Node2D, delta: float) -> void:
	if squash > 0.0:
		squash = maxf(squash - delta * 5.5, 0.0)
		var amount := squash * 0.16
		host.scale = Vector2(1.0 + amount, 1.0 - amount)
	elif host.scale != Vector2.ONE:
		host.scale = Vector2.ONE


## 更新朝向翻转、动画帧、受击闪白与头顶血条。
func update_visual(host: CharacterBody2D, def: EnemyDef, player: Node2D,
		hp: float, hp_max: float, dead: bool, explode_t: float, charge_t: float,
		delta: float) -> void:
	anim_override_t = maxf(anim_override_t - delta, 0.0)
	var facing_left: bool = player != null and player.global_position.x < host.global_position.x
	if anim != null:
		anim.flip_h = facing_left
		if explode_t >= 0.0:
			# 自爆倒计时：停在坐地帧，红圈负责倒计时，不循环爆炸帧。
			_set_anim("attack")
			if anim.is_playing():
				if anim.frame >= 1:
					anim.pause()
					anim.frame = 1
			else:
				anim.frame = 1
		else:
			var anim_name := "move"
			if anim_override_t > 0.0 and anim_override != "":
				anim_name = anim_override
			elif charge_t > 0.0:
				anim_name = "attack"
			_set_anim(anim_name)
			if anim_name != "move":
				if not anim.is_playing():
					anim.play(anim_name)
			elif host.velocity.length() > 1.0:
				if not anim.is_playing():
					anim.play("move")
			else:
				anim.pause()
		anim.modulate = _flash_color(def) if hit_flash > 0.0 else Color.WHITE
	elif sprite == null:
		return
	else:
		sprite.flip_h = facing_left
		if host.velocity.length() > 1.0:
			bob += delta * 9.0
			sprite.position.y = -sprite_h + absf(sin(bob)) * -2.0
		sprite.modulate = _flash_color(def) if hit_flash > 0.0 else Color.WHITE
	# 受伤后短暂显示血条（死亡后的引信阶段不再显示空血条）
	var show_bar := hp < hp_max - 0.5 and not dead
	bar_bg.visible = show_bar
	bar_fill.visible = show_bar
	if show_bar:
		var ratio := clampf(hp / hp_max, 0.0, 1.0)
		var left := -22.0
		var right := left + 44.0 * ratio
		bar_fill.polygon = PackedVector2Array([
			Vector2(left, -sprite_h - 11), Vector2(right, -sprite_h - 11),
			Vector2(right, -sprite_h - 7), Vector2(left, -sprite_h - 7),
		])


func _set_anim(anim_name: String) -> void:
	if anim == null or anim.animation == anim_name:
		return
	anim.play(anim_name)


## 受击闪白：金属偏冷白，血肉偏暖白，避免所有敌人都是一个颜色。
func _flash_color(def: EnemyDef) -> Color:
	if def.hit_material == "flesh":
		return Color(2.2, 1.75, 1.75)
	return Color(1.85, 2.05, 2.2)


## 绘制炮塔红色锁定激光与歌利亚自爆倒计时圆环（在宿主 _draw 中调用）。
func draw_overlays(host: CanvasItem, def: EnemyDef, player: Node2D,
		explode_t: float, laser_on: bool, laser_phase: float) -> void:
	if explode_t >= 0.0:
		_draw_blast_ring(host, def, explode_t)
	if not laser_on or player == null or not is_instance_valid(player):
		return
	var from := Vector2(0.0, -sprite_h * 0.62)
	var to: Vector2 = player.global_position - (host as Node2D).global_position + Vector2(0.0, -46.0)
	host.draw_line(from, to, Color(1.0, 0.04, 0.03, 0.06), 7.0)
	host.draw_line(from, to, Color(1.0, 0.10, 0.06, 0.22), 2.5)
	host.draw_line(from, to, Color(1.0, 0.30, 0.22, 0.55), 1.0)
	var pulse := 2.4 + 1.2 * sin(laser_phase * 22.0)
	host.draw_circle(to, pulse, Color(1.0, 0.12, 0.08, 0.45))
	host.draw_circle(from, 2.0, Color(1.0, 0.25, 0.18, 0.55))


## 哥利亚 2 秒倒计时：半透明红圈 + 从边缘向内填充的进度。
func _draw_blast_ring(host: CanvasItem, def: EnemyDef, explode_t: float) -> void:
	var total := maxf(def.explode_delay, 0.01)
	var radius := def.explode_radius * TILE
	var progress := clampf(1.0 - explode_t / total, 0.0, 1.0)
	var center := Vector2(0.0, -6.0)
	host.draw_circle(center, radius, Color(1.0, 0.08, 0.06, 0.10))
	host.draw_arc(center, radius, 0.0, TAU, 72, Color(1.0, 0.20, 0.12, 0.55), 2.0)
	var width := maxf(2.0, radius * progress)
	host.draw_arc(center, radius - width * 0.5, 0.0, TAU, 72,
		Color(1.0, 0.25, 0.16, 0.26), width)
	if progress > 0.98:
		host.draw_circle(center, radius, Color(1.0, 0.20, 0.12, 0.22))


## 近战挥击：朝玩家的弧形刀光，短暂淡出。
func spawn_melee_slash(host: Node2D, target: Vector2) -> void:
	var angle := (target - host.global_position).angle()
	var arc := Line2D.new()
	var points := PackedVector2Array()
	for i in 9:
		var a := angle - 0.65 + 1.3 * float(i) / 8.0
		points.append(Vector2.from_angle(a) * 30.0)
	arc.points = points
	arc.width = 5.0
	arc.default_color = Color(1.0, 0.42, 0.28, 0.92)
	arc.z_index = 60
	arc.position = Vector2(0, -sprite_h * 0.45)
	host.add_child(arc)
	var tw := host.create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.18)
	tw.tween_callback(arc.queue_free)


func spawn_attack_flash(host: Node2D, color: Color) -> void:
	var flash := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		points.append(Vector2(cos(a) * 9, sin(a) * 9))
	flash.polygon = points
	flash.color = color
	flash.position = Vector2(0, -sprite_h * 0.55)
	host.add_child(flash)
	var tween := host.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.14)
	tween.tween_callback(flash.queue_free)


func spawn_explosion_fx(host: Node2D, radius_px: float) -> void:
	var parent := host.get_parent()
	if parent == null:
		return
	var fx := Node2D.new()
	fx.global_position = host.global_position + Vector2(0, -18)
	fx.z_index = 80
	parent.add_child(fx)
	var points := PackedVector2Array()
	for i in 28:
		points.append(Vector2.from_angle(TAU * float(i) / 28.0) * 20.0)
	var blast := Polygon2D.new()
	blast.polygon = points
	blast.color = Color(1.0, 0.52, 0.16, 0.8)
	fx.add_child(blast)
	var core := Polygon2D.new()
	core.polygon = points
	core.color = Color(1.0, 0.92, 0.7, 0.95)
	core.scale = Vector2(0.45, 0.45)
	fx.add_child(core)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2.ONE * (radius_px / 20.0), 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(blast, "modulate:a", 0.0, 0.36)
	tw.tween_property(core, "scale", Vector2.ONE * (radius_px / 20.0) * 0.6, 0.2)
	tw.tween_property(core, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(fx.queue_free)
	for i in 8:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(10.0, radius_px * 0.8)
		Shot2D.impact(parent, host.global_position + offset + Vector2(0, -20),
			Color(1.0, 0.55, 0.2))


## 死亡动画与节点回收；自爆单位在爆炸后播死亡帧。
func finish_death_visual(host: Node2D, def: EnemyDef, exploded: bool, play_sfx_fn: Callable) -> void:
	if anim != null:
		if (not exploded or not def.death_explode) and play_sfx_fn.is_valid():
			play_sfx_fn.call("enemy_death", -9.0, randf_range(0.95, 1.05))
		anim.play("death")
		var anim_tween := host.create_tween()
		anim_tween.tween_interval(0.5)
		anim_tween.tween_property(anim, "modulate:a", 0.0, 0.2)
		anim_tween.tween_callback(host.queue_free)
		return
	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_property(sprite, "scale", Vector2(sprite.scale.x * 0.8, 0.05), 0.3)
	tween.chain().tween_callback(host.queue_free)
