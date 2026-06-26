extends CharacterBody2D

signal stats_changed
signal died
signal attack_requested(origin: Vector2, target_position: Vector2, attack_data: Dictionary)
signal area_preview_changed(center: Vector2, radius: float, visible: bool)
signal wall_blocked(pos: Vector2)

const TILE_SIZE := 64.0
const MAX_HEALTH := 5

var class_id := "warrior"
var character_name := "戰士"
var speed := 260.0
var max_health := MAX_HEALTH
var health := MAX_HEALTH
var attack_damage := 2.0
var attack_range_tiles := 2.0
var attacks_per_second := 2.0
var attack_mode := "cone"
var crit_chance := 0.0
var skill_area_bonus := 0.0
var selected_skills: Dictionary = {}
var level := 1

var invincible_timer := 0.0
var _wall_cd := 0.0        # 門清盾牌冷卻
var _attack_timer := 0.0
var _heal_pending := false
var _heal_timer := 0.0
var _held_attack := false
var _aim_position := Vector2.ZERO
var _player_texture: Texture2D
var _dash_cooldown_timer := 0.0
var _dash_timer := 0.0
var _dash_direction := Vector2.RIGHT
var _last_move_direction := Vector2.RIGHT
var _attack_move_lock := 0.0     # 攻擊後短暫鎖定移動

# ── 動畫系統 ──
var _anim_state := "idle"      # idle | walk | charge | attack | cast
var _anim_dir := "d"           # d u l r dl dr ul ur
var _anim_frame := 0           # 走路幀 0-3
var _anim_frame_timer := 0.0
var _anim_override_timer := 0.0  # attack / cast 持續時間倒計時

# 戰士集氣（0.3s 延遲才打出傷害）
var _warrior_charging := false
var _warrior_charge_timer := 0.0
var _warrior_pending_data: Dictionary = {}

# 戰士動畫紋理快取
var _wt_idle: Texture2D
var _wt_charge: Texture2D
var _wt_attack: Texture2D
var _wt_cast: Texture2D
var _wt_walk: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 3
	_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/player_core.png")
	health = max_health
	stats_changed.emit()


func setup_character(id: String) -> void:
	class_id = id
	match id:
		"archer":
			_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/archer.png")
			character_name = "弓手"
			attack_damage = 1.0
			attack_range_tiles = 5.0
			attacks_per_second = 3.0
			attack_mode = "single"
			crit_chance = 0.10
			skill_area_bonus = 0.0
		"mage":
			_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/mage.png")
			character_name = "法師"
			attack_damage = 1.0
			attack_range_tiles = 5.0
			attacks_per_second = 0.5
			attack_mode = "area"
			crit_chance = 0.0
			skill_area_bonus = 0.20
		_:  # warrior
			_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/warrior.png")
			character_name = "戰士"
			attack_damage = 2.0
			attack_range_tiles = 3.0
			attacks_per_second = 1.0
			attack_mode = "cone"
			crit_chance = 0.0
			skill_area_bonus = 0.0
			_load_warrior_textures()
	max_health = MAX_HEALTH
	health = max_health
	selected_skills.clear()
	level = 1
	invincible_timer = 0.0
	_attack_timer = 0.0
	_heal_pending = false
	_heal_timer = 0.0
	_dash_cooldown_timer = 0.0
	_dash_timer = 0.0
	_dash_direction = Vector2.RIGHT
	_last_move_direction = Vector2.RIGHT
	_attack_move_lock = 0.0
	_wall_cd = 0.0
	_anim_state = "idle"
	_anim_dir = "d"
	_anim_frame = 0
	_warrior_charging = false
	_warrior_charge_timer = 0.0
	stats_changed.emit()
	queue_redraw()


func _load_warrior_textures() -> void:
	var base: String = "res://AIgame_rougelike/assets/art/characters/player/warrior/"
	var walk_base: String = base + "warrior_walk/"

	_wt_idle = _try_load(base + "idle.png")
	_wt_charge = _try_load(base + "charge.png")
	_wt_attack = _try_load(base + "attack.png")
	_wt_cast = _try_load(base + "cast.png")

	for direc: String in ["d", "u", "l", "r", "dl", "dr", "ul", "ur"]:
		var frames: Array[Texture2D] = []

		for f: int in range(1, 10):
			var path: String = walk_base + "walk_%s_%02d.png" % [direc, f]
			var tex: Texture2D = _try_load(path)

			if tex != null:
				frames.append(tex)

		_wt_walk[direc] = frames


