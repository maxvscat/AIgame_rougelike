extends Node2D

const PlayerScene := preload("res://AIgame_rougelike/scenes/player.tscn")
const EnemyScene := preload("res://AIgame_rougelike/scenes/enemy.tscn")
const SkillSlotScript := preload("res://AIgame_rougelike/scripts/skill_slot.gd")
const SAVE_PATH := "user://save_slots.json"
const SAVE_SLOT_COUNT := 5
const TILE_SIZE := 64.0
const MAX_LEVEL := 30
const MAX_ACTIVE_SKILLS := 5

var rng := RandomNumberGenerator.new()
var player: Node2D
var selected_save_slot := -1
var save_slots: Array = []
var total_chips := 0
var game_started := false
var is_game_ended := false
var current_stage := 1
var kill_count := 0
var stage_enemies_alive := 0
var map_rect := Rect2()
var wall_points := {}
var mage_preview_center := Vector2.ZERO
var mage_preview_radius := 0.0
var mage_preview_visible := false
var bullets := []
var turrets := []
var skill_cooldowns := {}
var magnet_cooldown := 0.0
var active_magnet: Node2D
var active_poker_buffs := {}
var poker_timer := 20.0
var poker_deck := ["heart", "spade", "diamond", "club", "joker", "guard"]
var poker_discard := []

var test_overlay: Control
var _main_menu_input_buffer := ""
var _test_enemy_id := "retail"
var _test_enemy_count := 10
var _test_character_id := "warrior"
var _test_skill_slots: Array = [{"id": "", "lv": 0}, {"id": "", "lv": 0}, {"id": "", "lv": 0}, {"id": "", "lv": 0}, {"id": "", "lv": 0}]
var is_test_mode := false
var sanyuan_hit_counter := 0
var sanyuan_pending := false
var flush_cooldown := 0.0
var sixi_tiles: Array = []
var sixi_orbit_angle := 0.0
var sixi_hit_cds: Dictionary = {}
var moon_projectiles: Array = []
var moon_cooldown := 0.0
var _stage_preview_positions := []
var _stage_previewing := false

var ui_canvas: CanvasLayer
var hud_layer: Control
var heart_label: Label
var stage_label: Label
var level_label: Label
var skill_label: Label
var skill_bar: HBoxContainer
var message_label: Label
var main_menu_overlay: Control
var save_overlay: Control
var lobby_overlay: Control
var character_overlay: Control
var level_up_overlay: Control
var settings_overlay: Control
var game_over_overlay: Control
var result_label: Label

var enemy_defs := {
	"retail":     {"id": "retail",     "name": "散戶",    "hp":   4.0, "attack_type": "melee",  "range": 1.65, "aps": 0.25, "speed":  78.0, "scale": 2.0},
	"friend":     {"id": "friend",     "name": "街友",    "hp":   8.0, "attack_type": "melee",  "range": 2.7,  "aps": 0.5,  "speed":  76.0, "scale": 2.0, "skill": "speed_burst", "skill_cd": 8.0},
	"shooter":    {"id": "shooter",    "name": "射畜",    "hp":  10.0, "attack_type": "ranged", "range": 8.0,  "aps": 0.5,  "speed":  66.0, "scale": 2.0},
	"hoodlum":    {"id": "hoodlum",    "name": "89",      "hp":  12.0, "attack_type": "ranged", "range": 8.0,  "aps": 1.0,  "speed":  70.0, "scale": 2.0, "skill": "summon_retail", "skill_cd": 15.0},
	"aluminum":   {"id": "aluminum",   "name": "鋁布",    "hp":  20.0, "attack_type": "melee",  "range": 2.0,  "aps": 0.5,  "speed": 109.0, "scale": 3.0, "skill": "sweep",         "skill_cd": 5.0},
	"hacker":     {"id": "hacker",     "name": "耗客",    "hp":  50.0, "attack_type": "melee",  "range": 1.3,  "aps": 0.75, "speed": 122.0, "scale": 4.0, "skill": "jump_slash",    "skill_cd": 10.0},
	"patriot":    {"id": "patriot",    "name": "阻國人",  "hp":  80.0, "attack_type": "melee",  "range": 5.0,  "aps": 1.0,  "speed": 112.0, "scale": 2.5, "skill": "laser",         "skill_cd": 7.0},
	"headhunter": {"id": "headhunter", "name": "獵頭",    "hp":  65.0, "attack_type": "melee",  "range": 1.2,  "aps": 1.0,  "speed": 112.0, "scale": 1.5, "skill": "jump_slash",    "skill_cd": 7.0},
	"boss_mid":   {"id": "boss_mid",   "name": "中型Boss","hp": 260.0, "attack_type": "ranged", "range": 8.0,  "aps": 1.0,  "speed":  48.0, "scale": 2.0, "skill": "laser",         "skill_cd": 5.0},
	"boss_final": {"id": "boss_final", "name": "最終Boss","hp": 420.0, "attack_type": "ranged", "range": 8.0,  "aps": 1.2,  "speed":  54.0, "scale": 2.0, "skill": "laser",         "skill_cd": 4.0}
}

