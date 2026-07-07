extends Node2D
# ── Boss 頭頂拉霸機 ─────────────────────────────────────────────────────
# 演出流程：彈跳登場 → 三輪高速滾動 → 1.1/1.6/2.1 秒依序定格 →
# 三同時金光震動加強演出 → 發出 finished 訊號回傳三格結果 → 縮小消失。
# 純視覺節點：實際攻擊由 enemy.gd 的 _resolve_slot_results() 處理。

signal finished(results: Array)

var weights: Dictionary = {}          # 符號池 {"seven": 25, ...}
var jackpot_boost := 0.1              # 強制三同機率（終Boss較高）
var _symbols: Array = []
var _reels: Array = ["seven", "seven", "seven"]
var _final: Array = []
var _stopped := [false, false, false]
var _spin_timer := 0.0
var _cycle_timer := 0.0
var _resolving := false
var _done := false
var _jackpot_flash := 0.0
var _font: Font = null
var _rng := RandomNumberGenerator.new()

const STOP_TIMES := [1.1, 1.6, 2.1]


func setup(pool: Dictionary, p_jackpot_boost: float, font: Font) -> void:
	weights = pool
	_symbols = pool.keys()
	jackpot_boost = p_jackpot_boost
	_font = font
	_rng.randomize()
	_final = [_roll(), _roll(), _roll()]
	# Jackpot 加成：以第一輪結果強制三同
	if _rng.randf() < jackpot_boost:
		_final[1] = _final[0]
		_final[2] = _final[0]


func _roll() -> String:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k])
	var r := _rng.randf() * total
	for k in weights.keys():
		r -= float(weights[k])
		if r <= 0.0:
			return str(k)
	return str(_symbols[0])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 30
	scale = Vector2.ONE * 0.1
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _done:
		return
	_spin_timer += delta
	_cycle_timer += delta
	if _jackpot_flash > 0.0:
		_jackpot_flash = maxf(_jackpot_flash - delta, 0.0)
	# 轉輪滾動：未定格的輪每 0.06 秒換一個符號
	if _cycle_timer >= 0.06:
		_cycle_timer = 0.0
		for i in range(3):
			if not _stopped[i]:
				_reels[i] = str(_symbols[_rng.randi_range(0, _symbols.size() - 1)])
	# 依序定格
	for i in range(3):
		if not _stopped[i] and _spin_timer >= float(STOP_TIMES[i]):
			_stopped[i] = true
			_reels[i] = str(_final[i])
	# 全部定格 → 判定 Jackpot 演出 → 回傳結果
	if _stopped[0] and _stopped[1] and _stopped[2] and not _resolving:
		_resolving = true
		var is_jackpot: bool = _final[0] == _final[1] and _final[1] == _final[2]
		if is_jackpot:
			_jackpot_flash = 0.9
		var wait := 0.9 if is_jackpot else 0.35
		var t := get_tree().create_timer(wait, false, false, true)
		t.timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			_done = true
			finished.emit(_final.duplicate())
			var tw := create_tween()
			tw.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
			tw.tween_interval(0.5)
			tw.tween_property(self, "scale", Vector2.ONE * 0.05, 0.25)
			tw.tween_callback(func() -> void:
				if is_instance_valid(self):
					queue_free()
			)
		)
	queue_redraw()


