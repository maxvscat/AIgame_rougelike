extends Node2D

const PlayerScene := preload("res://AIgame_rougelike/scenes/player.tscn")
const EnemyScene := preload("res://AIgame_rougelike/scenes/enemy.tscn")
const DropScene := preload("res://AIgame_rougelike/scenes/drop.tscn")
const CatPetScene := preload("res://AIgame_rougelike/scenes/cat_pet.tscn")
const BossBulletScript := preload("res://AIgame_rougelike/scripts/boss_bullet.gd")

const GAME_DURATION_SECONDS := 600.0
const SAVE_PATH := "user://save_slots.json"
const SAVE_SLOT_COUNT := 5
const SLOT_BASE_TOKEN_COST := 10
const SLOT_COST_PER_MINUTE := 10
const NORMAL_TOKEN_DROP_CHANCE := 0.36
const ELITE_TOKEN_DROP_CHANCE := 0.7
const HEADHUNTER_TOKEN_DROP_AMOUNT := 5
const BOSS_TOKEN_DROP_AMOUNT := 20
const BOSS_CHIP_DROP_AMOUNT := 20
const HEADHUNTER_CHIP_DROP_AMOUNT := 5
const BASE_TWO_LINE_CHANCE := 0.25
const BASE_THREE_LINE_CHANCE := 0.06
const SLOT_PROBABILITY_MAX_MULTIPLIER := 1.7
const TILE_SIZE := 64.0
const PLAYER_BODY_RADIUS := 16.0
const NORMAL_ENEMY_SPEED_MULTIPLIER := 0.5
const ELITE_ENEMY_SPEED_MULTIPLIER := 1.08
const EDGE_BOSS_SPAWN_TILES := 2.0
const BOSS_BODY_RADIUS := PLAYER_BODY_RADIUS * 2.0
const BOSS_CHARGE_PATH_LENGTH_RATE := 0.7
const BOSS_CHARGE_PATH_WIDTH := BOSS_BODY_RADIUS * 6.0
const BOSS_SCAN_WARNING_WIDTH := 24.5
const BOSS_SCAN_DAMAGE_WIDTH := 119.0
const ELECTRIC_FENCE_START_MARGIN_TILES := 5.0
const ELECTRIC_FENCE_SHRINK_INTERVAL := 6.0
const ELECTRIC_FENCE_DAMAGE_INTERVAL := 0.5
const ELECTRIC_FENCE_SHRINK_AMOUNT := TILE_SIZE
const ELECTRIC_FENCE_KNOCKBACK := TILE_SIZE * 0.5
const DISABLED_LEVEL_UP_SKILLS := ["crit", "damage", "attack_speed", "experience", "move_speed"]
const SLOT_BASE_SYMBOLS := ["J", "Q", "K", "A"]
const BOSS_SPAWN_TIMES := [300.0, 600.0]
const SLOT_SMALL_REWARD_IDS := ["bomb", "thunder", "fire", "ice", "missile"]
const SLOT_JACKPOT_REWARD_IDS := ["lucky_cat", "bounce", "multishot", "slot_777", "energy_attack", "aura_ring"]
const SMALL_SKILL_INTERVALS := {
	"bomb": 3.0,
	"thunder": 5.0,
	"fire": 10.0,
	"ice": 5.0,
	"missile": 5.0
}

var player: Node2D
var spawn_timer: Timer
var elapsed_time := 0.0
var rng := RandomNumberGenerator.new()
var is_game_ended := false
var did_win := false
var game_started := false
var selected_save_slot := -1
var save_slots: Array = []
var total_chips := 0
var kill_count := 0
var boss_damage := 0
var boss_spawn_index := 0
var next_headhunter_time := 180.0
var last_difficulty_minute := 0
var boss_spawn_paused := false

var health_label: Label
var level_label: Label
var exp_label: Label
var money_label: Label
var chip_label: Label
var time_label: Label
var health_bar: ProgressBar
var exp_bar: ProgressBar
var hud_layer: Control
var game_over_label: Label
var settlement_label: Label

var main_menu_overlay: Control
var slot_select_overlay: Control
var lobby_overlay: Control
var lobby_chip_label: Label
var lobby_equipped_label: Label
var settings_overlay: Control
var research_overlay: Control
var level_up_overlay: Control
var slot_reward_overlay: Control
var pause_overlay: Control
var confirm_overlay: Control
var confirm_label: Label
var pending_new_slot := -1
var research_slot_index := 0

var slot_panel: PanelContainer
var slot_money_label: Label
var slot_cost_label: Label
var slot_result_label: Label
var slot_reel_labels: Array[Label] = []
var slot_spin_button: Button
var slot_auto_button: Button
var slot_popup_label: Label
var hud_equipped_panel: PanelContainer
var hud_equipped_label: Label
var is_slot_spinning := false
var auto_spin_enabled := false
var slot_popup_tween: Tween
var pending_level_choices := 0
var is_level_up_menu_open := false
var is_slot_reward_menu_open := false
var current_slot_reward_kind := ""

var energy_attack_timer := 60.0
var aura_timer := 0.25
var small_skill_timers := {}
var cat_pets: Array[Node2D] = []
var burning_enemies := {}
var frozen_enemies := {}
var electric_fence_active := false
var electric_fence_center := Vector2.ZERO
var electric_fence_half_extents := Vector2.ZERO
var electric_fence_shrink_timer := ELECTRIC_FENCE_SHRINK_INTERVAL
var electric_fence_damage_timer := ELECTRIC_FENCE_DAMAGE_INTERVAL
var electric_fence_line: Line2D

var slot_symbols := {
	"J": {"name": "J", "weight": 24},
	"Q": {"name": "Q", "weight": 22},
	"K": {"name": "K", "weight": 20},
	"A": {"name": "A", "weight": 18},
	"WILD": {"name": "WILD", "weight": 7},
	"7": {"name": "7", "weight": 3}
}

var research_defs := {
	"start_damage_50": {"name": "開局傷害", "base_cost": 50, "cost_step": 50, "effect": "start_damage_50", "max_level": 3},
	"crit_20": {"name": "暴擊率", "base_cost": 100, "cost_step": 100, "effect": "crit_20", "max_level": 3},
	"random_normal_skill": {"name": "開局隨機大獎技能", "base_cost": 500, "cost_step": 0, "effect": "random_jackpot_skill", "max_level": 1},
	"regen_2": {"name": "每秒回血", "base_cost": 100, "cost_step": 100, "effect": "regen_2", "max_level": 3},
	"extra_life": {"name": "額外生命", "base_cost": 250, "cost_step": 250, "effect": "extra_life", "max_level": 3},
	"chip_drop_x2": {"name": "晶片掉落數量", "base_cost": 50, "cost_step": 50, "effect": "chip_drop_x2", "max_level": 3},
	"defense_20": {"name": "防禦", "base_cost": 100, "cost_step": 100, "effect": "defense_20", "max_level": 3}
}

var upgrade_defs := {
	"crit": {"name": "暴擊", "effect": "暴擊率", "per_level": 7, "unit": "%"},
	"jackpot_rate": {"name": "大獎率", "effect": "大獎圖示出現率", "per_level": 7, "unit": "%"},
	"cost_rate": {"name": "代幣掉落", "effect": "Slot代幣掉落率", "per_level": 7, "unit": "%"},
	"fragment_amount": {"name": "WILD率", "effect": "WILD出現率", "per_level": 7, "unit": "%"},
	"reroll_rate": {"name": "重抽率", "effect": "免費重抽機率", "per_level": 10, "unit": "%"},
	"line_rate": {"name": "連線率", "effect": "連線機率", "per_level": 7, "unit": "%"},
	"damage": {"name": "傷害", "effect": "攻擊傷害", "per_level": 10, "unit": "%"},
	"attack_speed": {"name": "攻速", "effect": "攻擊速度", "per_level": 10, "unit": "%"},
	"experience": {"name": "經驗", "effect": "經驗值", "per_level": 10, "unit": "%"},
	"move_speed": {"name": "移速", "effect": "移動速度", "per_level": 10, "unit": "%"}
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	rng.randomize()
	_normalize_slot_symbol_names()
	_normalize_upgrade_defs()
	_reset_slot_run_state()
	_load_save_slots()
	_create_world()
	_create_player()
	_create_ui()
	_create_spawn_timer()
	_update_ui()
	_update_time_ui()
	_show_main_menu()


func _normalize_slot_symbol_names() -> void:
	var names := {
		"J": "J",
		"Q": "Q",
		"K": "K",
		"A": "A",
		"WILD": "WILD",
		"7": "7"
	}
	for symbol_id in names.keys():
		if slot_symbols.has(symbol_id):
			slot_symbols[symbol_id]["name"] = names[symbol_id]


func _normalize_upgrade_defs() -> void:
	var names := {
		"crit": ["暴擊", "暴擊率"],
		"jackpot_rate": ["大獎率", "大獎圖示出現率"],
		"cost_rate": ["代幣掉落", "Slot代幣掉落率"],
		"fragment_amount": ["WILD率", "WILD出現率"],
		"reroll_rate": ["重抽率", "免費重抽機率"],
		"line_rate": ["連線率", "連線機率"],
		"damage": ["傷害", "攻擊傷害"],
		"attack_speed": ["攻速", "攻擊速度"],
		"experience": ["經驗", "經驗值"],
		"move_speed": ["移速", "移動速度"]
	}
	for skill_id in names.keys():
		if upgrade_defs.has(skill_id):
			upgrade_defs[skill_id]["name"] = names[skill_id][0]
			upgrade_defs[skill_id]["effect"] = names[skill_id][1]


func _process(delta: float) -> void:
	if get_tree().paused or not game_started:
		return

	elapsed_time += delta
	_update_time_ui()
	_check_difficulty_minute()
	_check_boss_spawn()
	_check_headhunter_spawn()
	_update_spawn_timer_by_boss_presence()
	if elapsed_time >= GAME_DURATION_SECONDS and boss_spawn_index >= BOSS_SPAWN_TIMES.size():
		if not _has_alive_boss():
			_end_game(true)
			return
		_start_electric_fence()

	_process_passive_abilities(delta)
	_process_status_effects(delta)
	_process_electric_fence(delta)
	if auto_spin_enabled and not is_slot_spinning and is_instance_valid(player) and player.slot_tokens >= _get_slot_cost():
		_spin_slot()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_game_ended and (event.is_action_pressed("restart") or event.is_action_pressed("ui_accept")):
		_return_to_lobby_after_run()
		get_viewport().set_input_as_handled()
		return

	if game_started and not get_tree().paused and event.is_action_pressed("restart"):
		_spin_slot()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if game_started and not is_game_ended and not is_level_up_menu_open and _is_no_menu_overlay_open():
			_toggle_pause_game()
			get_viewport().set_input_as_handled()
		elif game_started and not is_game_ended and pause_overlay != null and pause_overlay.visible:
			_toggle_pause_game()
			get_viewport().set_input_as_handled()
		elif settings_overlay != null and settings_overlay.visible:
			_show_main_menu()
			get_viewport().set_input_as_handled()
		elif research_overlay != null and research_overlay.visible:
			_show_lobby()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not is_instance_valid(player):
		return
	var viewport_size := get_viewport_rect().size
	var camera_center := player.global_position
	var top_left := camera_center - viewport_size * 0.5
	var grid_color := Color(0.16, 0.18, 0.2, 0.45)
	for x in range(int(floor(top_left.x / 64.0)) * 64, int(top_left.x + viewport_size.x) + 64, 64):
		draw_line(Vector2(x, top_left.y - 64.0), Vector2(x, top_left.y + viewport_size.y + 64.0), grid_color, 1.0)
	for y in range(int(floor(top_left.y / 64.0)) * 64, int(top_left.y + viewport_size.y) + 64, 64):
		draw_line(Vector2(top_left.x - 64.0, y), Vector2(top_left.x + viewport_size.x + 64.0, y), grid_color, 1.0)


func _create_world() -> void:
	var background := ColorRect.new()
	background.color = Color(0.055, 0.065, 0.075)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var canvas := CanvasLayer.new()
	canvas.layer = -10
	add_child(canvas)
	canvas.add_child(background)


func _create_player() -> void:
	player = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.global_position = Vector2.ZERO
	player.stats_changed.connect(_update_ui)
	player.attack_performed.connect(_on_player_attack_performed)
	player.area_effect.connect(_show_area_effect)
	player.level_up_notice.connect(func(text: String) -> void:
		_show_pickup_text(player.global_position, text, Color(0.65, 1.0, 0.45))
	)
	player.level_up_available.connect(_queue_level_up_choices)
	player.died.connect(_on_player_died)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	player.add_child(camera)
	camera.make_current()


func _create_spawn_timer() -> void:
	spawn_timer = Timer.new()
	spawn_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	spawn_timer.wait_time = 0.9
	spawn_timer.autostart = true
	spawn_timer.timeout.connect(_spawn_enemy)
	add_child(spawn_timer)


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	hud_layer = Control.new()
	hud_layer.visible = false
	hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(hud_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 18.0
	margin.offset_top = 18.0
	margin.offset_right = 356.0
	margin.offset_bottom = 220.0
	hud_layer.add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.custom_minimum_size = Vector2(320.0, 170.0)
	panel.add_child(box)

	health_label = Label.new()
	level_label = Label.new()
	exp_label = Label.new()
	money_label = Label.new()
	chip_label = Label.new()
	time_label = Label.new()
	for label in [health_label, level_label, exp_label, money_label, chip_label, time_label]:
		label.add_theme_font_size_override("font_size", 18)
	health_bar = ProgressBar.new()
	exp_bar = ProgressBar.new()
	health_bar.show_percentage = false
	exp_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(300.0, 18.0)
	exp_bar.custom_minimum_size = Vector2(300.0, 14.0)
	box.add_child(health_label)
	box.add_child(health_bar)
	box.add_child(level_label)
	box.add_child(exp_label)
	box.add_child(exp_bar)
	box.add_child(money_label)
	box.add_child(chip_label)
	box.add_child(time_label)

	hud_equipped_panel = PanelContainer.new()
	hud_equipped_panel.visible = false
	hud_equipped_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hud_equipped_panel.offset_left = 18.0
	hud_equipped_panel.offset_top = -360.0
	hud_equipped_panel.offset_right = 390.0
	hud_equipped_panel.offset_bottom = -18.0
	hud_layer.add_child(hud_equipped_panel)

	hud_equipped_label = Label.new()
	hud_equipped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_equipped_label.add_theme_font_size_override("font_size", 14)
	hud_equipped_panel.add_child(hud_equipped_label)

	_create_fixed_slot_ui(hud_layer)
	_create_main_menu_overlay(canvas)
	_create_slot_select_overlay(canvas)
	_create_lobby_overlay(canvas)
	_create_research_overlay(canvas)
	_create_level_up_overlay(canvas)
	_create_slot_reward_overlay(canvas)
	_create_pause_overlay(canvas)
	_create_settings_overlay(canvas)
	_create_confirm_overlay(canvas)

	game_over_label = Label.new()
	game_over_label.visible = false
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 56)
	game_over_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(game_over_label)

	settlement_label = Label.new()
	settlement_label.visible = false
	settlement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settlement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	settlement_label.add_theme_font_size_override("font_size", 28)
	settlement_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(settlement_label)

	slot_popup_label = Label.new()
	slot_popup_label.visible = false
	slot_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_popup_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	slot_popup_label.add_theme_font_size_override("font_size", 36)
	slot_popup_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.28))
	slot_popup_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	slot_popup_label.add_theme_constant_override("shadow_offset_x", 3)
	slot_popup_label.add_theme_constant_override("shadow_offset_y", 3)
	slot_popup_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot_popup_label.offset_top = 130.0
	canvas.add_child(slot_popup_label)


