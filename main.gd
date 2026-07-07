extends Node2D

const PlayerScene := preload("res://AIgame_rougelike/scenes/player.tscn")
const EnemyScene := preload("res://AIgame_rougelike/scenes/enemy.tscn")
const CatPetScene := preload("res://AIgame_rougelike/scenes/cat_pet.tscn")
const SkillSlotScript := preload("res://AIgame_rougelike/scripts/skill_slot.gd")
const BALANCE_CONFIG_PATH := "res://AIgame_rougelike/data/balance_config.json"
const SAVE_PATH := "user://save_slots.json"
const SETTINGS_PATH := "user://settings.json"
const SPAWN_WARNING_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/spawn_warning.png"
const LOBBY_BACKGROUND_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/map/lobby_background.png"
const MELTDOWN_RING_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/meltdown_dashed_ring.png"
const FIRE_SPRAY_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/fire_spray.png"
const FIRE_SPRAY_TEXTURE_MAX_R := 464.0
const FIRE_SPRAY_TEXTURE_ORIGIN := Vector2(24.0, 160.0)
const FROST_BURST_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/frost_burst.png"
const HIT_SPARK_TEXTURE_PATH := "res://AIgame_rougelike/assets/art/effects/hit_spark.png"
# 砲台顯示大小＝玩家角色顯示大小的 1.2 倍
const TOWER_SOURCE_TEXTURE_SIZE := 650.0
const PLAYER_DISPLAY_SIZE := 120.0   # 對應 player.gd _draw() 的 112x128 顯示範圍平均值
const TURRET_SIZE_RATIO := 1.2
const SAVE_SLOT_COUNT := 5
const TILE_SIZE := 64.0
const MAX_LEVEL := 30
const MAX_ACTIVE_SKILLS := 5

var rng := RandomNumberGenerator.new()
var player: Node2D
var selected_save_slot := -1
var save_slots: Array = []
var total_chips := 0
var current_research: Dictionary = {}
var game_settings := {
	"volume": 0.8,
	"difficulty": "normal",
	"keys": {
		"attack": "MouseLeft",
		"dash": "Space",
		"turret_1": "1"
	}
}
var difficulty_defs := {
	"normal": {"name": "一般", "enemy_multiplier": 1.0, "player_hearts": 5},
	"hard": {"name": "困難", "enemy_multiplier": 1.5, "player_hearts": 4},
	"expert": {"name": "專家", "enemy_multiplier": 2.5, "player_hearts": 3}
}
var _pending_rebind_action := ""
var _pending_rebind_label := ""
var _rebind_blocker: ColorRect = null   # 等待按鍵時的全螢幕攔截層
var _permanent_regen_timer := 0.0
var game_started := false
var is_game_ended := false
var current_stage := 1
var kill_count := 0
var stage_enemies_alive := 0
var map_rect := Rect2()
var wall_points := {}

# ── 關卡地形系統：每 5 關一組視覺主題 + 功能地形區塊 ──────────────────────
# 視覺主題：只影響地板/格線/邊框/裝飾顏色，純美術、不影響玩法。
# 功能地形：不阻擋移動的圓形區塊，站在上面才有效果（敵我皆受影響）：
#   mud  泥沼：移動速度降為 55%
#   fire 火焰：敵人持續受傷；玩家每 1.5 秒扣 1 顆心（受無敵時間保護）
#   ice  冰面：移動速度提升為 135%
var stage_theme_defs := [
	{"name": "廢棄賣場", "floor": Color(0.045, 0.05, 0.065), "grid": Color(0.21, 0.23, 0.28), "border": Color(0.9, 0.65, 0.15), "decor": "tile",    "zones": {"mud": [0, 1]}, "floor_tex": "floor_mall.png"},
	{"name": "地下污水道", "floor": Color(0.04, 0.06, 0.045),  "grid": Color(0.17, 0.26, 0.17), "border": Color(0.35, 0.78, 0.3),  "decor": "moss",    "zones": {"mud": [3, 4]}, "floor_tex": "floor_sewer.png"},
	{"name": "熔毀機房", "floor": Color(0.07, 0.035, 0.03),  "grid": Color(0.3, 0.15, 0.11),  "border": Color(1.0, 0.42, 0.1),  "decor": "crack",   "zones": {"fire": [3, 4], "mud": [0, 1]}, "floor_tex": "floor_meltdown.png"},
	{"name": "冷凍倉庫", "floor": Color(0.03, 0.05, 0.08),   "grid": Color(0.16, 0.26, 0.36), "border": Color(0.45, 0.8, 1.0),  "decor": "tile",    "zones": {"ice": [3, 5]}, "floor_tex": "floor_freezer.png"},
	{"name": "駭客核心", "floor": Color(0.05, 0.03, 0.07),   "grid": Color(0.27, 0.16, 0.35), "border": Color(0.75, 0.35, 1.0), "decor": "circuit", "zones": {"ice": [1, 2], "fire": [1, 2], "mud": [1, 1]}, "floor_tex": "floor_hacker.png"},
	{"name": "末日戰場", "floor": Color(0.06, 0.025, 0.03),  "grid": Color(0.3, 0.12, 0.12),  "border": Color(1.0, 0.18, 0.18), "decor": "crack",   "zones": {"fire": [3, 4], "mud": [2, 2]}, "floor_tex": "floor_doom.png"}
]
const TERRAIN_TEX_DIR := "res://AIgame_rougelike/assets/art/map/terrain/"
var _terrain_tex_cache: Dictionary = {}   # 地圖貼圖快取（地板/背景）
var _decor_rocks: Array = []              # 每關裝飾岩石 [{"pos", "size", "seed"}]，純視覺不阻擋
const TERRAIN_MUD_SLOW := 0.70        # 泥沼移動倍率（2026-07-07 調整：0.55→0.70，減速變溫和）
const TERRAIN_ICE_SPEED := 1.50       # 冰面移動倍率（1.35→1.50）
const TERRAIN_FIRE_ENEMY_DPS := 3.0   # 火焰對敵人每秒傷害（8→3）
const TERRAIN_FIRE_PLAYER_TICK := 1.5 # 火焰對玩家扣血間隔（秒）
const TERRAIN_TICK_INTERVAL := 0.25   # 敵人地形效果檢查間隔（效能節流）
var terrain_zones: Array = []         # [{"type": String, "pos": Vector2, "radius": float, "seed": int}]
var _terrain_tick_timer := 0.0
var _player_fire_tick := 0.0
var _zone_banner_label: Label = null  # 進入新區域主題時的橫幅
var _game_camera: Camera2D = null
var _camera_shake_strength := 0.0     # 螢幕震動（受傷/死亡回饋）
var mage_preview_center := Vector2.ZERO
var mage_preview_radius := 0.0
var mage_preview_visible := false
var bullets := []
var turrets := []
var _turret_hotkey_map: Dictionary = {}  # int → skill_id，每次 _update_ui 時重建
var skill_cooldowns := {}
var magnet_cooldown := 0.0
var meltdown_cooldown := 0.0
var active_magnet: Node2D
var active_poker_buffs := {}
var poker_timer := 20.0
var poker_deck: Array = []   # 動態依玩家技能建立，不預設任何牌
var poker_discard := []
var _poker_deck_signature := ""   # 記錄牌組是依哪些「樸克技能:等級」建立的，變動時需重建牌組
const POKER_CARD_ORDER := ["heart", "spade", "diamond", "club", "joker"]
var _poker_drawing := false
var _poker_draw_timer := 0.0
var _poker_draw_cycle_timer := 0.0
var _poker_draw_cycle_index := 0
var _poker_draw_pending_card := ""
var _poker_draw_sprite: Sprite2D
var _poker_draw_label: Label

var test_overlay: Control
var _main_menu_input_buffer := ""
var _test_enemy_id := "retail"
var _test_enemy_count := 10
var _test_character_id := "archer"
var _test_skill_slots: Array = [{"id": "", "lv": 0}, {"id": "", "lv": 0}, {"id": "", "lv": 0}, {"id": "", "lv": 0}, {"id": "", "lv": 0}]
var is_test_mode := false
var sanyuan_hit_counter := 0
var sanyuan_pending := false
var _triple_dice_armed := false   # 三倍骰：爆擊後蓄勢，下一擊必定 3 倍爆擊
var _baxian_timer := 0.0          # 八仙過海：每 5 秒麻將牌轟炸計時
var flush_cooldown := 0.0
var sixi_tiles: Array = []
var sixi_orbit_angle := 0.0
var sixi_hit_cds: Dictionary = {}
var moon_projectiles: Array = []
var moon_cooldown := 0.0
# 海底撈月改為「齊發齊收」的整批模式：同一批麻將牌共用同一組飛出/停留/收回階段計時，
# 而不是個別各自獨立飛行與計時，讓技能呈現「一下同時打出分散攻擊、再一起收回」的手感。
var moon_volley_phase := "idle"   # idle / out / hover / return
var moon_volley_timer := 0.0
var moon_volley_out_duration := 0.35
var moon_volley_hover_duration := 1.5
var moon_volley_return_duration := 1.0
var _lightning_sfx_gate := 0.0   # 高壓電（tech_lightning）命中音效節流：播放中或播完1秒內不再播放新音效
var _turret_chain_sfx_gate := 0.0   # 電流砲台（fish_chain）命中音效節流：多座砲台共用，播放中或播完1秒內不再播放新音效
var _stage_preview_positions := []
var _stage_spawn_warning_nodes: Array[Node2D] = []
var _stage_previewing := false
var _stage_preview_timer := 0.0   # 剩餘預覽秒數，用於閃爍計算
var _skill_bar_skill_hash := ""   # 用於偵測技能欄是否需要重建
var _poker_guard_pets: Array = [] # 皇家護衛召喚的護衛節點列表
var _attack_preview_node: Node2D = null  # 戰士攻擊範圍預覽圓

# ── 關卡開始怪物生成：分散到多幀（效能優化）───────────────────────────────
# 原本一次性 for 迴圈把整關全部怪物（後期關卡可達 40~90 隻）在同一影格內 instantiate，
# 造成關卡開始瞬間明顯卡頓。改為排入佇列，每影格只生成一小批，分散到多個影格完成。
const ENEMY_SPAWNS_PER_FRAME := 6
var _pending_stage_spawns: Array = []
var _stage_spawn_active := false

var ui_canvas: CanvasLayer
var menu_background: TextureRect
var hud_layer: Control
var heart_label: Label
var stage_label: Label
var level_label: Label
var chip_label: Label
var enemy_count_label: Label
var _multi_attack_count := 1
var _sfx: Dictionary = {}          # 音效播放器字典
var _bgm_player: AudioStreamPlayer = null   # 背景音樂（assets/audio/bgm.ogg，檔案不存在則略過）
var _sfx_play_tokens: Dictionary = {}
var _prev_player_health := 999     # 用來偵測玩家受傷
var skill_label: Label
var skill_bar: HBoxContainer
var message_label: Label
var hover_tooltip_panel: PanelContainer
var hover_tooltip_label: RichTextLabel
var main_menu_overlay: Control
var save_overlay: Control
var lobby_overlay: Control
var character_overlay: Control
var level_up_overlay: Control
var settings_overlay: Control
var game_over_overlay: Control
var result_label: Label

var enemy_defs := {
	"retail":     {"id": "retail",     "name": "散戶",    "hp":   4.0, "attack_type": "melee",  "range": 1.65, "aps": 0.25, "speed":  85.8, "scale": 4.0},
	"friend":     {"id": "friend",     "name": "街友",    "hp":   8.0, "attack_type": "melee",  "range": 2.7,  "aps": 0.5,  "speed":  76.0, "scale": 4.0, "skill": "speed_burst", "skill_cd": 8.0},
	"shooter":    {"id": "shooter",    "name": "射畜",    "hp":  10.0, "attack_type": "ranged", "range": 8.0,  "aps": 0.5,  "speed":  66.0, "scale": 4.0},
	"hoodlum":    {"id": "hoodlum",    "name": "89",      "hp":  12.0, "attack_type": "ranged", "range": 8.0,  "aps": 1.0,  "speed":  70.0, "scale": 4.0, "skill": "summon_retail", "skill_cd": 15.0},
	"aluminum":   {"id": "aluminum",   "name": "鋁布",    "hp":  20.0, "attack_type": "melee",  "range": 2.0,  "aps": 0.5,  "speed": 109.0, "scale": 5.4, "skill": "sweep",         "skill_cd": 2.0},
	"hacker":     {"id": "hacker",     "name": "耗客",    "hp":  50.0, "attack_type": "melee",  "range": 1.3,  "aps": 0.75, "speed": 122.0, "scale": 8.0, "skill": "jump_slash",    "skill_cd": 10.0},
	"patriot":    {"id": "patriot",    "name": "阻國人",  "hp":  80.0, "attack_type": "melee",  "range": 5.0,  "aps": 1.0,  "speed": 112.0, "scale": 5.0, "skill": "laser",         "skill_cd": 7.0},
	"headhunter": {"id": "headhunter", "name": "獵頭",    "hp":  65.0, "attack_type": "melee",  "range": 1.2,  "aps": 1.0,  "speed": 112.0, "scale": 3.0, "skill": "jump_slash",    "skill_cd": 7.0},
	"boss_mid":   {"id": "boss_mid",   "name": "中型Boss","hp": 260.0, "attack_type": "ranged", "range": 8.0,  "aps": 1.0,  "speed":  257.4, "scale": 4.0, "skill": "laser",         "skill_cd": 5.0},
	"boss_final": {"id": "boss_final", "name": "最終Boss","hp": 420.0, "attack_type": "ranged", "range": 8.0,  "aps": 1.2,  "speed":  54.0, "scale": 4.0, "skill": "laser",         "skill_cd": 4.0}
}

var stage_defs := [
	{"retail": 15},
	{"retail": 30},
	{"retail": 50, "friend": 10},
	{"friend": 20, "retail": 40},
	{"shooter": 10, "retail": 40},
	{"shooter": 15, "friend": 20},
	{"shooter": 20, "retail": 50},
	{"hoodlum": 6, "shooter": 15},
	{"hoodlum": 8, "friend": 25},
	{"headhunter": 5},
	{"aluminum": 10, "retail": 60},
	{"aluminum": 15, "friend": 25},
	{"hoodlum": 10, "shooter": 20},
	{"aluminum": 20, "shooter": 20},
	{"headhunter": 10, "power": 1.5},
	{"hacker": 6, "friend": 40},
	{"hacker": 8, "shooter": 20},
	{"hacker": 10, "aluminum": 20},
	{"hoodlum": 12, "hacker": 8},
	{"headhunter": 10, "power": 2.5},
	{"patriot": 3, "shooter": 30},
	{"patriot": 4, "aluminum": 25},
	{"patriot": 5, "hacker": 10},
	{"patriot": 6, "hoodlum": 12},
	{"boss_mid": 1},
	{"patriot": 7, "hacker": 12},
	{"patriot": 8, "aluminum": 30},
	{"patriot": 10, "hoodlum": 15},
	{"patriot": 12, "hacker": 15, "aluminum": 20},
	{"boss_final": 1}
]

var skill_defs := {}
var skill_icon_paths := {}
var _game_font: Font = null
var _poker_icons: Dictionary = {}   # card → {sprite, label}
var _poker_blink_timer := 0.0
var _manual_pause_active := false
var permanent_research_defs := {
	"start_damage":      {"name": "開局傷害",   "base_cost": 3,  "max_level": 3, "desc": "LV1 傷害 +50%，之後每級再 +20%。"},
	"crit_rate":         {"name": "暴擊率",     "base_cost": 3,  "max_level": 3, "desc": "LV1 暴擊率 +20%，之後每級再 +10%。"},
	"start_random_skill":{"name": "開局隨機技能","base_cost": 50, "max_level": 1, "desc": "開局獲得 1 個隨機技能 LV1。"},
	"regen":             {"name": "自動修復",   "base_cost": 10, "max_level": 3, "desc": "LV1 每分鐘回1血，LV2 每45秒回1血，LV3 每秒回1血。"},
	"multi_attack":      {"name": "多重攻擊",   "base_cost": 6,  "max_level": 1, "desc": "LV1 一次攻擊同時打2個敵人。"},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	var _font_path := "res://AIgame_rougelike/assets/fonts/MaokenAssortedSans-TC.otf"
	if ResourceLoader.exists(_font_path):
		_game_font = load(_font_path) as Font
	_load_settings()
	_ensure_input_actions()
	_build_skill_defs()
	_load_balance_config()
	_load_save_slots()
	_create_world()
	_create_player()
	_create_ui()
	_create_audio()
	_setup_custom_cursor()
	_show_main_menu()


func _setup_custom_cursor() -> void:
	# 自訂滑鼠游標：assets/art/ui/cursor.png（建議 48x48、準心置中）；缺檔時維持系統游標
	var cursor_path := "res://AIgame_rougelike/assets/art/ui/cursor.png"
	var cursor_tex: Texture2D = null
	if ResourceLoader.exists(cursor_path):
		cursor_tex = load(cursor_path) as Texture2D
	elif FileAccess.file_exists(cursor_path):
		var img := Image.load_from_file(cursor_path)
		if img != null:
			cursor_tex = ImageTexture.create_from_image(img)
	if cursor_tex != null:
		# 熱點設在圖片中心（準心式游標）
		Input.set_custom_mouse_cursor(cursor_tex, Input.CURSOR_ARROW,
			Vector2(cursor_tex.get_width(), cursor_tex.get_height()) * 0.5)


func _ensure_input_actions() -> void:
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack", 0.5)
	if InputMap.action_get_events("attack").is_empty():
		_apply_input_binding("attack", str(game_settings.get("keys", {}).get("attack", "MouseLeft")), false)
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash", 0.5)
	if InputMap.action_get_events("dash").is_empty():
		_apply_input_binding("dash", str(game_settings.get("keys", {}).get("dash", "Space")), false)
	for index in range(1, 7):
		var action := "turret_%d" % index
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		if InputMap.action_get_events(action).is_empty():
			var binding := str(game_settings.get("keys", {}).get(action, str(index)))
			var key := InputEventKey.new()
			key.keycode = _key_name_to_keycode(binding, (KEY_0 + index) as Key)
			InputMap.action_add_event(action, key)
	var configured_keys: Dictionary = game_settings.get("keys", {})
	_apply_input_binding("attack", str(configured_keys.get("attack", "MouseLeft")))
	_apply_input_binding("dash", str(configured_keys.get("dash", "Space")))
	for index in range(1, 7):
		var turret_action := "turret_%d" % index
		_apply_input_binding(turret_action, str(configured_keys.get(turret_action, str(index))))


func _key_name_to_keycode(key_name: String, fallback: Key) -> Key:
	match key_name:
		"Space":
			return KEY_SPACE
		"Shift":
			return KEY_SHIFT
		"Ctrl":
			return KEY_CTRL
		"Alt":
			return KEY_ALT
		"Tab":
			return KEY_TAB
		"Enter":
			return KEY_ENTER
		"Q":
			return KEY_Q
		"W":
			return KEY_W
		"E":
			return KEY_E
		"R":
			return KEY_R
		"A":
			return KEY_A
		"S":
			return KEY_S
		"D":
			return KEY_D
		"F":
			return KEY_F
		"Z":
			return KEY_Z
		"X":
			return KEY_X
		"1":
			return KEY_1
		"2":
			return KEY_2
		"3":
			return KEY_3
		"4":
			return KEY_4
		"5":
			return KEY_5
		"6":
			return KEY_6
	return fallback


func _event_to_binding_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return OS.get_keycode_string(key_event.keycode)
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				return "MouseLeft"
			MOUSE_BUTTON_RIGHT:
				return "MouseRight"
			MOUSE_BUTTON_MIDDLE:
				return "MouseMiddle"
	return ""


func _binding_name_to_text(binding_name: String) -> String:
	match binding_name:
		"MouseLeft":
			return "滑鼠左鍵"
		"MouseRight":
			return "滑鼠右鍵"
		"MouseMiddle":
			return "滑鼠中鍵"
		"Space":
			return "空白鍵"
	return binding_name


func _apply_input_binding(action: String, binding_name: String, clear_existing := true) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)
	if clear_existing:
		InputMap.action_erase_events(action)
	var event: InputEvent
	match binding_name:
		"MouseLeft":
			var mouse_left := InputEventMouseButton.new()
			mouse_left.button_index = MOUSE_BUTTON_LEFT
			event = mouse_left
		"MouseRight":
			var mouse_right := InputEventMouseButton.new()
			mouse_right.button_index = MOUSE_BUTTON_RIGHT
			event = mouse_right
		"MouseMiddle":
			var mouse_middle := InputEventMouseButton.new()
			mouse_middle.button_index = MOUSE_BUTTON_MIDDLE
			event = mouse_middle
		_:
			var key := InputEventKey.new()
			key.keycode = _key_name_to_keycode(binding_name, KEY_SPACE)
			event = key
	InputMap.action_add_event(action, event)


func _process(delta: float) -> void:
	if not game_started or get_tree().paused or is_game_ended:
		return
	_process_bullets(delta)
	_process_skill_cooldowns(delta)
	_process_permanent_research(delta)
	_process_turrets(delta)
	_process_terrain_effects(delta)
	_process_camera_shake(delta)
	_process_poker(delta)
	_process_sixi(delta)
	_process_moon(delta)
	_process_baxian(delta)
	if _lightning_sfx_gate > 0.0:
		_lightning_sfx_gate = maxf(_lightning_sfx_gate - delta, 0.0)
	if _turret_chain_sfx_gate > 0.0:
		_turret_chain_sfx_gate = maxf(_turret_chain_sfx_gate - delta, 0.0)
	_poker_blink_timer += delta
	if _stage_preview_timer > 0.0:
		_stage_preview_timer = maxf(_stage_preview_timer - delta, 0.0)
	if _stage_spawn_active:
		_process_pending_stage_spawns()
	queue_redraw()
	_clamp_player_to_map()
	_update_ui()
	if stage_enemies_alive <= 0 and not is_test_mode and not _stage_previewing and not _stage_spawn_active:
		_finish_stage()


func _process_pending_stage_spawns() -> void:
	var spawned := 0
	while _pending_stage_spawns.size() > 0 and spawned < ENEMY_SPAWNS_PER_FRAME:
		var entry: Dictionary = _pending_stage_spawns.pop_front()
		_spawn_wave_enemy(str(entry["id"]), Vector2(entry["pos"]), float(entry["power"]))
		spawned += 1
	if _pending_stage_spawns.is_empty():
		_stage_spawn_active = false


func _process_skill_cooldowns(delta: float) -> void:
	magnet_cooldown = max(magnet_cooldown - delta, 0.0)
	meltdown_cooldown = max(meltdown_cooldown - delta, 0.0)
	flush_cooldown = max(flush_cooldown - delta, 0.0)
	for skill_id in skill_cooldowns.keys():
		var remaining: float = maxf(float(skill_cooldowns[skill_id]) - delta, 0.0)
		skill_cooldowns[skill_id] = 0.0 if remaining <= 0.08 else remaining
	# 清一色自動觸發（CD 5秒，不受攻速影響）
	if flush_cooldown <= 0.0 and player != null and player.get_skill_level("mahjong_flush") > 0 and game_started and not is_game_ended:
		var flush_cd := _skill_cooldown("mahjong_flush", 5.0)
		flush_cooldown = flush_cd
		skill_cooldowns["mahjong_flush"] = flush_cd
		var level: int = player.get_skill_level("mahjong_flush")
		var radius := 6.0 * TILE_SIZE
		var dmg: float = float(player.attack_damage) * (_skill_level_value("mahjong_flush", "damage_pct", [0, 100, 130, 160, 200, 250, 300], level) / 100.0) * _hot_damage_mult()
		var flush_skills: Dictionary = player.selected_skills.duplicate(true)
		_spawn_flush_effect(player.global_position)
		_spawn_circle_effect(player.global_position, radius, Color(0.4, 1.0, 0.6, 0.4), 0.18, func() -> void:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(enemy) and player.global_position.distance_to(enemy.global_position) <= radius:
					enemy.take_damage(dmg)
					_show_damage_number(enemy.global_position, dmg, false)
					_apply_on_hit_skills(enemy, dmg, flush_skills, true, false)
		)