var stage_defs := [
	{"retail": 30},
	{"retail": 40},
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	var _font_path := "res://AIgame_rougelike/assets/fonts/MaokenAssortedSans-TC.otf"
	if ResourceLoader.exists(_font_path):
		_game_font = load(_font_path) as Font
	_ensure_input_actions()
	_build_skill_defs()
	_load_save_slots()
	_create_world()
	_create_player()
	_create_ui()
	_show_main_menu()


func _ensure_input_actions() -> void:
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash", 0.5)
	if InputMap.action_get_events("dash").is_empty():
		var dash_key := InputEventKey.new()
		dash_key.keycode = KEY_SPACE
		InputMap.action_add_event("dash", dash_key)
	for index in range(1, 7):
		var action := "turret_%d" % index
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		if InputMap.action_get_events(action).is_empty():
			var key := InputEventKey.new()
			key.keycode = (KEY_0 + index) as Key
			InputMap.action_add_event(action, key)


func _process(delta: float) -> void:
	if not game_started or get_tree().paused or is_game_ended:
		return
	_process_bullets(delta)
	_process_skill_cooldowns(delta)
	_process_turrets(delta)
	_process_poker(delta)
	_process_sixi(delta)
	_process_moon(delta)
	_poker_blink_timer += delta
	queue_redraw()
	_clamp_player_to_map()
	_update_ui()
	if stage_enemies_alive <= 0 and not is_test_mode:
		_finish_stage()


func _process_skill_cooldowns(delta: float) -> void:
	magnet_cooldown = max(magnet_cooldown - delta, 0.0)
	flush_cooldown = max(flush_cooldown - delta, 0.0)
	for skill_id in skill_cooldowns.keys():
		skill_cooldowns[skill_id] = max(float(skill_cooldowns[skill_id]) - delta, 0.0)
	# 清一色自動觸發（CD 5秒，不受攻速影響）
	if flush_cooldown <= 0.0 and player != null and player.get_skill_level("mahjong_flush") > 0 and game_started and not is_game_ended:
		flush_cooldown = 5.0
		skill_cooldowns["mahjong_flush"] = 5.0
		var level: int = player.get_skill_level("mahjong_flush")
		var radius := 4.0 * TILE_SIZE
		var dmg: float = float(player.attack_damage) * float([0, 1.0, 1.3, 1.6, 2.0, 2.5, 3.0][level])
		_spawn_flush_effect(player.global_position)
		_spawn_circle_effect(player.global_position, radius, Color(0.4, 1.0, 0.6, 0.4), 0.18, func() -> void:
			for enemy in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(enemy) and player.global_position.distance_to(enemy.global_position) <= radius:
					enemy.take_damage(dmg)
					_show_damage_number(enemy.global_position, dmg, false)
		)


func _process_turrets(delta: float) -> void:
	_process_turret_visuals(delta)
	for index in range(turrets.size() - 1, -1, -1):
		var turret: Dictionary = turrets[index]
		var node: Node2D = turret["node"]
		if not is_instance_valid(node):
			turrets.remove_at(index)
			continue
		turret["timer"] = float(turret["timer"]) - delta
		if float(turret["timer"]) <= 0.0:
			if _is_turret_aimed(turret):
				_fire_turret(turret)
				turret["timer"] = float(turret["interval"])
			else:
				# 尚未對準，計時器停在負值，對準後立即開火
				turret["timer"] = maxf(float(turret["timer"]), -1.0)
		turrets[index] = turret


func _unhandled_input(event: InputEvent) -> void:
	if game_started and not get_tree().paused and not is_game_ended:
		if event.is_action_pressed("dash") and player != null and player.has_method("request_dash"):
			player.request_dash()
		for index in range(1, 7):
			if event.is_action_pressed("turret_%d" % index):
				_cast_turret_by_index(index)
	if event.is_action_pressed("ui_cancel"):
		if test_overlay != null and test_overlay.visible:
			_hide_all_overlays()
			_return_to_lobby()
			_show_main_menu()
			return
		if game_started and not is_game_ended and get_tree().paused:
			_hide_all_overlays()
			get_tree().paused = false
		elif game_started and not is_game_ended:
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
	if is_game_ended and (event.is_action_pressed("restart") or event.is_action_pressed("ui_accept")):
		_return_to_lobby()
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
		"dice_crit": {"school": "骰子", "name": "致命骰", "desc": "爆擊率 +20%，爆擊傷害隨等級提高。"},
		"dice_execute": {"school": "骰子", "name": "幸運收頭", "desc": "有機率秒殺小怪。"},
		"dice_first": {"school": "骰子", "name": "先手優勢", "desc": "攻擊滿血敵人時提高爆擊率。"},
		"dice_blast": {"school": "骰子", "name": "爆裂骰", "desc": "爆擊時機率造成 2 格爆炸。"},
		"dice_last": {"school": "骰子", "name": "孤注一擲", "desc": "剩 1 顆愛心時，每數次攻擊必爆。"},
		"dice_hot": {"school": "骰子", "name": "賭徒熱手", "desc": "爆擊後短時間提高傷害。"},
		"tech_frost": {"school": "科技", "name": "冷卻", "desc": "攻擊附加冰霜，緩速並機率冰凍。"},
		"tech_fire": {"school": "科技", "name": "過載", "desc": "攻擊附加燃燒。"},
		"tech_poison": {"school": "科技", "name": "病毒", "desc": "攻擊附加毒與緩速，可疊 3 層。"},
		"tech_lightning": {"school": "科技", "name": "高壓電", "desc": "雷電擴散至附近敵人。"},
		"tech_meltdown": {"school": "科技", "name": "熔毀", "desc": "命中後延遲爆炸。"},
		"tech_magnet": {"school": "科技", "name": "磁暴", "desc": "產生磁場吸怪與緩速。"},
		"poker_heart": {"school": "樸克", "name": "命運紅心", "desc": "抽中時提高閃避率。"},
		"poker_spade": {"school": "樸克", "name": "致命黑桃", "desc": "抽中時提高攻擊傷害。"},
		"poker_diamond": {"school": "樸克", "name": "鑽石爆擊", "desc": "抽中時提高爆擊傷害。"},
		"poker_club": {"school": "樸克", "name": "疾風梅花", "desc": "抽中時提高攻速。"},
		"poker_joker": {"school": "樸克", "name": "厄運小丑", "desc": "抽中時使目標受傷提高。"},
		"poker_guard": {"school": "樸克", "name": "皇家護衛", "desc": "抽中時產生護衛牌。"},
		"mahjong_sanyuan": {"school": "麻將", "name": "大三元", "desc": "第三下後下一擊造成 3 格範圍傷害。"},
		"mahjong_sixi": {"school": "麻將", "name": "大四喜", "desc": "麻將牌環繞玩家造成傷害。"},
		"mahjong_pong": {"school": "麻將", "name": "碰碰胡", "desc": "攻擊會額外命中附近敵人。"},
		"mahjong_moon": {"school": "麻將", "name": "海底撈月", "desc": "丟出麻將後回收，傷害路徑敵人。"},
		"mahjong_wall": {"school": "麻將", "name": "門清", "desc": "每隔一段時間抵擋一次傷害。"},
		"mahjong_flush": {"school": "麻將", "name": "清一色", "desc": "每 5 秒對周圍劈砍。"},
		"fish_rapid": {"school": "魚機", "name": "連射砲", "desc": "熱鍵 1，放置連射砲台。"},
		"fish_fire": {"school": "魚機", "name": "火焰砲", "desc": "熱鍵 2，放置火焰砲台。"},
		"fish_saw": {"school": "魚機", "name": "鋸齒砲", "desc": "熱鍵 3，放置鋸齒砲台。"},
		"fish_missile": {"school": "魚機", "name": "導彈砲", "desc": "熱鍵 4，放置導彈砲台。"},
		"fish_laser": {"school": "魚機", "name": "雷射砲", "desc": "熱鍵 5，放置雷射砲台。"},
		"fish_chain": {"school": "魚機", "name": "連鎖砲", "desc": "熱鍵 6，放置連鎖砲台。"}
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


func _create_world() -> void:
	set_process(true)


func _create_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	player.visible = false
	player.stats_changed.connect(_update_ui)
	player.died.connect(_on_player_died)
	player.attack_requested.connect(_on_player_attack_requested)
	player.area_preview_changed.connect(_on_area_preview_changed)
	player.wall_blocked.connect(_on_player_wall_blocked)
	var camera := Camera2D.new()
	camera.position_smoothing_enabled = false
	player.add_child(camera)
	camera.make_current()


func _create_ui() -> void:
	ui_canvas = CanvasLayer.new()
	ui_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_canvas)

	hud_layer = Control.new()
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_canvas.add_child(hud_layer)

	var hud := VBoxContainer.new()
	hud.position = Vector2(18, 14)
	hud.add_theme_constant_override("separation", 6)
	hud_layer.add_child(hud)
	heart_label = Label.new()
	_apply_game_font(heart_label, 26, Color(1.0, 0.12, 0.14), 3)
	hud.add_child(heart_label)
	stage_label = Label.new()
	_apply_game_font(stage_label, 22, Color.WHITE, 2)
	hud.add_child(stage_label)
	level_label = Label.new()
	_apply_game_font(level_label, 22, Color.WHITE, 2)
	hud.add_child(level_label)
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_game_font(message_label, 30, Color.WHITE, 3)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 28
	message_label.offset_bottom = 78
	hud_layer.add_child(message_label)

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
		["開新遊戲", func() -> void: _show_save_slots(true)],
		["讀取存檔", func() -> void: _show_save_slots(false)],
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


func _make_menu(parent: Control, title: String, items: Array, popup_style := false) -> void:
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
		sbox.bg_color = Color(0.06, 0.10, 0.16, 0.96)
		sbox.set_border_width_all(2)
		sbox.border_color = Color(0.45, 0.65, 1.0, 0.85)
		sbox.set_corner_radius_all(10)
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
	_apply_game_font(label, 28, Color.WHITE, 3)
	box.add_child(label)
	for item in items:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(360, 42)
		_apply_game_font(button, 22, Color.WHITE, 2)
		button.pressed.connect(item[1])
		box.add_child(button)


