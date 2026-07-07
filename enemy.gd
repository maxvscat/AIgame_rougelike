extends CharacterBody2D

signal died(enemy: Node2D)
signal attack_projectile_requested(origin: Vector2, target_position: Vector2, speed: float)
signal dot_damage_occurred(pos: Vector2, amount: float)

const TILE_SIZE := 64.0
const DASH_WARNING_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/dash_warning_line.png"
# dash_warning_line.png 原始尺寸 512x140，箭頭起點在本地 (0, 70)，箭頭沿 +X 延伸 502px
const DASH_WARNING_TEXTURE_SIZE := Vector2(512.0, 140.0)
const DASH_WARNING_TEXTURE_LENGTH := 502.0
const DASHED_RING_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/dashed_ring_silver.png"
const DASHED_RING_TEXTURE_SIZE := 512.0
const FAN_DASHED_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/fan_dashed_frame.png"
# fan_dashed_frame.png 原始尺寸 560x560，扇形頂點位於 (40, 280)，張角 90 度，半徑約 500px
const FAN_DASHED_TEXTURE_SIZE := Vector2(560.0, 560.0)
const FAN_DASHED_TEXTURE_VERTEX := Vector2(40.0, 280.0)
const FAN_DASHED_TEXTURE_RADIUS := 500.0
const FREE_PACK_ENEMY_PATH := "res://AIgame_rougelike/assets/art/enemies/free_pack/%s/"

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
# ── 受擊回饋（擊退/擊倒/擠壓）──────────────────────────────────────────
var _knockback_velocity := Vector2.ZERO  # 平滑擊退慣性（指數衰減）
var _knockdown_timer := 0.0              # 擊倒倒地剩餘時間（無法移動與攻擊）
var _knockdown_cd := 0.0                 # 擊倒內建冷卻，防高爆擊流無限控場
var _hit_squash_timer := 0.0             # 受擊擠壓變形計時
var _slow_timer := 0.0
var _slow_multiplier := 1.0
var terrain_speed_multiplier := 1.0  # 地形效果移動倍率（冰面加速等），由 main.gd 定期更新
var _pull_target := Vector2.ZERO
var _pull_timer := 0.0
var _pull_speed := 0.0
var _curse_timer := 0.0
var _curse_multiplier := 1.0
var _burn_ticks := []
# 毒素改為疊層倍增制：只保留「目前層數＋單層傷害＋剩餘時間」，
# 每秒造成的傷害＝單層傷害 × 目前層數（最多 3 層），不再是 3 個獨立 DOT 各自計算。
var _poison_stack_count := 0
var _poison_per_layer_damage := 0.0
var _poison_timer := 0.0
var _poison_tick_timer := 0.0
var _jump_state := "chase"     # "chase" | "prepare" | "landing"（耗客跳砍用）
var _jump_timer := 0.0
var _jump_target := Vector2.ZERO
var _warning_node: Node2D
var _texture: Texture2D
var _anim_frames: Dictionary = {}
var _anim_time := 0.0
var _facing_left := false
var _font: Font
var _dash_warning_texture: Texture2D
var _fan_dashed_texture: Texture2D
var _walk_bob_phase := 0.0   # 簡易走路動作（無多幀素材時的擠壓彈跳）

# ── 素材共用快取（效能優化）──────────────────────────────────────────────
# 原本每隻怪物 _ready() 都會各自重新 load() 一次貼圖／動畫幀（同種怪物重複載入同一批檔案），
# 在關卡開始一次生成大量怪物（例如後期關卡一次生成 40~90 隻）時，會造成明顯的瞬間卡頓。
# 改為以 enemy_id 為 key 的 static 快取，同一種怪物只需在整場遊戲中「第一次」實際從磁碟載入，
# 之後同種怪物生成時直接共用同一份 Texture2D／幀陣列（唯讀資源，多個 Sprite 共用安全）。
static var _shared_texture_cache: Dictionary = {}
static var _shared_anim_frames_cache: Dictionary = {}
static var _shared_font: Font = null
static var _shared_dash_warning_texture: Texture2D = null
static var _shared_dash_warning_loaded := false
static var _shared_fan_dashed_texture: Texture2D = null
static var _shared_fan_dashed_loaded := false

# ── 近戰攻擊狀態機 ──────────────────────────────────────────────────────────
# chase → charge → lunge → recovery → chase
var _ma_state := "chase"
var _ma_timer := 0.0
var _ma_attack_dir := Vector2.ZERO   # 集氣時鎖定的攻擊方向（世界空間）
var _ma_lunge_end := Vector2.ZERO    # 衝刺終點（世界空間）
var _ma_hit_done := false            # 本次衝刺是否已判定傷害
var _ma_charge_origin := Vector2.ZERO # 集氣開始當下的世界座標，預警圖形固定畫在這個位置，
									   # 不會因為衝刺過程中怪物本體移動而跟著跑掉

