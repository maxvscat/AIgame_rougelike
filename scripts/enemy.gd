extends CharacterBody2D

signal died(enemy: Node2D)
signal attack_projectile_requested(origin: Vector2, target_position: Vector2, speed: float)
signal dot_damage_occurred(pos: Vector2, amount: float)

const TILE_SIZE := 64.0

var target: Node2D
var enemy_id := "retail"
var display_name := "散戶"
var max_health := 4.0
var health := 4.0
var move_speed := 82.0
var attack_type := "melee"
var attack_range_tiles := 1.0
var attacks_per_second := 0.25
var contact_radius := 28.0
var scale_multiplier := 1.0
var skill_id := ""
var skill_cd := 0.0
var skill_timer := 0.0
var active := true

var _attack_timer := 0.0
var _hit_flash_timer := 0.0
var _slow_timer := 0.0
var _slow_multiplier := 1.0
var _burn_ticks := []
var _poison_ticks := []
var _jump_state := "chase"     # "chase" | "prepare" | "landing"（耗客跳砍用）
var _jump_timer := 0.0
var _jump_target := Vector2.ZERO
var _warning_node: Node2D
var _texture: Texture2D
var _font: Font

# ── 近戰攻擊狀態機 ──────────────────────────────────────────────────────────
# chase → charge → lunge → recovery → chase
var _ma_state := "chase"
var _ma_timer := 0.0
var _ma_attack_dir := Vector2.ZERO   # 集氣時鎖定的攻擊方向（世界空間）
var _ma_lunge_end := Vector2.ZERO    # 衝刺終點（世界空間）
var _ma_hit_done := false            # 本次衝刺是否已判定傷害

# 近戰攻擊參數（由 _setup_melee_params() 依怪物設定）
var _ma_charge_time   := 0.6    # 集氣時間（秒）
var _ma_range_tiles   := 1.2    # 攻擊到達距離（格）── 判定範圍
var _ma_width_tiles   := 0.8    # 矩形攻擊寬度（格）── 僅 rect 使用
var _ma_lunge_tiles   := 1.0    # 衝刺前進距離（格）
var _ma_recovery_time := 0.4    # 攻擊後硬直（秒）
var _ma_shape         := "rect" # 攻擊形狀："rect" | "fan" | "circle"
var _ma_fan_angle     := 120.0  # 扇形角度（度）── 僅 fan 使用

# 技能集氣（鋁布橫掃 / 其他需要蓄力的技能）
var _skill_charging := false
var _skill_charge_timer := 0.0
var _skill_charge_max := 1.5
var _skill_charge_callback := Callable()


func _ready() -> void:
	add_to_group("enemies")
	_font = load("res://AIgame_rougelike/assets/fonts/MaokenAssortedSans-TC.otf") if ResourceLoader.exists("res://AIgame_rougelike/assets/fonts/MaokenAssortedSans-TC.otf") else load("res://AIgame_rougelike/assets/fonts/NotoSansCJKtc-Regular.otf")
	_load_texture()
	health = max_health
	skill_timer = randf_range(1.0, max(1.2, skill_cd))


func setup(def: Dictionary, player: Node2D, power_multiplier := 1.0) -> void:
	target = player
	enemy_id    = str(def.get("id",          "retail"))
	display_name= str(def.get("name",        "敵人"))
	max_health  = float(def.get("hp",  4.0)) * power_multiplier
	health      = max_health
	move_speed  = float(def.get("speed", 82.0))
	attack_type = str(def.get("attack_type", "melee"))
	attack_range_tiles = float(def.get("range", 1.0))
	attacks_per_second = float(def.get("aps",   0.25))
	skill_id    = str(def.get("skill",    ""))
	skill_cd    = float(def.get("skill_cd", 0.0))
	scale_multiplier = float(def.get("scale", 1.0))
	contact_radius   = 18.0 * scale_multiplier
	# 動態更新 CollisionShape2D 半徑
	var _col := get_node_or_null("CollisionShape2D")
	if _col != null and _col.shape is CircleShape2D:
		_col.shape.radius = 10.5 * scale_multiplier
	_setup_melee_params()
	_load_texture()
	queue_redraw()


