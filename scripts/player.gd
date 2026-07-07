extends CharacterBody2D

signal stats_changed
signal died
signal attack_requested(origin: Vector2, target_position: Vector2, attack_data: Dictionary)
signal area_preview_changed(center: Vector2, radius: float, visible: bool)
signal wall_blocked(pos: Vector2)

const TILE_SIZE := 64.0
const MAX_HEALTH := 5
const BALANCE_CONFIG_PATH := "res://AIgame_rougelike/data/balance_config.json"

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
var attack_move_multiplier := 0.0
var defense_chance := 0.0
var poker_dodge_chance := 0.0   # 命運紅心閃避率（main.gd 設定）
var poker_aps_mult := 1.0       # 疾風梅花攻速倍率（main.gd 設定）
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
var terrain_speed_multiplier := 1.0  # 地形效果移動倍率（泥沼減速/冰面加速），由 main.gd 每幀更新

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

# 槍手（原弓手，內部代號仍為 archer）動畫紋理快取
var _at_idle: Texture2D
var _at_attack: Array[Texture2D] = []
var _at_walk: Dictionary = {}
var _at_weapon: Texture2D  # 步槍疊圖：從 attack_01 與 idle 的差異區域抽出，讓待機/走路時也持續顯示武器

# 玩家攻擊範圍圈：改用獨立常駐節點（Line2D），不依賴 _draw()/queue_redraw() 的時機，
# 也不會被 main.gd 的 _clear_world_objects 等場景清理流程影響，只跟著玩家節點本身的生命週期。
var _range_ring: Line2D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 0
	_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/player_core.png")
	health = max_health
	_create_range_ring()
	stats_changed.emit()


func _create_range_ring() -> void:
	_range_ring = Line2D.new()
	_range_ring.name = "attack_range_ring"
	_range_ring.width = 2.0
	_range_ring.default_color = Color(0.2, 0.65, 1.0, 0.16)
	_range_ring.closed = true
	_range_ring.z_index = -1
	_range_ring.process_mode = Node.PROCESS_MODE_INHERIT
	add_child(_range_ring)
	_update_range_ring()


func _update_range_ring() -> void:
	if not is_instance_valid(_range_ring):
		return
	var r := get_attack_range()
	var pts := PackedVector2Array()
	for i in range(65):
		var a: float = TAU * float(i) / 64.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	_range_ring.points = pts


func setup_character(id: String) -> void:
	class_id = id
	speed = 260.0
	match id:
		"archer":
			_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/archer.png")
			character_name = "槍手"
			character_name = "槍手"
			attack_damage = 10.0
			attack_range_tiles = 5.0
			attacks_per_second = 3.0
			attack_mode = "single"
			crit_chance = 0.10
			skill_area_bonus = 0.0
			attack_move_multiplier = 0.2
			_load_archer_textures()
		"mage":
			_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/mage.png")
			character_name = "法師"
			character_name = "法師"
			attack_damage = 11.0
			attack_range_tiles = 5.0
			attacks_per_second = 0.5
			attack_mode = "area"
			crit_chance = 0.0
			skill_area_bonus = 0.20
			attack_move_multiplier = 0.0
		_:  # warrior
			_player_texture = load("res://AIgame_rougelike/assets/art/characters/player/warrior.png")
			character_name = "戰士"
			character_name = "戰士"
			attack_damage = 13.0
			attack_range_tiles = 3.0
			attacks_per_second = 1.0
			attack_mode = "cone"
			crit_chance = 0.0
			skill_area_bonus = 0.0
			attack_move_multiplier = 0.0
			_load_warrior_textures()
	_apply_character_balance(id)
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
	terrain_speed_multiplier = 1.0
	_wall_cd = 0.0
	defense_chance = 0.0
	_anim_state = "idle"
	_anim_dir = "d"
	_anim_frame = 0
	_warrior_charging = false
	_warrior_charge_timer = 0.0
	stats_changed.emit()
	queue_redraw()


