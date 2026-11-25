extends Resource
class_name CameraFeelConfig
## 2D 镜头手感与瞄准前探可调配置资源（挂载于 Main2D.tscn 根节点）。
## 仅包含固定调优参数；关卡边界 limit_* 与玩家设置中的实时视角缩放档位保持运行时动态计算。

@export_group("Base & Zoom")
## 镜头向上抬升像素，使角色略偏屏下、前方视野更大。
@export_range(0.0, 160.0, 1.0) var camera_lift := 44.0
## 玩家 Alt+滚轮整体视角缩放范围（百分比）。
@export_range(10.0, 100.0, 5.0) var view_zoom_min := 20.0
@export_range(100.0, 300.0, 5.0) var view_zoom_max := 200.0
@export_range(1.0, 50.0, 1.0) var view_zoom_step := 10.0
## 滚轮缩放插值追赶速率（%/秒）。
@export_range(20.0, 800.0, 10.0) var view_zoom_lerp := 260.0

@export_group("ADS & Look-Ahead")
## 开镜过渡基础速度（受武器下挂激光与调试倍率调制）。
@export_range(1.0, 20.0, 0.2) var ads_zoom_speed := 6.0
## 基础前探距离（px，64 px = 1m）；红点/全息/高倍镜按 look_ahead_mul 叠加。
@export_range(0.0, 900.0, 10.0) var ads_look_ahead := 340.0
## 非高倍镜前探方向平滑速度。
@export_range(1.0, 30.0, 0.5) var ads_look_smooth := 10.0
## 高倍镜前探允许的最大半屏偏移比例（保证角色始终留在屏内）。
@export_range(0.30, 0.98, 0.01) var scope_keep_player_ratio_x := 0.88
@export_range(0.30, 0.98, 0.01) var scope_keep_player_ratio_y := 0.82
## 高倍镜主镜头拉远区间：2× 对应 min_mag，8× 对应 max_mag。
@export_range(0.40, 1.00, 0.01) var scope_zoom_out_min_mag := 0.85
@export_range(0.30, 0.95, 0.01) var scope_zoom_out_max_mag := 0.62
## 方案 B 增量外推防抖死区（像素）与平滑速率。
@export_range(0.0, 32.0, 0.5) var scope_deadzone_px := 6.0
@export_range(1.0, 30.0, 0.5) var scope_look_smooth := 10.0