func _process_permanent_research(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.health <= 0:
		return
	var regen_lv := int(current_research.get("regen", 0))
	if regen_lv <= 0:
		return
	var interval: float
	match regen_lv:
		1: interval = 60.0   # LV1：每分鐘回1血
		2: interval = 45.0   # LV2：每45秒回1血
		_: interval = 1.0    # LV3：每秒回1血
	_permanent_regen_timer += delta
	if _permanent_regen_timer >= interval:
		_permanent_regen_timer = 0.0
		if player.health < player.max_health:
			player.health += 1
			player.stats_changed.emit()


func _process_turrets(delta: float) -> void:
	_process_turret_visuals(delta)
	for index in range(turrets.size() - 1, -1, -1):
		var turret: Dictionary = turrets[index]
		var node: Node2D = turret["node"]
		if not is_instance_valid(node):
			turrets.remove_at(index)
			continue
		# 火焰砲：爆發模式狀態機
		if str(turret.get("skill_id", "")) == "fish_fire" and turret.has("burst_active"):
			if bool(turret["burst_active"]):
				turret["burst_time_left"] = float(turret["burst_time_left"]) - delta
				turret["burst_shot_timer"] = float(turret["burst_shot_timer"]) - delta
				if float(turret["burst_shot_timer"]) <= 0.0:
					if _is_turret_aimed(turret):
						_fire_turret(turret)
					turret["burst_shot_timer"] = 0.2  # 5次/秒
				if float(turret["burst_time_left"]) <= 0.0:
					turret["burst_active"] = false
					turret["rest_time_left"] = 3.0
			else:
				turret["rest_time_left"] = float(turret["rest_time_left"]) - delta
				if float(turret["rest_time_left"]) <= 0.0:
					turret["burst_active"] = true
					turret["burst_time_left"] = 5.0
					turret["burst_shot_timer"] = 0.0
					_play_turret_sfx("turret_fire", node.global_position)
			turrets[index] = turret
			continue
		# 一般砲台邏輯
		turret["timer"] = float(turret["timer"]) - delta
		if float(turret["timer"]) <= 0.0:
			if _is_turret_aimed(turret):
				_fire_turret(turret)
				turret["timer"] = float(turret["interval"])
			else:
				turret["timer"] = maxf(float(turret["timer"]), -1.0)
		turrets[index] = turret


func _input(event: InputEvent) -> void:
	# 等待按鍵重綁定期間，用最高優先度攔截所有輸入（含滑鼠）
	if _pending_rebind_action != "":
		var is_key   := event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo
		var is_mouse := event is InputEventMouseButton and (event as InputEventMouseButton).pressed
		if is_key or is_mouse:
			var binding_name := _event_to_binding_name(event)
			if binding_name != "":
				var keys: Dictionary = game_settings.get("keys", {})
				keys[_pending_rebind_action] = binding_name
				game_settings["keys"] = keys
				_apply_input_binding(_pending_rebind_action, binding_name)
				_cancel_rebind()
				_save_settings()
				_show_settings()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _pending_rebind_action != "":
		# 應已被 _input 處理，這裡只防漏
		get_viewport().set_input_as_handled()
		return
	if game_started and not get_tree().paused and not is_game_ended:
		if event.is_action_pressed("dash") and player != null and player.has_method("request_dash"):
			player.request_dash()
		for index in range(1, 7):
			if event.is_action_pressed("turret_%d" % index):
				_cast_turret_by_index(index)
	if event.is_action_pressed("ui_cancel"):
		if test_overlay != null and test_overlay.visible:
			_return_to_lobby()
			return
		if game_started and not is_game_ended and _manual_pause_active:
			_resume_game()
		elif game_started and not is_game_ended and not get_tree().paused:
			_show_pause()
	# F1：測試模式暫停 / 繼續
	if is_test_mode and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_F1:
			if get_tree().paused and test_overlay != null and test_overlay.visible:
				_hide_all_overlays()
				get_tree().paused = false
			else:
				_show_test_overlay()
			return
	# 死亡/通關後，只允許用滑鼠點按鈕，不接受鍵盤快捷鍵
	# （_end_game 面板的按鈕自己處理跳回主選單）
	# 主選單輸入 "test" 進入測試畫面
	if not game_started and event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode >= KEY_A and k.keycode <= KEY_Z:
			_main_menu_input_buffer += char(k.keycode + 32)
			if not "test".begins_with(_main_menu_input_buffer):
				_main_menu_input_buffer = ""
			elif _main_menu_input_buffer == "test":
				_main_menu_input_buffer = ""
				_enter_test_mode()


func _build_skill_defs() -> void:
	skill_defs = {
		"dice_crit": {"school": "骰子", "name": "致命骰", "desc": "爆擊傷害加成：LV1=+20%　LV2=+40%　LV3=+60%\nLV4=+80%　LV5=+100%　LV6=+120%\n（基礎爆擊倍率 ×2.0，加成後＝×2.0 + 每級20%）"},
		"dice_execute": {"school": "骰子", "name": "斬殺骰", "desc": "對小怪：每級 10% 機率直接秒殺。\nLV1=10%　LV2=20%　LV3=30%\nLV4=40%　LV5=50%　LV6=60%\n對Boss：傷害加成 LV1=+10%…LV6=+60%。"},
		"dice_first": {"school": "骰子", "name": "先手優勢", "desc": "攻擊血量 50% 以上的敵人時額外加爆擊率。\nLV1=+20%　LV2=+35%　LV3=+50%\nLV4=+65%　LV5=+80%　LV6=+95%\n（對精英/Boss 效果減半）"},
		"dice_blast": {"school": "骰子", "name": "爆裂骰", "desc": "爆擊時有 10%×等級 機率，在目標位置放置固定 6 格範圍的地雷圈，2 秒後引爆。\n引爆傷害（以本次爆擊傷害為基準）：LV1=70%　LV2=130%　LV3=190%\nLV4=250%　LV5=310%　LV6=370%"},
		"dice_last": {"school": "骰子", "name": "孤注一擲", "desc": "血量剩 1 顆愛心時必定爆擊，且所有傷害提升。\nLV1=+20%　LV2=+40%　LV3=+60%\nLV4=+80%　LV5=+100%　LV6=+120%"},
		"dice_hot": {"school": "骰子", "name": "賭徒熱手", "desc": "爆擊後 3 秒內所有傷害提升（可與其他加成疊加）。\nLV1=+10%　LV2=+20%　LV3=+30%\nLV4=+40%　LV5=+50%　LV6=+60%"},
		"tech_frost": {"school": "科技", "name": "冷卻", "desc": "攻擊命中後，以目標為中心對 3 格範圍內所有敵人造成同等冰霜傷害，並緩速至 70% 速度持續 2 秒。\n每個目標各有 10% 機率額外完全冰凍（移動停止）。\n附帶傷害：LV1=×20%　LV2=×35%　LV3=×50%\nLV4=×65%　LV5=×80%　LV6=×100%（最低 1）"},
		"tech_fire": {"school": "科技", "name": "過載", "desc": "攻擊使目標燃燒，持續 4 秒每秒造成 DoT 傷害。\nDoT：LV1=×20%　LV2=×30%　LV3=×40%\nLV4=×50%　LV5=×60%　LV6=×70%（最低 1）"},
		"tech_poison": {"school": "科技", "name": "病毒", "desc": "攻擊附加毒素並緩速，最多疊 3 層，持續 4 秒（重複命中會刷新時間並疊層）。\n每秒傷害＝單層傷害 × 目前層數（疊 3 層＝3 倍傷害，非各層獨立計算）。\n單層 DoT：LV1=×10%　LV2=×15%　LV3=×20%\nLV4=×25%　LV5=×30%　LV6=×35%（最低 1）"},
		"tech_lightning": {"school": "科技", "name": "高壓電", "desc": "命中時觸發鏈式閃電，依等級跳躍不同次數。\n跳躍次數：LV1~2=2次　LV3~4=3次　LV5~6=4次\n連鎖範圍：LV1=1.5格　LV3=2.5格　LV5=3.5格　LV6=4格\n每跳傷害：LV1=×15%　LV2=×25%　LV3=×35%\nLV4=×45%　LV5=×55%　LV6=×65%（最低 1）"},
		"tech_meltdown": {"school": "科技", "name": "熔毀", "desc": "攻擊命中後，在目標位置延遲 0.5 秒引爆，對 5.5 格圓形範圍內所有敵人造成傷害。\n冷卻 2 秒；視覺為橘色圓形虛線。"},
		"tech_magnet": {"school": "科技", "name": "磁暴", "desc": "觸發磁場（CD 5 秒），吸引並緩速範圍內敵人，造成傷害。\nBoss 只緩速不吸引。\n範圍：LV1=2格→LV6=5格\n傷害：LV1=×20%→LV6=×70%（最低 1）"},
		"poker_heart": {"school": "樸克", "name": "命運紅心", "desc": "抽中後提高玩家閃避率，持續到下次抽牌。\nLV1=+10%　LV2=+20%　LV3=+30%\nLV4=+40%　LV5=+50%　LV6=+60%"},
		"poker_spade": {"school": "樸克", "name": "致命黑桃", "desc": "抽中後攻擊傷害提升，持續到下次抽牌。\nLV1=+20%　LV2=+40%　LV3=+60%\nLV4=+80%　LV5=+100%　LV6=+120%"},
		"poker_diamond": {"school": "樸克", "name": "鑽石爆擊", "desc": "抽中後爆擊傷害倍率提升，持續到下次抽牌。\n每級額外 +0.5 倍率（LV1=+×0.5，LV6=+×3.0）"},
		"poker_club": {"school": "樸克", "name": "疾風梅花", "desc": "抽中後攻速提升，持續到下次抽牌。\nLV1=+100%　LV2=+150%　LV3=+200%\nLV4=+250%　LV5=+300%　LV6=+350%"},
		"poker_joker": {"school": "樸克", "name": "厄運小丑", "desc": "抽中後，攻擊命中敵人時會為該敵人附加 6 秒「易傷」詛咒，使牠在詛咒期間受到的所有傷害（含砲台、DOT、大四喜/海底撈月/清一色等）都會提高。\nLV1=+30%　LV2=+60%　LV3=+90%\nLV4=+120%　LV5=+150%　LV6=+180%"},
		"poker_guard": {"school": "樸克", "name": "皇家護衛", "desc": "抽中時召喚護衛（依等級數量），近戰攻擊最近敵人，攻擊會顯示傷害數字與音效。\n護衛傷害 = 玩家目前攻擊力 × 等級對應倍率。\n與其他花色一樣，抽到新牌時護衛會被清除，需再次抽到皇家牌才會重新召喚。"},
		"mahjong_sanyuan": {"school": "麻將", "name": "大三元", "desc": "每第 3 次攻擊觸發爆炸（3 格圓形範圍）。\n傷害：LV1=×100%　LV2=×130%　LV3=×160%\nLV4=×200%　LV5=×250%　LV6=×300%"},
		"mahjong_sixi": {"school": "麻將", "name": "大四喜", "desc": "4 張麻將磁磚繞玩家旋轉，接觸敵人持續造成傷害。\n傷害：LV1=×50%　LV2=×70%　LV3=×90%\nLV4=×110%　LV5=×130%　LV6=×150%\n（轉速每級提升）"},
		"mahjong_pong": {"school": "麻將", "name": "碰碰胡", "desc": "每次攻擊後，對 3 格內最近的 N 個其他敵人各造成 100% 傷害。\n彈射數量：LV1=1個　LV2=2個　LV3=3個\nLV4=4個　LV5=5個　LV6=6個\n（彈射可觸發 on-hit 效果）"},
		"mahjong_moon": {"school": "麻將", "name": "海底撈月", "desc": "同時朝不同方向丟出多顆麻將牌，停留後一起收回，來回路徑上的敵人各受一次攻擊傷害。\n同時發動的麻將牌數量：LV1=1顆，每升1級+1顆（LV6=6顆）。"},
		"mahjong_wall": {"school": "麻將", "name": "門清", "desc": "自動抵擋一次傷害（護盾），冷卻後再次就緒。\n冷卻：LV1=6秒　LV2=5秒　LV3=4秒\nLV4=3秒　LV5=2.5秒　LV6=2秒"},
		"mahjong_flush": {"school": "麻將", "name": "清一色", "desc": "每 5 秒對 6 格內所有敵人造成傷害，發動時繞玩家旋轉劈出旋風斬特效（CD 5 秒）。\n傷害：LV1=×100%　LV2=×130%　LV3=×160%\nLV4=×200%　LV5=×250%　LV6=×300%"},
		"fish_rapid": {"school": "魚機", "name": "連射砲", "desc": "熱鍵 1。放置連射砲台，每 0.3 秒射擊最近敵人。\n可同時放置台數：LV1~2=1台　LV3~4=2台　LV5~6=3台\n傷害：LV1=×100%　LV2=×120%　LV3=×150%\nLV4=×170%　LV5=×185%　LV6=×200%\n（CD 15 秒）"},
		"fish_fire": {"school": "魚機", "name": "火焰砲", "desc": "熱鍵 2。放置火焰砲台，爆發式扇形噴火（5次/秒，持續 5 秒後休息 3 秒）。\n扇形範圍：LV1=2格　LV2=2.5格　LV3=3格\nLV4=3.5格　LV5=4格　LV6=4.5格\n每次傷害 = 攻擊力×60%（CD 15 秒）"},
		"fish_saw": {"school": "魚機", "name": "鋸齒砲", "desc": "熱鍵 3。放置鋸齒砲台，砲管持續自轉，每 0.1 秒對 2.5 格內所有敵人造成傷害（即時依玩家目前攻擊力計算，受黑桃buff影響）。\n傷害：LV1=玩家攻擊力×10%　LV2=×20%　LV3=×30%\nLV4=×40%　LV5=×50%　LV6=×60%\n攻擊範圍圈：攻擊時淡入 0.5 秒顯示並持續維持，範圍內 2 秒無敵人後淡出 0.5 秒消失。\n攻擊音效完整播放 5 秒後淡出結束，若播完仍在攻擊會延遲 1 秒後再重播。\n（CD 15 秒）"},
		"fish_missile": {"school": "魚機", "name": "導彈砲", "desc": "熱鍵 4。放置導彈砲台，每 2 秒發射追蹤導彈。\n枚數：LV1=3枚，每升 1 級 +2 枚（LV6=13枚）\n傷害：LV1~2=×100%　LV3~4=×130%　LV5~6=×160%\n（CD 15 秒）"},
		"fish_laser": {"school": "魚機", "name": "雷射砲", "desc": "熱鍵 5。放置雷射砲台，每 3 秒發射貫穿雷射，命中路徑所有敵人。\n傷害：LV1=×100%　LV2=×150%　LV3=×200%\nLV4=×300%　LV5=×400%　LV6=×500%\n（CD 15 秒）"},
		"fish_chain": {"school": "魚機", "name": "電流砲台", "desc": "熱鍵 6。放置電流砲台，砲台本身不轉動，每 0.5 秒對敵人發射綠色電流，彈跳次數等於等級。\n彈跳：LV1=1跳　LV2=2跳…LV6=6跳\n傷害：LV1=×70%　LV2=×80%…LV6=×120%\n（CD 15 秒）"}
	}
	var groups := {
		"dice": ["dice_crit", "dice_execute", "dice_first", "dice_blast", "dice_last", "dice_hot"],
		"tech": ["tech_frost", "tech_fire", "tech_poison", "tech_lightning", "tech_meltdown", "tech_magnet"],
		"poker": ["poker_heart", "poker_spade", "poker_diamond", "poker_club", "poker_joker", "poker_guard"],
		"mahjong": ["mahjong_sanyuan", "mahjong_sixi", "mahjong_pong", "mahjong_moon", "mahjong_wall", "mahjong_flush"],
		"fish": ["fish_rapid", "fish_fire", "fish_saw", "fish_missile", "fish_laser", "fish_chain"]
	}
	for group_id in groups.keys():
		var list: Array = groups[group_id]
		for i in range(list.size()):
			skill_icon_paths[str(list[i])] = "res://AIgame_rougelike/assets/art/skills/%s/%02d_01.png" % [group_id, i + 1]


func _load_balance_config() -> void:
	if not FileAccess.file_exists(BALANCE_CONFIG_PATH):
		return
	var file := FileAccess.open(BALANCE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var enemies: Dictionary = parsed.get("enemies", {})
	for enemy_id in enemies.keys():
		if not enemy_defs.has(enemy_id):
			continue
		var base: Dictionary = enemy_defs[enemy_id]
		var data: Dictionary = enemies[enemy_id]
		for key in data.keys():
			base[key] = data[key]
		enemy_defs[enemy_id] = base
	var skills: Dictionary = parsed.get("skills", {})
	for skill_id in skills.keys():
		if not skill_defs.has(skill_id):
			continue
		var skill: Dictionary = skill_defs[skill_id]
		var data: Dictionary = skills[skill_id]
		for key in data.keys():
			skill[key] = data[key]
		skill_defs[skill_id] = skill
		# 若後台設定了自訂 icon 路徑，覆蓋掉預設依 group/index 算出的圖示路徑。
		if skill.has("icon") and str(skill["icon"]).strip_edges() != "":
			skill_icon_paths[skill_id] = str(skill["icon"])
	var difficulty_data: Dictionary = parsed.get("difficulty", {})
	for difficulty_id in difficulty_data.keys():
		if not difficulty_defs.has(difficulty_id):
			continue
		var base_difficulty: Dictionary = difficulty_defs[difficulty_id]
		var row: Dictionary = difficulty_data[difficulty_id]
		for key in row.keys():
			base_difficulty[key] = row[key]
		difficulty_defs[difficulty_id] = base_difficulty


func _create_world() -> void:
	set_process(true)


func _create_player() -> void:
	player = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.visible = false
	player.stats_changed.connect(_update_ui)
	player.stats_changed.connect(func() -> void:
		if player != null and player.health < _prev_player_health and player.health > 0:
			_play_sfx("player_hurt")
			_camera_shake_strength = 9.0   # 受傷螢幕震動回饋
		if player != null:
			_prev_player_health = player.health
	)
	player.died.connect(_on_player_died)
	player.attack_requested.connect(_on_player_attack_requested)
	player.area_preview_changed.connect(_on_area_preview_changed)
	player.wall_blocked.connect(_on_player_wall_blocked)
	var camera := Camera2D.new()
	camera.position_smoothing_enabled = false
	player.add_child(camera)
	camera.make_current()
	_game_camera = camera


func _create_ui() -> void:
	ui_canvas = CanvasLayer.new()
	ui_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_canvas)

	menu_background = TextureRect.new()
	menu_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	menu_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu_background.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(LOBBY_BACKGROUND_TEXTURE_PATH):
		menu_background.texture = load(LOBBY_BACKGROUND_TEXTURE_PATH) as Texture2D
	ui_canvas.add_child(menu_background)

	hud_layer = Control.new()
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_canvas.add_child(hud_layer)

	# HUD 資訊面板：半透明深色圓角底板＋主題色細框，取代原本裸露的文字
	var hud_panel := PanelContainer.new()
	hud_panel.position = Vector2(12, 10)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.03, 0.05, 0.09, 0.72)
	hud_style.border_color = Color(0.9, 0.65, 0.15, 0.4)
	hud_style.set_border_width_all(2)
	hud_style.set_corner_radius_all(10)
	hud_style.content_margin_left = 14.0
	hud_style.content_margin_right = 16.0
	hud_style.content_margin_top = 10.0
	hud_style.content_margin_bottom = 10.0
	hud_panel.add_theme_stylebox_override("panel", hud_style)
	hud_layer.add_child(hud_panel)
	var hud := VBoxContainer.new()
	hud.add_theme_constant_override("separation", 5)
	hud_panel.add_child(hud)
	heart_label = Label.new()
	_apply_game_font(heart_label, 26, Color(1.0, 0.12, 0.14), 3)
	hud.add_child(heart_label)
	stage_label = Label.new()
	_apply_game_font(stage_label, 22, Color.WHITE, 2)
	hud.add_child(stage_label)
	level_label = Label.new()
	_apply_game_font(level_label, 22, Color.WHITE, 2)
	hud.add_child(level_label)
	chip_label = Label.new()
	_apply_game_font(chip_label, 20, Color(0.9, 0.82, 0.2), 2)
	hud.add_child(chip_label)
	enemy_count_label = Label.new()
	_apply_game_font(enemy_count_label, 20, Color(0.85, 0.85, 0.85), 2)
	hud.add_child(enemy_count_label)
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_game_font(message_label, 30, Color.WHITE, 3)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 28
	message_label.offset_bottom = 78
	hud_layer.add_child(message_label)
	_create_hover_tooltip()

	skill_bar = HBoxContainer.new()
	skill_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	skill_bar.add_theme_constant_override("separation", 8)
	skill_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	skill_bar.offset_top = -112
	skill_bar.offset_bottom = -12
	skill_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	hud_layer.add_child(skill_bar)

	main_menu_overlay = _make_overlay()
	_make_menu(main_menu_overlay, "爆倉倖存者：AI末日777", [
		["開始遊戲", Callable(self, "_start_run").bind("archer")],
		["永久研究中心", _show_research_center],
		["設定", _show_settings],
		["離開遊戲", func() -> void: get_tree().quit()]
	])
	save_overlay = _make_overlay()
	lobby_overlay = _make_overlay()
	character_overlay = _make_overlay()
	level_up_overlay = _make_overlay()
	settings_overlay = _make_overlay()
	game_over_overlay = _make_overlay()
	test_overlay = _make_overlay()
	result_label = Label.new()


func _make_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.04, 0.07, 0.88)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false
	hud_layer.add_child(overlay)
	return overlay


func _create_hover_tooltip() -> void:
	hover_tooltip_panel = PanelContainer.new()
	hover_tooltip_panel.visible = false
	hover_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_tooltip_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	hover_tooltip_panel.z_index = 1000
	hover_tooltip_panel.z_as_relative = false
	hover_tooltip_panel.custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.94)
	style.border_color = Color(0.33, 0.52, 0.68, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	hover_tooltip_panel.add_theme_stylebox_override("panel", style)
	hud_layer.add_child(hover_tooltip_panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	hover_tooltip_panel.add_child(margin)

	hover_tooltip_label = RichTextLabel.new()
	hover_tooltip_label.bbcode_enabled = true
	hover_tooltip_label.fit_content = true
	hover_tooltip_label.scroll_active = false
	hover_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_tooltip_label.custom_minimum_size = Vector2(330, 0)
	_apply_game_font(hover_tooltip_label, 18, Color.WHITE, 1)
	margin.add_child(hover_tooltip_label)


func _show_hover_tooltip(text: String, pos := Vector2.ZERO) -> void:
	if hover_tooltip_panel == null or hover_tooltip_label == null:
		return
	if text.strip_edges() == "":
		return
	hover_tooltip_label.text = text
	# 欄位寬度依內容文字量動態調整：字數少時窄一點，字數多時寬一點（有上下限），
	# 避免短說明留一大片空白，也避免長說明被固定寬度硬擠成很窄很高的框。
	var plain_len := _bbcode_plain_length(text)
	var target_width: float = clampf(220.0 + float(plain_len) * 2.6, 260.0, 480.0)
	hover_tooltip_panel.custom_minimum_size.x = target_width
	hover_tooltip_label.custom_minimum_size.x = target_width - 24.0
	hover_tooltip_panel.visible = true
	var anchor := pos
	if anchor == Vector2.ZERO:
		anchor = get_viewport().get_mouse_position()
	call_deferred("_position_hover_tooltip", anchor)


func _bbcode_plain_length(text: String) -> int:
	# 概略估算 RichTextLabel 實際顯示的文字長度（去除 BBCode 標籤本身，只算內容）。
	var re := RegEx.new()
	re.compile("\\[.*?\\]")
	var stripped := re.sub(text, "", true)
	return stripped.length()


func _position_hover_tooltip(anchor: Vector2) -> void:
	if hover_tooltip_panel == null or not hover_tooltip_panel.visible:
		return
	var viewport_size := get_viewport_rect().size
	var tooltip_size := hover_tooltip_panel.size
	var x: float = clamp(anchor.x + 18.0, 8.0, maxf(8.0, viewport_size.x - tooltip_size.x - 8.0))
	var y: float = clamp(anchor.y - tooltip_size.y - 12.0, 8.0, maxf(8.0, viewport_size.y - tooltip_size.y - 8.0))
	hover_tooltip_panel.position = Vector2(x, y)


func _hide_hover_tooltip() -> void:
	if hover_tooltip_panel != null:
		hover_tooltip_panel.visible = false


func _set_menu_background_visible(should_show: bool) -> void:
	if menu_background != null and is_instance_valid(menu_background):
		menu_background.visible = should_show


func _create_audio() -> void:
	var sfx_names := [
		"hit", "enemy_die", "player_hurt", "player_die",
		"turret_rapid", "turret_fire", "turret_saw", "turret_missile", "turret_laser", "turret_chain",
		"tech_lightning_1", "tech_lightning_2", "tech_lightning_3",
		"turret_chain_1", "turret_chain_2", "turret_chain_3",
		"ui_select", "level_up", "poker_draw", "stage_start", "stage_clear",
		"mahjong_sixi", "mahjong_moon"
	]
	var base_path := "res://AIgame_rougelike/assets/audio/sfx/"
	for sname in sfx_names:
		var is_ogg_sfx := str(sname) == "hit" or str(sname) == "enemy_die"
		var path: String = "res://AIgame_rougelike/assets/audio/" + str(sname) + ".ogg" if is_ogg_sfx else base_path + str(sname) + ".wav"
		var stream: AudioStream = null
		if is_ogg_sfx and ResourceLoader.exists(path):
			stream = load(path) as AudioStream
		elif is_ogg_sfx and FileAccess.file_exists(path):
			stream = AudioStreamOggVorbis.load_from_file(path)
		elif FileAccess.file_exists(path):
			stream = AudioStreamWAV.load_from_file(path)
		elif ResourceLoader.exists(path):
			stream = load(path) as AudioStream
		if stream == null:
			continue
		var audio_player := AudioStreamPlayer.new()
		audio_player.stream = stream
		audio_player.bus = "Master"
		audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(audio_player)
		_sfx[sname] = audio_player
	# 連射砲沿用玩家攻擊命中音效(hit.wav)，但如果直接共用同一個 AudioStreamPlayer，
	# 會被玩家自己非常頻繁的攻擊命中音效互相搶播、蓋掉（同一個 AudioStreamPlayer 同時只能播一次），
	# 導致連射砲的聲音幾乎聽不到、像是「完全沒聲音」。這裡另外建立一個獨立的 AudioStreamPlayer，
	# 但沿用相同的音源（同一份 hit.wav），讓兩者可以同時播放、互不干擾。
	if _sfx.has("hit"):
		var rapid_hit_player := AudioStreamPlayer.new()
		rapid_hit_player.stream = (_sfx["hit"] as AudioStreamPlayer).stream
		rapid_hit_player.bus = "Master"
		rapid_hit_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(rapid_hit_player)
		_sfx["turret_rapid_hit"] = rapid_hit_player
	# ── 背景音樂（循環播放；沒有檔案就靜默略過）──
	var bgm_path := "res://AIgame_rougelike/assets/audio/bgm.ogg"
	var bgm_stream: AudioStream = null
	if ResourceLoader.exists(bgm_path):
		bgm_stream = load(bgm_path) as AudioStream
	elif FileAccess.file_exists(bgm_path):
		bgm_stream = AudioStreamOggVorbis.load_from_file(bgm_path)
	if bgm_stream != null:
		if bgm_stream is AudioStreamOggVorbis:
			(bgm_stream as AudioStreamOggVorbis).loop = true
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.stream = bgm_stream
		_bgm_player.volume_db = -12.0   # 比音效小聲，避免蓋掉打擊回饋
		_bgm_player.bus = "Master"
		_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_bgm_player)
		_bgm_player.play()
		# 保險：就算 loop 屬性沒生效（例如 wav），播完自動重播
		_bgm_player.finished.connect(func() -> void: _bgm_player.play())


func _play_sfx(sname: String, pitch: float = 1.0) -> void:
	if not _sfx.has(sname):
		return
	var ap: AudioStreamPlayer = _sfx[sname] as AudioStreamPlayer
	if ap == null or not is_instance_valid(ap):
		return
	ap.pitch_scale = pitch
	ap.volume_db = 0.0
	ap.play()


func _schedule_sfx_fade(sname: String, ap: AudioStreamPlayer, max_duration: float, fade_duration: float, restore_volume_db: float) -> void:
	if max_duration <= 0.0 or ap == null or not is_instance_valid(ap):
		return
	var token := int(_sfx_play_tokens.get(sname, 0)) + 1
	_sfx_play_tokens[sname] = token
	var timer := get_tree().create_timer(max_duration, false, false, true)
	timer.timeout.connect(func() -> void:
		if int(_sfx_play_tokens.get(sname, -1)) != token:
			return
		if ap == null or not is_instance_valid(ap) or not ap.playing:
			return
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(ap, "volume_db", -60.0, maxf(0.01, fade_duration))
		tween.tween_callback(func() -> void:
			if int(_sfx_play_tokens.get(sname, -1)) != token:
				return
			if ap != null and is_instance_valid(ap):
				ap.stop()
				ap.volume_db = restore_volume_db
		)
	)


func _play_sfx_limited(sname: String, pitch: float = 1.0, max_duration: float = 0.0, fade_duration: float = 0.12) -> void:
	if not _sfx.has(sname):
		return
	var ap: AudioStreamPlayer = _sfx[sname] as AudioStreamPlayer
	if ap == null or not is_instance_valid(ap):
		return
	ap.pitch_scale = pitch
	ap.volume_db = 0.0
	ap.play()
	_schedule_sfx_fade(sname, ap, max_duration, fade_duration, 0.0)


func _play_sfx_volume(sname: String, pitch: float, volume_db: float, max_duration: float = 0.0, fade_duration: float = 0.12) -> void:
	# 與 _play_sfx_limited 相同，但可指定播放音量（例如皇家護衛沿用玩家命中音效但降低音量）。
	if not _sfx.has(sname):
		return
	var ap: AudioStreamPlayer = _sfx[sname] as AudioStreamPlayer
	if ap == null or not is_instance_valid(ap):
		return
	ap.pitch_scale = pitch
	ap.volume_db = volume_db
	ap.play()
	_schedule_sfx_fade(sname, ap, max_duration, fade_duration, volume_db)


func _play_random_sfx(names: Array, pitch: float = 1.0, max_duration: float = 0.0, fade_duration: float = 0.12) -> void:
	if names.is_empty():
		return
	var available: Array[String] = []
	for raw_name in names:
		var sname := str(raw_name)
		if _sfx.has(sname):
			available.append(sname)
	if available.is_empty():
		return
	_play_sfx_limited(available[rng.randi_range(0, available.size() - 1)], pitch, max_duration, fade_duration)


# 砲台音效：依距離衰減。8格內線性 100%→0%，超出則靜音
func _play_turret_sfx(sname: String, turret_pos: Vector2, pitch: float = 1.0) -> void:
	if not _sfx.has(sname):
		return
	var ap: AudioStreamPlayer = _sfx[sname] as AudioStreamPlayer
	if ap == null or not is_instance_valid(ap):
		return
	if player == null or not is_instance_valid(player):
		return
	var dist: float = player.global_position.distance_to(turret_pos)
	# 以螢幕半對角線長度為最大可聽距離（超出螢幕就靜音）
	var vp := get_viewport_rect().size
	var max_dist: float = maxf(vp.x, vp.y) * 0.55
	var vol_factor := clampf(1.0 - dist / max_dist, 0.0, 1.0)
	if vol_factor <= 0.0:
		return
	ap.pitch_scale = pitch
	ap.volume_db = linear_to_db(vol_factor)   # 0→靜音，1→滿音量
	ap.play()


func _play_turret_sfx_limited(sname: String, turret_pos: Vector2, pitch: float = 1.0, max_duration: float = 0.0, fade_duration: float = 0.12) -> void:
	if not _sfx.has(sname):
		return
	var ap: AudioStreamPlayer = _sfx[sname] as AudioStreamPlayer
	if ap == null or not is_instance_valid(ap):
		return
	if player == null or not is_instance_valid(player):
		return
	var dist: float = player.global_position.distance_to(turret_pos)
	var vp := get_viewport_rect().size
	var max_dist: float = maxf(vp.x, vp.y) * 0.55
	var vol_factor := clampf(1.0 - dist / max_dist, 0.0, 1.0)
	if vol_factor <= 0.0:
		return
	var start_volume := linear_to_db(vol_factor)
	ap.pitch_scale = pitch
	ap.volume_db = start_volume
	ap.play()
	_schedule_sfx_fade(sname, ap, max_duration, fade_duration, start_volume)


func _play_turret_sfx_scaled(sname: String, turret_pos: Vector2, volume_scale: float, pitch: float = 1.0, max_duration: float = 0.0, fade_duration: float = 0.12) -> void:
	# 與 _play_turret_sfx_limited 相同（距離衰減），但額外可指定一個 0~1 的音量縮放係數，
	# 用於「砲台沿用玩家攻擊音效但降低音量」的情境（例如連射砲降低30%音量，即 volume_scale=0.7）。
	if not _sfx.has(sname):
		return
	var ap: AudioStreamPlayer = _sfx[sname] as AudioStreamPlayer
	if ap == null or not is_instance_valid(ap):
		return
	if player == null or not is_instance_valid(player):
		return
	var dist: float = player.global_position.distance_to(turret_pos)
	var vp := get_viewport_rect().size
	var max_dist: float = maxf(vp.x, vp.y) * 0.55
	var vol_factor := clampf(1.0 - dist / max_dist, 0.0, 1.0) * clampf(volume_scale, 0.0, 1.0)
	if vol_factor <= 0.0:
		return
	var start_volume := linear_to_db(vol_factor)
	ap.pitch_scale = pitch
	ap.volume_db = start_volume
	ap.play()
	_schedule_sfx_fade(sname, ap, max_duration, fade_duration, start_volume)


func _play_random_turret_sfx(names: Array, turret_pos: Vector2, pitch: float = 1.0, max_duration: float = 0.0, fade_duration: float = 0.12) -> void:
	if names.is_empty():
		return
	var available: Array[String] = []
	for raw_name in names:
		var sname := str(raw_name)
		if _sfx.has(sname):
			available.append(sname)
	if available.is_empty():
		return
	_play_turret_sfx_limited(available[rng.randi_range(0, available.size() - 1)], turret_pos, pitch, max_duration, fade_duration)


func _make_menu(parent: Control, title: String, items: Array, popup_style := false) -> VBoxContainer:
	if popup_style:
		get_tree().paused = true
	for child in parent.get_children():
		child.queue_free()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var box: VBoxContainer
	if popup_style:
		var panel := PanelContainer.new()
		var sbox := StyleBoxFlat.new()
		sbox.bg_color = Color(0.05, 0.07, 0.12, 0.97)
		sbox.set_border_width_all(2)
		sbox.border_color = Color(0.9, 0.65, 0.15, 0.8)   # 與按鈕/HUD 同一主題橘
		sbox.set_corner_radius_all(12)
		sbox.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		sbox.shadow_size = 12
		panel.add_theme_stylebox_override("panel", sbox)
		panel.custom_minimum_size = Vector2(400, 0)
		center.add_child(panel)
		var margin := MarginContainer.new()
		for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
			margin.add_theme_constant_override(side, 22)
		panel.add_child(margin)
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		margin.add_child(box)
	else:
		box = VBoxContainer.new()
		box.custom_minimum_size = Vector2(420, 0)
		box.add_theme_constant_override("separation", 10)
		center.add_child(box)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_game_font(label, 34, Color(1.0, 0.85, 0.35), 4)
	box.add_child(label)
	# 標題下方主題色分隔線
	var divider := ColorRect.new()
	divider.color = Color(0.9, 0.65, 0.15, 0.6)
	divider.custom_minimum_size = Vector2(0, 2)
	box.add_child(divider)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)
	for item in items:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(360, 46)
		_apply_game_font(button, 22, Color.WHITE, 2)
		_style_menu_button(button)
		button.tooltip_text = ""
		if item.size() >= 3:
			var tip_text := str(item[2])
			button.mouse_entered.connect(Callable(self, "_show_hover_tooltip").bind(tip_text))
			button.mouse_exited.connect(_hide_hover_tooltip)
			button.pressed.connect(_hide_hover_tooltip)
		button.pressed.connect(func() -> void: _play_sfx("ui_select"))
		button.pressed.connect(item[1])
		box.add_child(button)
	return box