func _show_main_menu() -> void:
	game_started = false
	get_tree().paused = true
	_hide_all_overlays()
	main_menu_overlay.visible = true


func _show_save_slots(_is_new: bool) -> void:
	_hide_all_overlays()
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
	lobby_overlay.visible = true
	_make_menu(lobby_overlay, "大廳｜永久晶片 %d" % total_chips, [
		["開始冒險", _show_character_select],
		["永久研究中心（暫留）", func() -> void: _flash_message("永久研究中心保留，之後接新版本數值。")],
		["返回", _show_main_menu]
	])


func _select_save_slot(index: int) -> void:
	selected_save_slot = index
	total_chips = int(save_slots[index].get("total_chips", 0))
	_show_lobby()


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
			"name": "🏹 弓手",
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
		var cid: String = str(def.get("id", "warrior"))
		btn.pressed.connect(Callable(self, "_start_run").bind(cid))
		hbox.add_child(btn)

	# 返回按鈕
	var sep := HSeparator.new()
	vbox.add_child(sep)
	var back_btn := Button.new()
	back_btn.text = "返回"
	back_btn.custom_minimum_size = Vector2(360, 40)
	back_btn.pressed.connect(_show_lobby)
	vbox.add_child(back_btn)


func _enter_test_mode() -> void:
	_hide_all_overlays()
	is_test_mode = true
	get_tree().paused = false
	game_started = true
	is_game_ended = false
	current_stage = 1
	kill_count = 0
	sanyuan_hit_counter = 0
	bullets.clear()
	active_poker_buffs.clear()
	poker_deck = ["heart", "spade", "diamond", "club", "joker", "guard"]
	poker_discard.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	player.visible = true
	player.setup_character("warrior")
	player.global_position = Vector2.ZERO
	_setup_stage_map()
	_update_ui()
	get_tree().paused = true
	_show_test_overlay()


func _show_test_overlay() -> void:
	get_tree().paused = true
	_hide_all_overlays()
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

	var cnames := {"warrior": "戰士", "archer": "弓手", "mage": "法師"}
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
	_make_menu(settings_overlay, "設定", [
		["音量 / 畫面 / 按鍵：暫用預設", func() -> void: _flash_message("設定頁保留，Dash 已不再使用本版核心。")],
		["返回", _show_main_menu]
	])


func _show_pause() -> void:
	get_tree().paused = true
	if settings_overlay is ColorRect:
		(settings_overlay as ColorRect).color = Color(0.0, 0.0, 0.0, 0.55)
	settings_overlay.visible = true
	_make_menu(settings_overlay, "⏸ 暫停", [
		["繼續遊戲", Callable(self, "_resume_game")],
		["回大廳", _return_to_lobby]
	], true)


func _resume_game() -> void:
	settings_overlay.visible = false
	get_tree().paused = false


func _hide_all_overlays() -> void:
	for overlay in [main_menu_overlay, save_overlay, lobby_overlay, character_overlay, level_up_overlay, settings_overlay, game_over_overlay, test_overlay]:
		if overlay != null:
			overlay.visible = false


func _start_run(character_id: String) -> void:
	_hide_all_overlays()
	is_test_mode = false
	get_tree().paused = false
	game_started = true
	is_game_ended = false
	current_stage = 1
	kill_count = 0
	sanyuan_hit_counter = 0
	sanyuan_pending = false
	flush_cooldown = 5.0
	moon_cooldown = 0.0
	_clear_poker_indicators()
	sixi_orbit_angle = 0.0
	sixi_hit_cds.clear()
	_clear_sixi_tiles()
	_clear_moon_tiles()
	bullets.clear()
	active_poker_buffs.clear()
	poker_deck = ["heart", "spade", "diamond", "club", "joker", "guard"]
	poker_discard.clear()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	player.visible = true
	player.setup_character(character_id)
	player.global_position = Vector2.ZERO
	_setup_stage_map()
	_update_ui()
	_start_stage_with_preview(current_stage)


func _setup_stage_map() -> void:
	var viewport_size := get_viewport_rect().size
	var map_size := viewport_size * 3.0
	map_rect = Rect2(-map_size * 0.5, map_size)
	_generate_wall_points()
	queue_redraw()


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


