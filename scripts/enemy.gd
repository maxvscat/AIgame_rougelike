extends CharacterBody2D

signal damaged(enemy_kind: String, damage_amount: int)
signal died(enemy_position: Vector2, xp_value: int, enemy_kind: String)
signal special_requested(enemy: Node2D, skill_id: String, target_position: Vector2)

const TILE_SIZE := 64.0
const HEADHUNTER_BODY_RADIUS := 21.0
const HEADHUNTER_DASH_DISTANCE := TILE_SIZE * 9.0
const HEADHUNTER_DASH_WIDTH := HEADHUNTER_BODY_RADIUS * 6.0
const HEADHUNTER_DASH_SPEED_MULTIPLIER := 4.0
const HEADHUNTER_SWEEP_RADIUS := TILE_SIZE * 5.0
const HEADHUNTER_SWEEP_PREPARE_TIME := 1.5
const BOSS_BODY_RADIUS := 32.0
const BOSS_CHARGE_DISTANCE := TILE_SIZE * 14.0
const BOSS_CHARGE_WIDTH := BOSS_BODY_RADIUS * 6.0
const BOSS_CHARGE_SPEED_MULTIPLIER := 5.0

@export var speed := 112.5
@export var max_health := 48
@export var touch_damage := 11
@export var contact_cooldown := 1.0
@export var contact_distance := 46.0
@export var separation_distance := 42.0
@export var separation_push_speed := 70.0
@export var xp_value := 8

var target: Node2D
var enemy_kind := "normal"
var health := 48
var _contact_timer := 0.0
var _hit_flash_timer := 0.0
var _headhunter_state := "chase"
var _headhunter_timer := 0.0
var _headhunter_dash_direction := Vector2.ZERO
var _headhunter_dash_hit := false
var _headhunter_dash_start := Vector2.ZERO
var _headhunter_dash_end := Vector2.ZERO
var _headhunter_warning_clear_timer := -1.0
var _headhunter_warning_line: Line2D
var _headhunter_sweep_ring: Line2D
var _boss_charge_timer := 7.0
var _boss_summon_timer := 10.0
var _boss_crash_timer := 15.0
var _boss_scan_timer := 7.0
var _boss_bullet_timer := 0.3
var _boss_bullets_left := 50
var _boss_reload_timer := 0.0
var _boss_state := "chase"
var _boss_state_timer := 0.0
var _boss_dash_direction := Vector2.ZERO
var _boss_dash_hit := false
var _boss_dash_start := Vector2.ZERO
var _boss_dash_end := Vector2.ZERO
var _skill_label_timer := 0.0
var _skill_label_text := ""
var _slow_timer := 0.0
var _slow_multiplier := 1.0


func _ready() -> void:
	add_to_group("enemies")
	health = max_health


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target) or health <= 0:
		return

	if enemy_kind == "headhunter":
		_process_headhunter(delta)
	elif enemy_kind == "boss":
		_process_boss(delta)
	else:
		_process_chase(delta)

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_multiplier = 1.0
	if _headhunter_warning_clear_timer > 0.0:
		_headhunter_warning_clear_timer -= delta
		if _headhunter_warning_clear_timer <= 0.0:
			_clear_headhunter_warning_line()

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		queue_redraw()
	if _skill_label_timer > 0.0:
		_skill_label_timer -= delta
		queue_redraw()


