extends RefCounted
class_name GameData
## 可编辑数值表入口：读取 res://data/*.json，带缓存与错误提示。
## 表结构尽量扁平，方便直接在文本编辑器 / 表格工具里改数值。
## 数值在脚本首次加载时读取，改表后重启游戏（或重新运行测试）生效。

const DATA_DIR := "res://data"

static var _cache: Dictionary = {}


static func table(table_name: String) -> Dictionary:
	if _cache.has(table_name):
		return _cache[table_name]
	var path := "%s/%s.json" % [DATA_DIR, table_name]
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
		else:
			push_error("数据表解析失败（需要 JSON 对象）：%s" % path)
	else:
		push_error("缺少数据表：%s" % path)
	_cache[table_name] = data
	return data


static func string_name_keys(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source:
		out[StringName(key)] = source[key]
	return out


static func string_keys(source: Dictionary) -> Dictionary:
	var out := {}
	for key in source:
		out[String(key)] = source[key]
	return out