func _start_stage_with_preview(stage_number: int) -> void:
	# 預先計算怪物種類+位置清單
	var spawn_list := []  # Array of {"id": ..., "pos": ..., "power": ...}
	_stage_preview_positions.clear()
	var stage_def: Dictionary = stage_defs[stage_number - 1]
	var power := float(stage_def.get("power", 1.0))
	for key in stage_def.keys():
		if key == "power":
			continue
		for _i in range(int(stage_def[key])):
			var pos := _random_spawn_position()
			spawn_list.append({"id": str(key), "pos": pos, "power": power})
			_stage_preview_positions.append(pos)
	_stage_previewing = true
	get_tree().paused = true
	_flash_message("第 %d 關" % stage_number)
	queue_redraw()
	# 3秒後正式生成怪物（ignore_pause=true，在暫停中仍計時）
	var timer := get_tree().create_timer(3.0, true, false, true)
	timer.timeout.connect(func() -> void:
		_stage_previewing = false
		_stage_preview_positions.clear()
		queue_redraw()
		get_tree().paused = false
		stage_enemies_alive = 0
		for entry in spawn_list:
			_spawn_wave_enemy(str(entry["id"]), Vector2(entry["pos"]), float(entry["power"]))
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
			_spawn_wave_enemy(str(key), _random_spawn_position(), power)
	_update_ui()


func _spawn_wave_enemy(enemy_id: String, pos: Vector2, power := 1.0) -> void:
	var enemy := EnemyScene.instantiate()
	add_child(enemy)
	var def: Dictionary = enemy_defs[enemy_id]
	enemy.setup(def, player, power)
	enemy.global_position = pos
	enemy.died.connect(_on_enemy_died)
	enemy.attack_projectile_requested.connect(_spawn_enemy_bullet)
	enemy.dot_damage_occurred.connect(func(pos: Vector2, amount: float) -> void:
		_show_damage_number(pos, amount, false)
	)
	stage_enemies_alive += 1


func _random_spawn_position() -> Vector2:
	var margin := 80.0
	return Vector2(
		rng.randf_range(map_rect.position.x + margin, map_rect.end.x - margin),
		rng.randf_range(map_rect.position.y + margin, map_rect.end.y - margin)
	)


func _on_enemy_died(_enemy: Node2D) -> void:
	stage_enemies_alive = max(stage_enemies_alive - 1, 0)
	kill_count += 1
	_update_ui()


func _finish_stage() -> void:
	if is_game_ended:
		return
	if current_stage >= 30:
		_end_game(true)
		return
	get_tree().paused = true
	player.level = min(MAX_LEVEL, current_stage + 1)
	_show_level_up_choices()


func _show_level_up_choices() -> void:
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
		var def: Dictionary = skill_defs[skill_id]
		var current: int = player.get_skill_level(skill_id)
		var next: int = current + 1
		items.append(["%s｜%s LV%d -> LV%d\n%s" % [def["school"], def["name"], current, next, def["desc"]], Callable(self, "_choose_level_skill").bind(skill_id)])
	_make_menu(level_up_overlay, "LV UP！選擇 1 個技能", items)


func _choose_level_skill(skill_id: String) -> void:
	player.grant_skill(skill_id)
	_go_next_stage()


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
	sanyuan_hit_counter += 1
	if player != null and player.get_skill_level("mahjong_sanyuan") > 0 and sanyuan_hit_counter % 3 == 0:
		sanyuan_pending = true

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
			_draw_attack_line(
				origin,
				target.global_position,
				Color(0.65, 0.9, 1.0, 0.8)
			)

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
		var angle_difference: float = absf(
	attack_direction.angle_to(enemy_direction)
		)

		if angle_difference <= half_angle:
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
	if skills.has("dice_crit"):
		crit_rate += 0.20
	if skills.has("dice_first") and abs(float(enemy.health) - float(enemy.max_health)) < 0.01:
		crit_rate += 0.10 * float(skills["dice_first"])
	var is_crit := rng.randf() < crit_rate
	if skills.has("dice_last") and player.health == 1:
		is_crit = true
	if skills.has("dice_execute") and not str(enemy.enemy_id).begins_with("boss") and rng.randf() < 0.10 * float(skills["dice_execute"]):
		damage = max(damage, float(enemy.health))
	if is_crit:
		var crit_mult: float = max(2.0, float(skills.get("dice_crit", 1)))
		if active_poker_buffs.has("diamond"):
			crit_mult += _poker_diamond_bonus(player.get_skill_level("poker_diamond"))
		damage *= crit_mult
		if skills.has("dice_blast") and rng.randf() < 0.10 * float(skills["dice_blast"]):
			_damage_area(enemy.global_position, 2.0 * TILE_SIZE, damage * 0.30)
		if skills.has("dice_hot"):
			active_poker_buffs["hot"] = {"timer": 3.0, "bonus": 0.10 * float(skills["dice_hot"])}
	if active_poker_buffs.has("hot"):
		damage *= 1.0 + float(active_poker_buffs["hot"]["bonus"])
	enemy.take_damage(damage)
	# 擊退效果（戰士1格、弓手0.3格、法師無）
	if is_instance_valid(player) and is_instance_valid(enemy) and enemy.has_method("apply_knockback"):
		var kb_tiles := 0.0
		match str(player.class_id):
			"warrior": kb_tiles = 0.5
			"archer": kb_tiles = 0.3
		if kb_tiles > 0.0:
			var kb_dir := (enemy.global_position - player.global_position).normalized()
			if kb_dir.length_squared() <= 0.001:
				kb_dir = Vector2.RIGHT
			enemy.apply_knockback(kb_dir, kb_tiles * TILE_SIZE)
	_show_damage_number(enemy.global_position, damage, is_crit)
	_apply_on_hit_skills(enemy, damage, skills)
	_apply_mahjong_skills(enemy, damage, skills)


func _apply_turret_hit(enemy: Node2D, damage: float) -> void:
	if player == null or not is_instance_valid(enemy):
		return
	_apply_on_hit_skills(enemy, damage, player.selected_skills)


func _apply_on_hit_skills(enemy: Node2D, base_damage: float, skills: Dictionary) -> void:
	if skills.has("tech_frost"):
		var level: int = int(skills["tech_frost"])
		enemy.apply_slow(0.70, 2.0)
		if rng.randf() < 0.10:
			enemy.apply_slow(0.02, 2.0)
		enemy.take_damage(base_damage * [0, .2, .35, .5, .65, .8, 1.0][level])
	if skills.has("tech_fire"):
		enemy.apply_burn(base_damage * [0, .2, .3, .4, .5, .6, .7][int(skills["tech_fire"])], 4.0)
	if skills.has("tech_poison"):
		enemy.apply_poison(base_damage * [0, .1, .15, .2, .25, .3, .35][int(skills["tech_poison"])], 4.0)
	if skills.has("tech_lightning"):
		_damage_area(enemy.global_position, 1.0 * TILE_SIZE, base_damage * [0, .15, .25, .35, .45, .55, .65][int(skills["tech_lightning"])], 3)
	if skills.has("tech_meltdown"):
		var level: int = int(skills["tech_meltdown"])
		_spawn_circle_effect(enemy.global_position, 2.0 * TILE_SIZE, Color(1, 0.45, 0.05, 0.35), 1.0, func() -> void:
			_damage_area(enemy.global_position, 2.0 * TILE_SIZE, base_damage * [0, .1, .2, .3, .4, .5, .6][level])
		)
	if skills.has("tech_magnet") and magnet_cooldown <= 0.0:
		_trigger_magnet(enemy.global_position, base_damage, int(skills["tech_magnet"]))


func _trigger_magnet(center: Vector2, base_damage: float, level: int) -> void:
	level = clamp(level, 1, 6)
	if is_instance_valid(active_magnet):
		active_magnet.queue_free()
	var radius: float = float([0, 2, 2.5, 3, 3.5, 4, 5][level]) * TILE_SIZE
	var damage: float = base_damage * float([0, .2, .3, .4, .5, .6, .7][level])
	active_magnet = Node2D.new()
	active_magnet.global_position = center
	add_child(active_magnet)
	_spawn_circle_effect(center, radius, Color(0.35, 0.9, 1.0, 0.24), 2.0, func() -> void: pass)
	magnet_cooldown = 5.0
	skill_cooldowns["tech_magnet"] = 5.0
	for other in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(other) or other.global_position.distance_to(center) > radius:
			continue
		if str(other.enemy_id).begins_with("boss"):
			other.apply_slow(0.5, 2.0)
		else:
			other.apply_slow(0.4, 2.0)
			other.global_position = other.global_position.move_toward(center, radius)
		other.take_damage(damage)
	var timer := get_tree().create_timer(2.0, true, false, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(active_magnet):
			active_magnet.queue_free()
	)


func _apply_mahjong_skills(enemy: Node2D, base_damage: float, skills: Dictionary) -> void:
	# 碰碰胡：打中附近N個「其他」敵人（不含原目標），N=等級
	if skills.has("mahjong_pong"):
		var level: int = int(skills["mahjong_pong"])
		var pong_radius := 2.0 * TILE_SIZE
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
		for i in range(mini(level, nearby.size())):
			var other: Node2D = nearby[i]
			other.take_damage(base_damage)
			_show_damage_number(other.global_position, base_damage, false)
			_spawn_pong_chain_effect(enemy.global_position, other.global_position)

	# 大三元：每攻擊週期只觸發一次（第3擊時由 attack_requested 設 pending）
	if skills.has("mahjong_sanyuan") and sanyuan_pending:
		sanyuan_pending = false
		var level: int = int(skills["mahjong_sanyuan"])
		var san_dmg: float = base_damage * float([0, 1.0, 1.3, 1.6, 2.0, 2.5, 3.0][level])
		var san_center: Vector2 = enemy.global_position
		_spawn_sanyuan_effect(san_center)
		get_tree().create_timer(0.25, true, false, true).timeout.connect(func() -> void:
			_damage_area(san_center, 3.0 * TILE_SIZE, san_dmg)
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
		if ResourceLoader.exists(tile_paths[idx]):
			sprite.texture = load(tile_paths[idx])
		add_child(sprite)
		sixi_tiles.append(sprite)
	var orbit_speed: float = float([0, 1.2, 1.4, 1.6, 1.9, 2.2, 2.6][level])
	sixi_orbit_angle = fmod(sixi_orbit_angle + orbit_speed * delta, TAU)
	var orbit_radius := 2.0 * TILE_SIZE
	var dmg: float = float(player.attack_damage) * float([0, 0.5, 0.65, 0.8, 1.0, 1.25, 1.5][level])
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
	if moon_cooldown <= 0.0 and moon_projectiles.size() < 2:
		var cd: float = float([0, 4.0, 3.5, 3.0, 2.5, 2.0, 1.5][level])
		moon_cooldown = cd
		_launch_moon_tile(level)
	# 更新飛行磁磚
	for i in range(moon_projectiles.size() - 1, -1, -1):
		var proj: Dictionary = moon_projectiles[i]
		var node = proj.get("node")
		if not is_instance_valid(node):
			moon_projectiles.remove_at(i)
			continue
		var state: String = str(proj.get("state", "fly_out"))
		var dmg: float = float(proj.get("dmg", 0.0))
		var spd := 290.0
		match state:
			"fly_out":
				var tgt: Vector2 = proj["target"]
				var to_tgt: Vector2 = tgt - node.global_position
				if to_tgt.length() <= spd * delta:
					node.global_position = tgt
					proj["state"] = "hover"
					proj["timer"] = 1.5
				else:
					node.global_position += to_tgt.normalized() * spd * delta
				_moon_hit_check(proj, node.global_position, dmg)
			"hover":
				_moon_hit_check(proj, node.global_position, dmg)
				proj["timer"] = float(proj.get("timer", 0.0)) - delta
				if float(proj.get("timer", 0.0)) <= 0.0:
					proj["state"] = "return"
					proj["timer"] = 8.0
					proj["hit_record"] = []
			"return":
				if not is_instance_valid(player) or float(proj.get("timer", 0.0)) <= 0.0:
					node.queue_free()
					moon_projectiles.remove_at(i)
					continue
				var to_player: Vector2 = player.global_position - node.global_position
				if to_player.length() <= spd * delta:
					node.queue_free()
					moon_projectiles.remove_at(i)
					continue
				node.global_position += to_player.normalized() * spd * delta
				proj["timer"] = float(proj.get("timer", 0.0)) - delta
				_moon_hit_check(proj, node.global_position, dmg)


func _moon_hit_check(proj: Dictionary, pos: Vector2, dmg: float) -> void:
	var hit_record: Array = proj.get("hit_record", [])
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var eid: int = int(enemy.get_instance_id())
		if hit_record.has(eid):
			continue
		if pos.distance_to(enemy.global_position) <= 36.0:
			enemy.take_damage(dmg)
			_show_damage_number(enemy.global_position, dmg, false)
			hit_record.append(eid)


func _launch_moon_tile(level: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dmg: float = float(player.attack_damage) * float([0, 0.8, 1.0, 1.3, 1.5, 1.8, 2.2][level])
	var target_pos: Vector2 = player.global_position + player._last_move_direction * 4.0 * TILE_SIZE
	var nearest_dist := 8.0 * TILE_SIZE
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = player.global_position.distance_to(enemy.global_position)
		if d < nearest_dist:
			nearest_dist = d
			target_pos = enemy.global_position
	var node := Sprite2D.new()
	var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/moon_tile.png"
	if ResourceLoader.exists(tex_path):
		node.texture = load(tex_path)
	node.global_position = player.global_position
	add_child(node)
	moon_projectiles.append({
		"node": node,
		"state": "fly_out",
		"timer": 5.0,
		"target": target_pos,
		"dmg": dmg,
		"hit_record": []
	})


func _clear_moon_tiles() -> void:
	for proj in moon_projectiles:
		var node = proj.get("node")
		if is_instance_valid(node):
			node.queue_free()
	moon_projectiles.clear()


func _spawn_sanyuan_effect(pos: Vector2) -> void:
	_spawn_circle_effect(pos, 3.0 * TILE_SIZE, Color(1.0, 0.5, 0.1, 0.45), 0.1, func() -> void: pass)
	var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/sanyuan_fx.png"
	if not ResourceLoader.exists(tex_path):
		return
	var sprite := Sprite2D.new()
	sprite.texture = load(tex_path)
	sprite.global_position = pos
	sprite.scale = Vector2(2.0, 2.0)
	add_child(sprite)
	var tween := create_tween()
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
	sprite.texture = load(tex_path)
	sprite.global_position = pos
	sprite.scale = Vector2(1.5, 1.5)
	add_child(sprite)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(2.5, 2.5), 0.5)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _spawn_flush_effect(pos: Vector2) -> void:
	var tex_path := "res://AIgame_rougelike/assets/art/skills/mahjong/flush_fx.png"
	if not ResourceLoader.exists(tex_path):
		return
	var sprite := Sprite2D.new()
	sprite.texture = load(tex_path)
	sprite.global_position = pos
	sprite.scale = Vector2(2.5, 2.5)
	add_child(sprite)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(4.0, 4.0), 0.4)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


func _on_player_wall_blocked(pos: Vector2) -> void:
	_spawn_wall_block_effect(pos)


func _damage_area(center: Vector2, radius: float, amount: float, limit := 9999) -> void:
	var hit := 0
	_spawn_circle_effect(center, radius, Color(1.0, 0.75, 0.2, 0.18), 0.05, func() -> void: pass)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if hit >= limit:
			return
		if is_instance_valid(enemy) and center.distance_to(enemy.global_position) <= radius:
			enemy.take_damage(amount)
			hit += 1



func _spawn_enemy_bullet(origin: Vector2, target_position: Vector2, bullet_speed: float) -> void:
	var node := Node2D.new()
	node.position = origin
	add_child(node)
	bullets.append({
		"node": node,
		"velocity": origin.direction_to(target_position) * bullet_speed,
		"radius": 9.0,
		"life": 8.0
	})



func _cast_turret_by_index(index: int) -> void:
	var ids := ["fish_rapid", "fish_fire", "fish_saw", "fish_missile", "fish_laser", "fish_chain"]
	if index < 1 or index > ids.size():
		return
	_cast_turret_skill(ids[index - 1])



func _cast_turret_skill(skill_id: String) -> void:
	if player == null or player.get_skill_level(skill_id) <= 0:
		_flash_message("尚未取得砲台技能")
		return
	if float(skill_cooldowns.get(skill_id, 0.0)) > 0.0:
		return
	var level: int = player.get_skill_level(skill_id)
	var max_count := 1
	if skill_id == "fish_rapid":
		if level < 3:
			max_count = 1
		elif level < 5:
			max_count = 2
		else:
			max_count = 3
		_remove_oldest_turret(skill_id, max_count - 1)
	else:
		_remove_oldest_turret(skill_id, 0)
	var node: Node2D = Node2D.new()
	node.global_position = player.global_position
	add_child(node)
	# ── 建立視覺節點 ──
	var vis: Dictionary = _create_turret_visual(skill_id)
	var base_sprite: Sprite2D = vis["base"] as Sprite2D
	var head: Node2D = vis["head"] as Node2D
	node.add_child(base_sprite)
	node.add_child(head)
	turrets.append({
		"node": node,
		"head": head,
		"skill_id": skill_id,
		"level": level,
		"timer": 0.0,
		"interval": _turret_interval(skill_id)
	})
	skill_cooldowns[skill_id] = 8.0
	_flash_message("%s 施放" % skill_defs[skill_id]["name"])



func _remove_oldest_turret(skill_id: String, keep_count: int) -> void:
	var same := []
	for turret in turrets:
		if str(turret.get("skill_id", "")) == skill_id:
			same.append(turret)
	while same.size() > keep_count:
		var turret: Dictionary = same.pop_front()
		var node: Node2D = turret.get("node")
		if is_instance_valid(node):
			node.queue_free()
		turrets.erase(turret)



func _turret_interval(skill_id: String) -> float:
	match skill_id:
		"fish_fire", "fish_missile":
			return 2.0
		"fish_laser":
			return 3.0
		"fish_saw":
			return 1.0
		_:
			return 0.5



func _fire_turret(turret: Dictionary) -> void:
	var node: Node2D = turret["node"]
	if not is_instance_valid(node):
		return
	var skill_id: String = str(turret["skill_id"])
	var level: int = int(turret["level"])
	var muzzle_pos: Vector2 = _get_turret_muzzle(turret)
	match skill_id:
		"fish_fire":
			# 火焰塔：以砲台中心為圓心做區域傷害
			_damage_area(node.global_position, 2.0 * TILE_SIZE, _fish_percent(skill_id, level), 9999)
		"fish_saw":
			# 鋸齒塔：以砲台中心為圓心做區域傷害
			_damage_area(node.global_position, 1.6 * TILE_SIZE, _fish_percent(skill_id, level), 9999)
		"fish_missile":
			var count: int = int([0, 1, 2, 2, 3, 4, 5][level])
			for _i in range(count):
				var target: Node2D = _nearest_enemy(node.global_position, 3.0 * TILE_SIZE)
				if target != null:
					target.take_damage(_fish_percent(skill_id, level))
					_draw_attack_line(muzzle_pos, target.global_position, Color(1.0, 0.5, 0.12, 0.85))
		"fish_laser":
			var target: Node2D = _nearest_enemy(node.global_position, 6.0 * TILE_SIZE)
			if target != null:
				var laser_end: Vector2 = muzzle_pos + muzzle_pos.direction_to(target.global_position) * 6.0 * TILE_SIZE
				_draw_attack_line(muzzle_pos, laser_end, Color(0.2, 0.9, 1.0, 0.9))
				for enemy in get_tree().get_nodes_in_group("enemies"):
					if is_instance_valid(enemy) and _distance_to_segment(enemy.global_position, muzzle_pos, laser_end) <= 24.0:
						enemy.take_damage(_fish_percent(skill_id, level))
		"fish_chain":
			var target: Node2D = _nearest_enemy(node.global_position, 6.0 * TILE_SIZE)
			var hit: Array = []
			var bounces: int = level
			while target != null and bounces > 0:
				target.take_damage(_fish_percent(skill_id, level))
				_draw_attack_line(muzzle_pos, target.global_position, Color(0.55, 0.9, 1.0, 0.75))
				hit.append(target)
				target = _nearest_enemy(target.global_position, 3.0 * TILE_SIZE, hit)
				bounces -= 1
		_:
			var target: Node2D = _nearest_enemy(node.global_position, 6.0 * TILE_SIZE)
			if target != null:
				target.take_damage(_fish_percent(skill_id, level))
				_draw_attack_line(muzzle_pos, target.global_position, Color(0.8, 1.0, 0.55, 0.75))



func _fish_percent(skill_id: String, level: int) -> float:
	match skill_id:
		"fish_rapid":
			return [0, 1.0, 1.3, 1.3, 1.6, 1.6, 2.0][level]
		"fish_fire":
			return [0, .3, .45, .6, .8, 1.0, 1.3][level]
		"fish_saw":
			return [0, .5, 1.0, 1.5, 2.0, 2.5, 3.0][level]
		"fish_missile":
			return [0, 1.0, 1.0, 1.3, 1.3, 1.6, 1.6][level]
		"fish_laser":
			return [0, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0][level]
		"fish_chain":
			return [0, .7, .7, .8, .9, 1.0, 1.2][level]
	return 1.0



func _nearest_enemy(origin: Vector2, max_distance: float, ignored := []) -> Node2D:
	var best: Node2D
	var best_distance := max_distance
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or ignored.has(enemy):
			continue
		var distance := origin.distance_to(enemy.global_position)
		if distance <= best_distance:
			best = enemy
			best_distance = distance
	return best



func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_sq := segment.length_squared()
	if length_sq <= 0.001:
		return point.distance_to(start)
	var t: float = clamp((point - start).dot(segment) / length_sq, 0.0, 1.0)
	return point.distance_to(start + segment * t)



func _process_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[i]
		var node: Node2D = bullet["node"]
		if not is_instance_valid(node):
			bullets.remove_at(i)
			continue
		node.global_position += Vector2(bullet["velocity"]) * delta
		bullet["life"] = float(bullet["life"]) - delta
		if is_instance_valid(player) and node.global_position.distance_to(player.global_position) <= float(bullet["radius"]) + 16.0:
			player.take_damage(1)
			node.queue_free()
			bullets.remove_at(i)
			continue
		if float(bullet["life"]) <= 0.0 or not map_rect.has_point(node.global_position):
			node.queue_free()
			bullets.remove_at(i)
		else:
			bullets[i] = bullet
	queue_redraw()



func _build_poker_deck() -> Array:
	# 只把玩家實際持有的樸克技能對應的牌加入牌組
	const CARD_TO_SKILL: Dictionary = {
		"heart": "poker_heart", "spade": "poker_spade", "diamond": "poker_diamond",
		"club": "poker_club", "joker": "poker_joker", "guard": "poker_guard",
	}
	var deck: Array = []
	for card in CARD_TO_SKILL:
		if player.get_skill_level(CARD_TO_SKILL[card]) > 0:
			deck.append(card)
	return deck


func _process_poker(delta: float) -> void:
	for key in active_poker_buffs.keys():
		var buff: Dictionary = active_poker_buffs[key]
		buff["timer"] = float(buff["timer"]) - delta
		if float(buff["timer"]) <= 0.0:
			active_poker_buffs.erase(key)
			_sync_poker_indicator()
		else:
			active_poker_buffs[key] = buff
	if not _has_poker_skill():
		return
	poker_timer -= delta
	if poker_timer > 0.0:
		return
	poker_timer = 20.0
	# 從玩家持有技能動態建立牌組，棄牌堆裡沒有的才放入
	var owned: Array = _build_poker_deck()
	if poker_deck.is_empty():
		# 重洗：只保留玩家有的牌
		poker_deck = owned.duplicate()
		poker_discard.clear()
	else:
		# 如果玩家新取得某張牌且不在牌組/棄牌堆中，補入牌組
		for card in owned:
			if not poker_deck.has(card) and not poker_discard.has(card):
				poker_deck.append(card)
	# 若最終牌組仍為空（玩家一張樸克牌都沒有），跳過
	if poker_deck.is_empty():
		return
	var card = poker_deck.pop_at(rng.randi_range(0, poker_deck.size() - 1))
	poker_discard.append(card)
	active_poker_buffs[card] = {"timer": 15.0}
	_flash_message("抽牌：" + str(card))
	_sync_poker_indicator()



func _has_poker_skill() -> bool:
	for skill_id in player.selected_skills.keys():
		if str(skill_id).begins_with("poker_"):
			return true
	return false



func _poker_spade_bonus(level: int) -> float:
	return [0, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5][level]



func _poker_diamond_bonus(level: int) -> float:
	return [0, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0][level]



func _spawn_circle_effect(center: Vector2, radius: float, color: Color, delay: float, callback: Callable) -> void:
	var ring := Line2D.new()
	ring.closed = true
	ring.width = 4.0
	ring.default_color = color
	var points := PackedVector2Array()
	for i in range(72):
		points.append(center + Vector2(cos(TAU * i / 72.0), sin(TAU * i / 72.0)) * radius)
	ring.points = points
	add_child(ring)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		if callback.is_valid():
			callback.call()
		if is_instance_valid(ring):
			ring.queue_free()
	)



