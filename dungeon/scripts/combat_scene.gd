extends Node2D

# ── state ─────────────────────────────────────────────────────────────────────
var _enemies:     Array = []   # Array[EnemyData]
var _player:      PlayerData
var _defending:   bool  = false
var _player_turn: bool  = true
var _combat_over: bool  = false
var _ai_thinking: bool = false
# ── UI refs ───────────────────────────────────────────────────────────────────
var _enemy_nodes:   Array  = []   # Array[Control] — top-level panels per enemy
var _enemy_hp_bars: Array  = []   # Array[ProgressBar]
var _lbl_phaser:    Label
var _lbl_log:       Label
var _lbl_plr_hp:    Label
var _lbl_plr_mp:    Label
var _btn_attack:    Button
var _btn_magic:     Button
var _btn_defend:    Button
var _log_lines:     Array  = []

# palette
const C_BG_TOP   := Color(0.04, 0.02, 0.10)
const C_BG_BOT   := Color(0.08, 0.04, 0.04)
const C_FLOOR    := Color(0.12, 0.08, 0.06)
const C_STONE    := Color(0.22, 0.18, 0.16)

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_player = GameManager.player
	for type: int in GameManager.pending_enemies:
		_enemies.append(EnemyData.new(type))
	_build_ui()
	_log("Combat begins!")
	if GameManager.is_boss_fight:
		_log("The Demon Lord appears! Watch the pattern hints.")
	if AiBridge.ai_enabled:
			
		var timer := Timer.new()
		timer.wait_time =0.3
		timer.one_shot = true
		timer.timeout.connect(_do_ai_combat_turn)
		add_child(timer)
		timer.start()
		
# ── background drawn procedurally ────────────────────────────────────────────
func _draw() -> void:
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y

	# gradient sky-to-floor
	var steps: int = 40
	for i in range(steps):
		var t: float   = float(i) / float(steps)
		var col: Color = C_BG_TOP.lerp(C_BG_BOT, t)
		var y0: float  = t * vh * 0.62
		var y1: float  = (t + 1.0 / float(steps)) * vh * 0.62
		draw_rect(Rect2(0, y0, vw, y1 - y0 + 1), col)

	# stone floor band
	draw_rect(Rect2(0, vh * 0.62, vw, vh * 0.38), C_FLOOR)

	# floor tiles grid
	var tile_w: float = 64.0
	var tile_h: float = 32.0
	var rows:   int   = int(vh * 0.38 / tile_h) + 2
	var cols:   int   = int(vw / tile_w) + 2
	for r in range(rows):
		for c in range(cols):
			var ox: float = (tile_w * 0.5) if (r % 2 == 1) else 0.0
			var tx: float = c * tile_w - ox
			var ty: float = vh * 0.62 + r * tile_h
			var shade: float = 0.55 + 0.1 * ((r + c) % 2)
			var tc: Color = C_STONE * shade
			draw_rect(Rect2(tx + 1, ty + 1, tile_w - 2, tile_h - 2), tc)

	# dungeon wall back-wall silhouette in the upper section
	_draw_dungeon_wall(vw, vh)

