extends Node2D

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy.tscn")
const DropScene := preload("res://scenes/drop.tscn")
const CatPetScene := preload("res://scenes/cat_pet.tscn")

const GAME_DURATION_SECONDS := 600.0
const SAVE_PATH := "user://save_slots.json"
const SAVE_SLOT_COUNT := 5
const BASE_SLOT_COST := 100
const SLOT_COST_INCREASE_PER_MINUTE := 20
const SMALL_FRAGMENT_MAX := 3
const JACKPOT_FRAGMENT_MAX := 10
const TILE_SIZE := 64.0

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
var next_boss_time := 60.0

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
var slot_fragment_label: Label
var slot_skill_label: Label
var slot_popup_label: Label
var hud_equipped_panel: PanelContainer
var hud_equipped_label: Label
var is_slot_spinning := false
var auto_spin_enabled := false
var slot_popup_tween: Tween
var pending_level_choices := 0
var is_level_up_menu_open := false

var money_attack_timer := 60.0
var aura_timer := 0.25
var cat_pets: Array[Node2D] = []
var burning_enemies := {}
var frozen_enemies := {}

var slot_symbols := {
	"bomb": {"name": "炸彈", "weight": 15, "type": "small"},
	"thunder": {"name": "落雷", "weight": 15, "type": "small"},
	"fire": {"name": "火焰風暴", "weight": 15, "type": "small"},
	"ice": {"name": "冰凍", "weight": 15, "type": "small"},
	"missile": {"name": "飛彈轟炸", "weight": 15, "type": "small"},
	"aura_ring": {"name": "刺環", "weight": 10, "type": "jackpot"},
	"bounce": {"name": "彈射", "weight": 10, "type": "jackpot"},
	"multishot": {"name": "多重", "weight": 10, "type": "jackpot"},
	"dice_split": {"name": "骰子分裂", "weight": 4, "type": "jackpot"},
	"slot_777": {"name": "777爆炸", "weight": 4, "type": "jackpot"},
	"money_attack": {"name": "金錢攻擊", "weight": 4, "type": "jackpot"},
	"lucky_cat": {"name": "招財貓", "weight": 4, "type": "jackpot"}
}

var slot_fragments := {}

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
	"cost_rate": {"name": "消耗率", "effect": "Spin 消耗金錢", "per_level": -5, "unit": "%"},
	"fragment_amount": {"name": "碎片量", "effect": "兩連線碎片", "per_level": 1, "unit": "片"},
	"reroll_rate": {"name": "重抽率", "effect": "免費重抽機率", "per_level": 10, "unit": "%"},
	"coin_value": {"name": "金幣倍率", "effect": "每枚金幣價值", "per_level": 3, "unit": "元"},
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
	_init_slot_fragments()
	_load_save_slots()
	_create_world()
	_create_player()
	_create_ui()
	_create_spawn_timer()
	_update_ui()
	_update_time_ui()
	_show_main_menu()


func _process(delta: float) -> void:
	if get_tree().paused or not game_started:
		return

	elapsed_time += delta
	_update_time_ui()
	if elapsed_time >= GAME_DURATION_SECONDS:
		_end_game(true)
		return

	_check_boss_spawn()
	_process_passive_abilities(delta)
	_process_status_effects(delta)
	if auto_spin_enabled and not is_slot_spinning and is_instance_valid(player) and player.money >= _get_slot_cost():
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
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_create_pause_overlay(canvas)
	_create_settings_overlay(canvas)
	_create_confirm_overlay(canvas)

	game_over_label = Label.new()
	game_over_label.visible = false
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 56)
	game_over_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(game_over_label)

	settlement_label = Label.new()
	settlement_label.visible = false
	settlement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settlement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	settlement_label.add_theme_font_size_override("font_size", 28)
	settlement_label.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	slot_popup_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_popup_label.offset_top = 130.0
	canvas.add_child(slot_popup_label)