func _draw_attack_line(start: Vector2, end: Vector2, color: Color) -> void:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = color
	line.points = PackedVector2Array([start, end])
	add_child(line)
	var tween := create_tween()
	tween.tween_interval(0.08)
	tween.tween_callback(func() -> void:
		if is_instance_valid(line):
			line.queue_free()
	)



func _on_area_preview_changed(center: Vector2, radius: float, visible: bool) -> void:
	mage_preview_center = center
	mage_preview_radius = radius
	mage_preview_visible = visible
	queue_redraw()



func _clamp_player_to_map() -> void:
	if player == null:
		return
	player.global_position.x = clamp(player.global_position.x, map_rect.position.x + 18.0, map_rect.end.x - 18.0)
	player.global_position.y = clamp(player.global_position.y, map_rect.position.y + 18.0, map_rect.end.y - 18.0)



func _on_player_died() -> void:
	_end_game(false)



func _end_game(win: bool) -> void:
	is_game_ended = true
	game_started = false
	get_tree().paused = true
	_hide_all_overlays()
	if game_over_overlay is ColorRect:
		(game_over_overlay as ColorRect).color = Color(0.02, 0.04, 0.07, 0.5)
	game_over_overlay.visible = true
	var title := "通關成功" if win else "遊戲失敗"
	_make_menu(game_over_overlay, "%s\n清到第 %d 關\n擊殺 %d 人" % [title, current_stage, kill_count], [
		["返回大廳", _return_to_lobby]
	], true)



