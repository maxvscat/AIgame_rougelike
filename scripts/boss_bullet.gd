extends Node2D

var direction := Vector2.RIGHT
var speed := 200.0
var damage := 1
var target: Node2D
var life_time := 6.0
var radius := 8.0


func setup(start_position: Vector2, target_position: Vector2, bullet_speed: float, damage_amount: int, target_node: Node2D) -> void:
	global_position = start_position
	var to_target := target_position - start_position
	direction = to_target.normalized() if to_target.length() > 0.001 else Vector2.RIGHT
	speed = bullet_speed
	damage = damage_amount
	target = target_node


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	life_time -= delta
	if life_time <= 0.0:
		queue_free()
		return
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= radius + 16.0:
		if target.has_method("take_damage"):
			target.take_damage(damage)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.62, 0.12))
	draw_circle(Vector2.ZERO, radius * 0.45, Color(1.0, 0.96, 0.36))