func _process_chase(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector2.ZERO
	if distance > contact_distance:
		velocity = direction * _current_speed()
	elif distance < separation_distance:
		velocity = -direction * separation_push_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	_contact_timer = max(_contact_timer - delta, 0.0)
	if distance <= contact_distance and _contact_timer <= 0.0:
		if target.has_method("take_damage"):
			target.take_damage(touch_damage)
		_contact_timer = contact_cooldown


func _process_headhunter(delta: float) -> void:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector2.RIGHT
	var lock_distance := 3.0 * TILE_SIZE
	match _headhunter_state:
		"chase":
			if distance > lock_distance:
				velocity = direction * _current_speed()
				move_and_slide()
			else:
				_start_headhunter_dash_lock(direction)
		"lock":
			velocity = Vector2.ZERO
			_headhunter_timer -= delta
			if _headhunter_timer <= 0.0:
				_headhunter_state = "dash"
				_headhunter_timer = HEADHUNTER_DASH_DISTANCE / max(1.0, _current_speed() * HEADHUNTER_DASH_SPEED_MULTIPLIER)
				_headhunter_warning_clear_timer = 1.0
		"dash":
			velocity = _headhunter_dash_direction * _current_speed() * HEADHUNTER_DASH_SPEED_MULTIPLIER
			move_and_slide()
			_try_path_hit(touch_damage, _headhunter_dash_start, _headhunter_dash_end, HEADHUNTER_DASH_WIDTH, "_headhunter_dash_hit")
			_headhunter_timer -= delta
			if _headhunter_timer <= 0.0:
				velocity = Vector2.ZERO
				_start_headhunter_sweep()
		"sweep_prepare":
			velocity = Vector2.ZERO
			_headhunter_timer -= delta
			if _headhunter_timer <= 0.0:
				_finish_headhunter_sweep()
				_headhunter_state = "recover"
				_headhunter_timer = 1.0
		"recover":
			velocity = Vector2.ZERO
			_headhunter_timer -= delta
			if _headhunter_timer <= 0.0:
				_headhunter_state = "chase"


func _process_boss(delta: float) -> void:
	_process_boss_timers(delta)
	match _boss_state:
		"charge_prepare":
			velocity = Vector2.ZERO
			_boss_state_timer -= delta
			if _boss_state_timer <= 0.0:
				_boss_state = "charge"
				_boss_state_timer = BOSS_CHARGE_DISTANCE / max(1.0, _current_speed() * BOSS_CHARGE_SPEED_MULTIPLIER)
				_boss_dash_hit = false
		"charge":
			velocity = _boss_dash_direction * _current_speed() * BOSS_CHARGE_SPEED_MULTIPLIER
			move_and_slide()
			_try_path_hit(max(1, int(round(float(touch_damage) * 0.5))), _boss_dash_start, _boss_dash_end, BOSS_CHARGE_WIDTH, "_boss_dash_hit", true)
			_boss_state_timer -= delta
			if _boss_state_timer <= 0.0:
				_boss_state = "recover"
				_boss_state_timer = 0.7
				velocity = Vector2.ZERO
		"recover":
			velocity = Vector2.ZERO
			_boss_state_timer -= delta
			if _boss_state_timer <= 0.0:
				_boss_state = "chase"
		_:
			_process_chase(delta)


func _process_boss_timers(delta: float) -> void:
	_boss_charge_timer -= delta
	_boss_summon_timer -= delta
	_boss_crash_timer -= delta
	_boss_scan_timer -= delta
	_process_boss_bullets(delta)
	if _boss_charge_timer <= 0.0:
		_boss_charge_timer = 7.0
		_start_boss_charge()
	if _boss_summon_timer <= 0.0:
		_boss_summon_timer = 10.0
		_show_skill_label("召喚AI大軍")
		special_requested.emit(self, "summon_ai", global_position)
	if _boss_crash_timer <= 0.0:
		_boss_crash_timer = 15.0
		_show_skill_label("股災")
		special_requested.emit(self, "stock_crash", target.global_position)
	if _boss_scan_timer <= 0.0:
		_boss_scan_timer = 7.0
		_show_skill_label("掃瞄")
		special_requested.emit(self, "scan_laser", target.global_position)


func _start_boss_charge() -> void:
	if not is_instance_valid(target):
		return
	_show_skill_label("衝鋒")
	var to_target := target.global_position - global_position
	_boss_dash_direction = to_target.normalized() if to_target.length() > 0.001 else Vector2.RIGHT
	_boss_dash_start = global_position
	_boss_dash_end = _boss_dash_start + _boss_dash_direction * BOSS_CHARGE_DISTANCE
	_boss_state = "charge_prepare"
	_boss_state_timer = 0.8
	_boss_dash_hit = false
	special_requested.emit(self, "charge_line", target.global_position)


func _process_boss_bullets(delta: float) -> void:
	if not is_instance_valid(target):
		return
	if _boss_bullets_left <= 0:
		_boss_reload_timer -= delta
		if _boss_reload_timer <= 0.0:
			_boss_bullets_left = 50
			_boss_bullet_timer = 0.0
		return
	_boss_bullet_timer -= delta
	if _boss_bullet_timer > 0.0:
		return
	_boss_bullet_timer = 0.3
	_boss_bullets_left -= 1
	special_requested.emit(self, "boss_bullet", target.global_position)
	if _boss_bullets_left <= 0:
		_boss_reload_timer = 5.0


func _start_headhunter_dash_lock(direction: Vector2) -> void:
	velocity = Vector2.ZERO
	_headhunter_state = "lock"
	_headhunter_timer = 1.0
	_headhunter_dash_direction = direction
	_headhunter_dash_hit = false
	_headhunter_dash_start = global_position
	_headhunter_dash_end = _headhunter_dash_start + direction * HEADHUNTER_DASH_DISTANCE
	_headhunter_warning_clear_timer = -1.0
	_show_skill_label("獵頭突刺")
	_create_headhunter_warning_line()


func _start_headhunter_sweep() -> void:
	_headhunter_state = "sweep_prepare"
	_headhunter_timer = HEADHUNTER_SWEEP_PREPARE_TIME
	_show_skill_label("橫掃")
	_create_headhunter_sweep_ring()


func _finish_headhunter_sweep() -> void:
	_clear_headhunter_sweep_ring()
	_create_headhunter_sweep_flash()
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= HEADHUNTER_SWEEP_RADIUS:
		if target.has_method("take_damage"):
			target.take_damage(touch_damage)


func _create_headhunter_warning_line() -> void:
	_clear_headhunter_warning_line()
	var parent := get_parent()
	if parent == null:
		return
	_headhunter_warning_line = Line2D.new()
	_headhunter_warning_line.width = HEADHUNTER_DASH_WIDTH
	_headhunter_warning_line.default_color = Color(0.1, 1.0, 0.25, 0.5)
	_headhunter_warning_line.points = PackedVector2Array([_headhunter_dash_start, _headhunter_dash_end])
	parent.add_child(_headhunter_warning_line)


func _clear_headhunter_warning_line() -> void:
	if is_instance_valid(_headhunter_warning_line):
		_headhunter_warning_line.queue_free()
	_headhunter_warning_line = null


func _create_headhunter_sweep_ring() -> void:
	_clear_headhunter_sweep_ring()
	var parent := get_parent()
	if parent == null:
		return
	_headhunter_sweep_ring = _create_world_ring(global_position, HEADHUNTER_SWEEP_RADIUS, Color(0.1, 1.0, 0.25, 0.5), 8.0)
	parent.add_child(_headhunter_sweep_ring)


func _clear_headhunter_sweep_ring() -> void:
	if is_instance_valid(_headhunter_sweep_ring):
		_headhunter_sweep_ring.queue_free()
	_headhunter_sweep_ring = null


func _create_headhunter_sweep_flash() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring := _create_world_ring(global_position, HEADHUNTER_SWEEP_RADIUS, Color(0.2, 1.0, 0.35, 0.82), 10.0)
	parent.add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "modulate:a", 0.0, 0.22)
	tween.tween_callback(ring.queue_free)