func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _physics_process(delta: float) -> void:
	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length() > 0.001:
		_last_move_direction = input_direction.normalized()
	_wall_cd = maxf(_wall_cd - delta, 0.0)
	_attack_move_lock = maxf(_attack_move_lock - delta, 0.0)
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_direction * speed * 3.2
		collision_mask = 1   # dash 穿越敵人
	else:
		collision_mask = 3
		if _held_attack or _attack_move_lock > 0.0 or _warrior_charging:
			velocity = Vector2.ZERO
		else:
			velocity = input_direction * speed
	move_and_slide()

	invincible_timer = max(invincible_timer - delta, 0.0)
	if _heal_pending:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_pending = false
			if health > 0 and health < max_health:
				health += 1
				stats_changed.emit()

	_attack_timer = max(_attack_timer - delta, 0.0)
	_aim_position = get_global_mouse_position()
	_held_attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if attack_mode == "area":
		var radius: float = get_mage_area_radius()
		area_preview_changed.emit(_aim_position, radius, true)
	else:
		area_preview_changed.emit(Vector2.ZERO, 0.0, false)

	# ── 戰士集氣處理 ──
	if _warrior_charging:
		_warrior_charge_timer -= delta
		if _warrior_charge_timer <= 0.0:
			_warrior_charging = false
			_attack_move_lock = 0.2
			if not _warrior_pending_data.is_empty():
				attack_requested.emit(global_position, _warrior_pending_data["target"], _warrior_pending_data["data"])
				_warrior_pending_data.clear()
			_anim_override_timer = 0.25
			_anim_state = "attack"

	# ── 攻擊觸發 ──
	if _held_attack and _attack_timer <= 0.0:
		var interval: float = 1.0 / max(0.05, attacks_per_second)
		_attack_timer = interval
		if class_id == "warrior" and not _warrior_charging:
			_warrior_charging = true
			_warrior_charge_timer = 0.3
			_anim_state = "charge"
			var tgt_pos: Vector2 = _aim_position
			if global_position.distance_to(tgt_pos) > get_attack_range():
				tgt_pos = global_position + global_position.direction_to(tgt_pos) * get_attack_range()
			_warrior_pending_data = {
				"target": tgt_pos,
				"data": {
					"damage": attack_damage,
					"mode": attack_mode,
					"range": get_attack_range(),
					"cone_angle": 90.0,
					"area_radius": get_mage_area_radius(),
					"crit_chance": crit_chance,
					"skills": selected_skills.duplicate(true)
				}
			}
		else:
			_request_attack()
			_attack_move_lock = 0.2
			if class_id != "warrior":
				_anim_override_timer = 0.2
				_anim_state = "attack"

	# ── 更新動畫狀態 ──
	_update_animation(delta, input_direction)

	queue_redraw()


func _update_animation(delta: float, input_dir: Vector2) -> void:
	if _anim_override_timer > 0.0:
		_anim_override_timer -= delta
		if _anim_override_timer <= 0.0 and _anim_state in ["attack", "cast"]:
			_anim_state = "idle"
		return

	if _warrior_charging:
		_anim_state = "charge"
		return

	if input_dir.length() > 0.001:
		_anim_dir = _vec_to_dir(input_dir)

	if velocity.length() > 10.0:
		_anim_state = "walk"
		_anim_frame_timer += delta
		if _anim_frame_timer >= 0.11:
			_anim_frame_timer = 0.0
			_anim_frame = (_anim_frame + 1) % 9
	else:
		_anim_state = "idle"
		_anim_frame = 0
		_anim_frame_timer = 0.0


func _vec_to_dir(v: Vector2) -> String:
	var angle := v.angle()
	var octant := int(round(angle / (PI / 4.0))) % 8
	match octant:
		0:       return "r"
		1:       return "dr"
		2:       return "d"
		3:       return "dl"
		4, -4:   return "l"
		-3:      return "ul"
		-2:      return "u"
		-1:      return "ur"
		_:       return "d"


func trigger_cast_animation() -> void:
	_anim_state = "cast"
	_anim_override_timer = 0.5


func request_dash() -> void:
	if health <= 0 or _dash_cooldown_timer > 0.0 or _dash_timer > 0.0:
		return
	_dash_direction = _last_move_direction
	_dash_timer = 0.14
	_dash_cooldown_timer = 1.0