func _show_main_menu() -> void:
	game_started = false
	_set_menu_background_visible(true)
	get_tree().paused = true
	_hide_all_overlays()
	_sync_current_save_slot()
	main_menu_overlay.visible = true


func _show_save_slots(_is_new: bool) -> void:
	_hide_all_overlays()
	_set_menu_background_visible(true)
	get_tree().paused = true
	save_overlay.visible = true
	for child in save_overlay.get_children():
		child.queue_free()
	var items := []
	for i in range(SAVE_SLOT_COUNT):
		var slot: Dictionary = save_slots[i]
		var label := "欄位 %d｜晶片 %d｜最後：%s" % [i + 1, int(slot.get("total_chips", 0)), str(slot.get("last_played", "無"))]
		items.append([label, Callable(self, "_select_save_slot").bind(i)])
	items.append(["返回", _show_main_menu])
	_make_menu(save_overlay, "選擇存檔欄位", items)


func _show_lobby() -> void:
	_hide_all_overlays()
	_set_menu_background_visible(true)
	get_tree().paused = true
	lobby_overlay.visible = true
	_make_menu(lobby_overlay, "大廳｜永久晶片 %d" % total_chips, [
		["開始遊戲", Callable(self, "_start_run").bind("archer")],
		["永久研究中心", _show_research_center],
		["返回", _show_main_menu]
	])


func _select_save_slot(index: int) -> void:
	selected_save_slot = index
	total_chips = int(save_slots[index].get("total_chips", 0))
	current_research = (save_slots[index].get("research", {}) as Dictionary).duplicate(true)
	_show_lobby()


func _show_research_center() -> void:
	_sync_current_save_slot()
	_hide_all_overlays()
	lobby_overlay.visible = true
	var items := []
	for research_id in permanent_research_defs.keys():
		var def: Dictionary = permanent_research_defs[research_id]
		var lv := int(current_research.get(research_id, 0))
		var max_lv := int(def.get("max_level", 3))
		var cost := _research_cost(research_id)
		var label := "%s LV%d/%d｜%s" % [str(def.get("name", research_id)), lv, max_lv, "已滿級" if lv >= max_lv else "花費 %d 晶片" % cost]
		var tip := "%s\n%s\n目前晶片：%d" % [label, str(def.get("desc", "")), total_chips]
		items.append([label, Callable(self, "_buy_research").bind(research_id), tip])
	items.append(["返回", _show_main_menu])
	_make_menu(lobby_overlay, "永久研究中心｜永久晶片 %d" % total_chips, items)


func _research_cost(research_id: String) -> int:
	var def: Dictionary = permanent_research_defs.get(research_id, {})
	var base_cost: int = max(3, int(def.get("base_cost", 3)))
	var lv := int(current_research.get(research_id, 0))
	return max(3, base_cost * (lv + 1))


func _buy_research(research_id: String) -> void:
	var def: Dictionary = permanent_research_defs.get(research_id, {})
	var lv := int(current_research.get(research_id, 0))
	var max_lv := int(def.get("max_level", 3))
	if lv >= max_lv:
		_flash_message("已達最高等級")
		_show_research_center()
		return
	var cost := _research_cost(research_id)
	if total_chips < cost:
		_flash_message("晶片不足")
		_show_research_center()
		return
	total_chips -= cost
	current_research[research_id] = lv + 1
	_save_current_slot()
	_flash_message("%s 升到 LV%d" % [str(def.get("name", research_id)), lv + 1])
	_show_research_center()


func _show_character_select() -> void:
	_hide_all_overlays()
	character_overlay.visible = true
	for child in character_overlay.get_children():
		child.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	character_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "選擇角色"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	var char_defs := [
		{
			"id": "warrior",
			"icon": "res://AIgame_rougelike/assets/art/characters/player/warrior/icon.png",
			"name": "⚔ 戰士",
			"desc": "近戰｜傷害 2｜範圍 2格｜攻速 2/s\n攻擊前集氣 0.3s，揮出後擊退 0.5格\n60秒無損自動回 1 血",
			"color": Color(0.9, 0.7, 0.2)
		},
		{
			"id": "archer",
			"icon": "res://AIgame_rougelike/assets/art/characters/player/archer_icon.png",
			"name": "🔫 槍手",
			"desc": "遠程｜傷害 1｜範圍 5格｜攻速 3/s\n基礎爆擊率 +10%，命中擊退 0.3格",
			"color": Color(0.4, 0.9, 0.4)
		},
		{
			"id": "mage",
			"icon": "res://AIgame_rougelike/assets/art/characters/player/mage_icon.png",
			"name": "✨ 法師",
			"desc": "範圍攻擊｜傷害 1｜範圍 5格｜攻速 0.5/s\n技能範圍 +20%，無擊退",
			"color": Color(0.7, 0.4, 1.0)
		}
	]

	for def in char_defs:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 14)
		vbox.add_child(hbox)

		# Icon
		var icon_tex: TextureRect = TextureRect.new()
		icon_tex.custom_minimum_size = Vector2(80, 80)
		icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path: String = str(def.get("icon", ""))
		if ResourceLoader.exists(icon_path):
			icon_tex.texture = load(icon_path)
		hbox.add_child(icon_tex)

		# 名稱 + 說明
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_box)

		var name_lbl := Label.new()
		name_lbl.text = str(def.get("name", ""))
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color(def.get("color", Color.WHITE)))
		info_box.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = str(def.get("desc", ""))
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(desc_lbl)

		# 選擇按鈕
		var btn := Button.new()
		btn.text = "選擇"
		btn.custom_minimum_size = Vector2(72, 56)
		_style_menu_button(btn)
		var cid: String = str(def.get("id", "warrior"))
		btn.pressed.connect(Callable(self, "_start_run").bind(cid))
		if cid == "archer":
			btn.text = "選擇"
		else:
			btn.text = "暫停開放"
			btn.disabled = true
		hbox.add_child(btn)

	# 返回按鈕
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.custom_minimum_size = Vector2(360, 40)
	_style_menu_button(back_btn)
	back_btn.pressed.connect(_show_lobby)
	vbox.add_child(back_btn)


func _enter_test_mode() -> void:
	_hide_all_overlays()
	_set_menu_background_visible(false)
	is_test_mode = true
	get_tree().paused = false
	game_started = true
	is_game_ended = false
	current_stage = 1
	kill_count = 0
	sanyuan_hit_counter = 0
	_setup_stage_map()
	_clear_world_objects(false)
	active_poker_buffs.clear()
	poker_deck = []   # 動態依玩家技能建立
	poker_discard.clear()
	_poker_deck_signature = ""
	player.visible = true
	player.setup_character("archer")
	player.global_position = Vector2.ZERO
	_update_ui()
	get_tree().paused = true
	_show_test_overlay()


func _show_test_overlay() -> void:
	get_tree().paused = true
	_hide_all_overlays()
	if test_overlay is ColorRect:
		(test_overlay as ColorRect).color = Color(0.02, 0.04, 0.07, 0.35)
	test_overlay.visible = true
	for child in test_overlay.get_children():
		child.queue_free()

	var scroll_root := ScrollContainer.new()
	scroll_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_root.process_mode = Node.PROCESS_MODE_ALWAYS
	test_overlay.add_child(scroll_root)

	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(680, 0)
	center.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(660, 0)
	center.add_child(vbox)

	# 標題
	var title := Label.new()
	title.text = "🧪 測試模式　　[F1] 暫停/繼續　　[ESC] 回主選單"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# === 怪物設定 ===
	var lbl_e := Label.new()
	lbl_e.text = "怪物設定"
	lbl_e.add_theme_font_size_override("font_size", 16)
	vbox.add_child(lbl_e)

	var hbox_e := HBoxContainer.new()
	hbox_e.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_e)

	var lbl_etype := Label.new()
	lbl_etype.text = "種類："
	hbox_e.add_child(lbl_etype)

	var enemy_opt := OptionButton.new()
	enemy_opt.custom_minimum_size = Vector2(150, 36)
	var enemy_keys: Array = enemy_defs.keys()
	var enemy_sel := 0
	for ei in range(enemy_keys.size()):
		var ek := str(enemy_keys[ei])
		enemy_opt.add_item(str(enemy_defs[ek].get("name", ek)))
		if ek == _test_enemy_id:
			enemy_sel = ei
	enemy_opt.selected = enemy_sel
	enemy_opt.item_selected.connect(func(idx: int) -> void:
		_test_enemy_id = str(enemy_keys[idx])
	)
	hbox_e.add_child(enemy_opt)

	var lbl_cnt_h := Label.new()
	lbl_cnt_h.text = "  數量："
	hbox_e.add_child(lbl_cnt_h)

	var cnt_val_lbl := Label.new()
	cnt_val_lbl.text = str(_test_enemy_count)
	cnt_val_lbl.custom_minimum_size.x = 34
	cnt_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	for dv in [-10, -5, -1, 1, 5, 10]:
		var dbtn := Button.new()
		dbtn.text = "%+d" % dv
		dbtn.custom_minimum_size = Vector2(44, 32)
		var cap_dv: int = int(dv)
		dbtn.pressed.connect(func() -> void:
			_test_enemy_count = max(1, _test_enemy_count + cap_dv)
			cnt_val_lbl.text = str(_test_enemy_count)
		)
		hbox_e.add_child(dbtn)
		if dv == -1:
			hbox_e.add_child(cnt_val_lbl)

	vbox.add_child(HSeparator.new())

	# === 角色選擇 ===
	var lbl_char := Label.new()
	lbl_char.text = "角色選擇"
	lbl_char.add_theme_font_size_override("font_size", 16)
	vbox.add_child(lbl_char)

	var hbox_char := HBoxContainer.new()
	hbox_char.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_char)

	var cnames := {"warrior": "戰士", "archer": "槍手", "mage": "法師"}
	for cid in ["warrior", "archer", "mage"]:
		var cbtn := Button.new()
		cbtn.text = cnames[cid]
		cbtn.toggle_mode = true
		cbtn.button_pressed = (_test_character_id == cid)
		cbtn.custom_minimum_size = Vector2(90, 36)
		var cap_cid: String = str(cid)
		cbtn.pressed.connect(func() -> void:
			_test_character_id = cap_cid
			# 更新所有角色按鈕視覺（重建 UI 成本高，直接更新 toggle 即可）
		)
		hbox_char.add_child(cbtn)

	vbox.add_child(HSeparator.new())

	# === 技能設定（5個下拉選單）===
	var lbl_sk := Label.new()
	lbl_sk.text = "技能設定（最多 5 個技能槽）"
	lbl_sk.add_theme_font_size_override("font_size", 16)
	vbox.add_child(lbl_sk)

	var skill_keys: Array = skill_defs.keys()
	for slot_i in range(5):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var slot_lbl := Label.new()
		slot_lbl.text = "槽 %d：" % (slot_i + 1)
		slot_lbl.custom_minimum_size.x = 50
		row.add_child(slot_lbl)

		var sk_opt := OptionButton.new()
		sk_opt.custom_minimum_size = Vector2(230, 36)
		sk_opt.add_item("（空）")
		for ski in range(skill_keys.size()):
			var sk_key := str(skill_keys[ski])
			var sd: Dictionary = skill_defs[sk_key]
			sk_opt.add_item("[%s] %s" % [sd.get("school", ""), sd.get("name", sk_key)])
		# 設定目前選擇
		var cur_slot: Dictionary = _test_skill_slots[slot_i]
		var cur_id: String = str(cur_slot.get("id", ""))
		var sel_sk_idx := 0
		if cur_id != "":
			for ski in range(skill_keys.size()):
				if str(skill_keys[ski]) == cur_id:
					sel_sk_idx = ski + 1
					break
		sk_opt.selected = sel_sk_idx
		var cap_si := slot_i
		sk_opt.item_selected.connect(func(idx: int) -> void:
			if idx == 0:
				_test_skill_slots[cap_si]["id"] = ""
				_test_skill_slots[cap_si]["lv"] = 0
			else:
				_test_skill_slots[cap_si]["id"] = str(skill_keys[idx - 1])
				if int(_test_skill_slots[cap_si].get("lv", 0)) == 0:
					_test_skill_slots[cap_si]["lv"] = 1
		)
		row.add_child(sk_opt)

		var lv_opt := OptionButton.new()
		lv_opt.custom_minimum_size = Vector2(70, 36)
		for lv in range(7):
			lv_opt.add_item("Lv %d" % lv)
		lv_opt.selected = int(cur_slot.get("lv", 0))
		lv_opt.item_selected.connect(func(lv_idx: int) -> void:
			_test_skill_slots[cap_si]["lv"] = lv_idx
		)
		row.add_child(lv_opt)

		# 顯示目前槽內容
		var cur_lbl := Label.new()
		cur_lbl.add_theme_font_size_override("font_size", 12)
		cur_lbl.modulate = Color(0.75, 0.95, 0.75)
		if cur_id != "" and skill_defs.has(cur_id):
			var sd2: Dictionary = skill_defs[cur_id]
			cur_lbl.text = "（[%s]%s Lv%d）" % [sd2.get("school", ""), sd2.get("name", cur_id), int(cur_slot.get("lv", 0))]
		row.add_child(cur_lbl)

	vbox.add_child(HSeparator.new())

	# === 生成按鈕（統一，清空 + 套用 + 開始）===
	var btn_gen := Button.new()
	btn_gen.text = "▶ 生成（套用設定 + 重新生成敵人 + 開始）"
	btn_gen.custom_minimum_size = Vector2(380, 44)
	btn_gen.add_theme_font_size_override("font_size", 16)
	btn_gen.pressed.connect(func() -> void:
		# 套用角色
		player.setup_character(_test_character_id)
		# 套用技能
		for slot in _test_skill_slots:
			var sid2: String = str(slot.get("id", ""))
			var slv: int = int(slot.get("lv", 0))
			if sid2 != "" and slv > 0:
				player.selected_skills[sid2] = slv
		player.stats_changed.emit()
		# 清空並重新生成敵人
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		stage_enemies_alive = 0
		for _gi in range(_test_enemy_count):
			_spawn_wave_enemy(_test_enemy_id, _random_spawn_position())
		# 測試模式先前沒有比照正式關卡「開局立即觸發抽牌」的邏輯，
		# 導致每次按「生成」都要重新等滿 20 秒才會抽到第一張牌，容易誤以為完全不會抽牌。
		# 這裡強制牌組依目前技能設定重建，並讓計時器歸零，按下生成後立即抽一次牌。
		if _has_poker_skill():
			poker_deck.clear()
			_poker_deck_signature = ""
			poker_timer = 0.0
		_hide_all_overlays()
		get_tree().paused = false
	)
	vbox.add_child(btn_gen)

	var btn_clear := Button.new()
	btn_clear.text = "清空全部敵人"
	btn_clear.custom_minimum_size = Vector2(160, 36)
	btn_clear.pressed.connect(func() -> void:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		stage_enemies_alive = 0
		_update_ui()
	)
	vbox.add_child(btn_clear)


func _show_settings() -> void:
	_hide_all_overlays()
	settings_overlay.visible = true
	var vol_level: int = int(round(float(game_settings.get("volume", 0.8)) * 10.0))
	var difficulty_id := str(game_settings.get("difficulty", "normal"))
	var difficulty: Dictionary = difficulty_defs.get(difficulty_id, difficulty_defs["normal"])
	var keys: Dictionary = game_settings.get("keys", {})
	var rebind_line := ""
	if _pending_rebind_action != "":
		rebind_line = "\n正在設定：%s，請按下一個按鍵或滑鼠鍵" % _pending_rebind_label
	# （2026-07-07）砲台1~6鍵的重綁定項目已依需求移除（熱鍵仍為預設 1~6）
	var items := [
		["難度：%s" % str(difficulty.get("name", "一般")), _cycle_difficulty, "一般：目前數值、5 顆愛心。\n困難：怪物數值 ×1.5、4 顆愛心。\n專家：怪物數值 ×2.5、3 顆愛心。"],
		["設定攻擊鍵（目前 %s）" % _binding_name_to_text(str(keys.get("attack", "MouseLeft"))), Callable(self, "_begin_rebind").bind("attack", "攻擊")],
		["設定衝刺鍵（目前 %s）" % _binding_name_to_text(str(keys.get("dash", "Space"))), Callable(self, "_begin_rebind").bind("dash", "衝刺")],
		["返回", _show_main_menu],
	]
	var box := _make_menu(settings_overlay, "設定%s" % rebind_line, items)
	# ── 音量列：−／＋ 按鈕 ──
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	var vol_minus := Button.new()
	vol_minus.text = "−"
	vol_minus.custom_minimum_size = Vector2(64, 46)
	_apply_game_font(vol_minus, 26, Color.WHITE, 2)
	_style_menu_button(vol_minus)
	vol_minus.pressed.connect(func() -> void:
		_play_sfx("ui_select")
		_change_volume(-0.1)
	)
	vol_row.add_child(vol_minus)
	var vol_label := Label.new()
	vol_label.text = "音量  %d / 10" % vol_level
	vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vol_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_game_font(vol_label, 22, Color.WHITE, 2)
	vol_row.add_child(vol_label)
	var vol_plus := Button.new()
	vol_plus.text = "＋"
	vol_plus.custom_minimum_size = Vector2(64, 46)
	_apply_game_font(vol_plus, 26, Color.WHITE, 2)
	_style_menu_button(vol_plus)
	vol_plus.pressed.connect(func() -> void:
		_play_sfx("ui_select")
		_change_volume(0.1)
	)
	vol_row.add_child(vol_plus)
	box.add_child(vol_row)
	box.move_child(vol_row, 3)   # 排在標題/分隔線/間距之後 = 第一個項目位置


func _cycle_volume() -> void:
	var vol_level: int = int(round(float(game_settings.get("volume", 0.8)) * 10.0))
	vol_level = (vol_level + 1) % 11
	game_settings["volume"] = float(vol_level) / 10.0
	_apply_volume()
	_save_settings()
	_show_settings()


func _change_volume(delta: float) -> void:
	game_settings["volume"] = clamp(float(game_settings.get("volume", 0.8)) + delta, 0.0, 1.0)
	_apply_volume()
	_save_settings()
	_show_settings()


func _cycle_difficulty() -> void:
	var order := ["normal", "hard", "expert"]
	var current := str(game_settings.get("difficulty", "normal"))
	var idx := order.find(current)
	game_settings["difficulty"] = order[(idx + 1) % order.size()]
	_save_settings()
	_show_settings()


func _begin_rebind(action: String, label: String) -> void:
	_pending_rebind_action = action
	_pending_rebind_label = label
	_show_settings()
	# 在最上層加入透明攔截板，確保任何滑鼠/鍵盤事件都能被 _input 捕獲
	if _rebind_blocker != null:
		_rebind_blocker.queue_free()
	_rebind_blocker = ColorRect.new()
	_rebind_blocker.color = Color(0.0, 0.0, 0.0, 0.0)   # 完全透明
	_rebind_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rebind_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_rebind_blocker.z_index = 999
	_rebind_blocker.z_as_relative = false
	_rebind_blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_canvas.add_child(_rebind_blocker)


func _cancel_rebind() -> void:
	_pending_rebind_action = ""
	_pending_rebind_label = ""
	if _rebind_blocker != null:
		_rebind_blocker.queue_free()
		_rebind_blocker = null


func _show_pause() -> void:
	get_tree().paused = true
	_manual_pause_active = true
	mage_preview_visible = false
	queue_redraw()
	if settings_overlay is ColorRect:
		(settings_overlay as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	settings_overlay.visible = true
	_make_menu(settings_overlay, "⏸ 暫停", [
		["繼續遊戲", Callable(self, "_resume_game")],
		["回大廳", _return_to_lobby]
	], true)


func _resume_game() -> void:
	_manual_pause_active = false
	settings_overlay.visible = false
	_hide_hover_tooltip()
	get_tree().paused = false


func _hide_all_overlays() -> void:
	_manual_pause_active = false
	_hide_hover_tooltip()
	for overlay in [main_menu_overlay, save_overlay, lobby_overlay, character_overlay, level_up_overlay, settings_overlay, game_over_overlay, test_overlay]:
		if overlay != null:
			overlay.visible = false


func _start_run(character_id: String) -> void:
	_hide_all_overlays()
	_set_menu_background_visible(false)
	_sync_current_save_slot()
	is_test_mode = false
	get_tree().paused = false
	game_started = true
	is_game_ended = false
	current_stage = 1
	_show_controls_hint()
	kill_count = 0
	sanyuan_hit_counter = 0
	sanyuan_pending = false
	flush_cooldown = 5.0
	moon_cooldown = 0.0
	_clear_poker_indicators()
	_reset_poker_draw_animation()
	sixi_orbit_angle = 0.0
	sixi_hit_cds.clear()
	_clear_world_objects(false)
	active_poker_buffs.clear()
	poker_deck = []   # 動態依玩家技能建立
	poker_discard.clear()
	_poker_deck_signature = ""
	player.visible = true
	player.setup_character(character_id)
	_apply_run_difficulty_to_player()
	_apply_permanent_research_to_player()
	player.global_position = Vector2.ZERO
	_setup_stage_map()
	_update_ui()
	_start_stage_with_preview(current_stage)


func _difficulty_enemy_multiplier() -> float:
	var difficulty_id := str(game_settings.get("difficulty", "normal"))
	var difficulty: Dictionary = difficulty_defs.get(difficulty_id, difficulty_defs["normal"])
	return float(difficulty.get("enemy_multiplier", 1.0))


func _difficulty_player_hearts() -> int:
	var difficulty_id := str(game_settings.get("difficulty", "normal"))
	var difficulty: Dictionary = difficulty_defs.get(difficulty_id, difficulty_defs["normal"])
	return int(difficulty.get("player_hearts", 5))


func _apply_run_difficulty_to_player() -> void:
	if player == null:
		return
	player.max_health = _difficulty_player_hearts()
	player.health = player.max_health
	player.stats_changed.emit()


func _apply_permanent_research_to_player() -> void:
	if player == null:
		return
	var damage_lv := int(current_research.get("start_damage", 0))
	if damage_lv > 0:
		player.attack_damage *= 1.0 + 0.50 + 0.20 * max(0, damage_lv - 1)
	var crit_lv := int(current_research.get("crit_rate", 0))
	if crit_lv > 0:
		player.crit_chance += 0.20 + 0.10 * max(0, crit_lv - 1)
	# 多重攻擊
	_multi_attack_count = 2 if int(current_research.get("multi_attack", 0)) >= 1 else 1
	var random_lv := int(current_research.get("start_random_skill", 0))
	if random_lv > 0:
		var ids: Array = skill_defs.keys()
		if not ids.is_empty():
			player.grant_skill(str(ids[rng.randi_range(0, ids.size() - 1)]))
	_permanent_regen_timer = 0.0
	player.stats_changed.emit()


func _clear_world_objects(keep_turrets := false, keep_summons := false) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	stage_enemies_alive = 0
	# 清除尚未生成完的怪物排隊佇列，避免上一關殘留的生成排程混進新關卡。
	_pending_stage_spawns.clear()
	_stage_spawn_active = false
	for drop in get_tree().get_nodes_in_group("drops"):
		if is_instance_valid(drop):
			drop.queue_free()
	for slot_machine in get_tree().get_nodes_in_group("slot_machines"):
		if is_instance_valid(slot_machine):
			slot_machine.queue_free()
	for warning in get_tree().get_nodes_in_group("stage_spawn_warnings"):
		if is_instance_valid(warning):
			warning.queue_free()
	_stage_spawn_warning_nodes.clear()
	for node in get_tree().get_nodes_in_group("damage_numbers"):
		if is_instance_valid(node):
			node.queue_free()
	for node in get_tree().get_nodes_in_group("transient_effects"):
		if is_instance_valid(node):
			node.queue_free()
	for item in bullets:
		if item is Dictionary:
			var bn: Node2D = item.get("node")
			if is_instance_valid(bn):
				bn.queue_free()
		elif item is Node and is_instance_valid(item):
			item.queue_free()
	bullets.clear()
	_clear_poker_indicators()
	_reset_poker_draw_animation()
	if not keep_summons:
		# 換關時保留大四喜、海底撈月、皇家護衛等玩家技能召喚物，只有真正重開/回大廳才清除
		_clear_sixi_tiles()
		_clear_moon_tiles()
		for pet in _poker_guard_pets:
			if is_instance_valid(pet):
				pet.queue_free()
		_poker_guard_pets.clear()
	if active_magnet != null and is_instance_valid(active_magnet):
		active_magnet.queue_free()
	active_magnet = null
	if _attack_preview_node != null and is_instance_valid(_attack_preview_node):
		_attack_preview_node.queue_free()
		_attack_preview_node = null
	if not keep_turrets:
		for turret in turrets:
			var n: Node2D = turret.get("node")
			if is_instance_valid(n):
				n.queue_free()
		turrets.clear()
	_stage_preview_positions.clear()
	_stage_previewing = false
	_stage_preview_timer = 0.0


func _setup_stage_map() -> void:
	var viewport_size := get_viewport_rect().size
	var map_size := viewport_size * 3.0
	map_rect = Rect2(-map_size * 0.5, map_size)
	_generate_wall_points()
	_generate_stage_terrain(current_stage)
	queue_redraw()


func _get_stage_theme(stage_number: int) -> Dictionary:
	var idx: int = clampi((stage_number - 1) / 5, 0, stage_theme_defs.size() - 1)
	return stage_theme_defs[idx]


func _generate_stage_terrain(stage_number: int) -> void:
	terrain_zones.clear()
	_player_fire_tick = 0.0
	if map_rect.size == Vector2.ZERO:
		return
	var theme: Dictionary = _get_stage_theme(stage_number)
	var zone_plan: Dictionary = theme.get("zones", {})
	for ztype in zone_plan.keys():
		var count_range: Array = zone_plan[ztype]
		var count: int = rng.randi_range(int(count_range[0]), int(count_range[1]))
		for _i in range(count):
			# （2026-07-07）範圍加大 3 格（+192px）
			var radius := rng.randf_range(302.0, 372.0)
			var zone_pos := _random_terrain_position(radius)
			if zone_pos == Vector2.INF:
				continue
			terrain_zones.append({"type": str(ztype), "pos": zone_pos, "radius": radius, "seed": rng.randi()})
	# 裝飾岩石：純視覺、不阻擋移動，避開中心與功能地形
	_decor_rocks.clear()
	var rock_count := rng.randi_range(6, 10)
	for _r in range(rock_count):
		var rock_size := rng.randf_range(18.0, 38.0)
		var rock_pos := _random_terrain_position(rock_size + 40.0)
		if rock_pos == Vector2.INF:
			continue
		_decor_rocks.append({"pos": rock_pos, "size": rock_size, "seed": rng.randi()})


func _random_terrain_position(radius: float) -> Vector2:
	# 嘗試找一個離玩家出生點（地圖中心）夠遠、且不跟其他地形重疊太多的位置
	var margin := 220.0
	for _attempt in range(14):
		var candidate := Vector2(
			rng.randf_range(map_rect.position.x + margin, map_rect.end.x - margin),
			rng.randf_range(map_rect.position.y + margin, map_rect.end.y - margin)
		)
		if candidate.length() < 320.0:
			continue  # 保留中心安全區，玩家出生不會直接踩到地形
		var overlapped := false
		for zone in terrain_zones:
			if candidate.distance_to(zone["pos"]) < (radius + float(zone["radius"])) * 0.8:
				overlapped = true
				break
		if not overlapped:
			return candidate
	return Vector2.INF


func _generate_wall_points() -> void:
	var segments := 16
	var wiggle := TILE_SIZE * 0.42
	wall_points = {
		"top": _make_wall_edge(map_rect.position, Vector2(map_rect.end.x, map_rect.position.y), Vector2.DOWN, segments, wiggle),
		"right": _make_wall_edge(Vector2(map_rect.end.x, map_rect.position.y), map_rect.end, Vector2.LEFT, segments, wiggle),
		"bottom": _make_wall_edge(map_rect.end, Vector2(map_rect.position.x, map_rect.end.y), Vector2.UP, segments, wiggle),
		"left": _make_wall_edge(Vector2(map_rect.position.x, map_rect.end.y), map_rect.position, Vector2.RIGHT, segments, wiggle)
	}


func _make_wall_edge(start: Vector2, end: Vector2, bend_axis: Vector2, segments: int, wiggle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var point := start.lerp(end, t)
		if i > 0 and i < segments:
			point += bend_axis * rng.randf_range(-wiggle, wiggle)
		points.append(point)
	return points


func _draw() -> void:
	if map_rect.size == Vector2.ZERO:
		return
	var theme: Dictionary = _get_stage_theme(current_stage)
	# ── 地圖外流動背景（漂浮島感）──
	_draw_void_background(theme)
	# ── 懸崖底座（島嶼厚度與側面）──
	_draw_island_base()
	# ── 主題地板：優先使用平鋪貼圖，無貼圖時退回純色 ──
	var floor_tex := _load_map_texture(str(theme.get("floor_tex", "")))
	var floor_color: Color = theme.get("floor", Color(0.0, 0.0, 0.0, 1.0))
	if floor_tex != null:
		draw_texture_rect(floor_tex, map_rect, true)
		# 壓一層主題色薄紗統一色調，並稍微壓暗讓角色浮出
		draw_rect(map_rect, Color(floor_color.r, floor_color.g, floor_color.b, 0.16))
	else:
		draw_rect(map_rect, floor_color)
	# ── 主題格線（貼圖模式下降低透明度，只保留輔助定位）──
	var grid_color: Color = theme.get("grid", Color(0.22, 0.22, 0.22, 1.0))
	if floor_tex != null:
		grid_color.a = 0.30
	var grid_width := 1.0
	var x := snappedf(map_rect.position.x, TILE_SIZE)
	while x <= map_rect.end.x:
		draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), grid_color, grid_width)
		x += TILE_SIZE
	var y := snappedf(map_rect.position.y, TILE_SIZE)
	while y <= map_rect.end.y:
		draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), grid_color, grid_width)
		y += TILE_SIZE
	# ── 主題地板裝飾（依關卡編號固定種子，畫面不會每幀閃爍；貼圖模式下略過，避免打架）──
	if floor_tex == null:
		_draw_stage_decor(theme)
	# ── 裝飾岩石（純視覺、不阻擋）──
	_draw_decor_rocks(theme)
	# ── 功能地形區塊 ──
	_draw_terrain_zones()
	# ── 場地邊界（主題色實線）──
	if not wall_points.is_empty():
		var border_color: Color = theme.get("border", Color(0.9, 0.65, 0.15, 1.0))
		var border_w := 5.0
		for edge_key in ["top", "right", "bottom", "left"]:
			var pts: PackedVector2Array = wall_points.get(edge_key, PackedVector2Array())
			if pts.size() >= 2:
				draw_polyline(pts, border_color, border_w)