func _create_world_ring(center: Vector2, radius: float, color: Color, width: float) -> Line2D:
	var ring := Line2D.new()
	ring.width = width
	ring.default_color = color
	ring.closed = true
	var points := PackedVector2Array()
	for index in range(72):
		var angle := TAU * float(index) / 72.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	ring.points = points
	return ring


func _try_dash_hit(damage_amount: int, radius: float, hit_flag: String, knockback := false) -> void:
	var already_hit := _headhunter_dash_hit if hit_flag == "_headhunter_dash_hit" else _boss_dash_hit
	if already_hit or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > radius:
		return
	if target.has_method("take_damage"):
		target.take_damage(damage_amount)
	if knockback:
		target.global_position += _boss_dash_direction * 72.0
	if hit_flag == "_headhunter_dash_hit":
		_headhunter_dash_hit = true
	else:
		_boss_dash_hit = true


func _try_path_hit(damage_amount: int, segment_start: Vector2, segment_end: Vector2, path_width: float, hit_flag: String, knockback := false) -> void:
	var already_hit := _headhunter_dash_hit if hit_flag == "_headhunter_dash_hit" else _boss_dash_hit
	if already_hit or not is_instance_valid(target):
		return
	if _distance_to_segment(target.global_position, segment_start, segment_end) > path_width * 0.5:
		return
	if target.has_method("take_damage"):
		target.take_damage(damage_amount)
	if knockback:
		target.global_position += _boss_dash_direction * 72.0
	if hit_flag == "_headhunter_dash_hit":
		_headhunter_dash_hit = true
	else:
		_boss_dash_hit = true


