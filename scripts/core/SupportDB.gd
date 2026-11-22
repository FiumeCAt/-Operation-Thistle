extends RefCounted
class_name SupportDB
## 支援协议分类。三种资源模型共用一套使用检查：
## - RECHARGE：无次数上限，按冷却恢复（自主恢复）
## - PER_LEVEL：每层限用，下潜后重置（狙击支援）
## - PER_RUN：每局限用，只有返回基地再出发才重置（后续 OP 技能）

enum Scope { RECHARGE, PER_LEVEL, PER_RUN }

const PROTOCOLS := {
	&"self_heal": {
		"name": "自主恢复",
		"scope": Scope.RECHARGE,
		"cooldown": 18.0,
		"heal": 25.0,
		"desc": "无次数上限，冷却结束后可再次恢复生命。",
	},
	&"sniper": {
		"name": "狙击支援",
		"scope": Scope.PER_LEVEL,
		"cooldown": 8.0,
		"damage": 80.0,
		"desc": "每层限用，次数为 2 + 支援协议等级，下潜后重置。",
	},
}

static func protocol(id: StringName) -> Dictionary:
	return PROTOCOLS.get(id, PROTOCOLS[&"sniper"])

static func scope_name(scope: int) -> String:
	match scope:
		Scope.RECHARGE:
			return "可恢复"
		Scope.PER_LEVEL:
			return "每层限用"
		Scope.PER_RUN:
			return "每局限用"
	return "未知"