func _return_to_lobby() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for bullet in bullets:
		var node: Node2D = bullet.get("node")
		if is_instance_valid(node):
			node.queue_free()
	bullets.clear()
	for turret in turrets:
		var turret_node: Node2D = turret.get("node")
		if is_instance_valid(turret_node):
			turret_node.queue_free()
	turrets.clear()
	if is_instance_valid(active_magnet):
		active_magnet.queue_free()
	player.visible = false
	game_started = false
	is_game_ended = false
	get_tree().paused = true
	_show_lobby()



func _update_ui() -> void:
	if heart_label == null or player == null:
		return
	var hearts := ""
	for i in range(player.max_health):
		hearts += "♥" if i < player.health else "♡"
	heart_label.text = hearts
	stage_label.text = "關卡：%d / 30　剩餘敵人：%d" % [current_stage, stage_enemies_alive]
	level_label.text = "等級：%d / 30　角色：%s" % [player.level, player.character_name]
	_update_skill_bar()
	return
	var lines := []
	for skill_id in player.selected_skills.keys():
		var def: Dictionary = skill_defs.get(skill_id, {})
		lines.append("%s %s LV%d" % [def.get("school", ""), def.get("name", skill_id), player.get_skill_level(skill_id)])
	skill_label.text = "技能：無" if lines.is_empty() else "技能：\n" + "\n".join(lines)



