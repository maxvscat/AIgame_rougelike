extends CharacterBody2D

signal stats_changed
signal died
signal attack_performed(from_position: Vector2, target_position: Vector2, damage_amount: int)
signal area_effect(center: Vector2, radius: float, color: Color)
signal level_up_notice(text: String)
signal level_up_available

@export var speed := 260.0
@export var max_health := 100
@export var attack_damage := 26
@export var attack_range := 170.0
@export var attack_cooldown := 0.65

var health := 100
var level := 1
var experience := 0
var experience_to_next := 25
var slot_tokens := 0
var chip_pickups := 0
var pickup_range_multiplier := 1.70
var chip_drop_multiplier := 1.0
var crit_chance := 0.0
var regen_per_second := 0.0
var extra_lives := 0
var defense_reduction := 0.0

var jackpot_skills := {
	"aura_ring": 0,
	"bounce": 0,
	"multishot": 0,
	"dice_split": 0,
	"slot_777": 0,
	"energy_attack": 0,
	"lucky_cat": 0
}

var small_skills := {
	"bomb": 0,
	"thunder": 0,
	"fire": 0,
	"ice": 0,
	"missile": 0
}

var upgrade_skills := {
	"crit": 0,
	"jackpot_rate": 0,
	"cost_rate": 0,
	"fragment_amount": 0,
	"reroll_rate": 0,
	"line_rate": 0,
	"damage": 0,
	"attack_speed": 0,
	"experience": 0,
	"move_speed": 0
}

var _attack_timer := 0.0
var _hit_flash_timer := 0.0
var _attack_count := 0
var _regen_pool := 0.0
var _dash_cooldown_timer := 0.0
var _dash_timer := 0.0
var _dash_direction := Vector2.RIGHT
var _last_move_direction := Vector2.RIGHT
var _player_texture: Texture2D
var _lucky_cat_texture: Texture2D


func _ready() -> void:
	add_to_group("player")
	_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/player_core.png")
	_lucky_cat_texture = load("res://AIgame_rougelike/assets/art/characters/pets/lucky_cat.png")
	health = max_health
	stats_changed.emit()


func _physics_process(delta: float) -> void:
	if health <= 0:
		return

	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length() > 0.001:
		_last_move_direction = input_direction.normalized()
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_direction * speed * 3.2
	else:
		velocity = input_direction * speed
	move_and_slide()

	if regen_per_second > 0.0 and health < max_health:
		_regen_pool += regen_per_second * delta
		var heal_amount := int(floor(_regen_pool))
		if heal_amount > 0:
			_regen_pool -= heal_amount
			heal(heal_amount)

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_auto_attack()

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		queue_redraw()


func request_dash() -> void:
	if health <= 0 or _dash_cooldown_timer > 0.0 or _dash_timer > 0.0:
		return
	_dash_direction = _last_move_direction
	_dash_timer = 0.14
	_dash_cooldown_timer = 1.0


func _auto_attack() -> void:
	var targets := _get_targets_in_range(1 + get_skill_level("multishot"))
	if targets.is_empty():
		return

	_attack_count += 1
	var hit_targets: Array[Node2D] = []
	for index in range(targets.size()):
		var target: Node2D = targets[index]
		var damage: int = _roll_attack_damage()
		if index > 0:
			damage = max(1, int(round(float(damage) * 0.8)))
		_damage_enemy(target, damage, global_position)
		hit_targets.append(target)

	var primary_target: Node2D = targets[0]
	var bounce_level := get_skill_level("bounce")
	if bounce_level > 0:
		_bounce_from_target(primary_target, bounce_level, hit_targets)

	var split_level := get_skill_level("dice_split")
	if split_level > 0:
		_split_from_target(primary_target, hit_targets, split_level)

	var explosion_level := get_skill_level("slot_777")
	if explosion_level > 0 and _attack_count % 3 == 0:
		_explode_at(primary_target.global_position, explosion_level)

	_attack_timer = attack_cooldown


func _roll_attack_damage() -> int:
	var amount := attack_damage
	if randf() < crit_chance:
		amount = int(round(float(amount) * 2.0))
	return max(1, amount)


func _get_targets_in_range(limit: int) -> Array[Node2D]:
	var candidates: Array[Dictionary] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance <= attack_range:
			candidates.append({"enemy": enemy, "distance": distance})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)

	var targets: Array[Node2D] = []
	for entry in candidates:
		targets.append(entry["enemy"])
		if targets.size() >= limit:
			break
	return targets