func _create_fixed_slot_ui(parent: Control) -> void:
	slot_panel = PanelContainer.new()
	slot_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	slot_panel.offset_left = -360.0
	slot_panel.offset_top = 18.0
	slot_panel.offset_right = -18.0
	slot_panel.offset_bottom = 690.0
	parent.add_child(slot_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.custom_minimum_size = Vector2(330.0, 650.0)
	slot_panel.add_child(box)

	var title := Label.new()
	title.text = "戰鬥拉霸"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	slot_money_label = Label.new()
	slot_money_label.add_theme_font_size_override("font_size", 18)
	box.add_child(slot_money_label)

	slot_cost_label = Label.new()
	slot_cost_label.text = "每次轉動：100 money｜Space 或按鈕"
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

	slot_fragment_label = Label.new()
	slot_fragment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(slot_fragment_label)

	slot_skill_label = Label.new()
	slot_skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(slot_skill_label)


func _create_menu_panel(parent: Control, title_text: String, panel_size: Vector2) -> VBoxContainer:
	parent.visible = false
	parent.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
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


func _init_slot_fragments() -> void:
	for symbol_id in slot_symbols.keys():
		slot_fragments[symbol_id] = 0


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
	next_boss_time = 60.0
	money_attack_timer = 60.0
	aura_timer = 0.25
	auto_spin_enabled = false
	is_slot_spinning = false
	burning_enemies.clear()
	frozen_enemies.clear()
	cat_pets.clear()
	_init_slot_fragments()
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
	if not is_level_up_menu_open:
		_show_level_up_choices()


func _show_level_up_choices() -> void:
	if not game_started or not is_instance_valid(player):
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
	info.text = "選擇 1 個技能。技能可重複取得，最高 LV5。"
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
		if player.get_upgrade_skill_level(str(skill_id)) < 5:
			available.append(str(skill_id))
	return available


func _format_upgrade_choice(skill_id: String) -> String:
	var current_level: int = player.get_upgrade_skill_level(skill_id)
	var next_level: int = current_level + 1
	return "%s LV%d -> LV%d\n%s" % [
		str(upgrade_defs[skill_id]["name"]),
		current_level,
		next_level,
		_get_upgrade_skill_effect_text(skill_id, next_level)
	]


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
	match skill_id:
		"crit":
			return "暴擊率 +%d%%" % int(skill_level * 7)
		"jackpot_rate":
			return "大獎圖示出現率 +%d%%" % int(skill_level * 7)
		"cost_rate":
			return "Spin 消耗金錢 -%d%%" % int(skill_level * 5)
		"fragment_amount":
			return "兩連線碎片 +%d片" % skill_level
		"reroll_rate":
			return "免費重抽率 +%d%%" % int(skill_level * 10)
		"coin_value":
			return "每枚金幣 +%d元" % int(skill_level * 3)
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
	hud_equipped_panel.visible = game_started and not text_blocks.is_empty()
	hud_equipped_label.text = "\n\n".join(text_blocks)


func _get_upgrade_skills_text() -> String:
	if not is_instance_valid(player):
		return ""
	var lines := ["升級技能："]
	for skill_id in upgrade_defs.keys():
		var level: int = player.get_upgrade_skill_level(str(skill_id))
		if level <= 0:
			continue
		lines.append("%s LV%d %s" % [str(upgrade_defs[skill_id]["name"]), level, _get_upgrade_skill_effect_text(str(skill_id))])
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
	if not is_instance_valid(player):
		return
	var enemy := EnemyScene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.target = player
	_configure_enemy_kind(enemy, _roll_spawn_enemy_kind())
	enemy.scale_stats(_get_enemy_growth_multiplier())
	enemy.global_position = _get_spawn_position()
	enemy.died.connect(_on_enemy_died)
	enemy.damaged.connect(_on_enemy_damaged)
	spawn_timer.wait_time = max(0.28, 0.9 - elapsed_time / 180.0)


func _get_enemy_growth_multiplier() -> float:
	return 1.0 + float(int(floor(elapsed_time / 60.0))) * 0.3


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
			enemy.speed *= 1.08
			enemy.xp_value *= 2
			enemy.money_value *= 2
		"boss":
			enemy.max_health *= 18
			enemy.health = enemy.max_health
			enemy.speed *= 0.68
			enemy.touch_damage *= 3
			enemy.xp_value *= 10
			enemy.money_value *= 10


func _check_boss_spawn() -> void:
	if elapsed_time >= next_boss_time:
		next_boss_time += 60.0
		_spawn_boss()


func _spawn_boss() -> void:
	if not is_instance_valid(player):
		return
	var enemy := EnemyScene.instantiate()
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy)
	enemy.target = player
	_configure_enemy_kind(enemy, "boss")
	enemy.scale_stats(_get_enemy_growth_multiplier())
	enemy.global_position = _get_spawn_position()
	enemy.died.connect(_on_enemy_died)
	enemy.damaged.connect(_on_enemy_damaged)