func _create_fixed_slot_ui(parent: Control) -> void:
	slot_panel = PanelContainer.new()
	slot_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	slot_panel.offset_left = -390.0
	slot_panel.offset_top = 14.0
	slot_panel.offset_right = -14.0
	slot_panel.offset_bottom = 510.0
	parent.add_child(slot_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360.0, 485.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(338.0, 0.0)
	scroll.add_child(box)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Slot 代幣機"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	slot_money_label = Label.new()
	slot_money_label.add_theme_font_size_override("font_size", 18)
	box.add_child(slot_money_label)

	slot_cost_label = Label.new()
	slot_cost_label.text = "每次轉動：10 Token｜每分鐘 +10｜Space 或按鈕"
	slot_cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(slot_cost_label)

	var reel_row := HBoxContainer.new()
	reel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reel_row.add_theme_constant_override("separation", 8)
	box.add_child(reel_row)
	for index in range(3):
		var reel := Label.new()
		reel.text = "?"
		reel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		reel.custom_minimum_size = Vector2(96.0, 70.0)
		reel.add_theme_font_size_override("font_size", 24)
		reel_row.add_child(reel)
		slot_reel_labels.append(reel)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	box.add_child(button_row)

	slot_spin_button = Button.new()
	slot_spin_button.text = "Spin"
	slot_spin_button.pressed.connect(_spin_slot)
	button_row.add_child(slot_spin_button)

	slot_auto_button = Button.new()
	slot_auto_button.text = "Auto：關"
	slot_auto_button.toggle_mode = true
	slot_auto_button.toggled.connect(_set_auto_spin)
	button_row.add_child(slot_auto_button)

	slot_result_label = Label.new()
	slot_result_label.text = "等待轉動"
	slot_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_result_label.custom_minimum_size = Vector2(300.0, 56.0)
	box.add_child(slot_result_label)


func _create_menu_panel(parent: Control, title_text: String, panel_size: Vector2) -> VBoxContainer:
	parent.visible = false
	parent.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	return box


func _create_main_menu_overlay(canvas: CanvasLayer) -> void:
	main_menu_overlay = Control.new()
	canvas.add_child(main_menu_overlay)
	var box := _create_menu_panel(main_menu_overlay, "主選單", Vector2(460.0, 450.0))
	var new_button := Button.new()
	new_button.text = "開新遊戲"
	new_button.pressed.connect(_show_new_game_slots)
	box.add_child(new_button)
	var load_button := Button.new()
	load_button.text = "讀取存檔"
	load_button.pressed.connect(_show_load_game_slots)
	box.add_child(load_button)
	var settings_button := Button.new()
	settings_button.text = "設定"
	settings_button.pressed.connect(_show_settings)
	box.add_child(settings_button)
	var quit_button := Button.new()
	quit_button.text = "離開遊戲"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit_button)


func _create_slot_select_overlay(canvas: CanvasLayer) -> void:
	slot_select_overlay = Control.new()
	canvas.add_child(slot_select_overlay)
	_create_menu_panel(slot_select_overlay, "存檔欄位", Vector2(720.0, 580.0))


func _create_lobby_overlay(canvas: CanvasLayer) -> void:
	lobby_overlay = Control.new()
	canvas.add_child(lobby_overlay)
	var box := _create_menu_panel(lobby_overlay, "大廳", Vector2(640.0, 520.0))

	lobby_chip_label = Label.new()
	lobby_chip_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lobby_chip_label.offset_left = 18.0
	lobby_chip_label.offset_top = 18.0
	lobby_chip_label.offset_right = 360.0
	lobby_chip_label.offset_bottom = 58.0
	lobby_chip_label.add_theme_font_size_override("font_size", 22)
	lobby_overlay.add_child(lobby_chip_label)

	lobby_equipped_label = Label.new()
	lobby_equipped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_equipped_label.add_theme_font_size_override("font_size", 18)
	box.add_child(lobby_equipped_label)

	var start_button := Button.new()
	start_button.text = "開始冒險"
	start_button.pressed.connect(_begin_adventure_from_lobby)
	box.add_child(start_button)

	var research_button := Button.new()
	research_button.text = "永久研究中心"
	research_button.pressed.connect(_show_research_center)
	box.add_child(research_button)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.pressed.connect(_show_main_menu)
	box.add_child(back_button)


func _create_research_overlay(canvas: CanvasLayer) -> void:
	research_overlay = Control.new()
	canvas.add_child(research_overlay)
	_create_menu_panel(research_overlay, "永久研究中心", Vector2(800.0, 680.0))


func _create_level_up_overlay(canvas: CanvasLayer) -> void:
	level_up_overlay = Control.new()
	canvas.add_child(level_up_overlay)
	_create_menu_panel(level_up_overlay, "LV UP！", Vector2(760.0, 440.0))


func _create_slot_reward_overlay(canvas: CanvasLayer) -> void:
	slot_reward_overlay = Control.new()
	canvas.add_child(slot_reward_overlay)
	_create_menu_panel(slot_reward_overlay, "Slot 獎勵", Vector2(760.0, 440.0))


func _create_pause_overlay(canvas: CanvasLayer) -> void:
	pause_overlay = Control.new()
	canvas.add_child(pause_overlay)
	var box := _create_menu_panel(pause_overlay, "暫停", Vector2(420.0, 220.0))
	var info := Label.new()
	info.text = "按 ESC 繼續遊戲"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 22)
	box.add_child(info)


func _create_settings_overlay(canvas: CanvasLayer) -> void:
	settings_overlay = Control.new()
	canvas.add_child(settings_overlay)
	var box := _create_menu_panel(settings_overlay, "設定", Vector2(520.0, 360.0))
	var volume_label := Label.new()
	volume_label.text = "音量"
	box.add_child(volume_label)
	var volume_slider := HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.value = 1.0
	volume_slider.value_changed.connect(func(value: float) -> void:
		AudioServer.set_bus_volume_db(0, linear_to_db(max(value, 0.001)))
	)
	box.add_child(volume_slider)
	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = "全螢幕"
	fullscreen_check.toggled.connect(func(enabled: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	)
	box.add_child(fullscreen_check)
	var key_label := Label.new()
	key_label.text = "按鍵：WASD 移動，Space 轉動 Slot / 重新開始，ESC 暫停 / 恢復"
	key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(key_label)
	var back_button := Button.new()
	back_button.text = "返回"
	back_button.pressed.connect(_show_main_menu)
	box.add_child(back_button)


func _create_confirm_overlay(canvas: CanvasLayer) -> void:
	confirm_overlay = Control.new()
	canvas.add_child(confirm_overlay)
	var box := _create_menu_panel(confirm_overlay, "確認覆蓋", Vector2(520.0, 260.0))
	confirm_label = Label.new()
	confirm_label.text = "此欄位已有資料，確定覆蓋？"
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var yes_button := Button.new()
	yes_button.text = "覆蓋"
	yes_button.pressed.connect(func() -> void:
		confirm_overlay.visible = false
		_enter_lobby_from_slot(pending_new_slot, true)
	)
	row.add_child(yes_button)
	var no_button := Button.new()
	no_button.text = "取消"
	no_button.pressed.connect(func() -> void:
		confirm_overlay.visible = false
		slot_select_overlay.visible = true
	)
	row.add_child(no_button)


func _reset_slot_run_state() -> void:
	_reset_small_skill_timers()
	is_slot_reward_menu_open = false
	current_slot_reward_kind = ""


func _reset_small_skill_timers() -> void:
	small_skill_timers.clear()
	for skill_id in SMALL_SKILL_INTERVALS.keys():
		small_skill_timers[skill_id] = float(SMALL_SKILL_INTERVALS[skill_id])


func _default_save_slot() -> Dictionary:
	return {
		"exists": false,
		"total_chips": 0,
		"account_level": 1,
		"play_seconds": 0.0,
		"last_played": "尚未遊玩",
		"owned_research": [],
		"equipped_research": [],
		"research_levels": {}
	}


func _normalize_save_slot(slot: Dictionary) -> Dictionary:
	var normalized := _default_save_slot()
	for key in slot.keys():
		normalized[key] = slot[key]
	var levels: Dictionary = normalized["research_levels"] if normalized["research_levels"] is Dictionary else {}
	for research_id in Array(normalized["owned_research"]):
		if not levels.has(str(research_id)):
			levels[str(research_id)] = 1
	normalized["research_levels"] = levels
	var owned: Array = []
	for research_id in levels.keys():
		if int(levels[research_id]) > 0:
			owned.append(str(research_id))
	normalized["owned_research"] = owned
	return normalized


func _load_save_slots() -> void:
	save_slots.clear()
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			save_slots = parsed
	while save_slots.size() < SAVE_SLOT_COUNT:
		save_slots.append(_default_save_slot())
	for index in range(save_slots.size()):
		save_slots[index] = _normalize_save_slot(save_slots[index])


func _save_save_slots() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_slots, "\t"))