# 近戰攻擊參數（由 _setup_melee_params() 依怪物設定）
var _ma_charge_time   := 0.6    # 集氣時間（秒）
var _ma_range_tiles   := 1.2    # 攻擊到達距離（格）── 判定範圍
var _ma_width_tiles   := 0.8    # 矩形攻擊寬度（格）── 僅 rect 使用
var _ma_lunge_tiles   := 1.0    # 衝刺前進距離（格）
var _ma_recovery_time := 0.4    # 攻擊後硬直（秒，即衝刺CD，滿了才能再次進入 charge）
const _MA_RECOVERY_STILL_TIME := 0.5  # 衝刺後原地停留秒數，時間到即恢復移動追擊（不必等整段CD跑完）
var _ma_shape         := "rect" # 攻擊形狀："rect" | "fan" | "circle"
var _ma_fan_angle     := 120.0  # 扇形角度（度）── 僅 fan 使用
var _ma_continuous_hit := false     # 衝刺過程中是否持續判定（而非只在落地瞬間判定一次）
var _chain_skill_after_lunge := false  # 衝刺落地後是否緊接著自動觸發技能（例如鋁布橫掃）

# 技能集氣（鋁布橫掃 / 其他需要蓄力的技能）
var _skill_charging := false
var _skill_charge_timer := 0.0
var _skill_charge_max := 1.5
var _skill_charge_callback := Callable()


func _ready() -> void:
	add_to_group("enemies")
	collision_mask = 0
	# 字型與預警貼圖對所有怪物都是同一份檔案，只需在整場遊戲第一次真正從磁碟載入，
	# 之後直接共用同一份資源，避免每隻怪物 _ready() 都重複做 ResourceLoader.exists()/load()。
	if _shared_font == null:
		_shared_font = load("res://AIgame_rougelike/assets/fonts/MaokenAssortedSans-TC.otf") if ResourceLoader.exists("res://AIgame_rougelike/assets/fonts/MaokenAssortedSans-TC.otf") else load("res://AIgame_rougelike/assets/fonts/NotoSansCJKtc-Regular.otf")
	_font = _shared_font
	if not _shared_dash_warning_loaded:
		_shared_dash_warning_loaded = true
		if ResourceLoader.exists(DASH_WARNING_TEXTURE_PATH):
			_shared_dash_warning_texture = load(DASH_WARNING_TEXTURE_PATH) as Texture2D
	_dash_warning_texture = _shared_dash_warning_texture
	if not _shared_fan_dashed_loaded:
		_shared_fan_dashed_loaded = true
		if ResourceLoader.exists(FAN_DASHED_TEXTURE_PATH):
			_shared_fan_dashed_texture = load(FAN_DASHED_TEXTURE_PATH) as Texture2D
	_fan_dashed_texture = _shared_fan_dashed_texture
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
	_ma_continuous_hit = false
	_chain_skill_after_lunge = false
	match enemy_id:
		"retail":
			_ma_charge_time   = 0.6
			_ma_range_tiles   = 1.2
			_ma_width_tiles   = 0.8
			_ma_lunge_tiles   = 1.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "rect"
		"friend":
			_ma_charge_time   = 0.5
			_ma_range_tiles   = 1.4
			_ma_width_tiles   = 0.9
			_ma_lunge_tiles   = 2.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "rect"
		"aluminum":
			_ma_charge_time   = 0.8
			_ma_range_tiles   = 2.0
			_ma_width_tiles   = 2.0   # fan 不用 width，但保留備用
			_ma_lunge_tiles   = 5.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "fan"
			_ma_fan_angle     = 90.0
			_ma_continuous_hit = true       # 衝刺過程中玩家進入扇形角度內即中招，不必等落地
			_chain_skill_after_lunge = true # 衝刺落地後立即接續橫掃一圈
		"hacker":
			_ma_charge_time   = 0.45
			_ma_range_tiles   = 1.3
			_ma_width_tiles   = 0.8
			_ma_lunge_tiles   = 3.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "rect"
		"patriot":
			_ma_charge_time   = 0.7
			_ma_range_tiles   = 5.0
			_ma_width_tiles   = 1.5
			_ma_lunge_tiles   = 8.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "rect"
		"headhunter":
			_ma_charge_time   = 0.5
			_ma_range_tiles   = 1.5
			_ma_width_tiles   = 1.0
			_ma_lunge_tiles   = 3.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "rect"
		_:
			_ma_charge_time   = 0.6
			_ma_range_tiles   = 1.2
			_ma_width_tiles   = 0.8
			_ma_lunge_tiles   = 1.0
			_ma_recovery_time = 1.0  # 衝刺 CD 統一改為 1 秒
			_ma_shape         = "rect"