func _load_map_texture(file_name: String) -> Texture2D:
	# 地圖貼圖載入（含快取）：優先走資源系統，未匯入時退回直接讀檔；找不到回傳 null（安全退化為純色）
	if file_name.is_empty():
		return null
	if _terrain_tex_cache.has(file_name):
		return _terrain_tex_cache[file_name]
	var path := TERRAIN_TEX_DIR + file_name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_terrain_tex_cache[file_name] = tex
	return tex


func _draw_void_background(theme: Dictionary) -> void:
	# 地圖外的流動虛空背景：大張雲霧圖以地圖中心為軸極慢旋轉，色調跟隨主題
	var bg_tex := _load_map_texture("bg_void.png")
	if bg_tex == null:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	var border_color: Color = theme.get("border", Color(0.9, 0.65, 0.15))
	var tint := border_color.lerp(Color(0.55, 0.5, 0.45), 0.45)
	var bg_size: float = maxf(map_rect.size.x, map_rect.size.y) * 2.4
	draw_set_transform(Vector2.ZERO, t * 0.015, Vector2.ONE)
	draw_texture_rect(bg_tex, Rect2(Vector2(-bg_size * 0.5, -bg_size * 0.5), Vector2(bg_size, bg_size)), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_island_base() -> void:
	# 漂浮島底座：地圖外圈一圈深色岩緣＋南側「側面厚度」與裂縫，做出高度感
	var base_rect := map_rect.grow(34.0)
	draw_rect(base_rect, Color(0.10, 0.09, 0.08, 1.0))
	# 南側側面（偽 3D 厚度）
	var side_height := 48.0
	draw_rect(Rect2(Vector2(base_rect.position.x, base_rect.end.y), Vector2(base_rect.size.x, side_height)),
		Color(0.06, 0.055, 0.05, 1.0))
	# 側面底部再一層更暗，增加立體
	draw_rect(Rect2(Vector2(base_rect.position.x, base_rect.end.y + side_height), Vector2(base_rect.size.x, 14.0)),
		Color(0.03, 0.028, 0.025, 1.0))
	# 側面直向裂縫（固定種子）
	var crack_rng := RandomNumberGenerator.new()
	crack_rng.seed = 4451
	var cx := base_rect.position.x + crack_rng.randf_range(30.0, 90.0)
	while cx < base_rect.end.x - 20.0:
		var top_y := base_rect.end.y + crack_rng.randf_range(2.0, 10.0)
		var len_y := crack_rng.randf_range(side_height * 0.4, side_height * 0.95)
		draw_line(Vector2(cx, top_y), Vector2(cx + crack_rng.randf_range(-6.0, 6.0), top_y + len_y),
			Color(0.02, 0.02, 0.02, 0.8), crack_rng.randf_range(1.5, 3.0))
		cx += crack_rng.randf_range(55.0, 130.0)


func _draw_decor_rocks(theme: Dictionary) -> void:
	if _decor_rocks.is_empty():
		return
	var border_color: Color = theme.get("border", Color(0.9, 0.65, 0.15))
	for rock in _decor_rocks:
		var pos: Vector2 = rock["pos"]
		var size: float = float(rock["size"])
		var rock_rng := RandomNumberGenerator.new()
		rock_rng.seed = int(rock["seed"])
		# 影子（壓扁橢圓）
		draw_set_transform(pos + Vector2(3.0, size * 0.5), 0.0, Vector2(1.0, 0.38))
		draw_circle(Vector2.ZERO, size * 0.95, Color(0.0, 0.0, 0.0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 岩石本體（不規則多邊形，往上偏移做假高度）
		var pts := PackedVector2Array()
		var point_count := 8
		for i in range(point_count):
			var ang := TAU * float(i) / float(point_count)
			pts.append(Vector2.RIGHT.rotated(ang) * size * rock_rng.randf_range(0.72, 1.12) - Vector2(0.0, size * 0.4))
		draw_set_transform(pos, 0.0, Vector2.ONE)
		draw_colored_polygon(pts, Color(0.13, 0.12, 0.11, 1.0))
		# 亮面（左上受光）＋主題色微光邊
		var hi_pts := PackedVector2Array()
		for p in pts:
			hi_pts.append(p * 0.62 + Vector2(-size * 0.12, -size * 0.2))
		draw_colored_polygon(hi_pts, Color(0.20, 0.19, 0.175, 1.0))
		draw_polyline(pts, Color(border_color.r, border_color.g, border_color.b, 0.18), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stage_decor(theme: Dictionary) -> void:
	# 用固定種子的獨立 RNG，確保同一關每一幀畫出的裝飾完全相同
	var deco_rng := RandomNumberGenerator.new()
	deco_rng.seed = int(current_stage) * 7919 + 13
	var decor_style: String = str(theme.get("decor", "tile"))
	var grid_color: Color = theme.get("grid", Color(0.22, 0.22, 0.22))
	match decor_style:
		"tile":
			# 隨機亮/暗地磚
			for _i in range(46):
				var cx := snappedf(deco_rng.randf_range(map_rect.position.x, map_rect.end.x), TILE_SIZE)
				var cy := snappedf(deco_rng.randf_range(map_rect.position.y, map_rect.end.y), TILE_SIZE)
				var shade := deco_rng.randf_range(-0.5, 0.9)
				var tile_color := Color(grid_color.r, grid_color.g, grid_color.b, 0.10 + 0.08 * absf(shade))
				draw_rect(Rect2(Vector2(cx, cy), Vector2(TILE_SIZE, TILE_SIZE)), tile_color)
		"moss":
			# 苔蘚／污漬斑塊
			for _i in range(40):
				var pos := Vector2(
					deco_rng.randf_range(map_rect.position.x, map_rect.end.x),
					deco_rng.randf_range(map_rect.position.y, map_rect.end.y)
				)
				var r := deco_rng.randf_range(10.0, 42.0)
				draw_circle(pos, r, Color(0.12, 0.2, 0.1, deco_rng.randf_range(0.08, 0.2)))
		"crack":
			# 地面裂痕（短折線）
			for _i in range(34):
				var start := Vector2(
					deco_rng.randf_range(map_rect.position.x, map_rect.end.x),
					deco_rng.randf_range(map_rect.position.y, map_rect.end.y)
				)
				var pts := PackedVector2Array([start])
				var dir := Vector2.RIGHT.rotated(deco_rng.randf_range(0.0, TAU))
				for _seg in range(3):
					dir = dir.rotated(deco_rng.randf_range(-0.8, 0.8))
					pts.append(pts[pts.size() - 1] + dir * deco_rng.randf_range(20.0, 55.0))
				draw_polyline(pts, Color(grid_color.r * 1.6, grid_color.g * 1.2, grid_color.b, 0.35), 2.0)
		"circuit":
			# 電路板走線（直角線段＋節點）
			for _i in range(30):
				var start := Vector2(
					snappedf(deco_rng.randf_range(map_rect.position.x, map_rect.end.x), TILE_SIZE),
					snappedf(deco_rng.randf_range(map_rect.position.y, map_rect.end.y), TILE_SIZE)
				)
				var mid := start + Vector2(deco_rng.randi_range(1, 4) * TILE_SIZE * (1 if deco_rng.randf() < 0.5 else -1), 0)
				var end := mid + Vector2(0, deco_rng.randi_range(1, 3) * TILE_SIZE * (1 if deco_rng.randf() < 0.5 else -1))
				var line_color := Color(grid_color.r * 1.8, grid_color.g * 1.4, grid_color.b * 1.8, 0.3)
				draw_line(start, mid, line_color, 2.0)
				draw_line(mid, end, line_color, 2.0)
				draw_circle(end, 4.0, line_color)


func _draw_terrain_zones() -> void:
	if terrain_zones.is_empty():
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	for zone in terrain_zones:
		var pos: Vector2 = zone["pos"]
		var radius: float = zone["radius"]
		var zone_rng := RandomNumberGenerator.new()
		zone_rng.seed = int(zone["seed"])
		match str(zone["type"]):
			"mud":
				# 泥沼：深綠棕大圓＋深色斑塊＋邊框
				draw_circle(pos, radius, Color(0.14, 0.13, 0.05, 0.88))
				for _i in range(6):
					var off := Vector2(zone_rng.randf_range(-0.6, 0.6), zone_rng.randf_range(-0.6, 0.6)) * radius
					draw_circle(pos + off, zone_rng.randf_range(radius * 0.15, radius * 0.3), Color(0.09, 0.085, 0.03, 0.9))
				draw_arc(pos, radius, 0.0, TAU, 40, Color(0.3, 0.28, 0.1, 0.55), 3.0)
			"fire":
				# 火焰：暗紅底＋脈動橘色內圈＋閃爍餘燼
				draw_circle(pos, radius, Color(0.28, 0.07, 0.02, 0.85))
				var pulse := 0.55 + 0.2 * sin(t * 3.2 + float(zone["seed"] % 7))
				draw_circle(pos, radius * 0.72, Color(0.9, 0.32, 0.05, 0.30 * pulse + 0.18))
				draw_circle(pos, radius * 0.4, Color(1.0, 0.62, 0.12, 0.28 * pulse + 0.14))
				for i in range(7):
					var ang := zone_rng.randf_range(0.0, TAU)
					var dist := zone_rng.randf_range(0.2, 0.85) * radius
					var flicker := 0.5 + 0.5 * sin(t * 5.0 + float(i) * 1.7 + float(zone["seed"] % 11))
					draw_circle(pos + Vector2.RIGHT.rotated(ang) * dist, 4.5, Color(1.0, 0.75, 0.2, 0.5 * flicker + 0.1))
				draw_arc(pos, radius, 0.0, TAU, 40, Color(1.0, 0.45, 0.1, 0.7), 3.0)
			"ice":
				# 冰面：半透明淺藍＋白色光澤裂紋
				draw_circle(pos, radius, Color(0.5, 0.75, 1.0, 0.20))
				draw_circle(pos, radius * 0.85, Color(0.7, 0.88, 1.0, 0.10))
				for _i in range(5):
					var a1 := zone_rng.randf_range(0.0, TAU)
					var p1 := pos + Vector2.RIGHT.rotated(a1) * zone_rng.randf_range(0.1, 0.5) * radius
					var p2 := p1 + Vector2.RIGHT.rotated(a1 + zone_rng.randf_range(-0.7, 0.7)) * zone_rng.randf_range(0.3, 0.6) * radius
					draw_line(p1, p2, Color(0.9, 0.97, 1.0, 0.4), 1.5)
				draw_arc(pos, radius, 0.0, TAU, 40, Color(0.65, 0.9, 1.0, 0.6), 3.0)


func _process_terrain_effects(delta: float) -> void:
	# ── 玩家：每幀更新（速度手感要即時）──
	if player != null and is_instance_valid(player):
		var has_mud := false
		var has_ice := false
		var in_fire := false
		for zone in terrain_zones:
			if player.global_position.distance_to(zone["pos"]) <= float(zone["radius"]):
				match str(zone["type"]):
					"mud": has_mud = true
					"ice": has_ice = true
					"fire": in_fire = true
		# 泥沼優先於冰面（同時踩到時取減速）
		player.terrain_speed_multiplier = TERRAIN_MUD_SLOW if has_mud else (TERRAIN_ICE_SPEED if has_ice else 1.0)
		_player_fire_tick = maxf(_player_fire_tick - delta, 0.0)
		if in_fire and _player_fire_tick <= 0.0 and player.health > 0:
			player.take_damage(1)
			_player_fire_tick = TERRAIN_FIRE_PLAYER_TICK
	# ── 敵人：每 0.25 秒批次檢查（效能節流）──
	if terrain_zones.is_empty():
		return
	_terrain_tick_timer += delta
	if _terrain_tick_timer < TERRAIN_TICK_INTERVAL:
		return
	_terrain_tick_timer = 0.0
	var fire_tick_damage := TERRAIN_FIRE_ENEMY_DPS * TERRAIN_TICK_INTERVAL
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var has_ice_e := false
		for zone in terrain_zones:
			if enemy.global_position.distance_to(zone["pos"]) <= float(zone["radius"]):
				match str(zone["type"]):
					"mud":
						enemy.apply_slow(TERRAIN_MUD_SLOW, TERRAIN_TICK_INTERVAL + 0.1)
					"ice":
						has_ice_e = true
					"fire":
						var dealt: float = enemy.take_damage(fire_tick_damage)
						if dealt > 0.0 and is_instance_valid(enemy):
							_show_damage_number(enemy.global_position, dealt, false)
		if is_instance_valid(enemy):
			enemy.terrain_speed_multiplier = TERRAIN_ICE_SPEED if has_ice_e else 1.0


func _process_camera_shake(delta: float) -> void:
	if _game_camera == null or not is_instance_valid(_game_camera):
		return
	if _camera_shake_strength > 0.0:
		_camera_shake_strength = maxf(_camera_shake_strength - delta * 28.0, 0.0)
		_game_camera.offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * _camera_shake_strength
	else:
		_game_camera.offset = Vector2.ZERO


func _show_controls_hint() -> void:
	# 開局操作提示：顯示在畫面中心與下方技能欄之間，8 秒後淡出
	if ui_canvas == null:
		return
	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.scroll_active = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.process_mode = Node.PROCESS_MODE_PAUSABLE
	hint.text = "[center]攻擊按 [color=#ffd84a]滑鼠左鍵[/color]　衝刺按 [color=#ffd84a]空白鍵[/color][/center]"
	if _game_font != null:
		hint.add_theme_font_override("normal_font", _game_font)
	hint.add_theme_font_size_override("normal_font_size", 26)
	hint.add_theme_color_override("default_color", Color(0.95, 0.95, 0.95))
	hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hint.add_theme_constant_override("outline_size", 7)
	# 錨定在畫面下方技能欄與中心之間
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -235.0
	hint.offset_bottom = -165.0
	ui_canvas.add_child(hint)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(8.0)
	tween.tween_property(hint, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func() -> void:
		if is_instance_valid(hint):
			hint.queue_free()
	)


func _show_zone_banner(stage_number: int) -> void:
	# 進入新視覺主題區域時顯示橫幅（每 5 關一次），並說明該區域的地形效果
	if ui_canvas == null:
		return
	if _zone_banner_label != null and is_instance_valid(_zone_banner_label):
		_zone_banner_label.queue_free()
		_zone_banner_label = null
	var theme: Dictionary = _get_stage_theme(stage_number)
	var lines: Array[String] = ["—— %s ——" % str(theme.get("name", ""))]
	var zone_plan: Dictionary = theme.get("zones", {})
	var hints := {
		"mud": "泥沼地帶：踩入會大幅減速（敵我皆同）",
		"fire": "火焰地帶：站在上面會持續受傷（敵我皆同）",
		"ice": "冰面地帶：移動速度加快（敵我皆同）"
	}
	for ztype in ["mud", "fire", "ice"]:
		if zone_plan.has(ztype) and int(zone_plan[ztype][1]) > 0:
			lines.append(str(hints[ztype]))
	var label := Label.new()
	label.text = "\n".join(lines)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = 130.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	label.z_index = 50
	if _game_font != null:
		label.add_theme_font_override("font", _game_font)
	label.add_theme_font_size_override("font_size", 34)
	var border_color: Color = theme.get("border", Color(0.9, 0.65, 0.15))
	label.add_theme_color_override("font_color", border_color.lightened(0.35))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	ui_canvas.add_child(label)
	_zone_banner_label = label
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "modulate:a", 1.0, 0.45)
	tween.tween_interval(2.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)


func _add_spawn_warning(pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite.z_index = 12
	sprite.add_to_group("stage_spawn_warnings")
	if ResourceLoader.exists(SPAWN_WARNING_TEXTURE_PATH):
		sprite.texture = load(SPAWN_WARNING_TEXTURE_PATH) as Texture2D
	sprite.scale = Vector2(0.48, 0.48)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.86)
	add_child(sprite)
	sprite.global_position = pos
	_stage_spawn_warning_nodes.append(sprite)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_loops()
	tween.tween_property(sprite, "scale", Vector2(0.62, 0.62), 0.38)
	tween.tween_property(sprite, "scale", Vector2(0.48, 0.48), 0.38)


func _clear_stage_spawn_warnings() -> void:
	for warning in _stage_spawn_warning_nodes:
		if is_instance_valid(warning):
			warning.queue_free()
	_stage_spawn_warning_nodes.clear()
	for warning in get_tree().get_nodes_in_group("stage_spawn_warnings"):
		if is_instance_valid(warning):
			warning.queue_free()


func _start_stage_with_preview(stage_number: int) -> void:
	# 確保前一個選單（LV UP / 暫停）留下的暫停狀態被解除
	get_tree().paused = false
	_clear_world_objects(true, true)
	# 每關重新生成功能地形（位置/數量隨機，種類依主題）
	_generate_stage_terrain(stage_number)
	# 每 5 關進入新視覺主題區域時顯示橫幅說明
	if (stage_number - 1) % 5 == 0:
		_show_zone_banner(stage_number)
	# 每關開始重置所有技能冷卻
	skill_cooldowns.clear()
	meltdown_cooldown = 0.0
	# 預先計算怪物種類+位置清單
	var spawn_list := []  # Array of {"id": ..., "pos": ..., "power": ...}
	_stage_preview_positions.clear()
	var stage_def: Dictionary = stage_defs[stage_number - 1]
	var power := float(stage_def.get("power", 1.0))
	for key in stage_def.keys():
		if key == "power":
			continue
		for _i in range(int(stage_def[key])):
			# 中型Boss（boss_mid）需求：生成時出現在玩家「當前腳下」，並在原地顯示生成預警，
			# 讓玩家有 3 秒反應時間離開，而不是跟其他小怪一樣隨機出現在場邊。
			var pos := player.global_position if str(key) == "boss_mid" and player != null and is_instance_valid(player) else _random_spawn_position()
			spawn_list.append({"id": str(key), "pos": pos, "power": power})
			_stage_preview_positions.append(pos)
			_add_spawn_warning(pos)
	_stage_previewing = true
	_stage_preview_timer = 3.0          # 倒計時，_process 每幀遞減
	queue_redraw()
	# 3秒後正式生成怪物（不暫停遊戲，玩家可正常行動）
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func() -> void:
		if not game_started or is_game_ended or current_stage != stage_number:
			_clear_stage_spawn_warnings()
			return
		_stage_previewing = false
		_stage_preview_positions.clear()
		_clear_stage_spawn_warnings()
		_stage_preview_timer = 0.0
		queue_redraw()
		stage_enemies_alive = 0
		_play_sfx_limited("stage_start", 1.0, 1.2, 0.25)
		# 怪物生成改為排入佇列，由 _process()/_process_pending_stage_spawns() 分批生成，
		# 避免整關怪物一次性在同一影格 instantiate 造成的卡頓（詳見上方常數註解）。
		_pending_stage_spawns = spawn_list.duplicate()
		_stage_spawn_active = not _pending_stage_spawns.is_empty()
		# 若有樸克牌技能，立即觸發抽牌
		if _has_poker_skill():
			poker_timer = 0.0
		_update_ui()
	)


func _spawn_stage(stage_number: int) -> void:
	stage_enemies_alive = 0
	var stage: Dictionary = stage_defs[stage_number - 1]
	var power := float(stage.get("power", 1.0))
	for key in stage.keys():
		if key == "power":
			continue
		for _i in range(int(stage[key])):
			var pos := player.global_position if str(key) == "boss_mid" and player != null and is_instance_valid(player) else _random_spawn_position()
			_spawn_wave_enemy(str(key), pos, power)
	_update_ui()


func _spawn_wave_enemy(enemy_id: String, pos: Vector2, power := 1.0) -> void:
	var enemy := EnemyScene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	var def: Dictionary = enemy_defs[enemy_id].duplicate(true)
	var diff_mult := _difficulty_enemy_multiplier()
	for key in ["hp", "speed", "range", "aps"]:
		if def.has(key):
			def[key] = float(def[key]) * diff_mult
	enemy.setup(def, player, power)
	enemy.global_position = pos
	enemy.died.connect(_on_enemy_died)
	enemy.attack_projectile_requested.connect(_spawn_enemy_bullet)
	enemy.dot_damage_occurred.connect(func(dot_pos: Vector2, amount: float) -> void:
		_show_damage_number(dot_pos, amount, false)
		# DOT（燃燒／毒素）每次造成傷害都算「玩家的傷害來源」，小丑牌啟用時一併觸發/刷新易傷詛咒
		_apply_joker_curse_if_active(enemy)
	)
	stage_enemies_alive += 1


func _random_spawn_position() -> Vector2:
	var margin := 80.0
	return Vector2(
		rng.randf_range(map_rect.position.x + margin, map_rect.end.x - margin),
		rng.randf_range(map_rect.position.y + margin, map_rect.end.y - margin)
	)


func _on_enemy_died(_enemy: Node2D) -> void:
	_play_sfx_limited("enemy_die", 0.85 + rng.randf_range(0.0, 0.3), 0.45, 0.12)
	stage_enemies_alive = max(stage_enemies_alive - 1, 0)
	kill_count += 1
	var enemy_id := ""
	if _enemy != null:
		enemy_id = str(_enemy.get("enemy_id"))
	match enemy_id:
		"boss_mid":
			_add_total_chips(1, "中型Boss擊破：+%d 晶片")
		"boss_final":
			_add_total_chips(3, "最終Boss擊破：+%d 晶片")
		_:
			# 普通敵人：僅在每 10 殺時輕量存檔
			if kill_count % 10 == 0:
				_save_current_slot()
	_update_ui()


func _add_total_chips(amount: int, message_template := "+%d 晶片") -> void:
	amount = max(0, amount)
	if amount <= 0:
		return
	total_chips += amount
	_save_current_slot()
	_flash_message(message_template % amount)


func _finish_stage() -> void:
	if is_game_ended:
		return
	_play_sfx("stage_clear")
	_save_current_slot()   # 每關結束自動存檔
	if current_stage >= 30:
		_end_game(true)
		return
	get_tree().paused = true
	player.level = min(MAX_LEVEL, current_stage + 1)
	_show_level_up_choices()


func _show_level_up_choices() -> void:
	_play_sfx("level_up")
	_hide_all_overlays()
	level_up_overlay.visible = true
	var available := _available_skill_ids()
	if available.is_empty():
		_go_next_stage()
		return
	available.shuffle()
	var picks := available.slice(0, min(3, available.size()))
	var items := []
	for skill_id in picks:
		var current: int = player.get_skill_level(skill_id)
		var next: int = current + 1
		var detail := _skill_detail_text(skill_id, current, next)
		var summary := _skill_choice_summary(skill_id, current, next)
		items.append([summary, Callable(self, "_choose_level_skill").bind(skill_id), detail])
	_make_menu(level_up_overlay, "LV UP！選擇 1 個技能", items)


func _choose_level_skill(skill_id: String) -> void:
	player.grant_skill(skill_id)
	_go_next_stage()


# ── 升級選項文字 ─────────────────────────────────────────────
func _skill_choice_summary(skill_id: String, current: int, next: int) -> String:
	var def: Dictionary = skill_defs.get(skill_id, {})
	var name_str: String = str(def.get("name", skill_id))
	if current <= 0:
		return "%s  （新習得 LV1）" % name_str
	return "%s  LV%d → LV%d" % [name_str, current, next]


func _skill_detail_text(skill_id: String, _current: int, _next: int) -> String:
	var def: Dictionary = skill_defs.get(skill_id, {})
	var current_level: int = clampi(_current, 0, 6)
	var next_level: int = clampi(_next, 1, 6)
	var value_level: int = max(1, current_level)
	var lines: Array[String] = []
	lines.append("[b]%s｜%s[/b]" % [str(def.get("school", "")), str(def.get("name", skill_id))])
	lines.append("效果：%s" % str(def.get("desc", "")))
	#if str(skill_id).begins_with("dice_"):
	#	lines.append(_color_numbers("骰子系共通被動：持有任一骰子技能即固定 +30% 爆擊率，多個骰子技能不疊加累加。"))
	if current_level <= 0:
		lines.append("習得後：%s，%s" % [_yellow("LV1"), _color_numbers(_skill_value_text(skill_id, 1))])
	elif _next > 0 and _next <= 6:
		lines.append("目前：%s" % _yellow("LV%d" % current_level))
		lines.append("目前數值：%s" % _color_numbers(_skill_value_text(skill_id, value_level)))
		lines.append("升級後：%s，%s" % [_yellow("LV%d" % next_level), _color_numbers(_skill_value_text(skill_id, next_level))])
	if str(skill_id).begins_with("fish_"):
		lines.append("操作：%s" % _color_numbers("按砲台熱鍵或點擊技能格施放，冷卻 15 秒。"))
	return "\n".join(lines)


func _yellow(text: String) -> String:
	return "[color=#ffd84a]%s[/color]" % text


func _skill_value_text(skill_id: String, level: int) -> String:
	level = clampi(level, 1, 6)
	match skill_id:
		"dice_crit":
			return "爆擊倍率 ×%.1f（基礎×2.0，每級爆傷 +%.0f%%）。" % [2.0 + _skill_level_value(skill_id, "crit_bonus_pct", [0, 20, 40, 60, 80, 100, 120], level) / 100.0, _skill_level_value(skill_id, "crit_bonus_pct", [0, 20, 40, 60, 80, 100, 120], level)]
		"dice_execute":
			return "2倍爆擊後蓄勢，下一次攻擊必定 3 倍爆擊；冷卻 %.0f 秒。" % _skill_level_value(skill_id, "cooldown_s", [0, 6, 5, 4, 3, 2, 1], level)
		"dice_first":
			return "攻擊血量 50%% 以上敵人時爆擊率 +%.0f%%（對精英/Boss 減半）。" % _skill_level_value(skill_id, "bonus_pct", [0, 20, 35, 50, 65, 80, 95], level)
		"dice_blast":
			return "爆擊時有 %.0f%% 機率在原地放置 6 格地雷圈，2 秒後引爆造成 %.0f%% 本次傷害。" % [_skill_level_value(skill_id, "trigger_chance_pct", [0, 10, 20, 30, 40, 50, 60], level), _skill_level_value(skill_id, "mine_damage_pct", [0, 70, 130, 190, 250, 310, 370], level)]
		"dice_last":
			return "每少 1 顆愛心，爆擊率 +%.0f%%。" % _skill_level_value(skill_id, "per_heart_pct", [0, 20, 25, 30, 35, 40, 45], level)
		"dice_hot":
			return "爆擊後 3 秒內傷害 +%.0f%%。" % _skill_level_value(skill_id, "bonus_pct", [0, 10, 20, 30, 40, 50, 60], level)
		"tech_frost":
			return "對命中目標 3 格內所有敵人造成 %.0f%% 本次傷害並緩速 70%% 持續 2 秒，各有 10%% 機率近乎冰凍。" % _skill_level_value(skill_id, "damage_pct", [0, 20, 35, 50, 65, 80, 100], level)
		"tech_fire":
			return "燃燒 4 秒，每秒 %.0f%% 本次傷害。" % _skill_level_value(skill_id, "dot_pct", [0, 20, 30, 40, 50, 60, 70], level)
		"tech_poison":
			return "中毒 4 秒，最多疊 3 層；每秒傷害＝%.0f%% 本次傷害 × 目前層數（3 層＝3 倍）。" % _skill_level_value(skill_id, "dot_pct", [0, 10, 15, 20, 25, 30, 35], level)
		"tech_lightning":
			return "命中時電擊，於 %.1f 格內最多跳 %d 次，每跳造成 %.0f%% 本次傷害。" % [
				_skill_level_value(skill_id, "jump_range_tiles", [0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0], level),
				int(_skill_level_value(skill_id, "jump_count", [0, 2, 2, 3, 3, 4, 4], level)),
				_skill_level_value(skill_id, "damage_pct", [0, 15, 25, 35, 45, 55, 65], level)]
		"tech_meltdown":
			return "冷卻 2 秒，命中位置 0.5 秒後引爆，5.5 格範圍造成 %.0f%% 本次傷害。" % _skill_level_value(skill_id, "damage_pct", [0, 10, 20, 30, 40, 50, 60], level)
		"tech_magnet":
			return "冷卻 5 秒，吸引範圍 %.1f 格，造成 %.0f%% 本次傷害；Boss 不受吸引。" % [_skill_level_value(skill_id, "range_tiles", [0, 4, 4.5, 5, 5.5, 6, 7], level), _skill_level_value(skill_id, "damage_pct", [0, 20, 30, 40, 50, 60, 70], level)]
		"poker_heart":
			return "抽中紅心時，閃避率 +%.0f%%，持續到下次抽牌。" % _skill_level_value(skill_id, "bonus_pct", [0, 10, 20, 30, 40, 50, 60], level)
		"poker_spade":
			return "抽中黑桃時，傷害 +%.0f%%。" % (_poker_spade_bonus(level) * 100.0)
		"poker_diamond":
			return "抽中方塊時，爆擊傷害 +%.0f%%。" % (_poker_diamond_bonus(level) * 100.0)
		"poker_club":
			return "抽中梅花時，攻速 +%.0f%%，持續到下次抽牌。" % _skill_level_value(skill_id, "bonus_pct", [0, 100, 150, 200, 250, 300, 350], level)
		"poker_joker":
			return "抽中 Joker 後，命中敵人施加 6 秒詛咒，敵人受傷 +%.0f%%。" % (_poker_joker_bonus(level) * 100.0)
		"poker_guard":
			return "抽中守護時召喚 %.0f 名護衛，護衛傷害 %.0f%% 玩家傷害。" % [_skill_level_value(skill_id, "count", [0, 1, 2, 3, 3, 3, 3], level), _skill_level_value(skill_id, "damage_multiplier", [0, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], level) * 100.0]
		"mahjong_sanyuan":
			return "每 5 秒砸下 8 張麻將牌轟炸隨機敵人，每張 %.0f%% 玩家傷害；只剩 1 隻敵人時 8 張全打他、第 2 張起逐張減半。" % _skill_level_value(skill_id, "damage_pct", [0, 50, 60, 70, 85, 100, 120], level)
		"mahjong_sixi":
			return "4 張麻將牌環繞，碰撞造成 %.0f%% 玩家傷害。" % _skill_level_value(skill_id, "damage_pct", [0, 50, 65, 80, 100, 125, 150], level)
		"mahjong_pong":
			return "命中後額外彈到附近 %d 名敵人。" % int(_skill_level_value(skill_id, "target_count", [0, 1, 2, 3, 4, 5, 6], level))
		"mahjong_moon":
			return "同時丟出 %d 顆麻將牌，飛出 7 格，搜尋 11 格，路徑傷害 %.0f%% 玩家傷害，回收速度 %.0f%%。" % [int(_skill_level_value(skill_id, "tile_count", [0, 1, 2, 3, 4, 5, 6], level)), _skill_level_value(skill_id, "damage_pct", [0, 80, 100, 130, 150, 180, 220], level), _skill_level_value(skill_id, "return_speed_multiplier", [0, 5, 5, 5, 5, 5, 5], level) * 100.0]
		"mahjong_wall":
			return "每 %.1f 秒抵擋一次傷害。" % float([0, 6.0, 5.0, 4.0, 3.0, 2.5, 2.0][level])
		"mahjong_flush":
			return "每 5 秒對周圍 6 格造成 %.0f%% 玩家傷害。" % _skill_level_value(skill_id, "damage_pct", [0, 100, 130, 160, 200, 250, 300], level)
	if str(skill_id).begins_with("fish_"):
		return "砲台每次命中造成 %.0f%% 玩家傷害，冷卻 8 秒。" % (_fish_percent(skill_id, level) * 100.0)
	return "依技能設定套用。"


# 將描述文字中的數字（含 % × 倍 格 秒）用黃色 BBCode 包起來
func _color_numbers(text: String) -> String:
	var result := ""
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		# 判斷是否為數字起頭（包含 × 前綴和負號）
		var is_digit := (c >= "0" and c <= "9")
		var is_prefix := (c == "×" or c == "+" or c == "-") and i + 1 < n and text[i + 1] >= "0" and text[i + 1] <= "9"
		if is_digit or is_prefix:
			var num := ""
			if is_prefix:
				num += c
				i += 1
			while i < n and ((text[i] >= "0" and text[i] <= "9") or text[i] == "."):
				num += text[i]
				i += 1
			# 附加單位（%、格、秒、倍、次、個、x、X）
			var unit := ""
			if i < n and text[i] in ["%", "格", "秒", "倍", "次", "個", "x", "X"]:
				unit = text[i]
				i += 1
			result += "[color=yellow]" + num + unit + "[/color]"
		else:
			result += c
			i += 1
	return result


# 建立技能 BBCode tooltip（供 skill bar hover 使用）
func _skill_tooltip_bbcode(skill_id: String, level: int) -> String:
	return _skill_detail_text(skill_id, level, min(level + 1, 6))


func _fish_percent(skill_id: String, level: int) -> float:
	# 注意：各魚機砲台實際傷害在 _fire_turret() 內讀取的 JSON key 並不統一
	# （fish_chain 用 damage_multiplier，其餘都用 dmg_pct），這裡務必對齊同一把 key，
	# 否則後台調整數值時，這裡顯示的說明文字會跟真正套用的傷害對不起來。
	match skill_id:
		"fish_rapid":
			return _skill_level_value(skill_id, "dmg_pct", [0, 100, 120, 150, 170, 185, 200], level) / 100.0
		"fish_fire":
			return _skill_level_value(skill_id, "dmg_pct", [0, 60, 60, 60, 60, 60, 60], level) / 100.0
		"fish_saw":
			return _skill_level_value(skill_id, "dmg_pct", [0, 10, 20, 30, 40, 50, 60], level) / 100.0
		"fish_missile":
			return _skill_level_value(skill_id, "dmg_pct", [0, 100, 100, 130, 130, 160, 160], level) / 100.0
		"fish_laser":
			return _skill_level_value(skill_id, "dmg_pct", [0, 100, 150, 200, 300, 400, 500], level) / 100.0
		"fish_chain":
			return _skill_level_value(skill_id, "damage_multiplier", [0, 0.7, 0.7, 0.8, 0.9, 1.0, 1.2], level)
	return 0.0


# ── 玩家死亡 ─────────────────────────────────────────────────
func _on_player_died() -> void:
	if is_game_ended:
		return
	_play_sfx("player_die")
	_end_game(false)


# ── 遊戲結束（死亡 / 通關）──────────────────────────────────
func _end_game(won: bool) -> void:
	if is_game_ended:
		return
	is_game_ended = true
	_save_current_slot()
	# 全部暫停
	get_tree().paused = true
	# 清除所有砲台
	for turret in turrets:
		var n: Node2D = turret.get("node")
		if is_instance_valid(n):
			n.queue_free()
	turrets.clear()

	_hide_all_overlays()
	game_over_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_overlay.visible = true
	for child in game_over_overlay.get_children():
		child.queue_free()

	# 半透明深色背景
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_overlay.add_child(bg)

	# 置中面板
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.add_child(center)

	var panel := PanelContainer.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.06, 0.10, 0.16, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(1.0, 0.75, 0.2, 0.9) if won else Color(0.85, 0.2, 0.2, 0.9)
	sbox.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", sbox)
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left","margin_right","margin_top","margin_bottom"]:
		margin.add_theme_constant_override(side, 32)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	# 標題
	var title_lbl := Label.new()
	title_lbl.text = "🏆  成功通關！" if won else "💀  爆倉了！"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_game_font(title_lbl, 36, Color(1.0, 0.9, 0.3) if won else Color(1.0, 0.4, 0.4), 3)
	box.add_child(title_lbl)

	# 統計資訊
	var survived_stages: int = current_stage
	var stats_text: String = "已過關卡：%d　　擊殺：%d　　累積晶片：%d" % [survived_stages, kill_count, total_chips]
	var stats_lbl := Label.new()
	stats_lbl.text = stats_text
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_game_font(stats_lbl, 20, Color(0.85, 0.85, 0.85), 2)
	box.add_child(stats_lbl)

	# 間距
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 8)
	box.add_child(sep)

	# 返回大廳按鈕（只能用滑鼠點擊）
	var btn := Button.new()
	btn.text = "返回大廳"
	btn.custom_minimum_size = Vector2(360, 52)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.focus_mode = Control.FOCUS_NONE   # 禁止鍵盤 focus
	_apply_game_font(btn, 24, Color.WHITE, 2)
	_style_menu_button(btn)
	btn.pressed.connect(func() -> void:
		get_tree().paused = false
		_play_sfx("ui_select")
		_return_to_lobby()
	)
	box.add_child(btn)


func _available_skill_ids() -> Array:
	var ids := []
	for skill_id in skill_defs.keys():
		if player.get_skill_level(skill_id) >= 6:
			continue
		if not player.has_skill_capacity_for(skill_id):
			continue
		ids.append(skill_id)
	return ids


func _go_next_stage() -> void:
	current_stage += 1
	_hide_all_overlays()
	_play_stage_transition(func() -> void:
		_setup_stage_map()
		_start_stage_with_preview(current_stage)
	)


func _play_stage_transition(done: Callable) -> void:
	message_label.text = "傳送到下一關..."
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(message_label, "modulate:a", 1.0, 0.1)
	tween.tween_interval(0.55)
	tween.tween_callback(func() -> void:
		message_label.text = ""
		if done.is_valid():
			done.call()
	)


func _on_player_attack_requested(
	origin: Vector2,
	target_position: Vector2,
	attack_data: Dictionary
) -> void:
	# （2026-07-07）大三元已改版為「八仙過海」：改由 _process_baxian() 每 5 秒自動轟炸，
	# 不再依攻擊次數觸發（sanyuan_hit_counter/sanyuan_pending 保留變數以相容舊存檔流程）

	var mode := str(attack_data.get("mode", "single"))

	if mode == "area":
		_spawn_circle_effect(
			target_position,
			float(attack_data["area_radius"]),
			Color(1, 1, 1, 0.5),
			0.3,
			func() -> void:
				for enemy in get_tree().get_nodes_in_group("enemies"):
					if (
						is_instance_valid(enemy)
						and target_position.distance_to(enemy.global_position)
						<= float(attack_data["area_radius"])
					):
						_apply_player_hit(enemy, attack_data)
		)

	elif mode == "cone":
		_attack_cone(origin, target_position, attack_data)

	else:
		var target := _find_attack_target(
			origin,
			target_position,
			float(attack_data["range"])
		)

		if target != null:
			_apply_player_hit(target, attack_data)
			_draw_attack_line(origin, target.global_position, Color(0.65, 0.9, 1.0, 0.8))
			# 多重攻擊：再擊中第2個敵人
			if _multi_attack_count >= 2:
				var second := _nearest_enemy(origin, float(attack_data["range"]), [target])
				if second != null:
					_apply_player_hit(second, attack_data)
					_draw_attack_line(origin, second.global_position, Color(1.0, 0.75, 0.3, 0.8))

func _attack_cone(
	origin: Vector2,
	target_position: Vector2,
	attack_data: Dictionary
) -> void:
	var attack_range := float(attack_data.get("range", 64.0))
	var cone_angle_degrees := float(attack_data.get("cone_angle", 90.0))
	var half_angle := deg_to_rad(cone_angle_degrees * 0.5)

	var attack_direction := origin.direction_to(target_position)

	if attack_direction.length_squared() <= 0.001:
		attack_direction = Vector2.RIGHT

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue

		var enemy_offset: Vector2 = enemy.global_position - origin
		var enemy_distance := enemy_offset.length()

		if enemy_distance > attack_range:
			continue

		if enemy_distance <= 0.001:
			_apply_player_hit(enemy, attack_data)
			continue

		var enemy_direction := enemy_offset.normalized()
		var ang_diff: float = absf(
	attack_direction.angle_to(enemy_direction)
		)

		if ang_diff <= half_angle:
			_apply_player_hit(enemy, attack_data)

	_draw_cone_effect(
		origin,
		attack_direction,
		attack_range,
		half_angle
	)
	
func _draw_cone_effect(
	origin: Vector2,
	direction: Vector2,
	attack_range: float,
	half_angle: float
) -> void:
	var line := Line2D.new()
	line.add_to_group("transient_effects")
	line.width = 4.0
	line.default_color = Color(1.0, 0.8, 0.3, 0.85)

	var point_count := 14
	var points := PackedVector2Array()
	points.append(origin)

	for index in range(point_count + 1):
		var ratio := float(index) / float(point_count)
		var angle: float = lerpf(-half_angle, half_angle, ratio)
		var point := origin + direction.rotated(angle) * attack_range
		points.append(point)

	points.append(origin)
	line.points = points
	add_child(line)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(line, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		if is_instance_valid(line):
			line.queue_free()
	)


func _find_attack_target(origin: Vector2, target_position: Vector2, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_score := 999999.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var distance_from_player := origin.distance_to(enemy.global_position)
		if distance_from_player > max_range:
			continue
		var score := target_position.distance_to(enemy.global_position)
		if score < best_score:
			best = enemy as Node2D
			best_score = score
	return best


func _apply_player_hit(enemy: Node2D, attack_data: Dictionary) -> void:
	if not is_instance_valid(enemy):
		return
	var skills: Dictionary = attack_data.get("skills", {})
	var damage := float(attack_data["damage"])
	if active_poker_buffs.has("spade"):
		damage *= 1.0 + _poker_spade_bonus(player.get_skill_level("poker_spade"))
	var crit_rate := float(attack_data.get("crit_chance", 0.0))
	# 骰子系技能共通被動：只要擁有任一骰子技能，爆擊率固定 +30%（多個骰子技能不疊加累加）
	var has_dice_skill := false
	for raw_key in skills.keys():
		if str(raw_key).begins_with("dice_"):
			has_dice_skill = true
			break
	if has_dice_skill:
		crit_rate += 0.30
	# 先手骰：攻擊半血以上加爆擊率，精英/BOSS效果減半
	if skills.has("dice_first"):
		var first_lv: int = int(skills["dice_first"])
		var first_bonus: float = _skill_level_value("dice_first", "bonus_pct", [0, 20, 35, 50, 65, 80, 95], first_lv) / 100.0
		var eid: String = str(enemy.enemy_id)
		if eid == "headhunter" or eid == "boss_mid" or eid == "boss_final":
			first_bonus *= 0.5
		if float(enemy.health) > float(enemy.max_health) * 0.5:
			crit_rate += first_bonus
	# 絕命骰：每少 1 顆愛心，爆擊率提升（LV1 每顆 +20%）
	if skills.has("dice_last") and player != null:
		var missing_hearts: int = maxi(int(player.max_health) - int(player.health), 0)
		if missing_hearts > 0:
			crit_rate += float(missing_hearts) * _skill_level_value("dice_last", "per_heart_pct", [0, 20, 25, 30, 35, 40, 45], int(skills["dice_last"])) / 100.0
	var is_crit := rng.randf() < crit_rate
	# 三倍骰：蓄勢中 → 本次攻擊必定爆擊，且爆擊倍率固定 3 倍
	var triple_dice_proc := false
	if skills.has("dice_execute") and _triple_dice_armed:
		_triple_dice_armed = false
		triple_dice_proc = true
		is_crit = true
	if is_crit:
		# 爆擊倍率：基礎 ×2.0，致命骰每級額外 +20% 爆擊傷害（LV1=×2.2…LV6=×3.2）
		var dice_crit_lv: int = int(skills.get("dice_crit", 0))
		var crit_mult: float = 2.0 + _skill_level_value("dice_crit", "crit_bonus_pct", [0, 20, 40, 60, 80, 100, 120], dice_crit_lv) / 100.0
		if active_poker_buffs.has("diamond"):
			crit_mult += _poker_diamond_bonus(player.get_skill_level("poker_diamond"))
		if triple_dice_proc:
			crit_mult = 3.0   # 三倍骰：固定 3 倍爆擊
		damage *= crit_mult
		# 三倍骰充能：一般爆擊後若冷卻完畢即蓄勢，並開始冷卻（顯示在技能欄）
		if not triple_dice_proc and skills.has("dice_execute") and float(skill_cooldowns.get("dice_execute", 0.0)) <= 0.0:
			_triple_dice_armed = true
			skill_cooldowns["dice_execute"] = _skill_level_value("dice_execute", "cooldown_s", [0, 6, 5, 4, 3, 2, 1], int(skills["dice_execute"]))
		# 爆裂骰：觸發條件與機率不變（爆擊時 10%×等級），但改為在目標位置放置一個
		# 固定 6 格範圍的地雷圈，2 秒後引爆，對圈內敵人造成 LV1=70%、每升1級+60% 的傷害。
		if skills.has("dice_blast"):
			var blast_lv: int = int(skills["dice_blast"])
			var blast_chance: float = _skill_level_value("dice_blast", "trigger_chance_pct", [0, 10, 20, 30, 40, 50, 60], blast_lv) / 100.0
			if rng.randf() < blast_chance:
				_trigger_dice_mine(enemy.global_position, damage, blast_lv, skills)
		if skills.has("dice_hot"):
			var hot_bonus: float = _skill_level_value("dice_hot", "bonus_pct", [0, 10, 20, 30, 40, 50, 60], int(skills["dice_hot"])) / 100.0
			var hot_fresh: bool = not active_poker_buffs.has("hot")
			active_poker_buffs["hot"] = {"timer": 3.0, "bonus": hot_bonus}
			# 傷害骰觸發特效：玩家腳下橘色能量圈（只在新觸發時播放，刷新不重播）
			if hot_fresh and player != null and is_instance_valid(player):
				_spawn_circle_effect(player.global_position, 1.3 * TILE_SIZE,
					Color(1.0, 0.5, 0.1, 0.35), 0.3, func() -> void: pass)
	if active_poker_buffs.has("hot"):
		damage *= 1.0 + float(active_poker_buffs["hot"]["bonus"])
	var dealt_damage: float = enemy.take_damage(damage)
	# 小丑詛咒：改為在敵人身上掛「易傷」debuff（enemy.gd 的 _curse_timer/_curse_multiplier），
	# 使該敵人接下來 6 秒內受到的「所有」傷害來源（砲台、DOT、大四喜/海底撈月/清一色、
	# 皇家護衛等）都會被放大，而不再只是乘進玩家這一下攻擊的傷害數字。
	# 放在 take_damage() 之後才刷新，避免這一下攻擊本身重複疊加剛掛上的新詛咒。
	_apply_joker_curse_if_active(enemy)
	_play_sfx_limited("hit", 0.9 + rng.randf_range(0.0, 0.2), 0.28, 0.08)
	# 擊退效果（戰士0.5格、槍手0.3格、法師0.15格；爆擊擊退 ×1.7）
	if is_instance_valid(player) and is_instance_valid(enemy) and enemy.has_method("apply_knockback"):
		var kb_tiles := 0.0
		match str(player.class_id):
			"warrior": kb_tiles = 0.5
			"archer": kb_tiles = 0.3
			"mage": kb_tiles = 0.15
		if is_crit:
			kb_tiles *= 1.7
		if kb_tiles > 0.0:
			var kb_dir := (enemy.global_position - player.global_position).normalized()
			if kb_dir.length_squared() <= 0.001:
				kb_dir = Vector2.RIGHT
			enemy.apply_knockback(kb_dir, kb_tiles * TILE_SIZE)
	# 爆擊擊倒：短暫倒地（enemy.gd 內建 3 秒冷卻與 Boss 免疫，避免無限控場）
	if is_crit and is_instance_valid(enemy) and enemy.has_method("apply_knockdown"):
		enemy.apply_knockdown(0.55)
	# 三倍骰觸發特效：紅色 X 斬擊
	if triple_dice_proc and is_instance_valid(enemy):
		_spawn_execute_effect(enemy.global_position)
	_show_damage_number(enemy.global_position, dealt_damage, is_crit)
	_apply_on_hit_skills(enemy, damage, skills)
	_apply_mahjong_skills(enemy, damage, skills)


func _apply_turret_hit(enemy: Node2D, damage: float) -> void:
	if player == null or not is_instance_valid(enemy):
		return
	_apply_on_hit_skills(enemy, damage, player.selected_skills, false, false)


func _apply_on_hit_skills(enemy: Node2D, base_damage: float, skills: Dictionary, apply_joker := true, allow_lightning := true) -> void:
	if apply_joker:
		_apply_joker_curse_if_active(enemy)
	if skills.has("tech_frost"):
		var level: int = int(skills["tech_frost"])
		# 傷害最低 1
		var frost_dmg := maxf(1.0, base_damage * (_skill_level_value("tech_frost", "damage_pct", [0, 20, 35, 50, 65, 80, 100], level) / 100.0))
		# 冰霜改為以命中目標為中心，對 3 格範圍內所有敵人造成同等傷害並附加緩速
		var frost_radius := 3.0 * TILE_SIZE
		var frost_center := enemy.global_position
		_spawn_frost_effect(frost_center, frost_radius)
		for frost_target in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(frost_target):
				continue
			if frost_center.distance_to(frost_target.global_position) > frost_radius:
				continue
			frost_target.apply_slow(0.70, 2.0)
			if rng.randf() < 0.10:
				frost_target.apply_slow(0.02, 2.0)
			frost_target.take_damage(frost_dmg)
			if apply_joker:
				_apply_joker_curse_if_active(frost_target)
	if skills.has("tech_fire"):
		var level: int = int(skills["tech_fire"])
		var fire_dot := maxf(1.0, base_damage * (_skill_level_value("tech_fire", "dot_pct", [0, 20, 30, 40, 50, 60, 70], level) / 100.0))
		enemy.apply_burn(fire_dot, 4.0)
		_spawn_ignite_effect(enemy.global_position)
	if skills.has("tech_poison"):
		var level: int = int(skills["tech_poison"])
		var poison_dot := maxf(1.0, base_damage * (_skill_level_value("tech_poison", "dot_pct", [0, 10, 15, 20, 25, 30, 35], level) / 100.0))
		enemy.apply_poison(poison_dot, 4.0)
	# 高壓電（tech_lightning）僅在玩家「本人主攻擊」命中時觸發，避免大四喜/海底撈月/清一色/
	# 碰碰胡/磁暴/熔毀等被動、持續性傷害來源在玩家沒有主動攻擊時也連帶觸發鏈式閃電，
	# 造成「沒攻擊卻一直閃電」的觀感。其餘科技技能（冰霜/燃燒/毒素/熔毀/磁暴）不受影響。
	if allow_lightning and skills.has("tech_lightning"):
		var _lt_level: int = int(skills["tech_lightning"])
		var _lt_dmg: float = maxf(1.0, base_damage * (_skill_level_value("tech_lightning", "damage_pct", [0, 15, 25, 35, 45, 55, 65], _lt_level) / 100.0))
		# 跳躍次數依等級：LV1~2=2，LV3~4=3，LV5~6=4
		var _lt_jumps: int = int(_skill_level_value("tech_lightning", "jump_count", [0, 2, 2, 3, 3, 4, 4], _lt_level))
		_trigger_lightning_chain(enemy, _lt_dmg, _lt_jumps, _lt_level, skills, apply_joker)
	if skills.has("tech_meltdown") and meltdown_cooldown <= 0.0:
		_trigger_meltdown(enemy.global_position, base_damage, int(skills["tech_meltdown"]), skills)
	if skills.has("tech_magnet") and magnet_cooldown <= 0.0:
		_trigger_magnet(enemy.global_position, base_damage, int(skills["tech_magnet"]))


func _trigger_meltdown(center: Vector2, base_damage: float, level: int, source_skills: Dictionary) -> void:
	level = clampi(level, 1, 6)
	var meltdown_cd := _skill_cooldown("tech_meltdown", 2.0)
	meltdown_cooldown = meltdown_cd
	skill_cooldowns["tech_meltdown"] = meltdown_cd
	var radius := 5.5 * TILE_SIZE
	var damage := maxf(1.0, base_damage * (_skill_level_value("tech_meltdown", "damage_pct", [0, 10, 20, 30, 40, 50, 60], level) / 100.0))
	var sprite := Sprite2D.new()
	sprite.add_to_group("transient_effects")
	sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite.z_index = 6
	if ResourceLoader.exists(MELTDOWN_RING_TEXTURE_PATH):
		sprite.texture = load(MELTDOWN_RING_TEXTURE_PATH) as Texture2D
	sprite.scale = Vector2.ONE * (radius * 2.0 / 512.0)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.9)
	add_child(sprite)
	sprite.global_position = center
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(0.5)
	tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.modulate = Color(1.0, 0.85, 0.45, 1.0)
		var area_skills := source_skills.duplicate(true)
		area_skills.erase("tech_meltdown")
		_damage_area(center, radius, damage, 9999, area_skills, false)
	)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _trigger_dice_mine(center: Vector2, base_damage: float, level: int, source_skills: Dictionary) -> void:
	# 爆裂骰新版效果：觸發後在目標位置放置固定 6 格範圍的地雷圈，2 秒後引爆，
	# 對當下仍在範圍內的敵人造成傷害（LV1=70%、每升1級+60%，以觸發當下這一下爆擊的傷害為基準）。
	level = clampi(level, 1, 6)
	var radius := 6.0 * TILE_SIZE
	var damage := maxf(1.0, base_damage * (_skill_level_value("dice_blast", "mine_damage_pct", [0, 70, 130, 190, 250, 310, 370], level) / 100.0))
	var sprite := Sprite2D.new()
	sprite.add_to_group("transient_effects")
	sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite.z_index = 6
	if ResourceLoader.exists(MELTDOWN_RING_TEXTURE_PATH):
		sprite.texture = load(MELTDOWN_RING_TEXTURE_PATH) as Texture2D
	sprite.scale = Vector2.ONE * (radius * 2.0 / 512.0)
	# 用偏紅橘色調與熔毀（tech_meltdown）的橘黃色區分，避免玩家混淆兩種延遲引爆技能
	sprite.modulate = Color(1.0, 0.3, 0.15, 0.9)
	add_child(sprite)
	sprite.global_position = center
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(2.0)
	tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.modulate = Color(1.0, 0.55, 0.2, 1.0)
		var area_skills := source_skills.duplicate(true)
		area_skills.erase("dice_blast")
		_damage_area(center, radius, damage, 9999, area_skills, false)
	)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _trigger_magnet(center: Vector2, base_damage: float, level: int) -> void:
	level = clamp(level, 1, 6)
	if is_instance_valid(active_magnet):
		active_magnet.queue_free()
	var radius: float = _skill_level_value("tech_magnet", "range_tiles", [0, 4, 4.5, 5, 5.5, 6, 7], level) * TILE_SIZE
	var damage: float = maxf(1.0, base_damage * (_skill_level_value("tech_magnet", "damage_pct", [0, 20, 30, 40, 50, 60, 70], level) / 100.0))
	active_magnet = Node2D.new()
	active_magnet.add_to_group("transient_effects")
	active_magnet.global_position = center
	add_child(active_magnet)
	_spawn_circle_effect(center, radius, Color(0.35, 0.9, 1.0, 0.24), 2.0, func() -> void: pass)
	var magnet_cd := _skill_cooldown("tech_magnet", 5.0)
	magnet_cooldown = magnet_cd
	skill_cooldowns["tech_magnet"] = magnet_cd
	var _magnet_skills: Dictionary = player.selected_skills if player != null else {}
	for other in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(other) or other.global_position.distance_to(center) > radius:
			continue
		# （2026-07-07 平衡調整）磁暴不再緩速，只吸引＋傷害；Boss 不受吸引僅受傷害
		if not str(other.enemy_id).begins_with("boss"):
			# 拉力速度 = 距離 / 0.35秒，讓敵人在 0.35 秒內被拉至中心附近
			var pull_dist: float = (other as Node2D).global_position.distance_to(center)
			var pull_spd: float = clamp(pull_dist / 0.35, 200.0, 1400.0)
			other.apply_pull(center, pull_spd, 0.35)
		other.take_damage(damage)
		_apply_joker_curse_if_active(other)
		if not _magnet_skills.is_empty():
			_apply_on_hit_skills(other, damage, _magnet_skills, false, false)
	var timer := get_tree().create_timer(2.0, false, false, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(active_magnet):
			active_magnet.queue_free()
	)