func _show_main_menu() -> void:
	get_tree().paused = true
	main_menu_overlay.visible = true
	slot_select_overlay.visible = false
	lobby_overlay.visible = false
	settings_overlay.visible = false
	research_overlay.visible = false
	level_up_overlay.visible = false
	slot_reward_overlay.visible = false
	pause_overlay.visible = false
	confirm_overlay.visible = false
	hud_layer.visible = false
	game_over_label.visible = false
	settlement_label.visible = false


func _show_settings() -> void:
	get_tree().paused = true
	main_menu_overlay.visible = false
	slot_select_overlay.visible = false
	lobby_overlay.visible = false
	settings_overlay.visible = true
	research_overlay.visible = false
	level_up_overlay.visible = false
	slot_reward_overlay.visible = false
	pause_overlay.visible = false
	confirm_overlay.visible = false


func _show_new_game_slots() -> void:
	_show_save_slots(true)


func _show_load_game_slots() -> void:
	_show_save_slots(false)


func _show_save_slots(for_new_game: bool) -> void:
	get_tree().paused = true
	main_menu_overlay.visible = false
	lobby_overlay.visible = false
	settings_overlay.visible = false
	research_overlay.visible = false
	level_up_overlay.visible = false
	slot_reward_overlay.visible = false
	pause_overlay.visible = false
	confirm_overlay.visible = false
	slot_select_overlay.visible = true
	var box := _get_menu_box(slot_select_overlay)
	_clear_menu_dynamic_children(box)
	for index in range(SAVE_SLOT_COUNT):
		var slot: Dictionary = save_slots[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(650.0, 72.0)
		button.text = _format_save_slot_text(index, slot)
		button.pressed.connect(_on_save_slot_pressed.bind(index, for_new_game))
		if not for_new_game and not bool(slot["exists"]):
			button.disabled = true
		box.add_child(button)
	var back_button := Button.new()
	back_button.text = "返回主選單"
	back_button.pressed.connect(_show_main_menu)
	box.add_child(back_button)


func _get_menu_box(overlay: Control) -> VBoxContainer:
	var center := overlay.get_child(1)
	var panel := center.get_child(0)
	return panel.get_child(0)


func _clear_menu_dynamic_children(box: VBoxContainer) -> void:
	for child in box.get_children():
		if child.get_index() > 0:
			child.queue_free()


func _format_save_slot_text(index: int, slot: Dictionary) -> String:
	if not bool(slot["exists"]):
		return "欄位 %d：空白" % (index + 1)
	var hours: float = float(slot["play_seconds"]) / 3600.0
	return "欄位 %d：帳號等級 %d｜遊玩 %.1f 小時｜最後遊玩 %s｜永久晶片 %d" % [
		index + 1,
		int(slot["account_level"]),
		hours,
		str(slot["last_played"]),
		int(slot["total_chips"])
	]


func _on_save_slot_pressed(index: int, for_new_game: bool) -> void:
	if for_new_game and bool(save_slots[index]["exists"]):
		pending_new_slot = index
		confirm_overlay.visible = true
		slot_select_overlay.visible = false
		return
	_enter_lobby_from_slot(index, for_new_game)


func _enter_lobby_from_slot(index: int, overwrite: bool) -> void:
	selected_save_slot = index
	research_slot_index = index
	if overwrite:
		save_slots[index] = _default_save_slot()
		save_slots[index]["exists"] = true
	var slot: Dictionary = save_slots[index]
	if not bool(slot["exists"]):
		slot["exists"] = true
	total_chips = int(slot["total_chips"])
	save_slots[index] = slot
	_save_save_slots()
	_show_lobby()


func _show_lobby() -> void:
	get_tree().paused = true
	main_menu_overlay.visible = false
	slot_select_overlay.visible = false
	settings_overlay.visible = false
	research_overlay.visible = false
	level_up_overlay.visible = false
	slot_reward_overlay.visible = false
	pause_overlay.visible = false
	confirm_overlay.visible = false
	hud_layer.visible = false
	game_over_label.visible = false
	settlement_label.visible = false
	if lobby_overlay != null:
		lobby_overlay.visible = true
	_update_lobby_ui()


func _begin_adventure_from_lobby() -> void:
	if selected_save_slot < 0:
		return
	var slot: Dictionary = save_slots[selected_save_slot]
	total_chips = int(slot["total_chips"])
	_reset_run_state()
	main_menu_overlay.visible = false
	slot_select_overlay.visible = false
	lobby_overlay.visible = false
	settings_overlay.visible = false
	research_overlay.visible = false
	level_up_overlay.visible = false
	slot_reward_overlay.visible = false
	pause_overlay.visible = false
	confirm_overlay.visible = false
	hud_layer.visible = true
	game_started = true
	_apply_equipped_research(slot)
	_update_slot_ui()
	get_tree().paused = false
	_update_ui()


func _reset_run_state() -> void:
	game_started = false
	is_game_ended = false
	did_win = false
	elapsed_time = 0.0
	kill_count = 0
	boss_damage = 0
	boss_spawn_index = 0
	next_headhunter_time = 180.0
	last_difficulty_minute = 0
	boss_spawn_paused = false
	energy_attack_timer = 60.0
	aura_timer = 0.25
	electric_fence_active = false
	electric_fence_shrink_timer = ELECTRIC_FENCE_SHRINK_INTERVAL
	electric_fence_damage_timer = ELECTRIC_FENCE_DAMAGE_INTERVAL
	if is_instance_valid(electric_fence_line):
		electric_fence_line.queue_free()
	electric_fence_line = null
	auto_spin_enabled = false
	is_slot_spinning = false
	is_slot_reward_menu_open = false
	burning_enemies.clear()
	frozen_enemies.clear()
	cat_pets.clear()
	_reset_slot_run_state()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	for drop in get_tree().get_nodes_in_group("drops"):
		if is_instance_valid(drop):
			drop.queue_free()
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	_create_player()
	player.global_position = Vector2.ZERO
	game_over_label.visible = false
	settlement_label.visible = false
	slot_popup_label.visible = false
	if slot_auto_button != null:
		slot_auto_button.button_pressed = false
		slot_auto_button.text = "Auto：關"
	if spawn_timer != null:
		spawn_timer.stop()
		spawn_timer.wait_time = 0.9
		spawn_timer.start()
	_update_time_ui()


func _apply_equipped_research(slot: Dictionary) -> void:
	var equipped: Array = slot["equipped_research"]
	for research_id in equipped:
		if research_defs.has(str(research_id)):
			player.apply_research_effect(research_defs[str(research_id)]["effect"], _research_level(slot, str(research_id)))


func _is_no_menu_overlay_open() -> bool:
	return not (
		(main_menu_overlay != null and main_menu_overlay.visible)
		or (slot_select_overlay != null and slot_select_overlay.visible)
		or (lobby_overlay != null and lobby_overlay.visible)
		or (settings_overlay != null and settings_overlay.visible)
		or (research_overlay != null and research_overlay.visible)
		or (level_up_overlay != null and level_up_overlay.visible)
		or (slot_reward_overlay != null and slot_reward_overlay.visible)
		or (confirm_overlay != null and confirm_overlay.visible)
		or (pause_overlay != null and pause_overlay.visible)
	)


func _toggle_pause_game() -> void:
	var should_pause := not get_tree().paused
	get_tree().paused = should_pause
	if pause_overlay != null:
		pause_overlay.visible = should_pause


func _save_current_slot() -> void:
	if selected_save_slot < 0:
		return
	var slot: Dictionary = save_slots[selected_save_slot]
	slot["exists"] = true
	slot["total_chips"] = total_chips
	slot["account_level"] = max(1, int(total_chips / 100) + 1)
	slot["play_seconds"] = float(slot["play_seconds"]) + elapsed_time
	slot["last_played"] = Time.get_datetime_string_from_system(false, true)
	save_slots[selected_save_slot] = slot
	_save_save_slots()


func _show_research_center() -> void:
	if selected_save_slot < 0:
		_show_main_menu()
		return
	get_tree().paused = true
	main_menu_overlay.visible = false
	slot_select_overlay.visible = false
	lobby_overlay.visible = false
	settings_overlay.visible = false
	confirm_overlay.visible = false
	level_up_overlay.visible = false
	slot_reward_overlay.visible = false
	pause_overlay.visible = false
	research_overlay.visible = true
	var box := _get_menu_box(research_overlay)
	_clear_menu_dynamic_children(box)
	var slot: Dictionary = save_slots[selected_save_slot]
	var info := Label.new()
	info.text = "欄位 %d｜永久晶片：%d\n購買後永久擁有；每局最多裝備 6 顆，不可重複裝備。已擁有能力可升級，最高 LV3。" % [selected_save_slot + 1, int(slot["total_chips"])]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)

	for research_id in research_defs.keys():
		var def: Dictionary = research_defs[research_id]
		var current_level := _research_level(slot, research_id)
		var max_level := int(def["max_level"])
		var next_cost := _research_next_cost(slot, research_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.custom_minimum_size = Vector2(430.0, 42.0)
		label.text = "%s｜%s｜下一級 %d 晶片" % [_research_display_name(research_id, current_level), _research_level_text(current_level, max_level), next_cost]
		row.add_child(label)
		var buy_button := Button.new()
		buy_button.text = "購買" if current_level == 0 else "升級"
		buy_button.disabled = current_level >= max_level or int(slot["total_chips"]) < next_cost
		buy_button.pressed.connect(_buy_research.bind(research_id))
		row.add_child(buy_button)
		var equip_button := Button.new()
		equip_button.text = "卸下" if _research_equipped(slot, research_id) else "裝備"
		equip_button.disabled = not _research_owned(slot, research_id)
		equip_button.pressed.connect(_toggle_research.bind(research_id))
		row.add_child(equip_button)
		box.add_child(row)
	var equipped_label := Label.new()
	equipped_label.text = _get_equipped_research_text(slot)
	equipped_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(equipped_label)
	var back_button := Button.new()
	back_button.text = "返回"
	back_button.pressed.connect(_show_lobby)
	box.add_child(back_button)


func _set_research_slot(index: int) -> void:
	research_slot_index = index
	_show_research_center()


func _queue_level_up_choices() -> void:
	pending_level_choices += 1
	if is_slot_spinning or is_slot_reward_menu_open or (slot_reward_overlay != null and slot_reward_overlay.visible):
		return
	if not is_level_up_menu_open:
		_show_level_up_choices()


func _show_level_up_choices() -> void:
	if not game_started or not is_instance_valid(player):
		return
	if is_slot_spinning or is_slot_reward_menu_open or (slot_reward_overlay != null and slot_reward_overlay.visible):
		return
	var available := _get_available_upgrade_ids()
	if available.is_empty():
		pending_level_choices = 0
		return
	is_level_up_menu_open = true
	get_tree().paused = true
	level_up_overlay.visible = true
	var box := _get_menu_box(level_up_overlay)
	_clear_menu_dynamic_children(box)

	var info := Label.new()
	info.text = "選擇 1 個技能。技能可重複取得，最高 LV MAX。"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)

	available.shuffle()
	var choice_count: int = min(3, available.size())
	for index in range(choice_count):
		var skill_id := str(available[index])
		var button := Button.new()
		button.custom_minimum_size = Vector2(680.0, 72.0)
		button.text = _format_upgrade_choice(skill_id)
		button.pressed.connect(_choose_upgrade_skill.bind(skill_id))
		box.add_child(button)


func _get_available_upgrade_ids() -> Array[String]:
	var available: Array[String] = []
	for skill_id in upgrade_defs.keys():
		if DISABLED_LEVEL_UP_SKILLS.has(str(skill_id)):
			continue
		if player.get_upgrade_skill_level(str(skill_id)) < 5:
			available.append(str(skill_id))
	return available


