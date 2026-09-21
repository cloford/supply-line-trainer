class_name BigUInt
extends RefCounted

static func normalize(value:String)->String:
	var out:=value.strip_edges().trim_prefix("+")
	while out.length()>1 and out.begins_with("0"):out=out.substr(1)
	for c in out:
		if c<"0" or c>"9":return "0"
	return out if not out.is_empty() else "0"
static func compare(a:String,b:String)->int:
	a=normalize(a);b=normalize(b)
	if a.length()!=b.length():return 1 if a.length()>b.length() else -1
	if a==b:return 0
	return 1 if a>b else -1
static func add(a:String,b:String)->String:
	a=normalize(a);b=normalize(b);var carry:=0;var out:="";var ia:=a.length()-1;var ib:=b.length()-1
	while ia>=0 or ib>=0 or carry>0:
		var sum:int=carry+(int(a.substr(ia,1)) if ia>=0 else 0)+(int(b.substr(ib,1)) if ib>=0 else 0);out=str(sum%10)+out;carry=int(sum/10);ia-=1;ib-=1
	return normalize(out)
static func subtract(a:String,b:String)->String:
	if compare(a,b)<0:return "0"
	var borrow:=0;var out:="";var ia:=a.length()-1;var ib:=b.length()-1
	while ia>=0:
		var digit:=int(a.substr(ia,1))-borrow-(int(b.substr(ib,1)) if ib>=0 else 0);borrow=0
		if digit<0:digit+=10;borrow=1
		out=str(digit)+out;ia-=1;ib-=1
	return normalize(out)
static func from_float(value:float)->String:
	if value<=0:return "0"
	if value<9.0e15:return str(int(floor(value)))
	var parts:=("%.14e"%value).split("e");var digits:=parts[0].replace(".","");var exponent:=int(parts[1]);var zeros:=exponent-(digits.length()-1)
	if zeros>=0:return normalize(digits+"0".repeat(zeros))
	return normalize(digits.substr(0,maxi(1,digits.length()+zeros)))
static func to_float(value:String)->float:
	value=normalize(value)
	if value.length()<16:return float(value)
	var take:=mini(15,value.length());return float(value.substr(0,take))*pow(10.0,value.length()-take)
static func format(value:String)->String:
	value=normalize(value);var length:=value.length()
	var units:=[{"d":21,"u":"垓"},{"d":17,"u":"京"},{"d":13,"u":"兆"},{"d":9,"u":"億"},{"d":5,"u":"万"}]
	for unit in units:
		if length>=unit.d:
			var lead:=value.substr(0,mini(3,length));return lead.substr(0,1)+("."+lead.substr(1) if lead.length()>1 else "")+unit.u
	return value