func _apply_mahjong_skills(enemy: Node2D, base_damage: float, skills: Dictionary) -> void:
	# 碰碰胡：打中附近N個「其他」敵人（不含原目標），N=等級
	if skills.has("mahjong_pong"):
		var level: int = int(skills["mahjong_pong"])
		var pong_count: int = int(_skill_level_value("mahjong_pong", "target_count", [0, 1, 2, 3, 4, 5, 6], level))
		var pong_radius := 3.0 * TILE_SIZE
		var nearby: Array = []
		for other in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(other) or other == enemy:
				continue
			if enemy.global_position.distance_to(other.global_position) <= pong_radius:
				nearby.append(other)
		nearby.sort_custom(func(a: Node2D, b: Node2D) -> bool:
			return enemy.global_position.distance_to(a.global_position) \
				 < enemy.global_position.distance_to(b.global_position)
		)
		for i in range(mini(pong_count, nearby.size())):
			var other: Node2D = nearby[i]
			other.take_damage(base_damage)
			_show_damage_number(other.global_position, base_damage, false)
			_spawn_pong_chain_effect(enemy.global_position, other.global_position)
			_apply_on_hit_skills(other, base_damage, skills, true, false)

	# （2026-07-07）大三元舊機制（第3擊爆炸）已移除，改版為「八仙過海」定時轟炸，見 _process_baxian()


