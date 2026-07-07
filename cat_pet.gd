extends Node2D

signal pet_attack(from_position: Vector2, target_position: Vector2, damage_amount: int)

@export var move_speed := 330.0
@export var attack_range := 170.0   # 索敵範圍（多遠會開始追擊敵人）
@export var melee_range := 56.0     # 近戰命中範圍（需貼近才能造成傷害）
@export var attack_cooldown := 1.0

var player: Node2D
var follow_offset := Vector2.ZERO
var damage_multiplier := 0.5
var collect_drops := true
var _attack_timer := 0.0
var _cat_texture: Texture2D
var _lunge_timer := 0.0
var _lunge_dir := Vector2.RIGHT


func setup(target_player: Node2D, offset: Vector2) -> void:
	player = target_player
	follow_offset = offset


func _ready() -> void:
	# 皇家護衛改用 AI 生成、比照玩家大頭blob卡通風格的護衛外觀，取代原本的招財貓素材
	# （目前遊戲已無其他地方使用招財貓機制，置換不影響其他功能）。
	_cat_texture = load("res://AIgame_rougelike/assets/art/characters/pets/guard_pet.png")


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		queue_free()
		return

	if _lunge_timer > 0.0:
		_lunge_timer -= delta

	var target_enemy := _find_nearest_enemy(attack_range)
	if target_enemy != null:
		# 近戰模式：先追到貼近敵人的距離，貼近後才造成傷害
		if global_position.distance_to(target_enemy.global_position) > melee_range:
			global_position = global_position.move_toward(target_enemy.global_position, move_speed * delta)
		_limit_distance_from_player()
		_attack_timer -= delta
		if _attack_timer <= 0.0 and global_position.distance_to(target_enemy.global_position) <= melee_range:
			_attack_enemy(target_enemy)
		queue_redraw()
		return

	var collectible_drop := _find_nearest_collectible_drop() if collect_drops else null
	if collectible_drop != null:
		global_position = global_position.move_toward(collectible_drop.global_position, move_speed * delta)
		if global_position.distance_to(collectible_drop.global_position) <= 18.0:
			_collect_drop(collectible_drop)
	else:
		var follow_position: Vector2 = player.global_position + follow_offset
		global_position = global_position.move_toward(follow_position, move_speed * delta)
	_limit_distance_from_player()

	_attack_timer -= delta

	queue_redraw()


func _find_nearest_enemy(max_dist: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := max_dist
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest


func _attack_enemy(target: Node2D) -> void:
	var damage: int = max(1, int(round(float(player.attack_damage) * damage_multiplier)))
	var target_position := target.global_position
	target.take_damage(damage)
	pet_attack.emit(global_position, target_position, damage)
	_attack_timer = attack_cooldown
	_lunge_timer = 0.16
	_lunge_dir = global_position.direction_to(target_position)
	if _lunge_dir.length_squared() < 0.001:
		_lunge_dir = Vector2.RIGHT
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
	# 護衛移動距離不可超過玩家攻擊範圍
	if is_instance_valid(player):
		if player.has_method("get_attack_range"):
			return float(player.get_attack_range())
		return attack_range
	return attack_range


func _limit_distance_from_player() -> void:
	if not is_instance_valid(player):
		return
	var max_distance := _max_distance_from_player()
	var offset := global_position - player.global_position
	if offset.length() > max_distance:
		global_position = player.global_position + offset.normalized() * max_distance


func _draw() -> void:
	# 近戰攻擊動畫：放大閃光 + 向目標方向撲擊位移 + 揮擊弧線
	var attacking: bool = _lunge_timer > 0.0
	var progress: float = clamp(_lunge_timer / 0.16, 0.0, 1.0) if attacking else 0.0
	var s: float = 1.0 + (0.35 * progress)
	var size := 36.0 * s
	var lunge_offset: Vector2 = _lunge_dir * (10.0 * progress) if attacking else Vector2.ZERO
	var draw_center: Vector2 = lunge_offset

	if attacking:
		var slash_angle: float = _lunge_dir.angle()
		var arc_col := Color(1.0, 0.92, 0.55, 0.85 * progress)
		draw_arc(draw_center + _lunge_dir * 20.0, 22.0, slash_angle - 0.9, slash_angle + 0.9, 10, arc_col, 4.0)

	if _cat_texture != null:
		draw_texture_rect(_cat_texture, Rect2(draw_center - Vector2(size * 0.5, size * 0.5), Vector2(size, size)), false)
	else:
		var r: float = 11.0 * s
		draw_circle(draw_center, r, Color(1.0, 0.72, 0.18))
		draw_circle(draw_center + Vector2(-4.0, -4.0), 2.0, Color(0.18, 0.09, 0.03))
		draw_circle(draw_center + Vector2(4.0, -4.0), 2.0, Color(0.18, 0.09, 0.03))
		draw_line(draw_center + Vector2(-4.0, 3.0), draw_center + Vector2(4.0, 3.0), Color(0.18, 0.09, 0.03), 2.0)