func _format_upgrade_choice(skill_id: String) -> String:
	var current_level: int = player.get_upgrade_skill_level(skill_id)
	var next_level: int = current_level + 1
	return "%s %s -> %s\n%s" % [
		str(upgrade_defs[skill_id]["name"]),
		_format_skill_level(current_level),
		_format_skill_level(next_level),
		_get_upgrade_skill_effect_text(skill_id, next_level)
	]


func _format_skill_level(level: int) -> String:
	return "LV MAX" if level >= 5 else "LV%d" % level


func _choose_upgrade_skill(skill_id: String) -> void:
	if not is_instance_valid(player):
		return
	player.apply_upgrade_skill(skill_id)
	pending_level_choices = max(0, pending_level_choices - 1)
	_update_ui()
	if pending_level_choices > 0 and not _get_available_upgrade_ids().is_empty():
		_show_level_up_choices()
	else:
		is_level_up_menu_open = false
		level_up_overlay.visible = false
		get_tree().paused = false


func _get_upgrade_skill_effect_text(skill_id: String, level: int = -1) -> String:
	var skill_level: int = player.get_upgrade_skill_level(skill_id) if level < 0 and is_instance_valid(player) else level
	if skill_level < 0:
		skill_level = 0
	var effect_texts := {
		"crit": "暴擊率 +%d%%" % int(skill_level * 7),
		"jackpot_rate": "大獎圖示出現率 +%d%%" % int(skill_level * 7),
		"cost_rate": "Slot代幣掉落率 +%d%%" % int(skill_level * 7),
		"fragment_amount": "WILD 出現率 +%d%%" % int(skill_level * 7),
		"reroll_rate": "免費重抽率 +%d%%" % int(skill_level * 10),
		"line_rate": "連線率 +%d%%" % int(skill_level * 7),
		"damage": "攻擊傷害 +%d%%" % int(skill_level * 10),
		"attack_speed": "攻擊速度 +%d%%" % int(skill_level * 10),
		"experience": "經驗值 +%d%%" % int(skill_level * 10),
		"move_speed": "移動速度 +%d%%" % int(skill_level * 10)
	}
	if effect_texts.has(skill_id):
		return effect_texts[skill_id]
	match skill_id:
		"crit":
			return "暴擊率 +%d%%" % int(skill_level * 7)
		"jackpot_rate":
			return "大獎圖示出現率 +%d%%" % int(skill_level * 7)
		"cost_rate":
			return "Slot代幣掉落率 +%d%%" % int(skill_level * 7)
		"fragment_amount":
			return "WILD 出現率 +%d%%" % int(skill_level * 7)
		"reroll_rate":
			return "免費重抽率 +%d%%" % int(skill_level * 10)
		"line_rate":
			return "連線率 +%d%%" % int(skill_level * 7)
		"damage":
			return "攻擊傷害 +%d%%" % int(skill_level * 10)
		"attack_speed":
			return "攻擊速度 +%d%%" % int(skill_level * 10)
		"experience":
			return "經驗值 +%d%%" % int(skill_level * 10)
		"move_speed":
			return "移動速度 +%d%%" % int(skill_level * 10)
	return ""


func _research_owned(slot: Dictionary, research_id: String) -> bool:
	return _research_level(slot, research_id) > 0


func _research_equipped(slot: Dictionary, research_id: String) -> bool:
	return Array(slot["equipped_research"]).has(research_id)


func _research_level(slot: Dictionary, research_id: String) -> int:
	var levels: Dictionary = slot["research_levels"] if slot["research_levels"] is Dictionary else {}
	return int(levels.get(research_id, 0))


func _research_next_cost(slot: Dictionary, research_id: String) -> int:
	var def: Dictionary = research_defs[research_id]
	var current_level := _research_level(slot, research_id)
	return int(def["base_cost"]) + int(def["cost_step"]) * current_level


func _research_level_text(current_level: int, max_level: int) -> String:
	if current_level <= 0:
		return "未擁有"
	if current_level >= max_level:
		return "LV%d/%d 滿級" % [current_level, max_level]
	return "LV%d/%d" % [current_level, max_level]


func _research_display_name(research_id: String, level: int) -> String:
	var preview_level: int = max(1, level)
	match research_id:
		"start_damage_50":
			return "開局傷害 +%d%%" % int(50 + 20 * (preview_level - 1))
		"crit_20":
			return "暴擊率 +%d%%" % int(20 + 10 * (preview_level - 1))
		"random_normal_skill":
			return "開局獲得 1 個隨機大獎技能 LV1"
		"regen_2":
			return "每秒回 %d HP" % int(2 + preview_level - 1)
		"extra_life":
			return "多 %d 條命" % preview_level
		"chip_drop_x2":
			return "晶片掉落數量 x%d" % int(1 + preview_level)
		"defense_20":
			return "防禦 +%d%%" % int(20 + 10 * (preview_level - 1))
	return str(research_defs[research_id]["name"])


func _get_equipped_research_text(slot: Dictionary) -> String:
	var equipped: Array = slot["equipped_research"]
	if equipped.is_empty():
		return ""
	var lines := ["目前裝備："]
	for research_id in equipped:
		var id := str(research_id)
		if not research_defs.has(id):
			continue
		var level := _research_level(slot, id)
		lines.append("%s %s" % [_research_display_name(id, level), _research_level_text(level, int(research_defs[id]["max_level"]))])
	return "\n".join(lines)


func _update_lobby_ui() -> void:
	if selected_save_slot < 0 or lobby_chip_label == null:
		return
	var slot: Dictionary = save_slots[selected_save_slot]
	lobby_chip_label.text = "永久晶片：%d" % int(slot["total_chips"])
	var equipped_text := _get_equipped_research_text(slot)
	lobby_equipped_label.visible = not equipped_text.is_empty()
	lobby_equipped_label.text = equipped_text


func _update_equipped_hud() -> void:
	if hud_equipped_panel == null or selected_save_slot < 0:
		return
	var text_blocks: Array[String] = []
	var equipped_text := _get_equipped_research_text(save_slots[selected_save_slot])
	if not equipped_text.is_empty():
		text_blocks.append(equipped_text)
	var upgrade_text := _get_upgrade_skills_text()
	if not upgrade_text.is_empty():
		text_blocks.append(upgrade_text)
	var slot_skill_text := _get_run_slot_skills_text()
	if not slot_skill_text.is_empty():
		text_blocks.append(slot_skill_text)
	hud_equipped_panel.visible = game_started and not text_blocks.is_empty()
	hud_equipped_label.text = "\n\n".join(text_blocks)


func _get_upgrade_skills_text() -> String:
	if not is_instance_valid(player):
		return ""
	var lines := ["升級技能："]
	for skill_id in upgrade_defs.keys():
		if DISABLED_LEVEL_UP_SKILLS.has(str(skill_id)):
			continue
		var level: int = player.get_upgrade_skill_level(str(skill_id))
		if level <= 0:
			continue
		lines.append("%s %s %s" % [str(upgrade_defs[skill_id]["name"]), _format_skill_level(level), _get_upgrade_skill_effect_text(str(skill_id))])
	if lines.size() == 1:
		return ""
	return "\n".join(lines)


func _get_run_slot_skills_text() -> String:
	if not is_instance_valid(player):
		return ""
	var lines := ["Slot技能："]
	for skill_id in player.small_skills.keys():
		var level: int = player.get_small_skill_level(str(skill_id))
		if level > 0:
			lines.append("%s %s" % [_skill_name(str(skill_id)), _format_skill_level(level)])
	for skill_id in player.jackpot_skills.keys():
		var level: int = player.get_skill_level(str(skill_id))
		if level > 0:
			lines.append("%s %s" % [_skill_name(str(skill_id)), _format_skill_level(level)])
	if lines.size() == 1:
		return ""
	return "\n".join(lines)


func _buy_research(research_id: String) -> void:
	var slot: Dictionary = save_slots[selected_save_slot]
	var current_level := _research_level(slot, research_id)
	var max_level := int(research_defs[research_id]["max_level"])
	if current_level >= max_level:
		return
	var cost := _research_next_cost(slot, research_id)
	if int(slot["total_chips"]) < cost:
		return
	slot["total_chips"] = int(slot["total_chips"]) - cost
	var levels: Dictionary = slot["research_levels"]
	levels[research_id] = current_level + 1
	slot["research_levels"] = levels
	if not Array(slot["owned_research"]).has(research_id):
		slot["owned_research"].append(research_id)
	total_chips = int(slot["total_chips"])
	save_slots[selected_save_slot] = slot
	_save_save_slots()
	_show_research_center()


func _toggle_research(research_id: String) -> void:
	var slot: Dictionary = save_slots[selected_save_slot]
	var equipped: Array = slot["equipped_research"]
	if equipped.has(research_id):
		equipped.erase(research_id)
	elif equipped.size() < 6:
		equipped.append(research_id)
	slot["equipped_research"] = equipped
	save_slots[selected_save_slot] = slot
	_save_save_slots()
	_show_research_center()


func _spawn_enemy() -> void:
	if not is_instance_valid(player) or _has_alive_boss():
		return
	var enemy := EnemyScene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.target = player
	_configure_enemy_kind(enemy, _roll_spawn_enemy_kind())
	enemy.scale_combat_stats(_get_enemy_growth_multiplier())
	enemy.global_position = _get_spawn_position()
	enemy.died.connect(_on_enemy_died)
	enemy.damaged.connect(_on_enemy_damaged)
	if enemy.has_signal("special_requested"):
		enemy.special_requested.connect(_on_enemy_special_requested)
	spawn_timer.wait_time = max(0.28, 0.9 - elapsed_time / 180.0)


func _get_enemy_growth_multiplier() -> float:
	return pow(1.2, float(int(floor(elapsed_time / 60.0))))


func _roll_spawn_enemy_kind() -> String:
	if elapsed_time >= 45.0 and rng.randf() < 0.12:
		return "elite"
	return "normal"


func _configure_enemy_kind(enemy: Node, enemy_kind: String) -> void:
	enemy.enemy_kind = enemy_kind
	match enemy_kind:
		"elite":
			enemy.max_health *= 3
			enemy.health = enemy.max_health
			enemy.speed *= ELITE_ENEMY_SPEED_MULTIPLIER
			enemy.touch_damage = max(1, int(round(float(enemy.touch_damage) * 1.5)))
			enemy.xp_value *= 2
		"headhunter":
			enemy.max_health *= 15
			enemy.health = enemy.max_health
			enemy.speed *= ELITE_ENEMY_SPEED_MULTIPLIER * 2.5
			enemy.touch_damage *= 3
			enemy.contact_distance *= 1.5
			enemy.separation_distance *= 1.5
			enemy.xp_value *= 5
		"boss":
			enemy.max_health *= 18
			enemy.health = enemy.max_health
			enemy.speed = float(player.speed) * 0.8 if is_instance_valid(player) else enemy.speed * 0.68
			enemy.touch_damage *= 3
			enemy.contact_distance = BOSS_BODY_RADIUS * 2.0
			enemy.separation_distance = BOSS_BODY_RADIUS * 1.85
			enemy.xp_value *= 10
		_:
			enemy.speed *= NORMAL_ENEMY_SPEED_MULTIPLIER


func _check_boss_spawn() -> void:
	while boss_spawn_index < BOSS_SPAWN_TIMES.size() and elapsed_time >= float(BOSS_SPAWN_TIMES[boss_spawn_index]):
		boss_spawn_index += 1
		_spawn_boss()


func _spawn_boss() -> void:
	if not is_instance_valid(player):
		return
	var enemy := EnemyScene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.target = player
	_configure_enemy_kind(enemy, "boss")
	enemy.scale_combat_stats(_get_enemy_growth_multiplier())
	enemy.global_position = _get_spawn_position(EDGE_BOSS_SPAWN_TILES)
	enemy.died.connect(_on_enemy_died)
	enemy.damaged.connect(_on_enemy_damaged)
	if enemy.has_signal("special_requested"):
		enemy.special_requested.connect(_on_enemy_special_requested)
	_show_top_notice("Boss 出現！擊敗 Boss 才能通關", Color(1.0, 0.18, 0.12))
	_update_spawn_timer_by_boss_presence()


