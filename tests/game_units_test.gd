extends SceneTree
## 2D 单位常量单一来源回归测试（GameUnits）：
## 1. 验证 GameUnits 常量数值与换算函数精确保持现状（阶段 1 前半段零数值改动）。
## 2. 验证 Main2D / Level2D / Enemy2D / VisionFog2D / HearingIndicator2D / WeaponRig2D / Doll2D
##    的单位常量全部与 GameUnits 单一来源一致。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const MAIN_2D := preload("res://scripts/core/Main2D.gd")
const LEVEL_2D := preload("res://scripts/level/Level2D.gd")
const ENEMY_2D := preload("res://scripts/actors/Enemy2D.gd")
const VISION_FOG_2D := preload("res://scripts/fx/VisionFog2D.gd")
const HEARING_2D := preload("res://scripts/fx/HearingIndicator2D.gd")
const WEAPON_RIG_2D := preload("res://scripts/weapons/WeaponRig2D.gd")
const DOLL_2D := preload("res://scripts/actors/Doll2D.gd")

var _ok := 0
var _fails := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] ", msg)
	else:
		_fails += 1
		push_error("  [FAIL] " + msg)


func _run() -> void:
	print("=== game_units_test ===")

	# 1. 基础常量精确值（锁定现状两套换算不被意外改动）
	_check(is_equal_approx(UNITS.TILE, 64.0), "GameUnits.TILE == 64.0")
	_check(is_equal_approx(UNITS.DOLL_WORLD_HEIGHT_PX, 128.0), "GameUnits.DOLL_WORLD_HEIGHT_PX == 128.0")
	_check(is_equal_approx(UNITS.DOLL_REFERENCE_HEIGHT_M, 1.7), "GameUnits.DOLL_REFERENCE_HEIGHT_M == 1.7")
	_check(
		is_equal_approx(UNITS.WORLD_PER_METER, 128.0 / 1.7),
		"GameUnits.WORLD_PER_METER == 128.0 / 1.7 (%.4f)" % UNITS.WORLD_PER_METER
	)
	_check(
		is_equal_approx(UNITS.VISION_PIXELS_PER_METER, UNITS.TILE),
		"GameUnits.VISION_PIXELS_PER_METER == TILE (64.0)"
	)

	# 2. 换算辅助函数往返一致性
	var weapon_px := UNITS.weapon_meters_to_px(34.0)
	_check(is_equal_approx(weapon_px, 34.0 * (128.0 / 1.7)), "weapon_meters_to_px(34m) matches WORLD_PER_METER")
	_check(is_equal_approx(UNITS.px_to_weapon_meters(weapon_px), 34.0), "px_to_weapon_meters round-trip == 34.0")

	var vision_px := UNITS.vision_meters_to_px(40.0)
	_check(is_equal_approx(vision_px, 2560.0), "vision_meters_to_px(40m) == 2560.0 px")
	_check(is_equal_approx(UNITS.px_to_vision_meters(vision_px), 40.0), "px_to_vision_meters round-trip == 40.0")

	# 3. 跨脚本常量与单一来源完全一致
	_check(is_equal_approx(MAIN_2D.TILE, UNITS.TILE), "Main2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(LEVEL_2D.TILE, UNITS.TILE), "Level2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(ENEMY_2D.TILE, UNITS.TILE), "Enemy2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(VISION_FOG_2D.TILE, UNITS.TILE), "VisionFog2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(HEARING_2D.TILE, UNITS.TILE), "HearingIndicator2D.TILE matches GameUnits.TILE")
	_check(
		is_equal_approx(VISION_FOG_2D.PIXELS_PER_METER, UNITS.VISION_PIXELS_PER_METER),
		"VisionFog2D.PIXELS_PER_METER matches GameUnits.VISION_PIXELS_PER_METER"
	)
	_check(
		is_equal_approx(MAIN_2D.WORLD_PER_METER, UNITS.WORLD_PER_METER),
		"Main2D.WORLD_PER_METER matches GameUnits.WORLD_PER_METER"
	)
	_check(
		is_equal_approx(WEAPON_RIG_2D.WORLD_PER_METER, UNITS.WORLD_PER_METER),
		"WeaponRig2D.WORLD_PER_METER matches GameUnits.WORLD_PER_METER"
	)
	_check(
		is_equal_approx(DOLL_2D.WORLD_BODY, UNITS.DOLL_WORLD_HEIGHT_PX),
		"Doll2D.WORLD_BODY matches GameUnits.DOLL_WORLD_HEIGHT_PX"
	)

	# 4. 关键跨系统语义核对（锁定 40m 视野 = 2560px，声纹 10m = 640px）
	_check(
		is_equal_approx(VISION_FOG_2D.CLEAR_RANGE_METERS * VISION_FOG_2D.PIXELS_PER_METER, 2560.0),
		"VisionFog2D clear range == 2560 px (40m * 64)"
	)
	_check(
		is_equal_approx(HEARING_2D.HEARING_METERS * HEARING_2D.TILE, 640.0),
		"HearingIndicator2D hearing range == 640 px (10m * 64)"
	)

	print("=== game_units_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