func _request_attack() -> void:
	var interval: float = 1.0 / max(0.05, attacks_per_second)
	_attack_timer = interval
	var target_position: Vector2 = _aim_position
	if global_position.distance_to(target_position) > get_attack_range():
		target_position = global_position + global_position.direction_to(target_position) * get_attack_range()
	var data: Dictionary = {
		"damage": attack_damage,
		"mode": attack_mode,
		"range": get_attack_range(),
		"cone_angle": 90.0,
		"area_radius": get_mage_area_radius(),
		"crit_chance": crit_chance,
		"skills": selected_skills.duplicate(true)
	}
	attack_requested.emit(global_position, target_position, data)


func take_damage(_amount := 1) -> void:
	if health <= 0 or invincible_timer > 0.0:
		return
	# 門清：盾牌格擋（不影響 invincible_timer，獨立冷卻）
	var wall_lv: int = get_skill_level("mahjong_wall")
	if wall_lv > 0 and _wall_cd <= 0.0:
		var wall_cd_table: Array = [0, 6.0, 5.0, 4.0, 3.0, 2.5, 2.0]
		_wall_cd = float(wall_cd_table[wall_lv])
		wall_blocked.emit(global_position)
		return
	health = max(health - 1, 0)
	invincible_timer = 0.8
	if class_id == "warrior" and health > 0:
		_heal_pending = true
		_heal_timer = 60.0
	stats_changed.emit()
	queue_redraw()
	if health <= 0:
		died.emit()


func get_attack_range() -> float:
	return attack_range_tiles * TILE_SIZE


func get_mage_area_radius() -> float:
	return 3.0 * TILE_SIZE * (1.0 + skill_area_bonus)


func grant_skill(skill_id: String) -> bool:
	var current: int = int(selected_skills.get(skill_id, 0))
	if current >= 6:
		return false
	if current == 0 and selected_skills.size() >= 5:
		return false
	selected_skills[skill_id] = current + 1
	stats_changed.emit()
	return true


func has_skill_capacity_for(skill_id: String) -> bool:
	return selected_skills.has(skill_id) or selected_skills.size() < 5


func get_skill_level(skill_id: String) -> int:
	return int(selected_skills.get(skill_id, 0))


func set_skill_level_direct(skill_id: String, lv: int) -> void:
	if lv <= 0:
		selected_skills.erase(skill_id)
	else:
		selected_skills[skill_id] = clamp(lv, 1, 6)
	stats_changed.emit()


func _draw() -> void:
	var alpha: float = 1.0
	if invincible_timer > 0.0:
		alpha = 0.35 if int(invincible_timer * 16.0) % 2 == 0 else 1.0
	var tint := Color(1, 1, 1, alpha)
	var dest := Rect2(Vector2(-56, -64), Vector2(112, 128))

	var tex: Texture2D = _player_texture
	var flip_h := false

	if class_id == "warrior" and _wt_idle != null:
		match _anim_state:
			"charge":
				tex = _wt_charge if _wt_charge != null else _wt_idle
			"attack":
				tex = _wt_attack if _wt_attack != null else _wt_idle
			"cast":
				tex = _wt_cast if _wt_cast != null else _wt_idle
			"walk":
				var dir_key := _get_cardinal_dir(_anim_dir)
				flip_h = _anim_dir in ["l", "dl", "ul"]  # walk_r 朝右，向左翻轉
				var frames: Array = _wt_walk.get(dir_key, [])
				var f: int = _anim_frame % max(1, frames.size())
				if frames.size() > 0 and frames[f] != null:
					tex = frames[f]
				else:
					tex = _wt_idle
			_:
				tex = _wt_idle

	if tex != null:
		if flip_h:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, dest, false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, dest, false, tint)
	else:
		draw_circle(Vector2.ZERO, 16.0, Color(0.2, 0.65, 1.0, alpha))

	var range_color: Color = Color(0.2, 0.65, 1.0, 0.14)
	draw_arc(Vector2.ZERO, get_attack_range(), 0.0, TAU, 96, range_color, 2.0)


func _get_cardinal_dir(dir: String) -> String:
	# warrior_walk 只有 d（正面）與 r（側面），左側由 r + flip_h 處理
	match dir:
		"r", "dr", "ur": return "r"
		"l", "dl", "ul": return "r"   # flip_h = true by caller
		"u":             return "d"   # 背面用正面代替
		_:               return "d"
