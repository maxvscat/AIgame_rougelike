extends Node2D

signal pet_attack(from_position: Vector2, target_position: Vector2, damage_amount: int)

@export var move_speed := 330.0
@export var attack_range := 170.0
@export var attack_cooldown := 1.0

var player: Node2D
var follow_offset := Vector2.ZERO
var damage_multiplier := 0.5
var _attack_timer := 0.0


func setup(target_player: Node2D, offset: Vector2) -> void:
	player = target_player
	follow_offset = offset


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return

	var collectible_drop := _find_nearest_collectible_drop()
	if collectible_drop != null:
		global_position = global_position.move_toward(collectible_drop.global_position, move_speed * delta)
		if global_position.distance_to(collectible_drop.global_position) <= 18.0:
			_collect_drop(collectible_drop)
	else:
		var follow_position: Vector2 = player.global_position + follow_offset
		global_position = global_position.move_toward(follow_position, move_speed * delta)
	_limit_distance_from_player()

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_nearest_enemy()

	queue_redraw()


func _find_nearest_collectible_drop() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = _max_distance_from_player()

	for drop in get_tree().get_nodes_in_group("drops"):
		if not is_instance_valid(drop):
			continue
		if not ["token", "chip"].has(str(drop.kind)):
			continue
		if player.global_position.distance_to(drop.global_position) > _max_distance_from_player():
			continue

		var distance: float = global_position.distance_to(drop.global_position)
		if distance <= nearest_distance:
			nearest = drop
			nearest_distance = distance

	return nearest


func _collect_drop(drop: Node2D) -> void:
	match str(drop.kind):
		"token":
			player.add_token(int(drop.amount))
		"chip":
			player.add_chip(int(drop.amount))
	drop.queue_free()


func _max_distance_from_player() -> float:
	if is_instance_valid(player):
		return float(player.attack_range) * 1.7
	return attack_range * 1.7


func _limit_distance_from_player() -> void:
	if not is_instance_valid(player):
		return
	var max_distance := _max_distance_from_player()
	var offset := global_position - player.global_position
	if offset.length() > max_distance:
		global_position = player.global_position + offset.normalized() * max_distance


func _attack_nearest_enemy() -> void:
	var target: Node2D = null
	var nearest_distance := attack_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue

		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= nearest_distance:
			target = enemy
			nearest_distance = distance

	if target == null:
		return

	var damage: int = max(1, int(round(float(player.attack_damage) * damage_multiplier)))
	var target_position := target.global_position
	target.take_damage(damage)
	pet_attack.emit(global_position, target_position, damage)
	_attack_timer = attack_cooldown


func _draw() -> void:
	draw_circle(Vector2.ZERO, 11.0, Color(1.0, 0.72, 0.18))
	draw_circle(Vector2(-4.0, -4.0), 2.0, Color(0.18, 0.09, 0.03))
	draw_circle(Vector2(4.0, -4.0), 2.0, Color(0.18, 0.09, 0.03))
	draw_line(Vector2(-4.0, 3.0), Vector2(4.0, 3.0), Color(0.18, 0.09, 0.03), 2.0)