func _get_spawn_position() -> Vector2:
	var viewport_size := get_viewport_rect().size
	var half_size := viewport_size * 0.5
	var margin := 90.0
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


func _process_passive_abilities(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var aura_level: int = player.get_skill_level("aura_ring")
	if aura_level > 0:
		aura_timer -= delta
		if aura_timer <= 0.0:
			aura_timer = 0.25
			_apply_aura_damage(aura_level)
	var money_level: int = player.get_skill_level("money_attack")
	if money_level > 0:
		money_attack_timer -= delta
		if money_attack_timer <= 0.0:
			money_attack_timer = 60.0 * pow(0.85, money_level - 1)
			_trigger_money_attack()


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

	to_clear.clear()
	for enemy in frozen_enemies.keys():
		if not is_instance_valid(enemy):
			to_clear.append(enemy)
			continue
		var time_left := float(frozen_enemies[enemy]) - delta
		if time_left <= 0.0:
			enemy.set_physics_process(true)
			to_clear.append(enemy)
		else:
			frozen_enemies[enemy] = time_left
	for enemy in to_clear:
		frozen_enemies.erase(enemy)


func _apply_aura_damage(level: int) -> void:
	var radius := 3.0 * TILE_SIZE
	var damage := int(round(30.0 * (1.0 + 0.2 * float(level - 1)) * 0.25))
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if player.global_position.distance_to(enemy.global_position) <= radius:
			enemy.take_damage(damage)
			_show_damage_number(enemy.global_position, damage)


func _trigger_money_attack() -> void:
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.8)))
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


func _spin_slot() -> void:
	if is_slot_spinning or not game_started or get_tree().paused:
		return
	var slot_cost := _get_slot_cost()
	if not player.spend_money(slot_cost):
		slot_result_label.text = "money 不足，無法轉動。"
		_update_slot_ui()
		return
	is_slot_spinning = true
	slot_spin_button.disabled = true
	slot_result_label.text = "轉輪中..."
	for tick in range(6):
		for reel in slot_reel_labels:
			reel.text = _symbol_name(_roll_weighted_symbol())
		await get_tree().create_timer(0.08).timeout
	var result := [_roll_weighted_symbol(), _roll_weighted_symbol(), _roll_weighted_symbol()]
	_apply_line_rate_to_result(result)
	for index in range(3):
		slot_reel_labels[index].text = _symbol_name(result[index])
	_resolve_slot_result(result)
	if _should_free_reroll():
		slot_result_label.text += "\n重抽率發動，免費重抽！"
		_show_slot_popup("重抽率發動：免費重抽")
		result = [_roll_weighted_symbol(), _roll_weighted_symbol(), _roll_weighted_symbol()]
		_apply_line_rate_to_result(result)
		for index in range(3):
			slot_reel_labels[index].text = _symbol_name(result[index])
		_resolve_slot_result(result)
	is_slot_spinning = false
	slot_spin_button.disabled = player.money < _get_slot_cost()
	_update_slot_ui()


func _get_slot_cost() -> int:
	var raw_cost := BASE_SLOT_COST + int(floor(elapsed_time / 60.0)) * SLOT_COST_INCREASE_PER_MINUTE
	var discount := 1.0 - 0.05 * float(player.get_upgrade_skill_level("cost_rate"))
	return max(1, int(round(float(raw_cost) * discount)))


func _set_auto_spin(enabled: bool) -> void:
	auto_spin_enabled = enabled
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
	return "bomb"


func _slot_symbol_weight(symbol_id: String) -> float:
	var weight := float(slot_symbols[symbol_id]["weight"])
	if str(slot_symbols[symbol_id]["type"]) == "jackpot":
		weight *= 1.0 + 0.07 * float(player.get_upgrade_skill_level("jackpot_rate"))
	return weight


