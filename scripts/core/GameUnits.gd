extends RefCounted
class_name GameUnits

## 2D 世界单位常量单一来源（阶段 1 前半段：仅收口定义，保持现有两套换算不变）。
##
## 已知历史设计债（未经明确拍板前禁止改动数值，避免联动影响地图/视野/射程/弹速）：
##   1. 地图格、寻路、敌人感知与视野迷雾使用 1 格 = 1 米 = 64 px（TILE / VISION_PIXELS_PER_METER）。
##   2. 武器射程、枪长、弹速与角色身高使用 128 px ≈ 1.7 米 → 75.294 px/m（WORLD_PER_METER）。

## 地图单格像素尺寸（Level2D / Enemy2D / VisionFog2D / HearingIndicator2D / Main2D）。
const TILE := 64.0
## 角色在 2D 世界中的逻辑身高（像素，约等于 2 格 / 1.7 m）。
const DOLL_WORLD_HEIGHT_PX := 128.0
## 角色参考真实身高（米）。
const DOLL_REFERENCE_HEIGHT_M := 1.7
## 武器射程、枪长、弹速换算标尺：像素 / 米（≈ 75.2941）。
const WORLD_PER_METER := DOLL_WORLD_HEIGHT_PX / DOLL_REFERENCE_HEIGHT_M
## 视野迷雾、敌人感知与声纹换算标尺：像素 / 米（当前按 1 格 = 1 米 = 64 px）。
const VISION_PIXELS_PER_METER := TILE


## 武器/弹道系统的米 -> 像素换算（使用 WORLD_PER_METER）。
static func weapon_meters_to_px(meters: float) -> float:
	return meters * WORLD_PER_METER


## 武器/弹道系统的像素 -> 米换算（使用 WORLD_PER_METER）。
static func px_to_weapon_meters(px: float) -> float:
	return px / WORLD_PER_METER


## 视野/感知/声纹系统的米 -> 像素换算（使用 VISION_PIXELS_PER_METER）。
static func vision_meters_to_px(meters: float) -> float:
	return meters * VISION_PIXELS_PER_METER


## 视野/感知/声纹系统的像素 -> 米换算（使用 VISION_PIXELS_PER_METER）。
static func px_to_vision_meters(px: float) -> float:
	return px / VISION_PIXELS_PER_METER