func _damage_enemy(enemy: Node2D, amount: int, from_position: Vector2) -> void:
	if not is_instance_valid(enemy):
		return
	var target_position := enemy.global_position
	enemy.take_damage(amount)
	attack_performed.emit(from_position, target_position, amount)


func _bounce_from_target(start_target: Node2D, max_bounces: int, hit_targets: Array[Node2D]) -> void:
	var current_target := start_target
	for _bounce_index in range(max_bounces):
		if not is_instance_valid(current_target):
			return
		var next_target := _find_nearest_enemy(current_target.global_position, 170.0, hit_targets)
		if next_target == null:
			return
		var bounce_damage: int = max(1, int(round(float(_roll_attack_damage()) * 0.8)))
		_damage_enemy(next_target, bounce_damage, current_target.global_position)
		hit_targets.append(next_target)
		current_target = next_target


func _split_from_target(primary_target: Node2D, hit_targets: Array[Node2D], split_count: int) -> void:
	if not is_instance_valid(primary_target):
		return
	var split_hits := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if split_hits >= split_count:
			return
		if enemy == primary_target or not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if hit_targets.has(enemy):
			continue
		if primary_target.global_position.distance_to(enemy.global_position) <= 130.0:
			var split_damage: int = max(1, int(round(float(attack_damage) * 0.5)))
			_damage_enemy(enemy, split_damage, primary_target.global_position)
			hit_targets.append(enemy)
			split_hits += 1


func _explode_at(center: Vector2, skill_level: int) -> void:
	var explosion_radius := 128.0
	var damage_multiplier := 1.0 + 0.5 * float(skill_level - 1)
	var damage: int = max(1, int(round(float(attack_damage) * damage_multiplier * 0.8)))
	area_effect.emit(center, explosion_radius, Color(1.0, 0.48, 0.08, 0.35))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if center.distance_to(enemy.global_position) <= explosion_radius:
			_damage_enemy(enemy, damage, center)


func _find_nearest_enemy(origin: Vector2, max_distance: float, ignored: Array[Node2D]) -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance := max_distance
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if ignored.has(enemy):
			continue
		var distance: float = origin.distance_to(enemy.global_position)
		if distance <= nearest_distance:
			nearest_enemy = enemy
			nearest_distance = distance
	return nearest_enemy


func take_damage(amount: int) -> void:
	if health <= 0:
		return
	var final_amount: int = max(1, int(ceil(float(amount) * (1.0 - clamp(defense_reduction, 0.0, 0.85)))))
	health = max(health - final_amount, 0)
	_hit_flash_timer = 0.12
	stats_changed.emit()
	queue_redraw()
	if health <= 0:
		if extra_lives > 0:
			extra_lives -= 1
			health = max(1, int(round(float(max_health) * 0.5)))
			stats_changed.emit()
		else:
			died.emit()


func add_experience(amount: int) -> void:
	var gained: int = max(1, int(round(float(amount) * (1.0 + 0.1 * float(get_upgrade_skill_level("experience"))))))
	experience += gained
	var level_count := 0
	while experience >= experience_to_next:
		experience -= experience_to_next
		level += 1
		_apply_level_stat_growth()
		experience_to_next = _calculate_next_experience_requirement()
		level_count += 1
	stats_changed.emit()
	for _index in range(level_count):
		level_up_notice.emit("LV UP！")
		level_up_available.emit()


func _calculate_next_experience_requirement() -> int:
	var multiplier := 1.18
	if level > 10:
		multiplier += min(0.82, pow(float(level - 10), 1.25) * 0.018)
	var flat_bonus := 8 + int(round(float(level) * 1.5))
	return max(experience_to_next + 1, int(round(float(experience_to_next) * multiplier)) + flat_bonus)


func _apply_level_stat_growth() -> void:
	attack_damage = max(attack_damage + 1, int(round(float(attack_damage) * 1.05)))
	attack_cooldown = max(0.12, attack_cooldown / 1.05)
	var old_max := max_health
	max_health = max(max_health + 1, int(round(float(max_health) * 1.10)))
	health = min(max_health, health + max_health - old_max)
	pickup_range_multiplier *= 1.05
	crit_chance += 0.02


func add_token(amount: int) -> void:
	slot_tokens += amount
	stats_changed.emit()


func add_chip(amount: int) -> void:
	chip_pickups += amount
	stats_changed.emit()


func spend_token(amount: int) -> bool:
	if slot_tokens < amount:
		return false
	slot_tokens -= amount
	stats_changed.emit()
	return true


func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	stats_changed.emit()


