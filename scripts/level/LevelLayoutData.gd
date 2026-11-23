extends RefCounted
class_name LevelLayoutData
## K-17 工业巨构与歌利亚竞技场静态地图布局数据（纯数据与格子几何函数，无节点依赖）。
## 从 Level2D 抽离，作为地图、小地图、部署页与墙体生成的单一数据源。

const UNITS := preload("res://scripts/core/GameUnits.gd")
const TILE := UNITS.TILE
const MAP_W := 176
const MAP_H := 116
const DOOR_W := 3.0
## 大厅中央巨型压铸机的中心格；刷怪与陈设都要绕开。
const HALL_MACHINE_CELL := Vector2(93.0, 54.0)
## 歌利亚狂潮：只有地板的矩形竞技场（格）。
const ARENA_W := 100
const ARENA_H := 60

## 走廊矩形（格）。房间矩形统一从 ROOM_DEFS 读取，避免两处抄写出错。
## 走廊之间只做边贴边，不重叠，避免贴图 UV 接缝。
const FLOOR_RECTS: Array[Rect2i] = [
	Rect2i(36, 14, 6, 92),    # 西主廊（物流脊）
	Rect2i(42, 33, 94, 6),    # 北主廊
	Rect2i(42, 69, 94, 6),    # 南主廊
	Rect2i(136, 33, 6, 64),   # 东主廊（货运）
	Rect2i(42, 90, 94, 4),    # 南二廊（窄服务廊）
	Rect2i(42, 51, 24, 8),    # 西侧大厅门厅
	Rect2i(120, 52, 16, 6),   # 东侧大厅闸口
]