func _distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(segment_start)
	var t: float = clamp((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * t)


func scale_combat_stats(multiplier: float) -> void:
	max_health = int(round(max_health * multiplier))
	health = min(max_health, max(1, int(round(float(health) * multiplier))))
	touch_damage = max(1, int(round(float(touch_damage) * multiplier)))


func scale_stats(multiplier: float) -> void:
	scale_combat_stats(multiplier)
	xp_value = int(round(xp_value * multiplier))


func apply_slow(multiplier: float, duration: float) -> void:
	_slow_multiplier = clamp(multiplier, 0.1, 1.0)
	_slow_timer = max(_slow_timer, duration)


func _current_speed() -> float:
	return speed * _slow_multiplier


func _show_skill_label(text: String) -> void:
	_skill_label_text = text
	_skill_label_timer = 2.0
	queue_redraw()


func take_damage(amount: int) -> void:
	health -= amount
	damaged.emit(enemy_kind, amount)
	_hit_flash_timer = 0.08
	queue_redraw()

	if health <= 0:
		died.emit(global_position, xp_value, enemy_kind)
		queue_free()


func _draw() -> void:
	var color := Color(0.95, 0.2, 0.16)
	if enemy_kind == "elite":
		color = Color(0.85, 0.22, 1.0)
	elif enemy_kind == "headhunter":
		color = Color(0.12, 0.95, 0.28)
	elif enemy_kind == "boss" or enemy_kind == "small_boss":
		color = Color(1.0, 0.55, 0.08)
	elif enemy_kind == "stage_boss":
		color = Color(0.95, 0.05, 0.05)
	if _hit_flash_timer > 0.0:
		color = Color(1.0, 0.9, 0.65)

	var body_radius := 14.0
	if enemy_kind == "elite":
		body_radius = 18.0
	elif enemy_kind == "headhunter":
		body_radius = HEADHUNTER_BODY_RADIUS
	elif enemy_kind == "boss" or enemy_kind == "small_boss":
		body_radius = BOSS_BODY_RADIUS
	elif enemy_kind == "stage_boss":
		body_radius = 36.0

	if enemy_kind == "headhunter":
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -body_radius),
			Vector2(body_radius * 0.9, body_radius * 0.72),
			Vector2(-body_radius * 0.9, body_radius * 0.72)
		]), color)
		draw_string(ThemeDB.fallback_font, Vector2(-22.0, -34.0), "獵頭", HORIZONTAL_ALIGNMENT_LEFT, 48.0, 14, Color(0.85, 1.0, 0.85))
	else:
		draw_circle(Vector2.ZERO, body_radius, color)
		draw_circle(Vector2(-4.0, -3.0), 3.0, Color(0.22, 0.04, 0.04))
		draw_circle(Vector2(4.0, -3.0), 3.0, Color(0.22, 0.04, 0.04))
		if enemy_kind == "boss":
			draw_string(ThemeDB.fallback_font, Vector2(-18.0, -44.0), "boss", HORIZONTAL_ALIGNMENT_LEFT, 48.0, 14, Color(1.0, 0.88, 0.5))

	var health_ratio: float = clamp(float(health) / float(max_health), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-16.0, -25.0), Vector2(32.0, 4.0)), Color(0.18, 0.02, 0.02))
	draw_rect(Rect2(Vector2(-16.0, -25.0), Vector2(32.0 * health_ratio, 4.0)), Color(0.4, 1.0, 0.32))
	if _skill_label_timer > 0.0 and not _skill_label_text.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(-44.0, -52.0), _skill_label_text, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 16, Color(1.0, 0.92, 0.2))