func _apply_character_balance(id: String) -> void:
	if not FileAccess.file_exists(BALANCE_CONFIG_PATH):
		return
	var file := FileAccess.open(BALANCE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var characters: Dictionary = parsed.get("characters", {})
	if not characters.has(id):
		return
	var data: Dictionary = characters[id]
	character_name = str(data.get("name", character_name))
	speed = float(data.get("move_speed", speed))
	attack_damage = float(data.get("attack_damage", attack_damage))
	attack_range_tiles = float(data.get("attack_range_tiles", attack_range_tiles))
	attacks_per_second = float(data.get("attacks_per_second", attacks_per_second))
	crit_chance = float(data.get("crit_chance", crit_chance))
	skill_area_bonus = float(data.get("skill_area_bonus", skill_area_bonus))
	attack_move_multiplier = float(data.get("attack_move_multiplier", attack_move_multiplier))


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


func _load_archer_textures() -> void:
	var base: String = "res://AIgame_rougelike/assets/art/characters/player/archer/"

	_at_idle = _try_load(base + "idle.png")
	_at_weapon = _try_load(base + "weapon_overlay.png")

	_at_attack.clear()
	for f: int in range(1, 5):
		var atex: Texture2D = _try_load(base + "attack_%02d.png" % f)
		if atex != null:
			_at_attack.append(atex)

	_at_walk.clear()
	for direc: String in ["d", "r"]:
		var frames: Array[Texture2D] = []
		for f: int in range(1, 10):
			var tex: Texture2D = _try_load(base + "walk_%s_%02d.png" % [direc, f])
			if tex != null:
				frames.append(tex)
		_at_walk[direc] = frames


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
		collision_mask = 0
	else:
		collision_mask = 0
		if _held_attack or _attack_move_lock > 0.0 or _warrior_charging:
			if attack_move_multiplier > 0.0:
				velocity = input_direction * speed * attack_move_multiplier * terrain_speed_multiplier
			else:
				velocity = Vector2.ZERO
		else:
			velocity = input_direction * speed * terrain_speed_multiplier
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
	_held_attack = Input.is_action_pressed("attack")
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
		var interval: float = 1.0 / max(0.05, attacks_per_second * poker_aps_mult)
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
			if class_id == "archer":
				# 槍手：不用固定時長的 override_timer 一次性播放，
				# 改由 _update_animation 依 _held_attack 持續判斷，
				# 避免攻擊間隔 > 0.2 秒時animation 中途跳回 idle 再跳回 attack（一跳一跳的問題）。
				pass
			elif class_id != "warrior":
				_anim_override_timer = 0.2
				_anim_state = "attack"

	# ── 更新動畫狀態 ──
	_update_animation(delta, input_direction)
	_update_range_ring()

	queue_redraw()


func _update_animation(delta: float, input_dir: Vector2) -> void:
	if class_id == "archer" and _held_attack and not _warrior_charging:
		# 槍手按住攻擊鍵：只要持續按住，開火動畫就持續連續播放（不受實際射擊間隔影響），
		# 放開攻擊鍵才會回到 idle/walk，避免射擊間隔較長時動畫中途跳回 idle 造成的跳動感。
		_anim_state = "attack"
		_anim_override_timer = 0.0
		_anim_frame_timer += delta
		if _anim_frame_timer >= 0.07:
			_anim_frame_timer = 0.0
			_anim_frame += 1
		return

	if _anim_override_timer > 0.0:
		_anim_override_timer -= delta
		if _anim_state == "attack":
			# 攻擊動畫連續播放（例如槍手舉槍→開槍）
			_anim_frame_timer += delta
			if _anim_frame_timer >= 0.07:
				_anim_frame_timer = 0.0
				_anim_frame += 1
		if _anim_override_timer <= 0.0 and _anim_state in ["attack", "cast"]:
			_anim_state = "idle"
			_anim_frame = 0
			_anim_frame_timer = 0.0
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
	var interval: float = 1.0 / max(0.05, attacks_per_second * poker_aps_mult)
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
	# 命運紅心：閃避
	if poker_dodge_chance > 0.0 and randf() < poker_dodge_chance:
		invincible_timer = 0.15
		return
	if defense_chance > 0.0 and randf() < defense_chance:
		invincible_timer = 0.25
		stats_changed.emit()
		queue_redraw()
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
	var need_weapon_overlay := false

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
	elif class_id == "archer" and _at_idle != null:
		# 武器（步槍）疊圖：攻擊動畫本身已內建步槍+槍口火光，其餘狀態（待機/走路）
		# 另外疊上 _at_weapon，讓步槍隨時顯示，不會因為動畫狀態而消失。
		need_weapon_overlay = true
		match _anim_state:
			"attack":
				need_weapon_overlay = false
				flip_h = _anim_dir in ["l", "dl", "ul"]
				if _at_attack.size() > 0:
					var af: int = _anim_frame % _at_attack.size()
					tex = _at_attack[af]
				else:
					tex = _at_idle
			"walk":
				var dir_key := _get_cardinal_dir(_anim_dir)
				flip_h = _anim_dir in ["l", "dl", "ul"]
				var frames: Array = _at_walk.get(dir_key, [])
				var f: int = _anim_frame % max(1, frames.size())
				if frames.size() > 0 and frames[f] != null:
					tex = frames[f]
				else:
					tex = _at_idle
			_:
				tex = _at_idle

	if tex != null:
		if flip_h:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(tex, dest, false, tint)
			if class_id == "archer" and need_weapon_overlay and _at_weapon != null:
				draw_texture_rect(_at_weapon, dest, false, tint)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(tex, dest, false, tint)
			if class_id == "archer" and need_weapon_overlay and _at_weapon != null:
				draw_texture_rect(_at_weapon, dest, false, tint)
	else:
		draw_circle(Vector2.ZERO, 16.0, Color(0.2, 0.65, 1.0, alpha))
	# 攻擊範圍圈已改用常駐 Line2D 節點（_range_ring），見 _create_range_ring()/_update_range_ring()，
	# 不再於此處用 draw_arc 繪製，避免依賴 _draw() 呼叫時機。


func _get_cardinal_dir(dir: String) -> String:
	# warrior_walk 只有 d（正面）與 r（側面），左側由 r + flip_h 處理
	match dir:
		"r", "dr", "ur": return "r"
		"l", "dl", "ul": return "r"   # flip_h = true by caller
		"u":             return "d"   # 背面用正面代替
		_:               return "d"
