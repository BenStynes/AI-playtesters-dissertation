extends Node2D

const C_BG_TOP := Color(0.04, 0.02, 0.10)
const C_BG_BOT := Color(0.08, 0.04, 0.04)
const C_FLOOR  := Color(0.12, 0.08, 0.06)
const C_STONE  := Color(0.22, 0.18, 0.16)

var _defeated: bool = false   # true = died, false = escaped

func _ready() -> void:
	var p: PlayerData = GameManager.player
	_defeated = (p == null or p.is_dead())
	var _won =(p != null and not p.is_dead() and GameManager.is_boss_fight == false)
	var final_score: int = GameManager.calculate_final_score() if p != null else 0

	var vp: Vector2 = get_viewport().size
	var vw: float   = vp.x
	var vh: float   = vp.y

	var canvas := CanvasLayer.new()
	add_child(canvas)
	if AiBridge.ai_training:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		RenderingServer.set_render_loop_enabled(false)
	# ── Outcome header ────────────────────────────────────────────────────
	var header := Label.new()
	if _defeated:
		header.text = "DEFEATED"
		header.add_theme_color_override("font_color", Color(0.90, 0.20, 0.20))
	elif _won:
		header.text = "VICTORY!!"
		header.add_theme_color_override("font_color", Color(0.90, 0.20, 0.20))
	else:
		header.text = "ESCAPED!"
		header.add_theme_color_override("font_color", Color(1.00, 0.85, 0.20))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(vw * 0.5 - 240, vh * 0.10)
	header.custom_minimum_size = Vector2(480, 70)
	header.add_theme_font_size_override("font_size", 56)
	canvas.add_child(header)

	# subtitle
	var sub := Label.new()
	sub.text = "Your run has ended." if _defeated else "You live to fight another day."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(vw * 0.5 - 280, vh * 0.26)
	sub.custom_minimum_size = Vector2(560, 28)
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.65, 0.60, 0.55))
	canvas.add_child(sub)

	# ── Stats panel ───────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.position = Vector2(vw * 0.5 - 200, vh * 0.33)
	panel.custom_minimum_size = Vector2(400, 220)
	_style_panel(panel)
	canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	if p != null:
		
		var elapsed: float = (Time.get_ticks_msec() / 1000.0) - GameManager.game_start_time
		var mins: int = int(elapsed) / 60
		var secs: int = int(elapsed) % 60

		_add_row(vbox, "Class",         p.player_class.capitalize())
		_add_row(vbox, "Floor Reached", "B%d" % GameManager.current_floor)
		_add_row(vbox, "Floors Cleared",str(GameManager.floors_cleared))
		_add_row(vbox, "Enemies Slain", str(GameManager.kills))
		_add_row(vbox, "Gold Carried",  "%d G" % p.gold)
		_add_row(vbox, "Level",         "Lv %d" % p.level)
		_add_row(vbox, "Time",          "%02d:%02d" % [mins, secs])

		# divider
		var div := ColorRect.new()
		div.color = Color(0.35, 0.30, 0.50, 0.6)
		div.custom_minimum_size = Vector2(380, 1)
		vbox.add_child(div)

		# final score — big
		var score_row := HBoxContainer.new()
		vbox.add_child(score_row)
		var slbl := Label.new()
		slbl.text = "FINAL SCORE"
		slbl.custom_minimum_size = Vector2(200, 30)
		slbl.add_theme_font_size_override("font_size", 17)
		slbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.75))
		score_row.add_child(slbl)
		var sval := Label.new()
		sval.text = "%d" % final_score
		sval.add_theme_font_size_override("font_size", 20)
		sval.add_theme_color_override("font_color", Color(1.00, 0.85, 0.20))
		score_row.add_child(sval)

	# ── Buttons ───────────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	btn_row.position = Vector2(vw * 0.5 - 200, vh * 0.85)
	btn_row.custom_minimum_size = Vector2(400, 46)
	canvas.add_child(btn_row)

	var retry_btn := _make_btn("PLAY AGAIN", Color(0.40, 0.85, 0.40))
	var menu_btn  := _make_btn("MAIN MENU",  Color(0.65, 0.65, 0.65))
	btn_row.add_child(retry_btn)
	btn_row.add_child(menu_btn)

	retry_btn.pressed.connect(func() -> void:
		if AiBridge.ai_enabled:
			GameManager.start_new_game(GameManager.ai_class, GameManager.current_seed)
			get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/class_select.tscn"))
		
	menu_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://Main.tscn"))
		
		
	if AiBridge.ai_enabled:
		var timer := Timer.new()
		timer.wait_time = 0.2
		timer.timeout.connect(_check_for_ai_action)
		add_child(timer)
		timer.start()
func _check_for_ai_action() -> void:
	if not FileAccess.file_exists(AiBridge.ACTION_FILE):
		return
	OS.delay_msec(100)
	var file := FileAccess.open(AiBridge.ACTION_FILE, FileAccess.READ)
	if not file: return
	
	var text : String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	
	if parsed and parsed.get("ready") == true:
		DirAccess.remove_absolute(AiBridge.ACTION_FILE)
		var action:String = parsed.get("action","replay")
		var seed_value: int = parsed.get("seed",0)
		if seed_value == 0:
			seed_value = randi()
		if action =="quit":
			get_tree().quit()
		else:
			GameManager.start_new_game(GameManager.ai_class,seed_value)
			get_tree().change_scene_to_file("res://scenes/dungeon.tscn")
func _add_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(200, 22)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.65))
	row.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	row.add_child(val)

