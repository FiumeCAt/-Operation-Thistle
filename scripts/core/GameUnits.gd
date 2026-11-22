extends RefCounted
class_name GameUnits

## 2D 世界单位常量单一来源（全项目统一 1 格 = 1 米 = 64 px）。
##
## 标尺分工：
##   1. 世界距离（地图、寻路、视野迷雾、敌人感知/移速/射程/自爆、声纹、玩家武器射程/弹速/衰减）：
##      全部统一使用 PIXELS_PER_METER = TILE = 64.0 px/m。
##   2. 武器贴图视觉缩放（仅用于 WeaponRig2D 将枪身贴图按默认角色 128 px 参考身高匹配手部握持比例）：
##      独立为 SPRITE_PX_PER_METER = 128.0 / 1.7 ≈ 75.294 px/m，与世界距离解耦，
##      确保未来加入不同身高的新角色时，世界距离与地图米制不受任何影响。

## 地图单格像素尺寸（1 格 = 1 米）。
const TILE := 64.0
## 全游戏统一世界距离标尺：像素 / 米（1 m = 1 格 = 64 px）。
const PIXELS_PER_METER := TILE
## 兼容别名：武器射程与弹道系统已统一为 PIXELS_PER_METER（64 px/m）。
const WORLD_PER_METER := PIXELS_PER_METER
## 兼容别名：视野迷雾、敌人感知与声纹系统统一为 PIXELS_PER_METER（64 px/m）。
const VISION_PIXELS_PER_METER := PIXELS_PER_METER

## 默认参考角色在 2D 世界中的逻辑贴图高度（像素，2 格）。
const DOLL_WORLD_HEIGHT_PX := 128.0
## 默认参考角色身高（米），仅用于枪械贴图视觉缩放。
const DOLL_REFERENCE_HEIGHT_M := 1.7
## 枪械贴图视觉缩放标尺（仅美术表现用，严禁参与世界距离/射程/弹速/视野计算）。
const SPRITE_PX_PER_METER := DOLL_WORLD_HEIGHT_PX / DOLL_REFERENCE_HEIGHT_M


## 统一世界距离：米 -> 像素（64 px/m）。
static func meters_to_px(meters: float) -> float:
	return meters * PIXELS_PER_METER


## 统一世界距离：像素 -> 米（64 px/m）。
static func px_to_meters(px: float) -> float:
	return px / PIXELS_PER_METER


## 兼容接口：武器/弹道系统米 -> 像素（已统一为 64 px/m）。
static func weapon_meters_to_px(meters: float) -> float:
	return meters_to_px(meters)


## 兼容接口：武器/弹道系统像素 -> 米（已统一为 64 px/m）。
static func px_to_weapon_meters(px: float) -> float:
	return px_to_meters(px)


## 兼容接口：视野/感知/声纹系统米 -> 像素（已统一为 64 px/m）。
static func vision_meters_to_px(meters: float) -> float:
	return meters_to_px(meters)


## 兼容接口：视野/感知/声纹系统像素 -> 米（已统一为 64 px/m）。
static func px_to_vision_meters(px: float) -> float:
	return px_to_meters(px)