## 房间顺序：0 装卸 / 1 仓库 / 2 医疗 / 3 军械 / 4 数据仓 /
## 5 控制 / 6 巢穴 / 7 维修 / 8 废弃仓 / 9 东侧撤离 / 10 南侧撤离 /
## 11 精炼 / 12 铸造 / 13 变电站 / 14 质检 / 15 更衣 / 16 通风 / 17 休息 / 18 食堂 / 19 主装配大厅。
## extra_doors 让部分房间变成穿堂，形成夹击路线而不是单门对峙。
const ROOM_DEFS: Array[Dictionary] = [
	{"type": &"insertion", "name": "装卸区", "rect": Rect2i(8, 40, 27, 24),
		"door_cell": Vector2i(35, 51), "vertical": true, "props": 5, "roster": []},
	{"type": &"storage", "name": "仓库区", "rect": Rect2i(10, 14, 25, 18),
		"door_cell": Vector2i(35, 22), "vertical": true, "props": 5,
		"roster": [&"rifleman", &"rusher", &"mobile_turret"]},
	{"type": &"medical", "name": "医疗站", "rect": Rect2i(10, 70, 25, 20),
		"door_cell": Vector2i(35, 79), "vertical": true, "props": 4,
		"roster": [&"rifleman", &"rusher", &"sentry_type1"]},
	{"type": &"armory", "name": "军械库", "rect": Rect2i(43, 60, 22, 8),
		"door_cell": Vector2i(65, 63), "vertical": true, "props": 3,
		"roster": [&"mobile_turret", &"heavy", &"rifleman"]},
	{"type": &"aux", "name": "数据仓", "rect": Rect2i(43, 40, 22, 10),
		"door_cell": Vector2i(65, 44), "vertical": true, "props": 3,
		"roster": [&"rusher", &"sentry_type1", &"rifleman"]},
	{"type": &"control", "name": "控制室", "rect": Rect2i(44, 95, 26, 12),
		"door_cell": Vector2i(57, 94), "vertical": false, "props": 5,
		"roster": [&"mobile_turret", &"rusher", &"hunter_type1", &"rifleman"]},
	{"type": &"nest", "name": "巢穴", "rect": Rect2i(73, 95, 24, 12),
		"door_cell": Vector2i(84, 94), "vertical": false, "props": 5,
		"roster": [&"hunter_type1", &"goliath", &"rusher", &"heavy", &"rifleman"]},
	{"type": &"workshop", "name": "维修间", "rect": Rect2i(44, 76, 22, 13),
		"door_cell": Vector2i(54, 75), "vertical": false,
		"extra_doors": [{"cell": Vector2i(54, 89), "vertical": false}], "props": 4,
		"roster": [&"sentry_type1", &"mobile_turret", &"rusher"]},
	{"type": &"abandoned", "name": "废弃仓", "rect": Rect2i(10, 93, 25, 17),
		"door_cell": Vector2i(35, 101), "vertical": true, "props": 4,
		"roster": [&"goliath", &"rusher", &"rifleman"]},
	{"type": &"extraction", "name": "撤离区", "rect": Rect2i(143, 80, 22, 16),
		"door_cell": Vector2i(142, 87), "vertical": true, "props": 3, "roster": []},
	{"type": &"extraction", "name": "南侧撤离区", "rect": Rect2i(100, 95, 22, 14),
		"door_cell": Vector2i(110, 94), "vertical": false, "props": 3, "roster": []},
	{"type": &"refinery", "name": "精炼车间", "rect": Rect2i(44, 12, 27, 20),
		"door_cell": Vector2i(57, 32), "vertical": false,
		"extra_doors": [{"cell": Vector2i(71, 21), "vertical": true}], "props": 5,
		"roster": [&"rusher", &"rifleman", &"sentry_type1"]},
	{"type": &"foundry", "name": "铸造车间", "rect": Rect2i(72, 10, 30, 22),
		"door_cell": Vector2i(87, 32), "vertical": false, "props": 5,
		"roster": [&"heavy", &"rusher", &"mobile_turret"]},
	{"type": &"substation", "name": "变电站", "rect": Rect2i(104, 14, 23, 18),
		"door_cell": Vector2i(114, 32), "vertical": false,
		"extra_doors": [{"cell": Vector2i(127, 24), "vertical": true}], "props": 4,
		"roster": [&"sentry_type1", &"rifleman"]},
	{"type": &"qc", "name": "质检室", "rect": Rect2i(128, 18, 20, 14),
		"door_cell": Vector2i(137, 32), "vertical": false, "props": 4,
		"roster": [&"rusher", &"rifleman"]},
	{"type": &"locker", "name": "更衣室", "rect": Rect2i(68, 76, 18, 13),
		"door_cell": Vector2i(76, 75), "vertical": false, "props": 3,
		"roster": [&"rusher", &"rifleman"]},
	{"type": &"vent", "name": "通风机房", "rect": Rect2i(143, 64, 22, 13),
		"door_cell": Vector2i(142, 70), "vertical": true, "props": 4,
		"roster": [&"sentry_type1", &"rusher"]},
	{"type": &"break_room", "name": "休息区", "rect": Rect2i(88, 76, 24, 13),
		"door_cell": Vector2i(99, 75), "vertical": false, "props": 4,
		"roster": [&"rifleman", &"rusher"]},
	{"type": &"canteen", "name": "食堂", "rect": Rect2i(113, 76, 22, 13),
		"door_cell": Vector2i(124, 75), "vertical": false,
		"extra_doors": [{"cell": Vector2i(112, 82), "vertical": true}], "props": 4,
		"roster": [&"rusher", &"rifleman", &"mobile_turret"]},
	{"type": &"hall", "name": "主装配大厅", "rect": Rect2i(66, 40, 54, 28),
		"door_cell": Vector2i(92, 39), "vertical": false,
		"extra_doors": [{"cell": Vector2i(92, 68), "vertical": false}], "props": 8,
		"roster": [&"hunter_type1", &"mobile_turret", &"rifleman", &"rusher",
			&"goliath", &"sentry_type1", &"heavy", &"rifleman"]},
]

