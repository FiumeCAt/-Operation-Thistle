extends SceneTree
## 2D 单位统一回归测试（GameUnits）：
## 1. 验证全游戏世界距离统一为 1 格 = 1 米 = 64 px（PIXELS_PER_METER == TILE == WORLD_PER_METER）。
## 2. 验证枪械贴图视觉缩放独立为 SPRITE_PX_PER_METER（128 / 1.7），不与世界距离混用。
## 3. 验证 Main2D / Level2D / Enemy2D / VisionFog2D / HearingIndicator2D / WeaponRig2D / Doll2D
##    全部引用 GameUnits 单一来源且语义一致。

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

	# 1. 统一世界距离标尺：1 格 = 1 米 = 64 px
	_check(is_equal_approx(UNITS.TILE, 64.0), "GameUnits.TILE == 64.0")
	_check(is_equal_approx(UNITS.PIXELS_PER_METER, 64.0), "GameUnits.PIXELS_PER_METER == 64.0")
	_check(
		is_equal_approx(UNITS.WORLD_PER_METER, UNITS.PIXELS_PER_METER),
		"GameUnits.WORLD_PER_METER unified to PIXELS_PER_METER (64.0)"
	)
	_check(
		is_equal_approx(UNITS.VISION_PIXELS_PER_METER, UNITS.PIXELS_PER_METER),
		"GameUnits.VISION_PIXELS_PER_METER unified to PIXELS_PER_METER (64.0)"
	)

	# 2. 枪械贴图视觉缩放与世界距离解耦
	_check(is_equal_approx(UNITS.DOLL_WORLD_HEIGHT_PX, 128.0), "GameUnits.DOLL_WORLD_HEIGHT_PX == 128.0")
	_check(is_equal_approx(UNITS.DOLL_REFERENCE_HEIGHT_M, 1.7), "GameUnits.DOLL_REFERENCE_HEIGHT_M == 1.7")
	_check(
		is_equal_approx(UNITS.SPRITE_PX_PER_METER, 128.0 / 1.7),
		"GameUnits.SPRITE_PX_PER_METER == 128.0 / 1.7 (%.4f, visual only)" % UNITS.SPRITE_PX_PER_METER
	)

	# 3. 统一换算函数往返一致性（武器与视野同标尺）
	var dist_px := UNITS.meters_to_px(40.0)
	_check(is_equal_approx(dist_px, 2560.0), "meters_to_px(40m) == 2560.0 px")
	_check(is_equal_approx(UNITS.px_to_meters(dist_px), 40.0), "px_to_meters round-trip == 40.0")
	_check(
		is_equal_approx(UNITS.weapon_meters_to_px(34.0), UNITS.vision_meters_to_px(34.0)),
		"weapon meters and vision meters are identical (34m == %.0f px)" % UNITS.weapon_meters_to_px(34.0)
	)
	_check(is_equal_approx(UNITS.px_to_weapon_meters(2176.0), 34.0), "px_to_weapon_meters(2176px) == 34.0m")
	_check(is_equal_approx(UNITS.px_to_vision_meters(2560.0), 40.0), "px_to_vision_meters(2560px) == 40.0m")

	# 4. 跨脚本常量全部指向同一来源且一致
	_check(is_equal_approx(MAIN_2D.TILE, UNITS.TILE), "Main2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(LEVEL_2D.TILE, UNITS.TILE), "Level2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(ENEMY_2D.TILE, UNITS.TILE), "Enemy2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(VISION_FOG_2D.TILE, UNITS.TILE), "VisionFog2D.TILE matches GameUnits.TILE")
	_check(is_equal_approx(HEARING_2D.TILE, UNITS.TILE), "HearingIndicator2D.TILE matches GameUnits.TILE")
	_check(
		is_equal_approx(MAIN_2D.WORLD_PER_METER, UNITS.PIXELS_PER_METER),
		"Main2D.WORLD_PER_METER == 64.0 px/m"
	)
	_check(
		is_equal_approx(VISION_FOG_2D.PIXELS_PER_METER, UNITS.PIXELS_PER_METER),
		"VisionFog2D.PIXELS_PER_METER == 64.0 px/m"
	)
	_check(
		is_equal_approx(MAIN_2D.WORLD_PER_METER, VISION_FOG_2D.PIXELS_PER_METER),
		"Main2D and VisionFog2D share exact same pixels-per-meter"
	)
	_check(
		is_equal_approx(WEAPON_RIG_2D.SPRITE_PX_PER_METER, UNITS.SPRITE_PX_PER_METER),
		"WeaponRig2D uses visual-only SPRITE_PX_PER_METER"
	)
	_check(
		is_equal_approx(DOLL_2D.WORLD_BODY, UNITS.DOLL_WORLD_HEIGHT_PX),
		"Doll2D.WORLD_BODY matches GameUnits.DOLL_WORLD_HEIGHT_PX"
	)

	# 5. 跨系统语义核对（40m 视野 == 40 格 == 2560px；13.5m 声纹 == 13.5 格 == 864px）
	_check(
		is_equal_approx(VISION_FOG_2D.CLEAR_RANGE_METERS * VISION_FOG_2D.PIXELS_PER_METER, 2560.0),
		"VisionFog2D clear range == 2560 px (40m * 64)"
	)
	_check(
		is_equal_approx(HEARING_2D.HEARING_METERS * HEARING_2D.TILE, 864.0),
		"HearingIndicator2D hearing range == 864 px (13.5m * 64)"
	)

	print("=== game_units_test: %d ok / %d fail ===" % [_ok, _fails])
	quit(0 if _fails == 0 else 1)