func _update_skill_bar() -> void:
	if skill_bar == null or player == null:
		return
	for child in skill_bar.get_children():
		child.queue_free()
	for skill_id in player.selected_skills.keys():
		var def: Dictionary = skill_defs.get(skill_id, {})
		var icon: Texture2D
		var icon_path := str(skill_icon_paths.get(skill_id, ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon = load(icon_path)
		var slot := SkillSlotScript.new()
		slot.setup({
			"id": skill_id,
			"name": str(def.get("name", skill_id)),
			"level": player.get_skill_level(skill_id),
			"icon": icon,
			"cooldown": _skill_current_cooldown(skill_id),
			"max_cooldown": _skill_max_cooldown(skill_id),
			"is_turret": str(skill_id).begins_with("fish_")
		})
		slot.activated.connect(_cast_turret_skill)
		skill_bar.add_child(slot)



func _skill_current_cooldown(skill_id: String) -> float:
	if skill_id == "tech_magnet":
		return magnet_cooldown
	return float(skill_cooldowns.get(skill_id, 0.0))



func _skill_max_cooldown(skill_id: String) -> float:
	if skill_id == "tech_magnet":
		return 5.0
	if str(skill_id).begins_with("fish_"):
		return 8.0
	return 0.0



func _flash_message(text: String) -> void:
	if message_label == null:
		return
	message_label.text = text
	message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(1.6)
	tween.tween_property(message_label, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void:
		message_label.text = ""
		message_label.modulate.a = 1.0
	)



func _load_save_slots() -> void:
	save_slots.clear()
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			save_slots = parsed
	while save_slots.size() < SAVE_SLOT_COUNT:
		save_slots.append({"total_chips": 0, "last_played": "無"})



func _draw() -> void:
	if game_started:
		draw_rect(map_rect, Color(0.03, 0.05, 0.07), true)
		for points in wall_points.values():
			var wall_line: PackedVector2Array = points
			draw_polyline(wall_line, Color.WHITE, 3.0)
		for x in range(int(map_rect.position.x), int(map_rect.end.x), int(TILE_SIZE)):
			draw_line(Vector2(x, map_rect.position.y), Vector2(x, map_rect.end.y), Color(0.15, 0.25, 0.30, 0.4), 1.0)
		for y in range(int(map_rect.position.y), int(map_rect.end.y), int(TILE_SIZE)):
			draw_line(Vector2(map_rect.position.x, y), Vector2(map_rect.end.x, y), Color(0.15, 0.25, 0.30, 0.4), 1.0)
		if mage_preview_visible:
			draw_circle(mage_preview_center, mage_preview_radius, Color(1, 1, 1, 0.18))
			draw_arc(mage_preview_center, mage_preview_radius, 0, TAU, 72, Color(1, 1, 1, 0.5), 3.0)
	for bullet in bullets:
		var node: Node2D = bullet.get("node")
		if is_instance_valid(node):
			draw_circle(node.global_position, 8.0, Color(1.0, 0.35, 0.15))
	_draw_poker_indicator()


func _show_damage_number(pos: Vector2, amount: float, is_crit: bool) -> void:
	var lbl := Label.new()
	lbl.text = ("★%d!" % int(amount)) if is_crit else ("%d" % int(amount))
	var dmg_color: Color = Color(1.0, 0.9, 0.0) if is_crit else Color(1.0, 1.0, 1.0)
	_apply_game_font(lbl, 37 if is_crit else 27, dmg_color, 4)
	lbl.position = pos + Vector2(rng.randf_range(-18.0, 18.0), -40.0)
	add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 44.0, 0.75)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.75)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(lbl):
			lbl.queue_free()
	)


# ══════════════════════════════════════════════════════
#  砲台視覺系統
# ══════════════════════════════════════════════════════


