extends Resource
class_name DollConfig
## 主角 Doll2D 固定调优配置资源（挂载于 Doll2D.tscn 根节点）。
## 仅包含基础动作/受击/背枪表现参数；关卡出生点、活动边界 bounds、最终血量/护甲/移速加成由运行时动态写入。

@export_group("Movement & Animation")
## 右键瞄准时的移速倍率。
@export_range(0.15, 1.0, 0.05) var ads_speed_mul := 0.5
## 行走与奔跑图集基准帧率。
@export_range(2.0, 30.0, 0.2) var walk_fps := 10.4
@export_range(2.0, 30.0, 0.2) var run_fps := 14.8
## 4 帧脚步起伏下沉量（像素，正值向下踩实）。
@export var step_bob_px := PackedFloat32Array([1.2, 0.0, 1.2, 0.0])

@export_group("Combat Feedback & Stowed Weapon")
## 受击后短暂无敌时长与闪白持续时长（秒）。
@export_range(0.0, 1.0, 0.01) var hurt_invuln_sec := 0.12
@export_range(0.0, 1.0, 0.01) var hurt_flash_sec := 0.16
@export var hurt_flash_tint := Color(2.1, 0.62, 0.58, 1.0)
## 开火时身体后坐一顿的像素距离与恢复速度。
@export_range(0.0, 10.0, 0.1) var fire_flinch_px := 2.2
@export_range(5.0, 120.0, 1.0) var flinch_recover_speed := 40.0
## 收枪后武器挂在背后的倾角（弧度）、偏移与压暗染色。
@export_range(-3.14, 3.14, 0.02) var stow_rotation := -0.62
@export var stow_offset := Vector2(0.0, 2.0)
@export var stow_tint := Color(0.78, 0.82, 0.90, 1.0)

@export_group("Head Tracking")
## 独立头部随瞄准微摆开关（关闭避免像素脖颈接缝）。
@export var head_motion_enabled := false
@export_range(0.0, 0.6, 0.01) var head_max_tilt := 0.18
@export_range(1.0, 30.0, 0.5) var head_tilt_speed := 9.0
@export_range(0.0, 0.05, 0.001) var head_max_shift := 0.010

@export_group("Dodge / Tactical Evasion")
## 翻滚位移总距离（米，1m = 64px）。
@export_range(1.0, 6.0, 0.1) var dodge_distance_m := 3.2
## 翻滚持续时间（秒）。
@export_range(0.15, 0.80, 0.02) var dodge_duration := 0.30
## 翻滚起始无敌帧时长（秒，自动钳制不超过 dodge_duration）。
@export_range(0.0, 0.50, 0.01) var dodge_iframe_sec := 0.20
## 翻滚总冷却时间（秒，从起滚瞬间计时）。
@export_range(0.35, 4.0, 0.05) var dodge_cooldown := 1.15
## 翻滚残影生成间隔（秒）。
@export_range(0.03, 0.20, 0.005) var dodge_afterimage_interval := 0.065