func _draw_dungeon_wall(vw: float, vh: float) -> void:
	var cx: float      = vw * 0.5
	var aw: float      = vw * 0.62
	var ah: float      = vh * 0.58
	var arch_top: float = vh * 0.05

	# side walls
	draw_rect(Rect2(0, 0, cx - aw * 0.5, vh * 0.65), Color(0.10, 0.07, 0.07))
	draw_rect(Rect2(cx + aw * 0.5, 0, vw - (cx + aw * 0.5), vh * 0.65), Color(0.10, 0.07, 0.07))

	# arch interior gradient — dark purple, not pure black
	var grad_steps: int = 24
	for g in range(grad_steps):
		var gt: float  = float(g) / float(grad_steps)
		var gc: Color  = Color(0.05, 0.03, 0.12).lerp(Color(0.01, 0.01, 0.04), gt)
		var gy0: float = arch_top + gt * ah
		var gy1: float = arch_top + (gt + 1.0 / float(grad_steps)) * ah
		draw_rect(Rect2(cx - aw * 0.5, gy0, aw, gy1 - gy0 + 1), gc)

	# torch glow halos on arch walls
	draw_circle(Vector2(cx - aw * 0.5 + 36, arch_top + ah * 0.32), 70, Color(0.65, 0.35, 0.05, 0.16))
	draw_circle(Vector2(cx + aw * 0.5 - 36, arch_top + ah * 0.32), 70, Color(0.65, 0.35, 0.05, 0.16))

	# lintel stones
	var stone_col: Color = Color(0.25, 0.20, 0.18)
	var dark_col:  Color = Color(0.15, 0.11, 0.10)
	var stone_h:   float = 14.0
	var stone_w:   float = 36.0
	for i in range(int(aw / stone_w) + 1):
		var sx: float = cx - aw * 0.5 + i * stone_w
		var sc: Color = stone_col if (i % 2 == 0) else dark_col
		draw_rect(Rect2(sx, arch_top - stone_h, stone_w - 1, stone_h), sc)

	# pillars
	var pill_w: float = 28.0
	draw_rect(Rect2(cx - aw * 0.5 - pill_w, arch_top, pill_w, ah), Color(0.20, 0.16, 0.14))
	draw_rect(Rect2(cx + aw * 0.5,           arch_top, pill_w, ah), Color(0.20, 0.16, 0.14))

	# wall torches on pillars
	_draw_combat_torch(Vector2(cx - aw * 0.5 - pill_w * 0.5, arch_top + ah * 0.26))
	_draw_combat_torch(Vector2(cx + aw * 0.5 + pill_w * 0.5, arch_top + ah * 0.26))

	# inner arch (depth illusion)
	var iw: float    = aw * 0.52
	var ih: float    = ah * 0.62
	var it: float    = arch_top + ah * 0.20
	for g in range(grad_steps):
		var gt: float  = float(g) / float(grad_steps)
		var gc: Color  = Color(0.02, 0.01, 0.07).lerp(Color(0.005, 0.005, 0.015), gt)
		var gy0: float = it + gt * ih
		var gy1: float = it + (gt + 1.0 / float(grad_steps)) * ih
		draw_rect(Rect2(cx - iw * 0.5, gy0, iw, gy1 - gy0 + 1), gc)
	for i in range(int(iw / stone_w) + 1):
		var sx: float = cx - iw * 0.5 + i * stone_w
		var sc: Color = Color(0.18, 0.14, 0.12) if (i % 2 == 0) else Color(0.12, 0.09, 0.08)
		draw_rect(Rect2(sx, it - 10, stone_w - 1, 10), sc)

func _draw_combat_torch(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x - 3, pos.y, 6, 14), Color(0.28, 0.20, 0.12))
	draw_circle(pos + Vector2(0, -2),  10, Color(0.65, 0.20, 0.04, 0.85))
	draw_circle(pos + Vector2(0, -6),   7, Color(0.92, 0.52, 0.06, 0.92))
	draw_circle(pos + Vector2(0, -10),  4, Color(1.00, 0.88, 0.40, 0.96))
	draw_circle(pos + Vector2(0, -13),  2, Color(1.00, 1.00, 0.85))
	draw_circle(pos + Vector2(0, -6),  28, Color(0.75, 0.40, 0.05, 0.10))