## 初始解锁的两个出生点：各自带默认撤离点与安全区（附近房间不刷怪）。
const SPAWNS := {
	&"insertion": {
		"name": "装卸区", "pos": Vector2(14.0, 51.0), "default_exit": &"east",
		"safe_rooms": [0, 1], "route": "西侧装卸区 → 西主廊 → 主装配大厅",
	},
	&"abandoned": {
		"name": "废弃仓", "pos": Vector2(16.0, 104.0), "default_exit": &"south",
		"safe_rooms": [8, 2], "route": "西南废弃仓 → 医疗站 → 南主廊",
	},
}

## 初始解锁的两个撤离点；货运电梯是恢复供电后的额外撤离线。
const EXTRACTS := {
	&"east": {"name": "东侧闸门", "pos": Vector2(157.0, 87.0), "room": 9},
	&"south": {"name": "南侧维修门", "pos": Vector2(110.0, 104.0), "room": 10},
}

## 环廊巡逻点：把战斗拉到门厅、窄服务廊和货运竖廊，避免只在门口对枪。
const RING_PATROLS: Array[Dictionary] = [
	{"pos": Vector2i(39, 20), "kind": &"rifleman"},
	{"pos": Vector2i(39, 40), "kind": &"rusher"},
	{"pos": Vector2i(39, 60), "kind": &"sentry_type1"},
	{"pos": Vector2i(39, 80), "kind": &"rifleman"},
	{"pos": Vector2i(39, 98), "kind": &"rifleman"},
	{"pos": Vector2i(60, 36), "kind": &"rifleman"},
	{"pos": Vector2i(90, 36), "kind": &"hunter_type1"},
	{"pos": Vector2i(120, 36), "kind": &"mobile_turret"},
	{"pos": Vector2i(139, 50), "kind": &"rifleman"},
	{"pos": Vector2i(139, 70), "kind": &"mobile_turret"},
	{"pos": Vector2i(139, 92), "kind": &"goliath"},
	{"pos": Vector2i(60, 72), "kind": &"rusher"},
	{"pos": Vector2i(100, 72), "kind": &"sentry_type1"},
	{"pos": Vector2i(60, 92), "kind": &"rusher"},
	{"pos": Vector2i(100, 92), "kind": &"rifleman"},
	{"pos": Vector2i(54, 55), "kind": &"rifleman"},
]