func _setup_melee_params() -> void:
	# 根據 enemy_id 設定各近戰怪的攻擊參數
	match enemy_id:
		"retail":
			_ma_charge_time   = 0.6
			_ma_range_tiles   = 1.2
			_ma_width_tiles   = 0.8
			_ma_lunge_tiles   = 1.0
			_ma_recovery_time = 0.4
			_ma_shape         = "rect"
		"friend":
			_ma_charge_time   = 0.5
			_ma_range_tiles   = 1.4
			_ma_width_tiles   = 0.9
			_ma_lunge_tiles   = 2.0
			_ma_recovery_time = 0.3
			_ma_shape         = "rect"
		"aluminum":
			_ma_charge_time   = 0.8
			_ma_range_tiles   = 2.0
			_ma_width_tiles   = 2.0   # fan 不用 width，但保留備用
			_ma_lunge_tiles   = 5.0
			_ma_recovery_time = 0.5
			_ma_shape         = "fan"
			_ma_fan_angle     = 120.0
		"hacker":
			_ma_charge_time   = 0.45
			_ma_range_tiles   = 1.3
			_ma_width_tiles   = 0.8
			_ma_lunge_tiles   = 3.0
			_ma_recovery_time = 0.3
			_ma_shape         = "rect"
		"patriot":
			_ma_charge_time   = 0.7
			_ma_range_tiles   = 5.0
			_ma_width_tiles   = 1.5
			_ma_lunge_tiles   = 8.0
			_ma_recovery_time = 0.5
			_ma_shape         = "rect"
		"headhunter":
			_ma_charge_time   = 0.5
			_ma_range_tiles   = 1.5
			_ma_width_tiles   = 1.0
			_ma_lunge_tiles   = 3.0
			_ma_recovery_time = 0.4
			_ma_shape         = "rect"
		_:
			_ma_charge_time   = 0.6
			_ma_range_tiles   = 1.2
			_ma_width_tiles   = 0.8
			_ma_lunge_tiles   = 1.0
			_ma_recovery_time = 0.4
			_ma_shape         = "rect"


func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(target) or health <= 0.0:
		return
	_process_status(delta)
	if _jump_state != "chase":
		_process_jump(delta)
	else:
		# 技能集氣（鋁布橫掃等）
		if _skill_charging:
			_skill_charge_timer += delta
			queue_redraw()
			if _skill_charge_timer >= _skill_charge_max and _skill_charge_callback.is_valid():
				_skill_charge_callback.call()
		_process_movement_and_attack(delta)
		if not _skill_charging:
			_process_skill(delta)
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		queue_redraw()