# ── UI ────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp: Vector2 = get_viewport().size
	var vw: float   = vp.x
	var vh: float   = vp.y

	var canvas := CanvasLayer.new()
	add_child(canvas)

	# ── enemy row — centered in arch ──────────────────────────────────────
	var enemy_y:   float = vh * 0.10
	var enemy_h:   float = vh * 0.46
	var n_enemies: int   = _enemies.size()
	var slot_w:    float = (vw * 0.56) / max(n_enemies, 1)
	var start_x:   float = vw * 0.22

	for i in range(n_enemies):
		var enemy: EnemyData = _enemies[i]
		var cx: float = start_x + slot_w * i + slot_w * 0.5

		var ep := Control.new()
		ep.position            = Vector2(cx - 100, enemy_y)
		ep.custom_minimum_size = Vector2(200, enemy_h)
		canvas.add_child(ep)

		# ground shadow ellipse under sprite
		var shadow_node := _GroundShadow.new()
		shadow_node.position = Vector2(100, enemy_h * 0.58 + 10)
		ep.add_child(shadow_node)

		# enemy sprite — larger scale
		var sprite_node := _EnemySprite.new()
		sprite_node.enemy_type  = enemy.enemy_type
		sprite_node.is_boss     = enemy.is_boss
		sprite_node.scale       = Vector2(1.35, 1.35)
		sprite_node.position    = Vector2(100, enemy_h * 0.30)   # lower in panel
		ep.add_child(sprite_node)

		# name label
		var ename := Label.new()
		ename.text = enemy.enemy_name
		ename.position = Vector2(0, enemy_h * 0.62)
		ename.custom_minimum_size = Vector2(200, 22)
		ename.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ename.add_theme_color_override("font_color",
				Color(1, 0.30, 0.30) if enemy.is_boss else Color(1, 0.65, 0.20))
		ename.add_theme_font_size_override("font_size", 16)
		ep.add_child(ename)

		# HP bar
		var bar := ProgressBar.new()
		bar.max_value       = enemy.max_hp
		bar.value           = enemy.hp
		bar.show_percentage = false
		bar.position        = Vector2(10, enemy_h * 0.62 + 26)
		bar.custom_minimum_size = Vector2(180, 14)
		_style_bar(bar, Color(0.15, 0.7, 0.25))
		ep.add_child(bar)

		var hp_lbl := Label.new()
		hp_lbl.text     = "HP %d/%d" % [enemy.hp, enemy.max_hp]
		hp_lbl.position = Vector2(0, enemy_h * 0.62 + 44)
		hp_lbl.custom_minimum_size = Vector2(200, 18)
		hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_lbl.add_theme_font_size_override("font_size", 11)
		hp_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		ep.add_child(hp_lbl)

		_enemy_nodes.append({"panel": ep, "hp_lbl": hp_lbl, "enemy": enemy})
		_enemy_hp_bars.append(bar)

	# ── phase / turn label ────────────────────────────────────────────────
	_lbl_phaser = Label.new()
	_lbl_phaser.text = "YOUR TURN"
	_lbl_phaser.position = Vector2(vw * 0.5 - 110, vh * 0.60)
	_lbl_phaser.custom_minimum_size = Vector2(220, 28)
	_lbl_phaser.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_phaser.add_theme_font_size_override("font_size", 16)
	_lbl_phaser.add_theme_color_override("font_color", Color(0.45, 1.0, 0.45))
	canvas.add_child(_lbl_phaser)

	# ── player stat panel (bottom-left) ──────────────────────────────────
	var plr_panel := PanelContainer.new()
	plr_panel.position = Vector2(10, vh * 0.645)
	plr_panel.custom_minimum_size = Vector2(210, 130)
	_style_panel(plr_panel, Color(0.06, 0.06, 0.14, 0.92))
	canvas.add_child(plr_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	plr_panel.add_child(pv)

	var plbl := Label.new()
	plbl.text = "%s  [%s]" % [_player.player_class.capitalize(), _player.get_class_weapon()]
	plbl.add_theme_font_size_override("font_size", 14)
	plbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	pv.add_child(plbl)

	var lv_lbl := Label.new()
	lv_lbl.text = "Level %d" % _player.level
	lv_lbl.add_theme_font_size_override("font_size", 12)
	lv_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	pv.add_child(lv_lbl)

	_lbl_plr_hp = Label.new()
	_lbl_plr_hp.add_theme_font_size_override("font_size", 13)
	pv.add_child(_lbl_plr_hp)

	# HP bar
	var hp_bar := ProgressBar.new()
	hp_bar.max_value       = _player.max_hp
	hp_bar.value           = _player.hp
	hp_bar.name            = "PlayerHPBar"
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(190, 12)
	_style_bar(hp_bar, Color(0.15, 0.75, 0.25))
	pv.add_child(hp_bar)

	_lbl_plr_mp = Label.new()
	_lbl_plr_mp.add_theme_font_size_override("font_size", 13)
	pv.add_child(_lbl_plr_mp)

	# MP bar
	var mp_bar := ProgressBar.new()
	mp_bar.max_value       = _player.max_mp
	mp_bar.value           = _player.mp
	mp_bar.name            = "PlayerMPBar"
	mp_bar.show_percentage = false
	mp_bar.custom_minimum_size = Vector2(190, 12)
	_style_bar(mp_bar, Color(0.25, 0.45, 1.0))
	pv.add_child(mp_bar)

	_refresh_player_ui()

	# ── combat log (bottom-center) ────────────────────────────────────────
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(230, vh * 0.645)
	log_panel.custom_minimum_size = Vector2(vw * 0.43, 130)
	_style_panel(log_panel, Color(0.04, 0.04, 0.10, 0.92))
	canvas.add_child(log_panel)

	_lbl_log = Label.new()
	_lbl_log.text = ""
	_lbl_log.add_theme_font_size_override("font_size", 12)
	_lbl_log.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	_lbl_log.custom_minimum_size = Vector2(vw * 0.41, 125)
	_lbl_log.add_theme_color_override("font_color", Color(0.88, 0.88, 0.80))
	log_panel.add_child(_lbl_log)

	# ── action buttons (bottom-right) ─────────────────────────────────────
	var btn_col := VBoxContainer.new()
	btn_col.position = Vector2(vw - 155, vh * 0.645)
	btn_col.add_theme_constant_override("separation", 8)
	canvas.add_child(btn_col)

	_btn_attack = _make_btn("⚔  ATTACK",  Color(0.95, 0.35, 0.35))
	_btn_magic  = _make_btn("✦  MAGIC",   Color(0.50, 0.65, 1.00))
	_btn_defend = _make_btn("🛡  DEFEND",  Color(0.40, 0.85, 0.40))
	btn_col.add_child(_btn_attack)
	btn_col.add_child(_btn_magic)
	btn_col.add_child(_btn_defend)

	_btn_attack.pressed.connect(_on_attack)
	_btn_magic.pressed.connect(_on_magic)
	_btn_defend.pressed.connect(_on_defend)

# ── style helpers ─────────────────────────────────────────────────────────────
func _make_btn(lbl: String, col: Color) -> Button:
	var b := Button.new()
	b.text = lbl
	b.custom_minimum_size = Vector2(140, 38)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", col)

	var sbn := StyleBoxFlat.new()
	sbn.bg_color    = Color(0.08, 0.08, 0.16)
	sbn.border_width_left   = 2; sbn.border_width_right  = 2
	sbn.border_width_top    = 2; sbn.border_width_bottom  = 2
	sbn.border_color = col * 0.7
	sbn.corner_radius_top_left     = 4; sbn.corner_radius_top_right    = 4
	sbn.corner_radius_bottom_left  = 4; sbn.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", sbn)

	var sbh := StyleBoxFlat.new()
	sbh.bg_color    = Color(0.14, 0.14, 0.26)
	sbh.border_width_left   = 2; sbh.border_width_right  = 2
	sbh.border_width_top    = 2; sbh.border_width_bottom  = 2
	sbh.border_color = col
	sbh.corner_radius_top_left     = 4; sbh.corner_radius_top_right    = 4
	sbh.corner_radius_bottom_left  = 4; sbh.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("hover",   sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	b.add_theme_stylebox_override("disabled", sbn)
	return b

func _style_panel(p: PanelContainer, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left   = 1; sb.border_width_right  = 1
	sb.border_width_top    = 1; sb.border_width_bottom  = 1
	sb.border_color = Color(0.35, 0.30, 0.50, 0.8)
	sb.corner_radius_top_left     = 4; sb.corner_radius_top_right    = 4
	sb.corner_radius_bottom_left  = 4; sb.corner_radius_bottom_right = 4
	p.add_theme_stylebox_override("panel", sb)

func _style_bar(bar: ProgressBar, col: Color) -> void:
	var sbfill := StyleBoxFlat.new()
	sbfill.bg_color = col
	bar.add_theme_stylebox_override("fill", sbfill)

	var sbbg := StyleBoxFlat.new()
	sbbg.bg_color = Color(0.08, 0.08, 0.12)
	bar.add_theme_stylebox_override("background", sbbg)

func _refresh_player_ui() -> void:
	_lbl_plr_hp.text = "HP  %d / %d" % [_player.hp, _player.max_hp]
	_lbl_plr_mp.text = "MP  %d / %d" % [_player.mp, _player.max_mp]

	# update HP bar colour: green→yellow→red based on ratio
	var hp_bar := _find_bar("PlayerHPBar")
	if hp_bar:
		hp_bar.value = _player.hp
		var ratio: float = float(_player.hp) / float(_player.max_hp)
		var bar_col: Color
		if ratio > 0.5:
			bar_col = Color(0.15, 0.75, 0.25).lerp(Color(0.85, 0.75, 0.10), (1.0 - ratio) * 2.0)
		else:
			bar_col = Color(0.85, 0.75, 0.10).lerp(Color(0.85, 0.20, 0.15), (0.5 - ratio) * 2.0)
		_style_bar(hp_bar, bar_col)

	var mp_bar := _find_bar("PlayerMPBar")
	if mp_bar:
		mp_bar.value = _player.mp

func _find_bar(bar_name: String) -> ProgressBar:
	# walk the tree to find the named bar
	return _find_node_by_name(self, bar_name) as ProgressBar

func _find_node_by_name(node: Node, target: String) -> Node:
	if node.name == target: return node
	for c in node.get_children():
		var found := _find_node_by_name(c, target)
		if found: return found
	return null

# ── actions ───────────────────────────────────────────────────────────────────
func _on_attack() -> void:
	if not _player_turn or _combat_over: return
	_set_buttons(false)

	var target: EnemyData = _first_living_enemy()
	if target == null: return

	var is_crit: bool = randf() < _player.crit_chance
	var dmg: int = _player.attack
	if is_crit: dmg = int(dmg * 2.0)
	var dealt: int = target.take_damage(dmg, false)

	var msg: String = "You strike with your %s for %d damage!" % [_player.get_class_weapon(), dealt]
	if is_crit: msg += "  CRITICAL HIT!"
	_log(msg)
	_refresh_enemies()

	if _all_enemies_dead():
		_begin_victory()
		return
	_do_enemy_turn()

func _on_magic() -> void:
	if not _player_turn or _combat_over: return
	var mp_cost: int = 10
	if _player.mp < mp_cost:
		_log("Not enough MP!")
		_set_buttons(true)
		return
	_set_buttons(false)
	_player.mp -= mp_cost

	var target: EnemyData = _first_living_enemy()
	if target == null: return

	var dmg: int  = int(_player.magic_power * 1.5)
	var dealt: int = target.take_damage(dmg, true)

	var hint: String = ""
	if target.enemy_type == EnemyData.EnemyType.SKELETON:
		hint = "  [Skeleton's bones crack — magic is effective!]"
	_log("You cast a spell for %d magic damage!%s" % [dealt, hint])
	_refresh_enemies()

	if _all_enemies_dead():
		_begin_victory()
		return
	_do_enemy_turn()

func _on_defend() -> void:
	if not _player_turn or _combat_over: return
	_set_buttons(false)
	_defending = true
	_log("You brace yourself! Incoming damage halved this turn.")
	_do_enemy_turn()

# ── pure bool victory check ───────────────────────────────────────────────────
func _all_enemies_dead() -> bool:
	for e: EnemyData in _enemies:
		if not e.is_dead(): return false
	return true

# ── async victory handler ─────────────────────────────────────────────────────
func _begin_victory() -> void:
	_combat_over = true
	_set_buttons(false)

	var total_gold: int = 0
	var total_exp:  int = 0
	for e: EnemyData in _enemies:
		total_gold += e.gold_drop
		total_exp  += e.exp_drop
	_player.gold += total_gold
	var levelled: bool = _player.gain_exp(total_exp)
	GameManager.add_combat_score(_enemies)

	var result: String = "Victory!  +%d gold  +%d exp" % [total_gold, total_exp]
	if levelled:
		result += "  ** LEVEL UP! Now Lv %d **" % _player.level
	_log(result)
	_lbl_phaser.text = "VICTORY!"
	_lbl_phaser.add_theme_color_override("font_color", Color(1, 0.9, 0.2))

	await get_tree().create_timer(2.0).timeout

	if GameManager.is_boss_fight:
		_log("Floor cleared! Descending deeper…")
		GameManager.next_floor()
		await get_tree().create_timer(1.0).timeout

	get_tree().change_scene_to_file("res://scenes/dungeon.tscn")

# ── async enemy turn ──────────────────────────────────────────────────────────
func _do_enemy_turn() -> void:
	_player_turn = false
	_lbl_phaser.text = "ENEMY TURN"
	_lbl_phaser.add_theme_color_override("font_color", Color(1, 0.3, 0.3))

	for enemy: EnemyData in _enemies:
		if enemy.is_dead(): continue

		var action: Dictionary = enemy.get_attack_action()
		var raw_dmg: int       = action["damage"]
		if _defending: raw_dmg = int(raw_dmg * 0.5)

		var taken: int  = _player.take_damage(raw_dmg, action["is_magic"])
		var line: String = "%s attacks for %d damage!" % [enemy.enemy_name, taken]

		if enemy.is_boss:
			line += "\n" + enemy.get_weakness_hint(action["type"])
		if enemy.enemy_type == EnemyData.EnemyType.ORC:
			if GameManager.rng.randi() % 2 == 0:
				line += "\n[The Orc is winding up — consider Defending!]"

		_log(line)
		_refresh_player_ui()

		if _player.is_dead():
			_combat_over = true
			_log("You have been defeated…")
			_lbl_phaser.text = "DEFEAT"
			_lbl_phaser.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
			await get_tree().create_timer(2.5).timeout
			get_tree().change_scene_to_file("res://scenes/game_over.tscn")
			return

	_defending   = false
	_player_turn = true
	_lbl_phaser.text = "YOUR TURN"
	_lbl_phaser.add_theme_color_override("font_color", Color(0.45, 1.0, 0.45))
	_set_buttons(true)

# ── helpers ───────────────────────────────────────────────────────────────────
func _first_living_enemy() -> EnemyData:
	for e: EnemyData in _enemies:
		if not e.is_dead(): return e
	return null

func _refresh_enemies() -> void:
	for i in range(_enemy_nodes.size()):
		var info:  Dictionary  = _enemy_nodes[i]
		var enemy: EnemyData   = info["enemy"]
		var bar:   ProgressBar = _enemy_hp_bars[i]
		bar.value = enemy.hp
		info["hp_lbl"].text = "HP %d/%d" % [enemy.hp, enemy.max_hp]
		if enemy.is_dead():
			info["panel"].modulate = Color(0.35, 0.35, 0.35, 0.7)

func _set_buttons(enabled: bool) -> void:
	print("_set_buttons called — enabled: ", enabled, " combat_over: ", _combat_over, " ai_thinking: ", _ai_thinking)
	_btn_attack.disabled = not enabled
	_btn_attack.disabled = not enabled
	_btn_magic.disabled  = not enabled
	_btn_defend.disabled = not enabled
	
	if enabled and AiBridge.ai_enabled and not _combat_over and not _ai_thinking:
		_ai_thinking = true
		var timer := Timer.new()
		timer.wait_time =0.3
		timer.one_shot = true
		timer.timeout.connect(_do_ai_combat_turn)
		add_child(timer)
		timer.start()
	
func _do_ai_combat_turn() -> void:
	_ai_thinking = false
	AiBridge.write_combat_state(_enemies,true,_defending)
	var action: String = AiBridge.read_action()
	
	match  action:
		"attack": _on_attack()
		"magic": _on_magic()
		"defend": _on_defend()
func _log(line: String) -> void:
	_log_lines.append(line)
	if _log_lines.size() > 6:
		_log_lines = _log_lines.slice(_log_lines.size() - 6)
	_lbl_log.text = "\n".join(_log_lines)


# ═════════════════════════════════════════════════════════════════════════════
# Inner class: procedurally drawn enemy sprite
# ═════════════════════════════════════════════════════════════════════════════
class _GroundShadow extends Node2D:
	func _draw() -> void:
		# Soft elliptical shadow cast on the ground beneath the enemy
		for i in range(4):
			var t: float = float(i) / 4.0
			var a: float = 0.22 - t * 0.18
			draw_ellipse_approx(60 - i * 10, 12 - i * 2, Color(0, 0, 0, a))

	func draw_ellipse_approx(rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var segs: int = 24
		for i in range(segs):
			var angle: float = float(i) / float(segs) * TAU
			pts.append(Vector2(cos(angle) * rx, sin(angle) * ry))
		draw_colored_polygon(pts, col)


class _EnemySprite extends Node2D:
	var enemy_type: int = 0
	var is_boss:    bool = false

	func _draw() -> void:
		match enemy_type:
			EnemyData.EnemyType.SLIME:    _draw_slime()
			EnemyData.EnemyType.SKELETON: _draw_skeleton()
			EnemyData.EnemyType.ORC:      _draw_orc()
			EnemyData.EnemyType.DEMON:    _draw_demon()
			_:                            _draw_slime()

	# ── Slime ─────────────────────────────────────────────────────────────
	func _draw_slime() -> void:
		var r: float = 36.0 if not is_boss else 48.0
		var bc: Color = Color(0.25, 0.75, 0.30)
		# body
		draw_circle(Vector2(0, 8), r, bc)
		draw_circle(Vector2(0, 8), r, Color(0.35, 0.90, 0.40))
		# highlight
		draw_circle(Vector2(-r * 0.3, 8 - r * 0.3), r * 0.35, Color(0.55, 1.0, 0.60, 0.5))
		# eyes
		draw_circle(Vector2(-10, 4), 5, Color(0.05, 0.05, 0.10))
		draw_circle(Vector2( 10, 4), 5, Color(0.05, 0.05, 0.10))
		draw_circle(Vector2(-10, 4), 2, Color(1, 1, 1))
		draw_circle(Vector2( 10, 4), 2, Color(1, 1, 1))
		# drip at bottom
		var drip := PackedVector2Array([
			Vector2(-8, r + 4), Vector2(0, r + 16), Vector2(8, r + 4)
		])
		draw_colored_polygon(drip, bc)

	# ── Skeleton ──────────────────────────────────────────────────────────
	func _draw_skeleton() -> void:
		var sc: float = 1.3 if is_boss else 1.0
		var bc: Color = Color(0.85, 0.82, 0.78)
		# skull
		draw_circle(Vector2(0, -28 * sc), 22 * sc, bc)
		# jaw
		var jaw := PackedVector2Array([
			Vector2(-14 * sc, -12 * sc), Vector2(14 * sc, -12 * sc),
			Vector2(12 * sc, 2 * sc),    Vector2(-12 * sc, 2 * sc)
		])
		draw_colored_polygon(jaw, bc)
		# eye sockets
		draw_circle(Vector2(-8 * sc, -32 * sc), 6 * sc, Color(0.05, 0.05, 0.12))
		draw_circle(Vector2( 8 * sc, -32 * sc), 6 * sc, Color(0.05, 0.05, 0.12))
		# spine
		for i in range(5):
			var y: float = 8 + i * 12
			draw_rect(Rect2(-4 * sc, y * sc, 8 * sc, 9 * sc), bc)
		# ribs
		for i in range(3):
			var ry: float = (12 + i * 10) * sc
			draw_line(Vector2(-4 * sc, ry), Vector2(-18 * sc, ry - 4 * sc), bc, 2.5)
			draw_line(Vector2( 4 * sc, ry), Vector2( 18 * sc, ry - 4 * sc), bc, 2.5)
		# arms
		draw_line(Vector2(-4 * sc, 12 * sc), Vector2(-26 * sc, 40 * sc), bc, 3.0)
		draw_line(Vector2( 4 * sc, 12 * sc), Vector2( 26 * sc, 40 * sc), bc, 3.0)
		# legs
		draw_line(Vector2(-4 * sc, 68 * sc), Vector2(-16 * sc, 98 * sc), bc, 3.5)
		draw_line(Vector2( 4 * sc, 68 * sc), Vector2( 16 * sc, 98 * sc), bc, 3.5)

	# ── Orc ───────────────────────────────────────────────────────────────
	func _draw_orc() -> void:
		var sc: float  = 1.35 if is_boss else 1.0
		var gc: Color  = Color(0.25, 0.50, 0.22)   # green body
		var dk: Color  = Color(0.15, 0.30, 0.12)   # dark shading
		# torso
		var torso := PackedVector2Array([
			Vector2(-30 * sc, 0), Vector2(30 * sc, 0),
			Vector2(36 * sc, 70 * sc), Vector2(-36 * sc, 70 * sc)
		])
		draw_colored_polygon(torso, gc)
		# head
		draw_circle(Vector2(0, -22 * sc), 26 * sc, gc)
		# brow ridge
		draw_line(Vector2(-20 * sc, -32 * sc), Vector2(20 * sc, -32 * sc), dk, 5.0)
		# eyes (red)
		draw_circle(Vector2(-9 * sc, -26 * sc), 5 * sc, Color(0.85, 0.15, 0.10))
		draw_circle(Vector2( 9 * sc, -26 * sc), 5 * sc, Color(0.85, 0.15, 0.10))
		# tusks
		draw_line(Vector2(-8 * sc, -8 * sc), Vector2(-10 * sc, 4 * sc), Color(0.90, 0.88, 0.75), 4.0)
		draw_line(Vector2( 8 * sc, -8 * sc), Vector2( 10 * sc, 4 * sc), Color(0.90, 0.88, 0.75), 4.0)
		# arms
		draw_line(Vector2(-30 * sc, 10 * sc), Vector2(-50 * sc, 55 * sc), gc, 14.0 * sc)
		draw_line(Vector2( 30 * sc, 10 * sc), Vector2( 50 * sc, 55 * sc), gc, 14.0 * sc)
		# club (right hand)
		draw_rect(Rect2(44 * sc, 40 * sc, 10 * sc, 40 * sc), Color(0.40, 0.28, 0.15))
		draw_circle(Vector2(49 * sc, 40 * sc), 12 * sc, Color(0.35, 0.24, 0.12))
		# legs
		draw_rect(Rect2(-26 * sc, 70 * sc, 22 * sc, 30 * sc), dk)
		draw_rect(Rect2(  4 * sc, 70 * sc, 22 * sc, 30 * sc), dk)

	# ── Demon Lord ────────────────────────────────────────────────────────
	func _draw_demon() -> void:
		var sc: float  = 1.4 if is_boss else 1.0
		var rc: Color  = Color(0.65, 0.08, 0.08)   # deep red body
		var dk: Color  = Color(0.35, 0.04, 0.04)
		# wings (behind body)
		var wl := PackedVector2Array([
			Vector2(-30 * sc, 0), Vector2(-90 * sc, -60 * sc),
			Vector2(-70 * sc, 30 * sc), Vector2(-30 * sc, 50 * sc)
		])
		var wr := PackedVector2Array([
			Vector2(30 * sc, 0), Vector2(90 * sc, -60 * sc),
			Vector2(70 * sc, 30 * sc), Vector2(30 * sc, 50 * sc)
		])
		draw_colored_polygon(wl, Color(0.20, 0.04, 0.04))
		draw_colored_polygon(wr, Color(0.20, 0.04, 0.04))
		# torso
		var torso := PackedVector2Array([
			Vector2(-28 * sc, 0), Vector2(28 * sc, 0),
			Vector2(32 * sc, 65 * sc), Vector2(-32 * sc, 65 * sc)
		])
		draw_colored_polygon(torso, rc)
		# head
		draw_circle(Vector2(0, -24 * sc), 24 * sc, rc)
		# horns
		var hl := PackedVector2Array([
			Vector2(-18 * sc, -44 * sc), Vector2(-28 * sc, -80 * sc), Vector2(-8 * sc, -46 * sc)
		])
		var hr := PackedVector2Array([
			Vector2( 18 * sc, -44 * sc), Vector2( 28 * sc, -80 * sc), Vector2( 8 * sc, -46 * sc)
		])
		draw_colored_polygon(hl, dk)
		draw_colored_polygon(hr, dk)
		# glowing eyes
		draw_circle(Vector2(-9 * sc, -26 * sc), 6 * sc, Color(1.0, 0.80, 0.10))
		draw_circle(Vector2( 9 * sc, -26 * sc), 6 * sc, Color(1.0, 0.80, 0.10))
		draw_circle(Vector2(-9 * sc, -26 * sc), 3 * sc, Color(1.0, 1.0, 0.6))
		draw_circle(Vector2( 9 * sc, -26 * sc), 3 * sc, Color(1.0, 1.0, 0.6))
		# arms
		draw_line(Vector2(-28 * sc, 8 * sc), Vector2(-52 * sc, 50 * sc), rc, 12.0 * sc)
		draw_line(Vector2( 28 * sc, 8 * sc), Vector2( 52 * sc, 50 * sc), rc, 12.0 * sc)
		# claw tips
		for i in range(3):
			var angle: float = (-0.4 + i * 0.4) * PI
			var tip: Vector2 = Vector2(-52 * sc, 50 * sc) + Vector2(cos(angle), sin(angle)) * 14 * sc
			draw_line(Vector2(-52 * sc, 50 * sc), tip, Color(0.85, 0.05, 0.05), 2.5)
			tip = Vector2(52 * sc, 50 * sc) + Vector2(-cos(angle), sin(angle)) * 14 * sc
			draw_line(Vector2(52 * sc, 50 * sc), tip, Color(0.85, 0.05, 0.05), 2.5)
		# aura ring
		draw_arc(Vector2(0, 0), 55 * sc, 0, TAU, 40, Color(0.9, 0.3, 0.1, 0.35), 6.0)
