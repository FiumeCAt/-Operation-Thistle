extends Resource
class_name VisionLightingConfig
## 分层视野光照强度与配色可调配置资源（挂载于 Main2D.tscn 根节点）。
## 迷雾基础环境色由场景节点 World2D/CanvasModulate.color 直接控制；瞄具视野倍率在运行时动态叠加。

@export_group("Vision Light Energy")
## 主清晰视野锥亮度、余光层相对比例、近身黑暗视野亮度与角色贴身补光亮度。
@export_range(0.0, 2.0, 0.02) var clear_energy := 0.60
@export_range(0.0, 1.0, 0.02) var ring_dim := 0.40
@export_range(0.0, 1.5, 0.02) var dark_energy := 0.18
@export_range(0.0, 1.5, 0.02) var self_energy := 0.18
## 相对暗外圈内敌人的可见不透明度。
@export_range(0.1, 1.0, 0.05) var ring_enemy_alpha := 0.80

@export_group("Vision Light Color")
@export var light_color := Color(1.0, 0.97, 0.92, 1.0)
@export var dark_color := Color(0.72, 0.82, 1.0, 1.0)
@export var self_color := Color(1.0, 0.95, 0.88, 1.0)
