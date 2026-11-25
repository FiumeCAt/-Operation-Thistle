extends Resource
class_name CombatFeelConfig
## 2D 战斗后坐力、镜头抖动与受击反馈可调配置资源（挂载于 Main2D.tscn 根节点）。
## 玩家设置里的震屏开关、震动倍率滑杆与顿帧开关仍在运行时动态叠加，不在此固化。

@export_group("Recoil")
## 准心后坐偏移封顶参考向量（兼容基础常量，实际单枪封顶来自 WeaponData）。
@export var recoil_limit := Vector2(52.0, 78.0)
## 停火后准心后坐回落速度（px/秒）。
@export_range(10.0, 300.0, 1.0) var recoil_recover := 95.0
## 开镜（ADS）状态下的后坐力倍率。
@export_range(0.10, 1.00, 0.05) var recoil_ads_mul := 0.55
## 连续开火随累积后坐放大的额外增益。
@export_range(0.0, 2.0, 0.05) var recoil_build_gain := 0.55
## 准心后坐向镜头位移映射的比例与封顶（px）。
@export_range(0.0, 2.0, 0.05) var recoil_cam_scale := 0.95
@export_range(0.0, 80.0, 1.0) var recoil_cam_limit := 26.0
@export_range(10.0, 240.0, 1.0) var recoil_cam_recover := 70.0
## 水平后坐向镜头微小翻滚映射的比例、封顶（弧度）与回正速率。
@export_range(0.0, 0.01, 0.0001) var recoil_roll_scale := 0.0016
@export_range(0.0, 0.15, 0.002) var recoil_roll_limit := 0.028
@export_range(0.02, 1.0, 0.01) var recoil_roll_recover := 0.16

@export_group("Shake & Feedback")
## 震动幅度设置 100% 对应的基准换算系数。
@export_range(0.5, 15.0, 0.1) var shake_scale_base := 5.0
## 命中/击杀顿帧时的时间缩放倍率。
@export_range(0.02, 0.50, 0.01) var hitstop_time_scale := 0.12
## 玩家掉血红屏颜色（alpha 由本次扣血动态计算）与淡出时长。
@export var hurt_flash_color := Color(0.72, 0.04, 0.04, 1.0)
@export_range(0.05, 1.5, 0.02) var hurt_flash_fade_sec := 0.34
## 玩家真实掉血时的基准震屏强度、旋转角度与衰减速度。
@export_range(0.0, 10.0, 0.1) var hurt_shake_amount := 2.2
@export_range(0.0, 2.0, 0.05) var hurt_shake_roll_deg := 0.3
@export_range(4.0, 80.0, 1.0) var hurt_shake_decay := 24.0
