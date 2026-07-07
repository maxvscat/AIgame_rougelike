extends Area2D

signal collected(kind: String, amount: int)

@export var pickup_radius := 92.0
@export var attraction_speed := 780.0

var kind := "xp"
var amount := 1
var player: Node2D
var is_attracted := false
var token_texture: Texture2D
var chip_texture: Texture2D
var xp_texture: Texture2D


func setup(drop_kind: String, drop_amount: int, target_player: Node2D) -> void:
	kind = drop_kind
	amount = drop_amount
	player = target_player
	queue_redraw()


func _ready() -> void:
	add_to_group("drops")
	token_texture = load("res://AIgame_rougelike/assets/art/drops/token.png")
	chip_texture = load("res://AIgame_rougelike/assets/art/drops/chip.png")
	xp_texture = load("res://AIgame_rougelike/assets/art/drops/xp.png")


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	var active_pickup_radius := pickup_radius
	var pickup_multiplier = player.get("pickup_range_multiplier")
	if pickup_multiplier != null:
		active_pickup_radius *= float(pickup_multiplier)

	var distance := global_position.distance_to(player.global_position)
	if distance <= active_pickup_radius:
		is_attracted = true
	if is_attracted:
		global_position = global_position.move_toward(player.global_position, attraction_speed * delta)

	if global_position.distance_to(player.global_position) <= 18.0:
		collected.emit(kind, amount)
		queue_free()


func _draw() -> void:
	if kind == "token":
		if token_texture != null:
			draw_texture_rect(token_texture, Rect2(Vector2(-13.0, -13.0), Vector2(26.0, 26.0)), false)
		else:
			draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.22, 0.9))
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.78, 1.0))
	elif kind == "chip":
		if chip_texture != null:
			draw_texture_rect(chip_texture, Rect2(Vector2(-13.0, -13.0), Vector2(26.0, 26.0)), false)
		else:
			draw_rect(Rect2(Vector2(-7.0, -6.0), Vector2(14.0, 12.0)), Color(0.2, 0.95, 1.0))
			draw_rect(Rect2(Vector2(-3.0, -2.0), Vector2(6.0, 4.0)), Color(0.02, 0.12, 0.18))
	else:
		if xp_texture != null:
			draw_texture_rect(xp_texture, Rect2(Vector2(-13.0, -13.0), Vector2(26.0, 26.0)), false)
		else:
			draw_circle(Vector2.ZERO, 7.0, Color(0.36, 1.0, 0.78))
			draw_circle(Vector2.ZERO, 3.0, Color(0.82, 1.0, 0.95))