func _process_baxian(delta: float) -> void:
	# 八仙過海（原大三元）：每 5 秒從天上砸下 8 張麻將牌轟炸隨機敵人。
	# 場上只剩 1 隻敵人時 8 張全打他，但第 2 張起傷害逐張減半（50%→25%→12.5%…）。
	if player == null or not is_instance_valid(player) or player.health <= 0:
		return
	if not game_started or is_game_ended:
		return
	var level: int = player.get_skill_level("mahjong_sanyuan")
	if level <= 0:
		return
	_baxian_timer -= delta
	if _baxian_timer > 0.0:
		return
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and float(e.health) > 0.0:
			enemies.append(e)
	if enemies.is_empty():
		_baxian_timer = 0.5   # 沒目標時不進入完整冷卻，0.5 秒後再檢查
		return
	_baxian_timer = 5.0
	skill_cooldowns["mahjong_sanyuan"] = 5.0   # 技能欄顯示冷卻
	var per_tile_pct: float = _skill_level_value("mahjong_sanyuan", "damage_pct", [0, 50, 60, 70, 85, 100, 120], level)
	var base_dmg: float = float(player.attack_damage) * (per_tile_pct / 100.0) * _hot_damage_mult()
	var single_target: bool = enemies.size() == 1
	var drop_delay := 0.0
	for i in range(8):
		var target_enemy: Node2D = enemies[0] if single_target else enemies[rng.randi_range(0, enemies.size() - 1)]
		var tile_dmg := base_dmg
		if single_target and i >= 1:
			tile_dmg = base_dmg * pow(0.5, float(i))
		_drop_baxian_tile(target_enemy, maxf(1.0, tile_dmg), drop_delay)
		# 時間差掉落（0.1~0.2 秒），營造實體牌暴雨感
		drop_delay += rng.randf_range(0.1, 0.2)


func _drop_baxian_tile(target_enemy: Node2D, damage: float, delay: float) -> void:
	var timer := get_tree().create_timer(delay, false, false, true)
	timer.timeout.connect(func() -> void:
		if not game_started or is_game_ended:
			return
		if not is_instance_valid(target_enemy):
			return
		var tile := Sprite2D.new()
		tile.add_to_group("transient_effects")
		tile.process_mode = Node.PROCESS_MODE_PAUSABLE
		tile.z_index = 20
		var tile_names := ["tile_east.png", "tile_south.png", "tile_west.png", "tile_north.png"]
		var tp: String = "res://AIgame_rougelike/assets/art/skills/mahjong/" + tile_names[rng.randi_range(0, 3)]
		if ResourceLoader.exists(tp):
			tile.texture = load(tp) as Texture2D
		add_child(tile)
		var land_pos: Vector2 = target_enemy.global_position
		tile.global_position = land_pos + Vector2(rng.randf_range(-24.0, 24.0), -420.0)
		tile.rotation = rng.randf_range(-0.6, 0.6)
		# 落點提示小圈
		_spawn_circle_effect(land_pos, 26.0, Color(0.3, 1.0, 0.5, 0.25), 0.3, func() -> void: pass)
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		tween.tween_property(tile, "global_position", land_pos, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func() -> void:
			if is_instance_valid(target_enemy) and float(target_enemy.health) > 0.0:
				var dealt: float = target_enemy.take_damage(damage)
				_show_damage_number(land_pos, dealt, false)
				if player != null and is_instance_valid(player):
					_apply_on_hit_skills(target_enemy, damage, player.selected_skills, true, false)
			_play_sfx_limited("mahjong_sixi", 1.1 + rng.randf_range(0.0, 0.2), 0.3, 0.08)
			_spawn_sixi_hit_effect(land_pos)
			if is_instance_valid(tile):
				var fade := create_tween()
				fade.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
				fade.tween_property(tile, "modulate:a", 0.0, 0.25)
				fade.tween_callback(func() -> void:
					if is_instance_valid(tile):
						tile.queue_free()
				)
		)
	)


func _spawn_sixi_hit_effect(pos: Vector2) -> void:
	# 麻將牌命中特效（大四喜旋轉牌／八仙過海落牌共用）：
	# 優先使用 AI 素材 tile_hit_fx.png，缺檔時退回程序繪製（綠色環＋放射線）
	var fx_path := "res://AIgame_rougelike/assets/art/skills/mahjong/tile_hit_fx.png"
	var fx_tex: Texture2D = null
	if _terrain_tex_cache.has("__tile_hit_fx"):
		fx_tex = _terrain_tex_cache["__tile_hit_fx"]
	else:
		if ResourceLoader.exists(fx_path):
			fx_tex = load(fx_path) as Texture2D
		elif FileAccess.file_exists(fx_path):
			var img := Image.load_from_file(fx_path)
			if img != null:
				fx_tex = ImageTexture.create_from_image(img)
		_terrain_tex_cache["__tile_hit_fx"] = fx_tex
	if fx_tex != null:
		var sprite := Sprite2D.new()
		sprite.add_to_group("transient_effects")
		sprite.z_index = 15
		sprite.texture = fx_tex
		add_child(sprite)
		sprite.global_position = pos
		var target_px := 64.0
		var base_scale: float = target_px / maxf(1.0, float(fx_tex.get_width()))
		sprite.scale = Vector2.ONE * base_scale * 0.5
		sprite.rotation = rng.randf_range(0.0, TAU)
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		tween.tween_property(sprite, "scale", Vector2.ONE * base_scale * 1.15, 0.16).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func() -> void:
			if is_instance_valid(sprite):
				sprite.queue_free()
		)
		return
	_spawn_circle_effect(pos, 28.0, Color(0.35, 1.0, 0.55, 0.4), 0.16, func() -> void: pass)
	for i in range(4):
		var line := Line2D.new()
		line.add_to_group("transient_effects")
		line.z_index = 15
		line.width = 3.0
		line.default_color = Color(0.7, 1.0, 0.8, 0.9)
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3))
		line.points = PackedVector2Array([dir * 8.0, dir * 22.0])
		add_child(line)
		line.global_position = pos
		var lt := create_tween()
		lt.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		lt.tween_property(line, "scale", Vector2.ONE * 1.6, 0.15)
		lt.parallel().tween_property(line, "modulate:a", 0.0, 0.17)
		lt.tween_callback(func() -> void:
			if is_instance_valid(line):
				line.queue_free()
		)


func _process_sixi(delta: float) -> void:
	if player == null or not game_started or is_game_ended or not is_instance_valid(player) or player.health <= 0:
		_clear_sixi_tiles()
		return
	var level: int = player.get_skill_level("mahjong_sixi")
	if level <= 0:
		_clear_sixi_tiles()
		return
	# 確保有4個軌道磁磚
	var tile_paths: Array = [
		"res://AIgame_rougelike/assets/art/skills/mahjong/tile_east.png",
		"res://AIgame_rougelike/assets/art/skills/mahjong/tile_south.png",
		"res://AIgame_rougelike/assets/art/skills/mahjong/tile_west.png",
		"res://AIgame_rougelike/assets/art/skills/mahjong/tile_north.png"
	]
	while sixi_tiles.size() < 4:
		var idx: int = sixi_tiles.size()
		var sprite := Sprite2D.new()
		# 注意：大四喜磁磚不可加入 "transient_effects" 群組，
		# 否則換關時 _clear_world_objects 的一般特效清除會連同召喚物一起被清掉。
		# 這裡改用專屬陣列 sixi_tiles 自行追蹤與清除（見 _clear_sixi_tiles）。
		sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
		if ResourceLoader.exists(tile_paths[idx]):
			sprite.texture = load(tile_paths[idx])
		add_child(sprite)
		sixi_tiles.append(sprite)
	var orbit_speed: float = float([0, 1.2, 1.4, 1.6, 1.9, 2.2, 2.6][level])
	sixi_orbit_angle = fmod(sixi_orbit_angle + orbit_speed * delta, TAU)
	var orbit_radius := 2.0 * TILE_SIZE
	var dmg: float = float(player.attack_damage) * (_skill_level_value("mahjong_sixi", "damage_pct", [0, 50, 65, 80, 100, 125, 150], level) / 100.0) * _hot_damage_mult()
	# 更新 hit CD
	var keys_to_remove: Array = []
	for key in sixi_hit_cds.keys():
		sixi_hit_cds[key] = float(sixi_hit_cds[key]) - delta
		if float(sixi_hit_cds[key]) <= 0.0:
			keys_to_remove.append(key)
	for key in keys_to_remove:
		sixi_hit_cds.erase(key)
	# 更新位置 + 碰撞
	for i in range(4):
		var tile = sixi_tiles[i]
		if not is_instance_valid(tile):
			continue
		var angle: float = sixi_orbit_angle + float(i) * (TAU / 4.0)
		tile.global_position = player.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
		tile.rotation = angle + PI * 0.5
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(enemy):
				continue
			var key: String = "%d_%d" % [i, int(enemy.get_instance_id())]
			if sixi_hit_cds.has(key):
				continue
			if tile.global_position.distance_to(enemy.global_position) <= 40.0:
				enemy.take_damage(dmg)
				_show_damage_number(enemy.global_position, dmg, false)
				_spawn_sixi_hit_effect(enemy.global_position)
				_play_sfx("mahjong_sixi", 0.95 + rng.randf_range(0.0, 0.15))
				if player != null:
					_apply_on_hit_skills(enemy, dmg, player.selected_skills, true, false)
				sixi_hit_cds[key] = 0.75


func _clear_sixi_tiles() -> void:
	for tile in sixi_tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	sixi_tiles.clear()
	sixi_hit_cds.clear()


func _process_moon(delta: float) -> void:
	if player == null or not game_started or is_game_ended or not is_instance_valid(player) or player.health <= 0:
		_clear_moon_tiles()
		return
	var level: int = player.get_skill_level("mahjong_moon")
	if level <= 0:
		_clear_moon_tiles()
		return
	moon_cooldown = maxf(moon_cooldown - delta, 0.0)
	# 同時存在的麻將牌數量依等級：LV1=1顆，每升1級+1顆（LV6=6顆）
	var moon_tile_cap: int = int(_skill_level_value("mahjong_moon", "tile_count", [0, 1, 2, 3, 4, 5, 6], level))
	# 使用者需求：整批麻將牌要「同時發動、同時收回」，呈現一次性齊發分散攻擊的手感，
	# 因此改為 idle→out→hover→return 的整批共用階段機制，而非每顆各自獨立飛行/計時。
	if moon_cooldown <= 0.0 and moon_volley_phase == "idle":
		var cd: float = float([0, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5][level])
		moon_cooldown = cd
		_launch_moon_volley(level, moon_tile_cap)
	if moon_volley_phase == "idle":
		return
	moon_volley_timer -= delta
	match moon_volley_phase:
		"out":
			var t: float = clampf(1.0 - moon_volley_timer / maxf(0.001, moon_volley_out_duration), 0.0, 1.0)
			for proj in moon_projectiles:
				var node = proj.get("node")
				if not is_instance_valid(node):
					continue
				var start_pos: Vector2 = proj.get("start_pos", Vector2.ZERO)
				var target_pos: Vector2 = proj.get("target", Vector2.ZERO)
				node.global_position = start_pos.lerp(target_pos, t)
				_moon_hit_check(proj, node.global_position, float(proj.get("dmg", 0.0)))
			if moon_volley_timer <= 0.0:
				for proj in moon_projectiles:
					var node2 = proj.get("node")
					if is_instance_valid(node2):
						node2.global_position = proj.get("target", Vector2.ZERO)
				moon_volley_phase = "hover"
				moon_volley_timer = moon_volley_hover_duration
		"hover":
			for proj in moon_projectiles:
				var node = proj.get("node")
				if is_instance_valid(node):
					_moon_hit_check(proj, node.global_position, float(proj.get("dmg", 0.0)))
			if moon_volley_timer <= 0.0:
				# 收回：整批麻將牌同時開始飛回，回程速度依等級加快，但共用同一個收回時長，
				# 讓所有牌一起出發、也一起抵達玩家身邊消失。
				var return_spd_mult: float = _skill_level_value("mahjong_moon", "return_speed_multiplier", [0, 5, 5, 5, 5, 5, 5], level)
				moon_volley_return_duration = maxf(0.15, (7.0 * TILE_SIZE) / (290.0 * maxf(1.0, return_spd_mult)))
				moon_volley_timer = moon_volley_return_duration
				for proj in moon_projectiles:
					var node3 = proj.get("node")
					proj["return_start"] = node3.global_position if is_instance_valid(node3) else proj.get("target", Vector2.ZERO)
					proj["hit_record"] = []
				moon_volley_phase = "return"
		"return":
			if not is_instance_valid(player):
				_clear_moon_tiles()
				return
			var rt: float = clampf(1.0 - moon_volley_timer / maxf(0.001, moon_volley_return_duration), 0.0, 1.0)
			for proj in moon_projectiles:
				var node = proj.get("node")
				if not is_instance_valid(node):
					continue
				var return_start: Vector2 = proj.get("return_start", player.global_position)
				node.global_position = return_start.lerp(player.global_position, rt)
				_moon_hit_check(proj, node.global_position, float(proj.get("dmg", 0.0)))
			if moon_volley_timer <= 0.0:
				_clear_moon_tiles()


func _moon_hit_check(proj: Dictionary, pos: Vector2, dmg: float) -> void:
	var hit_record: Array = proj.get("hit_record", [])
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var eid: int = int(enemy.get_instance_id())
		if hit_record.has(eid):
			continue
		if pos.distance_to(enemy.global_position) <= 54.0:
			enemy.take_damage(dmg)
			_show_damage_number(enemy.global_position, dmg, false)
			_play_sfx("mahjong_moon", 0.95 + rng.randf_range(0.0, 0.15))
			if player != null and is_instance_valid(player):
				_apply_on_hit_skills(enemy, dmg, player.selected_skills, true, false)
			hit_record.append(eid)


func _launch_moon_volley(level: int, tile_count: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dmg: float = float(player.attack_damage) * (_skill_level_value("mahjong_moon", "damage_pct", [0, 80, 100, 130, 150, 180, 220], level) / 100.0) * _hot_damage_mult()
	var start_pos: Vector2 = player.global_position
	# 依距離排序附近敵人，讓整批麻將牌盡量分散命中不同敵人；找不到足夠敵人時以角度分散方向補足。
	var search_radius := 11.0 * TILE_SIZE
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and start_pos.distance_to(e.global_position) <= search_radius:
			enemies.append(e)
	enemies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return start_pos.distance_to(a.global_position) < start_pos.distance_to(b.global_position)
	)
	var used_positions: Array = []
	moon_projectiles.clear()
	for i in range(tile_count):
		var target_pos: Vector2 = start_pos + player._last_move_direction * 7.0 * TILE_SIZE
		var found := false
		for e in enemies:
			if not is_instance_valid(e):
				continue
			var epos: Vector2 = e.global_position
			var occupied := false
			for occ in used_positions:
				if epos.distance_to(occ) <= 60.0:
					occupied = true
					break
			if occupied:
				continue
			target_pos = epos
			found = true
			break
		if not found:
			var spread_angle: float = (TAU / float(maxi(tile_count, 1))) * float(i)
			target_pos = start_pos + player._last_move_direction.rotated(spread_angle) * 7.0 * TILE_SIZE
		used_positions.append(target_pos)
		var node := Sprite2D.new()
		# 注意：海底撈月投射物同樣不可加入 "transient_effects" 群組，理由同大四喜磁磚，
		# 改由 moon_projectiles 陣列自行追蹤與清除（見 _clear_moon_tiles）。
		node.process_mode = Node.PROCESS_MODE_PAUSABLE
		var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/moon_tile.png"
		if ResourceLoader.exists(tex_path):
			node.texture = load(tex_path)
		node.scale = Vector2(1.5, 1.5)
		node.global_position = start_pos
		add_child(node)
		moon_projectiles.append({
			"node": node,
			"start_pos": start_pos,
			"target": target_pos,
			"dmg": dmg,
			"hit_record": []
		})
	moon_volley_phase = "out"
	# 依飛行距離估計出手時間，讓整批麻將牌大致同時抵達各自目標，呈現「一下同時打出」的齊發手感。
	moon_volley_out_duration = maxf(0.15, (7.0 * TILE_SIZE) / 290.0)
	moon_volley_timer = moon_volley_out_duration


func _clear_moon_tiles() -> void:
	for proj in moon_projectiles:
		var node = proj.get("node")
		if is_instance_valid(node):
			node.queue_free()
	moon_projectiles.clear()
	moon_volley_phase = "idle"
	moon_volley_timer = 0.0


func _spawn_sanyuan_effect(pos: Vector2) -> void:
	_spawn_circle_effect(pos, 3.0 * TILE_SIZE, Color(1.0, 0.5, 0.1, 0.45), 0.1, func() -> void: pass)
	var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/sanyuan_fx.png"
	if not ResourceLoader.exists(tex_path):
		return
	var sprite := Sprite2D.new()
	sprite.add_to_group("transient_effects")
	sprite.texture = load(tex_path)
	sprite.global_position = pos
	sprite.scale = Vector2(2.0, 2.0)
	add_child(sprite)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(3.5, 3.5), 0.4)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _spawn_pong_chain_effect(from_pos: Vector2, to_pos: Vector2) -> void:
	_draw_attack_line(from_pos, to_pos, Color(1.0, 0.85, 0.2, 0.9))


func _spawn_wall_block_effect(pos: Vector2) -> void:
	_spawn_circle_effect(pos, 1.5 * TILE_SIZE, Color(0.4, 0.7, 1.0, 0.6), 0.05, func() -> void: pass)
	var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/wall_fx.png"
	if not ResourceLoader.exists(tex_path):
		return
	var sprite := Sprite2D.new()
	sprite.add_to_group("transient_effects")
	sprite.texture = load(tex_path)
	sprite.global_position = pos
	sprite.scale = Vector2(1.5, 1.5)
	add_child(sprite)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(2.5, 2.5), 0.5)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _spawn_flush_effect(pos: Vector2) -> void:
	# 清一色改為「旋風斬」視覺：3 片劈砍圖各自錯開角度、快速旋轉一圈並放大淡出，
	# 疊在一起呈現繞玩家轉一圈的旋風斬效果，範圍以外圈虛線圓提示 6 格判定範圍。
	var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/flush_fx.png"
	if not ResourceLoader.exists(tex_path):
		return
	var blade_tex: Texture2D = load(tex_path)
	var blade_count := 3
	for i in range(blade_count):
		var sprite := Sprite2D.new()
		sprite.add_to_group("transient_effects")
		sprite.texture = blade_tex
		sprite.global_position = pos
		sprite.rotation = TAU * float(i) / float(blade_count)
		sprite.scale = Vector2(2.0, 2.0)
		add_child(sprite)
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		tween.set_parallel(true)
		tween.tween_property(sprite, "rotation", sprite.rotation + TAU, 0.35)
		tween.tween_property(sprite, "scale", Vector2(3.6, 3.6), 0.35)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.35)
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(sprite):
				sprite.queue_free()
		)


func _on_player_wall_blocked(pos: Vector2) -> void:
	_spawn_wall_block_effect(pos)


func _on_area_preview_changed(center: Vector2, radius: float, show_preview: bool) -> void:
	# 顯示或隱藏戰士攻擊範圍預覽圈
	if not is_instance_valid(_attack_preview_node):
		_attack_preview_node = null
	if not show_preview:
		if _attack_preview_node != null and is_instance_valid(_attack_preview_node):
			_attack_preview_node.queue_free()
		_attack_preview_node = null
		return
	# 建立或更新預覽圓
	if _attack_preview_node == null or not is_instance_valid(_attack_preview_node):
		var poly := Polygon2D.new()
		poly.process_mode = Node.PROCESS_MODE_ALWAYS
		poly.z_index = 2
		poly.color = Color(1.0, 0.85, 0.2, 0.22)
		add_child(poly)
		_attack_preview_node = poly
	# 畫圓
	var poly2: Polygon2D = _attack_preview_node as Polygon2D
	var pts := PackedVector2Array()
	for i in range(32):
		var a := float(i) / 32.0 * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly2.polygon = pts
	poly2.global_position = center


func _damage_area(center: Vector2, radius: float, amount: float, limit := 9999, skills: Dictionary = {}, show_effect := true, apply_joker := true) -> void:
	var hit := 0
	if show_effect:
		_spawn_circle_effect(center, radius, Color(1.0, 0.75, 0.2, 0.18), 0.05, func() -> void: pass)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if hit >= limit:
			return
		if is_instance_valid(enemy) and center.distance_to(enemy.global_position) <= radius:
			enemy.take_damage(amount)
			_show_damage_number(enemy.global_position, amount, false)
			if apply_joker:
				_apply_joker_curse_if_active(enemy)
			# 排除 tech_lightning 避免遞迴（chain 自身已呼叫過 lightning）
			if not skills.is_empty():
				var area_skills: Dictionary = skills.duplicate()
				area_skills.erase("tech_lightning")
				if not area_skills.is_empty():
					_apply_on_hit_skills(enemy, amount, area_skills, false, false)
			hit += 1



func _trigger_lightning_chain(first_enemy: Node2D, damage: float, jumps: int, level: int = 1, skills: Dictionary = {}, apply_joker := true) -> void:
	# 鏈式閃電：從 first_enemy 跳到附近最多 jumps 個不同敵人
	if is_instance_valid(player):
		_spawn_lightning_effect(player.global_position, first_enemy.global_position)
	# 音效節流：播放中或播完後1秒內不再播放新的高壓電音效，避免短時間內連續觸發時聲音重疊過於頻繁
	if _lightning_sfx_gate <= 0.0:
		_play_random_sfx(["tech_lightning_1", "tech_lightning_2", "tech_lightning_3"], 0.96 + rng.randf_range(0.0, 0.1), 0.55, 0.16)
		_lightning_sfx_gate = 0.55 + 0.16 + 1.0
	first_enemy.take_damage(damage)
	_show_damage_number(first_enemy.global_position, damage, false)
	if apply_joker:
		_apply_joker_curse_if_active(first_enemy)
	var hit: Array = [first_enemy]
	var from_pos: Vector2 = first_enemy.global_position
	# 跳躍範圍依等級：LV1=1.5格 LV2=2.0格 LV3=2.5格 LV4=3.0格 LV5=3.5格 LV6=4.0格
	var chain_radius: float = _skill_level_value("tech_lightning", "jump_range_tiles", [0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0], level) * TILE_SIZE
	for _j in range(jumps):
		var next_target: Node2D = null
		var best_dist := chain_radius
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or hit.has(e):
				continue
			var d: float = from_pos.distance_to(e.global_position)
			if d < best_dist:
				best_dist = d
				next_target = e
		if next_target == null:
			break
		_spawn_lightning_effect(from_pos, next_target.global_position)
		next_target.take_damage(damage)
		# 使用者需求：高壓電不需要對敵人施放額外的緩速 debuff，這裡移除原本的 apply_slow。
		_show_damage_number(next_target.global_position, damage, false)
		if apply_joker:
			_apply_joker_curse_if_active(next_target)
		# 傳遞 debuff 時排除 tech_lightning，避免無限遞迴
		if not skills.is_empty():
			var chain_skills: Dictionary = skills.duplicate()
			chain_skills.erase("tech_lightning")
			if not chain_skills.is_empty():
				_apply_on_hit_skills(next_target, damage, chain_skills, false, false)
		hit.append(next_target)
		from_pos = next_target.global_position