func _check_headhunter_spawn() -> void:
	if elapsed_time < next_headhunter_time or _has_alive_boss():
		return
	while elapsed_time >= next_headhunter_time:
		next_headhunter_time += 180.0
	if _has_enemy_kind("headhunter"):
		return
	_spawn_headhunter()


func _spawn_headhunter() -> void:
	if not is_instance_valid(player):
		return
	var enemy := EnemyScene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.target = player
	_configure_enemy_kind(enemy, "headhunter")
	enemy.scale_combat_stats(_get_enemy_growth_multiplier())
	enemy.global_position = _get_spawn_position(EDGE_BOSS_SPAWN_TILES)
	enemy.died.connect(_on_enemy_died)
	enemy.damaged.connect(_on_enemy_damaged)
	if enemy.has_signal("special_requested"):
		enemy.special_requested.connect(_on_enemy_special_requested)
	_show_top_notice("⚠ 獵頭已鎖定你！", Color(0.2, 1.0, 0.35))


func _get_spawn_position(edge_margin_tiles := 1.4) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var half_size := viewport_size * 0.5
	var margin := edge_margin_tiles * TILE_SIZE
	var side := rng.randi_range(0, 3)
	var offset := Vector2.ZERO
	match side:
		0:
			offset = Vector2(rng.randf_range(-half_size.x, half_size.x), -half_size.y - margin)
		1:
			offset = Vector2(rng.randf_range(-half_size.x, half_size.x), half_size.y + margin)
		2:
			offset = Vector2(-half_size.x - margin, rng.randf_range(-half_size.y, half_size.y))
		_:
			offset = Vector2(half_size.x + margin, rng.randf_range(-half_size.y, half_size.y))
	return player.global_position + offset


func _check_difficulty_minute() -> void:
	var current_minute := int(floor(elapsed_time / 60.0))
	if current_minute <= last_difficulty_minute:
		return
	last_difficulty_minute = current_minute
	_show_top_notice("難度提升", Color(1.0, 0.25, 0.16))
	_update_slot_ui()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("scale_combat_stats"):
			enemy.scale_combat_stats(1.2)


func _has_alive_boss() -> bool:
	return _has_enemy_kind("boss")


func _has_enemy_kind(enemy_kind: String) -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and str(enemy.enemy_kind) == enemy_kind:
			return true
	return false


func _update_spawn_timer_by_boss_presence() -> void:
	if spawn_timer == null:
		return
	var should_pause_spawns := _has_alive_boss()
	if should_pause_spawns == boss_spawn_paused:
		return
	boss_spawn_paused = should_pause_spawns
	if boss_spawn_paused:
		spawn_timer.stop()
	else:
		spawn_timer.start()


func _process_passive_abilities(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var aura_level: int = player.get_skill_level("aura_ring")
	if aura_level > 0:
		aura_timer -= delta
		if aura_timer <= 0.0:
			aura_timer = 0.25
			_apply_aura_damage(aura_level)
	var energy_level: int = player.get_skill_level("energy_attack")
	if energy_level > 0:
		energy_attack_timer -= delta
		if energy_attack_timer <= 0.0:
			energy_attack_timer = 60.0 * pow(0.85, energy_level - 1)
			_trigger_energy_attack()
	_process_small_skill_passives(delta)


func _process_small_skill_passives(delta: float) -> void:
	for skill_id in SMALL_SKILL_INTERVALS.keys():
		if not is_instance_valid(player) or not player.has_method("get_small_skill_level"):
			return
		var level: int = player.get_small_skill_level(str(skill_id))
		if level <= 0:
			continue
		var timer := float(small_skill_timers.get(skill_id, SMALL_SKILL_INTERVALS[skill_id])) - delta
		if timer <= 0.0:
			timer = float(SMALL_SKILL_INTERVALS[skill_id])
			_trigger_small_symbol(str(skill_id))
		small_skill_timers[skill_id] = timer


func _process_status_effects(delta: float) -> void:
	var to_clear := []
	for enemy in burning_enemies.keys():
		if not is_instance_valid(enemy):
			to_clear.append(enemy)
			continue
		var data: Dictionary = burning_enemies[enemy]
		data["time"] = float(data["time"]) - delta
		data["tick"] = float(data["tick"]) - delta
		if float(data["tick"]) <= 0.0:
			data["tick"] = 1.0
			enemy.take_damage(int(data["damage"]))
			_show_damage_number(enemy.global_position, int(data["damage"]))
		if float(data["time"]) <= 0.0:
			to_clear.append(enemy)
		else:
			burning_enemies[enemy] = data
	for enemy in to_clear:
		burning_enemies.erase(enemy)


func _start_electric_fence() -> void:
	if electric_fence_active or not is_instance_valid(player):
		return
	electric_fence_active = true
	electric_fence_center = player.global_position
	var half_size := get_viewport_rect().size * 0.5
	electric_fence_half_extents = half_size + Vector2.ONE * ELECTRIC_FENCE_START_MARGIN_TILES * TILE_SIZE
	electric_fence_shrink_timer = ELECTRIC_FENCE_SHRINK_INTERVAL
	electric_fence_damage_timer = ELECTRIC_FENCE_DAMAGE_INTERVAL
	_show_top_notice("電流柵欄啟動，擊敗 Boss 才能通關", Color(0.35, 0.75, 1.0))
	_update_electric_fence_visual()


func _process_electric_fence(delta: float) -> void:
	if not electric_fence_active:
		return
	electric_fence_shrink_timer -= delta
	if electric_fence_shrink_timer <= 0.0:
		electric_fence_shrink_timer += ELECTRIC_FENCE_SHRINK_INTERVAL
		electric_fence_half_extents.x = max(TILE_SIZE * 2.0, electric_fence_half_extents.x - ELECTRIC_FENCE_SHRINK_AMOUNT)
		electric_fence_half_extents.y = max(TILE_SIZE * 2.0, electric_fence_half_extents.y - ELECTRIC_FENCE_SHRINK_AMOUNT)
		_update_electric_fence_visual()
	electric_fence_damage_timer -= delta
	if electric_fence_damage_timer > 0.0:
		return
	electric_fence_damage_timer += ELECTRIC_FENCE_DAMAGE_INTERVAL
	_apply_electric_fence_damage()


func _update_electric_fence_visual() -> void:
	if is_instance_valid(electric_fence_line):
		electric_fence_line.queue_free()
	var left := electric_fence_center.x - electric_fence_half_extents.x
	var right := electric_fence_center.x + electric_fence_half_extents.x
	var top := electric_fence_center.y - electric_fence_half_extents.y
	var bottom := electric_fence_center.y + electric_fence_half_extents.y
	electric_fence_line = Line2D.new()
	electric_fence_line.width = 10.0
	electric_fence_line.default_color = Color(0.1, 0.55, 1.0, 0.85)
	electric_fence_line.closed = true
	electric_fence_line.points = PackedVector2Array([
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right, bottom),
		Vector2(left, bottom)
	])
	add_child(electric_fence_line)


func _apply_electric_fence_damage() -> void:
	if is_instance_valid(player) and not _is_inside_electric_fence(player.global_position):
		player.take_damage(max(1, int(round(float(player.max_health) * 0.2))))
		_knock_node_into_fence(player)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var kind := str(enemy.enemy_kind)
		if kind == "boss" or kind == "headhunter":
			continue
		if _is_inside_electric_fence(enemy.global_position):
			continue
		var max_health_value: Variant = enemy.get("max_health")
		var enemy_max_health: int = int(max_health_value) if max_health_value != null else 10
		if enemy.has_method("take_damage"):
			enemy.take_damage(max(1, int(round(float(enemy_max_health) * 0.2))))
		_knock_node_into_fence(enemy)


func _is_inside_electric_fence(position: Vector2) -> bool:
	return (
		position.x >= electric_fence_center.x - electric_fence_half_extents.x
		and position.x <= electric_fence_center.x + electric_fence_half_extents.x
		and position.y >= electric_fence_center.y - electric_fence_half_extents.y
		and position.y <= electric_fence_center.y + electric_fence_half_extents.y
	)


func _knock_node_into_fence(node: Node2D) -> void:
	var direction := (electric_fence_center - node.global_position).normalized()
	if direction.length() <= 0.001:
		direction = Vector2.RIGHT
	node.global_position += direction * ELECTRIC_FENCE_KNOCKBACK


func _apply_aura_damage(level: int) -> void:
	var radius := 3.0 * TILE_SIZE
	var damage := int(round(30.0 * (1.0 + 0.2 * float(level - 1)) * 0.25 * 0.8))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if player.global_position.distance_to(enemy.global_position) <= radius:
			enemy.take_damage(damage)
			_show_damage_number(enemy.global_position, damage)


func _trigger_energy_attack() -> void:
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.64)))
	for enemy in _get_visible_enemies():
		enemy.take_damage(damage)
		_show_damage_number(enemy.global_position, damage)
	_show_area_effect(player.global_position, 430.0, Color(1.0, 0.82, 0.15, 0.32))


func _get_visible_enemies() -> Array[Node2D]:
	var visible_enemies: Array[Node2D] = []
	if not is_instance_valid(player):
		return visible_enemies
	var half_size := get_viewport_rect().size * 0.5
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		var relative_position: Vector2 = enemy.global_position - player.global_position
		if abs(relative_position.x) <= half_size.x and abs(relative_position.y) <= half_size.y:
			visible_enemies.append(enemy)
	return visible_enemies


func _get_random_visible_position(edge_margin := 0.0) -> Vector2:
	if not is_instance_valid(player):
		return Vector2.ZERO
	var half_size := get_viewport_rect().size * 0.5
	return player.global_position + Vector2(
		rng.randf_range(-half_size.x + edge_margin, half_size.x - edge_margin),
		rng.randf_range(-half_size.y + edge_margin, half_size.y - edge_margin)
	)


func _spin_slot() -> void:
	if is_slot_spinning or not game_started or get_tree().paused:
		return
	var slot_cost := _get_slot_cost()
	if not player.spend_token(slot_cost):
		slot_result_label.text = "Slot 代幣不足，無法轉動。"
		_update_slot_ui()
		slot_result_label.text = "Slot 代幣不足，無法轉動。"
		return
	is_slot_spinning = true
	slot_spin_button.disabled = true
	slot_result_label.text = "轉輪中..."
	for tick in range(6):
		for reel in slot_reel_labels:
			reel.text = _symbol_name(_roll_weighted_symbol())
		await get_tree().create_timer(0.08).timeout
	var result := _roll_slot_result()
	for index in range(3):
		slot_reel_labels[index].text = _symbol_name(result[index])
	var opened_reward_menu := _resolve_slot_result(result)
	if not opened_reward_menu and not get_tree().paused and _should_free_reroll():
		slot_result_label.text += "\n重抽率發動，免費重抽！"
		_show_slot_popup("重抽率發動：免費重抽")
		result = _roll_slot_result()
		for index in range(3):
			slot_reel_labels[index].text = _symbol_name(result[index])
		_resolve_slot_result(result)
	is_slot_spinning = false
	slot_spin_button.disabled = player.slot_tokens < _get_slot_cost()
	_update_slot_ui()
	if pending_level_choices > 0 and not get_tree().paused and not _get_available_upgrade_ids().is_empty():
		_show_level_up_choices()


func _get_slot_cost() -> int:
	return SLOT_BASE_TOKEN_COST + int(floor(elapsed_time / 60.0)) * SLOT_COST_PER_MINUTE


func _set_auto_spin(enabled: bool) -> void:
	auto_spin_enabled = enabled
	if slot_auto_button != null:
		slot_auto_button.text = "Auto：開" if enabled else "Auto：關"


	if slot_auto_button != null:
		slot_auto_button.text = "Auto：開" if enabled else "Auto：關"


func _roll_weighted_symbol() -> String:
	var total := 0.0
	for symbol_id in slot_symbols.keys():
		total += _slot_symbol_weight(str(symbol_id))
	var roll := rng.randf_range(0.0, total)
	var running := 0.0
	for symbol_id in slot_symbols.keys():
		running += _slot_symbol_weight(str(symbol_id))
		if roll <= running:
			return symbol_id
	return "J"


