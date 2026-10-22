class_name TrainerTheme
extends RefCounted

static func box(fill:String,border:String,width:int=1)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color(fill);style.border_color=Color(border);style.set_border_width_all(width);style.set_corner_radius_all(6)
	style.content_margin_left=14;style.content_margin_right=14;style.content_margin_top=7;style.content_margin_bottom=7
	return style
static func create()->Theme:
	var theme:=Theme.new();theme.default_font_size=16
	theme.set_color("font_color","Label",Color("dce8eb"))
	for type in ["Button","PrimaryButton"]:
		if type=="PrimaryButton":theme.set_type_variation(type,"Button")
		var primary:bool=type=="PrimaryButton"
		theme.set_stylebox("normal",type,box("24545c" if primary else "152a37","65b7b6" if primary else "385362"))
		theme.set_stylebox("hover",type,box("306670" if primary else "213d4c","8cd3cb"))
		theme.set_stylebox("pressed",type,box("295963","98ddd4",2))
		theme.set_stylebox("disabled",type,box("12212b","293c46"))
		theme.set_stylebox("focus",type,box("00000000","e6c785",2))
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:theme.set_color(state,type,Color("eaf4f4"))
		theme.set_color("font_disabled_color",type,Color("7d929c"))
	return theme