func _spawn_frost_effect(center: Vector2, radius: float) -> void:
	# 冷卻（tech_frost）觸發緩速時，在緩速範圍內播放AI生成的冰霜特效動畫（快速放大淡入、停留後淡出）
	if not ResourceLoader.exists(FROST_BURST_TEXTURE_PATH):
		return
	var sprite := Sprite2D.new()
	sprite.add_to_group("transient_effects")
	sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite.z_index = 6
	sprite.texture = load(FROST_BURST_TEXTURE_PATH) as Texture2D
	var target_scale: float = (radius * 2.0) / 512.0
	sprite.scale = Vector2.ONE * (target_scale * 0.6)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(sprite)
	sprite.global_position = center
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * target_scale, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.85, 0.12)
	tween.chain().tween_interval(0.12)
	tween.chain().tween_property(sprite, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _spawn_lightning_effect(from_pos: Vector2, to_pos: Vector2, color: Color = Color(1.0, 0.9, 0.1, 1.0)) -> void:
	# 繪製鋸齒閃電線段（Line2D）；color 可自訂（電流砲台用綠色）
	var line := Line2D.new()
	line.add_to_group("transient_effects")
	line.width = 3.0
	line.default_color = color
	line.z_index = 5
	var pts := PackedVector2Array()
	var segs := 7
	var perp: Vector2 = (to_pos - from_pos).normalized().rotated(PI * 0.5)
	for i in range(segs + 1):
		var t: float = float(i) / float(segs)
		var pt: Vector2 = from_pos.lerp(to_pos, t)
		if i > 0 and i < segs:
			pt += perp * rng.randf_range(-14.0, 14.0)
		pts.append(pt)
	line.points = pts
	add_child(line)
	# 閃爍後淡出
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(line, "modulate:a", 0.0, 0.22)
	tween.tween_callback(line.queue_free)


func _spawn_fire_spray_effect(muzzle_pos: Vector2, angle: float, fire_range: float) -> void:
	# 火焰砲：噴火視覺效果（使用生成的火焰噴射圖片素材，依射程縮放並淡出）
	if not ResourceLoader.exists(FIRE_SPRAY_TEXTURE_PATH):
		return
	var s: float = fire_range / FIRE_SPRAY_TEXTURE_MAX_R
	var wrapper := Node2D.new()
	wrapper.add_to_group("transient_effects")
	wrapper.process_mode = Node.PROCESS_MODE_PAUSABLE
	wrapper.z_index = 6
	add_child(wrapper)
	wrapper.global_position = muzzle_pos
	# 素材本身的噴火方向與砲管實際瞄準方向相反，這裡轉180度校正（+PI），
	# 讓視覺上的火焰噴射方向與命中判定方向（fire_dir）一致。
	wrapper.rotation = angle + PI
	var spray := Sprite2D.new()
	spray.texture = load(FIRE_SPRAY_TEXTURE_PATH) as Texture2D
	spray.centered = false
	spray.scale = Vector2(s, s)
	spray.position = -FIRE_SPRAY_TEXTURE_ORIGIN * s
	spray.modulate = Color(1.0, 1.0, 1.0, 0.95)
	wrapper.add_child(spray)
	var stween := create_tween()
	stween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	stween.tween_property(spray, "modulate:a", 0.0, 0.18)
	stween.tween_callback(wrapper.queue_free)


func _fire_chain_turret(origin: Vector2, first_target: Node2D, damage: float, jumps: int) -> void:
	# 電流砲台：綠色電流鏈式攻擊，跳躍次數等於等級
	if not is_instance_valid(first_target):
		return
	var current_color := Color(0.25, 1.0, 0.35, 1.0)
	_spawn_lightning_effect(origin, first_target.global_position, current_color)
	first_target.take_damage(damage)
	_show_damage_number(first_target.global_position, damage, false)
	_apply_turret_hit(first_target, damage)
	var hit: Array = [first_target]
	var from_pos: Vector2 = first_target.global_position
	var chain_radius := 3.5 * TILE_SIZE
	for _j in range(jumps):
		var next_target: Node2D = null
		var best_dist := chain_radius
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or hit.has(e):
				continue
			var d: float = from_pos.distance_to(e.global_position)
			if d < best_dist:
				best_dist = d
				next_target = e
		if next_target == null:
			break
		_spawn_lightning_effect(from_pos, next_target.global_position, current_color)
		next_target.take_damage(damage)
		_show_damage_number(next_target.global_position, damage, false)
		_apply_turret_hit(next_target, damage)
		hit.append(next_target)
		from_pos = next_target.global_position


# ============================================================
# 以下為重建的遺失函式（因檔案截斷而丟失）
# ============================================================

func _hot_damage_mult() -> float:
	# 賭徒熱手（dice_hot）：爆擊後 3 秒內傷害加成。原本只影響玩家主攻擊本身（及其直接觸發的
	# on-hit/麻將技能），這裡額外提供給砲台與大四喜/海底撈月/清一色使用，讓熱手真的符合
	# 「所有傷害提升」的說明文字。刻意不套用在皇家護衛身上（護衛傷害在獨立的 pet 節點計算，
	# 這次沒有一併調整）。
	if active_poker_buffs.has("hot"):
		return 1.0 + float(active_poker_buffs["hot"].get("bonus", 0.0))
	return 1.0


func _skill_cooldown(skill_id: String, default_seconds: float) -> float:
	# 讀取後台可調整的技能冷卻秒數（balance_config.json 的 skills.<id>.cooldown），
	# 沒有設定時使用程式內建的預設值，行為與原本完全相同。
	var def: Dictionary = skill_defs.get(skill_id, {})
	if def.has("cooldown"):
		var raw = def["cooldown"]
		if raw is int or raw is float:
			return maxf(0.05, float(raw))
	return default_seconds


func _skill_level_value(_skill_id: String, _key: String, table: Array, level: int) -> float:
	if table.is_empty():
		return 0.0
	level = clampi(level, 0, 6)
	var skill: Dictionary = skill_defs.get(_skill_id, {})
	var values = skill.get("values", {})
	var source = table
	if values is Dictionary and (values as Dictionary).has(_key):
		source = (values as Dictionary).get(_key)
	if source is Array:
		var source_array: Array = source
		if source_array.is_empty():
			return 0.0
		return float(source_array[clampi(level, 0, source_array.size() - 1)])
	if source is int or source is float:
		return float(source)
	return float(table[clampi(level, 0, table.size() - 1)])


func _style_menu_button(button: Button) -> void:
	# 全選單通用按鈕樣式：深色圓角底＋主題橘色框，滑過亮起、按下加深
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.10, 0.16, 0.92)
	normal.border_color = Color(0.9, 0.65, 0.15, 0.5)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.14, 0.17, 0.26, 0.96)
	hover.border_color = Color(1.0, 0.82, 0.32, 0.95)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.05, 0.06, 0.10, 0.98)
	pressed.border_color = Color(0.9, 0.65, 0.15, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover.duplicate())
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.65))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.8, 0.3))


func _apply_game_font(node: Control, size: int, color: Color, outline_size: int) -> void:
	if _game_font != null:
		node.add_theme_font_override("font", _game_font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if outline_size > 0:
		node.add_theme_constant_override("outline_size", outline_size)
		node.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))


func _flash_message(text: String) -> void:
	if not is_instance_valid(message_label):
		return
	message_label.text = text
	message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(1.6)
	tween.tween_property(message_label, "modulate:a", 0.0, 0.5)


func _get_skill_icon_path(skill_id: String, level: int) -> String:
	if skill_id.begins_with("fish_"):
		var tower_num_map: Dictionary = {
			"fish_rapid": 1,
			"fish_fire": 2,
			"fish_saw": 3,
			"fish_missile": 4,
			"fish_laser": 5,
			"fish_chain": 6,
		}
		if not tower_num_map.has(skill_id):
			return ""
		return "res://AIgame_rougelike/assets/art/skills/tower/tower_%d_2.png" % int(tower_num_map[skill_id])
	var skill_num_map: Dictionary = {
		"poker_heart": ["poker", 1], "poker_spade": ["poker", 2], "poker_diamond": ["poker", 3],
		"poker_club": ["poker", 4], "poker_joker": ["poker", 5], "poker_guard": ["poker", 6],
		"dice_crit": ["dice", 1], "dice_execute": ["dice", 2], "dice_first": ["dice", 3],
		"dice_blast": ["dice", 4], "dice_last": ["dice", 5], "dice_hot": ["dice", 6],
		"tech_frost": ["tech", 1], "tech_fire": ["tech", 2], "tech_poison": ["tech", 3],
		"tech_lightning": ["tech", 4], "tech_meltdown": ["tech", 5], "tech_magnet": ["tech", 6],
		"mahjong_sanyuan": ["mahjong", 1], "mahjong_sixi": ["mahjong", 2],
		"mahjong_pong": ["mahjong", 3], "mahjong_moon": ["mahjong", 4],
		"mahjong_wall": ["mahjong", 5], "mahjong_flush": ["mahjong", 6],
	}
	if not skill_num_map.has(skill_id):
		return ""
	var info: Array = skill_num_map[skill_id]
	var school: String = str(info[0])
	var num: int = int(info[1])
	@warning_ignore("integer_division")
	var lv_idx: int = clampi((level - 1) / 2 + 1, 1, 4)
	return "res://AIgame_rougelike/assets/art/skills/%s/%02d_%02d.png" % [school, num, lv_idx]


func _get_tower_part_path(skill_id: String, part_index: int) -> String:
	var tower_num_map: Dictionary = {
		"fish_rapid": 1,
		"fish_fire": 2,
		"fish_saw": 3,
		"fish_missile": 4,
		"fish_laser": 5,
		"fish_chain": 6,
	}
	if not tower_num_map.has(skill_id):
		return ""
	return "res://AIgame_rougelike/assets/art/skills/tower/tower_%d_%d.png" % [int(tower_num_map[skill_id]), clampi(part_index, 1, 2)]


func _get_skill_max_cooldown(skill_id: String) -> float:
	if skill_id.begins_with("fish_"):
		return 15.0
	match skill_id:
		"tech_meltdown": return 2.0
		"tech_magnet": return 5.0
		"mahjong_flush": return 5.0
		"mahjong_wall": return 10.0
	return 0.0


func _update_ui() -> void:
	if player == null or not is_instance_valid(player):
		return
	# 血量
	var hearts := ""
	for _hi in range(player.health):
		hearts += "❤"
	for _hi in range(player.max_health - player.health):
		hearts += "🖤"
	heart_label.text = hearts
	stage_label.text = "關卡 %d / %d" % [current_stage, stage_defs.size()]
	chip_label.text = "晶片：%d" % total_chips
	var enemy_cnt := get_tree().get_nodes_in_group("enemies").size()
	enemy_count_label.text = "敵人：%d" % enemy_cnt
	level_label.text = ""
	# 技能欄：Hash 比對，只在技能改變時重建
	var skill_hash := str(player.selected_skills)
	if skill_hash != _skill_bar_skill_hash:
		_skill_bar_skill_hash = skill_hash
		for child in skill_bar.get_children():
			child.queue_free()
		_turret_hotkey_map.clear()
		var fish_hotkey := 1
		for raw_id in player.selected_skills.keys():
			var sid := str(raw_id)
			var level: int = int(player.selected_skills[raw_id])
			var def: Dictionary = skill_defs.get(sid, {})
			var is_turret: bool = str(def.get("school", "")) == "魚機"
			var hk := 0
			if is_turret:
				hk = fish_hotkey
				_turret_hotkey_map[hk] = sid
				fish_hotkey += 1
			var icon_tex: Texture2D = null
			var icon_path := _get_skill_icon_path(sid, level)
			if icon_path != "" and ResourceLoader.exists(icon_path):
				icon_tex = load(icon_path) as Texture2D
			var slot := SkillSlotScript.new()
			slot.setup({
				"id": sid, "name": str(def.get("name", sid)), "level": level,
				"icon": icon_tex,
				"cooldown": float(skill_cooldowns.get(sid, 0.0)),
				"max_cooldown": _get_skill_max_cooldown(sid),
				"is_turret": is_turret, "hotkey": hk,
				"description": str(def.get("desc", ""))
			})
			var _sid_cap := sid
			var _lv_cap := level
			var _hk_cap := hk
			slot.tooltip_requested.connect(func(_t: String, _p: Vector2) -> void:
				_show_hover_tooltip(_skill_tooltip_bbcode(_sid_cap, _lv_cap), _p)
			)
			slot.tooltip_closed.connect(_hide_hover_tooltip)
			# 砲台技能：滑鼠點擊也可施放
			if is_turret and _hk_cap > 0:
				slot.activated.connect(func(_id: String) -> void:
					_cast_turret_by_index(_hk_cap)
				)
			skill_bar.add_child(slot)
		# 空槽補齊
		for _ei in range(MAX_ACTIVE_SKILLS - player.selected_skills.size()):
			var empty := SkillSlotScript.new()
			empty.setup({
				"id": "", "name": "", "level": 0, "icon": null,
				"cooldown": 0.0, "max_cooldown": 0.0,
				"is_turret": false, "hotkey": 0, "description": ""
			})
			skill_bar.add_child(empty)
	else:
		# 只更新冷卻進度，不重建
		for child in skill_bar.get_children():
			if child.has_method("update_cooldown"):
				var sid_var = child.get("skill_id")
				if sid_var != null:
					var sid: String = str(sid_var)
					if sid != "" and sid != "<null>":
						child.update_cooldown(
							float(skill_cooldowns.get(sid, 0.0)),
							_get_skill_max_cooldown(sid)
						)


func _clamp_player_to_map() -> void:
	if player == null or not is_instance_valid(player):
		return
	var margin := 24.0
	var p := player.global_position
	p.x = clampf(p.x, map_rect.position.x + margin, map_rect.end.x - margin)
	p.y = clampf(p.y, map_rect.position.y + margin, map_rect.end.y - margin)
	player.global_position = p


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data = json.get_data()
		if data is Dictionary:
			for k in data.keys():
				game_settings[k] = data[k]
	f.close()
	_apply_volume()
	# 套用按鍵綁定
	var keys: Dictionary = game_settings.get("keys", {})
	for action in keys.keys():
		_apply_input_binding(str(action), str(keys[action]))


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(game_settings))
	f.close()


func _apply_volume() -> void:
	var vol := clampf(float(game_settings.get("volume", 0.8)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(vol))


func _load_save_slots() -> void:
	save_slots = []
	for _i in range(SAVE_SLOT_COUNT):
		save_slots.append({})
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data = json.get_data()
		if data is Array:
			for i in range(mini(data.size(), SAVE_SLOT_COUNT)):
				if data[i] is Dictionary:
					save_slots[i] = data[i]
	f.close()


func _save_current_slot() -> void:
	if selected_save_slot < 0 or selected_save_slot >= save_slots.size():
		return
	var slot: Dictionary = save_slots[selected_save_slot]
	slot["total_chips"] = total_chips
	slot["last_played"] = Time.get_datetime_string_from_system()
	slot["research"] = current_research.duplicate(true)
	slot["stage"] = current_stage
	slot["kills"] = kill_count
	save_slots[selected_save_slot] = slot
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_slots))
		f.close()


func _sync_current_save_slot() -> void:
	if selected_save_slot >= 0 and selected_save_slot < save_slots.size():
		var slot: Dictionary = save_slots[selected_save_slot]
		total_chips = int(slot.get("total_chips", 0))
		current_research = (slot.get("research", {}) as Dictionary).duplicate(true)


func _return_to_lobby() -> void:
	game_started = false
	is_game_ended = false
	get_tree().paused = false
	_clear_world_objects(false)
	_set_menu_background_visible(true)
	if player != null and is_instance_valid(player):
		player.visible = false
		player.poker_dodge_chance = 0.0
		player.poker_aps_mult = 1.0
	active_poker_buffs.clear()
	# 重置計數器和冷卻
	sanyuan_pending = false
	sanyuan_hit_counter = 0
	flush_cooldown = 0.0
	moon_cooldown = 0.0
	magnet_cooldown = 0.0
	meltdown_cooldown = 0.0
	poker_timer = 0.0
	_poker_blink_timer = 0.0
	skill_cooldowns.clear()
	_turret_hotkey_map.clear()
	_hide_all_overlays()
	_show_lobby()


func _spawn_execute_effect(pos: Vector2) -> void:
	# 斬殺骰觸發：紅色 X 斬擊，快速放大並淡出
	for angle_deg in [45.0, -45.0]:
		var line := Line2D.new()
		line.add_to_group("transient_effects")
		line.z_index = 14
		line.width = 7.0
		line.default_color = Color(1.0, 0.12, 0.1, 0.95)
		var dir := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
		line.points = PackedVector2Array([-dir * 26.0, dir * 26.0])
		add_child(line)
		line.global_position = pos
		line.scale = Vector2.ONE * 0.4
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		tween.tween_property(line, "scale", Vector2.ONE * 1.6, 0.22).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(line, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func() -> void:
			if is_instance_valid(line):
				line.queue_free()
		)


func _spawn_ignite_effect(pos: Vector2) -> void:
	# 過載（燃燒）附加瞬間：三顆小火苗往上飄散淡出
	for i in range(3):
		var flame := Polygon2D.new()
		flame.add_to_group("transient_effects")
		flame.z_index = 13
		var pts := PackedVector2Array()
		var flame_r := rng.randf_range(4.0, 7.0)
		for j in range(10):
			pts.append(Vector2(cos(TAU * j / 10.0), sin(TAU * j / 10.0)) * flame_r)
		flame.polygon = pts
		flame.color = Color(1.0, rng.randf_range(0.4, 0.7), 0.1, 0.85)
		add_child(flame)
		flame.global_position = pos + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-6.0, 6.0))
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		tween.tween_property(flame, "global_position",
			flame.global_position + Vector2(rng.randf_range(-8.0, 8.0), -rng.randf_range(18.0, 30.0)), 0.4)
		tween.parallel().tween_property(flame, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func() -> void:
			if is_instance_valid(flame):
				flame.queue_free()
		)


func _spawn_hit_spark(pos: Vector2, is_crit: bool) -> void:
	# 所有技能命中怪物時的小型命中特效，刻意做小避免遮擋畫面
	if not ResourceLoader.exists(HIT_SPARK_TEXTURE_PATH):
		return
	var spark := Sprite2D.new()
	spark.add_to_group("transient_effects")
	spark.process_mode = Node.PROCESS_MODE_PAUSABLE
	spark.z_index = 8
	spark.texture = load(HIT_SPARK_TEXTURE_PATH) as Texture2D
	var base_size: float = 30.0 if is_crit else 20.0
	spark.scale = Vector2.ONE * (base_size / 128.0)
	spark.rotation = rng.randf_range(0.0, TAU)
	spark.modulate = Color(1.0, 1.0, 1.0, 0.9)
	add_child(spark)
	spark.global_position = pos + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
	var stween := create_tween()
	stween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	stween.set_parallel(true)
	stween.tween_property(spark, "scale", spark.scale * 1.4, 0.16)
	stween.tween_property(spark, "modulate:a", 0.0, 0.16)
	stween.chain().tween_callback(spark.queue_free)


func _show_damage_number(pos: Vector2, amount: float, is_crit: bool) -> void:
	_spawn_hit_spark(pos, is_crit)
	var lbl := Label.new()
	lbl.add_to_group("damage_numbers")
	var display := int(maxf(1.0, round(amount)))
	lbl.text = ("★%d" % display) if is_crit else str(display)
	# 傷害數字統一放大 1.2 倍
	var font_size := int(round((30 if is_crit else 20) * 1.2))
	var color := Color(1.0, 0.92, 0.1) if is_crit else Color.WHITE
	_apply_game_font(lbl, font_size, color, 2)
	lbl.z_index = 20
	lbl.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(lbl)
	lbl.global_position = pos + Vector2(rng.randf_range(-18.0, 18.0), -28.0)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 52.0, 0.75)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.75)
	tween.chain().tween_callback(lbl.queue_free)


func _spawn_circle_effect(center: Vector2, radius: float, color: Color, duration: float, on_done: Callable) -> void:
	var poly := Polygon2D.new()
	poly.add_to_group("transient_effects")
	poly.process_mode = Node.PROCESS_MODE_PAUSABLE
	poly.z_index = 3
	poly.color = color
	var pts := PackedVector2Array()
	var segs := 32
	for i in range(segs):
		var a := float(i) / float(segs) * TAU
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	add_child(poly)
	poly.global_position = center
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_interval(duration)
	tween.tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call()
	)
	tween.tween_property(poly, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func() -> void:
		if is_instance_valid(poly):
			poly.queue_free()
	)