func _roll_slot_result() -> Array:
	var result := [_roll_weighted_symbol(), _roll_weighted_symbol(), _roll_weighted_symbol()]
	_limit_wild_count(result)
	_apply_base_line_bonus(result)
	_limit_wild_count(result)
	_apply_line_rate_to_result(result)
	_limit_wild_count(result)
	return result


func _limit_wild_count(result: Array) -> void:
	var found_wild := false
	for index in range(result.size()):
		if str(result[index]) != "WILD":
			continue
		if not found_wild:
			found_wild = true
		else:
			result[index] = _roll_non_wild_symbol()


func _roll_non_wild_symbol() -> String:
	var choices := ["J", "Q", "K", "A", "7"]
	return str(choices[rng.randi_range(0, choices.size() - 1)])


func _slot_symbol_weight(symbol_id: String) -> float:
	var weight := float(slot_symbols[symbol_id]["weight"])
	if symbol_id == "7":
		weight *= 1.05
		weight *= 1.0 + 0.07 * float(player.get_upgrade_skill_level("jackpot_rate"))
	elif symbol_id == "WILD":
		weight *= 1.0 + 0.07 * float(player.get_upgrade_skill_level("fragment_amount"))
	return weight


func _get_slot_probability_multiplier() -> float:
	var minute_step: int = clamp(int(floor(elapsed_time / 60.0)), 0, 9)
	return 1.0 + (SLOT_PROBABILITY_MAX_MULTIPLIER - 1.0) * float(minute_step) / 9.0


func _apply_base_line_bonus(result: Array) -> void:
	if _is_slot_jackpot(result) or _is_slot_small_win(result):
		return
	var roll := rng.randf()
	var probability_multiplier: float = _get_slot_probability_multiplier()
	var three_line_chance: float = min(0.95, BASE_THREE_LINE_CHANCE * probability_multiplier)
	var two_line_chance: float = min(0.95 - three_line_chance, BASE_TWO_LINE_CHANCE * probability_multiplier)
	if roll < three_line_chance:
		var symbol_id: String = _roll_weighted_symbol()
		if symbol_id == "WILD":
			var wild_index := rng.randi_range(0, result.size() - 1)
			for index in range(result.size()):
				result[index] = "WILD" if index == wild_index else "7"
		else:
			for index in range(result.size()):
				result[index] = symbol_id
	elif roll < three_line_chance + two_line_chance:
		var symbol_id: String = SLOT_BASE_SYMBOLS[rng.randi_range(0, SLOT_BASE_SYMBOLS.size() - 1)]
		var wild_index := rng.randi_range(0, result.size() - 1)
		for index in range(result.size()):
			result[index] = "WILD" if index == wild_index else symbol_id


func _apply_line_rate_to_result(result: Array) -> void:
	var line_level: int = player.get_upgrade_skill_level("line_rate")
	if line_level <= 0 or _is_slot_jackpot(result) or _is_slot_small_win(result) or rng.randf() >= 0.07 * float(line_level):
		return
	var symbol_id := ""
	for candidate in SLOT_BASE_SYMBOLS:
		if result.count(candidate) >= 2:
			symbol_id = candidate
			break
	if symbol_id.is_empty():
		symbol_id = SLOT_BASE_SYMBOLS[rng.randi_range(0, SLOT_BASE_SYMBOLS.size() - 1)]
	var wild_index := rng.randi_range(0, result.size() - 1)
	for index in range(result.size()):
		result[index] = "WILD" if index == wild_index else symbol_id


func _should_free_reroll() -> bool:
	var reroll_level: int = player.get_upgrade_skill_level("reroll_rate")
	return reroll_level > 0 and rng.randf() < 0.10 * float(reroll_level)


func _resolve_slot_result(result: Array) -> bool:
	if _is_slot_jackpot(result):
		slot_result_label.text = "777 大獎！選擇一個永久技能"
		_show_slot_reward_choices("jackpot")
		return true
	var small_symbol := _get_small_win_symbol(result)
	if not small_symbol.is_empty():
		slot_result_label.text = "%s 連線！選擇一個小獎攻擊" % small_symbol
		_show_slot_reward_choices("small")
		return true
	slot_result_label.text = "未中獎"
	_apply_consolation()
	return false


func _is_slot_jackpot(result: Array) -> bool:
	if result.size() != 3:
		return false
	var seven_count := 0
	var wild_count := 0
	for symbol in result:
		if str(symbol) == "7":
			seven_count += 1
		elif str(symbol) == "WILD":
			wild_count += 1
		else:
			return false
	return seven_count >= 2 and wild_count <= 1


func _is_slot_small_win(result: Array) -> bool:
	return not _get_small_win_symbol(result).is_empty()


func _get_small_win_symbol(result: Array) -> String:
	if result.size() != 3:
		return ""
	for symbol_id in SLOT_BASE_SYMBOLS:
		var symbol_count := 0
		var wild_count := 0
		for result_symbol in result:
			if str(result_symbol) == symbol_id:
				symbol_count += 1
			elif str(result_symbol) == "WILD":
				wild_count += 1
		if wild_count > 1:
			return ""
		if symbol_count == 3 or (symbol_count == 2 and wild_count == 1):
			return symbol_id
	return ""


func _show_slot_reward_choices(reward_kind: String) -> void:
	if not game_started or not is_instance_valid(player):
		return
	var choices := _get_slot_reward_choices(reward_kind)
	if choices.is_empty():
		_apply_slot_reward_fallback()
		return
	is_slot_reward_menu_open = true
	current_slot_reward_kind = reward_kind
	get_tree().paused = true
	slot_reward_overlay.visible = true
	var box := _get_menu_box(slot_reward_overlay)
	_clear_menu_dynamic_children(box)

	var info := Label.new()
	info.text = "選擇 1 個%s。" % ("永久技能" if reward_kind == "jackpot" else "小獎攻擊")
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)

	for skill_id in choices:
		_add_rich_choice_button(box, _format_slot_reward_choice_bbcode(str(skill_id), reward_kind), _choose_slot_reward.bind(str(skill_id), reward_kind))


func _get_slot_reward_choices(reward_kind: String) -> Array[String]:
	var pool: Array[String] = []
	if reward_kind == "jackpot":
		pool.assign(SLOT_JACKPOT_REWARD_IDS)
	else:
		for skill_id in SLOT_SMALL_REWARD_IDS:
			if player.get_small_skill_level(str(skill_id)) < 5:
				pool.append(str(skill_id))
	pool.shuffle()
	var choices: Array[String] = []
	for skill_id in pool:
		choices.append(str(skill_id))
		if choices.size() >= 3:
			break
	return choices


func _format_slot_reward_choice(skill_id: String, reward_kind: String) -> String:
	if reward_kind == "jackpot":
		var level: int = player.get_skill_level(skill_id)
		if level >= 5:
			return "%s LV MAX\n已滿級：回復 30%% HP 或 Token +5" % _skill_name(skill_id)
		return "%s %s -> %s\n%s" % [_skill_name(skill_id), _format_skill_level(level), _format_skill_level(level + 1), _slot_reward_effect_text(skill_id)]
	var small_level: int = player.get_small_skill_level(skill_id)
	return "%s %s -> %s\n%s" % [_skill_name(skill_id), _format_skill_level(small_level), _format_skill_level(small_level + 1), _slot_reward_effect_text(skill_id)]


func _add_rich_choice_button(box: VBoxContainer, bbcode_text: String, callback: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(680.0, 86.0)
	button.text = ""
	button.pressed.connect(callback)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = bbcode_text
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 16.0
	label.offset_top = 8.0
	label.offset_right = -16.0
	label.offset_bottom = -8.0
	button.add_child(label)
	box.add_child(button)


func _format_slot_reward_choice_bbcode(skill_id: String, reward_kind: String) -> String:
	if reward_kind == "jackpot":
		var level: int = player.get_skill_level(skill_id)
		if level >= 5:
			return "%s LV MAX\n已滿級：回復 [color=yellow]30%% HP[/color] 或 [color=yellow]Token +5[/color]" % _skill_name(skill_id)
		return "%s %s → %s\n%s" % [
			_skill_name(skill_id),
			_format_skill_level(level),
			_format_skill_level(level + 1),
			_jackpot_reward_effect_bbcode(skill_id, level, level + 1)
		]
	var small_level: int = player.get_small_skill_level(skill_id)
	return "%s %s → %s\n%s" % [
		_skill_name(skill_id),
		_format_skill_level(small_level),
		_format_skill_level(small_level + 1),
		_small_reward_effect_bbcode(skill_id, small_level, small_level + 1)
	]


func _small_reward_effect_bbcode(skill_id: String, current_level: int, next_level: int) -> String:
	var current_multiplier := _small_skill_display_multiplier(current_level)
	var next_multiplier := _small_skill_display_multiplier(next_level)
	match skill_id:
		"bomb":
			return "目標 [color=yellow]%s[/color] → [color=yellow]%s[/color]；周圍 [color=yellow]%s[/color] → [color=yellow]%s[/color]" % [
				_format_percent(100.0 * current_multiplier),
				_format_percent(100.0 * next_multiplier),
				_format_percent(75.0 * current_multiplier),
				_format_percent(75.0 * next_multiplier)
			]
		"thunder":
			return "傷害 [color=yellow]%s[/color] → [color=yellow]%s[/color]；最多 7 道" % [
				_format_percent(50.0 * current_multiplier),
				_format_percent(50.0 * next_multiplier)
			]
		"fire":
			return "每秒傷害 [color=yellow]%s[/color] → [color=yellow]%s[/color]；燃燒 3 秒" % [
				_format_percent(7.0 * current_multiplier),
				_format_percent(7.0 * next_multiplier)
			]
		"ice":
			return "傷害 [color=yellow]%s[/color] → [color=yellow]%s[/color]；緩速秒數 [color=yellow]%d秒[/color] → [color=yellow]%d秒[/color]" % [
				_format_percent(50.0 * current_multiplier),
				_format_percent(50.0 * next_multiplier),
				0 if current_level <= 0 else 3 + current_level - 1,
				3 + next_level - 1
			]
		"missile":
			return "每枚傷害 [color=yellow]%s[/color] → [color=yellow]%s[/color]；10 枚" % [
				_format_percent(30.0 * current_multiplier),
				_format_percent(30.0 * next_multiplier)
			]
	return _slot_reward_effect_text(skill_id)


func _jackpot_reward_effect_bbcode(skill_id: String, current_level: int, next_level: int) -> String:
	match skill_id:
		"aura_ring":
			return "刺環傷害已套用 -20%；目前 [color=yellow]%s[/color] → 下級 [color=yellow]%s[/color]" % [_format_skill_level(current_level), _format_skill_level(next_level)]
		"energy_attack":
			return "能量攻擊傷害 [color=yellow]64%玩家傷害[/color]，冷卻隨等級縮短。"
		"slot_777":
			return "爆炸傷害已套用 -20%；LV1 為 [color=yellow]80%玩家傷害[/color]。"
		"bounce":
			return "彈射傷害為 [color=yellow]80%玩家攻擊傷害[/color]。"
		"multishot":
			return "額外投射物傷害為 [color=yellow]80%玩家攻擊傷害[/color]。"
	return _slot_reward_effect_text(skill_id)


func _small_skill_display_multiplier(level: int) -> float:
	if level <= 0:
		return 0.0
	return 1.0 + 0.25 * float(level - 1)


func _format_percent(value: float) -> String:
	if abs(value - round(value)) < 0.01:
		return "%d%%" % int(round(value))
	return "%.1f%%" % value


func _slot_reward_effect_text(skill_id: String) -> String:
	match skill_id:
		"bomb":
			return "每 3 秒自動爆炸：目標 100%，周圍 3 格 75%。"
		"thunder":
			return "每 5 秒自動落雷，最多 7 道，每道 50%。"
		"fire":
			return "每 10 秒讓可視怪燃燒 3 秒，每秒 7%。"
		"ice":
			return "每 5 秒打出 45 度冰霜扇形，傷害 50%，緩速 50%。"
		"missile":
			return "每 5 秒發射飛彈轟炸，每枚 30%。"
		"lucky_cat":
			return "召喚招財貓撿 Token / 晶片並攻擊。"
		"bounce":
			return "玩家攻擊會額外彈射。"
		"multishot":
			return "玩家每次攻擊增加投射物。"
		"slot_777":
			return "每第 3 次攻擊造成爆炸。"
		"energy_attack":
			return "每 60 秒對可視怪造成能量攻擊。"
		"aura_ring":
			return "玩家周圍產生持續傷害刺環。"
	return ""


func _choose_slot_reward(skill_id: String, reward_kind: String) -> void:
	if not is_instance_valid(player):
		return
	if reward_kind == "jackpot":
		if player.get_skill_level(skill_id) >= 5:
			_apply_slot_reward_fallback()
		else:
			var upgraded: bool = player.grant_jackpot_skill(skill_id)
			if upgraded and skill_id == "lucky_cat":
				_sync_lucky_cats()
			slot_result_label.text = "%s升到 %s" % [_skill_name(skill_id), _format_skill_level(player.get_skill_level(skill_id))]
			_show_slot_popup(slot_result_label.text)
	else:
		var upgraded: bool = player.grant_small_skill(skill_id)
		if upgraded:
			small_skill_timers[skill_id] = float(SMALL_SKILL_INTERVALS.get(skill_id, 5.0))
			slot_result_label.text = "%s升到 %s" % [_skill_name(skill_id), _format_skill_level(player.get_small_skill_level(skill_id))]
			_show_slot_popup(slot_result_label.text)
		else:
			_apply_slot_reward_fallback()
	is_slot_reward_menu_open = false
	current_slot_reward_kind = ""
	slot_reward_overlay.visible = false
	_update_ui()
	if pending_level_choices > 0 and not _get_available_upgrade_ids().is_empty():
		_show_level_up_choices()
	else:
		get_tree().paused = false


func _apply_slot_reward_fallback() -> void:
	if rng.randi_range(0, 1) == 0:
		var heal_amount: int = max(1, int(round(float(player.max_health) * 0.3)))
		player.heal(heal_amount)
		slot_result_label.text = "滿級補償：回復 %d HP" % heal_amount
	else:
		player.add_token(5)
		slot_result_label.text = "滿級補償：Token +5"
	_show_slot_popup(slot_result_label.text)


func _trigger_small_symbol(symbol_id: String) -> void:
	match symbol_id:
		"bomb":
			_trigger_bomb()
		"thunder":
			_trigger_thunder()
		"fire":
			_trigger_fire()
		"ice":
			_trigger_ice()
		"missile":
			_trigger_missile()


func _small_skill_damage_multiplier(symbol_id: String) -> float:
	if not is_instance_valid(player) or not player.has_method("get_small_skill_level"):
		return 1.0
	var level: int = player.get_small_skill_level(symbol_id)
	if level <= 1:
		return 1.0
	return 1.0 + 0.25 * float(level - 1)


func _apply_consolation() -> void:
	var roll := rng.randi_range(0, 1)
	match roll:
		0:
			var heal_amount: int = max(1, int(round(float(player.max_health) * 0.3)))
			player.heal(heal_amount)
			slot_result_label.text = "未中獎，獲得安慰獎：回復最大生命 30%。"
			_show_slot_popup("安慰獎：回復 %d HP" % heal_amount)
		_:
			var exp_amount: int = max(1, int(round(float(player.experience_to_next) * 0.3)))
			player.add_experience(exp_amount)
			slot_result_label.text = "未中獎，獲得安慰獎：增加目前升級需求 30% 經驗。"
			_show_slot_popup("安慰獎：增加 %d 經驗" % exp_amount)


func _trigger_bomb() -> void:
	var enemies := _get_visible_enemies()
	if enemies.is_empty():
		return
	enemies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return player.global_position.distance_to(a.global_position) < player.global_position.distance_to(b.global_position)
	)
	var target: Node2D = enemies[0]
	var center := target.global_position
	var skill_multiplier := _small_skill_damage_multiplier("bomb")
	var primary_damage: int = max(1, int(round(float(player.attack_damage) * 1.0 * skill_multiplier)))
	var splash_damage: int = max(1, int(round(float(player.attack_damage) * 0.75 * skill_multiplier)))
	var radius := 3.0 * TILE_SIZE
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var damage := primary_damage if enemy == target else splash_damage
		if center.distance_to(enemy.global_position) <= radius:
			enemy.take_damage(damage)
			_show_damage_number(enemy.global_position, damage)
	_show_area_effect(center, radius, Color(1.0, 0.42, 0.08, 0.35))


