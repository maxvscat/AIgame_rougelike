extends CharacterBody2D

signal damaged(enemy_kind: String, damage_amount: int)
signal died(enemy_position: Vector2, xp_value: int, money_value: int, enemy_kind: String)

@export var speed := 112.5
@export var max_health := 48
@export var touch_damage := 11
@export var contact_cooldown := 1.0
@export var xp_value := 8
@export var money_value := 3

var target: Node2D
var enemy_kind := "normal"
var health := 48
var _contact_timer := 0.0
var _hit_flash_timer := 0.0


func _ready() -> void:
	add_to_group("enemies")
	health = max_health


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or health <= 0:
		return

	velocity = global_position.direction_to(target.global_position) * speed
	move_and_slide()

	_contact_timer = max(_contact_timer - delta, 0.0)
	if global_position.distance_to(target.global_position) <= 46.0 and _contact_timer <= 0.0:
		if target.has_method("take_damage"):
			target.take_damage(touch_damage)
		_contact_timer = contact_cooldown

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		queue_redraw()


func scale_stats(multiplier: float) -> void:
	max_health = int(round(max_health * multiplier))
	health = max_health
	xp_value = int(round(xp_value * multiplier))
	money_value = max(1, int(round(money_value * multiplier)))


func take_damage(amount: int) -> void:
	health -= amount
	damaged.emit(enemy_kind, amount)
	_hit_flash_timer = 0.08
	queue_redraw()

	if health <= 0:
		died.emit(global_position, xp_value, money_value, enemy_kind)
		queue_free()


func _draw() -> void:
	var color := Color(0.95, 0.2, 0.16)
	if enemy_kind == "elite":
		color = Color(0.85, 0.22, 1.0)
	elif enemy_kind == "boss" or enemy_kind == "small_boss":
		color = Color(1.0, 0.55, 0.08)
	elif enemy_kind == "stage_boss":
		color = Color(0.95, 0.05, 0.05)
	if _hit_flash_timer > 0.0:
		color = Color(1.0, 0.9, 0.65)

	var body_radius := 14.0
	if enemy_kind == "elite":
		body_radius = 18.0
	elif enemy_kind == "boss" or enemy_kind == "small_boss":
		body_radius = 26.0
	elif enemy_kind == "stage_boss":
		body_radius = 36.0

	draw_circle(Vector2.ZERO, body_radius, color)
	draw_circle(Vector2(-4.0, -3.0), 3.0, Color(0.22, 0.04, 0.04))
	draw_circle(Vector2(4.0, -3.0), 3.0, Color(0.22, 0.04, 0.04))

	var health_ratio: float = clamp(float(health) / float(max_health), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-16.0, -25.0), Vector2(32.0, 4.0)), Color(0.18, 0.02, 0.02))
	draw_rect(Rect2(Vector2(-16.0, -25.0), Vector2(32.0 * health_ratio, 4.0)), Color(0.4, 1.0, 0.32))