func _draw() -> void:
	var jitter := Vector2.ZERO
	if _jackpot_flash > 0.0:
		jitter = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
	# 機身
	var body := Rect2(Vector2(-80, -48) + jitter, Vector2(160, 82))
	draw_rect(body.grow(3.0), Color(0.85, 0.62, 0.15, 1.0))          # 金框
	draw_rect(body, Color(0.13, 0.10, 0.20, 0.97))                    # 深色機身
	# 頂部跑馬燈
	for i in range(6):
		var lx := body.position.x + 14.0 + float(i) * 26.0
		var on: bool = int(_spin_timer * 8.0 + float(i)) % 2 == 0
		draw_circle(Vector2(lx, body.position.y + 7.0), 4.0,
			Color(1.0, 0.85, 0.25, 1.0) if on else Color(0.45, 0.32, 0.1, 1.0))
	# 三個轉輪窗
	for i in range(3):
		var wx := -52.0 + float(i) * 52.0
		var win := Rect2(Vector2(wx - 22.0, -30.0) + jitter, Vector2(44.0, 52.0))
		draw_rect(win, Color(0.94, 0.92, 0.85, 1.0))
		draw_rect(win, Color(0.55, 0.42, 0.1, 1.0), false, 2.0)
		_draw_symbol(str(_reels[i]), win.get_center(), bool(_stopped[i]))
	# 拉桿
	var lever_base := Vector2(body.end.x + 4.0, body.position.y + 30.0)
	draw_line(lever_base, lever_base + Vector2(10.0, -22.0), Color(0.75, 0.75, 0.8, 1.0), 4.0)
	draw_circle(lever_base + Vector2(10.0, -22.0), 6.0, Color(0.9, 0.2, 0.2, 1.0))
	# Jackpot 金光
	if _jackpot_flash > 0.0:
		draw_rect(body.grow(9.0), Color(1.0, 0.85, 0.2, _jackpot_flash * 0.6), false, 6.0)
		draw_rect(body.grow(16.0), Color(1.0, 0.9, 0.4, _jackpot_flash * 0.3), false, 4.0)


func _draw_symbol(sym: String, center: Vector2, stopped: bool) -> void:
	var alpha := 1.0 if stopped else 0.65
	match sym:
		"seven":
			if _font != null:
				draw_string(_font, center + Vector2(-11.0, 13.0), "7",
					HORIZONTAL_ALIGNMENT_CENTER, 24, 34, Color(0.85, 0.1, 0.1, alpha))
		"bell":
			# 金鐘：上圓＋裙擺＋鐘舌
			var bell_col := Color(0.95, 0.75, 0.15, alpha)
			draw_circle(center + Vector2(0, -6.0), 8.0, bell_col)
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-8.0, -4.0), center + Vector2(8.0, -4.0),
				center + Vector2(13.0, 9.0), center + Vector2(-13.0, 9.0)
			]), bell_col)
			draw_circle(center + Vector2(0, 13.0), 3.5, Color(0.7, 0.5, 0.1, alpha))
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -14.0), center + Vector2(11.0, 0),
				center + Vector2(0, 14.0), center + Vector2(-11.0, 0)
			]), Color(0.25, 0.85, 1.0, alpha))
			draw_polyline(PackedVector2Array([
				center + Vector2(0, -14.0), center + Vector2(11.0, 0),
				center + Vector2(0, 14.0), center + Vector2(-11.0, 0), center + Vector2(0, -14.0)
			]), Color(0.7, 0.97, 1.0, alpha), 1.5)
		"joker":
			if _font != null:
				draw_string(_font, center + Vector2(-13.0, 10.0), "鬼",
					HORIZONTAL_ALIGNMENT_CENTER, 26, 24, Color(0.65, 0.25, 0.9, alpha))
		"cherry":
			# 櫻桃：兩顆紅果＋梗
			draw_line(center + Vector2(-5.0, 6.0), center + Vector2(0, -12.0), Color(0.25, 0.6, 0.2, alpha), 2.5)
			draw_line(center + Vector2(7.0, 8.0), center + Vector2(0, -12.0), Color(0.25, 0.6, 0.2, alpha), 2.5)
			draw_circle(center + Vector2(-5.0, 8.0), 6.5, Color(0.85, 0.12, 0.15, alpha))
			draw_circle(center + Vector2(7.0, 10.0), 6.5, Color(0.9, 0.18, 0.2, alpha))
		"skull":
			# 骷髏：白顱＋黑眼＋齒
			draw_circle(center + Vector2(0, -3.0), 10.0, Color(0.95, 0.95, 0.9, alpha))
			draw_rect(Rect2(center + Vector2(-7.0, 3.0), Vector2(14.0, 8.0)), Color(0.95, 0.95, 0.9, alpha))
			draw_circle(center + Vector2(-4.0, -4.0), 2.8, Color(0.08, 0.08, 0.1, alpha))
			draw_circle(center + Vector2(4.0, -4.0), 2.8, Color(0.08, 0.08, 0.1, alpha))
			for tx in [-4.5, -1.5, 1.5, 4.5]:
				draw_line(center + Vector2(tx, 5.0), center + Vector2(tx, 10.0), Color(0.08, 0.08, 0.1, alpha), 1.4)
