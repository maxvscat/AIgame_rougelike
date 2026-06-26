extends Control

signal activated(skill_id: String)

var skill_id := ""
var skill_name := ""
var level := 0
var icon: Texture2D
var cooldown := 0.0
var max_cooldown := 0.0
var is_turret := false
var hotkey := 0
var _font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(78, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = load("res://AIgame_rougelike/assets/fonts/NotoSansCJKtc-Regular.otf")


func setup(data: Dictionary) -> void:
	skill_id = str(data.get("id", ""))
	skill_name = str(data.get("name", ""))
	level = int(data.get("level", 0))
	icon = data.get("icon", null)
	cooldown = float(data.get("cooldown", 0.0))
	max_cooldown = float(data.get("max_cooldown", 0.0))
	is_turret = bool(data.get("is_turret", false))
	hotkey = int(data.get("hotkey", 0))
	tooltip_text = "%s LV%d" % [skill_name, level]
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_turret and cooldown <= 0.0:
			activated.emit(skill_id)


func _draw() -> void:
	var bg := Color(0.05, 0.08, 0.12, 0.92)
	var edge := Color(0.35, 0.58, 0.72, 1.0)
	if is_turret:
		edge = Color(0.95, 0.74, 0.22, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	draw_rect(Rect2(Vector2.ZERO, size), edge, false, 2.0)

	var short_name := skill_name.substr(0, min(2, skill_name.length()))
	if _font != null:
		draw_string(_font, Vector2(8, 17), short_name, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 15, Color(1, 1, 1))
		draw_string(_font, Vector2(8, 88), "LV%d" % level, HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 12, Color(0.85, 0.95, 1.0))

	var icon_rect := Rect2(Vector2(15, 27), Vector2(48, 48))
	if icon != null:
		draw_texture_rect(icon, icon_rect, false)
	else:
		draw_circle(icon_rect.get_center(), 22, Color(0.2, 0.42, 0.62))

	if max_cooldown > 0.0 and cooldown > 0.0:
		var ratio: float = clamp(cooldown / max_cooldown, 0.0, 1.0)
		draw_circle(icon_rect.get_center(), 25, Color(0, 0, 0, 0.55))
		draw_arc(icon_rect.get_center(), 25, -PI * 0.5, -PI * 0.5 + TAU * ratio, 36, Color(0.35, 0.85, 1.0), 5.0)
		if _font != null:
			draw_string(_font, Vector2(15, 57), "%d" % ceil(cooldown), HORIZONTAL_ALIGNMENT_CENTER, 48, 16, Color(1, 1, 1))
	# 魚機系技能熱鍵數字（右下角）
	if is_turret and hotkey > 0 and _font != null:
		var br := icon_rect.end
		draw_rect(Rect2(Vector2(br.x - 16, br.y - 16), Vector2(16, 16)), Color(0.0, 0.0, 0.0, 0.72))
		draw_string(_font, Vector2(br.x - 14, br.y - 2), str(hotkey),
			HORIZONTAL_ALIGNMENT_CENTER, 13, 12, Color(1.0, 0.9, 0.3))