func _apply_line_rate_to_result(result: Array) -> void:
	var line_level: int = player.get_upgrade_skill_level("line_rate")
	if line_level <= 0 or rng.randf() >= 0.07 * float(line_level):
		return
	var counts := {}
	for symbol_id in result:
		counts[symbol_id] = int(counts.get(symbol_id, 0)) + 1
	for symbol_id in counts.keys():
		if int(counts[symbol_id]) == 2:
			for index in range(result.size()):
				if result[index] != symbol_id:
					result[index] = symbol_id
					return
	result[1] = result[0]


func _should_free_reroll() -> bool:
	var reroll_level: int = player.get_upgrade_skill_level("reroll_rate")
	return reroll_level > 0 and rng.randf() < 0.10 * float(reroll_level)


func _resolve_slot_result(result: Array) -> void:
	if result[0] == result[1] and result[1] == result[2]:
		_trigger_symbol(result[0], true)
		return
	var counts := {}
	for symbol_id in result:
		counts[symbol_id] = int(counts.get(symbol_id, 0)) + 1
	for symbol_id in counts.keys():
		if int(counts[symbol_id]) == 2:
			var fragment_gain: int = 2 + player.get_upgrade_skill_level("fragment_amount")
			_add_fragments(symbol_id, fragment_gain)
			slot_result_label.text = "差一格！%s碎片 +%d" % [_symbol_name(symbol_id), fragment_gain]
			return
	_apply_consolation()


func _add_fragments(symbol_id: String, amount: int) -> void:
	slot_fragments[symbol_id] = int(slot_fragments.get(symbol_id, 0)) + amount
	var required := _fragment_required(symbol_id)
	while int(slot_fragments[symbol_id]) >= required:
		slot_fragments[symbol_id] = int(slot_fragments[symbol_id]) - required
		slot_result_label.text = "%s能量滿！自動發動。" % _symbol_name(symbol_id)
		_trigger_symbol(symbol_id, false)


func _fragment_required(symbol_id: String) -> int:
	if str(slot_symbols[symbol_id]["type"]) == "small":
		return SMALL_FRAGMENT_MAX
	return JACKPOT_FRAGMENT_MAX


func _trigger_symbol(symbol_id: String, from_line: bool) -> void:
	var symbol_type := str(slot_symbols[symbol_id]["type"])
	var popup_text := ""
	if symbol_type == "small":
		_trigger_small_symbol(symbol_id)
		if from_line:
			slot_result_label.text = "%s連線！發動%s攻擊。" % [_symbol_name(symbol_id), _symbol_name(symbol_id)]
		popup_text = "發動：%s" % _symbol_name(symbol_id)
	else:
		var upgraded: bool = player.grant_jackpot_skill(symbol_id)
		if symbol_id == "lucky_cat":
			_sync_lucky_cats()
		if upgraded:
			slot_result_label.text = "%s連線！%s升到 LV%d。" % [_symbol_name(symbol_id), _symbol_name(symbol_id), player.get_skill_level(symbol_id)]
			popup_text = "獲得：%s LV%d" % [_symbol_name(symbol_id), player.get_skill_level(symbol_id)]
		else:
			slot_result_label.text = "%s已 LV5，轉為補償：money +100，回復 50 HP。" % _symbol_name(symbol_id)
			popup_text = "%s滿級補償：money +100，回復 50 HP" % _symbol_name(symbol_id)
	_show_slot_popup(popup_text)


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


func _apply_consolation() -> void:
	var roll := rng.randi_range(0, 1)
	match roll:
		0:
			var heal_amount: int = max(1, int(round(float(player.max_health) * 0.5)))
			player.heal(heal_amount)
			slot_result_label.text = "沒連線，獲得安慰獎：回復 50% HP。"
			_show_slot_popup("安慰獎：回復 %d HP" % heal_amount)
		_:
			var exp_amount: int = max(1, int(round(float(player.experience_to_next) * 0.5)))
			player.add_experience(exp_amount)
			slot_result_label.text = "沒連線，獲得安慰獎：增加 50% 經驗。"
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
	var primary_damage: int = max(1, int(round(float(player.attack_damage) * 1.5)))
	var splash_damage: int = max(1, int(round(float(player.attack_damage))))
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
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.7)))
	for index in range(min(7, enemies.size())):
		var enemy := enemies[index]
		enemy.take_damage(damage)
		_show_damage_number(enemy.global_position, damage)
		_show_lightning_effect(enemy.global_position)


