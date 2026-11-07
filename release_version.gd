class_name ReleaseVersion
extends RefCounted

# 0.21以降は連番体系。旧0.xの三要素タグを新体系と推測しない。
const PUBLIC := "0.25"
const INTERNAL := "0.25.0"
const FEEDBACK_URL := "https://github.com/cloford/supply-line-trainer/discussions/17"

static func parse(value:String)->Dictionary:
	var regex := RegEx.new()
	regex.compile("^v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:\\.(0|[1-9][0-9]*))?\\z")
	var found := regex.search(value)
	if found == null:
		return {}
	for index in range(1,4):
		if found.get_string(index).length() > 9:
			return {}
	var major := int(found.get_string(1))
	var minor := int(found.get_string(2))
	var third := found.get_string(3)
	if major == 0 and minor >= 21 and third.is_empty():
		return {"epoch":1,"parts":[0,minor,0],"public":"0.%d" % minor}
	# 内部版は現在ビルドだけを明示的に許可。任意の旧0.x.yは旧体系。
	if value.trim_prefix("v") == INTERNAL:
		return {"epoch":1,"parts":[0,int(PUBLIC.get_slice(".",1)),0],"public":PUBLIC}
	if third.is_empty():
		return {}
	return {"epoch":0,"parts":[major,minor,int(third)],"public":"%d.%d.%d" % [major,minor,int(third)]}

static func parts(value:String)->Array[int]:
	var parsed := parse(value)
	var result:Array[int] = []
	if not parsed.is_empty():
		for part in parsed.parts:
			result.append(int(part))
	return result

static func display(value:String)->String:
	return str(parse(value).get("public",""))

static func newer(candidate:String, current:String)->bool:
	var left := parse(candidate)
	var right := parse(current)
	if left.is_empty() or right.is_empty():
		return false
	if int(left.epoch) != int(right.epoch):
		return int(left.epoch) > int(right.epoch)
	for index in 3:
		if int(left.parts[index]) != int(right.parts[index]):
			return int(left.parts[index]) > int(right.parts[index])
	return false

static func same(left:String, right:String)->bool:
	return not parse(left).is_empty() and parse(left) == parse(right)
