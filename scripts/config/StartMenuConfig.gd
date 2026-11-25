extends Resource
class_name StartMenuConfig
## 主菜单固定视觉表现与背景轮播配置资源（挂载于 StartMenu2D.tscn 根节点）。
## 玩家可切换的 UI 主题配色、音量与作战档案数据保持由 Progress 存档动态驱动。

@export_group("Background Carousel")
## 单张背景图停留时长与交叉淡入过渡时长（秒）。
@export_range(1.0, 60.0, 0.5) var bg_hold_seconds := 8.5
@export_range(0.1, 10.0, 0.1) var bg_fade_seconds := 1.8
## 背景底层兜底纯色。
@export var base_bg_color := Color(0.008, 0.011, 0.016, 1.0)
## 轮播背景图路径列表与对应场景角标文案。
@export var slide_paths := PackedStringArray([
	"res://assets/art/ui/menu_bg/bg_01_hangar.png",
	"res://assets/art/ui/menu_bg/bg_02_airlock.png",
	"res://assets/art/ui/menu_bg/bg_03_outpost.png",
])
@export var slide_labels := PackedStringArray([
	"01 K-17 整备库",
	"02 隔离闸门",
	"03 雨夜哨站",
])

@export_group("Vignette & Readability Mask")
## 左右与上下柔和暗渐变蒙版比例及最大不透明度（保证前景 UI 高可读且中央留白通透）。
@export_range(0.0, 0.7, 0.01) var left_mask_width_ratio := 0.42
@export_range(0.0, 1.0, 0.02) var left_mask_alpha := 0.72
@export_range(0.0, 0.7, 0.01) var right_mask_width_ratio := 0.34
@export_range(0.0, 1.0, 0.02) var right_mask_alpha := 0.56
@export_range(0.0, 0.4, 0.01) var top_vignette_ratio := 0.14
@export_range(0.0, 1.0, 0.02) var top_vignette_alpha := 0.42
@export_range(0.0, 0.4, 0.01) var bottom_vignette_ratio := 0.16
@export_range(0.0, 1.0, 0.02) var bottom_vignette_alpha := 0.54
@export var mask_tint := Color(0.008, 0.011, 0.016, 1.0)

@export_group("Scanline & Tactical Frame")
@export_range(0.0, 0.15, 0.002) var scanline_alpha := 0.012
@export_range(2.0, 16.0, 1.0) var scanline_step_px := 5.0
@export_range(0.0, 0.5, 0.005) var sweep_speed := 0.045
@export_range(0.0, 0.3, 0.01) var sweep_alpha := 0.05
@export_range(0.0, 1.0, 0.02) var corner_bracket_alpha := 0.42
@export_range(4.0, 64.0, 1.0) var corner_margin := 18.0
@export_range(12.0, 140.0, 2.0) var corner_length := 56.0