func _trigger_fire() -> void:
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.15)))
	for enemy in _get_visible_enemies():
		burning_enemies[enemy] = {"time": 3.0, "tick": 1.0, "damage": damage}
	_show_area_effect(player.global_position, 460.0, Color(1.0, 0.22, 0.04, 0.28))


func _trigger_ice() -> void:
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.45)))
	for enemy in _get_visible_enemies():
		enemy.take_damage(damage)
		_show_damage_number(enemy.global_position, damage)
		enemy.set_physics_process(false)
		frozen_enemies[enemy] = 3.0
	_show_area_effect(player.global_position, 460.0, Color(0.35, 0.85, 1.0, 0.28))


func _trigger_missile() -> void:
	var enemies := _get_visible_enemies()
	if enemies.is_empty():
		return
	var damage: int = max(1, int(round(float(player.attack_damage) * 0.6)))
	for index in range(10):
		var enemy: Node2D = enemies[index % enemies.size()]
		if not is_instance_valid(enemy):
			continue
		enemy.take_damage(damage)
		_show_damage_number(enemy.global_position, damage)
		_draw_attack_line(player.global_position, enemy.global_position, Color(1.0, 0.2, 0.2, 0.85), 2.0)


func _on_enemy_damaged(enemy_kind: String, damage_amount: int) -> void:
	if enemy_kind == "boss":
		boss_damage += damage_amount


func _on_enemy_died(enemy_position: Vector2, xp_value: int, money_value: int, enemy_kind: String) -> void:
	kill_count += 1
	_spawn_drop("xp", xp_value, enemy_position + _random_small_offset())
	var coin_value: int = 5 + player.get_upgrade_skill_level("coin_value") * 3
	var final_money_value: int = max(1, int(round(float(money_value * coin_value) * player.money_drop_multiplier)))
	_spawn_drop("money", final_money_value, enemy_position + _random_small_offset())
	var chip_amount := _roll_chip_drop(enemy_kind)
	if chip_amount > 0:
		chip_amount = max(1, int(round(float(chip_amount) * player.chip_drop_multiplier)))
		_spawn_drop("chip", chip_amount, enemy_position + _random_small_offset())


func _random_small_offset() -> Vector2:
	return Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-18.0, 18.0))


func _roll_chip_drop(enemy_kind: String) -> int:
	match enemy_kind:
		"elite":
			return 1 if rng.randf() < 0.5 else 0
		"boss":
			return 5
		_:
			return 0


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
	if kind == "money":
		player.add_money(amount)
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


func _update_slot_ui() -> void:
	if slot_money_label == null or not is_instance_valid(player):
		return
	var slot_cost := _get_slot_cost()
	slot_money_label.text = "目前 money：%d" % player.money
	slot_cost_label.text = "每次轉動：%d money｜Space 或按鈕" % slot_cost
	slot_spin_button.disabled = is_slot_spinning or player.money < slot_cost
	var fragment_lines := ["碎片進度："]
	for symbol_id in slot_symbols.keys():
		fragment_lines.append("%s %d/%d" % [_symbol_name(symbol_id), int(slot_fragments[symbol_id]), _fragment_required(symbol_id)])
	slot_fragment_label.text = "\n".join(fragment_lines)
	var skill_lines := ["大獎技能："]
	for skill_id in player.jackpot_skills.keys():
		var level: int = player.get_skill_level(skill_id)
		skill_lines.append("%s %s" % [_symbol_name(skill_id), "未取得" if level == 0 else "LV%d/5" % level])
	slot_skill_label.text = "\n".join(skill_lines)


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
		player.money = 0
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
	money_label.text = "金錢 %d" % player.money
	chip_label.text = "本局晶片 %d｜永久晶片 %d" % [player.chip_pickups, total_chips]
	_update_equipped_hud()
	_update_slot_ui()
