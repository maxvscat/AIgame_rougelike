extends Area2D

@export var interact_radius := 72.0

var player: Node2D
var can_interact := false


func setup(target_player: Node2D) -> void:
	player = target_player


func _ready() -> void:
	add_to_group("slot_machines")


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		can_interact = false
		return

	var was_interactable := can_interact
	can_interact = global_position.distance_to(player.global_position) <= interact_radius
	if was_interactable != can_interact:
		queue_redraw()


func _draw() -> void:
	var body_color := Color(0.22, 0.2, 0.28)
	var screen_color := Color(0.1, 0.8, 0.95)
	if can_interact:
		body_color = Color(0.34, 0.28, 0.48)
		screen_color = Color(1.0, 0.86, 0.2)

	draw_rect(Rect2(Vector2(-22.0, -28.0), Vector2(44.0, 56.0)), body_color)
	draw_rect(Rect2(Vector2(-15.0, -20.0), Vector2(30.0, 17.0)), screen_color)
	draw_circle(Vector2(0.0, 12.0), 7.0, Color(0.95, 0.18, 0.18))
	draw_line(Vector2(24.0, -16.0), Vector2(36.0, -30.0), Color(0.75, 0.75, 0.82), 4.0)
	draw_circle(Vector2(38.0, -32.0), 5.0, Color(0.95, 0.18, 0.18))

	if can_interact:
		draw_circle(Vector2.ZERO, interact_radius, Color(1.0, 0.86, 0.2, 0.08))
