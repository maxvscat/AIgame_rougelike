extends Node2D
# ── Boss 衝擊波（拉霸機「鑽石」符號）─────────────────────────────────────
# 帶缺口的紅色能量環：從 Boss 位置擴張到最大半徑 → 停留 2 秒 → 收縮回中心。
# 玩家需要閃 2 次（擴張時一次、收縮時一次）；站在缺口角度內或環帶外皆安全。

var target: Node2D = null
var max_radius := 1280.0             # 預設 20 格
var band_half_width := 26.0          # 環帶判定半寬（px）
var expand_speed := 880.0            # 擴張/收縮速度（px/秒）
var gap_centers: Array = []          # 缺口中心角（弧度）
var gap_half_width := 0.42           # 缺口半寬（弧度），setup 時覆蓋

var _phase := "expand"               # expand / hold / contract
var _radius := 30.0
var _hold_timer := 2.0
var _hit_done_expand := false
var _hit_done_contract := false


func setup(p_target: Node2D, p_max_radius: float, gap_count: int, gap_half_deg: float) -> void:
	target = p_target
	max_radius = p_max_radius
	gap_half_width = deg_to_rad(gap_half_deg)
	gap_centers.clear()
	# 缺口均勻分布＋隨機擾動，每次施放缺口位置都不同
	var base := randf_range(0.0, TAU)
	for i in range(gap_count):
		gap_centers.append(fposmod(base + TAU * float(i) / float(gap_count) + randf_range(-0.25, 0.25), TAU))


func _ready() -> void:
	add_to_group("transient_effects")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 9


func _process(delta: float) -> void:
	match _phase:
		"expand":
			_radius += expand_speed * delta
			if _radius >= max_radius:
				_radius = max_radius
				_phase = "hold"
			_check_hit(true)
		"hold":
			_hold_timer -= delta
			_check_hit(true)   # 停留期間站在環帶上仍會中
			if _hold_timer <= 0.0:
				_phase = "contract"
		"contract":
			_radius -= expand_speed * delta
			_check_hit(false)
			if _radius <= 24.0:
				queue_free()
				return
	queue_redraw()


func _check_hit(is_expand_phase: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	if is_expand_phase and _hit_done_expand:
		return
	if not is_expand_phase and _hit_done_contract:
		return
	var rel := target.global_position - global_position
	if absf(rel.length() - _radius) > band_half_width + 12.0:
		return
	if _in_gap(rel.angle()):
		return
	if is_expand_phase:
		_hit_done_expand = true
	else:
		_hit_done_contract = true
	target.take_damage(1)


func _in_gap(angle: float) -> bool:
	for g in gap_centers:
		var diff: float = absf(wrapf(angle - float(g), -PI, PI))
		if diff <= gap_half_width:
			return true
	return false


func _draw() -> void:
	if gap_centers.is_empty():
		draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 96, Color(1.0, 0.25, 0.15, 0.9), 20.0)
		return
	var sorted_gaps := gap_centers.duplicate()
	sorted_gaps.sort()
	for i in range(sorted_gaps.size()):
		var a1: float = float(sorted_gaps[i]) + gap_half_width
		var a2: float = float(sorted_gaps[(i + 1) % sorted_gaps.size()]) - gap_half_width
		if i == sorted_gaps.size() - 1:
			a2 += TAU
		if a2 <= a1:
			continue
		var seg: int = maxi(8, int((a2 - a1) / TAU * 96.0))
		# 外光暈＋核心雙層
		draw_arc(Vector2.ZERO, _radius, a1, a2, seg, Color(1.0, 0.55, 0.2, 0.30), 34.0)
		draw_arc(Vector2.ZERO, _radius, a1, a2, seg, Color(1.0, 0.25, 0.15, 0.95), 16.0)