func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(target) or health <= 0.0:
		return
	# 磁爆拉力：覆蓋正常移動
	if _pull_timer > 0.0:
		_pull_timer -= delta
		var dir := (_pull_target - global_position)
		if dir.length() > 4.0:
			velocity = dir.normalized() * _pull_speed
		else:
			velocity = Vector2.ZERO
			_pull_timer = 0.0
		move_and_slide()
		_process_status(delta)
		return
	_process_status(delta)
	_knockdown_cd = maxf(_knockdown_cd - delta, 0.0)
	if _hit_squash_timer > 0.0:
		_hit_squash_timer = maxf(_hit_squash_timer - delta, 0.0)
		queue_redraw()
	if _knockback_velocity.length() > 8.0:
		# 擊退慣性：覆蓋一般行動，速度指數衰減
		velocity = _knockback_velocity
		_knockback_velocity = _knockback_velocity * pow(0.0000001, delta)
		if _knockback_velocity.length() <= 8.0:
			_knockback_velocity = Vector2.ZERO
		move_and_slide()
	elif _knockdown_timer > 0.0:
		# 擊倒倒地：無法移動與攻擊
		_knockdown_timer = maxf(_knockdown_timer - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		queue_redraw()
	elif _jump_state != "chase":
		_process_jump(delta)
	else:
		# 技能集氣（鋁布橫掃等）
		if _skill_charging:
			_skill_charge_timer += delta
			queue_redraw()
			if _skill_charge_timer >= _skill_charge_max and _skill_charge_callback.is_valid():
				_skill_charge_callback.call()
		_process_movement_and_attack(delta)
		# 技能改由衝刺落地後直接觸發的怪物（例如鋁布），不使用獨立技能計時器，避免與衝刺不同步
		if not _skill_charging and not _chain_skill_after_lunge:
			_process_skill(delta)
	_update_free_pack_animation(delta)
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		queue_redraw()
	# 簡易走路動作：依移動速度擠壓彈跳，取代缺少多幀走路素材的怪物
	if velocity.length() > 6.0:
		_walk_bob_phase += delta * (6.0 + velocity.length() * 0.02)
		queue_redraw()
	else:
		_walk_bob_phase = 0.0


func _update_free_pack_animation(delta: float) -> void:
	if _anim_frames.is_empty():
		return
	_anim_time += delta
	if absf(velocity.x) > 4.0:
		_facing_left = velocity.x < 0.0
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
		if enemy_id == "boss_mid":
			# 中型Boss需求：邊朝玩家移動邊射擊，不像一般遠程怪要先停下來才開火
			if distance > contact_radius + 12.0:
				velocity = direction * move_speed * _slow_multiplier * terrain_speed_multiplier
			else:
				velocity = Vector2.ZERO
		elif distance > max(attack_range * 0.86, contact_radius + 12.0):
			velocity = direction * move_speed * _slow_multiplier * terrain_speed_multiplier
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
				velocity = direction * move_speed * _slow_multiplier * terrain_speed_multiplier
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
				_ma_charge_origin = global_position   # 鎖定預警圖形的固定世界座標
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
			# 持續判定型攻擊（例如鋁布）：衝刺過程中玩家只要進入攻擊角度/範圍內就算命中，不必等落地
			if _ma_continuous_hit and not _ma_hit_done and _check_melee_hit():
				_ma_hit_done = true
				if is_instance_valid(target):
					target.take_damage(1)
			if remaining.length() <= lunge_speed * delta:
				global_position = _ma_lunge_end
				# 衝刺到位：非持續判定型怪物在落地瞬間才判定一次
				if not _ma_hit_done and _check_melee_hit():
					_ma_hit_done = true
					if is_instance_valid(target):
						target.take_damage(1)
				_ma_state = "recovery"
				_ma_timer = 0.0
				velocity  = Vector2.ZERO
				if _chain_skill_after_lunge and not skill_id.is_empty():
					skill_timer = skill_cd
					match skill_id:
						"sweep":
							_sweep_attack()
			else:
				velocity = remaining.normalized() * lunge_speed
			move_and_slide()
			queue_redraw()

		"recovery":
			# 攻擊後硬直：前 _MA_RECOVERY_STILL_TIME 秒原地停留（僅反黏附微調），
			# 之後即使還沒完全冷卻（尚未到 _ma_recovery_time）也會立即恢復移動追擊，
			# 只是要等冷卻完全跑完才能再次進入 charge 觸發下一次衝刺。
			if _ma_timer < _MA_RECOVERY_STILL_TIME:
				var rdist: float = global_position.distance_to(target.global_position)
				var rrepel: float = contact_radius * 1.2
				if rdist < rrepel and rdist > 0.5:
					var raway: Vector2 = (global_position - target.global_position).normalized()
					velocity = raway * move_speed * 0.3
				else:
					velocity = Vector2.ZERO
			else:
				if distance > max(contact_radius + 8.0, 1.0):
					velocity = direction * move_speed * _slow_multiplier * terrain_speed_multiplier
				else:
					velocity = Vector2.ZERO
				var repel_dist: float = contact_radius * 1.4
				if distance < repel_dist and distance > 0.5:
					var away: Vector2 = (global_position - target.global_position).normalized()
					velocity += away * move_speed * 0.5 * (1.0 - distance / repel_dist)
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
	# Boss 完全免疫；精英怪（獵頭/愛國者/駭客）擊退距離減為 45%（原本完全免疫，改為仍有回饋感）
	if ["boss_mid", "boss_final"].has(enemy_id):
		return
	if _jump_state != "chase":
		return  # 跳砍過程（Tween 控制位置）不受擊退，避免位置錯亂
	var dist := distance
	if ["headhunter", "patriot", "hacker"].has(enemy_id):
		dist *= 0.45
	# 被擊退打斷集氣 / 衝刺
	if _ma_state == "charge" or _ma_state == "lunge":
		_ma_state = "chase"
		_ma_timer = 0.0
	# 平滑擊退：改為給予會衰減的初速度（原本是瞬間位移，視覺上像瞬移）
	_knockback_velocity = direction.normalized() * dist * 16.0


func apply_knockdown(duration: float) -> void:
	# 爆擊擊倒：倒地無法行動。Boss 免疫；精英怪時間縮短；內建 3 秒冷卻防無限控場
	if ["boss_mid", "boss_final"].has(enemy_id):
		return
	if _knockdown_cd > 0.0 or _jump_state != "chase":
		return
	var dur := duration
	if ["headhunter", "patriot", "hacker"].has(enemy_id):
		dur *= 0.6
	_knockdown_timer = maxf(_knockdown_timer, dur)
	_knockdown_cd = 3.0
	# 打斷普攻集氣/衝刺與技能集氣（例如鋁布橫掃）
	if _ma_state == "charge" or _ma_state == "lunge":
		_ma_state = "chase"
		_ma_timer = 0.0
	if _skill_charging:
		_skill_charging = false
		_skill_charge_timer = 0.0
		_skill_charge_callback = Callable()
	queue_redraw()


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
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(2.0)
	tween.tween_callback(func() -> void:
		move_speed = old_speed
	)


func _sweep_attack() -> void:
	# 鋁布橫掃一圈技能：0.8 秒預警虛線框 → 對 5 格範圍造成傷害（原 2 格擴大為 5 格）
	_skill_charging     = true
	_skill_charge_timer = 0.0
	_skill_charge_max   = 0.8
	_skill_charge_callback = func() -> void:
		_skill_charging     = false
		_skill_charge_timer = 0.0
		_skill_charge_callback = Callable()
		_spawn_dashed_ring_warning(global_position, 5.0 * TILE_SIZE, 0.2,
			func() -> void:
				if is_instance_valid(target) and \
						global_position.distance_to(target.global_position) <= 5.0 * TILE_SIZE:
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
	# 落點縮小為 2.6 格（原 4 格太大幾乎躲不掉），並加上收縮圈倒數提示，預警更直覺
	_spawn_circle_warning(_jump_target, 2.6 * TILE_SIZE,
		Color(1.0, 0.1, 0.1, 0.55), 2.0, func() -> void: pass)
	_spawn_shrinking_ring(_jump_target, 5.2 * TILE_SIZE, 2.6 * TILE_SIZE, 2.0,
		Color(1.0, 0.45, 0.1, 0.8))


func _process_jump(delta: float) -> void:
	if _jump_state == "prepare":
		velocity = Vector2.ZERO
		move_and_slide()
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			_jump_state = "flying"
			# 縮小 → 飛衝 → 落地放大
			var tween := create_tween()
			tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			tween.tween_property(self, "scale", Vector2(0.65, 0.65), 0.06)
			tween.parallel().tween_property(self, "global_position", _jump_target, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.08).set_ease(Tween.EASE_OUT)
			tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
			tween.tween_callback(func() -> void:
				if not is_instance_valid(self):
					return
				_jump_state = "landing"
				_jump_timer = 0.2
				if is_instance_valid(target) and \
						global_position.distance_to(target.global_position) <= 2.6 * TILE_SIZE:
					target.take_damage(1)
				# 落地衝擊波視覺 + 螢幕震動
				_spawn_expanding_ring(global_position, 0.4 * TILE_SIZE, 2.6 * TILE_SIZE, 0.35,
					Color(1.0, 0.5, 0.15, 0.85))
				_request_camera_shake(5.0)
			)
	elif _jump_state == "flying":
		# Tween 控制位置，physics 保持靜止
		velocity = Vector2.ZERO
		move_and_slide()
	elif _jump_state == "landing":
		_jump_timer -= delta
		if _jump_timer <= 0.0:
			remove_from_group("jumping_enemies")
			_jump_state = "chase"


func _fire_random_lasers() -> void:
	# 雷射改良：原本兩道全隨機方向，常常整輪都打不到玩家、毫無威脅也毫無記憶點。
	# 改為第一道必定瞄準玩家當前位置（仍有 1 秒預警可躲），其餘隨機補場面；
	# 最終 Boss 三道（第二道瞄準玩家 ±35 度扇區）。發射瞬間有亮色光束特效與震動。
	var laser_count := 3 if enemy_id == "boss_final" else 2
	for i in range(laser_count):
		var angle: float
		if i == 0 and is_instance_valid(target):
			angle = (target.global_position - global_position).angle()
		elif i == 1 and enemy_id == "boss_final" and is_instance_valid(target):
			angle = (target.global_position - global_position).angle() + deg_to_rad(randf_range(-35.0, 35.0))
		else:
			angle = randf_range(0.0, TAU)
		var start := global_position
		var end   := start + Vector2.RIGHT.rotated(angle) * 16.0 * TILE_SIZE
		_spawn_line_warning(start, end, 34.0, Color(1.0, 0.05, 0.05, 0.5), 1.0,
			func() -> void:
				_spawn_laser_beam(start, end)
				_request_camera_shake(4.0)
				if is_instance_valid(target) and \
						_distance_to_segment(target.global_position, start, end) <= 34.0:
					target.take_damage(1)
		)


func _process_status(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_multiplier = 1.0
	if _curse_timer > 0.0:
		_curse_timer -= delta
		if _curse_timer <= 0.0:
			_curse_multiplier = 1.0
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
	if _poison_stack_count > 0:
		_poison_timer -= delta
		_poison_tick_timer -= delta
		if _poison_tick_timer <= 0.0:
			_poison_tick_timer = 1.0
			# 疊層倍增制：每秒傷害 = 單層傷害 × 目前層數（最多 3 層＝3 倍），不再各層獨立計算
			var poison_amount := _poison_per_layer_damage * float(_poison_stack_count)
			take_damage(poison_amount)
			dot_damage_occurred.emit(global_position, poison_amount)
		if _poison_timer <= 0.0:
			_poison_stack_count = 0
			_poison_per_layer_damage = 0.0
			_poison_tick_timer = 0.0


func take_damage(amount: float) -> float:
	if health <= 0.0:
		return 0.0

	var final_damage: float = amount

	if _curse_timer > 0.0:
		final_damage *= _curse_multiplier

	health -= final_damage
	_hit_flash_timer = 0.08
	_hit_squash_timer = 0.14   # 受擊擠壓變形回饋
	queue_redraw()
	if health <= 0.0:
		_spawn_free_pack_death_animation()
		died.emit(self)
		queue_free()
	return final_damage

func apply_pull(target_pos: Vector2, speed: float, duration: float) -> void:
	_pull_target = target_pos
	_pull_speed = speed
	_pull_timer = duration


func apply_slow(multiplier: float, duration: float) -> void:
	_slow_multiplier = min(_slow_multiplier, multiplier)
	_slow_timer      = max(_slow_timer, duration)


func apply_burn(damage: float, duration: float) -> void:
	_burn_ticks.append({"damage": damage, "timer": duration, "tick": 1.0})


func apply_poison(per_layer_damage: float, duration: float) -> void:
	# 疊層倍增制：最多疊 3 層，每次命中都刷新單層傷害與持續時間，層數 +1（上限 3）
	_poison_stack_count = mini(_poison_stack_count + 1, 3)
	_poison_per_layer_damage = per_layer_damage
	_poison_timer = duration
	if _poison_tick_timer <= 0.0:
		_poison_tick_timer = 1.0
	# （2026-07-07 平衡調整）毒素不再附帶緩速，緩速定位交給冰霜


func apply_joker_curse(multiplier: float, duration: float) -> void:

	_curse_multiplier = max(_curse_multiplier, multiplier)
	_curse_timer = max(_curse_timer, duration)


# ── 場景警告圖形 ─────────────────────────────────────────────────────────────

func _request_camera_shake(strength: float) -> void:
	# 透過父節點（main.gd）觸發螢幕震動；父節點沒有該屬性時安全略過
	var parent := get_parent()
	if parent != null and "_camera_shake_strength" in parent:
		parent._camera_shake_strength = maxf(float(parent._camera_shake_strength), strength)


func _spawn_shrinking_ring(center: Vector2, from_radius: float, to_radius: float,
		duration: float, color: Color) -> void:
	# 收縮預警圈：從大圈收縮到實際傷害範圍，讓玩家直覺看出剩餘反應時間
	var parent := get_parent()
	if parent == null:
		return
	var ring := Line2D.new()
	ring.closed = true
	ring.width = 4.0
	ring.default_color = color
	ring.add_to_group("transient_effects")
	var points := PackedVector2Array()
	for i in range(64):
		points.append(Vector2(cos(TAU * i / 64.0), sin(TAU * i / 64.0)) * to_radius)
	ring.points = points
	parent.add_child(ring)
	ring.global_position = center
	ring.scale = Vector2.ONE * (from_radius / maxf(1.0, to_radius))
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(ring, "scale", Vector2.ONE, duration)
	tween.tween_callback(func() -> void:
		if is_instance_valid(ring):
			ring.queue_free()
	)


func _spawn_expanding_ring(center: Vector2, from_radius: float, to_radius: float,
		duration: float, color: Color) -> void:
	# 擴散衝擊波：由小圈快速擴大並淡出（跳砍落地、爆炸等）
	var parent := get_parent()
	if parent == null:
		return
	var ring := Line2D.new()
	ring.closed = true
	ring.width = 6.0
	ring.default_color = color
	ring.add_to_group("transient_effects")
	var points := PackedVector2Array()
	for i in range(64):
		points.append(Vector2(cos(TAU * i / 64.0), sin(TAU * i / 64.0)) * to_radius)
	ring.points = points
	parent.add_child(ring)
	ring.global_position = center
	ring.scale = Vector2.ONE * (from_radius / maxf(1.0, to_radius))
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(ring, "scale", Vector2.ONE, duration)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	tween.tween_callback(func() -> void:
		if is_instance_valid(ring):
			ring.queue_free()
	)


func _spawn_laser_beam(start: Vector2, end: Vector2) -> void:
	# 雷射實際發射的亮色光束（外紅內白），0.28 秒淡出
	var parent := get_parent()
	if parent == null:
		return
	var outer := Line2D.new()
	outer.width = 16.0
	outer.default_color = Color(1.0, 0.3, 0.2, 0.9)
	outer.points = PackedVector2Array([start, end])
	outer.add_to_group("transient_effects")
	outer.z_index = 8
	parent.add_child(outer)
	var inner := Line2D.new()
	inner.width = 5.0
	inner.default_color = Color(1.0, 0.95, 0.9, 1.0)
	inner.points = PackedVector2Array([start, end])
	inner.add_to_group("transient_effects")
	inner.z_index = 9
	parent.add_child(inner)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(outer, "modulate:a", 0.0, 0.28)
	tween.parallel().tween_property(inner, "modulate:a", 0.0, 0.28)
	tween.tween_callback(func() -> void:
		if is_instance_valid(outer):
			outer.queue_free()
		if is_instance_valid(inner):
			inner.queue_free()
	)


func _spawn_circle_warning(center: Vector2, radius: float, color: Color,
		delay: float, callback: Callable) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring := Line2D.new()
	ring.closed = true
	ring.width  = 5.0
	ring.default_color = color
	# 加入 transient_effects 群組，換關時 main.gd 的 _clear_world_objects() 才會一併清除，
	# 避免舊關卡殘留的紅色預警範圍圈殘留到下一關。
	ring.add_to_group("transient_effects")
	var points := PackedVector2Array()
	for i in range(72):
		points.append(center + Vector2(cos(TAU * i / 72.0), sin(TAU * i / 72.0)) * radius)
	ring.points = points
	parent.add_child(ring)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		if callback.is_valid():
			callback.call()
		if is_instance_valid(ring):
			ring.queue_free()
	)


func _spawn_dashed_ring_warning(center: Vector2, radius: float, delay: float, callback: Callable) -> void:
	# 虛線框預警（例如鋁布橫掃），使用生成的虛線圓圖片素材
	var parent := get_parent()
	if parent == null:
		return
	if not ResourceLoader.exists(DASHED_RING_TEXTURE_PATH):
		_spawn_circle_warning(center, radius, Color(0.85, 0.88, 0.94, 0.75), delay, callback)
		return
	var sprite := Sprite2D.new()
	sprite.add_to_group("transient_effects")
	sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite.z_index = 5
	sprite.texture = load(DASHED_RING_TEXTURE_PATH) as Texture2D
	sprite.scale = Vector2.ONE * (radius * 2.0 / DASHED_RING_TEXTURE_SIZE)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.9)
	parent.add_child(sprite)
	sprite.global_position = center
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		if callback.is_valid():
			callback.call()
		if is_instance_valid(sprite):
			sprite.queue_free()
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
	# 加入 transient_effects 群組，換關時 main.gd 的 _clear_world_objects() 才會一併清除，
	# 避免舊關卡殘留的紅色預警線殘留到下一關。
	line.add_to_group("transient_effects")
	parent.add_child(line)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
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
	if _shared_texture_cache.has(enemy_id):
		_texture = _shared_texture_cache[enemy_id]
	else:
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
		_shared_texture_cache[enemy_id] = _texture
	_load_free_pack_frames()


func _load_free_pack_frames() -> void:
	if _shared_anim_frames_cache.has(enemy_id):
		# 同種怪物先前已經載入過，直接共用同一份幀陣列（唯讀，不會被修改），不重新讀檔。
		_anim_frames = _shared_anim_frames_cache[enemy_id]
		return
	_anim_frames = {}
	var base: String = FREE_PACK_ENEMY_PATH % enemy_id
	for action: String in ["idle", "walk", "hit", "death", "fly"]:
		var frames: Array[Texture2D] = []
		for frame_index: int in range(1, 13):
			var frame_path: String = base + "%s_%02d.png" % [action, frame_index]
			var frame_texture := _try_load_enemy_texture(frame_path)
			if frame_texture != null:
				frames.append(frame_texture)
		if frames.size() > 0:
			_anim_frames[action] = frames
	if not _anim_frames.has("idle") and _anim_frames.has("fly"):
		_anim_frames["idle"] = _anim_frames["fly"]
	if not _anim_frames.has("walk") and _anim_frames.has("fly"):
		_anim_frames["walk"] = _anim_frames["fly"]
	if not _anim_frames.has("hit") and _anim_frames.has("idle"):
		_anim_frames["hit"] = _anim_frames["idle"]
	_shared_anim_frames_cache[enemy_id] = _anim_frames


func _try_load_enemy_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


func _current_free_pack_texture() -> Texture2D:
	if _anim_frames.is_empty():
		return null
	var action := "idle"
	var fps := 8.0
	if _hit_flash_timer > 0.0 and _anim_frames.has("hit"):
		action = "hit"
		fps = 16.0
	elif velocity.length() > 6.0 and _anim_frames.has("walk"):
		action = "walk"
		fps = 10.0
	elif _anim_frames.has("fly"):
		action = "fly"
		fps = 8.0
	var frames: Array = _anim_frames.get(action, [])
	if frames.is_empty():
		return null
	var frame_index := int(floor(_anim_time * fps)) % frames.size()
	return frames[frame_index] as Texture2D


func _spawn_free_pack_death_animation() -> void:
	if not _anim_frames.has("death"):
		return
	var parent := get_parent()
	if parent == null:
		return
	var frames: Array = _anim_frames.get("death", [])
	if frames.is_empty():
		return
	var sprite := AnimatedSprite2D.new()
	var sprite_frames := SpriteFrames.new()
	sprite_frames.add_animation("death")
	sprite_frames.set_animation_loop("death", false)
	sprite_frames.set_animation_speed("death", 14.0)
	for tex in frames:
		if tex != null:
			sprite_frames.add_frame("death", tex)
	sprite.sprite_frames = sprite_frames
	sprite.animation = "death"
	sprite.centered = true
	sprite.global_position = global_position
	sprite.z_index = z_index
	sprite.scale = Vector2.ONE * ((16.0 * scale_multiplier * 3.0) / 256.0)
	parent.add_child(sprite)
	sprite.play("death")
	sprite.animation_finished.connect(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _draw() -> void:
	var radius := 16.0 * scale_multiplier
	var tint   := Color.WHITE
	if _hit_flash_timer > 0.0:
		tint = Color(1.0, 0.88, 0.72)

	# 角色圖像（走路時做簡易擠壓彈跳動作；受擊擠壓；擊倒時倒地旋轉）
	var draw_tex: Texture2D = _current_free_pack_texture()
	if draw_tex == null:
		draw_tex = _texture
	if draw_tex != null:
		var size := radius * 3.0
		var bob: float = sin(_walk_bob_phase) * 0.08
		var w: float = size * (1.0 + bob)
		var h: float = size * (1.0 - bob)
		var bob_y: float = -absf(bob) * size * 0.5
		# 受擊擠壓：橫向拉寬、縱向壓扁，隨計時回彈
		var squash := 0.0
		if _hit_squash_timer > 0.0:
			squash = (_hit_squash_timer / 0.14) * 0.22
		# 擊倒：倒地旋轉（朝面向的反方向倒），起身前 0.2 秒逐漸爬起
		var rot := 0.0
		if _knockdown_timer > 0.0:
			var lie_ratio: float = clampf(_knockdown_timer / 0.2, 0.0, 1.0)
			rot = deg_to_rad(78.0) * lie_ratio * (-1.0 if _facing_left else 1.0)
		var flip_x := -1.0 if (_facing_left and not _anim_frames.is_empty()) else 1.0
		var dest := Rect2(Vector2(-w * 0.5, -h * 0.5 + bob_y), Vector2(w, h))
		draw_set_transform(Vector2.ZERO, rot, Vector2(flip_x * (1.0 + squash), 1.0 - squash))
		draw_texture_rect(draw_tex, dest, false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, radius, Color(0.95, 0.2, 0.16))

	# 擊倒暈眩星星（頭頂旋轉）
	if _knockdown_timer > 0.0:
		for star_i in range(3):
			var star_a: float = _anim_time * 5.0 + TAU * float(star_i) / 3.0
			var star_pos := Vector2(cos(star_a) * 16.0, -radius - 14.0 + sin(star_a) * 5.0)
			draw_circle(star_pos, 3.5, Color(1.0, 0.9, 0.25, 0.95))

	# 名稱標籤（2026-07-07：加大字級並加黑色描邊，提升辨識度）
	if _font != null:
		draw_string_outline(_font, Vector2(-45, -radius - 26), display_name,
			HORIZONTAL_ALIGNMENT_CENTER, 90, 17, 5, Color(0, 0, 0, 0.9))
		draw_string(_font, Vector2(-45, -radius - 26), display_name,
			HORIZONTAL_ALIGNMENT_CENTER, 90, 17, Color(1, 1, 1))

	# ── 狀態效果 icon（緩速／燃燒／毒素）────────────────────────────────
	var status_icons: Array = []
	if _slow_timer > 0.0:
		status_icons.append({"label": "緩", "color": Color(0.3, 0.7, 1.0)})
	if _burn_ticks.size() > 0:
		status_icons.append({"label": "燃", "color": Color(1.0, 0.45, 0.1)})
	if _poison_stack_count > 0:
		var poison_label := "毒" if _poison_stack_count <= 1 else "毒×%d" % _poison_stack_count
		status_icons.append({"label": poison_label, "color": Color(0.35, 1.0, 0.35)})
	if _curse_timer > 0.0:
		status_icons.append({"label": "咒", "color": Color(0.9, 0.45, 1.0)})
	if status_icons.size() > 0 and _font != null:
		for idx in range(status_icons.size()):
			var si: Dictionary = status_icons[idx]
			var ix: float = float(idx - (status_icons.size() - 1) * 0.5) * 18.0
			var iy: float = -radius - 10.0
			draw_circle(Vector2(ix, iy), 8.0, si["color"])
			draw_string(_font, Vector2(ix - 8.0, iy + 5.0), str(si["label"]),
				HORIZONTAL_ALIGNMENT_CENTER, 16, 11, Color(0.05, 0.05, 0.05))

	# 血量條（2026-07-07：加大並加深色外框，提升辨識度）
	var ratio: float = clamp(health / max(0.001, max_health), 0.0, 1.0)
	draw_rect(Rect2(Vector2(-30, -radius - 13), Vector2(60, 8)), Color(0.0, 0.0, 0.0, 0.85))
	draw_rect(Rect2(Vector2(-28, -radius - 11.5), Vector2(56, 5)), Color(0.25, 0.03, 0.03))
	draw_rect(Rect2(Vector2(-28, -radius - 11.5), Vector2(56.0 * ratio, 5)), Color(0.35, 1.0, 0.3))

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
		# 預警長度需對應「實際衝刺距離」（衝刺格數），而非攻擊判定格數，
		# 否則會出現衝刺 5 格但預警線只顯示 2 格的誤導畫面。
		var warn_px   := _ma_lunge_tiles * TILE_SIZE
		var width_px  := _ma_width_tiles * TILE_SIZE
		# 預警圖形固定畫在「集氣開始時」鎖定的世界座標（_ma_charge_origin），不隨怪物衝刺移動：
		# _draw() 是以怪物目前的 global_position 為原點的本地座標，因此這裡換算出對應的本地偏移，
		# 讓視覺上的預警範圍維持在地面上同一個位置，直到攻擊結束才消失。
		var anchor: Vector2 = _ma_charge_origin - global_position
		match _ma_shape:
			"rect":
				if _dash_warning_texture != null:
					var tex_scale: float = warn_px / DASH_WARNING_TEXTURE_LENGTH
					var draw_h: float = DASH_WARNING_TEXTURE_SIZE.y * tex_scale
					var angle := _ma_attack_dir.angle()
					draw_set_transform(anchor, angle, Vector2.ONE)
					draw_texture_rect(_dash_warning_texture,
						Rect2(Vector2(0.0, -draw_h * 0.5), Vector2(warn_px, draw_h)),
						false, Color(1, 1, 1, lerpf(0.55, 1.0, charge_ratio)))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					var pts := _rect_warning_points(_ma_attack_dir, warn_px, width_px)
					var offset_pts := PackedVector2Array()
					for p in pts:
						offset_pts.append(p + anchor)
					draw_colored_polygon(offset_pts, fill_col)
					draw_polyline(PackedVector2Array([offset_pts[0], offset_pts[1], offset_pts[2], offset_pts[3], offset_pts[0]]),
						edge_col, 2.0)
			"fan":
				# 扇形怪物（如鋁布）的衝刺預警：改用生成的扇形虛線框素材（固定 90 度張角）
				if _fan_dashed_texture != null and absf(_ma_fan_angle - 90.0) < 0.5:
					var fan_scale: float = warn_px / FAN_DASHED_TEXTURE_RADIUS
					var fan_angle := _ma_attack_dir.angle()
					draw_set_transform(anchor, fan_angle, Vector2.ONE)
					draw_texture_rect(_fan_dashed_texture,
						Rect2(-FAN_DASHED_TEXTURE_VERTEX * fan_scale, FAN_DASHED_TEXTURE_SIZE * fan_scale),
						false, Color(1, 1, 1, lerpf(0.55, 1.0, charge_ratio)))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					var pts := _fan_warning_points(_ma_attack_dir, warn_px, _ma_fan_angle)
					var offset_pts := PackedVector2Array()
					for p in pts:
						offset_pts.append(p + anchor)
					draw_colored_polygon(offset_pts, fill_col)
					draw_polyline(offset_pts, edge_col, 2.0, true)
			"circle":
				draw_circle(anchor, warn_px, fill_col)
				draw_arc(anchor, warn_px, 0.0, TAU, 64, edge_col, 2.0)

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