func _process_movement_and_attack(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	var distance  := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector2.RIGHT

	# ── 遠程怪：移動 + 射擊，無接觸傷害 ──────────────────────────
	if attack_type == "ranged":
		var attack_range := attack_range_tiles * TILE_SIZE
		if distance > max(attack_range * 0.86, contact_radius + 12.0):
			velocity = direction * move_speed * _slow_multiplier
		else:
			velocity = Vector2.ZERO
		move_and_slide()
		_attack_timer = max(_attack_timer - delta, 0.0)
		if distance <= attack_range and _attack_timer <= 0.0:
			_attack_timer = 1.0 / max(0.05, attacks_per_second)
			attack_projectile_requested.emit(global_position, target.global_position, move_speed * 1.95)
		return

	# ── 近戰狀態機 chase → charge → lunge → recovery ──────────────
	# 觸發集氣距離 = (衝刺格 + 攻擊格) × TILE_SIZE × 0.9
	var trigger_dist := (_ma_lunge_tiles + _ma_range_tiles) * TILE_SIZE * 0.9

	match _ma_state:
		"chase":
			if _skill_charging:
				velocity = Vector2.ZERO
				move_and_slide()
				return
			# 追蹤玩家
			if distance > max(trigger_dist * 0.85, contact_radius + 8.0):
				velocity = direction * move_speed * _slow_multiplier
			else:
				velocity = Vector2.ZERO
			# 反黏附：距離過近時往外推，避免黏在玩家身上
			var repel_dist: float = contact_radius * 1.4
			if distance < repel_dist and distance > 0.5:
				var away: Vector2 = (global_position - target.global_position).normalized()
				velocity += away * move_speed * 0.5 * (1.0 - distance / repel_dist)
			move_and_slide()
			# 玩家進入觸發距離 → 開始集氣
			if distance <= trigger_dist and not _skill_charging:
				_ma_state     = "charge"
				_ma_timer     = 0.0
				_ma_attack_dir = direction   # 鎖定方向
				velocity      = Vector2.ZERO
				queue_redraw()

		"charge":
			# 原地集氣，面向鎖定方向，顯示攻擊預警
			velocity = Vector2.ZERO
			move_and_slide()
			_ma_timer += delta
			queue_redraw()
			if _ma_timer >= _ma_charge_time:
				_start_melee_lunge()

		"lunge":
			# 快速衝向鎖定終點
			var remaining   := _ma_lunge_end - global_position
			var lunge_speed := 800.0
			if remaining.length() <= lunge_speed * delta:
				global_position = _ma_lunge_end
				# 衝刺到位：判定是否擊中
				if not _ma_hit_done and _check_melee_hit():
					_ma_hit_done = true
					if is_instance_valid(target):
						target.take_damage(1)
				_ma_state = "recovery"
				_ma_timer = 0.0
				velocity  = Vector2.ZERO
			else:
				velocity = remaining.normalized() * lunge_speed
			move_and_slide()
			queue_redraw()

		"recovery":
			# 攻擊後硬直：同樣加反黏附
			var rdist: float = global_position.distance_to(target.global_position)
			var rrepel: float = contact_radius * 1.2
			if rdist < rrepel and rdist > 0.5:
				var raway: Vector2 = (global_position - target.global_position).normalized()
				velocity = raway * move_speed * 0.3
			else:
				velocity = Vector2.ZERO
			move_and_slide()
			_ma_timer += delta
			if _ma_timer >= _ma_recovery_time:
				_ma_state = "chase"
			queue_redraw()


func _start_melee_lunge() -> void:
	_ma_state    = "lunge"
	_ma_lunge_end = global_position + _ma_attack_dir * _ma_lunge_tiles * TILE_SIZE
	_ma_timer    = 0.0
	_ma_hit_done = false
	queue_redraw()


func _check_melee_hit() -> bool:
	# 判定玩家是否在攻擊形狀範圍內（以衝刺終點為基準）
	if not is_instance_valid(target):
		return false
	var rel      := target.global_position - global_position
	var range_px := _ma_range_tiles * TILE_SIZE
	var width_px := _ma_width_tiles * TILE_SIZE
	match _ma_shape:
		"rect":
			var fwd  := rel.dot(_ma_attack_dir)
			var perp: float = absf(rel.dot(_ma_attack_dir.rotated(PI * 0.5)))
			# 往後 16px 容忍（玩家剛好貼著怪時仍能判中）
			return fwd >= -16.0 and fwd <= range_px and perp <= width_px * 0.5
		"fan":
			if rel.length() > range_px:
				return false
			if rel.length() < 0.001:
				return true
			return abs(_ma_attack_dir.angle_to(rel.normalized())) <= deg_to_rad(_ma_fan_angle * 0.5)
		"circle":
			return rel.length() <= range_px
	return false


func apply_knockback(direction: Vector2, distance: float) -> void:
	# 被擊退打斷集氣 / 衝刺
	if _ma_state == "charge" or _ma_state == "lunge":
		_ma_state = "chase"
		_ma_timer = 0.0
	global_position += direction.normalized() * distance


func _process_skill(delta: float) -> void:
	if skill_id.is_empty() or skill_cd <= 0.0:
		return
	skill_timer -= delta
	if skill_timer > 0.0:
		return
	skill_timer = skill_cd
	match skill_id:
		"speed_burst":
			_speed_burst()
		"summon_retail":
			get_parent().call_deferred("_spawn_wave_enemy", "retail",
				global_position + Vector2(randf_range(-48.0, 48.0), randf_range(-48.0, 48.0)))
			get_parent().call_deferred("_spawn_wave_enemy", "retail",
				global_position + Vector2(randf_range(-48.0, 48.0), randf_range(-48.0, 48.0)))
		"sweep":
			_sweep_attack()
		"jump_slash":
			_start_jump_slash()
		"laser":
			_fire_random_lasers()


func _speed_burst() -> void:
	# 街友：移動速度 +100%，持續 2 秒
	var old_speed := move_speed
	move_speed *= 2.0
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(func() -> void:
		move_speed = old_speed
	)


func _sweep_attack() -> void:
	# 鋁布橫掃一圈技能：0.8 秒預警圓 → 對 2 格範圍造成傷害
	_skill_charging     = true
	_skill_charge_timer = 0.0
	_skill_charge_max   = 0.8
	_skill_charge_callback = func() -> void:
		_skill_charging     = false
		_skill_charge_timer = 0.0
		_skill_charge_callback = Callable()
		_spawn_circle_warning(global_position, 2.0 * TILE_SIZE,
			Color(1.0, 0.2, 0.2, 0.5), 0.2,
			func() -> void:
				if is_instance_valid(target) and \
						global_position.distance_to(target.global_position) <= 2.0 * TILE_SIZE:
					target.take_damage(1)
		)
		queue_redraw()


func _start_jump_slash() -> void:
	# 耗客跳砍技能
	# 觸發條件：玩家 5 格內；同時最多 4 隻進行跳砍
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > 5.0 * TILE_SIZE:
		return
	if get_tree().get_nodes_in_group("jumping_enemies").size() >= 4:
		return
	add_to_group("jumping_enemies")
	# 中斷普攻
	_ma_state = "chase"
	_ma_timer = 0.0
	_jump_state = "prepare"
	_jump_timer = 2.0
	# 鎖定玩家當下位置的隨機 2 格範圍
	var angle := randf_range(0.0, TAU)
	var dist  := randf_range(0.0, 2.0) * TILE_SIZE
	_jump_target = target.global_position + Vector2(cos(angle), sin(angle)) * dist
	_spawn_circle_warning(_jump_target, 2.0 * TILE_SIZE,
		Color(1.0, 0.1, 0.1, 0.5), 2.0, func() -> void: pass)


func _process_jump(delta: float) -> void:
	if _jump_state == "prepare":
		velocity = Vector2.ZERO
		move_and_slide()
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			_jump_state = "landing"
			_jump_timer = 0.2
			global_position = _jump_target
			if is_instance_valid(target) and \
					global_position.distance_to(target.global_position) <= 2.0 * TILE_SIZE:
				target.take_damage(1)
	elif _jump_state == "landing":
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			remove_from_group("jumping_enemies")
			_jump_state = "chase"


func _fire_random_lasers() -> void:
	for _i in range(2):
		var angle := randf_range(0.0, TAU)
		var start := global_position
		var end   := start + Vector2.RIGHT.rotated(angle) * 16.0 * TILE_SIZE
		_spawn_line_warning(start, end, 34.0, Color(1.0, 0.05, 0.05, 0.5), 1.0,
			func() -> void:
				if is_instance_valid(target) and \
						_distance_to_segment(target.global_position, start, end) <= 34.0:
					target.take_damage(1)
		)


func _process_status(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_multiplier = 1.0
	for index in range(_burn_ticks.size() - 1, -1, -1):
		var tick: Dictionary = _burn_ticks[index]
		tick["timer"] = float(tick["timer"]) - delta
		tick["tick"]  = float(tick["tick"])  - delta
		if float(tick["tick"]) <= 0.0:
			tick["tick"] = 1.0
			var burn_amount := float(tick["damage"])
			take_damage(burn_amount)
			dot_damage_occurred.emit(global_position, burn_amount)
		if float(tick["timer"]) <= 0.0:
			_burn_ticks.remove_at(index)
		else:
			_burn_ticks[index] = tick
	for index in range(_poison_ticks.size() - 1, -1, -1):
		var tick: Dictionary = _poison_ticks[index]
		tick["timer"] = float(tick["timer"]) - delta
		tick["tick"]  = float(tick["tick"])  - delta
		if float(tick["tick"]) <= 0.0:
			tick["tick"] = 1.0
			var poison_amount := float(tick["damage"])
			take_damage(poison_amount)
			dot_damage_occurred.emit(global_position, poison_amount)
		if float(tick["timer"]) <= 0.0:
			_poison_ticks.remove_at(index)
		else:
			_poison_ticks[index] = tick


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health -= amount
	_hit_flash_timer = 0.08
	queue_redraw()
	if health <= 0.0:
		died.emit(self)
		queue_free()


func apply_slow(multiplier: float, duration: float) -> void:
	_slow_multiplier = min(_slow_multiplier, multiplier)
	_slow_timer      = max(_slow_timer, duration)


func apply_burn(damage: float, duration: float) -> void:
	_burn_ticks.append({"damage": damage, "timer": duration, "tick": 1.0})


func apply_poison(damage: float, duration: float) -> void:
	if _poison_ticks.size() >= 3:
		_poison_ticks.pop_front()
	_poison_ticks.append({"damage": damage, "timer": duration, "tick": 1.0})
	apply_slow(0.85, duration)


# ── 場景警告圖形 ─────────────────────────────────────────────────────────────

func _spawn_circle_warning(center: Vector2, radius: float, color: Color,
		delay: float, callback: Callable) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring := Line2D.new()
	ring.closed = true
	ring.width  = 5.0
	ring.default_color = color
	var points := PackedVector2Array()
	for i in range(72):
		points.append(center + Vector2(cos(TAU * i / 72.0), sin(TAU * i / 72.0)) * radius)
	ring.points = points
	parent.add_child(ring)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		if callback.is_valid():
			callback.call()
		if is_instance_valid(ring):
			ring.queue_free()
	)


func _spawn_line_warning(start: Vector2, end: Vector2, width: float, color: Color,
		delay: float, callback: Callable) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var line := Line2D.new()
	line.width         = width
	line.default_color = color
	line.points        = PackedVector2Array([start, end])
	parent.add_child(line)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		if callback.is_valid():
			callback.call()
		if is_instance_valid(line):
			line.queue_free()
	)