func _apply_game_font(node: Control, size: int, color: Color, outline: int) -> void:
	if _game_font != null:
		node.add_theme_font_override("font", _game_font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_outline_color", Color.BLACK)
	node.add_theme_constant_override("outline_size", outline)


func _get_turret_number(skill_id: String) -> int:
	match skill_id:
		"fish_rapid":   return 1
		"fish_fire":    return 2
		"fish_saw":     return 3
		"fish_missile": return 4
		"fish_laser":   return 5
		"fish_chain":   return 6
	return 1


func _get_turret_texture_path(number: int, part: int) -> String:
	return "res://AIgame_rougelike/assets/art/skills/tower/tower_%d_%d.png" % [number, part]


func _fit_sprite_to_size(sprite: Sprite2D, target_size: float) -> void:
	var texture: Texture2D = sprite.texture
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	var longest_side: float = maxf(texture_size.x, texture_size.y)
	if longest_side <= 0.0:
		return
	var scale_value: float = target_size / longest_side
	sprite.scale = Vector2(scale_value, scale_value)


func _create_turret_visual(skill_id: String) -> Dictionary:
	var number: int = _get_turret_number(skill_id)

	# ── 底座 ──
	var base_sprite: Sprite2D = Sprite2D.new()
	base_sprite.name = "Base"
	base_sprite.centered = true
	var base_path: String = _get_turret_texture_path(number, 2)
	if ResourceLoader.exists(base_path):
		var base_tex: Texture2D = load(base_path) as Texture2D
		base_sprite.texture = base_tex
		_fit_sprite_to_size(base_sprite, 128.0)

	# ── 上半部 Head ──
	var head: Node2D = Node2D.new()
	head.name = "Head"

	var head_sprite: Sprite2D = Sprite2D.new()
	head_sprite.name = "Sprite"
	head_sprite.centered = true
	var head_path: String = _get_turret_texture_path(number, 1)
	if ResourceLoader.exists(head_path):
		var head_tex: Texture2D = load(head_path) as Texture2D
		head_sprite.texture = head_tex
		_fit_sprite_to_size(head_sprite, 128.0)
	head.add_child(head_sprite)

	# ── Muzzle：砲口朝下（+Y），偏移到砲管端點 ──
	var muzzle: Marker2D = Marker2D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector2(0.0, 24.0)
	head.add_child(muzzle)

	return {"base": base_sprite, "head": head}


func _get_turret_muzzle(turret: Dictionary) -> Vector2:
	var node: Node2D = turret.get("node")
	if not is_instance_valid(node):
		return Vector2.ZERO
	var head: Node2D = turret.get("head")
	if is_instance_valid(head):
		var muzzle: Node = head.get_node_or_null("Muzzle")
		if muzzle != null:
			return (muzzle as Node2D).global_position
	return node.global_position


func _is_turret_aimed(turret: Dictionary) -> bool:
	var skill_id: String = str(turret.get("skill_id", ""))
	# 區域攻擊 / 無需瞄準的砲台
	if skill_id in ["fish_saw", "fish_fire", "fish_chain"]:
		return true
	var node: Node2D = turret.get("node")
	if not is_instance_valid(node):
		return true
	var head: Node2D = turret.get("head")
	if not is_instance_valid(head):
		return true
	var target: Node2D = _nearest_enemy(node.global_position, 6.0 * TILE_SIZE)
	if target == null:
		return true
	var dir: Vector2 = node.global_position.direction_to(target.global_position)
	# 砲口朝下 = 原始角度 PI/2；瞄準補正 -PI/2
	var target_angle: float = dir.angle() - PI * 0.5
	var diff: float = absf(angle_difference(head.rotation, target_angle))
	return diff < deg_to_rad(8.0)


func _process_turret_visuals(delta: float) -> void:
	var turn_speeds: Dictionary = {
		"fish_rapid":   5.0,
		"fish_fire":    2.5,
		"fish_missile": 3.0,
		"fish_laser":   4.5,
	}
	for turret in turrets:
		var node: Node2D = turret.get("node")
		if not is_instance_valid(node):
			continue
		var head: Node2D = turret.get("head")
		if not is_instance_valid(head):
			continue
		var skill_id: String = str(turret.get("skill_id", ""))

		if skill_id == "fish_saw":
			# 鋸齒塔持續自轉
			head.rotation += 2.5 * delta
		elif skill_id == "fish_chain":
			# 連鎖塔不旋轉
			pass
		else:
			var target: Node2D = _nearest_enemy(node.global_position, 6.0 * TILE_SIZE)
			if target != null and is_instance_valid(target):
				var dir: Vector2 = node.global_position.direction_to(target.global_position)
				# 砲口朝下：補正 -PI/2
				var target_angle: float = dir.angle() - PI * 0.5
				var spd: float = float(turn_speeds.get(skill_id, 3.0))
				head.rotation = lerp_angle(head.rotation, target_angle, clampf(spd * delta, 0.0, 1.0))


# ══════════════════════════════════════════════════════
#  樸克牌頭上提示系統
# ══════════════════════════════════════════════════════

const _POKER_ICON_PATHS: Dictionary = {
	"heart":   "res://AIgame_rougelike/assets/art/skills/poker/01_01.png",
	"spade":   "res://AIgame_rougelike/assets/art/skills/poker/02_01.png",
	"diamond": "res://AIgame_rougelike/assets/art/skills/poker/03_01.png",
	"club":    "res://AIgame_rougelike/assets/art/skills/poker/04_01.png",
	"joker":   "res://AIgame_rougelike/assets/art/skills/poker/05_01.png",
	"guard":   "res://AIgame_rougelike/assets/art/skills/poker/06_01.png",
}

const _POKER_LABEL_TEXT: Dictionary = {
	"heart":   "閃避 UP",
	"spade":   "傷害 UP",
	"diamond": "爆傷 UP",
	"club":    "攻速 UP",
	"joker":   "詛咒",
	"guard":   "護衛",
}


func _clear_poker_indicators() -> void:
	for key in _poker_icons.keys():
		var row: Dictionary = _poker_icons[key]
		var sp: Sprite2D = row.get("sprite")
		if is_instance_valid(sp):
			sp.queue_free()
	_poker_icons.clear()


func _sync_poker_indicator() -> void:
	if player == null or not is_instance_valid(player):
		return

	# 移除已消失牌的節點
	for key in _poker_icons.keys():
		if not active_poker_buffs.has(key):
			var row: Dictionary = _poker_icons[key]
			var sp: Sprite2D = row.get("sprite")
			if is_instance_valid(sp):
				sp.queue_free()
			_poker_icons.erase(key)

	# 新增或更新現有牌
	var row_index: int = 0
	for card in active_poker_buffs.keys():
		if not _poker_icons.has(card):
			var sprite: Sprite2D = Sprite2D.new()
			var icon_path: String = _POKER_ICON_PATHS.get(card, "")
			if icon_path != "" and ResourceLoader.exists(icon_path):
				var tex: Texture2D = load(icon_path) as Texture2D
				sprite.texture = tex
				var tex_size: Vector2 = tex.get_size()
				var longest: float = maxf(tex_size.x, tex_size.y)
				var sv: float = 28.0 / longest if longest > 0 else 1.0
				sprite.scale = Vector2(sv, sv)
			sprite.centered = true
			player.add_child(sprite)
			_poker_icons[card] = {"sprite": sprite}
		# 更新位置（疊排，每行 34px）
		var entry: Dictionary = _poker_icons[card]
		var sp: Sprite2D = entry.get("sprite")
		if is_instance_valid(sp):
			sp.position = Vector2(-16.0, -96.0 - row_index * 34.0)
		row_index += 1


func _draw_poker_indicator() -> void:
	if player == null or not is_instance_valid(player) or not game_started:
		return
	if _game_font == null:
		return
	var row_index: int = 0
	for card in _poker_icons.keys():
		if not active_poker_buffs.has(card):
			row_index += 1
			continue
		var buff: Dictionary = active_poker_buffs[card]
		var remaining: float = float(buff.get("timer", 0.0))
		# 閃爍：剩餘 < 2s 時 alpha 振盪
		var alpha: float = 1.0
		if remaining < 2.0:
			alpha = 0.4 + 0.6 * absf(sin(_poker_blink_timer * PI * 3.0))
		var entry: Dictionary = _poker_icons[card]
		var sp: Sprite2D = entry.get("sprite")
		if is_instance_valid(sp):
			sp.modulate.a = alpha
		# 文字
		var label_text: String = _POKER_LABEL_TEXT.get(card, card)
		var text_pos: Vector2 = player.global_position + Vector2(4.0, -88.0 - row_index * 34.0)
		draw_string_outline(_game_font, text_pos, label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, Color.BLACK)
		draw_string(_game_font, text_pos, label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		row_index += 1