## 三十四个标准补给点按区域分工：装卸/仓储出零件，车间出物料，军械/数据出电子与弹药，
## 医疗/控制出能量与维修件，大厅四角放高价值箱子，逼玩家绕着压铸机打。
const LOOT_PLAN: Array[Dictionary] = [
	{"room": 0, "loot": &"parts", "art": &"weapon_crate", "pos": Vector2(12.0, 44.0)},
	{"room": 0, "loot": &"parts", "art": &"material_box", "pos": Vector2(13.0, 58.0)},
	{"room": 1, "loot": &"parts", "art": &"supplycrate_large", "pos": Vector2(16.0, 18.0)},
	{"room": 1, "loot": &"energy", "art": &"safe_military", "pos": Vector2(28.0, 20.0)},
	{"room": 2, "loot": &"repair", "art": &"medbag_pro", "pos": Vector2(15.0, 74.0)},
	{"room": 2, "loot": &"energy", "art": &"safe_standard", "pos": Vector2(28.0, 78.0)},
	{"room": 3, "loot": &"ammo", "art": &"ammo_can", "pos": Vector2(47.0, 63.0)},
	{"room": 3, "loot": &"electronics", "art": &"safe_electronic", "pos": Vector2(58.0, 64.0)},
	{"room": 4, "loot": &"electronics", "art": &"pc_military", "pos": Vector2(47.0, 44.0)},
	{"room": 4, "loot": &"electronics", "art": &"drawer_steel", "pos": Vector2(58.0, 44.0)},
	{"room": 5, "loot": &"energy", "art": &"safe_small", "pos": Vector2(49.0, 99.0)},
	{"room": 5, "loot": &"electronics", "art": &"computer_case", "pos": Vector2(62.0, 101.0)},
	{"room": 6, "loot": &"electronics", "art": &"filing_cabinet", "pos": Vector2(78.0, 99.0)},
	{"room": 6, "loot": &"parts", "art": &"mech_unit", "pos": Vector2(90.0, 101.0)},
	{"room": 7, "loot": &"repair", "art": &"toolbox", "pos": Vector2(48.0, 80.0)},
	{"room": 7, "loot": &"parts", "art": &"material_box", "pos": Vector2(60.0, 84.0)},
	{"room": 8, "loot": &"parts", "art": &"case_trolley_green", "pos": Vector2(14.0, 97.0)},
	{"room": 9, "loot": &"parts", "art": &"supplycrate_large", "pos": Vector2(155.0, 84.0)},
	{"room": 10, "loot": &"ammo", "art": &"ammo_can", "pos": Vector2(110.0, 99.0)},
	{"room": 11, "loot": &"parts", "art": &"material_box", "pos": Vector2(49.0, 17.0)},
	{"room": 11, "loot": &"parts", "art": &"supplycrate_large", "pos": Vector2(63.0, 20.0)},
	{"room": 12, "loot": &"parts", "art": &"material_box", "pos": Vector2(77.0, 15.0)},
	{"room": 12, "loot": &"parts", "art": &"supplycrate_large", "pos": Vector2(94.0, 18.0)},
	{"room": 13, "loot": &"energy", "art": &"safe_standard", "pos": Vector2(109.0, 19.0)},
	{"room": 13, "loot": &"ammo", "art": &"ammo_can", "pos": Vector2(120.0, 24.0)},
	{"room": 14, "loot": &"electronics", "art": &"filing_cabinet", "pos": Vector2(133.0, 22.0)},
	{"room": 15, "loot": &"electronics", "art": &"drawer_cabinet", "pos": Vector2(72.0, 82.0)},
	{"room": 16, "loot": &"repair", "art": &"toolbox", "pos": Vector2(150.0, 68.0)},
	{"room": 17, "loot": &"parts", "art": &"suitcase", "pos": Vector2(94.0, 80.0)},
	{"room": 18, "loot": &"parts", "art": &"supplycrate_large", "pos": Vector2(118.0, 82.0)},
	{"room": 19, "loot": &"ammo", "art": &"weapon_crate", "pos": Vector2(72.0, 45.0)},
	{"room": 19, "loot": &"energy", "art": &"safe_military", "pos": Vector2(114.0, 45.0)},
	{"room": 19, "loot": &"ammo", "art": &"ammo_can", "pos": Vector2(72.0, 63.0)},
	{"room": 19, "loot": &"parts", "art": &"supplycrate_large", "pos": Vector2(114.0, 63.0)},
]

static var _floor_cache: Array[Rect2i] = []


## 地板矩形全集：走廊 + 所有房间。缓存一份，小地图每帧重绘时不再重复拼数组。
static func floor_rects() -> Array[Rect2i]:
	if _floor_cache.is_empty():
		_floor_cache = FLOOR_RECTS.duplicate()
		for def in ROOM_DEFS:
			_floor_cache.append(def["rect"])
	return _floor_cache


static func gap_rect(cell: Vector2i, vertical: bool) -> Rect2i:
	if vertical:
		return Rect2i(cell.x, cell.y - 1, 1, 3)
	return Rect2i(cell.x - 1, cell.y, 3, 1)


static func door_gap(def: Dictionary) -> Rect2i:
	return gap_rect(def["door_cell"], bool(def["vertical"]))


## 无门扇的拱门洞口（大厅南北贯通用）。
static func arch_gap(cell: Vector2i) -> Rect2i:
	return Rect2i(cell.x - 1, cell.y, 3, 1)


## 房间所有门洞（主门 + 侧门）。
static func all_door_gaps(def: Dictionary) -> Array[Rect2i]:
	var gaps: Array[Rect2i] = [door_gap(def)]
	for extra in def.get("extra_doors", []):
		gaps.append(gap_rect(extra["cell"], bool(extra["vertical"])))
	return gaps