func _distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment        := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(segment_start)
	var t: float = clamp((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * t)


# ── 攻擊預警形狀（本地座標，跟隨敵人）────────────────────────────────────────

func _rect_warning_points(dir: Vector2, length: float, width: float) -> PackedVector2Array:
	var perp   := dir.rotated(PI * 0.5)
	var half_w := width * 0.5
	return PackedVector2Array([
		perp * half_w,
		dir * length + perp * half_w,
		dir * length - perp * half_w,
		-perp * half_w
	])


func _fan_warning_points(dir: Vector2, radius: float, angle_deg: float) -> PackedVector2Array:
	var pts        := PackedVector2Array()
	pts.append(Vector2.ZERO)
	var half_rad   := deg_to_rad(angle_deg * 0.5)
	var base_angle := dir.angle()
	var steps      := 24
	for i in range(steps + 1):
		var a := base_angle - half_rad + deg_to_rad(angle_deg) * float(i) / float(steps)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _load_texture() -> void:
	var path := "res://AIgame_rougelike/assets/art/enemies/%s/%s.png"
	match enemy_id:
		"friend":
			_texture = load(path % ["friend",     "friend"])
		"shooter":
			_texture = load(path % ["shooter",    "shooter"])
		"hoodlum":
			_texture = load(path % ["hoodlum",    "hoodlum"])
		"aluminum":
			_texture = load(path % ["aluminum",   "aluminum"])
		"hacker":
			_texture = load(path % ["hacker",     "hacker"])
		"patriot":
			_texture = load(path % ["patriot",    "patriot"])
		"headhunter":
			_texture = load("res://AIgame_rougelike/assets/art/enemies/headhunter/green_triangle.png")
		"boss_mid", "boss_final":
			_texture = load("res://AIgame_rougelike/assets/art/enemies/boss/orange_market_crash_core.png")
		_:
			_texture = load(path % ["retail", "retail"])


func _draw() -> void:
	var radius := 16.0 * scale_multiplier
	var tint   := Color.WHITE
	if _hit_flash_timer > 0.0:
		tint = Color(1.0, 0.88, 0.72)

	# 角色圖像
	if _texture != null:
		var size := radius * 3.0
		draw_texture_rect(_texture,
			Rect2(Vector2(-size * 0.5, -size * 0.5), Vector2(size, size)), false, tint)
	else:
		draw_circle(Vector2.ZERO, radius, Color(0.95, 0.2, 0.16))

	# 名稱標籤
	if _font != null:
		draw_string(_font, Vector2(-34, -radius - 22), display_name,
			HORIZONTAL_ALIGNMENT_CENTER, 68, 13, Color(1, 1, 1))

	# 血量條
	var ratio: float = clamp(health / max(0.001, max_health), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-22, -radius - 10), Vector2(44, 4)), Color(0.18, 0.02, 0.02))
	draw_rect(Rect2(Vector2(-22, -radius - 10), Vector2(44.0 * ratio, 4)), Color(0.35, 1.0, 0.3))

	# ── 攻擊預警（集氣 / 衝刺期間，以本地座標顯示在地板上）──────────────
	if attack_type == "melee" and \
			(_ma_state == "charge" or _ma_state == "lunge") and \
			_ma_attack_dir.length() > 0.001:
		var charge_ratio: float
		if _ma_state == "charge":
			charge_ratio = clamp(_ma_timer / max(0.001, _ma_charge_time), 0.0, 1.0)
		else:
			charge_ratio = 1.0
		var preview_alpha: float = lerpf(0.18, 0.50, charge_ratio)
		var fill_col: Color = Color(1.0, 0.15, 0.15, preview_alpha)
		var edge_col: Color = Color(1.0, 0.10, 0.10, minf(preview_alpha * 1.6, 0.85))
		var range_px  := _ma_range_tiles * TILE_SIZE
		var width_px  := _ma_width_tiles * TILE_SIZE
		match _ma_shape:
			"rect":
				var pts := _rect_warning_points(_ma_attack_dir, range_px, width_px)
				draw_colored_polygon(pts, fill_col)
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
					edge_col, 2.0)
			"fan":
				var pts := _fan_warning_points(_ma_attack_dir, range_px, _ma_fan_angle)
				draw_colored_polygon(pts, fill_col)
				draw_polyline(pts, edge_col, 2.0, true)
			"circle":
				draw_circle(Vector2.ZERO, range_px, fill_col)
				draw_arc(Vector2.ZERO, range_px, 0.0, TAU, 64, edge_col, 2.0)

	# ── 集氣條（攻擊集氣 / 技能集氣）─────────────────────────────────────
	var charge_pct  := 0.0
	var show_charge := false
	if _ma_state == "charge" and _ma_charge_time > 0.0:
		charge_pct  = _ma_timer / _ma_charge_time
		show_charge = true
	elif _ma_state == "lunge":
		charge_pct  = 1.0
		show_charge = true
	elif _skill_charging and _skill_charge_max > 0.0:
		charge_pct  = _skill_charge_timer / _skill_charge_max
		show_charge = true
	if show_charge:
		draw_rect(Rect2(Vector2(-22, -radius - 20), Vector2(44, 6)),
			Color(0.08, 0.08, 0.08, 0.8))
		draw_rect(Rect2(Vector2(-22, -radius - 20),
			Vector2(44.0 * clamp(charge_pct, 0.0, 1.0), 6)),
			Color(1.0, 0.78, 0.08, 0.95))