func grant_jackpot_skill(skill_id: String) -> bool:
	if skill_id == "money_attack":
		skill_id = "energy_attack"
	if not jackpot_skills.has(skill_id):
		return false
	var current_level := int(jackpot_skills[skill_id])
	if current_level >= 5:
		return false
	jackpot_skills[skill_id] = current_level + 1
	queue_redraw()
	stats_changed.emit()
	return true


func grant_small_skill(skill_id: String) -> bool:
	if not small_skills.has(skill_id):
		return false
	var current_level := int(small_skills[skill_id])
	if current_level >= 5:
		return false
	small_skills[skill_id] = current_level + 1
	stats_changed.emit()
	return true


func get_skill_level(skill_id: String) -> int:
	if skill_id == "money_attack":
		skill_id = "energy_attack"
	return int(jackpot_skills.get(skill_id, 0))


func get_small_skill_level(skill_id: String) -> int:
	return int(small_skills.get(skill_id, 0))


func get_upgrade_skill_level(skill_id: String) -> int:
	return int(upgrade_skills.get(skill_id, 0))


func is_upgrade_skill_maxed(skill_id: String) -> bool:
	return get_upgrade_skill_level(skill_id) >= 5


func apply_upgrade_skill(skill_id: String) -> bool:
	if not upgrade_skills.has(skill_id) or is_upgrade_skill_maxed(skill_id):
		return false
	upgrade_skills[skill_id] = get_upgrade_skill_level(skill_id) + 1
	match skill_id:
		"crit":
			crit_chance += 0.07
		"damage":
			attack_damage = max(attack_damage + 1, int(round(float(attack_damage) * 1.1)))
		"attack_speed":
			attack_cooldown = max(0.12, attack_cooldown / 1.1)
		"move_speed":
			speed *= 1.1
	stats_changed.emit()
	return true


func apply_research_effect(effect_id: String, level: int = 1) -> void:
	match effect_id:
		"start_damage_50":
			attack_damage = max(attack_damage + 1, int(round(float(attack_damage) * (1.0 + float(50 + 20 * (level - 1)) / 100.0))))
		"crit_20":
			crit_chance += float(20 + 10 * (level - 1)) / 100.0
		"random_jackpot_skill":
			var choices := jackpot_skills.keys()
			grant_jackpot_skill(str(choices.pick_random()))
		"regen_2":
			regen_per_second += float(2 + level - 1)
		"extra_life":
			extra_lives += level
		"chip_drop_x2":
			chip_drop_multiplier *= float(1 + level)
		"defense_20":
			defense_reduction += float(20 + 10 * (level - 1)) / 100.0
	stats_changed.emit()


func _apply_research_normal_skill(skill_id: String) -> void:
	match skill_id:
		"damage":
			attack_damage = max(attack_damage + 1, int(round(float(attack_damage) * 1.3)))
		"attack_speed":
			attack_cooldown = max(0.12, attack_cooldown / 1.3)
		"move_speed":
			speed *= 1.15
		"pickup_range":
			pickup_range_multiplier *= 1.3


func _draw() -> void:
	var body_color := Color(0.15, 0.55, 1.0)
	if _hit_flash_timer > 0.0:
		body_color = Color(1.0, 0.95, 0.95)

	draw_arc(Vector2.ZERO, attack_range, 0.0, TAU, 96, Color(0.2, 0.65, 1.0, 0.12), 2.0)
	var aura_level := get_skill_level("aura_ring")
	if aura_level > 0:
		var aura_radius := 3.0 * 64.0
		draw_circle(Vector2.ZERO, aura_radius, Color(0.95, 0.15, 0.35, 0.12))
		draw_arc(Vector2.ZERO, aura_radius, 0.0, TAU, 96, Color(1.0, 0.2, 0.4, 0.45), 3.0)

	if _player_texture != null:
		draw_texture_rect(_player_texture, Rect2(Vector2(-24.0, -24.0), Vector2(48.0, 48.0)), false, body_color.lightened(0.18) if _hit_flash_timer > 0.0 else Color.WHITE)
	else:
		draw_circle(Vector2.ZERO, 16.0, body_color)
		draw_circle(Vector2(5.0, -5.0), 4.0, Color(0.85, 0.95, 1.0))

	if get_skill_level("lucky_cat") > 0:
		if _lucky_cat_texture != null:
			draw_texture_rect(_lucky_cat_texture, Rect2(Vector2(-40.0, 2.0), Vector2(28.0, 28.0)), false)
		else:
			draw_circle(Vector2(-24.0, 18.0), 8.0, Color(1.0, 0.72, 0.18))
			draw_circle(Vector2(-21.0, 16.0), 2.0, Color(0.2, 0.12, 0.05))