func _trigger_thunder() -> void:
	var enemies := _get_visible_enemies()
	enemies.shuffle()
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.5 * _small_skill_damage_multiplier("thunder"))))
	for index in range(min(7, enemies.size())):
		var enemy := enemies[index]
		enemy.take_damage(damage)
		_show_damage_number(enemy.global_position, damage)
		_show_lightning_effect(enemy.global_position)


func _trigger_fire() -> void:
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.07 * _small_skill_damage_multiplier("fire"))))
	for enemy in _get_visible_enemies():
		burning_enemies[enemy] = {"time": 3.0, "tick": 1.0, "damage": damage}
	_show_area_effect(player.global_position, 460.0, Color(1.0, 0.22, 0.04, 0.28))


func _trigger_ice() -> void:
	var level: int = max(1, player.get_small_skill_level("ice"))
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.5 * _small_skill_damage_multiplier("ice"))))
	var slow_duration: float = 3.0 + float(level - 1)
	var attack_distance: float = float(player.attack_range) * 2.0
	var aim_direction: Vector2 = _get_nearest_visible_enemy_direction()
	var half_angle: float = deg_to_rad(22.5)
	var hit_points: Array[Vector2] = []
	for enemy in _get_visible_enemies():
		var to_enemy: Vector2 = enemy.global_position - player.global_position
		if to_enemy.length() > attack_distance:
			continue
		var angle: float = abs(aim_direction.angle_to(to_enemy.normalized()))
		if angle <= half_angle:
			enemy.take_damage(damage)
			_show_damage_number(enemy.global_position, damage)
			if enemy.has_method("apply_slow"):
				enemy.apply_slow(0.5, slow_duration)
			hit_points.append(enemy.global_position)
	_show_frost_cone(player.global_position, aim_direction, attack_distance, Color(0.38, 0.88, 1.0, 0.34))


func _trigger_missile() -> void:
	var enemies := _get_visible_enemies()
	if enemies.is_empty():
		return
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.3 * _small_skill_damage_multiplier("missile"))))
	for index in range(10):
		var enemy: Node2D = enemies[index % enemies.size()]
		if not is_instance_valid(enemy):
			continue
		enemy.take_damage(damage)
		_show_damage_number(enemy.global_position, damage)
		_draw_attack_line(player.global_position, enemy.global_position, Color(1.0, 0.2, 0.2, 0.85), 2.0)


func _get_nearest_visible_enemy_direction() -> Vector2:
	var best_direction := Vector2.RIGHT
	var best_distance := INF
	for enemy in _get_visible_enemies():
		var to_enemy: Vector2 = enemy.global_position - player.global_position
		var distance := to_enemy.length()
		if distance < best_distance and distance > 0.001:
			best_distance = distance
			best_direction = to_enemy.normalized()
	return best_direction


func _show_frost_cone(origin: Vector2, direction: Vector2, distance: float, color: Color) -> void:
	var cone := Polygon2D.new()
	var half_angle := deg_to_rad(22.5)
	var points := PackedVector2Array([origin])
	for index in range(12):
		var t := float(index) / 11.0
		var angle := -half_angle + half_angle * 2.0 * t
		points.append(origin + direction.rotated(angle) * distance)
	cone.polygon = points
	cone.color = color
	add_child(cone)
	var tween := create_tween()
	tween.tween_property(cone, "modulate:a", 0.0, 0.28)
	tween.tween_callback(cone.queue_free)


func _on_enemy_special_requested(enemy: Node2D, skill_id: String, target_position: Vector2) -> void:
	if not is_instance_valid(enemy) or not is_instance_valid(player):
		return
	match skill_id:
		"summon_ai":
			_spawn_boss_elites(enemy.global_position, rng.randi_range(20, 30))
		"stock_crash":
			_trigger_boss_stock_crash(target_position)
		"scan_laser":
			_trigger_boss_scan_laser(enemy.global_position, target_position)
		"charge_line":
			_trigger_boss_charge_warning(enemy.global_position, target_position)
		"boss_bullet":
			_spawn_boss_bullet(enemy.global_position, target_position)


func _spawn_boss_elites(origin: Vector2, amount: int) -> void:
	for index in range(amount):
		var enemy := EnemyScene.instantiate()
		enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(enemy)
		enemy.target = player
		_configure_enemy_kind(enemy, "elite")
		enemy.scale_combat_stats(_get_enemy_growth_multiplier())
		enemy.global_position = _get_random_visible_position(48.0)
		enemy.died.connect(_on_enemy_died)
		enemy.damaged.connect(_on_enemy_damaged)
		if enemy.has_signal("special_requested"):
			enemy.special_requested.connect(_on_enemy_special_requested)


func _trigger_boss_charge_warning(origin: Vector2, target_position: Vector2) -> void:
	var direction := (target_position - origin).normalized()
	if direction.length() <= 0.001:
		direction = Vector2.RIGHT
	var path_length: float = max(get_viewport_rect().size.x, get_viewport_rect().size.y) * BOSS_CHARGE_PATH_LENGTH_RATE
	var end_position: Vector2 = origin + direction * path_length
	var line: Line2D = _create_warning_line(origin, end_position, Color(1.0, 0.12, 0.08, 0.55), BOSS_CHARGE_PATH_WIDTH)
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(line):
		line.queue_free()