func _draw_attack_line(from_pos: Vector2, to_pos: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.add_to_group("transient_effects")
	line.width = 3.0
	line.default_color = color
	line.z_index = 8
	line.add_point(from_pos)
	line.add_point(to_pos)
	add_child(line)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.tween_property(line, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void:
		if is_instance_valid(line):
			line.queue_free()
	)


func _nearest_enemy(from_pos: Vector2, max_range: float, exclude: Array = []) -> Node2D:
	var best: Node2D = null
	var best_dist := max_range + 1.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or exclude.has(enemy):
			continue
		var d: float = from_pos.distance_to(enemy.global_position)
		if d <= max_range and d < best_dist:
			best_dist = d
			best = enemy as Node2D
	return best


func _spawn_enemy_bullet(origin: Vector2, target_position: Vector2, speed: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var BossBulletScript := load("res://AIgame_rougelike/scripts/boss_bullet.gd")
	if BossBulletScript == null:
		return
	var bullet := Node2D.new()
	bullet.add_to_group("transient_effects")
	bullet.set_script(BossBulletScript)
	bullet.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bullet)
	bullet.setup(origin, target_position, speed, 1, player)
	bullets.append(bullet)


func _has_poker_skill() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	for sid in player.selected_skills.keys():
		if str(sid).begins_with("poker_"):
			return true
	return false


func _poker_skills_signature() -> String:
	# 用來偵測玩家「目前擁有哪些樸克技能＋各自等級」是否有變動；
	# 排序後組字串，同一組合永遠得到同一個簽章，變動（新增/升級/失去）就會不同
	if player == null or not is_instance_valid(player):
		return ""
	var parts: Array = []
	for sid in player.selected_skills.keys():
		var s := str(sid)
		if s.begins_with("poker_"):
			parts.append("%s:%d" % [s, player.get_skill_level(s)])
	parts.sort()
	return ",".join(parts)


func _clear_poker_indicators() -> void:
	for key in _poker_icons.keys():
		var data: Dictionary = _poker_icons[key]
		var sprite = data.get("sprite")
		if is_instance_valid(sprite):
			sprite.queue_free()
		var lbl = data.get("label")
		if is_instance_valid(lbl):
			lbl.queue_free()
	_poker_icons.clear()


func _reset_poker_draw_animation() -> void:
	_poker_drawing = false
	_poker_draw_pending_card = ""
	if is_instance_valid(_poker_draw_sprite):
		_poker_draw_sprite.queue_free()
	if is_instance_valid(_poker_draw_label):
		_poker_draw_label.queue_free()
	_poker_draw_sprite = null
	_poker_draw_label = null


func _show_poker_indicator(card: String) -> void:
	# 清除同 card 舊指示器
	if _poker_icons.has(card):
		var old: Dictionary = _poker_icons[card]
		if is_instance_valid(old.get("sprite")):
			old["sprite"].queue_free()
		if is_instance_valid(old.get("label")):
			old["label"].queue_free()
	var def: Dictionary = skill_defs.get("poker_" + card, {})
	var icon_path := _get_skill_icon_path("poker_" + card, player.get_skill_level("poker_" + card) if player != null else 1)
	# Sprite
	var sprite := Sprite2D.new()
	sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
	sprite.z_index = 15
	if icon_path != "" and ResourceLoader.exists(icon_path):
		sprite.texture = load(icon_path) as Texture2D
	sprite.scale = Vector2(0.55, 0.55)
	add_child(sprite)
	# Label
	var lbl := Label.new()
	lbl.process_mode = Node.PROCESS_MODE_PAUSABLE
	lbl.z_index = 15
	_apply_game_font(lbl, 14, Color(1.0, 0.92, 0.3), 1)
	lbl.text = str(def.get("name", card))
	add_child(lbl)
	_poker_icons[card] = {"sprite": sprite, "label": lbl}


func _update_poker_indicator_positions() -> void:
	if player == null or not is_instance_valid(player):
		return
	var idx := 0
	# 閃爍週期 0.3 秒（on 0.15s / off 0.15s），buff 剩 2 秒前開始閃爍
	var blink := fmod(_poker_blink_timer, 0.3) < 0.15
	var blink_visible := (poker_timer < 2.0 and blink) or poker_timer >= 2.0
	for card in _poker_icons.keys():
		var data: Dictionary = _poker_icons[card]
		var offset := Vector2(-float(_poker_icons.size() - 1) * 22.0 * 0.5 + float(idx) * 22.0, -60.0)
		var sprite = data.get("sprite")
		if is_instance_valid(sprite):
			sprite.global_position = player.global_position + offset
			sprite.visible = blink_visible
		var lbl = data.get("label")
		if is_instance_valid(lbl):
			lbl.global_position = player.global_position + offset + Vector2(-16.0, 10.0)
			lbl.visible = blink_visible
		idx += 1


func _process_bullets(delta: float) -> void:
	# 更新撲克指示器位置
	if game_started and not is_game_ended:
		_update_poker_indicator_positions()
	# 處理子彈
	for i in range(bullets.size() - 1, -1, -1):
		var item = bullets[i]
		if item is Dictionary:
			var bnode: Node2D = item.get("node") as Node2D
			if not is_instance_valid(bnode):
				bullets.remove_at(i)
				continue
			item["life"] = float(item.get("life", 5.0)) - delta
			if float(item["life"]) <= 0.0:
				bnode.queue_free()
				bullets.remove_at(i)
				continue
			var btype: String = str(item.get("type", ""))
			var bdamage: float = float(item.get("damage", 1.0))
			var bspeed: float = float(item.get("speed", 400.0))
			if btype == "turret_rapid":
				var bdir: Vector2 = item["direction"]
				bnode.global_position += bdir * bspeed * delta
				bnode.rotation = bdir.angle()
				for enemy in get_tree().get_nodes_in_group("enemies"):
					if is_instance_valid(enemy) and bnode.global_position.distance_to(enemy.global_position) <= 28.0:
						enemy.take_damage(bdamage)
						_show_damage_number(enemy.global_position, bdamage, false)
						if player != null:
							_apply_on_hit_skills(enemy, bdamage, player.selected_skills, false, false)
						bnode.queue_free()
						bullets.remove_at(i)
						break
			elif btype == "turret_missile":
				var tgt: Node2D = item.get("target") as Node2D
				if is_instance_valid(tgt):
					var mdir := bnode.global_position.direction_to(tgt.global_position)
					bnode.global_position += mdir * bspeed * delta
					bnode.rotation = mdir.angle()
					if bnode.global_position.distance_to(tgt.global_position) <= 30.0:
						tgt.take_damage(bdamage)
						_show_damage_number(tgt.global_position, bdamage, false)
						if player != null:
							_apply_on_hit_skills(tgt, bdamage, player.selected_skills, false, false)
						bnode.queue_free()
						bullets.remove_at(i)
				else:
					bnode.queue_free()
					bullets.remove_at(i)
		elif item is Node:
			# 敵人子彈（boss_bullet.gd 自行處理移動與命中）
			if not is_instance_valid(item as Node):
				bullets.remove_at(i)


func _poker_spade_bonus(level: int) -> float:
	# 黑桃：傷害 +20% 每級，LV1=+20%…LV6=+120%
	return _skill_level_value("poker_spade", "bonus_pct", [0, 20, 40, 60, 80, 100, 120], level) / 100.0


func _poker_diamond_bonus(level: int) -> float:
	# 鑽石：爆擊倍率額外加成 LV1=+0.5…LV6=+3.0
	return _skill_level_value("poker_diamond", "bonus_mult", [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0], level)


func _poker_joker_bonus(level: int) -> float:
	# 小丑詛咒：使敵人受到的傷害增加 LV1=+30%…LV6=+180%
	return _skill_level_value("poker_joker", "bonus_pct", [0, 30, 60, 90, 120, 150, 180], level) / 100.0


func _apply_joker_curse_if_active(enemy: Node2D) -> void:
	# 小丑牌啟用時，所有「非砲台」的玩家傷害來源（主攻擊、DOT／燃燒／毒素、雷電、麻將系技能等）
	# 命中/造成傷害時都會觸發（或刷新）敵人身上的易傷詛咒；砲台刻意不觸發，維持先前的範圍界線。
	if not active_poker_buffs.has("joker"):
		return
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_method("apply_joker_curse"):
		return
	if player == null or not is_instance_valid(player):
		return
	var joker_mult: float = 1.0 + _poker_joker_bonus(player.get_skill_level("poker_joker"))
	enemy.apply_joker_curse(joker_mult, 6.0)


func _apply_poker_card(card: String) -> void:
	# 清除同類舊效果，並重設玩家 poker 數值
	active_poker_buffs.erase(card)
	if player != null and is_instance_valid(player):
		player.poker_dodge_chance = 0.0
		player.poker_aps_mult = 1.0
	match card:
		"heart":
			# 紅心：閃避率提升，套用至玩家
			active_poker_buffs["heart"] = true
			if player != null and is_instance_valid(player):
				var lv: int = player.get_skill_level("poker_heart")
				player.poker_dodge_chance = _skill_level_value("poker_heart", "bonus_pct", [0, 10, 20, 30, 40, 50, 60], lv) / 100.0
		"spade":
			# 黑桃：傷害提升（_apply_attack_outcome 讀取）
			active_poker_buffs["spade"] = true
		"diamond":
			# 鑽石：爆擊倍率提升（_apply_attack_outcome 讀取）
			active_poker_buffs["diamond"] = true
		"club":
			# 梅花：攻速提升，套用至玩家
			active_poker_buffs["club"] = true
			if player != null and is_instance_valid(player):
				var lv: int = player.get_skill_level("poker_club")
				player.poker_aps_mult = 1.0 + _skill_level_value("poker_club", "bonus_pct", [0, 100, 150, 200, 250, 300, 350], lv) / 100.0
		"joker":
			# 小丑：詛咒乘進傷害（_apply_attack_outcome 讀取）
			active_poker_buffs["joker"] = true
		"guard":
			# 皇家護衛：召喚護衛
			_spawn_poker_guard()
	_show_poker_indicator(card)
	_play_sfx("ui_select", 1.1)


func _clear_poker_guard_pets() -> void:
	for pet in _poker_guard_pets:
		if is_instance_valid(pet):
			pet.queue_free()
	_poker_guard_pets.clear()


func _on_poker_guard_attack(from_position: Vector2, target_position: Vector2, damage_amount: int) -> void:
	_show_damage_number(target_position, float(damage_amount), false)
	# 護衛攻擊音效：沿用玩家命中音效，音量降低 40%（約 -4.4dB，等同音量剩 60%）
	_play_sfx_volume("hit", 0.9 + rng.randf_range(0.0, 0.2), -4.44, 0.28, 0.08)


func _spawn_poker_guard() -> void:
	if player == null or not is_instance_valid(player):
		return
	# 皇家牌現在也比照其他花色「抽到新牌就清除舊效果」的規則：
	# 每次重新召喚前，先把先前留下的護衛全部清空，再依目前等級一次補滿到上限，
	# 而不是像以前那樣每次只增加 1 隻、慢慢疊到上限。
	_clear_poker_guard_pets()
	if not ResourceLoader.exists("res://AIgame_rougelike/scenes/cat_pet.tscn"):
		return
	var lv: int = player.get_skill_level("poker_guard")
	var max_guards: int = int(_skill_level_value("poker_guard", "count", [0, 1, 2, 3, 3, 3, 3], lv))
	var dmg_mult: float = _skill_level_value("poker_guard", "damage_multiplier",
		[0, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], lv)
	for _i in range(max_guards):
		var pet := CatPetScene.instantiate()
		pet.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(pet)
		pet.global_position = player.global_position + Vector2(rng.randf_range(-48, 48), rng.randf_range(-48, 48))
		# 修正：cat_pet.gd 的 setup() 只接受 (玩家, 跟隨偏移量) 兩個參數，
		# 先前傳入 3 個參數會呼叫失敗，導致 player 從未指定，護衛下一幀就被清除。
		if pet.has_method("setup"):
			pet.setup(player, Vector2(rng.randf_range(-48, 48), rng.randf_range(-48, 48)))
		pet.damage_multiplier = dmg_mult
		pet.collect_drops = false
		pet.scale = Vector2(1.2, 1.2)
		if pet.has_signal("pet_attack"):
			pet.pet_attack.connect(_on_poker_guard_attack)
		_poker_guard_pets.append(pet)


func _process_poker(delta: float) -> void:
	if not game_started or is_game_ended or player == null:
		return
	# 若玩家身上已無皇家護衛技能，護衛應立即移除
	if is_instance_valid(player) and player.get_skill_level("poker_guard") <= 0 and not _poker_guard_pets.is_empty():
		for pet in _poker_guard_pets:
			if is_instance_valid(pet):
				pet.queue_free()
		_poker_guard_pets.clear()
	# 更新 dice_hot 計時器
	if active_poker_buffs.has("hot"):
		var hot: Dictionary = active_poker_buffs["hot"]
		hot["timer"] = float(hot["timer"]) - delta
		if float(hot["timer"]) <= 0.0:
			active_poker_buffs.erase("hot")
		else:
			active_poker_buffs["hot"] = hot
	if not _has_poker_skill():
		return
	if _poker_drawing:
		_process_poker_draw_animation(delta)
		return
	poker_timer -= delta
	if poker_timer > 0.0:
		return
	# 重建牌組（每輪洗牌）
	poker_timer = 20.0
	# 若玩家的樸克技能組合（新增/升級）有變動，即使舊牌組還沒抽完也要重建，
	# 避免「早期只抽到黑桃、後來新加的其他花色技能要等很久才會被抽到」的問題
	var cur_sig := _poker_skills_signature()
	if poker_deck.is_empty() or cur_sig != _poker_deck_signature:
		poker_deck.clear()
		# 根據玩家已有的撲克技能建立牌組
		for sid in player.selected_skills.keys():
			var s := str(sid)
			if s.begins_with("poker_"):
				var card_type := s.substr(6)   # 去掉 "poker_"
				var lv: int = player.get_skill_level(s)
				for _rep in range(lv):          # 等級越高，牌越多張
					poker_deck.append(card_type)
		poker_deck.shuffle()
		_poker_deck_signature = cur_sig
	if poker_deck.is_empty():
		return
	var card: String = str(poker_deck.pop_front())
	poker_discard.append(card)
	_start_poker_draw_animation(card)


func _start_poker_draw_animation(card: String) -> void:
	# 抽牌前先展示 2 秒跑牌動畫（所有花色跳過一輪），動畫結束才正式定牌套用效果
	# 一開始抽牌就先清除上一張牌的 buff 與頭上圖示，新牌要等動畫結束才會出現並生效
	for k in ["heart", "spade", "diamond", "club", "joker"]:
		active_poker_buffs.erase(k)
	if player != null and is_instance_valid(player):
		player.poker_dodge_chance = 0.0
		player.poker_aps_mult = 1.0
	# 皇家牌（護衛）現在也比照其他花色，抽新牌時立即清除舊效果；
	# 若新抽到的仍是「guard」，_apply_poker_card() 稍後會重新召喚滿額護衛。
	_clear_poker_guard_pets()
	_clear_poker_indicators()
	_poker_drawing = true
	_poker_draw_timer = 2.0
	_poker_draw_cycle_timer = 0.0
	_poker_draw_cycle_index = 0
	_poker_draw_pending_card = card
	if not is_instance_valid(_poker_draw_sprite):
		_poker_draw_sprite = Sprite2D.new()
		_poker_draw_sprite.process_mode = Node.PROCESS_MODE_PAUSABLE
		_poker_draw_sprite.z_index = 16
		_poker_draw_sprite.scale = Vector2(0.7, 0.7)
		add_child(_poker_draw_sprite)
	if not is_instance_valid(_poker_draw_label):
		_poker_draw_label = Label.new()
		_poker_draw_label.process_mode = Node.PROCESS_MODE_PAUSABLE
		_poker_draw_label.z_index = 16
		_apply_game_font(_poker_draw_label, 14, Color(1.0, 0.92, 0.3), 1)
		add_child(_poker_draw_label)
	_poker_draw_sprite.visible = true
	_poker_draw_label.visible = true
	_update_poker_draw_visual(POKER_CARD_ORDER[0])


func _process_poker_draw_animation(delta: float) -> void:
	_poker_draw_timer -= delta
	_poker_draw_cycle_timer -= delta
	if _poker_draw_cycle_timer <= 0.0:
		# 跑牌速度：2 秒內至少跑完一輪所有花色（5 種 × 0.08 秒 = 0.4 秒／輪）
		_poker_draw_cycle_timer = 0.08
		_poker_draw_cycle_index = (_poker_draw_cycle_index + 1) % POKER_CARD_ORDER.size()
		_update_poker_draw_visual(POKER_CARD_ORDER[_poker_draw_cycle_index])
	if is_instance_valid(player):
		var pos: Vector2 = player.global_position + Vector2(0.0, -60.0)
		if is_instance_valid(_poker_draw_sprite):
			_poker_draw_sprite.global_position = pos
		if is_instance_valid(_poker_draw_label):
			_poker_draw_label.global_position = pos + Vector2(-16.0, 20.0)
	if _poker_draw_timer <= 0.0:
		_finish_poker_draw_animation()


func _update_poker_draw_visual(card: String) -> void:
	var icon_path := _get_skill_icon_path("poker_" + card, 1)
	if is_instance_valid(_poker_draw_sprite):
		_poker_draw_sprite.texture = (load(icon_path) as Texture2D) if (icon_path != "" and ResourceLoader.exists(icon_path)) else null
	if is_instance_valid(_poker_draw_label):
		var def: Dictionary = skill_defs.get("poker_" + card, {})
		_poker_draw_label.text = str(def.get("name", card))


func _finish_poker_draw_animation() -> void:
	_poker_drawing = false
	if is_instance_valid(_poker_draw_sprite):
		_poker_draw_sprite.queue_free()
	if is_instance_valid(_poker_draw_label):
		_poker_draw_label.queue_free()
	_poker_draw_sprite = null
	_poker_draw_label = null
	var card: String = _poker_draw_pending_card
	_poker_draw_pending_card = ""
	if card == "":
		return
	# 舊 buff 與圖示已在動畫開始時清除，這裡動畫結束才正式定牌、套用新效果並顯示新圖示
	_apply_poker_card(card)


func _is_turret_aimed(turret: Dictionary) -> bool:
	var node: Node2D = turret.get("node") as Node2D
	if not is_instance_valid(node):
		return false
	var range_px: float = float(turret.get("range", 5.0 * TILE_SIZE))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and node.global_position.distance_to(enemy.global_position) <= range_px:
			return true
	return false


func _process_turret_visuals(delta: float) -> void:
	for index in range(turrets.size()):
		var turret: Dictionary = turrets[index]
		var node: Node2D = turret.get("node") as Node2D
		if not is_instance_valid(node):
			continue
		var skill_id: String = str(turret.get("skill_id", ""))
		# 鋸齒砲台：不追蹤敵人，只讓砲管（鋸齒片）本身持續自轉，
		# 底座 base_sprite 保持不動，避免底座美術未置中造成整體轉動時歪斜/搖晃。
		# 若想改成底座也一起轉，或校正底座美術置中，可調整這裡與
		# assets/art/skills/tower/tower_3_2.png（底座圖）。
		if skill_id == "fish_saw":
			var barrel: Sprite2D = node.get_node_or_null("barrel_sprite") as Sprite2D
			if is_instance_valid(barrel):
				barrel.rotation += delta * 6.0
			_update_saw_sfx_state(turret, node, delta)
			_update_saw_range_visual(turret, delta)
			turrets[index] = turret
			continue
		# 電流砲台：本身不轉動
		if skill_id == "fish_chain":
			continue
		var range_px: float = float(turret.get("range", 5.0 * TILE_SIZE))
		# 找最近敵人並旋轉
		var nearest: Node2D = _nearest_enemy(node.global_position, range_px)
		if nearest != null:
			var dir := node.global_position.direction_to(nearest.global_position)
			node.rotation = lerp_angle(node.rotation, dir.angle(), 0.2)


func _update_saw_sfx_state(turret: Dictionary, node: Node2D, delta: float) -> void:
	# 鋸齒砲攻擊音效素材約 5 秒：不可每 0.1 秒攻擊就重播，
	# 改為完整播完＋淡出後，若仍在攻擊範圍內才等待 1 秒重播一次。
	if bool(turret.get("saw_sfx_playing", false)):
		turret["saw_sfx_time_left"] = float(turret.get("saw_sfx_time_left", 0.0)) - delta
		if float(turret["saw_sfx_time_left"]) <= 0.0:
			turret["saw_sfx_playing"] = false
			turret["saw_sfx_wait_left"] = 1.0
		return
	var wait_left: float = float(turret.get("saw_sfx_wait_left", 0.0))
	if wait_left > 0.0:
		wait_left -= delta
		turret["saw_sfx_wait_left"] = wait_left
		if wait_left > 0.0:
			return
	if _is_turret_aimed(turret):
		turret["saw_sfx_playing"] = true
		turret["saw_sfx_time_left"] = 5.0
		turret["saw_sfx_wait_left"] = 0.0
		_play_turret_sfx_limited("turret_saw", node.global_position, 1.0, 5.0, 0.5)


func _update_saw_range_visual(turret: Dictionary, delta: float) -> void:
	# 鋸齒砲攻擊範圍圈：有敵人在範圍內就淡入 0.5 秒顯示一次並持續維持；
	# 範圍內連續 2 秒沒有敵人才淡出 0.5 秒消失，避免敵人只是短暫離開範圍就一直閃爍。
	var range_node: Polygon2D = turret.get("saw_range_node") as Polygon2D
	if not is_instance_valid(range_node):
		return
	var has_target := _is_turret_aimed(turret)
	if has_target:
		turret["saw_no_target_timer"] = 0.0
		if not bool(turret.get("saw_range_visible", false)):
			turret["saw_range_visible"] = true
			var tw := create_tween()
			tw.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			tw.tween_property(range_node, "color:a", 0.16, 0.5)
	else:
		var no_target_time: float = float(turret.get("saw_no_target_timer", 0.0)) + delta
		turret["saw_no_target_timer"] = no_target_time
		if no_target_time >= 2.0 and bool(turret.get("saw_range_visible", false)):
			turret["saw_range_visible"] = false
			var tw2 := create_tween()
			tw2.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			tw2.tween_property(range_node, "color:a", 0.0, 0.5)


func _fire_turret(turret: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var node: Node2D = turret.get("node") as Node2D
	if not is_instance_valid(node):
		return
	var skill_id: String = str(turret.get("skill_id", ""))
	var level: int = int(turret.get("level", 1))
	var range_px: float = float(turret.get("range", 5.0 * TILE_SIZE))
	var damage: float = float(turret.get("damage", float(player.attack_damage)))
	# 取得砲口位置（若有 muzzle 子節點）
	var muzzle_pos: Vector2 = node.global_position
	var muzzle: Node2D = node.get_node_or_null("muzzle") as Node2D
	if is_instance_valid(muzzle):
		muzzle_pos = muzzle.global_position

	match skill_id:
		"fish_rapid":
			# 連射砲：對最近敵人射出子彈
			var target := _nearest_enemy(node.global_position, range_px)
			if target == null:
				return
			var dmg: float = damage * (_skill_level_value("fish_rapid", "dmg_pct",
				[0, 100, 120, 150, 170, 185, 200], level) / 100.0) * _hot_damage_mult()
			var bullet_node := Node2D.new()
			bullet_node.add_to_group("transient_effects")
			bullet_node.process_mode = Node.PROCESS_MODE_PAUSABLE
			bullet_node.z_index = 5
			add_child(bullet_node)
			bullet_node.global_position = muzzle_pos
			# 繪製子彈圓點
			var circ := ColorRect.new()
			circ.color = Color(1.0, 0.85, 0.2)
			circ.size = Vector2(10, 10)
			circ.position = Vector2(-5, -5)
			bullet_node.add_child(circ)
			var bdir := muzzle_pos.direction_to(target.global_position)
			bullets.append({
				"node": bullet_node, "type": "turret_rapid",
				"direction": bdir, "speed": 520.0,
				"damage": dmg, "life": 3.0
			})
			# 連射砲改用玩家攻擊音效(hit.wav)，音量降低30%；改用獨立的turret_rapid_hit播放器
			# （沿用同一份音源但不與玩家自己的hit音效共用同一個AudioStreamPlayer），
			# 避免被玩家頻繁的攻擊音效互相搶播蓋掉導致幾乎聽不到聲音。
			_play_turret_sfx_scaled("turret_rapid_hit", node.global_position, 0.7, 0.9 + rng.randf_range(0.0, 0.2), 0.28, 0.08)

		"fish_fire":
			# 火焰砲：扇形區域傷害
			var fire_range: float = _skill_level_value("fish_fire", "range",
				[0, 2, 2.5, 3, 3.5, 4, 4.5], level) * TILE_SIZE
			var fire_dmg: float = damage * (_skill_level_value("fish_fire", "dmg_pct", [0, 60, 60, 60, 60, 60, 60], level) / 100.0) * _hot_damage_mult()
			var fire_dir := Vector2.from_angle(node.rotation)
			var half_angle := deg_to_rad(45.0)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(enemy):
					continue
				var to_enemy := muzzle_pos.direction_to(enemy.global_position)
				var dist := muzzle_pos.distance_to(enemy.global_position)
				if dist <= fire_range and fire_dir.angle_to(to_enemy) <= half_angle:
					enemy.take_damage(fire_dmg)
					_show_damage_number(enemy.global_position, fire_dmg, false)
					_apply_on_hit_skills(enemy, fire_dmg, player.selected_skills, false, false)
			_spawn_fire_spray_effect(muzzle_pos, node.rotation, fire_range)

		"fish_saw":
			# 鋸齒砲：範圍傷害（2.5格），每 0.1 秒觸發一次；音效與範圍視覺播放邏輯改在 _process_turret_visuals 統一管理
			# 傷害改為即時讀取玩家目前攻擊力的百分比（非放置當下的快照），並受黑桃buff影響
			var saw_base_atk: float = float(player.attack_damage)
			if active_poker_buffs.has("spade"):
				saw_base_atk *= 1.0 + _poker_spade_bonus(player.get_skill_level("poker_spade"))
			var saw_range := range_px
			var saw_dmg: float = saw_base_atk * (_skill_level_value("fish_saw", "dmg_pct",
				[0, 10, 20, 30, 40, 50, 60], level) / 100.0) * _hot_damage_mult()
			_damage_area(node.global_position, saw_range, saw_dmg, 9999, player.selected_skills, true, false)

		"fish_missile":
			# 導彈砲：發射追蹤導彈
			var missile_count: int = int(_skill_level_value("fish_missile", "count", [0, 3, 5, 7, 9, 11, 13], level))
			var missile_dmg: float = damage * (_skill_level_value("fish_missile", "dmg_pct", [0, 100, 100, 130, 130, 160, 160], level) / 100.0) * _hot_damage_mult()
			var targets: Array = []
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(enemy) and node.global_position.distance_to(enemy.global_position) <= range_px:
					targets.append(enemy)
			targets.sort_custom(func(a: Node2D, b: Node2D) -> bool:
				return node.global_position.distance_to(a.global_position) \
					 < node.global_position.distance_to(b.global_position)
			)
			for mi in range(mini(missile_count, targets.size())):
				var tgt: Node2D = targets[mi]
				var m_node := Node2D.new()
				m_node.add_to_group("transient_effects")
				m_node.process_mode = Node.PROCESS_MODE_PAUSABLE
				m_node.z_index = 5
				add_child(m_node)
				m_node.global_position = muzzle_pos
				var mcirc := ColorRect.new()
				mcirc.color = Color(1.0, 0.45, 0.1)
				mcirc.size = Vector2(12, 7)
				mcirc.position = Vector2(-6, -3)
				m_node.add_child(mcirc)
				bullets.append({
					"node": m_node, "type": "turret_missile",
					"target": tgt, "speed": 340.0,
					"damage": missile_dmg, "life": 6.0
				})
			_play_turret_sfx("turret_missile", node.global_position)

		"fish_laser":
			# 雷射砲：貫穿直線
			var laser_dmg: float = damage * (_skill_level_value("fish_laser", "dmg_pct", [0, 100, 150, 200, 300, 400, 500], level) / 100.0) * _hot_damage_mult()
			var laser_dir := Vector2.from_angle(node.rotation)
			var laser_end := muzzle_pos + laser_dir * range_px
			var laser_line := Line2D.new()
			laser_line.add_to_group("transient_effects")
			laser_line.width = 18.0 * 4.5
			laser_line.default_color = Color(1.0, 0.2, 0.95, 0.85)
			laser_line.z_index = 6
			laser_line.add_point(muzzle_pos)
			laser_line.add_point(laser_end)
			add_child(laser_line)
			var ltween := create_tween()
			ltween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			ltween.tween_property(laser_line, "modulate:a", 0.0, 0.28)
			ltween.tween_callback(laser_line.queue_free)
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(enemy):
					continue
				var laser_to_enemy: Vector2 = (enemy as Node2D).global_position - muzzle_pos
				var t_proj: float = laser_to_enemy.dot(laser_dir)
				if t_proj < 0.0 or t_proj > range_px:
					continue
				var perp_dist: float = (laser_to_enemy - laser_dir * t_proj).length()
				if perp_dist <= 80.0:
					enemy.take_damage(laser_dmg)
					_show_damage_number(enemy.global_position, laser_dmg, false)
					_apply_on_hit_skills(enemy, laser_dmg, player.selected_skills, false, false)
			_play_turret_sfx_limited("turret_laser", node.global_position, 1.0, 0.55, 0.12)

		"fish_chain":
			# 電流砲台：對最近敵人發射綠色電流，依等級鏈式跳躍
			var chain_target := _nearest_enemy(node.global_position, range_px)
			if chain_target == null:
				return
			var chain_dmg: float = damage * _fish_percent("fish_chain", level) * _hot_damage_mult()
			_fire_chain_turret(muzzle_pos, chain_target, chain_dmg, level)
			# 音效節流：多座電流砲台共用同一個節流閥，播放中或播完後1秒內不再播放新音效
			if _turret_chain_sfx_gate <= 0.0:
				_play_random_turret_sfx(["turret_chain_1", "turret_chain_2", "turret_chain_3"], node.global_position, 0.94 + rng.randf_range(0.0, 0.12), 0.35, 0.12)
				_turret_chain_sfx_gate = 0.35 + 0.12 + 1.0


func _cast_turret_by_index(index: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not _turret_hotkey_map.has(index):
		return
	var skill_id: String = str(_turret_hotkey_map[index])
	var level: int = int(player.selected_skills.get(skill_id, 0))
	if level <= 0:
		return
	if float(skill_cooldowns.get(skill_id, 0.0)) > 0.08:
		_flash_message("冷卻中…")
		return
	skill_cooldowns[skill_id] = 0.0
	# 最大砲台數量（連射砲按等級可放多台）
	var max_count: int = 1
	if skill_id == "fish_rapid":
		max_count = int(_skill_level_value("fish_rapid", "turret_count", [0, 1, 1, 2, 2, 3, 3], level))
	var same_turrets: Array = turrets.filter(func(t: Dictionary) -> bool:
		return str(t.get("skill_id", "")) == skill_id
	)
	# 使用者需求：點擊一次就直接依目前等級的上限數量「一口氣補滿」，不用每台各自點一次；
	# 若已經在上限（例如原本就滿台），維持原本「移除最舊、換一台新的」的行為（等同重新整批換新）。
	if same_turrets.size() >= max_count:
		var oldest: Dictionary = same_turrets[0]
		var onode: Node2D = oldest.get("node") as Node2D
		if is_instance_valid(onode):
			onode.queue_free()
		turrets = turrets.filter(func(t: Dictionary) -> bool:
			return t != oldest
		)
		_spawn_single_turret(skill_id, level, player.global_position)
	else:
		var deficit: int = max_count - same_turrets.size()
		for i in range(deficit):
			var spawn_pos: Vector2 = player.global_position
			if deficit > 1:
				# 一次補滿多台時，以玩家為中心小範圍分散開來，避免多座砲台完全重疊在同一點。
				var angle: float = TAU * float(i) / float(deficit)
				spawn_pos += Vector2(cos(angle), sin(angle)) * 56.0
			_spawn_single_turret(skill_id, level, spawn_pos)
	skill_cooldowns[skill_id] = _skill_cooldown(skill_id, 15.0)
	_update_ui()
	_play_sfx("ui_select", 1.05)


func _spawn_single_turret(skill_id: String, level: int, spawn_pos: Vector2) -> void:
	# 建立砲台 Node
	var node := Node2D.new()
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	node.z_index = 4
	add_child(node)
	node.global_position = spawn_pos
	# 砲台 Sprite：_2 是底座，_1 是槍管；LV1~LV6 外觀不改變
	# 砲台顯示大小固定為玩家角色顯示大小的 1.2 倍
	var turret_scale: float = (PLAYER_DISPLAY_SIZE * TURRET_SIZE_RATIO) / TOWER_SOURCE_TEXTURE_SIZE
	# 砲台原始圖檔的槍管朝下繪製（朝 +Y），但施放邏輯以 rotation=0 代表朝 +X（右）為準，
	# 兩者不一致會導致「砲台攻擊方向和砲管不對齊」，這裡先把 Sprite 局部旋轉 -90 度校正。
	var base_sprite := Sprite2D.new()
	var base_path := _get_tower_part_path(skill_id, 2)
	if base_path != "" and ResourceLoader.exists(base_path):
		base_sprite.texture = load(base_path) as Texture2D
	base_sprite.scale = Vector2(turret_scale, turret_scale)
	base_sprite.rotation = -PI / 2.0
	node.add_child(base_sprite)
	var barrel_sprite := Sprite2D.new()
	barrel_sprite.name = "barrel_sprite"
	var barrel_path := _get_tower_part_path(skill_id, 1)
	if barrel_path != "" and ResourceLoader.exists(barrel_path):
		barrel_sprite.texture = load(barrel_path) as Texture2D
	barrel_sprite.scale = Vector2(turret_scale, turret_scale)
	barrel_sprite.rotation = -PI / 2.0
	node.add_child(barrel_sprite)
	# 砲口標記：置於槍管圖片校正後的朝向邊緣（依砲台縮放比例同步調整位置）
	var muzzle := Node2D.new()
	muzzle.name = "muzzle"
	muzzle.position = Vector2(TOWER_SOURCE_TEXTURE_SIZE * 0.5 * turret_scale, 0.0)
	node.add_child(muzzle)
	# 攻擊間隔
	var interval: float
	var range_tiles: float
	match skill_id:
		"fish_rapid":
			interval = 0.3
			range_tiles = _skill_level_value("fish_rapid", "range", [0, 5, 5, 5.5, 5.5, 6, 6], level)
		"fish_fire":
			interval = 0.2
			range_tiles = _skill_level_value("fish_fire", "range", [0, 2, 2.5, 3, 3.5, 4, 4.5], level)
		"fish_saw":
			interval = 0.1
			range_tiles = _skill_level_value("fish_saw", "range", [0, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5], level)
		"fish_missile":
			interval = 2.0
			range_tiles = _skill_level_value("fish_missile", "range", [0, 8.0, 8.0, 8.0, 8.0, 8.0, 8.0], level)
		"fish_laser":
			interval = 3.0
			range_tiles = _skill_level_value("fish_laser", "range", [0, 10.0, 10.0, 10.0, 10.0, 10.0, 10.0], level)
		"fish_chain":
			interval = 0.5
			range_tiles = _skill_level_value("fish_chain", "range", [0, 6.0, 6.0, 6.0, 6.0, 6.0, 6.0], level)
		_:
			interval = 1.0
			range_tiles = 5.0
	var t_entry: Dictionary = {
		"node": node,
		"skill_id": skill_id,
		"level": level,
		"interval": interval,
		"timer": 0.0,
		"range": range_tiles * TILE_SIZE,
		"damage": float(player.attack_damage),
	}
	if skill_id == "fish_fire":
		t_entry["burst_active"] = true
		t_entry["burst_time_left"] = 5.0
		t_entry["burst_shot_timer"] = 0.0
		t_entry["rest_time_left"] = 0.0
	if skill_id == "fish_saw":
		# 鋸齒砲音效狀態：不隨每 0.1 秒攻擊重複播放，改為完整播完 5 秒素材、淡出後，
		# 若仍在攻擊則等待 1 秒再重播（見 _process_turret_visuals）
		t_entry["saw_sfx_playing"] = false
		t_entry["saw_sfx_time_left"] = 0.0
		t_entry["saw_sfx_wait_left"] = 0.0
		# 鋸齒砲攻擊範圍視覺：攻擊時淡入 0.5 秒顯示 1 次並維持，範圍內 2 秒無敵人後淡出 0.5 秒消失
		var saw_range_indicator := Polygon2D.new()
		saw_range_indicator.name = "saw_range_indicator"
		var saw_pts := PackedVector2Array()
		var saw_r: float = range_tiles * TILE_SIZE
		for i in range(48):
			var sa: float = TAU * float(i) / 48.0
			saw_pts.append(Vector2(cos(sa), sin(sa)) * saw_r)
		saw_range_indicator.polygon = saw_pts
		saw_range_indicator.color = Color(0.6, 0.95, 1.0, 0.0)
		saw_range_indicator.z_index = -1
		node.add_child(saw_range_indicator)
		t_entry["saw_range_node"] = saw_range_indicator
		t_entry["saw_range_visible"] = false
		t_entry["saw_no_target_timer"] = 0.0
	turrets.append(t_entry)
	if skill_id == "fish_fire":
		_play_turret_sfx("turret_fire", node.global_position)