func _make_btn(lbl: String, col: Color) -> Button:
	var b := Button.new()
	b.text = lbl
	b.custom_minimum_size = Vector2(160, 44)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", col)

	var sbn := StyleBoxFlat.new()
	sbn.bg_color     = Color(0.07, 0.07, 0.14)
	sbn.border_width_left = 2; sbn.border_width_right  = 2
	sbn.border_width_top  = 2; sbn.border_width_bottom = 2
	sbn.border_color  = col * 0.65
	sbn.corner_radius_top_left    = 4; sbn.corner_radius_top_right    = 4
	sbn.corner_radius_bottom_left = 4; sbn.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("normal", sbn)

	var sbh := StyleBoxFlat.new()
	sbh.bg_color     = col * 0.20
	sbh.border_width_left = 2; sbh.border_width_right  = 2
	sbh.border_width_top  = 2; sbh.border_width_bottom = 2
	sbh.border_color  = col
	sbh.corner_radius_top_left    = 4; sbh.corner_radius_top_right    = 4
	sbh.corner_radius_bottom_left = 4; sbh.corner_radius_bottom_right = 4
	b.add_theme_stylebox_override("hover",   sbh)
	b.add_theme_stylebox_override("pressed", sbh)
	return b

func _style_panel(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color  = Color(0.07, 0.06, 0.14, 0.95)
	sb.border_width_left = 1; sb.border_width_right  = 1
	sb.border_width_top  = 1; sb.border_width_bottom = 1
	sb.border_color = Color(0.35, 0.30, 0.50, 0.8)
	sb.corner_radius_top_left    = 5; sb.corner_radius_top_right    = 5
	sb.corner_radius_bottom_left = 5; sb.corner_radius_bottom_right = 5
	p.add_theme_stylebox_override("panel", sb)

func _draw() -> void:
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y

	var steps: int = 40
	for i in range(steps):
		var t: float   = float(i) / float(steps)
		var col: Color = C_BG_TOP.lerp(C_BG_BOT, t)
		var y0: float  = t * vh * 0.62
		var y1: float  = (t + 1.0 / float(steps)) * vh * 0.62
		draw_rect(Rect2(0, y0, vw, y1 - y0 + 1), col)

	draw_rect(Rect2(0, vh * 0.62, vw, vh * 0.38), C_FLOOR)
	var tile_w: float = 64.0; var tile_h: float = 32.0
	var rows: int = int(vh * 0.38 / tile_h) + 2
	var cols: int = int(vw / tile_w) + 2
	for r in range(rows):
		for c in range(cols):
			var ox: float = (tile_w * 0.5) if (r % 2 == 1) else 0.0
			var tx: float = c * tile_w - ox
			var ty: float = vh * 0.62 + r * tile_h
			var shade: float = 0.55 + 0.1 * ((r + c) % 2)
			draw_rect(Rect2(tx + 1, ty + 1, tile_w - 2, tile_h - 2), C_STONE * shade)

	# Red overlay tint for defeat
	if _defeated:
		draw_rect(Rect2(0, 0, vw, vh), Color(0.35, 0.02, 0.02, 0.22))