func _spawn_boss_bullet(origin: Vector2, target_position: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var bullet: Node2D = BossBulletScript.new()
	bullet.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(bullet)
	var bullet_speed: float = float(player.speed) * 1.5
	var bullet_damage: int = max(1, int(round(11.0 * _get_enemy_growth_multiplier())))
	bullet.call("setup", origin, target_position, bullet_speed, bullet_damage, player)


func _trigger_boss_stock_crash(center: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var radius := PLAYER_BODY_RADIUS * 2.0
	var viewport_size := get_viewport_rect().size
	var half_size := viewport_size * 0.5
	var rings: Array[Line2D] = []
	var centers: Array[Vector2] = []
	for index in range(40):
		var target_center := player.global_position + Vector2(rng.randf_range(-half_size.x, half_size.x), rng.randf_range(-half_size.y, half_size.y))
		centers.append(target_center)
		rings.append(_create_warning_circle(target_center, radius, Color(1.0, 0.05, 0.05, 0.55)))
	await get_tree().create_timer(1.5).timeout
	for ring in rings:
		if is_instance_valid(ring):
			ring.queue_free()
	var did_hit_player := false
	for target_center in centers:
		_show_area_effect(target_center, radius, Color(1.0, 0.05, 0.05, 0.38))
		if not did_hit_player and is_instance_valid(player) and player.global_position.distance_to(target_center) <= radius:
			did_hit_player = true
	if did_hit_player and is_instance_valid(player):
		player.take_damage(max(1, int(round(float(player.max_health) * 0.5))))


func _trigger_boss_scan_laser(origin: Vector2, target_position: Vector2) -> void:
	var direction := (target_position - origin).normalized()
	if direction.length() <= 0.001:
		direction = Vector2.RIGHT
	var laser_length: float = max(get_viewport_rect().size.x, get_viewport_rect().size.y) * 3.0
	var end_position: Vector2 = origin + direction * laser_length
	var line: Line2D = _create_warning_line(origin, end_position, Color(1.0, 0.0, 0.0, 0.75), BOSS_SCAN_WARNING_WIDTH)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(line):
		line.queue_free()
	_draw_attack_line(origin, end_position, Color(1.0, 0.05, 0.05, 0.95), BOSS_SCAN_WARNING_WIDTH * 1.7)
	if is_instance_valid(player) and _distance_to_segment(player.global_position, origin, end_position) <= BOSS_SCAN_DAMAGE_WIDTH:
		player.take_damage(max(1, int(round(float(player.max_health) * 0.8))))


func _create_warning_circle(center: Vector2, radius: float, color: Color) -> Line2D:
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = color
	ring.closed = true
	var points := PackedVector2Array()
	for index in range(64):
		var angle := TAU * float(index) / 64.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	ring.points = points
	add_child(ring)
	return ring


func _create_warning_line(from_position: Vector2, to_position: Vector2, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.points = PackedVector2Array([from_position, to_position])
	add_child(line)
	return line


func _distance_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(segment_start)
	var t: float = clamp((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * t)


func _on_enemy_damaged(enemy_kind: String, damage_amount: int) -> void:
	if enemy_kind == "boss":
		boss_damage += damage_amount


func _on_enemy_died(enemy_position: Vector2, xp_value: int, enemy_kind: String) -> void:
	kill_count += 1
	_spawn_drop("xp", xp_value, enemy_position + _random_small_offset())
	var token_amount := _roll_token_drop(enemy_kind)
	if token_amount > 0:
		_spawn_drop("token", token_amount, enemy_position + _random_small_offset())
	var chip_amount := _roll_chip_drop(enemy_kind)
	if chip_amount > 0:
		chip_amount = max(1, int(round(float(chip_amount) * player.chip_drop_multiplier)))
		if enemy_kind == "boss" or enemy_kind == "headhunter":
			player.add_chip(chip_amount)
			_show_pickup_text(enemy_position, "+%d 晶片" % chip_amount, Color(0.2, 0.95, 1.0))
		else:
			_spawn_drop("chip", chip_amount, enemy_position + _random_small_offset())
	if enemy_kind == "boss":
		_show_boss_defeat_effect(enemy_position)
		call_deferred("_update_spawn_timer_by_boss_presence")
		if elapsed_time >= GAME_DURATION_SECONDS and boss_spawn_index >= BOSS_SPAWN_TIMES.size() and not _has_alive_boss():
			call_deferred("_end_game", true)


func _random_small_offset() -> Vector2:
	return Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-18.0, 18.0))


func _roll_chip_drop(enemy_kind: String) -> int:
	match enemy_kind:
		"elite":
			return 1 if rng.randf() < 0.5 else 0
		"headhunter":
			return HEADHUNTER_CHIP_DROP_AMOUNT
		"boss":
			return BOSS_CHIP_DROP_AMOUNT
		_:
			return 0


func _roll_token_drop(enemy_kind: String) -> int:
	var drop_bonus := 0.07 * float(player.get_upgrade_skill_level("cost_rate")) if is_instance_valid(player) else 0.0
	match enemy_kind:
		"elite":
			return 1 if rng.randf() < min(0.95, ELITE_TOKEN_DROP_CHANCE + drop_bonus) else 0
		"headhunter":
			return HEADHUNTER_TOKEN_DROP_AMOUNT
		"boss", "small_boss", "stage_boss":
			return BOSS_TOKEN_DROP_AMOUNT
		_:
			if elapsed_time >= 300.0:
				return 0
			return 1 if rng.randf() < min(0.95, NORMAL_TOKEN_DROP_CHANCE + drop_bonus) else 0


func _spawn_drop(kind: String, amount: int, drop_position: Vector2) -> void:
	var drop := DropScene.instantiate()
	drop.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(drop)
	drop.global_position = drop_position
	drop.setup(kind, amount, player)
	drop.collected.connect(_on_drop_collected)


func _on_drop_collected(kind: String, amount: int) -> void:
	if not is_instance_valid(player):
		return
	if kind == "token":
		player.add_token(amount)
		_show_pickup_text(player.global_position, "+%d Token" % amount, Color(1.0, 0.46, 0.95))
	elif kind == "chip":
		player.add_chip(amount)
		_show_pickup_text(player.global_position, "+%d 晶片" % amount, Color(0.2, 0.95, 1.0))
	else:
		player.add_experience(amount)


func _sync_lucky_cats() -> void:
	while cat_pets.size() < player.get_skill_level("lucky_cat"):
		var pet := CatPetScene.instantiate()
		pet.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(pet)
		var pet_index := cat_pets.size()
		var offset := Vector2(-44.0 - pet_index * 18.0, 34.0 + pet_index * 10.0)
		pet.global_position = player.global_position + offset
		pet.setup(player, offset)
		pet.pet_attack.connect(_on_player_attack_performed)
		cat_pets.append(pet)


func _symbol_name(symbol_id: String) -> String:
	return str(slot_symbols[symbol_id]["name"])


func _skill_name(skill_id: String) -> String:
	match skill_id:
		"bomb":
			return "炸彈"
		"thunder":
			return "落雷"
		"fire":
			return "火焰風暴"
		"ice":
			return "冰霜"
		"missile":
			return "飛彈轟炸"
		"lucky_cat":
			return "招財貓"
		"bounce":
			return "彈射"
		"multishot":
			return "多重"
		"slot_777":
			return "777爆炸"
		"energy_attack", "money_attack":
			return "能量攻擊"
		"aura_ring":
			return "刺環"
		"dice_split":
			return "骰子分裂"
	return skill_id


func _update_slot_ui() -> void:
	if slot_money_label == null or not is_instance_valid(player):
		return
	var slot_cost := _get_slot_cost()
	slot_money_label.text = "Slot代幣：%d" % player.slot_tokens
	slot_cost_label.text = "每次轉動：%d Token｜Space 或按鈕" % slot_cost
	slot_spin_button.disabled = is_slot_spinning or player.slot_tokens < slot_cost


func _show_slot_popup(text: String) -> void:
	if slot_popup_label == null or text.is_empty():
		return
	if slot_popup_tween != null and slot_popup_tween.is_valid():
		slot_popup_tween.kill()
	slot_popup_label.text = text
	slot_popup_label.modulate.a = 1.0
	slot_popup_label.visible = true
	slot_popup_tween = create_tween()
	slot_popup_tween.tween_interval(2.0)
	slot_popup_tween.tween_property(slot_popup_label, "modulate:a", 0.0, 0.25)
	slot_popup_tween.tween_callback(func() -> void:
		slot_popup_label.visible = false
		slot_popup_label.modulate.a = 1.0
	)


func _show_top_notice(text: String, color := Color(1.0, 0.9, 0.22)) -> void:
	if hud_layer == null or text.is_empty():
		return
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_left = 0.0
	label.offset_top = 36.0
	label.offset_right = 0.0
	label.offset_bottom = 96.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	hud_layer.add_child(label)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(label.queue_free)


func _on_player_attack_performed(from_position: Vector2, target_position: Vector2, damage_amount: int) -> void:
	_draw_attack_line(from_position, target_position, Color(1.0, 0.82, 0.25, 0.95), 4.0)
	_show_damage_number(target_position, damage_amount)


func _draw_attack_line(from_position: Vector2, target_position: Vector2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.points = PackedVector2Array([from_position, target_position])
	add_child(line)
	var line_tween := create_tween()
	line_tween.tween_property(line, "modulate:a", 0.0, 0.14)
	line_tween.tween_callback(line.queue_free)


func _show_damage_number(target_position: Vector2, damage_amount: int) -> void:
	var label := Label.new()
	label.text = str(damage_amount)
	label.global_position = target_position + Vector2(-10.0, -46.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.22))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -34.0), 0.45)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.45)
	tween.tween_callback(label.queue_free)


func _show_pickup_text(target_position: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.global_position = target_position + Vector2(-20.0, -64.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -28.0), 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _play_pickup_sound() -> void:
	var player_node := AudioStreamPlayer.new()
	var stream := AudioStreamWAV.new()
	var data := PackedByteArray()
	var sample_count := 1600
	for index in range(sample_count):
		var wave := sin(float(index) * 0.18)
		var envelope := 1.0 - float(index) / float(sample_count)
		data.append(int(clamp(128.0 + wave * 42.0 * envelope, 0.0, 255.0)))
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.data = data
	player_node.stream = stream
	add_child(player_node)
	player_node.play()
	player_node.finished.connect(player_node.queue_free)


func _show_lightning_effect(target_position: Vector2) -> void:
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(1.0, 0.95, 0.18, 0.95)
	line.points = PackedVector2Array([
		target_position + Vector2(-28.0, -280.0),
		target_position + Vector2(18.0, -160.0),
		target_position + Vector2(-12.0, -70.0),
		target_position
	])
	add_child(line)
	var tween := create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.22)
	tween.tween_callback(line.queue_free)


func _show_area_effect(center: Vector2, radius: float, color: Color) -> void:
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = color
	ring.closed = true
	var points := PackedVector2Array()
	for index in range(48):
		var angle := TAU * float(index) / 48.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	ring.points = points
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector2(1.18, 1.18), 0.28)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.28)
	tween.tween_callback(ring.queue_free)


func _show_boss_defeat_effect(center: Vector2) -> void:
	_show_top_notice("Boss 擊破！", Color(1.0, 0.86, 0.22))
	_show_area_effect(center, 180.0, Color(1.0, 0.82, 0.08, 0.45))
	for index in range(10):
		var angle := TAU * float(index) / 10.0
		_draw_attack_line(center, center + Vector2(cos(angle), sin(angle)) * 190.0, Color(1.0, 0.72, 0.18, 0.9), 4.0)


func _on_player_died() -> void:
	_end_game(false)


func _end_game(win: bool) -> void:
	if is_game_ended:
		return
	is_game_ended = true
	did_win = win
	total_chips += player.chip_pickups
	_save_current_slot()
	if not win:
		player.slot_tokens = 0
		player.stats_changed.emit()
	spawn_timer.stop()
	if is_instance_valid(player):
		player.set_physics_process(false)
	game_over_label.visible = true
	game_over_label.text = "過關成功\n按 Space 返回大廳" if did_win else "遊戲失敗\n按 Space 返回大廳"
	settlement_label.visible = true
	settlement_label.text = "%s\n\n生存時間：%s\n擊殺數：%d\nBOSS傷害：%d\n本局獲得晶片：%d\n永久晶片：%d\n\n按 Space 返回大廳" % [
		"過關結算" if did_win else "死亡結算",
		_format_time(elapsed_time),
		kill_count,
		boss_damage,
		player.chip_pickups,
		total_chips
	]
	get_tree().paused = true


func _return_to_lobby_after_run() -> void:
	game_started = false
	is_game_ended = false
	hud_layer.visible = false
	game_over_label.visible = false
	settlement_label.visible = false
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	for drop in get_tree().get_nodes_in_group("drops"):
		if is_instance_valid(drop):
			drop.queue_free()
	electric_fence_active = false
	if is_instance_valid(electric_fence_line):
		electric_fence_line.queue_free()
	electric_fence_line = null
	_show_lobby()


func _format_time(seconds: float) -> String:
	var current_seconds: int = int(floor(seconds))
	var current_minutes: int = current_seconds / 60
	var current_remainder: int = current_seconds % 60
	return "%02d:%02d" % [current_minutes, current_remainder]


func _update_time_ui() -> void:
	if time_label == null:
		return
	var current_seconds: int = int(floor(min(elapsed_time, GAME_DURATION_SECONDS)))
	var current_minutes: int = current_seconds / 60
	var current_remainder: int = current_seconds % 60
	time_label.text = "時間 %02d:%02d / 10:00" % [current_minutes, current_remainder]


func _update_ui() -> void:
	if not is_instance_valid(player) or health_label == null:
		return
	health_label.text = "生命 %d / %d" % [player.health, player.max_health]
	health_bar.max_value = player.max_health
	health_bar.value = player.health
	level_label.text = "等級 %d" % player.level
	exp_label.text = "經驗 %d / %d" % [player.experience, player.experience_to_next]
	exp_bar.max_value = player.experience_to_next
	exp_bar.value = player.experience
	money_label.text = "Slot代幣 %d" % player.slot_tokens
	chip_label.text = "本局晶片 %d｜永久晶片 %d" % [player.chip_pickups, total_chips]
	_update_equipped_hud()
	_update_slot_ui()
